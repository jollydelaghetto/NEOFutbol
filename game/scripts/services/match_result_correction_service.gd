class_name MatchResultCorrectionService
extends RefCounted

const Club = preload("res://game/scripts/data/club_season.gd")
const Fixture = preload("res://game/scripts/data/match_fixture.gd")
const MatchResultModel = preload("res://game/scripts/data/match_result.gd")
const Rules = preload("res://game/scripts/data/competition_rules.gd")
const Standings = preload("res://game/scripts/services/standings_service.gd")
const REQUIRED_SELECTION = ["season_id", "competition_id", "stage_id", "group_id"]
const CORRECTION_FIELDS = [
	"season_id",
	"fixture_id",
	"expected_home_goals",
	"expected_away_goals",
	"new_home_goals",
	"new_away_goals",
	"reason",
	"correction_id",
]

## Rectifica resultados finales sobre copias independientes del estado conocido.
## Una petición posterior debe aportar un correction_id nuevo y un marcador
## esperado que coincida con el estado actualizado. La unicidad global de los
## identificadores requiere un registro persistente, fuera del alcance de esta fase.
func correct_results(clubs: Array[Club], fixtures: Array[Fixture],
		current_results: Array[MatchResultModel], corrections: Array[Dictionary],
		rules: Rules, selection: Dictionary) -> Dictionary:
	var selection_error = _validate_selection(selection)
	if selection_error != null:
		return selection_error

	var fixtures_by_season: Dictionary = {}
	for index in fixtures.size():
		var fixture = fixtures[index]
		if fixture.fixture_id.strip_edges().is_empty():
			return _fixture_failure("invalid_fixture",
				"El partido debe tener un identificador no vacío.", index, fixture)
		if not fixtures_by_season.has(fixture.season_id):
			fixtures_by_season[fixture.season_id] = {}
		var season_fixtures: Dictionary = fixtures_by_season[fixture.season_id]
		if season_fixtures.has(fixture.fixture_id):
			var duplicate = _fixture_failure("duplicate_fixture",
				"El identificador de partido está duplicado en la temporada.",
				index, fixture)
			duplicate.errors[0]["first_index"] = season_fixtures[fixture.fixture_id].index
			return duplicate
		season_fixtures[fixture.fixture_id] = {"fixture": fixture, "index": index}

	var current_by_fixture: Dictionary = {}
	for index in current_results.size():
		var match_result = current_results[index]
		var result_error = _validate_current_result(
			match_result, index, fixtures_by_season, selection
		)
		if result_error != null:
			return result_error
		if current_by_fixture.has(match_result.fixture_id):
			var duplicate_result = _result_failure("duplicate_current_result",
				"El estado actual contiene más de un resultado para el mismo partido.",
				index, match_result)
			duplicate_result.errors[0]["first_index"] = \
				current_by_fixture[match_result.fixture_id].index
			return duplicate_result
		current_by_fixture[match_result.fixture_id] = {
			"result": match_result,
			"index": index,
		}

	var seen_correction_ids: Dictionary = {}
	var corrections_by_fixture: Dictionary = {}
	for index in corrections.size():
		var correction = corrections[index]
		var correction_error = _validate_correction_shape(correction, index)
		if correction_error != null:
			return correction_error
		var correction_id: String = correction.correction_id
		if seen_correction_ids.has(correction_id):
			var duplicate_id = _correction_failure("duplicate_correction_id",
				"El identificador de corrección está duplicado en el lote.",
				index, correction)
			duplicate_id.errors[0]["first_index"] = seen_correction_ids[correction_id]
			return duplicate_id
		seen_correction_ids[correction_id] = index
		var fixture_id: String = correction.fixture_id
		if corrections_by_fixture.has(fixture_id):
			var duplicate_fixture_correction = _correction_failure(
				"duplicate_fixture_correction",
				"El lote contiene más de una rectificación para el mismo partido.",
				index, correction
			)
			duplicate_fixture_correction.errors[0]["first_index"] = \
				corrections_by_fixture[fixture_id].index
			return duplicate_fixture_correction
		corrections_by_fixture[fixture_id] = {"correction": correction, "index": index}

		if correction.season_id != selection.season_id:
			return _correction_failure("season_mismatch",
				"La corrección no pertenece a la temporada seleccionada.",
				index, correction)
		var season_fixtures: Dictionary = fixtures_by_season.get(correction.season_id, {})
		if not season_fixtures.has(fixture_id):
			return _correction_failure("unknown_fixture",
				"La corrección no corresponde a ningún partido identificado.",
				index, correction)
		var fixture: Fixture = season_fixtures[fixture_id].fixture
		if not _fixture_in_scope(fixture, selection):
			return _correction_failure("scope_mismatch",
				"El partido queda fuera de la selección exacta.", index, correction)
		if not current_by_fixture.has(fixture_id):
			return _correction_failure("missing_result",
				"El partido no tiene un resultado previo que rectificar.", index, correction)
		var current: MatchResultModel = current_by_fixture[fixture_id].result
		if current.status != MatchResultModel.Status.FINAL:
			return _correction_failure("result_not_final",
				"Solo pueden rectificarse resultados finalizados.", index, correction)
		if current.home_goals != correction.expected_home_goals \
				or current.away_goals != correction.expected_away_goals:
			return _correction_failure("stale_expected_score",
				"El marcador esperado no coincide con el estado actual.", index, correction)
		if current.home_goals == correction.new_home_goals \
				and current.away_goals == correction.new_away_goals:
			return _correction_failure("unchanged_score",
				"El nuevo marcador debe cambiar el resultado anterior.", index, correction)

	var next_by_fixture: Dictionary = {}
	for fixture_id in current_by_fixture:
		next_by_fixture[fixture_id] = _copy_result(current_by_fixture[fixture_id].result)
	var corrected_fixture_ids: Array[String] = []
	var audit_entries: Array[Dictionary] = []
	for fixture_id in corrections_by_fixture:
		var correction: Dictionary = corrections_by_fixture[fixture_id].correction
		var corrected: MatchResultModel = next_by_fixture[fixture_id]
		var before = _score_snapshot(corrected)
		corrected.home_goals = correction.new_home_goals
		corrected.away_goals = correction.new_away_goals
		var after = _score_snapshot(corrected)
		corrected_fixture_ids.append(fixture_id)
		audit_entries.append({
			"correction_id": correction.correction_id,
			"season_id": correction.season_id,
			"fixture_id": fixture_id,
			"reason": correction.reason,
			"before": before,
			"after": after,
		})
	corrected_fixture_ids.sort()
	_sort_audit_entries(audit_entries)

	var next_results: Array[MatchResultModel] = []
	for match_result in next_by_fixture.values():
		next_results.append(match_result)
	_sort_results(next_results)
	var standings = Standings.new().calculate(clubs, fixtures, next_results, rules, selection)
	if not standings.ok:
		return standings
	return {
		"ok": true,
		"data": {
			"results": next_results,
			"standings": standings.data,
			"corrected_fixture_ids": corrected_fixture_ids,
			"audit_entries": audit_entries,
		},
		"errors": [],
	}


func _validate_selection(selection: Dictionary) -> Variant:
	for field in REQUIRED_SELECTION:
		if not selection.has(field):
			var missing = _failure("missing_selection",
				"Falta un campo de selección obligatorio.")
			missing.errors[0]["field"] = field
			return missing
	for field in ["season_id", "competition_id"]:
		if not selection[field] is String or selection[field].strip_edges().is_empty():
			return _field_failure("invalid_selection",
				"La selección requiere identificadores no vacíos.", field)
	for field in ["stage_id", "group_id"]:
		if selection[field] != null and (
			not selection[field] is String or selection[field].strip_edges().is_empty()
		):
			return _field_failure("invalid_selection",
				"Fase y grupo deben ser cadenas no vacías o null.", field)
	return null


func _validate_current_result(match_result: MatchResultModel, index: int,
		fixtures_by_season: Dictionary, selection: Dictionary) -> Variant:
	if match_result.fixture_id.strip_edges().is_empty() \
			or match_result.season_id.strip_edges().is_empty():
		return _result_failure("invalid_result",
			"El resultado debe identificar partido y temporada.", index, match_result)
	if match_result.season_id != selection.season_id:
		return _result_failure("season_mismatch",
			"El resultado no pertenece a la temporada seleccionada.", index, match_result)
	var season_fixtures: Dictionary = fixtures_by_season.get(match_result.season_id, {})
	if not season_fixtures.has(match_result.fixture_id):
		return _result_failure("unknown_fixture",
			"El resultado no corresponde a ningún partido identificado.", index, match_result)
	var fixture: Fixture = season_fixtures[match_result.fixture_id].fixture
	if not _fixture_in_scope(fixture, selection):
		return _result_failure("scope_mismatch",
			"El partido del resultado queda fuera de la selección exacta.", index, match_result)
	if match_result.status not in [MatchResultModel.Status.PENDING, MatchResultModel.Status.FINAL]:
		return _result_failure("invalid_status",
			"El estado del resultado no está admitido.", index, match_result)
	if match_result.status == MatchResultModel.Status.PENDING:
		if match_result.home_goals != null or match_result.away_goals != null:
			return _result_failure("pending_with_score",
				"Un partido pendiente debe conservar ambos marcadores como null.",
				index, match_result)
		return null
	if match_result.home_goals == null or match_result.away_goals == null:
		return _result_failure("missing_score",
			"Un partido finalizado necesita ambos marcadores.", index, match_result)
	for field in ["home_goals", "away_goals"]:
		var goals = match_result.get(field)
		if typeof(goals) != TYPE_INT or goals < 0:
			var invalid = _result_failure("invalid_score",
				"Los marcadores deben ser enteros no negativos.", index, match_result)
			invalid.errors[0]["field"] = field
			return invalid
	return null


func _validate_correction_shape(correction: Dictionary, index: int) -> Variant:
	for field in CORRECTION_FIELDS:
		if not correction.has(field):
			var missing = _correction_failure("missing_correction_field",
				"Falta un campo obligatorio en la corrección.", index, correction)
			missing.errors[0]["field"] = field
			return missing
	for field in correction:
		if not field is String or field not in CORRECTION_FIELDS:
			var unknown = _correction_failure("unknown_correction_field",
				"La corrección contiene un campo no admitido.", index, correction)
			unknown.errors[0]["field"] = str(field)
			return unknown
	for field in ["season_id", "fixture_id", "reason", "correction_id"]:
		if not correction[field] is String:
			var invalid_text = _correction_failure("invalid_correction_field",
				"Los identificadores y el motivo deben ser cadenas.", index, correction)
			invalid_text.errors[0]["field"] = field
			return invalid_text
	for field in ["season_id", "fixture_id", "reason", "correction_id"]:
		if correction[field].strip_edges().is_empty():
			var code = "empty_correction_field"
			var message = "Los identificadores y el motivo no pueden estar vacíos."
			if field == "reason":
				code = "empty_reason"
				message = "La corrección requiere una justificación no vacía."
			elif field == "correction_id":
				code = "empty_correction_id"
				message = "La corrección requiere un identificador no vacío."
			var empty = _correction_failure(code, message, index, correction)
			empty.errors[0]["field"] = field
			return empty
	for field in [
		"expected_home_goals", "expected_away_goals",
		"new_home_goals", "new_away_goals",
	]:
		if typeof(correction[field]) != TYPE_INT or correction[field] < 0:
			var invalid_goals = _correction_failure("invalid_correction_score",
				"Los marcadores esperados y nuevos deben ser enteros no negativos.",
				index, correction)
			invalid_goals.errors[0]["field"] = field
			return invalid_goals
	return null


func _fixture_in_scope(fixture: Fixture, selection: Dictionary) -> bool:
	return fixture.season_id == selection.season_id \
		and fixture.competition_id == selection.competition_id \
		and fixture.stage_id == selection.stage_id \
		and fixture.group_id == selection.group_id


func _copy_result(source: MatchResultModel) -> MatchResultModel:
	var copy = MatchResultModel.new()
	copy.fixture_id = source.fixture_id
	copy.season_id = source.season_id
	copy.home_goals = source.home_goals
	copy.away_goals = source.away_goals
	copy.status = source.status
	return copy


func _score_snapshot(match_result: MatchResultModel) -> Dictionary:
	return {
		"home_goals": match_result.home_goals,
		"away_goals": match_result.away_goals,
		"status": match_result.status,
	}


func _sort_results(results: Array[MatchResultModel]) -> void:
	results.sort_custom(func(left: MatchResultModel, right: MatchResultModel) -> bool:
		if left.season_id != right.season_id:
			return left.season_id < right.season_id
		return left.fixture_id < right.fixture_id
	)


func _sort_audit_entries(entries: Array[Dictionary]) -> void:
	entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if left.season_id != right.season_id:
			return left.season_id < right.season_id
		if left.fixture_id != right.fixture_id:
			return left.fixture_id < right.fixture_id
		return left.correction_id < right.correction_id
	)


func _field_failure(code: String, message: String, field: String) -> Dictionary:
	var result = _failure(code, message)
	result.errors[0]["field"] = field
	return result


func _fixture_failure(code: String, message: String, index: int,
		fixture: Fixture) -> Dictionary:
	var result = _failure(code, message)
	result.errors[0]["index"] = index
	result.errors[0]["fixture_id"] = fixture.fixture_id
	result.errors[0]["season_id"] = fixture.season_id
	result.errors[0]["source"] = "fixtures"
	return result


func _result_failure(code: String, message: String, index: int,
		match_result: MatchResultModel) -> Dictionary:
	var result = _failure(code, message)
	result.errors[0]["index"] = index
	result.errors[0]["fixture_id"] = match_result.fixture_id
	result.errors[0]["season_id"] = match_result.season_id
	result.errors[0]["source"] = "current_results"
	return result


func _correction_failure(code: String, message: String, index: int,
		correction: Dictionary) -> Dictionary:
	var result = _failure(code, message)
	result.errors[0]["index"] = index
	result.errors[0]["source"] = "corrections"
	for field in ["correction_id", "fixture_id", "season_id"]:
		if correction.has(field):
			result.errors[0][field] = correction[field]
	return result


func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "data": null, "errors": [{"code": code, "message": message}]}
