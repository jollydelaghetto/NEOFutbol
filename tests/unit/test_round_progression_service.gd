extends SceneTree

const Service = preload("res://game/scripts/services/round_progression_service.gd")
const Calendar = preload("res://game/scripts/services/calendar_service.gd")
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
	var selection = _selection()
	var rules = _rules(3, 1, 0, 1)
	var generated = Generator.new().generate(clubs, {
		"format": "round_robin",
		"season_id": selection.season_id,
		"competition_id": selection.competition_id,
		"stage_id": selection.stage_id,
		"group_id": selection.group_id,
		"legs": 1,
	})
	_check(generated.ok, "calendario base generado")
	if not generated.ok:
		_finish()
		return
	var fixtures: Array[Fixture] = []
	for fixture in generated.data:
		fixtures.append(fixture)
	var round_one = Calendar.new().get_round_fixtures(fixtures,
		selection.season_id, 1, _filters(selection), Calendar.Order.FIXTURE_ID)
	var round_two = Calendar.new().get_round_fixtures(fixtures,
		selection.season_id, 2, _filters(selection), Calendar.Order.FIXTURE_ID)
	_check(round_one.size() == 2 and round_two.size() == 2,
		"liga de cuatro clubes produce dos partidos por jornada")
	var incoming: Array[Result] = [
		_result(round_one[1].fixture_id, Result.Status.FINAL, 1, 1),
		_result(round_one[0].fixture_id, Result.Status.FINAL, 2, 0),
	]
	var club_snapshot = _snapshot_clubs(clubs)
	var fixture_snapshot = _snapshot_fixtures(fixtures)
	var incoming_snapshot = _snapshot_results(incoming)
	var rules_snapshot = _snapshot_rules(rules)
	var selection_snapshot = selection.duplicate(true)

	var first = service.apply_round(clubs, fixtures, [], incoming, rules, selection, 1)
	_check(first.ok and first.errors.is_empty(), "jornada completa aplicada")
	if first.ok:
		_check(first.data.round_number == 1, "jornada procesada informada")
		_check(first.data.results is Array and first.data.results.size() == 2,
			"colección nueva contiene ambos resultados")
		_check(first.data.applied_fixture_ids == _sorted_ids(round_one),
			"incorporaciones ordenadas por fixture_id")
		_check(first.data.already_applied_fixture_ids.is_empty(),
			"primera aplicación sin reintentos")
		_check(_result_ids(first.data.results) == _sorted_ids(round_one),
			"resultados ordenados determinísticamente")
		_check(_all_new_objects(first.data.results, incoming),
			"salida usa objetos nuevos")

	var expected_standings = Standings.new().calculate(
		clubs, fixtures, first.data.results, rules, selection
	)
	_check(expected_standings.ok and first.data.standings == expected_standings.data,
		"clasificación compatible con StandingsService")
	_check(_result_ids(first.data.results) == _fixture_ids(round_one),
		"orden compatible con CalendarService")

	var partial_incoming: Array[Result] = [incoming[0]]
	var partial = service.apply_round(clubs, fixtures, [], partial_incoming,
		rules, selection, 1)
	_check(partial.ok and partial.data.results.size() == 1,
		"jornada parcialmente procesada")
	_check(partial.data.applied_fixture_ids == [incoming[0].fixture_id],
		"aplicación parcial identifica el único alta")
	var remaining_incoming: Array[Result] = [incoming[1]]
	var completed_later = service.apply_round(clubs, fixtures, partial.data.results,
		remaining_incoming, rules, selection, 1)
	_check(completed_later.ok and completed_later.data.results.size() == 2,
		"incorporación posterior completa el estado conocido")
	_check(completed_later.data.applied_fixture_ids == [incoming[1].fixture_id],
		"segunda aplicación distingue la incorporación restante")
	_check(completed_later.data.standings == first.data.standings,
		"aplicación parcial y completa son deportivamente equivalentes")

	var pending_current: Array[Result] = [
		_result(incoming[0].fixture_id, Result.Status.PENDING, null, null)
	]
	var finalized_pending = service.apply_round(clubs, fixtures, pending_current,
		[incoming[0]], rules, selection, 1)
	_check(finalized_pending.ok
		and finalized_pending.data.applied_fixture_ids == [incoming[0].fixture_id],
		"resultado pendiente pasa a finalizado")
	_check(_find_result(finalized_pending.data.results, incoming[0].fixture_id).status
		== Result.Status.FINAL, "estado pendiente sustituido en la copia")

	var exact_retry = service.apply_round(clubs, fixtures, first.data.results,
		incoming, rules, selection, 1)
	_check(exact_retry.ok and exact_retry.data.applied_fixture_ids.is_empty(),
		"repetición exacta no incorpora resultados")
	_check(exact_retry.data.already_applied_fixture_ids == _sorted_ids(round_one),
		"repetición exacta identifica resultados ya aplicados")
	_check(_snapshot_results(exact_retry.data.results) == _snapshot_results(first.data.results)
		and exact_retry.data.standings == first.data.standings,
		"repetición completa conserva estado y clasificación")

	var changed_score = _copy_result(incoming[0])
	changed_score.home_goals += 1
	_expect_error(service.apply_round(clubs, fixtures, first.data.results,
		[changed_score], rules, selection, 1), "final_result_conflict")
	var contradictory: Array[Result] = [incoming[0], changed_score]
	_expect_error(service.apply_round(clubs, fixtures, [], contradictory,
		rules, selection, 1), "conflicting_incoming_results")
	var identical_duplicate: Array[Result] = [incoming[0], _copy_result(incoming[0])]
	_expect_error(service.apply_round(clubs, fixtures, [], identical_duplicate,
		rules, selection, 1), "duplicate_incoming_result")

	var other_round = _result(round_two[0].fixture_id, Result.Status.FINAL, 1, 0)
	_expect_error(service.apply_round(clubs, fixtures, [], [other_round],
		rules, selection, 1), "round_mismatch")
	var cup_fixture = _fixture("cup_fixture", "season_a", "cup", "regular", null,
		"club_a", "club_b", 1)
	var fixtures_with_cup: Array[Fixture] = fixtures.duplicate()
	fixtures_with_cup.append(cup_fixture)
	_expect_error(service.apply_round(clubs, fixtures_with_cup, [],
		[_result(cup_fixture.fixture_id, Result.Status.FINAL, 1, 0)],
		rules, selection, 1), "scope_mismatch")
	var other_group_fixture = _fixture("other_group", "season_a", "league",
		"regular", "group_b", "club_a", "club_b", 1)
	var fixtures_with_group: Array[Fixture] = fixtures.duplicate()
	fixtures_with_group.append(other_group_fixture)
	_expect_error(service.apply_round(clubs, fixtures_with_group, [],
		[_result(other_group_fixture.fixture_id, Result.Status.FINAL, 1, 0)],
		rules, selection, 1), "scope_mismatch")
	var other_stage_fixture = _fixture("other_stage", "season_a", "league",
		"second", null, "club_a", "club_b", 1)
	var fixtures_with_stage: Array[Fixture] = fixtures.duplicate()
	fixtures_with_stage.append(other_stage_fixture)
	_expect_error(service.apply_round(clubs, fixtures_with_stage, [],
		[_result(other_stage_fixture.fixture_id, Result.Status.FINAL, 1, 0)],
		rules, selection, 1), "scope_mismatch")

	var wrong_season = _copy_result(incoming[0])
	wrong_season.season_id = "season_b"
	_expect_error(service.apply_round(clubs, fixtures, [], [wrong_season],
		rules, selection, 1), "season_mismatch")
	_expect_error(service.apply_round(clubs, fixtures, [],
		[_result("unknown", Result.Status.FINAL, 1, 0)],
		rules, selection, 1), "unknown_fixture")
	for field in ["home_goals", "away_goals"]:
		for value in [-1, 1.5, "1", true, [], {}]:
			var invalid_score = _copy_result(incoming[0])
			invalid_score.set(field, value)
			_expect_error(service.apply_round(clubs, fixtures, [], [invalid_score],
				rules, selection, 1), "invalid_score")
	var pending_incoming = _result(incoming[0].fixture_id,
		Result.Status.PENDING, null, null)
	_expect_error(service.apply_round(clubs, fixtures, [], [pending_incoming],
		rules, selection, 1), "incoming_not_final")
	_expect_error(service.apply_round(clubs, fixtures, [], [],
		rules, selection, 99), "round_not_found")
	for invalid_round in [0, -1, 1.5, "1", true, null]:
		_expect_error(service.apply_round(clubs, fixtures, [], [],
			rules, selection, invalid_round), "invalid_round_number")

	var valid_then_invalid: Array[Result] = [incoming[0], _copy_result(incoming[1])]
	valid_then_invalid[1].away_goals = -1
	var current_snapshot = _snapshot_results(partial.data.results)
	var late_error = service.apply_round(clubs, fixtures, partial.data.results,
		valid_then_invalid, rules, selection, 1)
	_expect_error(late_error, "invalid_score")
	_check(_snapshot_results(partial.data.results) == current_snapshot,
		"error tardío no altera el estado actual")
	_check(_snapshot_results(incoming) == incoming_snapshot,
		"error tardío no altera el lote")

	var previous_round_result = _result(round_two[0].fixture_id,
		Result.Status.FINAL, 3, 2)
	var with_previous = service.apply_round(clubs, fixtures,
		[previous_round_result], incoming, rules, selection, 1)
	_check(with_previous.ok and with_previous.data.results.size() == 3,
		"resultados finales de otras jornadas se conservan")
	_check(_find_result(with_previous.data.results, previous_round_result.fixture_id)
		.home_goals == 3, "marcador anterior permanece intacto")

	var permuted_incoming: Array[Result] = incoming.duplicate()
	permuted_incoming.reverse()
	var permuted_current: Array[Result] = [previous_round_result]
	var permuted = service.apply_round(clubs, fixtures, permuted_current,
		permuted_incoming, rules, selection, 1)
	_check(permuted.ok
		and _snapshot_results(permuted.data.results) == _snapshot_results(with_previous.data.results)
		and permuted.data.standings == with_previous.data.standings,
		"permutaciones de entrada producen el mismo estado deportivo")

	var direct_rules = _rules(3, 1, 0, 2,
		["head_to_head_points", "head_to_head_goal_difference"])
	var all_draws: Array[Result] = [
		_result(round_one[0].fixture_id, Result.Status.FINAL, 0, 0),
		_result(round_one[1].fixture_id, Result.Status.FINAL, 0, 0),
	]
	var provisional = service.apply_round(clubs, fixtures, [], all_draws,
		direct_rules, selection, 1)
	_check(provisional.ok and provisional.data.standings.provisional,
		"clasificación provisional conservada")
	_check(not provisional.data.standings.pending_tiebreakers.is_empty(),
		"diagnósticos pendientes de StandingsService conservados")

	for points_win in [2, 3]:
		var points_rules = _rules(points_win, 1, 0, 1)
		var points_table = service.apply_round(clubs, fixtures, [], incoming,
			points_rules, selection, 1)
		_check(points_table.ok and _max_points(points_table.data.standings.rows)
			== points_win, "clasificación usa %d puntos por victoria" % points_win)

	for legs in [1, 2]:
		var integration = Generator.new().generate(clubs, {
			"format": "round_robin",
			"season_id": selection.season_id,
			"competition_id": selection.competition_id,
			"stage_id": selection.stage_id,
			"group_id": selection.group_id,
			"legs": legs,
		})
		_check(integration.ok, "calendario generado para %d vuelta(s)" % legs)
		if integration.ok:
			var integration_fixtures: Array[Fixture] = []
			for fixture in integration.data:
				integration_fixtures.append(fixture)
			var integration_round = Calendar.new().get_round_fixtures(
				integration_fixtures, selection.season_id, 1, _filters(selection),
				Calendar.Order.FIXTURE_ID
			)
			var integration_results: Array[Result] = []
			for fixture in integration_round:
				integration_results.append(
					_result(fixture.fixture_id, Result.Status.FINAL, 0, 0)
				)
			var integrated = service.apply_round(clubs, integration_fixtures, [],
				integration_results, _rules(3, 1, 0, legs), selection, 1)
			_check(integrated.ok and integrated.data.results.size() == 2,
				"avance compatible con calendario de %d vuelta(s)" % legs)

	var invalid_rules = _rules(3, 1, 0, 1)
	invalid_rules.points_win = null
	var invalid_rules_result = service.apply_round(clubs, fixtures, [], incoming,
		invalid_rules, selection, 1)
	_expect_error(invalid_rules_result, "invalid_rules")
	_check(_snapshot_results(incoming) == incoming_snapshot,
		"reglas inválidas no publican cambios parciales")

	var duplicate_current: Array[Result] = [incoming[0], _copy_result(incoming[0])]
	_expect_error(service.apply_round(clubs, fixtures, duplicate_current, [],
		rules, selection, 1), "duplicate_current_result")
	var invalid_current = _result(incoming[0].fixture_id,
		Result.Status.PENDING, 0, null)
	_expect_error(service.apply_round(clubs, fixtures, [invalid_current], [],
		rules, selection, 1), "pending_with_score")

	_check(_snapshot_clubs(clubs) == club_snapshot, "clubes sin modificar")
	_check(_snapshot_fixtures(fixtures) == fixture_snapshot, "fixtures sin modificar")
	_check(_snapshot_results(incoming) == incoming_snapshot, "resultados de entrada sin modificar")
	_check(_snapshot_rules(rules) == rules_snapshot, "reglas sin modificar")
	_check(selection == selection_snapshot, "selección sin modificar")

	_finish()


func _club(club_id: String, season_id: String = "season_a") -> Club:
	var club = Club.new()
	club.club_id = club_id
	club.season_id = season_id
	club.division_id = "synthetic_division"
	return club


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


func _rules(points_win: Variant, points_draw: Variant, points_loss: Variant,
		legs: Variant, tiebreakers: Variant = ["goal_difference", "goals_for", "wins"]
		) -> Rules:
	var rules = Rules.new()
	rules.season_id = "season_a"
	rules.competition_id = "league"
	rules.points_win = points_win
	rules.points_draw = points_draw
	rules.points_loss = points_loss
	rules.team_count = 4
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


func _filters(selection: Dictionary) -> Dictionary:
	return {
		"competition_id": selection.competition_id,
		"stage_id": selection.stage_id,
		"group_id": selection.group_id,
	}


func _find_result(results: Array, fixture_id: String) -> Result:
	for match_result in results:
		if match_result.fixture_id == fixture_id:
			return match_result
	return null


func _max_points(rows: Array) -> int:
	var maximum = -1000000
	for row in rows:
		maximum = maxi(maximum, row.points)
	return maximum


func _sorted_ids(fixtures: Array[Fixture]) -> Array[String]:
	var ids = _fixture_ids(fixtures)
	ids.sort()
	return ids


func _fixture_ids(fixtures: Array[Fixture]) -> Array[String]:
	var ids: Array[String] = []
	for fixture in fixtures:
		ids.append(fixture.fixture_id)
	return ids


func _result_ids(results: Array) -> Array[String]:
	var ids: Array[String] = []
	for match_result in results:
		ids.append(match_result.fixture_id)
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
	for match_result in results:
		snapshot.append({
			"fixture_id": match_result.fixture_id,
			"season_id": match_result.season_id,
			"home_goals": match_result.home_goals,
			"away_goals": match_result.away_goals,
			"status": match_result.status,
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
