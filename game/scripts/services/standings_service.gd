class_name StandingsService
extends RefCounted

const Club = preload("res://game/scripts/data/club_season.gd")
const Fixture = preload("res://game/scripts/data/match_fixture.gd")
const MatchResultModel = preload("res://game/scripts/data/match_result.gd")
const Rules = preload("res://game/scripts/data/competition_rules.gd")
const REQUIRED_SELECTION = ["season_id", "competition_id", "stage_id", "group_id"]
const SUPPORTED_TIEBREAKERS = ["goal_difference", "goals_for", "wins"]

## Calcula una tabla de liga para la selección exacta indicada.
## selection requiere season_id y competition_id como String no vacío, además
## de stage_id y group_id como String no vacío o null.
## Solo se admite competition_format.kind == "round_robin". Los puntos son el
## criterio principal y rules.tiebreakers puede contener, en orden de prioridad,
## goal_difference, goals_for y wins. club_id se usa únicamente para presentar
## de forma determinista los empates deportivos que continúan sin resolver.
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
	for index in fixtures.size():
		var fixture = fixtures[index]
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
			selected_fixtures[fixture.fixture_id] = {"fixture": fixture, "index": index}

	var seen_results: Dictionary = {}
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
	_sort_rows(rows, rules.tiebreakers)
	var unresolved_ties: Array = []
	var current_tie: Array[String] = []
	for index in rows.size():
		if index == 0 or not _sporting_equal(rows[index], rows[index - 1], rules.tiebreakers):
			if current_tie.size() > 1:
				unresolved_ties.append(current_tie)
			current_tie = [rows[index].club_id]
			rows[index]["position"] = index + 1
		else:
			current_tie.append(rows[index].club_id)
			rows[index]["position"] = rows[index - 1].position
	if current_tie.size() > 1:
		unresolved_ties.append(current_tie)
	return {
		"ok": true,
		"data": {
			"rows": rows,
			"provisional": not unresolved_ties.is_empty(),
			"unresolved_ties": unresolved_ties,
			"tiebreakers_applied": rules.tiebreakers.duplicate(),
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


## Inserción determinista: el comparador incluye club_id como último criterio
## visual, de modo que no depende de la estabilidad de Array.sort_custom().
func _sort_rows(rows: Array[Dictionary], tiebreakers: Array) -> void:
	for index in range(1, rows.size()):
		var row = rows[index]
		var position = index
		while position > 0 and _row_before(row, rows[position - 1], tiebreakers):
			rows[position] = rows[position - 1]
			position -= 1
		rows[position] = row


func _row_before(left: Dictionary, right: Dictionary, tiebreakers: Array) -> bool:
	if left.points != right.points:
		return left.points > right.points
	for criterion in tiebreakers:
		if left[criterion] != right[criterion]:
			return left[criterion] > right[criterion]
	return left.club_id < right.club_id


func _sporting_equal(left: Dictionary, right: Dictionary, tiebreakers: Array) -> bool:
	if left.points != right.points:
		return false
	for criterion in tiebreakers:
		if left[criterion] != right[criterion]:
			return false
	return true


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
