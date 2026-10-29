extends SceneTree

const Service = preload("res://game/scripts/services/match_result_correction_service.gd")
const Progression = preload("res://game/scripts/services/round_progression_service.gd")
const Standings = preload("res://game/scripts/services/standings_service.gd")
const Generator = preload("res://game/scripts/services/league_calendar_generator.gd")
const Club = preload("res://game/scripts/data/club_season.gd")
const Fixture = preload("res://game/scripts/data/match_fixture.gd")
const Result = preload("res://game/scripts/data/match_result.gd")
const Rules = preload("res://game/scripts/data/competition_rules.gd")

var failures: Array[String] = []
var checks = 0


func _initialize() -> void:
	var service = Service.new()
	var clubs: Array[Club] = [
		_club("club_a"), _club("club_b"), _club("club_c"), _club("club_d")
	]
	var fixtures = _fixtures(2)
	var results = _results(fixtures)
	var rules = _rules(3, 2)
	var selection = _selection()
	var snapshots = {
		"clubs": _snapshot_clubs(clubs),
		"fixtures": _snapshot_fixtures(fixtures),
		"results": _snapshot_results(results),
		"rules": _snapshot_rules(rules),
		"selection": selection.duplicate(true),
	}

	var home_win = _correction("correction-home", "fixture_01", 2, 0, 3, 0,
		"Rectificación del acta")
	var corrected_home = service.correct_results(
		clubs, fixtures, results, [home_win], rules, selection
	)
	_check(corrected_home.ok and corrected_home.errors.is_empty(),
		"corrige una victoria local")
	if corrected_home.ok:
		_check(corrected_home.data.corrected_fixture_ids == ["fixture_01"],
			"informa el partido corregido")
		_check(_find_result(corrected_home.data.results, "fixture_01").home_goals == 3,
			"publica el nuevo marcador local")
		_check(_find_result(corrected_home.data.results, "fixture_01").status
			== Result.Status.FINAL, "conserva el estado final")
		_check(_all_new_objects(corrected_home.data.results, results),
			"todos los resultados de salida son copias")
		_check(_result_ids(corrected_home.data.results) == _sorted_result_ids(results),
			"resultados ordenados por temporada y partido")

	var away_win = _correction("correction-away", "fixture_04", 2, 0, 0, 3,
		"Error en el equipo ganador")
	var corrected_away = service.correct_results(
		clubs, fixtures, results, [away_win], rules, selection
	)
	_check(corrected_away.ok
		and _find_result(corrected_away.data.results, "fixture_04").away_goals == 3,
		"corrige una victoria visitante")

	var win_to_draw = _correction("win-to-draw", "fixture_01", 2, 0, 1, 1,
		"Marcador definitivo empatado")
	var draw_result = service.correct_results(
		clubs, fixtures, results, [win_to_draw], rules, selection
	)
	_check(draw_result.ok and _find_result(draw_result.data.results, "fixture_01").home_goals == 1
		and _find_result(draw_result.data.results, "fixture_01").away_goals == 1,
		"convierte victoria en empate")
	var draw_to_win = _correction("draw-to-win", "fixture_02", 1, 1, 0, 2,
		"Victoria visitante confirmada")
	var won_result = service.correct_results(
		clubs, fixtures, results, [draw_to_win], rules, selection
	)
	_check(won_result.ok and _find_result(won_result.data.results, "fixture_02").away_goals == 2,
		"convierte empate en victoria")

	var two_corrections: Array[Dictionary] = [away_win, home_win]
	var corrected_two = service.correct_results(
		clubs, fixtures, results, two_corrections, rules, selection
	)
	_check(corrected_two.ok and corrected_two.data.corrected_fixture_ids
		== ["fixture_01", "fixture_04"], "corrige dos partidos atómicamente")
	_check(corrected_two.data.audit_entries[0].fixture_id == "fixture_01"
		and corrected_two.data.audit_entries[1].fixture_id == "fixture_04",
		"auditoría ordenada independientemente del lote")
	var audit = corrected_two.data.audit_entries[0]
	_check(audit.correction_id == "correction-home"
		and audit.season_id == "season_a" and audit.fixture_id == "fixture_01"
		and audit.reason == "Rectificación del acta", "auditoría conserva identidad y motivo")
	_check(audit.before == {
		"home_goals": 2, "away_goals": 0, "status": Result.Status.FINAL,
	}, "auditoría contiene el estado anterior")
	_check(audit.after == {
		"home_goals": 3, "away_goals": 0, "status": Result.Status.FINAL,
	}, "auditoría contiene el estado posterior")
	_check(audit.before is Dictionary and audit.after is Dictionary,
		"auditoría usa diccionarios independientes")
	var isolated_results: Array[Result] = []
	for result in results:
		isolated_results.append(_copy_result(result))
	var isolated_request = home_win.duplicate(true)
	var isolated = service.correct_results(
		clubs, fixtures, isolated_results, [isolated_request], rules, selection
	)
	isolated_results[0].home_goals = 99
	isolated_request.reason = "Motivo alterado por el llamador"
	_check(isolated.ok and isolated.data.audit_entries[0].before.home_goals == 2
		and isolated.data.audit_entries[0].reason == "Rectificación del acta",
		"auditoría no conserva referencias a las entradas")

	var expected_table = Standings.new().calculate(
		clubs, fixtures, corrected_two.data.results, rules, selection
	)
	_check(expected_table.ok and corrected_two.data.standings == expected_table.data,
		"clasificación coincide con StandingsService")
	_check(_row(corrected_two.data.standings.rows, "club_a").points
		== _row(expected_table.data.rows, "club_a").points,
		"recalcula los puntos")
	_check(_row(corrected_two.data.standings.rows, "club_d").goals_for
		== _row(expected_table.data.rows, "club_d").goals_for,
		"recalcula goles a favor")
	_check(_row(corrected_two.data.standings.rows, "club_b").goals_against
		== _row(expected_table.data.rows, "club_b").goals_against,
		"recalcula goles en contra")
	_check(_row(corrected_two.data.standings.rows, "club_b").goal_difference
		== _row(expected_table.data.rows, "club_b").goal_difference,
		"recalcula diferencia de goles")
	_check(_row(corrected_two.data.standings.rows, "club_d").position
		== _row(expected_table.data.rows, "club_d").position,
		"recalcula posiciones")

	var direct = _direct_tiebreak_case(service)
	_check(direct.ok, "corrección múltiple mantiene empate general")
	if direct.ok:
		_check(direct.before_first == "club_a" and direct.after_first == "club_b",
			"la corrección altera un desempate directo")

	var provisional_rules = _rules(3, 2,
		["head_to_head_points", "head_to_head_goal_difference"])
	var partial_results: Array[Result] = [
		_result("fixture_01", Result.Status.FINAL, 0, 0),
		_result("fixture_02", Result.Status.FINAL, 0, 0),
	]
	var before_provisional = Standings.new().calculate(
		clubs, fixtures, partial_results, provisional_rules, selection
	)
	var provisional_correction = _correction(
		"provisional", "fixture_01", 0, 0, 1, 1, "Acta corregida"
	)
	var after_provisional = service.correct_results(
		clubs, fixtures, partial_results, [provisional_correction],
		provisional_rules, selection
	)
	_check(before_provisional.ok and after_provisional.ok
		and after_provisional.data.standings.provisional,
		"conserva la naturaleza provisional")
	_check(after_provisional.ok
		and after_provisional.data.standings.pending_tiebreakers is Array,
		"conserva pending_tiebreakers")

	var pending_results: Array[Result] = results.duplicate()
	pending_results[0] = _result("fixture_01", Result.Status.PENDING, null, null)
	_expect_error(service.correct_results(clubs, fixtures, pending_results,
		[home_win], rules, selection), "result_not_final")
	var without_result: Array[Result] = []
	for result in results:
		if result.fixture_id != "fixture_01":
			without_result.append(result)
	_expect_error(service.correct_results(clubs, fixtures, without_result,
		[home_win], rules, selection), "missing_result")
	var unknown = home_win.duplicate(true)
	unknown.fixture_id = "unknown_fixture"
	_expect_error(service.correct_results(clubs, fixtures, results,
		[unknown], rules, selection), "unknown_fixture")

	var cup_fixture = _fixture("cup_fixture", "season_a", "cup", "regular", null,
		"club_a", "club_b", 1)
	var fixtures_with_cup: Array[Fixture] = fixtures.duplicate()
	fixtures_with_cup.append(cup_fixture)
	var cup_result = _result("cup_fixture", Result.Status.FINAL, 1, 0)
	var results_with_cup: Array[Result] = results.duplicate()
	results_with_cup.append(cup_result)
	var cup_correction = _correction(
		"cup", "cup_fixture", 1, 0, 0, 1, "Corrección fuera de liga"
	)
	_expect_error(service.correct_results(clubs, fixtures_with_cup, results_with_cup,
		[cup_correction], rules, selection), "scope_mismatch")
	var wrong_season = home_win.duplicate(true)
	wrong_season.season_id = "season_b"
	_expect_error(service.correct_results(clubs, fixtures, results,
		[wrong_season], rules, selection), "season_mismatch")

	var stale = home_win.duplicate(true)
	stale.expected_home_goals = 9
	_expect_error(service.correct_results(clubs, fixtures, results,
		[stale], rules, selection), "stale_expected_score")
	var unchanged = home_win.duplicate(true)
	unchanged.new_home_goals = 2
	_expect_error(service.correct_results(clubs, fixtures, results,
		[unchanged], rules, selection), "unchanged_score")
	for field in [
		"expected_home_goals", "expected_away_goals", "new_home_goals", "new_away_goals"
	]:
		for invalid_value in [-1, 1.5, "1", true, null, [], {}]:
			var invalid_score = home_win.duplicate(true)
			invalid_score[field] = invalid_value
			_expect_error(service.correct_results(clubs, fixtures, results,
				[invalid_score], rules, selection), "invalid_correction_score")
	var empty_reason = home_win.duplicate(true)
	empty_reason.reason = " \t "
	_expect_error(service.correct_results(clubs, fixtures, results,
		[empty_reason], rules, selection), "empty_reason")
	var empty_id = home_win.duplicate(true)
	empty_id.correction_id = ""
	_expect_error(service.correct_results(clubs, fixtures, results,
		[empty_id], rules, selection), "empty_correction_id")
	for field in ["season_id", "fixture_id", "reason", "correction_id"]:
		var wrong_type = home_win.duplicate(true)
		wrong_type[field] = 1
		_expect_error(service.correct_results(clubs, fixtures, results,
			[wrong_type], rules, selection), "invalid_correction_field")

	var duplicate_id_second = away_win.duplicate(true)
	duplicate_id_second.correction_id = home_win.correction_id
	_expect_error(service.correct_results(clubs, fixtures, results,
		[home_win, duplicate_id_second], rules, selection), "duplicate_correction_id")
	var same_fixture_second = home_win.duplicate(true)
	same_fixture_second.correction_id = "different-id"
	same_fixture_second.new_home_goals = 4
	_expect_error(service.correct_results(clubs, fixtures, results,
		[home_win, same_fixture_second], rules, selection), "duplicate_fixture_correction")
	for field in Service.CORRECTION_FIELDS:
		var missing = home_win.duplicate(true)
		missing.erase(field)
		_expect_error(service.correct_results(clubs, fixtures, results,
			[missing], rules, selection), "missing_correction_field")
	var extra = home_win.duplicate(true)
	extra["unexpected"] = true
	_expect_error(service.correct_results(clubs, fixtures, results,
		[extra], rules, selection), "unknown_correction_field")

	var permuted: Array[Dictionary] = [home_win.duplicate(true), away_win.duplicate(true)]
	var forward = service.correct_results(clubs, fixtures, results,
		permuted, rules, selection)
	permuted.reverse()
	var reverse = service.correct_results(clubs, fixtures, results,
		permuted, rules, selection)
	_check(forward.ok and reverse.ok
		and _snapshot_results(forward.data.results) == _snapshot_results(reverse.data.results),
		"resultados deterministas ante permutaciones")
	_check(forward.ok and reverse.ok
		and forward.data.audit_entries == reverse.data.audit_entries,
		"auditoría determinista ante permutaciones")
	_check(forward.ok and reverse.ok and forward.data.standings == reverse.data.standings,
		"clasificación determinista ante permutaciones")

	var retry = service.correct_results(clubs, fixtures, corrected_home.data.results,
		[home_win], rules, selection)
	_expect_error(retry, "stale_expected_score")
	var no_change_retry = _correction(
		"retry-new-id", "fixture_01", 3, 0, 3, 0, "Reintento sin cambio"
	)
	_expect_error(service.correct_results(clubs, fixtures, corrected_home.data.results,
		[no_change_retry], rules, selection), "unchanged_score")
	var later = _correction(
		"later-correction", "fixture_01", 3, 0, 1, 2, "Nueva rectificación legítima"
	)
	var corrected_later = service.correct_results(
		clubs, fixtures, corrected_home.data.results, [later], rules, selection
	)
	_check(corrected_later.ok
		and _find_result(corrected_later.data.results, "fixture_01").away_goals == 2,
		"admite corrección posterior con nueva identidad y estado actualizado")

	var late_invalid: Array[Dictionary] = [home_win.duplicate(true), away_win.duplicate(true)]
	late_invalid[1].new_away_goals = -1
	var late_error = service.correct_results(
		clubs, fixtures, results, late_invalid, rules, selection
	)
	_expect_error(late_error, "invalid_correction_score")
	_check(late_error.data == null and _snapshot_results(results) == snapshots.results,
		"error tardío no devuelve ni aplica estado parcial")

	var round_one_results: Array[Result] = [
		_copy_result(results[0]), _copy_result(results[1])
	]
	var progressed = Progression.new().apply_round(
		clubs, fixtures, [], round_one_results, rules, selection, 1
	)
	_check(progressed.ok, "RoundProgressionService prepara resultados corregibles")
	if progressed.ok:
		var integrated = service.correct_results(
			clubs, fixtures, progressed.data.results, [home_win], rules, selection
		)
		_check(integrated.ok and integrated.data.results.size() == 2,
			"integración con RoundProgressionService")
		_check(integrated.data.standings
			== Standings.new().calculate(
				clubs, fixtures, integrated.data.results, rules, selection
			).data, "integración con StandingsService")

	for points_win in [2, 3]:
		var historical_rules = _rules(points_win, 2)
		var historical = service.correct_results(
			clubs, fixtures, results, [win_to_draw], historical_rules, selection
		)
		_check(historical.ok, "rectificación válida con %d puntos por victoria" % points_win)
		if historical.ok:
			var historical_expected = Standings.new().calculate(
				clubs, fixtures, historical.data.results, historical_rules, selection
			)
			_check(historical.data.standings == historical_expected.data,
				"clasificación histórica de %d puntos recalculada" % points_win)

	for legs in [1, 2]:
		var generated = Generator.new().generate(clubs, {
			"format": "round_robin",
			"season_id": selection.season_id,
			"competition_id": selection.competition_id,
			"stage_id": selection.stage_id,
			"group_id": selection.group_id,
			"legs": legs,
		})
		_check(generated.ok, "genera liga de %d vuelta(s)" % legs)
		if generated.ok:
			var generated_fixtures: Array[Fixture] = []
			for fixture in generated.data:
				generated_fixtures.append(fixture)
			var generated_results: Array[Result] = []
			for fixture in generated_fixtures:
				generated_results.append(
					_result(fixture.fixture_id, Result.Status.FINAL, 1, 0)
				)
			var generated_correction = _correction(
				"generated-%d" % legs, generated_fixtures[0].fixture_id,
				1, 0, 0, 1, "Corrección en calendario generado"
			)
			var compatible = service.correct_results(
				clubs, generated_fixtures, generated_results, [generated_correction],
				_rules(3, legs), selection
			)
			_check(compatible.ok and compatible.data.results.size()
				== generated_results.size(), "compatible con liga de %d vuelta(s)" % legs)

	var other_round_before = _find_result(results, "fixture_06")
	var preserved = _find_result(corrected_home.data.results, "fixture_06")
	_check(preserved.home_goals == other_round_before.home_goals
		and preserved.away_goals == other_round_before.away_goals,
		"conserva resultados de jornadas no afectadas")

	var invalid_existing: Array[Result] = results.duplicate()
	invalid_existing[5] = _copy_result(invalid_existing[5])
	invalid_existing[5].home_goals = -1
	_expect_error(service.correct_results(clubs, fixtures, invalid_existing,
		[home_win], rules, selection), "invalid_score")
	var duplicate_existing: Array[Result] = results.duplicate()
	duplicate_existing.append(_copy_result(results[0]))
	_expect_error(service.correct_results(clubs, fixtures, duplicate_existing,
		[home_win], rules, selection), "duplicate_current_result")
	var invalid_rules = _rules(3, 2)
	invalid_rules.points_win = null
	_expect_error(service.correct_results(clubs, fixtures, results,
		[home_win], invalid_rules, selection), "invalid_rules")

	_check(_snapshot_clubs(clubs) == snapshots.clubs, "clubes sin mutaciones")
	_check(_snapshot_fixtures(fixtures) == snapshots.fixtures, "fixtures sin mutaciones")
	_check(_snapshot_results(results) == snapshots.results, "resultados sin mutaciones")
	_check(_snapshot_rules(rules) == snapshots.rules, "reglas sin mutaciones")
	_check(selection == snapshots.selection, "selección sin mutaciones")
	_check(home_win == _correction("correction-home", "fixture_01", 2, 0, 3, 0,
		"Rectificación del acta"), "solicitudes sin mutaciones")

	_finish()


func _direct_tiebreak_case(service: Service) -> Dictionary:
	var clubs: Array[Club] = [_club("club_a"), _club("club_b"), _club("club_c")]
	var fixtures: Array[Fixture] = [
		_fixture("direct_ab", "season_a", "league", "regular", null,
			"club_a", "club_b", 1),
		_fixture("direct_ba", "season_a", "league", "regular", null,
			"club_b", "club_a", 2),
		_fixture("external_ac", "season_a", "league", "regular", null,
			"club_a", "club_c", 3),
		_fixture("external_ca", "season_a", "league", "regular", null,
			"club_c", "club_a", 4),
		_fixture("external_bc", "season_a", "league", "regular", null,
			"club_b", "club_c", 5),
		_fixture("external_cb", "season_a", "league", "regular", null,
			"club_c", "club_b", 6),
	]
	var results: Array[Result] = [
		_result("direct_ab", Result.Status.FINAL, 1, 0),
		_result("direct_ba", Result.Status.FINAL, 0, 0),
		_result("external_ac", Result.Status.FINAL, 0, 1),
		_result("external_ca", Result.Status.FINAL, 1, 0),
		_result("external_bc", Result.Status.FINAL, 1, 0),
		_result("external_cb", Result.Status.FINAL, 1, 0),
	]
	var rules = _rules(3, 2, ["head_to_head_points"])
	var before = Standings.new().calculate(clubs, fixtures, results, rules, _selection())
	if not before.ok:
		return {"ok": false}
	var corrections: Array[Dictionary] = [
		_correction("flip-direct", "direct_ab", 1, 0, 0, 1, "Invierte el acta directa"),
		_correction("balance-a", "external_ca", 1, 0, 0, 1, "Compensa puntos de A"),
		_correction("balance-b", "external_bc", 1, 0, 0, 1, "Compensa puntos de B"),
	]
	var after = service.correct_results(clubs, fixtures, results, corrections,
		rules, _selection())
	if not after.ok:
		return {"ok": false}
	return {
		"ok": _row(before.data.rows, "club_a").points
			== _row(before.data.rows, "club_b").points
			and _row(after.data.standings.rows, "club_a").points
			== _row(after.data.standings.rows, "club_b").points,
		"before_first": "club_a" if _row(before.data.rows, "club_a").position
			< _row(before.data.rows, "club_b").position else "club_b",
		"after_first": "club_a" if _row(after.data.standings.rows, "club_a").position
			< _row(after.data.standings.rows, "club_b").position else "club_b",
	}


func _club(club_id: String, season_id: String = "season_a") -> Club:
	var club = Club.new()
	club.club_id = club_id
	club.season_id = season_id
	club.division_id = "synthetic_division"
	return club


func _fixtures(legs: int) -> Array[Fixture]:
	var fixtures: Array[Fixture] = [
		_fixture("fixture_01", "season_a", "league", "regular", null,
			"club_a", "club_b", 1),
		_fixture("fixture_02", "season_a", "league", "regular", null,
			"club_c", "club_d", 1),
		_fixture("fixture_03", "season_a", "league", "regular", null,
			"club_a", "club_c", 2),
		_fixture("fixture_04", "season_a", "league", "regular", null,
			"club_b", "club_d", 2),
		_fixture("fixture_05", "season_a", "league", "regular", null,
			"club_a", "club_d", 3),
		_fixture("fixture_06", "season_a", "league", "regular", null,
			"club_b", "club_c", 3),
	]
	if legs == 2:
		fixtures.append_array([
			_fixture("fixture_07", "season_a", "league", "regular", null,
				"club_b", "club_a", 4),
			_fixture("fixture_08", "season_a", "league", "regular", null,
				"club_d", "club_c", 4),
			_fixture("fixture_09", "season_a", "league", "regular", null,
				"club_c", "club_a", 5),
			_fixture("fixture_10", "season_a", "league", "regular", null,
				"club_d", "club_b", 5),
			_fixture("fixture_11", "season_a", "league", "regular", null,
				"club_d", "club_a", 6),
			_fixture("fixture_12", "season_a", "league", "regular", null,
				"club_c", "club_b", 6),
		])
	return fixtures


func _results(fixtures: Array[Fixture]) -> Array[Result]:
	var scores = [
		[2, 0], [1, 1], [0, 1], [2, 0], [1, 0], [0, 2],
		[0, 0], [1, 0], [0, 3], [2, 2], [0, 1], [1, 1],
	]
	var results: Array[Result] = []
	for index in fixtures.size():
		results.append(_result(fixtures[index].fixture_id,
			Result.Status.FINAL, scores[index][0], scores[index][1]))
	return results


func _fixture(fixture_id: String, season_id: String, competition_id: Variant,
		stage_id: Variant, group_id: Variant, home_club_id: Variant,
		away_club_id: Variant, round_number: Variant) -> Fixture:
	var fixture = Fixture.new()
	fixture.fixture_id = fixture_id
	fixture.season_id = season_id
	fixture.competition_id = competition_id
	fixture.stage_id = stage_id
	fixture.group_id = group_id
	fixture.home_club_id = home_club_id
	fixture.away_club_id = away_club_id
	fixture.round_number = round_number
	fixture.scheduled_date = null
	fixture.metadata = {"synthetic": true}
	return fixture


func _result(fixture_id: String, status: int, home_goals: Variant,
		away_goals: Variant, season_id: String = "season_a") -> Result:
	var result = Result.new()
	result.fixture_id = fixture_id
	result.season_id = season_id
	result.status = status
	result.home_goals = home_goals
	result.away_goals = away_goals
	return result


func _copy_result(source: Result) -> Result:
	return _result(source.fixture_id, source.status,
		source.home_goals, source.away_goals, source.season_id)


func _correction(correction_id: String, fixture_id: String,
		expected_home_goals: Variant, expected_away_goals: Variant,
		new_home_goals: Variant, new_away_goals: Variant, reason: String,
		season_id: String = "season_a") -> Dictionary:
	return {
		"season_id": season_id,
		"fixture_id": fixture_id,
		"expected_home_goals": expected_home_goals,
		"expected_away_goals": expected_away_goals,
		"new_home_goals": new_home_goals,
		"new_away_goals": new_away_goals,
		"reason": reason,
		"correction_id": correction_id,
	}


func _rules(points_win: Variant, legs: Variant,
		tiebreakers: Variant = ["goal_difference", "goals_for", "wins"]) -> Rules:
	var rules = Rules.new()
	rules.season_id = "season_a"
	rules.competition_id = "league"
	rules.points_win = points_win
	rules.points_draw = 1
	rules.points_loss = 0
	rules.team_count = null
	rules.round_count = null
	rules.tiebreakers = tiebreakers.duplicate() if tiebreakers is Array else tiebreakers
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


func _find_result(results: Array, fixture_id: String) -> Result:
	for match_result in results:
		if match_result.fixture_id == fixture_id:
			return match_result
	return null


func _row(rows: Array, club_id: String) -> Dictionary:
	for row in rows:
		if row.club_id == club_id:
			return row
	return {}


func _result_ids(results: Array) -> Array[String]:
	var ids: Array[String] = []
	for result in results:
		ids.append(result.fixture_id)
	return ids


func _sorted_result_ids(results: Array[Result]) -> Array[String]:
	var ids = _result_ids(results)
	ids.sort()
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
