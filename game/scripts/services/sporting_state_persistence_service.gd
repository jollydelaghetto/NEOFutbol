class_name SportingStatePersistenceService
extends RefCounted

const Club = preload("res://game/scripts/data/club_season.gd")
const Fixture = preload("res://game/scripts/data/match_fixture.gd")
const MatchResultModel = preload("res://game/scripts/data/match_result.gd")
const Rules = preload("res://game/scripts/data/competition_rules.gd")
const Standings = preload("res://game/scripts/services/standings_service.gd")

const SCHEMA_VERSION = 1
const SAVE_ROOT = "user://neofutbol/sporting_state/"
const MAX_FILE_SIZE = 8 * 1024 * 1024
const MAX_SAFE_JSON_INTEGER = 9007199254740991.0
const DOCUMENT_FIELDS = [
	"schema_version",
	"selection",
	"rules_fingerprint",
	"fixtures_fingerprint",
	"results",
	"audit_entries",
	"payload_hash",
]
const SELECTION_FIELDS = ["season_id", "competition_id", "stage_id", "group_id"]
const RESULT_FIELDS = ["season_id", "fixture_id", "status", "home_goals", "away_goals"]
const AUDIT_FIELDS = [
	"correction_id", "season_id", "fixture_id", "reason", "before", "after",
]
const SCORE_FIELDS = ["home_goals", "away_goals", "status"]

## Esquema JSON v1:
## schema_version, selection, rules_fingerprint, fixtures_fingerprint, results,
## audit_entries y payload_hash. Las huellas y payload_hash son SHA-256 sobre
## JSON canónico UTF-8 con claves ordenadas y precisión numérica completa.
##
## El guardado valida el estado, escribe y relee un temporal en el mismo
## directorio, conserva el destino válido anterior como .bak y después renombra
## el temporal sobre el destino. Esta estrategia evita borrar primero la partida,
## pero no promete atomicidad frente a caídas del sistema en todas las plataformas.
## El hash detecta alteraciones accidentales; no autentica a un atacante capaz de
## reescribir el documento y recalcularlo.
func save_state(path: String, clubs: Array[Club], fixtures: Array[Fixture],
		results: Array[MatchResultModel], audit_entries: Array[Dictionary],
		rules: Rules, selection: Dictionary) -> Dictionary:
	var path_error = _validate_path(path, false)
	if path_error != null:
		return path_error
	var prepared = _prepare_state(clubs, fixtures, results, audit_entries, rules, selection)
	if not prepared.ok:
		return prepared
	var document = {
		"schema_version": SCHEMA_VERSION,
		"selection": _selection_document(selection),
		"rules_fingerprint": _rules_fingerprint(rules),
		"fixtures_fingerprint": _fixtures_fingerprint(fixtures, selection),
		"results": prepared.data.results,
		"audit_entries": prepared.data.audit_entries,
	}
	document["payload_hash"] = _hash_value(document)
	var encoded = _canonical_json(document)
	if encoded.to_utf8_buffer().size() > MAX_FILE_SIZE:
		return _failure("state_too_large", "El estado supera el tamaño máximo admitido.")

	var directory_error = DirAccess.make_dir_recursive_absolute(SAVE_ROOT)
	if directory_error != OK:
		return _io_failure("directory_error",
			"No se pudo preparar el directorio de guardado.", directory_error, path)
	var temporary_path = path + ".tmp"
	var write_result = _write_text(temporary_path, encoded)
	if not write_result.ok:
		return write_result
	var temporary_validation = _load_document_file(
		temporary_path, clubs, fixtures, rules, selection
	)
	if not temporary_validation.ok:
		var invalid_temporary = _failure("invalid_temporary_file",
			"El archivo temporal no superó la validación posterior a la escritura.")
		invalid_temporary.errors[0]["cause"] = temporary_validation.errors[0]
		invalid_temporary.errors[0]["path"] = temporary_path
		return invalid_temporary

	var backup_path = path + ".bak"
	var backup_updated = false
	if FileAccess.file_exists(path):
		var existing = _load_document_file(path, clubs, fixtures, rules, selection)
		if existing.ok:
			var backup_candidate = backup_path + ".tmp"
			var copy_error = DirAccess.copy_absolute(path, backup_candidate)
			if copy_error != OK:
				return _io_failure("backup_error",
					"No se pudo preparar el respaldo del estado anterior.", copy_error, path)
			var backup_validation = _load_document_file(
				backup_candidate, clubs, fixtures, rules, selection
			)
			if not backup_validation.ok:
				var invalid_backup = _failure("invalid_backup_candidate",
					"La copia de respaldo no superó su validación.")
				invalid_backup.errors[0]["cause"] = backup_validation.errors[0]
				return invalid_backup
			var backup_error = DirAccess.rename_absolute(backup_candidate, backup_path)
			if backup_error != OK:
				return _io_failure("backup_error",
					"No se pudo publicar el respaldo del estado anterior.", backup_error, path)
			backup_updated = true
	var replace_error = DirAccess.rename_absolute(temporary_path, path)
	if replace_error != OK:
		return _io_failure("replace_error",
			"No se pudo sustituir el estado deportivo anterior.", replace_error, path)
	return {
		"ok": true,
		"data": {
			"schema_version": SCHEMA_VERSION,
			"path": path,
			"backup_path": backup_path if backup_updated else null,
			"payload_hash": document.payload_hash,
		},
		"errors": [],
	}


func load_state(path: String, clubs: Array[Club], fixtures: Array[Fixture],
		rules: Rules, selection: Dictionary) -> Dictionary:
	var path_error = _validate_path(path, true)
	if path_error != null:
		return path_error
	var loaded = _load_document_file(path, clubs, fixtures, rules, selection)
	if loaded.ok:
		return loaded
	var backup_path = path + ".bak"
	if not path.ends_with(".bak") and FileAccess.file_exists(backup_path):
		var backup = _load_document_file(backup_path, clubs, fixtures, rules, selection)
		if backup.ok:
			loaded.errors[0]["backup_available"] = true
			loaded.errors[0]["backup_path"] = backup_path
	return loaded


func _prepare_state(clubs: Array[Club], fixtures: Array[Fixture],
		results: Array[MatchResultModel], audit_entries: Array[Dictionary],
		rules: Rules, selection: Dictionary) -> Dictionary:
	var standings = Standings.new().calculate(clubs, fixtures, results, rules, selection)
	if not standings.ok:
		return standings
	var result_documents: Array[Dictionary] = []
	var results_by_fixture: Dictionary = {}
	for match_result in results:
		var result_document = _result_document(match_result)
		result_documents.append(result_document)
		results_by_fixture[match_result.fixture_id] = result_document
	_sort_result_documents(result_documents)
	var audit_result = _validate_and_order_audit(
		audit_entries, fixtures, results_by_fixture, selection
	)
	if not audit_result.ok:
		return audit_result
	return {
		"ok": true,
		"data": {
			"results": result_documents,
			"audit_entries": audit_result.data,
			"standings": standings.data,
		},
		"errors": [],
	}


func _load_document_file(path: String, clubs: Array[Club], fixtures: Array[Fixture],
		rules: Rules, selection: Dictionary) -> Dictionary:
	var read_result = _read_text(path)
	if not read_result.ok:
		return read_result
	var parser = JSON.new()
	var parse_error = parser.parse(read_result.data)
	if parse_error != OK:
		var malformed = _failure("malformed_json", "El archivo no contiene JSON válido.")
		malformed.errors[0]["line"] = parser.get_error_line()
		malformed.errors[0]["detail"] = parser.get_error_message()
		return malformed
	if not parser.data is Dictionary:
		return _failure("invalid_document", "La raíz del archivo debe ser un objeto JSON.")
	var document: Dictionary = _normalize_json_numbers(parser.data)
	return _validate_document(document, clubs, fixtures, rules, selection)


func _validate_document(document: Dictionary, clubs: Array[Club],
		fixtures: Array[Fixture], rules: Rules, selection: Dictionary) -> Dictionary:
	var shape_error = _validate_exact_fields(document, DOCUMENT_FIELDS, "document")
	if shape_error != null:
		return shape_error
	if typeof(document.schema_version) != TYPE_INT:
		return _field_failure("invalid_schema_version",
			"schema_version debe ser un entero.", "schema_version")
	if document.schema_version != SCHEMA_VERSION:
		var incompatible = _field_failure("unsupported_schema_version",
			"La versión del esquema no está admitida.", "schema_version")
		incompatible.errors[0]["schema_version"] = document.schema_version
		return incompatible
	if not document.payload_hash is String or not _is_sha256(document.payload_hash):
		return _field_failure("invalid_payload_hash",
			"payload_hash debe ser una huella SHA-256 hexadecimal.", "payload_hash")
	var unhashed = document.duplicate(true)
	unhashed.erase("payload_hash")
	if not _constant_time_equal(document.payload_hash, _hash_value(unhashed)):
		return _field_failure("payload_hash_mismatch",
			"El contenido no coincide con su hash declarado.", "payload_hash")

	var selection_error = _validate_selection_document(document.selection)
	if selection_error != null:
		return selection_error
	var expected_selection = _selection_document(selection)
	for field in SELECTION_FIELDS:
		if document.selection[field] != expected_selection[field]:
			var mismatch = _field_failure("selection_mismatch",
				"El archivo pertenece a una selección deportiva diferente.",
				"selection." + field)
			mismatch.errors[0]["stored"] = document.selection[field]
			mismatch.errors[0]["expected"] = expected_selection[field]
			return mismatch
	if not document.rules_fingerprint is String \
			or not _is_sha256(document.rules_fingerprint):
		return _field_failure("invalid_rules_fingerprint",
			"rules_fingerprint debe ser una huella SHA-256 hexadecimal.",
			"rules_fingerprint")
	if not _constant_time_equal(document.rules_fingerprint, _rules_fingerprint(rules)):
		return _field_failure("rules_fingerprint_mismatch",
			"Las reglas actuales no coinciden con las del estado guardado.",
			"rules_fingerprint")
	if not document.fixtures_fingerprint is String \
			or not _is_sha256(document.fixtures_fingerprint):
		return _field_failure("invalid_fixtures_fingerprint",
			"fixtures_fingerprint debe ser una huella SHA-256 hexadecimal.",
			"fixtures_fingerprint")
	if not _constant_time_equal(
		document.fixtures_fingerprint, _fixtures_fingerprint(fixtures, selection)
	):
		return _field_failure("fixtures_fingerprint_mismatch",
			"El calendario actual no coincide con el del estado guardado.",
			"fixtures_fingerprint")
	if not document.results is Array:
		return _field_failure("invalid_results", "results debe ser un array.", "results")
	if not document.audit_entries is Array:
		return _field_failure("invalid_audit_entries",
			"audit_entries debe ser un array.", "audit_entries")

	var reconstructed: Array[MatchResultModel] = []
	for index in document.results.size():
		var item = document.results[index]
		if not item is Dictionary:
			return _indexed_failure("invalid_result_entry",
				"Cada resultado debe ser un objeto.", index, "results")
		var result_shape = _validate_exact_fields(item, RESULT_FIELDS, "results", index)
		if result_shape != null:
			return result_shape
		var result_error = _validate_result_document(item, index)
		if result_error != null:
			return result_error
		reconstructed.append(_reconstruct_result(item))

	var audit_documents: Array[Dictionary] = []
	for item in document.audit_entries:
		if not item is Dictionary:
			return _failure("invalid_audit_entry", "Cada auditoría debe ser un objeto.")
		audit_documents.append(item.duplicate(true))
	var prepared = _prepare_state(
		clubs, fixtures, reconstructed, audit_documents, rules, selection
	)
	if not prepared.ok:
		return prepared
	if prepared.data.results != document.results:
		return _failure("noncanonical_results",
			"Los resultados persistidos no están en el orden canónico.")
	if prepared.data.audit_entries != document.audit_entries:
		return _failure("noncanonical_audit",
			"La auditoría persistida no está en el orden canónico.")
	return {
		"ok": true,
		"data": {
			"results": reconstructed,
			"audit_entries": prepared.data.audit_entries.duplicate(true),
			"standings": prepared.data.standings,
			"schema_version": SCHEMA_VERSION,
		},
		"errors": [],
	}


func _validate_result_document(item: Dictionary, index: int) -> Variant:
	for field in ["season_id", "fixture_id"]:
		if not item[field] is String or item[field].strip_edges().is_empty():
			return _indexed_field_failure("invalid_result_field",
				"Los identificadores del resultado deben ser cadenas no vacías.",
				index, "results", field)
	if typeof(item.status) != TYPE_INT \
			or item.status not in [MatchResultModel.Status.PENDING, MatchResultModel.Status.FINAL]:
		return _indexed_field_failure("invalid_status",
			"El estado del resultado no está admitido.", index, "results", "status")
	if item.status == MatchResultModel.Status.PENDING:
		if item.home_goals != null or item.away_goals != null:
			return _indexed_failure("pending_with_score",
				"Un resultado pendiente debe conservar marcadores null.", index, "results")
		return null
	for field in ["home_goals", "away_goals"]:
		if typeof(item[field]) != TYPE_INT or item[field] < 0:
			return _indexed_field_failure("invalid_score",
				"Los marcadores finales deben ser enteros no negativos.",
				index, "results", field)
	return null


func _validate_and_order_audit(audit_entries: Array[Dictionary],
		fixtures: Array[Fixture], results_by_fixture: Dictionary,
		selection: Dictionary) -> Dictionary:
	var selected_fixtures: Dictionary = {}
	for fixture in fixtures:
		if _fixture_in_scope(fixture, selection):
			selected_fixtures[fixture.fixture_id] = fixture
	var seen_ids: Dictionary = {}
	var by_fixture: Dictionary = {}
	for index in audit_entries.size():
		var entry = audit_entries[index]
		var shape_error = _validate_exact_fields(entry, AUDIT_FIELDS, "audit_entries", index)
		if shape_error != null:
			return shape_error
		for field in ["correction_id", "season_id", "fixture_id", "reason"]:
			if not entry[field] is String or entry[field].strip_edges().is_empty():
				return _indexed_field_failure("invalid_audit_field",
					"La auditoría requiere identificadores y motivo no vacíos.",
					index, "audit_entries", field)
		if seen_ids.has(entry.correction_id):
			var duplicate = _indexed_failure("duplicate_correction_id",
				"El identificador de corrección está duplicado en la auditoría.",
				index, "audit_entries")
			duplicate.errors[0]["correction_id"] = entry.correction_id
			duplicate.errors[0]["first_index"] = seen_ids[entry.correction_id]
			return duplicate
		seen_ids[entry.correction_id] = index
		if entry.season_id != selection.season_id \
				or not selected_fixtures.has(entry.fixture_id):
			return _indexed_failure("audit_scope_mismatch",
				"La auditoría no corresponde a un partido de la selección.",
				index, "audit_entries")
		for field in ["before", "after"]:
			if not entry[field] is Dictionary:
				return _indexed_field_failure("invalid_audit_state",
					"Los estados de auditoría deben ser objetos.",
					index, "audit_entries", field)
			var state_shape = _validate_exact_fields(
				entry[field], SCORE_FIELDS, "audit_entries", index, field + "."
			)
			if state_shape != null:
				return state_shape
			if entry[field].status != MatchResultModel.Status.FINAL:
				return _indexed_field_failure("audit_state_not_final",
					"Los estados de auditoría deben estar finalizados.",
					index, "audit_entries", field + ".status")
			for score_field in ["home_goals", "away_goals"]:
				if typeof(entry[field][score_field]) != TYPE_INT \
						or entry[field][score_field] < 0:
					return _indexed_field_failure("invalid_audit_score",
						"Los marcadores de auditoría deben ser enteros no negativos.",
						index, "audit_entries", field + "." + score_field)
		if _same_score(entry.before, entry.after):
			return _indexed_failure("audit_without_change",
				"Una auditoría debe representar una rectificación efectiva.",
				index, "audit_entries")
		if not by_fixture.has(entry.fixture_id):
			by_fixture[entry.fixture_id] = []
		by_fixture[entry.fixture_id].append(entry.duplicate(true))

	var ordered: Array[Dictionary] = []
	var fixture_ids: Array[String] = []
	for fixture_id in by_fixture:
		fixture_ids.append(fixture_id)
	fixture_ids.sort()
	for fixture_id in fixture_ids:
		if not results_by_fixture.has(fixture_id):
			return _audit_failure("audit_without_result",
				"La auditoría no tiene un resultado actual asociado.", fixture_id)
		var current: Dictionary = results_by_fixture[fixture_id]
		if current.status != MatchResultModel.Status.FINAL:
			return _audit_failure("audit_result_not_final",
				"La auditoría requiere un resultado actual finalizado.", fixture_id)
		var remaining: Array = by_fixture[fixture_id].duplicate(true)
		var reverse_chain: Array[Dictionary] = []
		var expected = {
			"home_goals": current.home_goals,
			"away_goals": current.away_goals,
			"status": current.status,
		}
		while not remaining.is_empty():
			var candidates: Array[int] = []
			for index in remaining.size():
				if _same_score(remaining[index].after, expected):
					candidates.append(index)
			if candidates.size() != 1:
				return _audit_failure("incoherent_audit_history",
					"La cadena de rectificaciones es incompleta o ambigua.", fixture_id)
			var position = candidates[0]
			var entry: Dictionary = remaining[position]
			reverse_chain.append(entry)
			expected = entry.before
			remaining.remove_at(position)
		reverse_chain.reverse()
		for entry in reverse_chain:
			ordered.append(entry)
	return {"ok": true, "data": ordered, "errors": []}


func _result_document(match_result: MatchResultModel) -> Dictionary:
	return {
		"season_id": match_result.season_id,
		"fixture_id": match_result.fixture_id,
		"status": match_result.status,
		"home_goals": match_result.home_goals,
		"away_goals": match_result.away_goals,
	}


func _reconstruct_result(item: Dictionary) -> MatchResultModel:
	var result = MatchResultModel.new()
	result.season_id = item.season_id
	result.fixture_id = item.fixture_id
	result.status = item.status
	result.home_goals = item.home_goals
	result.away_goals = item.away_goals
	return result


func _selection_document(selection: Dictionary) -> Dictionary:
	var result = {}
	for field in SELECTION_FIELDS:
		result[field] = selection.get(field, null)
	return result


func _validate_selection_document(selection: Variant) -> Variant:
	if not selection is Dictionary:
		return _field_failure("invalid_selection", "selection debe ser un objeto.", "selection")
	var shape_error = _validate_exact_fields(selection, SELECTION_FIELDS, "selection")
	if shape_error != null:
		return shape_error
	for field in ["season_id", "competition_id"]:
		if not selection[field] is String or selection[field].strip_edges().is_empty():
			return _field_failure("invalid_selection",
				"La selección requiere identificadores no vacíos.", "selection." + field)
	for field in ["stage_id", "group_id"]:
		if selection[field] != null and (
			not selection[field] is String or selection[field].strip_edges().is_empty()
		):
			return _field_failure("invalid_selection",
				"Fase y grupo deben ser cadenas no vacías o null.", "selection." + field)
	return null


func _rules_fingerprint(rules: Rules) -> String:
	return _hash_value({
		"season_id": rules.season_id,
		"competition_id": rules.competition_id,
		"points_win": rules.points_win,
		"points_draw": rules.points_draw,
		"points_loss": rules.points_loss,
		"team_count": rules.team_count,
		"round_count": rules.round_count,
		"tiebreakers": _json_copy(rules.tiebreakers),
		"substitution_rules": _json_copy(rules.substitution_rules),
		"promotion_relegation_rules": _json_copy(rules.promotion_relegation_rules),
		"competition_format": _json_copy(rules.competition_format),
	})


func _fixtures_fingerprint(fixtures: Array[Fixture], selection: Dictionary) -> String:
	var documents: Array[Dictionary] = []
	for fixture in fixtures:
		if _fixture_in_scope(fixture, selection):
			documents.append({
				"fixture_id": fixture.fixture_id,
				"season_id": fixture.season_id,
				"competition_id": fixture.competition_id,
				"stage_id": fixture.stage_id,
				"group_id": fixture.group_id,
				"home_club_id": fixture.home_club_id,
				"away_club_id": fixture.away_club_id,
				"round_number": fixture.round_number,
				"scheduled_date": fixture.scheduled_date,
				"metadata": _json_copy(fixture.metadata),
			})
	documents.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if left.season_id != right.season_id:
			return left.season_id < right.season_id
		return left.fixture_id < right.fixture_id
	)
	return _hash_value(documents)


func _fixture_in_scope(fixture: Fixture, selection: Dictionary) -> bool:
	return fixture.season_id == selection.get("season_id") \
		and fixture.competition_id == selection.get("competition_id") \
		and fixture.stage_id == selection.get("stage_id") \
		and fixture.group_id == selection.get("group_id")


func _sort_result_documents(results: Array[Dictionary]) -> void:
	results.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if left.season_id != right.season_id:
			return left.season_id < right.season_id
		return left.fixture_id < right.fixture_id
	)


func _canonical_json(value: Variant) -> String:
	return JSON.stringify(value, "", true, true)


func _hash_value(value: Variant) -> String:
	var context = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(_canonical_json(value).to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()


func _json_copy(value: Variant) -> Variant:
	if value == null:
		return null
	var parser = JSON.new()
	if parser.parse(_canonical_json(value)) != OK:
		return null
	return _normalize_json_numbers(parser.data)


func _normalize_json_numbers(value: Variant) -> Variant:
	# JSON.parse representa todos los números como float. Solo se recuperan como
	# int los valores integrales dentro del rango exacto de IEEE-754; el resto se
	# conserva para que la validación de tipos lo rechace cuando corresponda.
	if value is Dictionary:
		for key in value.keys():
			value[key] = _normalize_json_numbers(value[key])
		return value
	if value is Array:
		for index in value.size():
			value[index] = _normalize_json_numbers(value[index])
		return value
	if typeof(value) == TYPE_FLOAT and is_finite(value) \
			and absf(value) <= MAX_SAFE_JSON_INTEGER and value == floor(value):
		return int(value)
	return value


func _same_score(left: Dictionary, right: Dictionary) -> bool:
	return left.home_goals == right.home_goals \
		and left.away_goals == right.away_goals \
		and left.status == right.status


func _is_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value:
		if character not in "0123456789abcdef":
			return false
	return true


func _constant_time_equal(left: String, right: String) -> bool:
	if left.length() != right.length():
		return false
	var difference = 0
	for index in left.length():
		difference |= left.unicode_at(index) ^ right.unicode_at(index)
	return difference == 0


func _validate_path(path: String, allow_backup: bool) -> Variant:
	if not path.begins_with(SAVE_ROOT):
		return _field_failure("unsafe_path",
			"La ruta debe pertenecer al directorio deportivo de user://.", "path")
	var filename = path.trim_prefix(SAVE_ROOT)
	var valid_extension = filename.ends_with(".json") \
		or (allow_backup and filename.ends_with(".json.bak"))
	if filename.is_empty() or not valid_extension \
			or filename.contains("/") or filename.contains("\\") \
			or filename.contains("..") or not filename.is_valid_filename():
		return _field_failure("unsafe_path",
			"La ruta debe identificar un archivo JSON directo y seguro.", "path")
	return null


func _write_text(path: String, content: String) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _io_failure("write_error", "No se pudo abrir el archivo temporal.",
			FileAccess.get_open_error(), path)
	var stored = file.store_string(content)
	file.flush()
	var file_error = file.get_error()
	file = null
	if not stored or file_error != OK:
		return _io_failure("write_error", "No se pudo escribir el archivo temporal.",
			file_error, path)
	return {"ok": true, "data": null, "errors": []}


func _read_text(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _io_failure("file_not_found", "El archivo deportivo no existe.",
			ERR_FILE_NOT_FOUND, path)
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _io_failure("read_error", "No se pudo abrir el archivo deportivo.",
			FileAccess.get_open_error(), path)
	var length = file.get_length()
	if length <= 0 or length > MAX_FILE_SIZE:
		file = null
		return _io_failure("invalid_file_size",
			"El tamaño del archivo deportivo no está admitido.", ERR_FILE_CORRUPT, path)
	var content = file.get_as_text()
	var file_error = file.get_error()
	file = null
	if file_error != OK:
		return _io_failure("read_error", "No se pudo leer el archivo deportivo.",
			file_error, path)
	return {"ok": true, "data": content, "errors": []}


func _validate_exact_fields(value: Dictionary, expected: Array,
		source: String, index: int = -1, prefix: String = "") -> Variant:
	for field in expected:
		if not value.has(field):
			var missing = _failure("missing_field", "Falta un campo obligatorio.")
			missing.errors[0]["source"] = source
			missing.errors[0]["field"] = prefix + field
			if index >= 0:
				missing.errors[0]["index"] = index
			return missing
	var unknown_fields: Array[String] = []
	for field in value:
		if not field is String or field not in expected:
			unknown_fields.append(str(field))
	if not unknown_fields.is_empty():
		unknown_fields.sort()
		var unknown = _failure("unknown_field", "El documento contiene un campo no admitido.")
		unknown.errors[0]["source"] = source
		unknown.errors[0]["field"] = prefix + unknown_fields[0]
		if index >= 0:
			unknown.errors[0]["index"] = index
		return unknown
	return null


func _field_failure(code: String, message: String, field: String) -> Dictionary:
	var result = _failure(code, message)
	result.errors[0]["field"] = field
	return result


func _indexed_failure(code: String, message: String, index: int,
		source: String) -> Dictionary:
	var result = _failure(code, message)
	result.errors[0]["index"] = index
	result.errors[0]["source"] = source
	return result


func _indexed_field_failure(code: String, message: String, index: int,
		source: String, field: String) -> Dictionary:
	var result = _indexed_failure(code, message, index, source)
	result.errors[0]["field"] = field
	return result


func _audit_failure(code: String, message: String, fixture_id: String) -> Dictionary:
	var result = _failure(code, message)
	result.errors[0]["source"] = "audit_entries"
	result.errors[0]["fixture_id"] = fixture_id
	return result


func _io_failure(code: String, message: String, error: int, path: String) -> Dictionary:
	var result = _failure(code, message)
	result.errors[0]["error"] = error
	result.errors[0]["path"] = path
	return result


func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "data": null, "errors": [{"code": code, "message": message}]}
