extends SceneTree

const Service = preload("res://game/scripts/services/standings_service.gd")
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
	var fixtures: Array[Fixture] = [
		_fixture("home_win", "club_a", "club_b"),
		_fixture("away_win", "club_c", "club_a"),
		_fixture("draw", "club_b", "club_c"),
		_fixture("pending", "club_a", "club_d"),
		_fixture("without_result", "club_d", "club_b"),
	]
	var results: Array[Result] = [
		_result("home_win", Result.Status.FINAL, 2, 0),
		_result("away_win", Result.Status.FINAL, 1, 3),
		_result("draw", Result.Status.FINAL, 0, 0),
		_result("pending", Result.Status.PENDING, null, null),
	]
	var rules = _rules(3, 1, 0)
	var selection = _selection()
	var club_snapshot = _snapshot_clubs(clubs)
	var fixture_snapshot = _snapshot_fixtures(fixtures)
	var result_snapshot = _snapshot_results(results)
	var rules_snapshot = _snapshot_rules(rules)
	var selection_snapshot = selection.duplicate(true)
	var calculated = service.calculate(clubs, fixtures, results, rules, selection)
	_check(calculated.ok and calculated.errors.is_empty(), "clasificación válida")
	if calculated.ok:
		var rows = calculated.data.rows
		_check(_club_ids(rows) == ["club_a", "club_b", "club_c", "club_d"],
			"orden por puntos y club_id auxiliar")
		_expect_row(rows[0], 1, "club_a", 2, 2, 0, 0, 5, 1, 4, 6)
		_expect_row(rows[1], 2, "club_b", 2, 0, 1, 1, 0, 2, -2, 1)
		_expect_row(rows[2], 2, "club_c", 2, 0, 1, 1, 1, 3, -2, 1)
		_expect_row(rows[3], 4, "club_d", 0, 0, 0, 0, 0, 0, 0, 0)
		_check(calculated.data.provisional, "empate marcado como provisional")
		_check(calculated.data.unresolved_ties == [["club_b", "club_c"]],
			"empate deportivo explícito")
		_check(calculated.data.tiebreakers_applied == [], "sin desempate inventado")

	var two_point = service.calculate(clubs, fixtures, results, _rules(2, 1, 0), selection)
	_check(two_point.ok and _row(two_point, "club_a").points == 4,
		"regla de dos puntos por victoria")
	var custom = service.calculate(clubs, fixtures, results, _rules(4, 2, -1), selection)
	_check(custom.ok, "puntuación configurable válida")
	if custom.ok:
		_check(_row(custom, "club_a").points == 8, "puntos configurables por victoria")
		_check(_row(custom, "club_b").points == 1, "puntos configurables empate y derrota")
		_check(_row(custom, "club_c").points == 1, "puntos configurables visitante")
		_check(_row(custom, "club_d").points == 0, "equipo sin partidos")

	var no_tie_results: Array[Result] = [
		_result("home_win", Result.Status.FINAL, 1, 0),
		_result("away_win", Result.Status.FINAL, 0, 1),
		_result("draw", Result.Status.FINAL, 2, 1),
	]
	var no_tie_clubs: Array[Club] = [clubs[0], clubs[1], clubs[2]]
	var no_tie = service.calculate(no_tie_clubs, fixtures, no_tie_results, rules, selection)
	_check(no_tie.ok and not no_tie.data.provisional, "tabla resuelta únicamente por puntos")
	_check(no_tie.data.unresolved_ties.is_empty(), "sin empates pendientes")

	var other_scope: Array[Fixture] = fixtures.duplicate()
	other_scope.append(_fixture("other_competition", "club_a", "club_b",
		"season_a", "cup", "knockout", null))
	other_scope.append(_fixture("other_group", "club_a", "club_c",
		"season_a", "league", "regular", "group_b"))
	other_scope.append(_fixture("other_season", "club_a", "club_b",
		"season_b", "league", "regular", null))
	calculated = service.calculate(clubs, other_scope, results, rules, selection)
	_check(calculated.ok and _row(calculated, "club_a").played == 2,
		"temporadas competiciones fases y grupos independientes")
	var out_of_scope: Array[Result] = [_result("other_competition", Result.Status.FINAL, 1, 0)]
	_expect_error(service.calculate(clubs, other_scope, out_of_scope, rules, selection),
		"scope_mismatch")

	var exact_selection = _selection(" Exact Season ", " League ", " Stage ", " Group ")
	var exact_clubs: Array[Club] = [
		_club(" Club ", " Exact Season "), _club("Visitor", " Exact Season ")
	]
	var exact_fixtures: Array[Fixture] = [
		_fixture(" Exact Fixture ", " Club ", "Visitor",
			" Exact Season ", " League ", " Stage ", " Group ")
	]
	var exact_results: Array[Result] = [
		_result(" Exact Fixture ", Result.Status.FINAL, 1, 0, " Exact Season ")
	]
	var exact = service.calculate(exact_clubs, exact_fixtures, exact_results,
		_rules(3, 1, 0, " Exact Season ", " League "), exact_selection)
	_check(exact.ok and _row(exact, " Club ").points == 3,
		"identificadores exactos con espacios y mayúsculas")
	var wrong_case: Array[Result] = [
		_result(" exact fixture ", Result.Status.FINAL, 1, 0, " Exact Season ")
	]
	_expect_error(service.calculate(exact_clubs, exact_fixtures, wrong_case,
		_rules(3, 1, 0, " Exact Season ", " League "), exact_selection), "unknown_fixture")

	var duplicated = results.duplicate()
	duplicated.append(_result("home_win", Result.Status.FINAL, 2, 0))
	_expect_error(service.calculate(clubs, fixtures, duplicated, rules, selection),
		"duplicate_result")
	var unknown: Array[Result] = [_result("unknown", Result.Status.FINAL, 1, 0)]
	_expect_error(service.calculate(clubs, fixtures, unknown, rules, selection),
		"unknown_fixture")
	var wrong_season: Array[Result] = [
		_result("home_win", Result.Status.FINAL, 1, 0, "season_b")
	]
	_expect_error(service.calculate(clubs, fixtures, wrong_season, rules, selection),
		"season_mismatch")

	for field in ["home_goals", "away_goals"]:
		for value in [-1, -2, 1.5, "1", true, [], {}]:
			var invalid = _result("home_win", Result.Status.FINAL, 1, 0)
			invalid.set(field, value)
			_expect_error(service.calculate(clubs, fixtures, [invalid], rules, selection),
				"invalid_score")
	for scores in [[null, 0], [0, null], [null, null]]:
		var incomplete = _result("home_win", Result.Status.FINAL, scores[0], scores[1])
		_expect_error(service.calculate(clubs, fixtures, [incomplete], rules, selection),
			"missing_score")
	for scores in [[0, null], [null, 0], [0, 0]]:
		var pending_score = _result("home_win", Result.Status.PENDING, scores[0], scores[1])
		_expect_error(service.calculate(clubs, fixtures, [pending_score], rules, selection),
			"pending_with_score")
	var invalid_status = _result("home_win", 99, null, null)
	_expect_error(service.calculate(clubs, fixtures, [invalid_status], rules, selection),
		"invalid_status")

	for field in ["points_win", "points_draw", "points_loss"]:
		for value in [null, 1.5, "1", true, [], {}]:
			var invalid_rules = _rules(3, 1, 0)
			invalid_rules.set(field, value)
			var invalid = service.calculate(clubs, fixtures, results, invalid_rules, selection)
			_expect_error(invalid, "invalid_rules")
			_check(invalid.errors[0].get("field") == field, "campo de reglas inválido")
	var mismatched_rules = _rules(3, 1, 0, "season_b")
	_expect_error(service.calculate(clubs, fixtures, results, mismatched_rules, selection),
		"rules_mismatch")
	mismatched_rules = _rules(3, 1, 0, "season_a", "cup")
	_expect_error(service.calculate(clubs, fixtures, results, mismatched_rules, selection),
		"rules_mismatch")
	for format in [null, {}, {"kind": "knockout"}, {"kind": "unknown"}]:
		var invalid_rules = _rules(3, 1, 0)
		invalid_rules.competition_format = format
		_expect_error(service.calculate(clubs, fixtures, results, invalid_rules, selection),
			"unsupported_format")

	var missing_club_fixtures: Array[Fixture] = [
		_fixture("missing_club", "club_a", "missing")
	]
	var missing_club_results: Array[Result] = [
		_result("missing_club", Result.Status.FINAL, 1, 0)
	]
	_expect_error(service.calculate(clubs, missing_club_fixtures,
		missing_club_results, rules, selection), "missing_club_reference")
	var self_fixtures: Array[Fixture] = [_fixture("self", "club_a", "club_a")]
	_expect_error(service.calculate(clubs, self_fixtures, [], rules, selection), "self_match")

	var duplicate_clubs = clubs.duplicate()
	duplicate_clubs.append(_club("club_a"))
	_expect_error(service.calculate(duplicate_clubs, fixtures, results, rules, selection),
		"duplicate_club")
	var mismatched_clubs = clubs.duplicate()
	mismatched_clubs[0] = _club("club_a", "season_b")
	_expect_error(service.calculate(mismatched_clubs, fixtures, results, rules, selection),
		"season_mismatch")

	for field in ["season_id", "competition_id", "stage_id", "group_id"]:
		var missing_selection = selection.duplicate(true)
		missing_selection.erase(field)
		_expect_error(service.calculate(clubs, fixtures, results, rules, missing_selection),
			"missing_selection")

	var generated_clubs: Array[Club] = [
		_club("g1"), _club("g2"), _club("g3"), _club("g4")
	]
	var generated = Generator.new().generate(generated_clubs, {
		"format": "round_robin", "season_id": "season_a",
		"competition_id": "league", "stage_id": "regular",
		"group_id": null, "legs": 1,
	})
	_check(generated.ok, "calendario sintético generado")
	if generated.ok:
		var generated_results: Array[Result] = []
		for fixture in generated.data:
			generated_results.append(_result(fixture.fixture_id, Result.Status.FINAL, 1, 0))
		var generated_table = service.calculate(generated_clubs, generated.data,
			generated_results, rules, selection)
		_check(generated_table.ok, "integración con LeagueCalendarGenerator")
		if generated_table.ok:
			var total_played = 0
			for row in generated_table.data.rows:
				total_played += row.played
				_check(row.played == 3, "cada club completa la liga generada")
			_check(total_played == 12, "partidos jugados acumulados correctos")

	var repeated = service.calculate(clubs, fixtures, results, rules, selection)
	_check(calculated == repeated, "resultado determinista entre consultas")
	_check(_snapshot_clubs(clubs) == club_snapshot, "clubes sin modificar")
	_check(_snapshot_fixtures(fixtures) == fixture_snapshot, "partidos sin modificar")
	_check(_snapshot_results(results) == result_snapshot, "resultados sin modificar")
	_check(_snapshot_rules(rules) == rules_snapshot, "reglas sin modificar")
	_check(selection == selection_snapshot, "selección sin modificar")

	if failures.is_empty():
		print("PASS: %d comprobaciones" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)


func _club(club_id: String, season_id: String = "season_a") -> Club:
	var club = Club.new()
	club.club_id = club_id
	club.season_id = season_id
	club.division_id = "synthetic_division"
	return club


func _fixture(fixture_id: String, home_club_id: Variant, away_club_id: Variant,
		season_id: String = "season_a", competition_id: Variant = "league",
		stage_id: Variant = "regular", group_id: Variant = null) -> Fixture:
	var fixture = Fixture.new()
	fixture.fixture_id = fixture_id
	fixture.season_id = season_id
	fixture.competition_id = competition_id
	fixture.stage_id = stage_id
	fixture.group_id = group_id
	fixture.home_club_id = home_club_id
	fixture.away_club_id = away_club_id
	fixture.round_number = 1
	fixture.scheduled_date = null
	fixture.metadata = {"synthetic": true}
	return fixture


func _result(fixture_id: String, status: int, home_goals: Variant, away_goals: Variant,
		season_id: String = "season_a") -> Result:
	var result = Result.new()
	result.fixture_id = fixture_id
	result.season_id = season_id
	result.status = status
	result.home_goals = home_goals
	result.away_goals = away_goals
	return result


func _rules(points_win: int, points_draw: int, points_loss: int,
		season_id: String = "season_a", competition_id: String = "league") -> Rules:
	var rules = Rules.new()
	rules.season_id = season_id
	rules.competition_id = competition_id
	rules.points_win = points_win
	rules.points_draw = points_draw
	rules.points_loss = points_loss
	rules.team_count = null
	rules.round_count = null
	rules.tiebreakers = ["undefined_for_phase_1"]
	rules.substitution_rules = null
	rules.promotion_relegation_rules = null
	rules.competition_format = {"kind": "round_robin"}
	return rules


func _selection(season_id: String = "season_a", competition_id: String = "league",
		stage_id: Variant = "regular", group_id: Variant = null) -> Dictionary:
	return {
		"season_id": season_id,
		"competition_id": competition_id,
		"stage_id": stage_id,
		"group_id": group_id,
	}


func _row(calculated: Dictionary, club_id: String) -> Dictionary:
	for row in calculated.data.rows:
		if row.club_id == club_id:
			return row
	return {}


func _expect_row(row: Dictionary, position: int, club_id: String, played: int,
		wins: int, draws: int, losses: int, goals_for: int, goals_against: int,
		goal_difference: int, points: int) -> void:
	_check(row == {
		"club_id": club_id,
		"played": played,
		"wins": wins,
		"draws": draws,
		"losses": losses,
		"goals_for": goals_for,
		"goals_against": goals_against,
		"goal_difference": goal_difference,
		"points": points,
		"position": position,
	}, "fila completa " + club_id)


func _expect_error(calculated: Dictionary, code: String) -> void:
	_check(not calculated.ok and calculated.data == null, "fallo sin tabla parcial " + code)
	_check(calculated.errors.size() == 1, "un diagnóstico " + code)
	if not calculated.errors.is_empty():
		_check(calculated.errors[0].get("code") == code, "código " + code)
		_check(calculated.errors[0].get("message") is String
			and not calculated.errors[0].message.is_empty(), "mensaje " + code)


func _club_ids(rows: Array) -> Array[String]:
	var ids: Array[String] = []
	for row in rows:
		ids.append(row.club_id)
	return ids


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


func _snapshot_results(results: Array[Result]) -> Array[Dictionary]:
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


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
