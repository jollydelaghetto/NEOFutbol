extends SceneTree

const Controller = preload("res://game/scripts/services/season_controller.gd")
const Progression = preload("res://game/scripts/services/round_progression_service.gd")
const Correction = preload("res://game/scripts/services/match_result_correction_service.gd")
const Standings = preload("res://game/scripts/services/standings_service.gd")
const Persistence = preload("res://game/scripts/services/sporting_state_persistence_service.gd")
const Generator = preload("res://game/scripts/services/league_calendar_generator.gd")
const Club = preload("res://game/scripts/data/club_season.gd")
const Fixture = preload("res://game/scripts/data/match_fixture.gd")
const Result = preload("res://game/scripts/data/match_result.gd")
const Rules = preload("res://game/scripts/data/competition_rules.gd")

const TEST_PREFIX = "user://neofutbol/sporting_state/season_controller_phase1_"

var failures: Array[String] = []
var checks = 0
var created_paths: Array[String] = []


func _initialize() -> void:
	_cleanup_known_paths()
	_test_before_initialization()
	_test_invalid_initialization()

	var reference_clubs = _clubs()
	var reference_fixtures = _fixtures(2)
	var reference_rules = _rules(3, 2)
	var reference_selection = _selection()
	var source_clubs = _copy_clubs(reference_clubs)
	var source_fixtures = _copy_fixtures(reference_fixtures)
	var source_rules = _copy_rules(reference_rules)
	var source_selection = reference_selection.duplicate(true)
	var controller = Controller.new()
	var initialized = controller.initialize(
		source_clubs, source_fixtures, source_rules, source_selection
	)
	_check(initialized.ok and initialized.errors.is_empty(), "inicialización válida")
	_check(initialized.ok and initialized.data.result_count == 0
		and initialized.data.audit_entry_count == 0, "inicialización vacía")
	_check(initialized.ok and initialized.data.selection == reference_selection,
		"inicialización informa selección")
	var session_context = controller.get_session_context()
	_check(session_context.ok and session_context.data.selection == reference_selection,
		"consulta pública de la selección de sesión")
	_check(session_context.ok and session_context.data.fixtures.size()
		== reference_fixtures.size(), "consulta pública del calendario de sesión")
	session_context.data.selection.season_id = "mutated_context"
	session_context.data.fixtures[0].fixture_id = "mutated_context_fixture"
	session_context.data.fixtures[0].metadata["synthetic"] = false
	var fresh_context = controller.get_session_context()
	_check(fresh_context.data.selection == reference_selection
		and fresh_context.data.fixtures[0].fixture_id == reference_fixtures[0].fixture_id
		and fresh_context.data.fixtures[0].metadata.synthetic,
		"el contexto público devuelve copias defensivas")
	var initial_table = controller.get_standings()
	_check(initial_table.ok and initial_table.data.rows.size() == 4,
		"consulta de tabla inicial")
	_check(initial_table.ok and _all_rows_zero(initial_table.data.rows),
		"tabla inicial sin partidos")

	# Las mutaciones posteriores de las fuentes no atraviesan las copias defensivas.
	source_clubs[0].club_id = "mutated_club"
	source_fixtures[0].fixture_id = "mutated_fixture"
	source_fixtures[0].metadata["synthetic"] = false
	source_rules.points_win = 99
	source_rules.competition_format.legs = 1
	source_selection.season_id = "mutated_season"
	source_clubs.clear()
	source_fixtures.clear()
	_check(controller.get_standings().ok, "arrays originales aislados")

	var round_one = _round_results(reference_fixtures, 1, [[2, 0], [1, 1]])
	var partial: Array[Result] = [round_one[0]]
	var partial_snapshot = _snapshot_results(partial)
	var applied_partial = controller.apply_round(partial, 1)
	_check(applied_partial.ok and applied_partial.data.applied_fixture_ids
		== [round_one[0].fixture_id], "aplica jornada parcial")
	_check(controller.get_results().data.results.size() == 1,
		"publica únicamente el resultado parcial")
	partial[0].home_goals = 88
	partial.clear()
	_check(_find_result(controller.get_results().data.results,
		round_one[0].fixture_id).home_goals == partial_snapshot[0].home_goals,
		"resultados pasados como argumentos quedan aislados")

	var remaining: Array[Result] = [round_one[1]]
	var completed_round = controller.apply_round(remaining, 1)
	_check(completed_round.ok and controller.get_results().data.results.size() == 2,
		"finaliza posteriormente una jornada parcial")
	_check(completed_round.data.applied_fixture_ids == [round_one[1].fixture_id],
		"informa la incorporación restante")
	var retry_results = _round_results(reference_fixtures, 1, [[2, 0], [1, 1]])
	var exact_retry = controller.apply_round(retry_results, 1)
	_check(exact_retry.ok and exact_retry.data.applied_fixture_ids.is_empty(),
		"reintento idempotente sin altas")
	_check(exact_retry.ok and exact_retry.data.already_applied_fixture_ids
		== _result_ids(retry_results), "reintento informa partidos ya aplicados")
	var conflict = _copy_result(retry_results[0])
	conflict.home_goals = 3
	var before_conflict = _state_snapshot(controller)
	_expect_error(controller.apply_round([conflict], 1), "final_result_conflict")
	_check(_state_snapshot(controller) == before_conflict,
		"conflicto no modifica el estado")

	var round_two = _round_results(reference_fixtures, 2, [[0, 1], [3, 0]])
	var applied_second = controller.apply_round(round_two, 2)
	_check(applied_second.ok and controller.get_results().data.results.size() == 4,
		"aplica segunda jornada y acumula resultados")
	var table_after_two = controller.get_standings()
	_check(table_after_two.ok and _max_played(table_after_two.data.rows) == 2,
		"tabla acumulada tras dos jornadas")
	_check(table_after_two.ok and _max_points(table_after_two.data.rows) < 99,
		"mutar las reglas originales no cambia la puntuación interna")
	var reference_after_two = Standings.new().calculate(
		reference_clubs, reference_fixtures,
		controller.get_results().data.results, reference_rules, reference_selection
	)
	_check(reference_after_two.ok and table_after_two.data == reference_after_two.data,
		"clasificación compatible con StandingsService")

	var first_correction = _correction(
		"controller-correction-1", round_one[0].fixture_id,
		2, 0, 0, 2, "Acta rectificada por primera vez"
	)
	var position_before = _row(table_after_two.data.rows, "club_a").position
	var corrected_first = controller.correct_results([first_correction])
	_check(corrected_first.ok and corrected_first.data.corrected_fixture_ids
		== [round_one[0].fixture_id], "primera rectificación")
	_check(corrected_first.ok and corrected_first.data.audit_entries.size() == 1,
		"primera auditoría acumulada")
	var position_after = _row(corrected_first.data.standings.rows, "club_a").position
	_check(position_before != position_after, "rectificación cambia posiciones")
	first_correction.reason = "Motivo alterado por el llamador"
	_check(controller.get_audit_entries().data.audit_entries[0].reason
		== "Acta rectificada por primera vez", "solicitud de corrección aislada")

	var second_correction = _correction(
		"controller-correction-2", round_one[0].fixture_id,
		0, 2, 1, 1, "Segunda rectificación del mismo partido"
	)
	var corrected_second = controller.correct_results([second_correction])
	_check(corrected_second.ok and corrected_second.data.audit_entries.size() == 2,
		"segunda rectificación conserva historial")
	var accumulated = controller.get_audit_entries().data.audit_entries
	_check(accumulated[0].correction_id == "controller-correction-1"
		and accumulated[1].correction_id == "controller-correction-2",
		"auditoría acumulada en orden histórico")
	_check(accumulated[0].after == accumulated[1].before,
		"cadena de auditoría coherente")
	var duplicate_historical = _correction(
		"controller-correction-1", round_two[0].fixture_id,
		0, 1, 1, 0, "Identidad repetida"
	)
	var before_duplicate = _state_snapshot(controller)
	_expect_error(controller.correct_results([duplicate_historical]),
		"historical_duplicate_correction_id")
	_check(_state_snapshot(controller) == before_duplicate,
		"identidad histórica duplicada no muta")

	var exposed_results = controller.get_results()
	exposed_results.data.results[0].home_goals = 99
	exposed_results.data.results.clear()
	_check(controller.get_results().data.results.size() == 4
		and _find_result(controller.get_results().data.results,
		round_one[0].fixture_id).home_goals == 1,
		"resultados devueltos son copias independientes")
	var exposed_audit = controller.get_audit_entries()
	exposed_audit.data.audit_entries[0].reason = "Alteración externa"
	exposed_audit.data.audit_entries.clear()
	_check(controller.get_audit_entries().data.audit_entries.size() == 2
		and controller.get_audit_entries().data.audit_entries[0].reason
		== "Acta rectificada por primera vez",
		"auditoría devuelta es una copia independiente")
	var exposed_table = controller.get_standings()
	exposed_table.data.rows[0].points = 999
	_check(controller.get_standings().data.rows[0].points != 999,
		"clasificación devuelta no expone estado mutable")

	var reinitialize_snapshot = _state_snapshot(controller)
	_expect_error(controller.initialize(
		reference_clubs, reference_fixtures, reference_rules, reference_selection
	), "already_initialized")
	_check(_state_snapshot(controller) == reinitialize_snapshot,
		"reinicialización rechazada conserva sesión activa")

	_test_provisional_diagnostics(reference_clubs, reference_fixtures, reference_selection)
	_test_persistence(controller, reference_clubs, reference_fixtures,
		reference_rules, reference_selection)
	_test_determinism(reference_clubs, reference_fixtures,
		reference_rules, reference_selection)
	_test_formats_and_points()
	_test_complete_sequence()

	_finish()


func _test_before_initialization() -> void:
	var controller = Controller.new()
	_expect_error(controller.get_standings(), "not_initialized")
	_expect_error(controller.get_results(), "not_initialized")
	_expect_error(controller.get_session_context(), "not_initialized")
	_expect_error(controller.get_audit_entries(), "not_initialized")
	_expect_error(controller.apply_round([], 1), "not_initialized")
	_expect_error(controller.correct_results([]), "not_initialized")
	_expect_error(controller.save_state(_path("before_init")), "not_initialized")
	_expect_error(controller.load_state(_path("before_init")), "not_initialized")


func _test_invalid_initialization() -> void:
	var clubs = _clubs()
	var fixtures = _fixtures(2)
	var invalid_rules = _rules(3, 2)
	invalid_rules.points_win = null
	var invalid_rule_controller = Controller.new()
	_expect_error(invalid_rule_controller.initialize(
		clubs, fixtures, invalid_rules, _selection()
	), "invalid_rules")
	_expect_error(invalid_rule_controller.get_results(), "not_initialized")
	var duplicate_fixtures: Array[Fixture] = fixtures.duplicate()
	duplicate_fixtures.append(_copy_fixture(fixtures[0]))
	var invalid_calendar_controller = Controller.new()
	_expect_error(invalid_calendar_controller.initialize(
		clubs, duplicate_fixtures, _rules(3, 2), _selection()
	), "duplicate_fixture")
	_expect_error(invalid_calendar_controller.get_results(), "not_initialized")


func _test_provisional_diagnostics(clubs: Array[Club], fixtures: Array[Fixture],
		selection: Dictionary) -> void:
	var rules = _rules(3, 2, ["head_to_head_points", "head_to_head_goal_difference"])
	var controller = Controller.new()
	_check(controller.initialize(clubs, fixtures, rules, selection).ok,
		"inicializa reglas de desempate directo")
	var draws = _round_results(fixtures, 1, [[0, 0], [0, 0]])
	var applied = controller.apply_round(draws, 1)
	_check(applied.ok and applied.data.standings.provisional,
		"conserva clasificación provisional")
	_check(applied.ok and not applied.data.standings.pending_tiebreakers.is_empty(),
		"conserva diagnósticos de desempate pendientes")


func _test_persistence(controller: Controller, clubs: Array[Club],
		fixtures: Array[Fixture], rules: Rules, selection: Dictionary) -> void:
	var path = _path("state")
	var before_save = _state_snapshot(controller)
	var saved = controller.save_state(path)
	_check(saved.ok and saved.data.schema_version == 1, "guardado correcto")
	_check(_state_snapshot(controller) == before_save, "guardar no altera memoria")
	var persistence_load = Persistence.new().load_state(
		path, clubs, fixtures, rules, selection
	)
	_check(persistence_load.ok
		and persistence_load.data.audit_entries.size() == 2,
		"archivo compatible con SportingStatePersistenceService")

	var extra_correction = _correction(
		"after-save", "fixture_03", 0, 1, 2, 0, "Cambio posterior al guardado"
	)
	_check(controller.correct_results([extra_correction]).ok,
		"modifica memoria después de guardar")
	var loaded = controller.load_state(path)
	_check(loaded.ok and loaded.data.result_count == 4
		and loaded.data.audit_entry_count == 2, "carga correcta sustituye estado")
	_check(controller.get_audit_entries().data.audit_entries.size() == 2,
		"carga restaura historial guardado")

	# Un segundo guardado crea el respaldo explícito del estado anterior.
	var backup_controller = Controller.new()
	_check(backup_controller.initialize(clubs, fixtures, rules, selection).ok,
		"inicializa controlador para respaldo")
	var round_one = _round_results(fixtures, 1, [[1, 0], [0, 0]])
	_check(backup_controller.apply_round(round_one, 1).ok,
		"prepara primer estado del respaldo")
	var backup_path = _path("backup")
	_check(backup_controller.save_state(backup_path).ok, "primer guardado de respaldo")
	var round_two = _round_results(fixtures, 2, [[1, 1], [2, 0]])
	_check(backup_controller.apply_round(round_two, 2).ok,
		"prepara segundo estado del respaldo")
	_check(backup_controller.save_state(backup_path).ok, "segundo guardado crea respaldo")
	_check(backup_controller.load_state(backup_path + ".bak").ok,
		"recuperación explícita desde respaldo")
	_check(backup_controller.get_results().data.results.size() == 2,
		"respaldo contiene el estado anterior")

	var stable_snapshot = _state_snapshot(controller)
	var corrupt_path = _path("corrupt")
	_write_raw(corrupt_path, "{not json")
	_expect_error(controller.load_state(corrupt_path), "malformed_json")
	_check(_state_snapshot(controller) == stable_snapshot,
		"archivo corrupto no modifica estado")
	var incompatible_path = _copy_path(path, "schema")
	var document = _read_document(incompatible_path)
	document.schema_version = 2
	_write_document(incompatible_path, document)
	_expect_error(controller.load_state(incompatible_path), "unsupported_schema_version")
	_check(_state_snapshot(controller) == stable_snapshot,
		"esquema incompatible no modifica estado")

	var incompatible_rules = Controller.new()
	_check(incompatible_rules.initialize(clubs, fixtures, _rules(2, 2), selection).ok,
		"inicializa reglas alternativas")
	_expect_error(incompatible_rules.load_state(path), "rules_fingerprint_mismatch")
	var changed_fixtures = _copy_fixtures(fixtures)
	changed_fixtures[0].round_number = 99
	var incompatible_calendar = Controller.new()
	_check(incompatible_calendar.initialize(clubs, changed_fixtures, rules, selection).ok,
		"inicializa calendario alternativo")
	_expect_error(incompatible_calendar.load_state(path), "fixtures_fingerprint_mismatch")
	var other_selection = {
		"season_id": "season_a", "competition_id": "cup",
		"stage_id": "regular", "group_id": null,
	}
	var incompatible_selection = Controller.new()
	var cup_rules = _rules(3, 2)
	cup_rules.competition_id = "cup"
	_check(incompatible_selection.initialize(clubs, fixtures, cup_rules, other_selection).ok,
		"inicializa selección alternativa")
	_expect_error(incompatible_selection.load_state(path), "selection_mismatch")

	var blocked_path = _path("blocked")
	var temp_path = blocked_path + ".tmp"
	DirAccess.make_dir_recursive_absolute(Persistence.SAVE_ROOT)
	DirAccess.remove_absolute(temp_path)
	_check(DirAccess.make_dir_absolute(temp_path) == OK,
		"prepara error de escritura sintético")
	var before_write_error = _state_snapshot(controller)
	_expect_error(controller.save_state(blocked_path), "write_error")
	_check(_state_snapshot(controller) == before_write_error,
		"error de guardado no modifica memoria")
	DirAccess.remove_absolute(temp_path)


func _test_determinism(clubs: Array[Club], fixtures: Array[Fixture],
		rules: Rules, selection: Dictionary) -> void:
	var left = Controller.new()
	var right = Controller.new()
	var reversed_clubs = _copy_clubs(clubs)
	reversed_clubs.reverse()
	var reversed_fixtures = _copy_fixtures(fixtures)
	reversed_fixtures.reverse()
	_check(left.initialize(clubs, fixtures, rules, selection).ok
		and right.initialize(reversed_clubs, reversed_fixtures, rules, selection).ok,
		"inicializa permutaciones equivalentes")
	var incoming = _round_results(fixtures, 1, [[2, 1], [0, 0]])
	var reversed_incoming: Array[Result] = incoming.duplicate()
	reversed_incoming.reverse()
	_check(left.apply_round(incoming, 1).ok
		and right.apply_round(reversed_incoming, 1).ok,
		"aplica lotes permutados")
	_check(_snapshot_results(left.get_results().data.results)
		== _snapshot_results(right.get_results().data.results),
		"resultados deterministas ante permutaciones")
	_check(left.get_standings().data == right.get_standings().data,
		"clasificación determinista ante permutaciones")
	var correction_left = _correction(
		"deterministic", incoming[0].fixture_id, 2, 1, 1, 2, "Corrección determinista"
	)
	var correction_right = correction_left.duplicate(true)
	var second_left = _correction(
		"deterministic-second", incoming[1].fixture_id,
		0, 0, 1, 1, "Segunda corrección determinista"
	)
	var second_right = second_left.duplicate(true)
	_check(left.correct_results([correction_left, second_left]).ok
		and right.correct_results([second_right, correction_right]).ok,
		"rectifica estados permutados")
	_check(left.get_audit_entries().data.audit_entries
		== right.get_audit_entries().data.audit_entries,
		"auditoría determinista ante permutaciones")


func _test_formats_and_points() -> void:
	for legs in [1, 2]:
		for points_win in [2, 3]:
			var clubs = _clubs()
			var selection = _selection()
			var generated = Generator.new().generate(clubs, {
				"format": "round_robin",
				"season_id": selection.season_id,
				"competition_id": selection.competition_id,
				"stage_id": selection.stage_id,
				"group_id": selection.group_id,
				"legs": legs,
			})
			_check(generated.ok, "genera liga %d vuelta(s)" % legs)
			if not generated.ok:
				continue
			var fixtures: Array[Fixture] = []
			for fixture in generated.data:
				fixtures.append(fixture)
			var rules = _rules(points_win, legs)
			var controller = Controller.new()
			_check(controller.initialize(clubs, fixtures, rules, selection).ok,
				"controlador compatible con %d vuelta(s), %d puntos" % [legs, points_win])
			var incoming = _round_results(fixtures, 1, [[1, 0], [0, 0]])
			var applied = controller.apply_round(incoming, 1)
			_check(applied.ok and _max_points(applied.data.standings.rows) == points_win,
				"clasificación usa %d puntos por victoria" % points_win)
			var direct = Progression.new().apply_round(
				clubs, fixtures, [], incoming, rules, selection, 1
			)
			_check(direct.ok and direct.data.standings == applied.data.standings,
				"jornada compatible con RoundProgressionService")


func _test_complete_sequence() -> void:
	var clubs = _clubs()
	var fixtures = _fixtures(2)
	var rules = _rules(3, 2)
	var selection = _selection()
	var controller = Controller.new()
	_check(controller.initialize(clubs, fixtures, rules, selection).ok,
		"secuencia completa inicializa")
	var first_round = _round_results(fixtures, 1, [[2, 0], [1, 1]])
	_check(controller.apply_round(first_round, 1).ok, "secuencia completa avanza")
	var request = _correction(
		"full-sequence", first_round[0].fixture_id, 2, 0, 1, 0,
		"Rectificación de secuencia completa"
	)
	var direct_correction = Correction.new().correct_results(
		clubs, fixtures, first_round, [request], rules, selection
	)
	var controller_correction = controller.correct_results([request])
	_check(direct_correction.ok and controller_correction.ok
		and direct_correction.data.standings == controller_correction.data.standings,
		"corrección compatible con MatchResultCorrectionService")
	var path = _path("full_sequence")
	_check(controller.save_state(path).ok, "secuencia completa guarda")
	var restored = Controller.new()
	_check(restored.initialize(clubs, fixtures, rules, selection).ok
		and restored.load_state(path).ok, "secuencia completa carga en otra instancia")
	var second_round = _round_results(fixtures, 2, [[0, 1], [1, 0]])
	_check(restored.apply_round(second_round, 2).ok,
		"secuencia completa continúa tras cargar")
	_check(restored.get_results().data.results.size() == 4
		and restored.get_audit_entries().data.audit_entries.size() == 1,
		"secuencia completa conserva resultados y auditoría")


func _clubs() -> Array[Club]:
	return [_club("club_a"), _club("club_b"), _club("club_c"), _club("club_d")]


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


func _copy_fixtures(source: Array[Fixture]) -> Array[Fixture]:
	var copies: Array[Fixture] = []
	for fixture in source:
		copies.append(_copy_fixture(fixture))
	return copies


func _copy_clubs(source: Array[Club]) -> Array[Club]:
	var copies: Array[Club] = []
	for original in source:
		var club = Club.new()
		club.club_id = original.club_id
		club.season_id = original.season_id
		club.division_id = original.division_id
		copies.append(club)
	return copies


func _result(fixture_id: String, home_goals: int, away_goals: int) -> Result:
	var result = Result.new()
	result.fixture_id = fixture_id
	result.season_id = "season_a"
	result.status = Result.Status.FINAL
	result.home_goals = home_goals
	result.away_goals = away_goals
	return result


func _copy_result(source: Result) -> Result:
	var result = Result.new()
	result.fixture_id = source.fixture_id
	result.season_id = source.season_id
	result.status = source.status
	result.home_goals = source.home_goals
	result.away_goals = source.away_goals
	return result


func _round_results(fixtures: Array[Fixture], round_number: int,
		scores: Array) -> Array[Result]:
	var selected: Array[Fixture] = []
	for fixture in fixtures:
		if fixture.round_number == round_number:
			selected.append(fixture)
	selected.sort_custom(func(left: Fixture, right: Fixture):
		return left.fixture_id < right.fixture_id
	)
	var results: Array[Result] = []
	for index in selected.size():
		results.append(_result(selected[index].fixture_id,
			scores[index][0], scores[index][1]))
	return results


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


func _rules(points_win: int, legs: int,
		tiebreakers: Variant = ["goal_difference", "goals_for", "wins"]) -> Rules:
	var rules = Rules.new()
	rules.season_id = "season_a"
	rules.competition_id = "league"
	rules.points_win = points_win
	rules.points_draw = 1
	rules.points_loss = 0
	rules.team_count = 4
	rules.round_count = 3 * legs
	rules.tiebreakers = tiebreakers.duplicate(true)
	rules.substitution_rules = null
	rules.promotion_relegation_rules = null
	rules.competition_format = {
		"kind": "round_robin",
		"legs": legs,
		"head_to_head_policy": "single_pass",
	}
	return rules


func _copy_rules(source: Rules) -> Rules:
	var rules = Rules.new()
	rules.season_id = source.season_id
	rules.competition_id = source.competition_id
	rules.points_win = source.points_win
	rules.points_draw = source.points_draw
	rules.points_loss = source.points_loss
	rules.team_count = source.team_count
	rules.round_count = source.round_count
	rules.tiebreakers = source.tiebreakers.duplicate(true)
	rules.substitution_rules = source.substitution_rules
	rules.promotion_relegation_rules = source.promotion_relegation_rules
	rules.competition_format = source.competition_format.duplicate(true)
	return rules


func _selection() -> Dictionary:
	return {
		"season_id": "season_a",
		"competition_id": "league",
		"stage_id": "regular",
		"group_id": null,
	}


func _row(rows: Array, club_id: String) -> Dictionary:
	for row in rows:
		if row.club_id == club_id:
			return row
	return {}


func _find_result(results: Array, fixture_id: String) -> Result:
	for result in results:
		if result.fixture_id == fixture_id:
			return result
	return null


func _result_ids(results: Array) -> Array[String]:
	var ids: Array[String] = []
	for result in results:
		ids.append(result.fixture_id)
	ids.sort()
	return ids


func _all_rows_zero(rows: Array) -> bool:
	for row in rows:
		if row.played != 0 or row.points != 0:
			return false
	return true


func _max_played(rows: Array) -> int:
	var maximum = 0
	for row in rows:
		maximum = maxi(maximum, row.played)
	return maximum


func _max_points(rows: Array) -> int:
	var maximum = -1000000
	for row in rows:
		maximum = maxi(maximum, row.points)
	return maximum


func _state_snapshot(controller: Controller) -> Dictionary:
	var results = controller.get_results()
	var audit = controller.get_audit_entries()
	var standings = controller.get_standings()
	return {
		"results": _snapshot_results(results.data.results) if results.ok else null,
		"audit": audit.data.audit_entries.duplicate(true) if audit.ok else null,
		"standings": standings.data.duplicate(true) if standings.ok else null,
	}


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


func _path(name: String) -> String:
	var path = TEST_PREFIX + name + ".json"
	if path not in created_paths:
		created_paths.append(path)
	return path


func _copy_path(source: String, name: String) -> String:
	var target = _path(name)
	DirAccess.copy_absolute(source, target)
	return target


func _read_document(path: String) -> Dictionary:
	var parser = JSON.new()
	parser.parse(_read_raw(path))
	return parser.data


func _write_document(path: String, document: Dictionary) -> void:
	_write_raw(path, JSON.stringify(document, "", true, true))


func _write_raw(path: String, content: String) -> void:
	if path.begins_with(TEST_PREFIX) and path not in created_paths:
		created_paths.append(path)
	DirAccess.make_dir_recursive_absolute(Persistence.SAVE_ROOT)
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
	DirAccess.make_dir_recursive_absolute(Persistence.SAVE_ROOT)
	var directory = DirAccess.open(Persistence.SAVE_ROOT)
	if directory == null:
		return
	for filename in directory.get_files():
		if filename.begins_with("season_controller_phase1_"):
			directory.remove(filename)
	for dirname in directory.get_directories():
		if dirname.begins_with("season_controller_phase1_"):
			directory.remove(dirname)


func _cleanup_created_paths() -> void:
	for path in created_paths:
		for suffix in ["", ".tmp", ".bak", ".bak.tmp"]:
			DirAccess.remove_absolute(path + suffix)


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
