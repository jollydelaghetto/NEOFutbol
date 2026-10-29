class_name StandingsService
extends RefCounted

const Club = preload("res://game/scripts/data/club_season.gd")
const Fixture = preload("res://game/scripts/data/match_fixture.gd")
const MatchResultModel = preload("res://game/scripts/data/match_result.gd")
const Rules = preload("res://game/scripts/data/competition_rules.gd")
const REQUIRED_SELECTION = ["season_id", "competition_id", "stage_id", "group_id"]
const GENERAL_TIEBREAKERS = ["goal_difference", "goals_for", "wins"]
const DIRECT_TIEBREAKERS = [
	"head_to_head_points",
	"head_to_head_goal_difference",
	"head_to_head_goals_for",
]
const SUPPORTED_TIEBREAKERS = GENERAL_TIEBREAKERS + DIRECT_TIEBREAKERS

## Calcula una tabla de liga para la selección exacta indicada.
## selection requiere season_id y competition_id como String no vacío, además
## de stage_id y group_id como String no vacío o null.
## Solo se admite competition_format.kind == "round_robin". Los puntos son el
## criterio principal y rules.tiebreakers puede contener, en orden de prioridad,
## goal_difference, goals_for, wins y los tres criterios head_to_head. Cada
## criterio se aplica una sola vez y solo a los subgrupos que sigan empatados.
## Los criterios directos se certifican con competition_format.legs y
## competition_format.head_to_head_policy. La ausencia de esos datos conserva
## un orden informativo y provisional; nunca se infieren desde el calendario.
## club_id se usa únicamente para presentar de forma determinista los empates
## deportivos que continúan sin resolver.
func calculate(clubs: Array[Club], fixtures: Array[Fixture],
		results: Array[MatchResultModel], rules: Rules, selection: Dictionary) -> Dictionary:
	var selection_error = _validate_selection(selection)
	if selection_error != null:
		return selection_error
	var rules_error = _validate_rules(rules, selection)
	if rules_error != null:
		return rules_error

	var rows_by_club: Dictionary = {}
	for index in clubs.size():
		var club = clubs[index]
		if club.club_id.strip_edges().is_empty():
			return _indexed_failure("invalid_club", "El club debe tener un identificador no vacío.",
				index, "club_id", club.club_id)
		if club.season_id != selection.season_id:
			return _indexed_failure("season_mismatch",
				"El club no pertenece a la temporada seleccionada.",
				index, "club_id", club.club_id)
		if rows_by_club.has(club.club_id):
			var duplicate_club = _indexed_failure("duplicate_club",
				"El club está duplicado entre los participantes.",
				index, "club_id", club.club_id)
			duplicate_club.errors[0]["first_index"] = rows_by_club[club.club_id].source_index
			return duplicate_club
		rows_by_club[club.club_id] = _empty_row(club.club_id, index)

	var fixtures_by_season: Dictionary = {}
	var selected_fixtures: Dictionary = {}
	var selected_fixture_entries: Array[Dictionary] = []
	for index in fixtures.size():
		var fixture = fixtures[index]
		if fixture.fixture_id.strip_edges().is_empty():
			return _fixture_failure("invalid_fixture",
				"El partido debe tener un identificador no vacío.", index, fixture)
		if not fixtures_by_season.has(fixture.season_id):
			fixtures_by_season[fixture.season_id] = {}
		var season_fixtures: Dictionary = fixtures_by_season[fixture.season_id]
		if season_fixtures.has(fixture.fixture_id):
			var duplicate_fixture = _indexed_failure("duplicate_fixture",
				"El identificador de partido está duplicado en la temporada.",
				index, "fixture_id", fixture.fixture_id)
			duplicate_fixture.errors[0]["first_index"] = season_fixtures[fixture.fixture_id].index
			return duplicate_fixture
		season_fixtures[fixture.fixture_id] = {"fixture": fixture, "index": index}
		if _fixture_in_scope(fixture, selection):
			if fixture.home_club_id != null and fixture.away_club_id != null \
					and fixture.home_club_id == fixture.away_club_id:
				return _fixture_failure("self_match",
					"Un club no puede enfrentarse a sí mismo.", index, fixture)
			var entry = {"fixture": fixture, "index": index}
			selected_fixtures[fixture.fixture_id] = entry
			selected_fixture_entries.append(entry)

	var seen_results: Dictionary = {}
	var results_by_fixture: Dictionary = {}
	var completed: Array[Dictionary] = []
	for index in results.size():
		var match_result = results[index]
		if match_result.fixture_id.strip_edges().is_empty() \
				or match_result.season_id.strip_edges().is_empty():
			return _indexed_failure("invalid_result",
				"El resultado debe identificar partido y temporada.",
				index, "fixture_id", match_result.fixture_id)
		if match_result.season_id != selection.season_id:
			return _result_failure("season_mismatch",
				"El resultado no pertenece a la temporada seleccionada.", index, match_result)
		if seen_results.has(match_result.fixture_id):
			var duplicate_result = _result_failure("duplicate_result",
				"Existe más de un resultado para el mismo partido.", index, match_result)
			duplicate_result.errors[0]["first_index"] = seen_results[match_result.fixture_id]
			return duplicate_result
		seen_results[match_result.fixture_id] = index
		var season_fixtures: Dictionary = fixtures_by_season.get(match_result.season_id, {})
		if not season_fixtures.has(match_result.fixture_id):
			return _result_failure("unknown_fixture",
				"El resultado no corresponde a ningún partido identificado.", index, match_result)
		if not selected_fixtures.has(match_result.fixture_id):
			return _result_failure("scope_mismatch",
				"El partido del resultado queda fuera de la selección exacta.", index, match_result)
		if match_result.status not in [MatchResultModel.Status.PENDING, MatchResultModel.Status.FINAL]:
			return _result_failure("invalid_status",
				"El estado del resultado no está admitido.", index, match_result)
		results_by_fixture[match_result.fixture_id] = match_result
		if match_result.status == MatchResultModel.Status.PENDING:
			if match_result.home_goals != null or match_result.away_goals != null:
				return _result_failure("pending_with_score",
					"Un partido pendiente debe conservar ambos marcadores como null.",
					index, match_result)
			continue
		if match_result.home_goals == null or match_result.away_goals == null:
			return _result_failure("missing_score",
				"Un partido finalizado necesita ambos marcadores.", index, match_result)
		for field in ["home_goals", "away_goals"]:
			var goals = match_result.get(field)
			if typeof(goals) != TYPE_INT or goals < 0:
				var invalid_score = _result_failure("invalid_score",
					"Los marcadores deben ser enteros no negativos.", index, match_result)
				invalid_score.errors[0]["field"] = field
				return invalid_score
		var fixture: Fixture = selected_fixtures[match_result.fixture_id].fixture
		for field in ["home_club_id", "away_club_id"]:
			var club_id = fixture.get(field)
			if club_id == null or not rows_by_club.has(club_id):
				var missing_club = _fixture_failure("missing_club_reference",
					"El partido computable referencia un club participante inexistente.",
					selected_fixtures[match_result.fixture_id].index, fixture)
				missing_club.errors[0]["field"] = field
				if club_id != null:
					missing_club.errors[0]["club_id"] = club_id
				return missing_club
		completed.append({"fixture": fixture, "result": match_result})

	for completed_match in completed:
		_apply_result(completed_match.fixture, completed_match.result,
			rows_by_club, rules.points_win, rules.points_draw, rules.points_loss)

	var rows: Array[Dictionary] = []
	for row in rows_by_club.values():
		row.erase("source_index")
		row.goal_difference = row.goals_for - row.goals_against
		rows.append(row)
	var ranking = _rank_rows(rows, rules.tiebreakers, selected_fixture_entries,
		results_by_fixture, rules)
	rows = ranking.rows
	var unresolved_ties: Array = []
	var row_index = 0
	for group in ranking.groups:
		var position = row_index + 1
		var tied_clubs: Array[String] = []
		for row in group:
			row["position"] = position
			rows[row_index] = row
			row_index += 1
			tied_clubs.append(row.club_id)
		if tied_clubs.size() > 1:
			unresolved_ties.append(tied_clubs)
	return {
		"ok": true,
		"data": {
			"rows": rows,
			"provisional": not unresolved_ties.is_empty()
				or not ranking.pending_tiebreakers.is_empty(),
			"unresolved_ties": unresolved_ties,
			"tiebreakers_applied": rules.tiebreakers.duplicate(),
			"pending_tiebreakers": ranking.pending_tiebreakers,
		},
		"errors": [],
	}


func _validate_selection(selection: Dictionary) -> Variant:
	for field in REQUIRED_SELECTION:
		if not selection.has(field):
			var missing = _failure("missing_selection", "Falta un campo de selección obligatorio.")
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


func _validate_rules(rules: Rules, selection: Dictionary) -> Variant:
	if rules.season_id != selection.season_id:
		return _field_failure("rules_mismatch",
			"Las reglas no pertenecen a la temporada seleccionada.", "season_id")
	if rules.competition_id != selection.competition_id:
		return _field_failure("rules_mismatch",
			"Las reglas no pertenecen a la competición seleccionada.", "competition_id")
	for field in ["points_win", "points_draw", "points_loss"]:
		if typeof(rules.get(field)) != TYPE_INT:
			return _field_failure("invalid_rules",
				"Las reglas de puntuación deben ser enteros explícitos.", field)
	var tiebreaker_error = _validate_tiebreakers(rules.tiebreakers)
	if tiebreaker_error != null:
		return tiebreaker_error
	if not rules.competition_format is Dictionary \
			or rules.competition_format.get("kind") != "round_robin":
		return _field_failure("unsupported_format",
			"Solo se admite competition_format.kind igual a round_robin.",
			"competition_format")
	var legs = rules.competition_format.get("legs", null)
	if legs != null and (typeof(legs) != TYPE_INT or legs not in [1, 2]):
		return _field_failure("invalid_legs",
			"competition_format.legs debe ser 1, 2 o null.",
			"competition_format.legs")
	var policy = rules.competition_format.get("head_to_head_policy", null)
	if policy != null and not policy is String:
		return _field_failure("invalid_head_to_head_policy",
			"competition_format.head_to_head_policy debe ser una cadena o null.",
			"competition_format.head_to_head_policy")
	if policy != null and policy != "single_pass":
		var unsupported = _field_failure("unsupported_head_to_head_policy",
			"La política de desempate directo no está admitida.",
			"competition_format.head_to_head_policy")
		unsupported.errors[0]["policy"] = policy
		return unsupported
	return null


func _validate_tiebreakers(tiebreakers: Variant) -> Variant:
	if tiebreakers == null:
		return _field_failure("invalid_tiebreakers",
			"Los criterios de desempate deben estar documentados mediante un array.",
			"tiebreakers")
	if not tiebreakers is Array:
		return _field_failure("invalid_tiebreakers",
			"Los criterios de desempate deben formar un array.", "tiebreakers")
	var seen: Dictionary = {}
	for index in tiebreakers.size():
		var criterion = tiebreakers[index]
		if not criterion is String:
			var invalid = _field_failure("invalid_tiebreaker",
				"Cada criterio de desempate debe ser una cadena.", "tiebreakers")
			invalid.errors[0]["index"] = index
			return invalid
		if criterion not in SUPPORTED_TIEBREAKERS:
			var unknown = _field_failure("unknown_tiebreaker",
				"El criterio de desempate no está admitido.", "tiebreakers")
			unknown.errors[0]["index"] = index
			unknown.errors[0]["criterion"] = criterion
			return unknown
		if seen.has(criterion):
			var duplicate = _field_failure("duplicate_tiebreaker",
				"El criterio de desempate está duplicado.", "tiebreakers")
			duplicate.errors[0]["index"] = index
			duplicate.errors[0]["first_index"] = seen[criterion]
			duplicate.errors[0]["criterion"] = criterion
			return duplicate
		seen[criterion] = index
	return null


func _fixture_in_scope(fixture: Fixture, selection: Dictionary) -> bool:
	return fixture.season_id == selection.season_id \
		and fixture.competition_id == selection.competition_id \
		and fixture.stage_id == selection.stage_id \
		and fixture.group_id == selection.group_id


func _empty_row(club_id: String, source_index: int) -> Dictionary:
	return {
		"club_id": club_id,
		"played": 0,
		"wins": 0,
		"draws": 0,
		"losses": 0,
		"goals_for": 0,
		"goals_against": 0,
		"goal_difference": 0,
		"points": 0,
		"source_index": source_index,
	}


func _apply_result(fixture: Fixture, match_result: MatchResultModel,
		rows: Dictionary, points_win: int, points_draw: int, points_loss: int) -> void:
	var home: Dictionary = rows[fixture.home_club_id]
	var away: Dictionary = rows[fixture.away_club_id]
	home.played += 1
	away.played += 1
	home.goals_for += match_result.home_goals
	home.goals_against += match_result.away_goals
	away.goals_for += match_result.away_goals
	away.goals_against += match_result.home_goals
	if match_result.home_goals > match_result.away_goals:
		home.wins += 1
		away.losses += 1
		home.points += points_win
		away.points += points_loss
	elif match_result.home_goals < match_result.away_goals:
		away.wins += 1
		home.losses += 1
		away.points += points_win
		home.points += points_loss
	else:
		home.draws += 1
		away.draws += 1
		home.points += points_draw
		away.points += points_draw


## Aplica puntos y los criterios configurados como una única pasada ordenada.
## Los grupos que produce cada criterio son la única entrada del siguiente; no
## se reinicia la secuencia al formar un subgrupo.
func _rank_rows(rows: Array[Dictionary], tiebreakers: Array,
		fixture_entries: Array[Dictionary], results_by_fixture: Dictionary,
		rules: Rules) -> Dictionary:
	var groups = _split_by_value(rows, "points", {})
	var pending_tiebreakers: Array[Dictionary] = []
	for criterion_index in tiebreakers.size():
		var criterion: String = tiebreakers[criterion_index]
		var next_groups: Array = []
		for group in groups:
			if group.size() < 2:
				next_groups.append(group)
				continue
			if criterion in GENERAL_TIEBREAKERS:
				for subgroup in _split_by_value(group, criterion, {}):
					next_groups.append(subgroup)
				continue
			var direct = _direct_values(group, fixture_entries, results_by_fixture, rules)
			for direct_diagnostic in direct.diagnostics:
				var diagnostic: Dictionary = direct_diagnostic
				diagnostic["criterion"] = criterion
				diagnostic["criterion_index"] = criterion_index
				pending_tiebreakers.append(diagnostic)
			if not direct.ready:
				next_groups.append(group)
				continue
			var value_name = criterion.trim_prefix("head_to_head_")
			for subgroup in _split_by_value(group, value_name, direct.values):
				next_groups.append(subgroup)
		groups = next_groups

	var ranked_rows: Array[Dictionary] = []
	for group in groups:
		_sort_group_by_club_id(group)
		for row in group:
			ranked_rows.append(row)
	return {
		"rows": ranked_rows,
		"groups": groups,
		"pending_tiebreakers": pending_tiebreakers,
	}


## Divide un grupo por un valor descendente. La inserción y club_id hacen el
## resultado total y determinista sin depender de la estabilidad del sort.
func _split_by_value(rows: Array, value_name: String, values: Dictionary) -> Array:
	var ordered: Array = rows.duplicate()
	for index in range(1, ordered.size()):
		var row = ordered[index]
		var position = index
		while position > 0 and _value_before(row, ordered[position - 1],
				value_name, values):
			ordered[position] = ordered[position - 1]
			position -= 1
		ordered[position] = row
	var groups: Array = []
	for row in ordered:
		var value = _ranking_value(row, value_name, values)
		if groups.is_empty() or _ranking_value(groups[-1][0], value_name, values) != value:
			groups.append([row])
		else:
			groups[-1].append(row)
	return groups


func _value_before(left: Dictionary, right: Dictionary,
		value_name: String, values: Dictionary) -> bool:
	var left_value = _ranking_value(left, value_name, values)
	var right_value = _ranking_value(right, value_name, values)
	if left_value != right_value:
		return left_value > right_value
	return left.club_id < right.club_id


func _ranking_value(row: Dictionary, value_name: String, values: Dictionary) -> int:
	if values.is_empty():
		return row[value_name]
	return values[row.club_id][value_name]


func _sort_group_by_club_id(group: Array) -> void:
	for index in range(1, group.size()):
		var row = group[index]
		var position = index
		while position > 0 and row.club_id < group[position - 1].club_id:
			group[position] = group[position - 1]
			position -= 1
		group[position] = row


## Calcula una mini-liga para el grupo actual. legs define el número exacto de
## encuentros esperados por pareja; solo legs == 2 exige ambas localías.
func _direct_values(group: Array, fixture_entries: Array[Dictionary],
		results_by_fixture: Dictionary, rules: Rules) -> Dictionary:
	var club_ids: Array[String] = []
	var member: Dictionary = {}
	var values: Dictionary = {}
	for row in group:
		club_ids.append(row.club_id)
		member[row.club_id] = true
		values[row.club_id] = {"points": 0, "goal_difference": 0, "goals_for": 0}
	club_ids.sort()

	var pair_counts: Dictionary = {}
	var pair_directions: Dictionary = {}
	for left_index in club_ids.size():
		for right_index in range(left_index + 1, club_ids.size()):
			var key = _pair_key(club_ids[left_index], club_ids[right_index])
			pair_counts[key] = 0
			pair_directions[key] = {"first_home": 0, "second_home": 0}
	var direct_entries: Array[Dictionary] = []
	for entry in fixture_entries:
		var fixture: Fixture = entry.fixture
		if fixture.home_club_id == null or fixture.away_club_id == null \
				or not member.has(fixture.home_club_id) or not member.has(fixture.away_club_id):
			continue
		var key = _pair_key(fixture.home_club_id, fixture.away_club_id)
		pair_counts[key] += 1
		if fixture.home_club_id < fixture.away_club_id:
			pair_directions[key].first_home += 1
		else:
			pair_directions[key].second_home += 1
		direct_entries.append(entry)

	var expected_legs = rules.competition_format.get("legs", null)
	var policy = rules.competition_format.get("head_to_head_policy", null)
	var observed_meetings = _observed_meetings(club_ids, pair_counts, pair_directions)
	var calendar_matches_rule = true
	if expected_legs == null:
		var meeting_counts: Array[int] = []
		for count in pair_counts.values():
			meeting_counts.append(count)
		meeting_counts.sort()
		calendar_matches_rule = not meeting_counts.is_empty() \
			and meeting_counts[0] > 0 and meeting_counts[0] == meeting_counts[-1]
	else:
		for meeting in observed_meetings:
			if meeting.total != expected_legs:
				calendar_matches_rule = false
				break
			if expected_legs == 2 \
					and (meeting.first_home != 1 or meeting.second_home != 1):
				calendar_matches_rule = false
				break
	if not calendar_matches_rule:
		var incomplete = _pending_diagnostic(
			"incomplete_calendar",
			"El calendario no coincide con el número de vueltas declarado.",
			club_ids, [])
		incomplete["expected_legs"] = expected_legs
		incomplete["observed_meetings"] = observed_meetings
		return {
			"ready": false,
			"diagnostics": [incomplete],
		}

	var pending_result_fixture_ids: Array[String] = []
	var missing_result_fixture_ids: Array[String] = []
	for entry in direct_entries:
		var fixture: Fixture = entry.fixture
		if not results_by_fixture.has(fixture.fixture_id):
			missing_result_fixture_ids.append(fixture.fixture_id)
		elif results_by_fixture[fixture.fixture_id].status != MatchResultModel.Status.FINAL:
			pending_result_fixture_ids.append(fixture.fixture_id)
	if not pending_result_fixture_ids.is_empty() or not missing_result_fixture_ids.is_empty():
		pending_result_fixture_ids.sort()
		missing_result_fixture_ids.sort()
		var reason = "incomplete_results"
		if missing_result_fixture_ids.is_empty():
			reason = "pending_results"
		elif pending_result_fixture_ids.is_empty():
			reason = "missing_results"
		var fixture_ids = pending_result_fixture_ids + missing_result_fixture_ids
		fixture_ids.sort()
		var diagnostic = _pending_diagnostic(
			reason,
			"La mini-liga conserva partidos programados sin resultado final.",
			club_ids, fixture_ids)
		diagnostic["expected_legs"] = expected_legs
		diagnostic["observed_meetings"] = observed_meetings
		diagnostic["pending_result_fixture_ids"] = pending_result_fixture_ids
		diagnostic["missing_result_fixture_ids"] = missing_result_fixture_ids
		return {
			"ready": false,
			"diagnostics": [diagnostic],
		}

	for entry in direct_entries:
		var fixture: Fixture = entry.fixture
		var match_result: MatchResultModel = results_by_fixture[fixture.fixture_id]
		_apply_direct_result(fixture, match_result, values,
			rules.points_win, rules.points_draw, rules.points_loss)
	var diagnostics: Array[Dictionary] = []
	if expected_legs == null:
		var unknown_legs = _pending_diagnostic(
			"unknown_legs",
			"El número de vueltas no está documentado para certificar la mini-liga.",
			club_ids, [])
		unknown_legs["expected_legs"] = null
		unknown_legs["observed_meetings"] = observed_meetings
		diagnostics.append(unknown_legs)
	if policy == null:
		var unknown_policy = _pending_diagnostic(
			"unknown_head_to_head_policy",
			"La política de desempate directo no está documentada.",
			club_ids, [])
		unknown_policy["expected_legs"] = expected_legs
		unknown_policy["observed_meetings"] = observed_meetings
		diagnostics.append(unknown_policy)
	return {"ready": true, "values": values, "diagnostics": diagnostics}


func _observed_meetings(club_ids: Array[String], pair_counts: Dictionary,
		pair_directions: Dictionary) -> Array[Dictionary]:
	var observed: Array[Dictionary] = []
	for left_index in club_ids.size():
		for right_index in range(left_index + 1, club_ids.size()):
			var key = _pair_key(club_ids[left_index], club_ids[right_index])
			observed.append({
				"first_club_id": club_ids[left_index],
				"second_club_id": club_ids[right_index],
				"total": pair_counts[key],
				"first_home": pair_directions[key].first_home,
				"second_home": pair_directions[key].second_home,
			})
	return observed


func _apply_direct_result(fixture: Fixture, match_result: MatchResultModel,
		values: Dictionary, points_win: int, points_draw: int, points_loss: int) -> void:
	var home: Dictionary = values[fixture.home_club_id]
	var away: Dictionary = values[fixture.away_club_id]
	home.goals_for += match_result.home_goals
	away.goals_for += match_result.away_goals
	home.goal_difference += match_result.home_goals - match_result.away_goals
	away.goal_difference += match_result.away_goals - match_result.home_goals
	if match_result.home_goals > match_result.away_goals:
		home.points += points_win
		away.points += points_loss
	elif match_result.home_goals < match_result.away_goals:
		away.points += points_win
		home.points += points_loss
	else:
		home.points += points_draw
		away.points += points_draw


func _pair_key(left: String, right: String) -> String:
	if right < left:
		var swap = left
		left = right
		right = swap
	return "%d:%s|%d:%s" % [left.length(), left, right.length(), right]


func _pending_diagnostic(reason: String, message: String,
		club_ids: Array[String], fixture_ids: Array[String]) -> Dictionary:
	return {
		"code": "pending_head_to_head_tiebreaker",
		"message": message,
		"reason": reason,
		"club_ids": club_ids.duplicate(),
		"fixture_ids": fixture_ids.duplicate(),
	}


func _field_failure(code: String, message: String, field: String) -> Dictionary:
	var result = _failure(code, message)
	result.errors[0]["field"] = field
	return result


func _indexed_failure(code: String, message: String, index: int,
		identifier_name: String, identifier: Variant) -> Dictionary:
	var result = _failure(code, message)
	result.errors[0]["index"] = index
	result.errors[0][identifier_name] = identifier
	return result


func _fixture_failure(code: String, message: String,
		index: int, fixture: Fixture) -> Dictionary:
	var result = _indexed_failure(code, message, index, "fixture_id", fixture.fixture_id)
	result.errors[0]["season_id"] = fixture.season_id
	return result


func _result_failure(code: String, message: String,
		index: int, match_result: MatchResultModel) -> Dictionary:
	var result = _indexed_failure(code, message, index, "fixture_id", match_result.fixture_id)
	result.errors[0]["season_id"] = match_result.season_id
	return result


func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "data": null, "errors": [{"code": code, "message": message}]}
