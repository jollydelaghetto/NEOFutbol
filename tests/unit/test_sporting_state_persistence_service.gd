extends SceneTree

const Service = preload("res://game/scripts/services/sporting_state_persistence_service.gd")
const Progression = preload("res://game/scripts/services/round_progression_service.gd")
const Correction = preload("res://game/scripts/services/match_result_correction_service.gd")
const Standings = preload("res://game/scripts/services/standings_service.gd")
const Generator = preload("res://game/scripts/services/league_calendar_generator.gd")
const Club = preload("res://game/scripts/data/club_season.gd")
const Fixture = preload("res://game/scripts/data/match_fixture.gd")
const Result = preload("res://game/scripts/data/match_result.gd")
const Rules = preload("res://game/scripts/data/competition_rules.gd")

const TEST_PREFIX = "user://neofutbol/sporting_state/persistence_phase1_"

var failures: Array[String] = []
var checks = 0
var created_paths: Array[String] = []


func _initialize() -> void:
	var service = Service.new()
	_cleanup_known_paths()
	var clubs: Array[Club] = [
		_club("club_a"), _club("club_b"), _club("club_c"), _club("club_d")
	]
	var fixtures = _fixtures(2)
	var results: Array[Result] = [
		_result("fixture_03", Result.Status.FINAL, 0, 1),
		_result("fixture_02", Result.Status.PENDING, null, null),
		_result("fixture_01", Result.Status.FINAL, 2, 0),
	]
	var rules = _rules(3, 2)
	var selection = _selection()
	var audit: Array[Dictionary] = [_audit("correction-1", "fixture_01", 1, 0, 2, 0,
		"Acta final rectificada")]
	var snapshots = {
		"clubs": _snapshot_clubs(clubs),
		"fixtures": _snapshot_fixtures(fixtures),
		"results": _snapshot_results(results),
		"audit": audit.duplicate(true),
		"rules": _snapshot_rules(rules),
		"selection": selection.duplicate(true),
	}

	var base_path = _path("base")
	var saved = service.save_state(
		base_path, clubs, fixtures, results, audit, rules, selection
	)
	_check(saved.ok and saved.errors.is_empty(), "guarda una competición")
	if not saved.ok:
		_finish()
		return
	_check(saved.data.schema_version == 1 and saved.data.path == base_path,
		"informa esquema y ruta")
	_check(saved.data.payload_hash is String and saved.data.payload_hash.length() == 64,
		"informa hash SHA-256")
	var loaded = service.load_state(base_path, clubs, fixtures, rules, selection)
	_check(loaded.ok and loaded.errors.is_empty(), "recupera una competición")
	if not loaded.ok:
		_finish()
		return
	_check(loaded.data.schema_version == 1, "recupera schema_version")
	_check(loaded.data.results.size() == 3, "no exige resultados para todo el calendario")
	_check(_find_result(loaded.data.results, "fixture_01").status == Result.Status.FINAL
		and _find_result(loaded.data.results, "fixture_01").home_goals == 2,
		"recupera resultado finalizado")
	_check(_find_result(loaded.data.results, "fixture_02").status == Result.Status.PENDING
		and _find_result(loaded.data.results, "fixture_02").home_goals == null
		and _find_result(loaded.data.results, "fixture_02").away_goals == null,
		"recupera resultado pendiente con null explícito")
	_check(_result_ids(loaded.data.results) == ["fixture_01", "fixture_02", "fixture_03"],
		"recupera resultados en orden determinista")
	_check(loaded.data.audit_entries.size() == 1
		and loaded.data.audit_entries[0] == audit[0], "recupera auditoría de rectificación")
	var original_table = Standings.new().calculate(
		clubs, fixtures, results, rules, selection
	)
	_check(original_table.ok and loaded.data.standings == original_table.data,
		"clasificación recuperada idéntica a la original")
	_check(_all_new_objects(loaded.data.results, results),
		"resultados reconstruidos como objetos independientes")
	loaded.data.results[0].home_goals = 99
	loaded.data.audit_entries[0].reason = "Alterado después de cargar"
	_check(results[2].home_goals == 2 and audit[0].reason == "Acta final rectificada",
		"mutar la carga no altera las entradas originales")

	var correction_service = Correction.new()
	var first_request = _correction(
		"history-a", "fixture_01", 2, 0, 1, 1, "Primera rectificación"
	)
	var first_correction = correction_service.correct_results(
		clubs, fixtures, results, [first_request], rules, selection
	)
	_check(first_correction.ok, "MatchResultCorrectionService produce primera auditoría")
	var second_request = _correction(
		"history-b", "fixture_01", 1, 1, 0, 2, "Segunda rectificación"
	)
	var second_correction = correction_service.correct_results(
		clubs, fixtures, first_correction.data.results, [second_request], rules, selection
	)
	_check(second_correction.ok, "produce rectificación sucesiva")
	var accumulated_audit: Array[Dictionary] = [
		second_correction.data.audit_entries[0], first_correction.data.audit_entries[0]
	]
	var history_path = _path("history")
	var history_save = service.save_state(
		history_path, clubs, fixtures, second_correction.data.results,
		accumulated_audit, rules, selection
	)
	_check(history_save.ok, "guarda varias rectificaciones sucesivas")
	var history_load = service.load_state(history_path, clubs, fixtures, rules, selection)
	_check(history_load.ok and history_load.data.audit_entries.size() == 2,
		"recupera historial acumulado")
	if history_load.ok:
		_check(history_load.data.audit_entries[0].correction_id == "history-a"
			and history_load.data.audit_entries[1].correction_id == "history-b",
			"reconstruye la cadena histórica en orden")
		_check(history_load.data.audit_entries[0].after
			== history_load.data.audit_entries[1].before,
			"after de una rectificación coincide con before de la siguiente")
		_check(history_load.data.audit_entries[1].after.home_goals == 0
			and history_load.data.audit_entries[1].after.away_goals == 2
			and _find_result(history_load.data.results, "fixture_01").home_goals == 0
			and _find_result(history_load.data.results, "fixture_01").away_goals == 2,
			"último after coincide con el resultado actual")

	var incoherent: Array[Dictionary] = accumulated_audit.duplicate(true)
	incoherent[0].before.home_goals = 9
	_expect_error(service.save_state(_path("bad_audit"), clubs, fixtures,
		second_correction.data.results, incoherent, rules, selection),
		"incoherent_audit_history")
	var duplicate_audit: Array[Dictionary] = accumulated_audit.duplicate(true)
	duplicate_audit[0].correction_id = duplicate_audit[1].correction_id
	_expect_error(service.save_state(_path("duplicate_audit"), clubs, fixtures,
		second_correction.data.results, duplicate_audit, rules, selection),
		"duplicate_correction_id")

	var corrupt_json_path = _copy_path(base_path, "corrupt_json")
	_write_raw(corrupt_json_path, "{not json")
	_expect_error(service.load_state(corrupt_json_path, clubs, fixtures, rules, selection),
		"malformed_json")
	var missing_field_path = _mutated_copy(base_path, "missing_field", service,
		func(document): document.erase("results"), false)
	_expect_error(service.load_state(missing_field_path, clubs, fixtures, rules, selection),
		"missing_field")
	var unknown_field_path = _mutated_copy(base_path, "unknown_field", service,
		func(document): document["unexpected"] = true, false)
	_expect_error(service.load_state(unknown_field_path, clubs, fixtures, rules, selection),
		"unknown_field")
	var version_path = _mutated_copy(base_path, "version", service,
		func(document): document.schema_version = 2, false)
	_expect_error(service.load_state(version_path, clubs, fixtures, rules, selection),
		"unsupported_schema_version")
	var hash_path = _mutated_copy(base_path, "hash", service,
		func(document): document.results[0].home_goals = 7, false)
	_expect_error(service.load_state(hash_path, clubs, fixtures, rules, selection),
		"payload_hash_mismatch")
	var rules_hash_path = _mutated_copy(base_path, "rules_hash", service,
		func(document): document.rules_fingerprint = "0".repeat(64), true)
	_expect_error(service.load_state(rules_hash_path, clubs, fixtures, rules, selection),
		"rules_fingerprint_mismatch")
	var fixtures_hash_path = _mutated_copy(base_path, "fixtures_hash", service,
		func(document): document.fixtures_fingerprint = "0".repeat(64), true)
	_expect_error(service.load_state(fixtures_hash_path, clubs, fixtures, rules, selection),
		"fixtures_fingerprint_mismatch")

	for field_and_value in [
		["season_id", "season_b"],
		["competition_id", "cup"],
		["stage_id", "second_stage"],
		["group_id", "group_b"],
	]:
		var field: String = field_and_value[0]
		var value: String = field_and_value[1]
		var selection_path = _mutated_copy(base_path,
			"selection_" + field, service,
			func(document): document.selection[field] = value, true)
		_expect_error(service.load_state(
			selection_path, clubs, fixtures, rules, selection
		), "selection_mismatch")

	var duplicate_result_path = _mutated_copy(base_path, "duplicate_result", service,
		func(document): document.results.append(document.results[0].duplicate(true)), true)
	_expect_error(service.load_state(
		duplicate_result_path, clubs, fixtures, rules, selection
	), "duplicate_result")
	var invalid_score_path = _mutated_copy(base_path, "invalid_score", service,
		func(document): document.results[0].home_goals = -1, true)
	_expect_error(service.load_state(
		invalid_score_path, clubs, fixtures, rules, selection
	), "invalid_score")
	var invalid_status_path = _mutated_copy(base_path, "invalid_status", service,
		func(document): document.results[0].status = 99, true)
	_expect_error(service.load_state(
		invalid_status_path, clubs, fixtures, rules, selection
	), "invalid_status")

	_expect_error(service.load_state(_path("missing"), clubs, fixtures, rules, selection),
		"file_not_found")
	_expect_error(service.save_state("user://outside.json", clubs, fixtures,
		results, audit, rules, selection), "unsafe_path")
	_expect_error(service.load_state("/tmp/outside.json", clubs, fixtures,
		rules, selection), "unsafe_path")
	_expect_error(service.save_state(
		"user://neofutbol/sporting_state/../escape.json",
		clubs, fixtures, results, audit, rules, selection
	), "unsafe_path")

	var protected_path = _path("protected")
	var initial_protected = service.save_state(
		protected_path, clubs, fixtures, results, audit, rules, selection
	)
	_check(initial_protected.ok, "prepara archivo anterior para fallo de escritura")
	var previous_content = _read_raw(protected_path)
	var temp_directory = protected_path + ".tmp"
	DirAccess.remove_absolute(temp_directory)
	var make_temp_directory = DirAccess.make_dir_absolute(temp_directory)
	_check(make_temp_directory == OK, "prepara bloqueo sintético del temporal")
	var changed_results: Array[Result] = []
	for result in results:
		changed_results.append(_copy_result(result))
	changed_results[0].home_goals = 1
	changed_results[0].away_goals = 0
	var changed_audit: Array[Dictionary] = [_audit(
		"correction-1", "fixture_01", 1, 0, 2, 0, "Acta final rectificada"
	)]
	_expect_error(service.save_state(protected_path, clubs, fixtures,
		changed_results, changed_audit, rules, selection), "write_error")
	_check(_read_raw(protected_path) == previous_content,
		"conserva archivo previo ante fallo de escritura")
	DirAccess.remove_absolute(temp_directory)

	var stale_temp_path = _path("stale_temp")
	_write_raw(stale_temp_path + ".tmp", "temporal corrupto")
	var stale_temp_save = service.save_state(
		stale_temp_path, clubs, fixtures, results, audit, rules, selection
	)
	_check(stale_temp_save.ok, "sobrescribe y valida un temporal corrupto preexistente")
	_check(service.load_state(stale_temp_path, clubs, fixtures, rules, selection).ok,
		"archivo publicado tras temporal corrupto es válido")

	var backup_path = _path("backup")
	var backup_first = service.save_state(
		backup_path, clubs, fixtures, results, audit, rules, selection
	)
	_check(backup_first.ok, "primer guardado para respaldo")
	var backup_first_content = _read_raw(backup_path)
	var backup_second = service.save_state(
		backup_path, clubs, fixtures, second_correction.data.results,
		accumulated_audit, rules, selection
	)
	_check(backup_second.ok and backup_second.data.backup_path == backup_path + ".bak",
		"segundo guardado conserva respaldo")
	_check(_read_raw(backup_path + ".bak") == backup_first_content,
		"respaldo contiene el estado válido anterior")
	_write_raw(backup_path, "{corrupt main")
	var corrupt_main = service.load_state(backup_path, clubs, fixtures, rules, selection)
	_check(not corrupt_main.ok and corrupt_main.data == null,
		"no recupera silenciosamente el archivo principal corrupto")
	_check(corrupt_main.errors[0].get("backup_available") == true
		and corrupt_main.errors[0].get("backup_path") == backup_path + ".bak",
		"expone respaldo válido para recuperación explícita")
	var explicit_backup = service.load_state(
		backup_path + ".bak", clubs, fixtures, rules, selection
	)
	_check(explicit_backup.ok
		and _result_ids(explicit_backup.data.results)
			== ["fixture_01", "fixture_02", "fixture_03"]
		and _find_result(explicit_backup.data.results, "fixture_01").home_goals == 2,
		"permite cargar explícitamente el respaldo sin sustituir el principal")

	var permuted_results: Array[Result] = results.duplicate()
	permuted_results.reverse()
	var canonical_audit: Array[Dictionary] = accumulated_audit.duplicate(true)
	var permuted_audit: Array[Dictionary] = accumulated_audit.duplicate(true)
	permuted_audit.reverse()
	var serial_a_path = _path("serialization_a")
	var serial_b_path = _path("serialization_b")
	var serial_a = service.save_state(serial_a_path, clubs, fixtures,
		second_correction.data.results, canonical_audit, rules, selection)
	var serial_b_results: Array[Result] = second_correction.data.results.duplicate()
	serial_b_results.reverse()
	var serial_b = service.save_state(serial_b_path, clubs, fixtures,
		serial_b_results, permuted_audit, rules, selection)
	_check(serial_a.ok and serial_b.ok, "guarda permutaciones equivalentes")
	_check(_read_raw(serial_a_path) == _read_raw(serial_b_path),
		"serialización y hash iguales ante permutaciones")

	var round_results: Array[Result] = [
		_result("fixture_01", Result.Status.FINAL, 2, 0),
		_result("fixture_02", Result.Status.FINAL, 1, 1),
	]
	var progressed = Progression.new().apply_round(
		clubs, fixtures, [], round_results, rules, selection, 1
	)
	_check(progressed.ok, "RoundProgressionService produce estado persistible")
	if progressed.ok:
		var progression_path = _path("progression")
		var progression_save = service.save_state(
			progression_path, clubs, fixtures, progressed.data.results,
			[], rules, selection
		)
		var progression_load = service.load_state(
			progression_path, clubs, fixtures, rules, selection
		)
		_check(progression_save.ok and progression_load.ok,
			"integra guardado y carga con RoundProgressionService")
		_check(progression_load.ok
			and progression_load.data.standings == progressed.data.standings,
			"conserva clasificación del avance de jornada")
	_check(history_save.ok and history_load.ok,
		"integra persistencia con MatchResultCorrectionService")

	for legs in [1, 2]:
		var generated = Generator.new().generate(clubs, {
			"format": "round_robin",
			"season_id": selection.season_id,
			"competition_id": selection.competition_id,
			"stage_id": selection.stage_id,
			"group_id": selection.group_id,
			"legs": legs,
		})
		_check(generated.ok, "genera calendario de %d vuelta(s)" % legs)
		if generated.ok:
			var generated_fixtures: Array[Fixture] = []
			for fixture in generated.data:
				generated_fixtures.append(fixture)
			var generated_results: Array[Result] = []
			for index in mini(2, generated_fixtures.size()):
				generated_results.append(_result(
					generated_fixtures[index].fixture_id, Result.Status.FINAL, index, 0
				))
			var generated_path = _path("legs_%d" % legs)
			var generated_rules = _rules(3, legs)
			var generated_save = service.save_state(
				generated_path, clubs, generated_fixtures, generated_results,
				[], generated_rules, selection
			)
			var generated_load = service.load_state(
				generated_path, clubs, generated_fixtures, generated_rules, selection
			)
			_check(generated_save.ok and generated_load.ok,
				"compatible con liga de %d vuelta(s)" % legs)

	var changed_rules = _rules(2, 2)
	_expect_error(service.load_state(base_path, clubs, fixtures,
		changed_rules, selection), "rules_fingerprint_mismatch")
	var changed_fixtures: Array[Fixture] = fixtures.duplicate()
	changed_fixtures[0] = _copy_fixture(fixtures[0])
	changed_fixtures[0].round_number = 99
	_expect_error(service.load_state(base_path, clubs, changed_fixtures,
		rules, selection), "fixtures_fingerprint_mismatch")

	_check(_snapshot_clubs(clubs) == snapshots.clubs, "clubes sin mutaciones")
	_check(_snapshot_fixtures(fixtures) == snapshots.fixtures, "fixtures sin mutaciones")
	_check(_snapshot_results(results) == snapshots.results, "resultados sin mutaciones")
	_check(audit == snapshots.audit, "auditoría de entrada sin mutaciones")
	_check(_snapshot_rules(rules) == snapshots.rules, "reglas sin mutaciones")
	_check(selection == snapshots.selection, "selección sin mutaciones")

	_finish()


func _club(club_id: String) -> Club:
	var club = Club.new()
	club.club_id = club_id
	club.season_id = "season_a"
	club.division_id = "synthetic_division"
	return club


func _fixtures(legs: int) -> Array[Fixture]:
	var fixtures: Array[Fixture] = [
		_fixture("fixture_01", "club_a", "club_b", 1),
		_fixture("fixture_02", "club_c", "club_d", 1),
		_fixture("fixture_03", "club_a", "club_c", 2),
		_fixture("fixture_04", "club_b", "club_d", 2),
		_fixture("fixture_05", "club_a", "club_d", 3),
		_fixture("fixture_06", "club_b", "club_c", 3),
	]
	if legs == 2:
		fixtures.append_array([
			_fixture("fixture_07", "club_b", "club_a", 4),
			_fixture("fixture_08", "club_d", "club_c", 4),
			_fixture("fixture_09", "club_c", "club_a", 5),
			_fixture("fixture_10", "club_d", "club_b", 5),
			_fixture("fixture_11", "club_d", "club_a", 6),
			_fixture("fixture_12", "club_c", "club_b", 6),
		])
	return fixtures


func _fixture(fixture_id: String, home_id: String, away_id: String,
		round_number: int) -> Fixture:
	var fixture = Fixture.new()
	fixture.fixture_id = fixture_id
	fixture.season_id = "season_a"
	fixture.competition_id = "league"
	fixture.stage_id = "regular"
	fixture.group_id = null
	fixture.home_club_id = home_id
	fixture.away_club_id = away_id
	fixture.round_number = round_number
	fixture.scheduled_date = null
	fixture.metadata = {"synthetic": true}
	return fixture


func _copy_fixture(source: Fixture) -> Fixture:
	var fixture = Fixture.new()
	fixture.fixture_id = source.fixture_id
	fixture.season_id = source.season_id
	fixture.competition_id = source.competition_id
	fixture.stage_id = source.stage_id
	fixture.group_id = source.group_id
	fixture.home_club_id = source.home_club_id
	fixture.away_club_id = source.away_club_id
	fixture.round_number = source.round_number
	fixture.scheduled_date = source.scheduled_date
	fixture.metadata = source.metadata.duplicate(true)
	return fixture


func _result(fixture_id: String, status: int, home_goals: Variant,
		away_goals: Variant) -> Result:
	var result = Result.new()
	result.fixture_id = fixture_id
	result.season_id = "season_a"
	result.status = status
	result.home_goals = home_goals
	result.away_goals = away_goals
	return result


func _copy_result(source: Result) -> Result:
	return _result(source.fixture_id, source.status, source.home_goals, source.away_goals)


func _audit(correction_id: String, fixture_id: String,
		before_home: int, before_away: int, after_home: int, after_away: int,
		reason: String) -> Dictionary:
	return {
		"correction_id": correction_id,
		"season_id": "season_a",
		"fixture_id": fixture_id,
		"reason": reason,
		"before": {
			"home_goals": before_home,
			"away_goals": before_away,
			"status": Result.Status.FINAL,
		},
		"after": {
			"home_goals": after_home,
			"away_goals": after_away,
			"status": Result.Status.FINAL,
		},
	}


func _correction(correction_id: String, fixture_id: String,
		expected_home: int, expected_away: int, new_home: int, new_away: int,
		reason: String) -> Dictionary:
	return {
		"season_id": "season_a",
		"fixture_id": fixture_id,
		"expected_home_goals": expected_home,
		"expected_away_goals": expected_away,
		"new_home_goals": new_home,
		"new_away_goals": new_away,
		"reason": reason,
		"correction_id": correction_id,
	}


func _rules(points_win: int, legs: int) -> Rules:
	var rules = Rules.new()
	rules.season_id = "season_a"
	rules.competition_id = "league"
	rules.points_win = points_win
	rules.points_draw = 1
	rules.points_loss = 0
	rules.team_count = 4
	rules.round_count = 3 * legs
	rules.tiebreakers = ["goal_difference", "goals_for", "wins"]
	rules.substitution_rules = null
	rules.promotion_relegation_rules = null
	rules.competition_format = {
		"kind": "round_robin",
		"legs": legs,
		"head_to_head_policy": "single_pass",
	}
	return rules


func _selection() -> Dictionary:
	return {
		"season_id": "season_a",
		"competition_id": "league",
		"stage_id": "regular",
		"group_id": null,
	}


func _path(name: String) -> String:
	var path = TEST_PREFIX + name + ".json"
	if path not in created_paths:
		created_paths.append(path)
	return path


func _copy_path(source: String, name: String) -> String:
	var target = _path(name)
	DirAccess.copy_absolute(source, target)
	return target


func _mutated_copy(source: String, name: String, service: Service,
		mutator: Callable, rehash: bool) -> String:
	var target = _copy_path(source, name)
	var parser = JSON.new()
	parser.parse(_read_raw(target))
	var document: Dictionary = service._normalize_json_numbers(parser.data)
	mutator.call(document)
	if rehash:
		var unhashed = document.duplicate(true)
		unhashed.erase("payload_hash")
		document.payload_hash = service._hash_value(unhashed)
	_write_raw(target, JSON.stringify(document, "", true, true))
	return target


func _write_raw(path: String, content: String) -> void:
	if path.begins_with(TEST_PREFIX) and path not in created_paths:
		created_paths.append(path)
	DirAccess.make_dir_recursive_absolute(Service.SAVE_ROOT)
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(content)
		file = null


func _read_raw(path: String) -> String:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var content = file.get_as_text()
	file = null
	return content


func _cleanup_known_paths() -> void:
	DirAccess.make_dir_recursive_absolute(Service.SAVE_ROOT)
	var directory = DirAccess.open(Service.SAVE_ROOT)
	if directory == null:
		return
	for filename in directory.get_files():
		if filename.begins_with("persistence_phase1_"):
			directory.remove(filename)
	for dirname in directory.get_directories():
		if dirname.begins_with("persistence_phase1_"):
			directory.remove(dirname)


func _cleanup_created_paths() -> void:
	for path in created_paths:
		for suffix in ["", ".tmp", ".bak", ".bak.tmp"]:
			DirAccess.remove_absolute(path + suffix)


func _find_result(results: Array, fixture_id: String) -> Result:
	for result in results:
		if result.fixture_id == fixture_id:
			return result
	return null


func _result_ids(results: Array) -> Array[String]:
	var ids: Array[String] = []
	for result in results:
		ids.append(result.fixture_id)
	return ids


func _all_new_objects(output: Array, input: Array[Result]) -> bool:
	for output_result in output:
		for input_result in input:
			if output_result == input_result:
				return false
	return true


func _snapshot_clubs(clubs: Array[Club]) -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for club in clubs:
		snapshot.append({
			"club_id": club.club_id,
			"season_id": club.season_id,
			"division_id": club.division_id,
		})
	return snapshot


func _snapshot_fixtures(fixtures: Array[Fixture]) -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for fixture in fixtures:
		snapshot.append({
			"fixture_id": fixture.fixture_id,
			"season_id": fixture.season_id,
			"competition_id": fixture.competition_id,
			"stage_id": fixture.stage_id,
			"group_id": fixture.group_id,
			"home_club_id": fixture.home_club_id,
			"away_club_id": fixture.away_club_id,
			"round_number": fixture.round_number,
			"scheduled_date": fixture.scheduled_date,
			"metadata": fixture.metadata.duplicate(true),
		})
	return snapshot


func _snapshot_results(results: Array) -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for result in results:
		snapshot.append({
			"fixture_id": result.fixture_id,
			"season_id": result.season_id,
			"home_goals": result.home_goals,
			"away_goals": result.away_goals,
			"status": result.status,
		})
	return snapshot


func _snapshot_rules(rules: Rules) -> Dictionary:
	return {
		"season_id": rules.season_id,
		"competition_id": rules.competition_id,
		"points_win": rules.points_win,
		"points_draw": rules.points_draw,
		"points_loss": rules.points_loss,
		"team_count": rules.team_count,
		"round_count": rules.round_count,
		"tiebreakers": rules.tiebreakers.duplicate(true),
		"substitution_rules": rules.substitution_rules,
		"promotion_relegation_rules": rules.promotion_relegation_rules,
		"competition_format": rules.competition_format.duplicate(true),
	}


func _expect_error(result: Dictionary, code: String) -> void:
	_check(not result.ok and result.data == null, "fallo atómico " + code)
	_check(result.errors.size() == 1, "un diagnóstico " + code)
	if not result.errors.is_empty():
		_check(result.errors[0].get("code") == code, "código " + code)
		_check(result.errors[0].get("message") is String
			and not result.errors[0].message.is_empty(), "mensaje " + code)


func _finish() -> void:
	_cleanup_created_paths()
	if failures.is_empty():
		print("PASS: %d comprobaciones" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
