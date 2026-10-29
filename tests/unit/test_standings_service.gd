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

	var goal_difference_only = service.calculate(clubs, fixtures, results,
		_rules(3, 1, 0, "season_a", "league", ["goal_difference"]), selection)
	_check(goal_difference_only.ok and goal_difference_only.data.provisional,
		"diferencia de goles insuficiente conserva empate")
	_check(goal_difference_only.data.unresolved_ties == [["club_b", "club_c"]],
		"empate persistente tras criterio disponible")
	_check(goal_difference_only.data.tiebreakers_applied == ["goal_difference"],
		"criterio aplicado informado")
	var goals_for = service.calculate(clubs, fixtures, results,
		_rules(3, 1, 0, "season_a", "league", ["goals_for"]), selection)
	_check(goals_for.ok and _club_ids(goals_for.data.rows)
		== ["club_a", "club_c", "club_b", "club_d"],
		"desempate por goles a favor")
	_check(not goals_for.data.provisional and goals_for.data.unresolved_ties.is_empty(),
		"primer criterio resuelve el empate")
	var second_criterion = service.calculate(clubs, fixtures, results,
		_rules(3, 1, 0, "season_a", "league",
			["goal_difference", "goals_for"]), selection)
	_check(second_criterion.ok and _club_ids(second_criterion.data.rows)
		== ["club_a", "club_c", "club_b", "club_d"],
		"segundo criterio resuelve el empate")
	_check(second_criterion.data.tiebreakers_applied
		== ["goal_difference", "goals_for"], "prioridad declarada informada")

	var priority_clubs: Array[Club] = [
		_club("priority_a"), _club("priority_b"), _club("opponent_x"), _club("opponent_y")
	]
	var priority_fixtures: Array[Fixture] = [
		_fixture("priority_a_match", "priority_a", "opponent_x"),
		_fixture("priority_b_match", "priority_b", "opponent_y"),
	]
	var priority_results: Array[Result] = [
		_result("priority_a_match", Result.Status.FINAL, 2, 0),
		_result("priority_b_match", Result.Status.FINAL, 4, 3),
	]
	var difference_first_rules = _rules(3, 1, 0, "season_a", "league",
		["goal_difference", "goals_for"])
	var difference_first_snapshot = _snapshot_rules(difference_first_rules)
	var difference_first = service.calculate(priority_clubs, priority_fixtures,
		priority_results, difference_first_rules, selection)
	var goals_first = service.calculate(priority_clubs, priority_fixtures, priority_results,
		_rules(3, 1, 0, "season_a", "league", ["goals_for", "goal_difference"]), selection)
	_check(difference_first.ok and _index_of(difference_first, "priority_a")
		< _index_of(difference_first, "priority_b"), "diferencia de goles con mayor prioridad")
	_check(goals_first.ok and _index_of(goals_first, "priority_b")
		< _index_of(goals_first, "priority_a"), "cambiar prioridad cambia la clasificación")
	_check(difference_first.data.tiebreakers_applied == ["goal_difference", "goals_for"]
		and goals_first.data.tiebreakers_applied == ["goals_for", "goal_difference"],
		"orden exacto de criterios conservado")
	_check(_snapshot_rules(difference_first_rules) == difference_first_snapshot,
		"criterios configurados sin modificar")
	_check(difference_first == service.calculate(priority_clubs, priority_fixtures,
		priority_results, difference_first_rules, selection),
		"desempate configurado determinista")

	var wins_clubs: Array[Club] = [
		_club("wins_a"), _club("wins_b"), _club("wins_c"),
		_club("wins_d"), _club("wins_e"), _club("wins_idle")
	]
	var wins_fixtures: Array[Fixture] = [
		_fixture("wins_a_match", "wins_a", "wins_c"),
		_fixture("wins_b_draw_c", "wins_b", "wins_c"),
		_fixture("wins_b_draw_d", "wins_b", "wins_d"),
		_fixture("wins_b_draw_e", "wins_b", "wins_e"),
		_fixture("wins_pending", "wins_a", "wins_idle"),
	]
	var wins_results: Array[Result] = [
		_result("wins_a_match", Result.Status.FINAL, 1, 0),
		_result("wins_b_draw_c", Result.Status.FINAL, 0, 0),
		_result("wins_b_draw_d", Result.Status.FINAL, 1, 1),
		_result("wins_b_draw_e", Result.Status.FINAL, 2, 2),
		_result("wins_pending", Result.Status.PENDING, null, null),
	]
	var wins_table = service.calculate(wins_clubs, wins_fixtures, wins_results,
		_rules(3, 1, 0, "season_a", "league", ["wins"]), selection)
	_check(wins_table.ok and _index_of(wins_table, "wins_a")
		< _index_of(wins_table, "wins_b"), "desempate por número de victorias")
	_check(_row(wins_table, "wins_a").points == _row(wins_table, "wins_b").points
		and _row(wins_table, "wins_a").wins == 1
		and _row(wins_table, "wins_b").wins == 0, "victorias comparadas tras puntos")
	_check(_row(wins_table, "wins_idle").played == 0,
		"pendiente y club sin partidos no alteran criterios")

	var three_clubs: Array[Club] = [
		_club("three_a"), _club("three_b"), _club("three_c"),
		_club("three_x"), _club("three_y"), _club("three_z")
	]
	var three_fixtures: Array[Fixture] = [
		_fixture("three_a_match", "three_a", "three_x"),
		_fixture("three_b_match", "three_b", "three_y"),
		_fixture("three_c_match", "three_c", "three_z"),
	]
	var three_results: Array[Result] = [
		_result("three_a_match", Result.Status.FINAL, 2, 0),
		_result("three_b_match", Result.Status.FINAL, 3, 1),
		_result("three_c_match", Result.Status.FINAL, 1, 0),
	]
	var three_table = service.calculate(three_clubs, three_fixtures, three_results,
		_rules(3, 1, 0, "season_a", "league",
			["goal_difference", "goals_for"]), selection)
	_check(three_table.ok and _club_ids(three_table.data.rows).slice(0, 3)
		== ["three_b", "three_a", "three_c"],
		"tres clubes inicialmente empatados se resuelven por prioridades")

	var group_clubs: Array[Club] = [
		_club("group_a"), _club("group_b"), _club("group_c"), _club("group_d")
	]
	var group_fixtures: Array[Fixture] = [
		_fixture("group_a_match", "group_a", "group_c"),
		_fixture("group_b_match", "group_b", "group_d"),
	]
	var group_results: Array[Result] = [
		_result("group_a_match", Result.Status.FINAL, 1, 0),
		_result("group_b_match", Result.Status.FINAL, 1, 0),
	]
	var group_table = service.calculate(group_clubs, group_fixtures, group_results,
		_rules(3, 1, 0, "season_a", "league",
			["goal_difference", "goals_for", "wins"]), selection)
	_check(group_table.ok and group_table.data.provisional,
		"empates persisten tras todos los criterios")
	_check(group_table.data.unresolved_ties
		== [["group_a", "group_b"], ["group_c", "group_d"]],
		"grupos de desempate independientes")
	_check([_row(group_table, "group_a").position, _row(group_table, "group_b").position,
		_row(group_table, "group_c").position, _row(group_table, "group_d").position]
		== [1, 1, 3, 3], "posiciones compartidas numeradas correctamente")

	_run_head_to_head_checks(service, selection)

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
	var null_tiebreakers = _rules(3, 1, 0)
	null_tiebreakers.tiebreakers = null
	_expect_error(service.calculate(clubs, fixtures, results, null_tiebreakers, selection),
		"invalid_tiebreakers")
	for value in ["goal_difference", 1, true, {}]:
		var invalid_tiebreakers = _rules(3, 1, 0)
		invalid_tiebreakers.tiebreakers = value
		_expect_error(service.calculate(clubs, fixtures, results,
			invalid_tiebreakers, selection), "invalid_tiebreakers")
	for value in [1, true, {}]:
		var invalid_element = _rules(3, 1, 0)
		invalid_element.tiebreakers = [value]
		_expect_error(service.calculate(clubs, fixtures, results,
			invalid_element, selection), "invalid_tiebreaker")
	for criterion in ["Goal_Difference", "goal_diff", "head_to_head", "unknown"]:
		var unknown_tiebreaker = _rules(3, 1, 0)
		unknown_tiebreaker.tiebreakers = [criterion]
		var unknown_error = service.calculate(clubs, fixtures, results,
			unknown_tiebreaker, selection)
		_expect_error(unknown_error, "unknown_tiebreaker")
		_check(unknown_error.errors[0].get("criterion") == criterion,
			"criterio desconocido exacto")
	var duplicate_tiebreaker = _rules(3, 1, 0)
	duplicate_tiebreaker.tiebreakers = ["wins", "wins"]
	var duplicate_error = service.calculate(clubs, fixtures, results,
		duplicate_tiebreaker, selection)
	_expect_error(duplicate_error, "duplicate_tiebreaker")
	_check(duplicate_error.errors[0].get("index") == 1
		and duplicate_error.errors[0].get("first_index") == 0
		and duplicate_error.errors[0].get("criterion") == "wins",
		"criterio duplicado localizable")

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


func _run_head_to_head_checks(service: Service, selection: Dictionary) -> void:
	var direct_clubs: Array[Club] = [
		_club("direct_a"), _club("direct_b"), _club("direct_x"), _club("direct_y")
	]
	var direct_fixtures: Array[Fixture] = [
		_fixture("direct_ab", "direct_a", "direct_b"),
		_fixture("direct_bx", "direct_b", "direct_x"),
		_fixture("direct_ya", "direct_y", "direct_a"),
		_fixture("direct_yx", "direct_y", "direct_x"),
	]
	var direct_results: Array[Result] = [
		_result("direct_ab", Result.Status.FINAL, 1, 0),
		_result("direct_bx", Result.Status.FINAL, 1, 0),
		_result("direct_ya", Result.Status.FINAL, 1, 0),
		_result("direct_yx", Result.Status.FINAL, 1, 0),
	]
	var direct_rules = _direct_rules(3, 1, 0, ["head_to_head_points"], 1)
	var direct_table = service.calculate(direct_clubs, direct_fixtures,
		direct_results, direct_rules, selection)
	_check(direct_table.ok and _index_of(direct_table, "direct_a")
		< _index_of(direct_table, "direct_b"),
		"dos clubes resueltos por puntos directos")
	_check(_row(direct_table, "direct_a").points == _row(direct_table, "direct_b").points,
		"los puntos generales siguen siendo el criterio principal")
	_check(direct_table.data.pending_tiebreakers.is_empty()
		and not direct_table.data.provisional,
		"una vuelta explícita certifica un único partido directo")
	_check(direct_table.data.tiebreakers_applied == ["head_to_head_points"],
		"criterio directo aplicado informado")

	var legacy_rules = _rules(3, 1, 0, "season_a", "league",
		["head_to_head_points"])
	var legacy_table = service.calculate(direct_clubs, direct_fixtures,
		direct_results, legacy_rules, selection)
	_check(legacy_table.ok and _index_of(legacy_table, "direct_a")
		< _index_of(legacy_table, "direct_b"),
		"configuración antigua conserva un orden directo informativo")
	_check(legacy_table.data.provisional and _pending_reasons(legacy_table) == [
		"unknown_legs", "unknown_head_to_head_policy"
	], "atributos ausentes conservan clasificación provisional")
	var explicit_null = service.calculate(direct_clubs, direct_fixtures,
		direct_results, _direct_rules(3, 1, 0, ["head_to_head_points"], null, null),
		selection)
	_check(explicit_null.ok and _pending_reasons(explicit_null) == [
		"unknown_legs", "unknown_head_to_head_policy"
	], "atributos null representan información no documentada")
	var unknown_legs_rules = _direct_rules(3, 1, 0,
		["head_to_head_points"], null)
	var unknown_legs = service.calculate(direct_clubs, direct_fixtures,
		direct_results, unknown_legs_rules, selection)
	_check(_pending_reasons(unknown_legs) == ["unknown_legs"]
		and unknown_legs.data.provisional,
		"vueltas desconocidas se diagnostican sin inferencias")
	var unknown_policy_rules = _rules(3, 1, 0, "season_a", "league",
		["head_to_head_points"])
	unknown_policy_rules.competition_format["legs"] = 1
	var unknown_policy = service.calculate(direct_clubs, direct_fixtures,
		direct_results, unknown_policy_rules, selection)
	_check(_pending_reasons(unknown_policy) == ["unknown_head_to_head_policy"]
		and unknown_policy.data.provisional,
		"política ausente conserva desempate provisional")

	var aggregate_clubs: Array[Club] = [_club("aggregate_a"), _club("aggregate_b")]
	var aggregate_fixtures: Array[Fixture] = [
		_fixture("aggregate_first", "aggregate_a", "aggregate_b"),
		_fixture("aggregate_second", "aggregate_b", "aggregate_a"),
	]
	var aggregate_results: Array[Result] = [
		_result("aggregate_first", Result.Status.FINAL, 3, 0),
		_result("aggregate_second", Result.Status.FINAL, 1, 0),
	]
	var aggregate_table = service.calculate(aggregate_clubs, aggregate_fixtures,
		aggregate_results, _direct_rules(3, 1, 0, [
			"head_to_head_points", "head_to_head_goal_difference"
		], 2), selection)
	_check(aggregate_table.ok and _index_of(aggregate_table, "aggregate_a")
		< _index_of(aggregate_table, "aggregate_b"),
		"diferencia de goles directa decide tras puntos directos empatados")
	_check(not aggregate_table.data.provisional,
		"serie completa resuelve definitivamente el empate")
	var aggregate_goals = service.calculate(aggregate_clubs, aggregate_fixtures,
		aggregate_results, _direct_rules(3, 1, 0, [
			"head_to_head_points", "head_to_head_goals_for"
		], 2), selection)
	_check(aggregate_goals.ok and _index_of(aggregate_goals, "aggregate_a")
		< _index_of(aggregate_goals, "aggregate_b"),
		"goles a favor directos admitidos")

	var single_leg_duplicate = service.calculate(aggregate_clubs, aggregate_fixtures,
		aggregate_results, _direct_rules(3, 1, 0, ["head_to_head_points"], 1),
		selection)
	_expect_pending(single_leg_duplicate, "incomplete_calendar", [])
	_check(single_leg_duplicate.data.unresolved_ties
		== [["aggregate_a", "aggregate_b"]],
		"una vuelta rechaza encuentros duplicados")
	var missing_second_leg_fixtures: Array[Fixture] = [aggregate_fixtures[0]]
	var missing_second_leg_results: Array[Result] = [
		_result("aggregate_first", Result.Status.FINAL, 1, 1)
	]
	var missing_second_leg = service.calculate(aggregate_clubs,
		missing_second_leg_fixtures, missing_second_leg_results,
		_direct_rules(3, 1, 0, ["head_to_head_points"], 2), selection)
	_expect_pending(missing_second_leg, "incomplete_calendar", [])
	var missing_meetings = missing_second_leg.data.pending_tiebreakers[0]
	_check(missing_meetings.expected_legs == 2
		and missing_meetings.observed_meetings[0].total == 1,
		"diagnóstico precisa vueltas esperadas y encuentros observados")
	var duplicate_home_fixtures: Array[Fixture] = [
		_fixture("duplicate_home_1", "aggregate_a", "aggregate_b"),
		_fixture("duplicate_home_2", "aggregate_a", "aggregate_b"),
	]
	var duplicate_home_results: Array[Result] = [
		_result("duplicate_home_1", Result.Status.FINAL, 1, 0),
		_result("duplicate_home_2", Result.Status.FINAL, 0, 1),
	]
	var duplicate_home = service.calculate(aggregate_clubs, duplicate_home_fixtures,
		duplicate_home_results, _direct_rules(3, 1, 0,
			["head_to_head_points"], 2), selection)
	_expect_pending(duplicate_home, "incomplete_calendar", [])
	var duplicate_home_diagnostic = duplicate_home.data.pending_tiebreakers[0]
	_check(duplicate_home_diagnostic.observed_meetings[0].first_home == 2
		and duplicate_home_diagnostic.observed_meetings[0].second_home == 0,
		"doble vuelta detecta localía duplicada")

	var mini_clubs: Array[Club] = [
		_club("mini_a"), _club("mini_b"), _club("mini_c"), _club("mini_e")
	]
	var mini_fixtures: Array[Fixture] = [
		_fixture("mini_ab", "mini_a", "mini_b"),
		_fixture("mini_ba", "mini_b", "mini_a"),
		_fixture("mini_ac", "mini_a", "mini_c"),
		_fixture("mini_ca", "mini_c", "mini_a"),
		_fixture("mini_bc", "mini_b", "mini_c"),
		_fixture("mini_cb", "mini_c", "mini_b"),
		_fixture("mini_be_1", "mini_b", "mini_e"),
		_fixture("mini_be_2", "mini_b", "mini_e"),
		_fixture("mini_ce_1", "mini_c", "mini_e"),
		_fixture("mini_ce_2", "mini_c", "mini_e"),
		_fixture("mini_ce_3", "mini_c", "mini_e"),
		_fixture("mini_ce_4", "mini_c", "mini_e"),
	]
	var mini_results: Array[Result] = [
		_result("mini_ab", Result.Status.FINAL, 1, 0),
		_result("mini_ba", Result.Status.FINAL, 0, 1),
		_result("mini_ac", Result.Status.FINAL, 1, 0),
		_result("mini_ca", Result.Status.FINAL, 0, 1),
		_result("mini_bc", Result.Status.FINAL, 1, 0),
		_result("mini_cb", Result.Status.FINAL, 0, 1),
		_result("mini_be_1", Result.Status.FINAL, 1, 0),
		_result("mini_be_2", Result.Status.FINAL, 1, 0),
		_result("mini_ce_1", Result.Status.FINAL, 1, 0),
		_result("mini_ce_2", Result.Status.FINAL, 1, 0),
		_result("mini_ce_3", Result.Status.FINAL, 1, 0),
		_result("mini_ce_4", Result.Status.FINAL, 1, 0),
	]
	var mini_table = service.calculate(mini_clubs, mini_fixtures, mini_results,
		_direct_rules(3, 1, 0, ["head_to_head_points"], 2), selection)
	_check(mini_table.ok and _club_ids(mini_table.data.rows).slice(0, 3)
		== ["mini_a", "mini_b", "mini_c"],
		"mini-liga completa de tres clubes usa solo resultados internos")
	_check(_row(mini_table, "mini_a").points == _row(mini_table, "mini_b").points
		and _row(mini_table, "mini_b").points == _row(mini_table, "mini_c").points,
		"mini-liga parte de un empate general real")
	_check(mini_table.data.pending_tiebreakers.is_empty(),
		"mini-liga recíproca de tres clubes queda certificada")

	var four_clubs: Array[Club] = [
		_club("four_d"), _club("four_b"), _club("four_a"), _club("four_c")
	]
	var four_fixtures: Array[Fixture] = []
	var four_results: Array[Result] = []
	var four_ids = ["four_a", "four_b", "four_c", "four_d"]
	for left_index in four_ids.size():
		for right_index in range(left_index + 1, four_ids.size()):
			var first_fixture_id = "four_%d_%d_first" % [left_index, right_index]
			var second_fixture_id = "four_%d_%d_second" % [left_index, right_index]
			four_fixtures.append(_fixture(first_fixture_id,
				four_ids[left_index], four_ids[right_index]))
			four_fixtures.append(_fixture(second_fixture_id,
				four_ids[right_index], four_ids[left_index]))
			four_results.append(_result(first_fixture_id, Result.Status.FINAL, 0, 0))
			four_results.append(_result(second_fixture_id, Result.Status.FINAL, 0, 0))
	var four_table = service.calculate(four_clubs, four_fixtures, four_results,
		_direct_rules(3, 1, 0, [
			"head_to_head_points", "head_to_head_goal_difference",
			"head_to_head_goals_for"
		], 2), selection)
	_check(four_table.ok and four_table.data.unresolved_ties == [four_ids],
		"mini-liga de cuatro conserva empate deportivo persistente")
	_check(_club_ids(four_table.data.rows) == four_ids,
		"club_id solo ordena visualmente el empate de cuatro")
	_check(four_table.data.pending_tiebreakers.is_empty(),
		"mini-liga recíproca de cuatro clubes queda certificada")
	_check([_row(four_table, "four_a").position, _row(four_table, "four_b").position,
		_row(four_table, "four_c").position, _row(four_table, "four_d").position]
		== [1, 1, 1, 1], "cuatro clubes conservan posición compartida")

	var priority_clubs: Array[Club] = [
		_club("order_a"), _club("order_b"), _club("order_x"), _club("order_y")
	]
	var priority_fixtures: Array[Fixture] = [
		_fixture("order_ab", "order_a", "order_b"),
		_fixture("order_bx", "order_b", "order_x"),
		_fixture("order_ya", "order_y", "order_a"),
		_fixture("order_yx", "order_y", "order_x"),
	]
	var priority_results: Array[Result] = [
		_result("order_ab", Result.Status.FINAL, 1, 0),
		_result("order_bx", Result.Status.FINAL, 10, 0),
		_result("order_ya", Result.Status.FINAL, 1, 0),
		_result("order_yx", Result.Status.FINAL, 1, 0),
	]
	var direct_first = service.calculate(priority_clubs, priority_fixtures, priority_results,
		_direct_rules(3, 1, 0, [
			"head_to_head_points", "goal_difference"
		], 1), selection)
	var general_first = service.calculate(priority_clubs, priority_fixtures, priority_results,
		_direct_rules(3, 1, 0, [
			"goal_difference", "head_to_head_points"
		], 1), selection)
	_check(_index_of(direct_first, "order_a") < _index_of(direct_first, "order_b")
		and _index_of(general_first, "order_b") < _index_of(general_first, "order_a"),
		"el orden declarado entre criterios directos y generales cambia el resultado")

	for points_win in [2, 3]:
		var configured = service.calculate(direct_clubs, direct_fixtures, direct_results,
			_direct_rules(points_win, 1, 0, ["head_to_head_points"], 1),
			selection)
		_check(configured.ok and _index_of(configured, "direct_a")
			< _index_of(configured, "direct_b"),
			"puntos directos respetan %d puntos por victoria" % points_win)

	var pending_clubs: Array[Club] = [_club("pending_a"), _club("pending_b")]
	var pending_fixtures: Array[Fixture] = [
		_fixture("pending_direct", "pending_a", "pending_b")
	]
	var pending_rules = _direct_rules(3, 1, 0, ["head_to_head_points"], 1)
	var pending_result = service.calculate(pending_clubs, pending_fixtures,
		[_result("pending_direct", Result.Status.PENDING, null, null)],
		pending_rules, selection)
	_check(pending_result.ok and pending_result.data.provisional,
		"partido directo pendiente mantiene resultado válido y provisional")
	_expect_pending(pending_result, "pending_results", ["pending_direct"])
	_check(pending_result.data.unresolved_ties == [["pending_a", "pending_b"]],
		"partido pendiente no decide posiciones deportivas")
	var missing_result = service.calculate(pending_clubs, pending_fixtures, [],
		pending_rules, selection)
	_expect_pending(missing_result, "missing_results", ["pending_direct"])
	_check(missing_result.data.provisional,
		"partido sin registro de resultado mantiene tabla provisional")
	var pending_double_results: Array[Result] = [
		_result("aggregate_first", Result.Status.PENDING, null, null),
		_result("aggregate_second", Result.Status.PENDING, null, null),
	]
	var pending_double = service.calculate(aggregate_clubs, aggregate_fixtures,
		pending_double_results, _direct_rules(3, 1, 0,
			["head_to_head_points"], 2), selection)
	_expect_pending(pending_double, "pending_results",
		["aggregate_first", "aggregate_second"])
	_check(pending_double.data.unresolved_ties == [["aggregate_a", "aggregate_b"]],
		"doble vuelta pendiente no aplica resultados parciales")

	var incomplete_fixtures: Array[Fixture] = aggregate_fixtures.duplicate()
	var incomplete_results: Array[Result] = [
		_result("aggregate_first", Result.Status.FINAL, 1, 1)
	]
	var incomplete_double = service.calculate(aggregate_clubs, incomplete_fixtures,
		incomplete_results, _direct_rules(3, 1, 0, [
			"head_to_head_points", "head_to_head_goal_difference"
		], 2), selection)
	_expect_pending(incomplete_double, "missing_results", ["aggregate_second"])
	_check(incomplete_double.data.unresolved_ties
		== [["aggregate_a", "aggregate_b"]],
		"doble vuelta incompleta no utiliza marcadores parciales")

	var uneven_clubs: Array[Club] = [_club("uneven_a"), _club("uneven_b"), _club("uneven_c")]
	var uneven_fixtures: Array[Fixture] = [
		_fixture("uneven_ab", "uneven_a", "uneven_b"),
		_fixture("uneven_ac", "uneven_a", "uneven_c"),
	]
	var uneven_results: Array[Result] = [
		_result("uneven_ab", Result.Status.FINAL, 0, 0),
		_result("uneven_ac", Result.Status.FINAL, 0, 0),
	]
	var uneven = service.calculate(uneven_clubs, uneven_fixtures, uneven_results,
		pending_rules, selection)
	_expect_pending(uneven, "incomplete_calendar", [])
	_check(uneven.data.provisional, "calendario incompleto no certifica la mini-liga")

	for invalid_legs in [-1, 0, 3, 1.5, "1", true, [], {}]:
		var invalid_legs_rules = _rules(3, 1, 0)
		invalid_legs_rules.competition_format["legs"] = invalid_legs
		_expect_error(service.calculate(direct_clubs, direct_fixtures,
			direct_results, invalid_legs_rules, selection), "invalid_legs")
	for invalid_policy in [1, true, [], {}]:
		var invalid_policy_rules = _rules(3, 1, 0)
		invalid_policy_rules.competition_format["head_to_head_policy"] = invalid_policy
		_expect_error(service.calculate(direct_clubs, direct_fixtures,
			direct_results, invalid_policy_rules, selection),
			"invalid_head_to_head_policy")
	for unsupported_policy in ["restart", "recursive", "Single_Pass", ""]:
		var unsupported_policy_rules = _rules(3, 1, 0)
		unsupported_policy_rules.competition_format["head_to_head_policy"] = \
			unsupported_policy
		var unsupported = service.calculate(direct_clubs, direct_fixtures,
			direct_results, unsupported_policy_rules, selection)
		_expect_error(unsupported, "unsupported_head_to_head_policy")
		_check(unsupported.errors[0].get("policy") == unsupported_policy,
			"política desconocida exacta en diagnóstico")

	var subgroup_clubs: Array[Club] = [
		_club("sub_a"), _club("sub_b"), _club("sub_c"),
		_club("sub_x"), _club("sub_y")
	]
	var subgroup_fixtures: Array[Fixture] = [
		_fixture("sub_ba_1", "sub_b", "sub_a"),
		_fixture("sub_ba_2", "sub_b", "sub_a"),
		_fixture("sub_ba_3", "sub_b", "sub_a"),
		_fixture("sub_ac_1", "sub_a", "sub_c"),
		_fixture("sub_ac_2", "sub_a", "sub_c"),
		_fixture("sub_ac_3", "sub_a", "sub_c"),
		_fixture("sub_bc_1", "sub_b", "sub_c"),
		_fixture("sub_cb_2", "sub_c", "sub_b"),
		_fixture("sub_cb_3", "sub_c", "sub_b"),
		_fixture("sub_ax", "sub_a", "sub_x"),
		_fixture("sub_ay", "sub_a", "sub_y"),
		_fixture("sub_cx", "sub_c", "sub_x"),
		_fixture("sub_cy", "sub_c", "sub_y"),
	]
	var subgroup_results: Array[Result] = [
		_result("sub_ba_1", Result.Status.FINAL, 2, 0),
		_result("sub_ba_2", Result.Status.FINAL, 0, 0),
		_result("sub_ba_3", Result.Status.FINAL, 0, 0),
		_result("sub_ac_1", Result.Status.FINAL, 4, 0),
		_result("sub_ac_2", Result.Status.FINAL, 0, 0),
		_result("sub_ac_3", Result.Status.FINAL, 0, 0),
		_result("sub_bc_1", Result.Status.FINAL, 1, 0),
		_result("sub_cb_2", Result.Status.FINAL, 0, 1),
		_result("sub_cb_3", Result.Status.FINAL, 5, 0),
		_result("sub_ax", Result.Status.FINAL, 1, 0),
		_result("sub_ay", Result.Status.FINAL, 0, 0),
		_result("sub_cx", Result.Status.FINAL, 1, 0),
		_result("sub_cy", Result.Status.FINAL, 1, 0),
	]
	var subgroup_table = service.calculate(subgroup_clubs, subgroup_fixtures,
		subgroup_results, _direct_rules(3, 1, 0, [
			"head_to_head_goal_difference", "head_to_head_points"
		], null), selection)
	_check(subgroup_table.ok and _club_ids(subgroup_table.data.rows).slice(0, 3)
		== ["sub_a", "sub_b", "sub_c"],
		"criterios posteriores se aplican al subgrupo que continúa empatado")
	_check(_index_of(subgroup_table, "sub_b") < _index_of(subgroup_table, "sub_c"),
		"la mini-liga del subgrupo no reinicia el criterio anterior")

	var scoped_fixtures: Array[Fixture] = direct_fixtures.duplicate()
	scoped_fixtures.append(_fixture("scope_other_stage", "direct_b", "direct_a",
		"season_a", "league", "other_stage", null))
	scoped_fixtures.append(_fixture("scope_other_group", "direct_b", "direct_a",
		"season_a", "league", "regular", "other_group"))
	scoped_fixtures.append(_fixture("scope_other_competition", "direct_b", "direct_a",
		"season_a", "cup", "regular", null))
	scoped_fixtures.append(_fixture("scope_other_season", "direct_b", "direct_a",
		"season_b", "league", "regular", null))
	var scoped = service.calculate(direct_clubs, scoped_fixtures, direct_results,
		direct_rules, selection)
	_check(scoped.ok and _index_of(scoped, "direct_a") < _index_of(scoped, "direct_b"),
		"mini-liga separa exactamente temporada competición fase y grupo")

	var direct_duplicate = _direct_rules(3, 1, 0, [
		"head_to_head_points", "head_to_head_points"
	], 1)
	_expect_error(service.calculate(direct_clubs, direct_fixtures, direct_results,
		direct_duplicate, selection), "duplicate_tiebreaker")
	var empty_fixture = _fixture("", "direct_a", "direct_b")
	_expect_error(service.calculate(direct_clubs, [empty_fixture], [], direct_rules, selection),
		"invalid_fixture")

	var club_snapshot = _snapshot_clubs(direct_clubs)
	var fixture_snapshot = _snapshot_fixtures(direct_fixtures)
	var result_snapshot = _snapshot_results(direct_results)
	var rules_snapshot = _snapshot_rules(direct_rules)
	var permuted_clubs: Array[Club] = direct_clubs.duplicate()
	var permuted_fixtures: Array[Fixture] = direct_fixtures.duplicate()
	var permuted_results: Array[Result] = direct_results.duplicate()
	permuted_clubs.reverse()
	permuted_fixtures.reverse()
	permuted_results.reverse()
	var permuted = service.calculate(permuted_clubs, permuted_fixtures,
		permuted_results, direct_rules, selection)
	_check(permuted == direct_table, "desempate directo determinista ante permutaciones")
	var permuted_legacy = service.calculate(permuted_clubs, permuted_fixtures,
		permuted_results, legacy_rules, selection)
	_check(permuted_legacy == legacy_table,
		"diagnósticos de reglas desconocidas deterministas ante permutaciones")
	_check(_snapshot_clubs(direct_clubs) == club_snapshot, "mini-liga no modifica clubes")
	_check(_snapshot_fixtures(direct_fixtures) == fixture_snapshot,
		"mini-liga no modifica calendario")
	_check(_snapshot_results(direct_results) == result_snapshot,
		"mini-liga no modifica resultados")
	_check(_snapshot_rules(direct_rules) == rules_snapshot,
		"mini-liga no modifica reglas")

	var generated_clubs: Array[Club] = [
		_club("head_g1"), _club("head_g2"), _club("head_g3"), _club("head_g4")
	]
	for generated_legs in [1, 2]:
		var generated = Generator.new().generate(generated_clubs, {
			"format": "round_robin", "season_id": "season_a",
			"competition_id": "league", "stage_id": "regular",
			"group_id": null, "legs": generated_legs,
		})
		_check(generated.ok,
			"calendario de %d vuelta(s) generado para mini-liga" % generated_legs)
		if generated.ok:
			var generated_results: Array[Result] = []
			for fixture in generated.data:
				generated_results.append(
					_result(fixture.fixture_id, Result.Status.FINAL, 0, 0)
				)
			var generated_table = service.calculate(generated_clubs, generated.data,
				generated_results, _direct_rules(3, 1, 0, [
					"head_to_head_points", "head_to_head_goal_difference"
				], generated_legs), selection)
			_check(generated_table.ok
				and generated_table.data.pending_tiebreakers.is_empty(),
				"integración directa con LeagueCalendarGenerator para %d vuelta(s)"
					% generated_legs)
			_check(generated_table.data.unresolved_ties.size() == 1
				and generated_table.data.unresolved_ties[0].size() == 4,
				"calendario generado conserva empate compartido real")


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
		season_id: String = "season_a", competition_id: String = "league",
		tiebreakers: Variant = []) -> Rules:
	var rules = Rules.new()
	rules.season_id = season_id
	rules.competition_id = competition_id
	rules.points_win = points_win
	rules.points_draw = points_draw
	rules.points_loss = points_loss
	rules.team_count = null
	rules.round_count = null
	rules.tiebreakers = tiebreakers.duplicate() if tiebreakers is Array else tiebreakers
	rules.substitution_rules = null
	rules.promotion_relegation_rules = null
	rules.competition_format = {"kind": "round_robin"}
	return rules


func _direct_rules(points_win: int, points_draw: int, points_loss: int,
		tiebreakers: Array, legs: Variant,
		head_to_head_policy: Variant = "single_pass") -> Rules:
	var rules = _rules(points_win, points_draw, points_loss,
		"season_a", "league", tiebreakers)
	rules.competition_format["legs"] = legs
	rules.competition_format["head_to_head_policy"] = head_to_head_policy
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


func _index_of(calculated: Dictionary, club_id: String) -> int:
	for index in calculated.data.rows.size():
		if calculated.data.rows[index].club_id == club_id:
			return index
	return -1


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


func _expect_pending(calculated: Dictionary, reason: String,
		fixture_ids: Array[String]) -> void:
	_check(calculated.ok and calculated.errors.is_empty(),
		"desempate pendiente conserva resultado válido " + reason)
	_check(calculated.data.pending_tiebreakers.size() >= 1,
		"diagnóstico informativo de desempate " + reason)
	if calculated.data.pending_tiebreakers.size() >= 1:
		var diagnostic = calculated.data.pending_tiebreakers[0]
		_check(diagnostic.get("code") == "pending_head_to_head_tiebreaker",
			"código informativo de desempate pendiente")
		_check(diagnostic.get("reason") == reason,
			"motivo de desempate pendiente " + reason)
		_check(diagnostic.get("fixture_ids") == fixture_ids,
			"partidos pendientes deterministas " + reason)
		if reason == "pending_results":
			_check(diagnostic.get("pending_result_fixture_ids") == fixture_ids
				and diagnostic.get("missing_result_fixture_ids") == [],
				"resultados pendientes diferenciados de resultados ausentes")
		elif reason == "missing_results":
			_check(diagnostic.get("missing_result_fixture_ids") == fixture_ids
				and diagnostic.get("pending_result_fixture_ids") == [],
				"resultados ausentes diferenciados de resultados pendientes")
		_check(diagnostic.get("club_ids") is Array
			and diagnostic.club_ids.size() >= 2,
			"grupo localizable en desempate pendiente")


func _pending_reasons(calculated: Dictionary) -> Array[String]:
	var reasons: Array[String] = []
	for diagnostic in calculated.data.pending_tiebreakers:
		reasons.append(diagnostic.reason)
	return reasons


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
