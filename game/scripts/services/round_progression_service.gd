class_name RoundProgressionService
extends RefCounted

const Club = preload("res://game/scripts/data/club_season.gd")
const Fixture = preload("res://game/scripts/data/match_fixture.gd")
const MatchResultModel = preload("res://game/scripts/data/match_result.gd")
const Rules = preload("res://game/scripts/data/competition_rules.gd")
const Calendar = preload("res://game/scripts/services/calendar_service.gd")
const Standings = preload("res://game/scripts/services/standings_service.gd")
const REQUIRED_SELECTION = ["season_id", "competition_id", "stage_id", "group_id"]

## Incorpora resultados finales de una jornada sobre un estado conocido.
## Devuelve copias nuevas de todos los resultados, ordenadas por season_id y
## fixture_id; applied_fixture_ids identifica altas y transiciones PENDING ->
## FINAL, mientras already_applied_fixture_ids identifica reintentos exactos.
## standings contiene directamente data del resultado de StandingsService.
func apply_round(clubs: Array[Club], fixtures: Array[Fixture],
		current_results: Array[MatchResultModel], incoming_results: Array[MatchResultModel],
		rules: Rules, selection: Dictionary, round_number: Variant) -> Dictionary:
	var selection_error = _validate_selection(selection)
	if selection_error != null:
		return selection_error
	if typeof(round_number) != TYPE_INT or round_number <= 0:
		return _field_failure("invalid_round_number",
			"La jornada debe ser un entero positivo.", "round_number")

	var fixtures_by_season: Dictionary = {}
	for index in fixtures.size():
		var fixture = fixtures[index]
		if fixture.fixture_id.strip_edges().is_empty():
			return _indexed_failure("invalid_fixture",
				"El partido debe tener un identificador no vacío.",
				index, fixture.fixture_id, fixture.season_id)
		if not fixtures_by_season.has(fixture.season_id):
			fixtures_by_season[fixture.season_id] = {}
		var season_fixtures: Dictionary = fixtures_by_season[fixture.season_id]
		if season_fixtures.has(fixture.fixture_id):
			var duplicate = _indexed_failure("duplicate_fixture",
				"El identificador de partido está duplicado en la temporada.",
				index, fixture.fixture_id, fixture.season_id)
			duplicate.errors[0]["first_index"] = season_fixtures[fixture.fixture_id].index
			return duplicate
		season_fixtures[fixture.fixture_id] = {"fixture": fixture, "index": index}

	var filters = {
		"competition_id": selection.competition_id,
		"stage_id": selection.stage_id,
		"group_id": selection.group_id,
	}
	var round_fixtures: Array[Fixture] = Calendar.new().get_round_fixtures(
		fixtures, selection.season_id, round_number, filters, Calendar.Order.FIXTURE_ID
	)
	if round_fixtures.is_empty():
		var missing_round = _failure("round_not_found",
			"La selección no contiene partidos para la jornada solicitada.")
		missing_round.errors[0]["round_number"] = round_number
		return missing_round
	var target_fixture_ids: Dictionary = {}
	for fixture in round_fixtures:
		target_fixture_ids[fixture.fixture_id] = true

	var current_by_fixture: Dictionary = {}
	for index in current_results.size():
		var match_result = current_results[index]
		var result_error = _validate_known_result(match_result, index,
			fixtures_by_season, selection, "current")
		if result_error != null:
			return result_error
		if current_by_fixture.has(match_result.fixture_id):
			var duplicate_current = _result_failure("duplicate_current_result",
				"El estado actual contiene más de un resultado para el mismo partido.",
				index, match_result)
			duplicate_current.errors[0]["first_index"] = \
				current_by_fixture[match_result.fixture_id].index
			return duplicate_current
		current_by_fixture[match_result.fixture_id] = {
			"result": match_result,
			"index": index,
		}

	var incoming_by_fixture: Dictionary = {}
	for index in incoming_results.size():
		var match_result = incoming_results[index]
		var result_error = _validate_known_result(match_result, index,
			fixtures_by_season, selection, "incoming")
		if result_error != null:
			return result_error
		if match_result.status != MatchResultModel.Status.FINAL:
			return _result_failure("incoming_not_final",
				"Los resultados incorporados deben estar finalizados.", index, match_result)
		if not target_fixture_ids.has(match_result.fixture_id):
			var wrong_round = _result_failure("round_mismatch",
				"El resultado no pertenece a la jornada solicitada.", index, match_result)
			var fixture: Fixture = fixtures_by_season[match_result.season_id] \
				[match_result.fixture_id].fixture
			wrong_round.errors[0]["round_number"] = fixture.round_number
			wrong_round.errors[0]["expected_round_number"] = round_number
			return wrong_round
		if incoming_by_fixture.has(match_result.fixture_id):
			var first: MatchResultModel = incoming_by_fixture[match_result.fixture_id].result
			var code = "duplicate_incoming_result"
			var message = "El lote repite un resultado para el mismo partido."
			if not _same_result(first, match_result):
				code = "conflicting_incoming_results"
				message = "El lote contiene marcadores contradictorios para el mismo partido."
			var duplicate_incoming = _result_failure(code, message, index, match_result)
			duplicate_incoming.errors[0]["first_index"] = \
				incoming_by_fixture[match_result.fixture_id].index
			return duplicate_incoming
		incoming_by_fixture[match_result.fixture_id] = {
			"result": match_result,
			"index": index,
		}

	var applied_fixture_ids: Array[String] = []
	var already_applied_fixture_ids: Array[String] = []
	for fixture_id in incoming_by_fixture:
		var incoming: MatchResultModel = incoming_by_fixture[fixture_id].result
		if not current_by_fixture.has(fixture_id):
			applied_fixture_ids.append(fixture_id)
			continue
		var current: MatchResultModel = current_by_fixture[fixture_id].result
		if current.status == MatchResultModel.Status.PENDING:
			applied_fixture_ids.append(fixture_id)
		elif _same_result(current, incoming):
			already_applied_fixture_ids.append(fixture_id)
		else:
			return _result_failure("final_result_conflict",
				"Un resultado finalizado no puede sustituirse por otro marcador.",
				incoming_by_fixture[fixture_id].index, incoming)
	applied_fixture_ids.sort()
	already_applied_fixture_ids.sort()

	var next_by_fixture: Dictionary = {}
	for fixture_id in current_by_fixture:
		next_by_fixture[fixture_id] = _copy_result(current_by_fixture[fixture_id].result)
	for fixture_id in incoming_by_fixture:
		if fixture_id in already_applied_fixture_ids:
			continue
		next_by_fixture[fixture_id] = _copy_result(incoming_by_fixture[fixture_id].result)
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
			"applied_fixture_ids": applied_fixture_ids,
			"already_applied_fixture_ids": already_applied_fixture_ids,
			"round_number": round_number,
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


func _validate_known_result(match_result: MatchResultModel, index: int,
		fixtures_by_season: Dictionary, selection: Dictionary, source: String) -> Variant:
	if match_result.fixture_id.strip_edges().is_empty() \
			or match_result.season_id.strip_edges().is_empty():
		return _result_failure("invalid_result",
			"El resultado debe identificar partido y temporada.", index, match_result, source)
	if match_result.season_id != selection.season_id:
		return _result_failure("season_mismatch",
			"El resultado no pertenece a la temporada seleccionada.",
			index, match_result, source)
	if not fixtures_by_season.has(match_result.season_id) \
			or not fixtures_by_season[match_result.season_id].has(match_result.fixture_id):
		return _result_failure("unknown_fixture",
			"El resultado no corresponde a ningún partido identificado.",
			index, match_result, source)
	var fixture: Fixture = fixtures_by_season[match_result.season_id] \
		[match_result.fixture_id].fixture
	if not _fixture_in_scope(fixture, selection):
		return _result_failure("scope_mismatch",
			"El partido del resultado queda fuera de la selección exacta.",
			index, match_result, source)
	if match_result.status not in [MatchResultModel.Status.PENDING, MatchResultModel.Status.FINAL]:
		return _result_failure("invalid_status",
			"El estado del resultado no está admitido.", index, match_result, source)
	if match_result.status == MatchResultModel.Status.PENDING:
		if match_result.home_goals != null or match_result.away_goals != null:
			return _result_failure("pending_with_score",
				"Un partido pendiente debe conservar ambos marcadores como null.",
				index, match_result, source)
		return null
	if match_result.home_goals == null or match_result.away_goals == null:
		return _result_failure("missing_score",
			"Un partido finalizado necesita ambos marcadores.", index, match_result, source)
	for field in ["home_goals", "away_goals"]:
		var goals = match_result.get(field)
		if typeof(goals) != TYPE_INT or goals < 0:
			var invalid = _result_failure("invalid_score",
				"Los marcadores deben ser enteros no negativos.", index, match_result, source)
			invalid.errors[0]["field"] = field
			return invalid
	return null


func _fixture_in_scope(fixture: Fixture, selection: Dictionary) -> bool:
	return fixture.season_id == selection.season_id \
		and fixture.competition_id == selection.competition_id \
		and fixture.stage_id == selection.stage_id \
		and fixture.group_id == selection.group_id


func _same_result(left: MatchResultModel, right: MatchResultModel) -> bool:
	return left.season_id == right.season_id \
		and left.fixture_id == right.fixture_id \
		and left.status == right.status \
		and left.home_goals == right.home_goals \
		and left.away_goals == right.away_goals


func _copy_result(source: MatchResultModel) -> MatchResultModel:
	var copy = MatchResultModel.new()
	copy.fixture_id = source.fixture_id
	copy.season_id = source.season_id
	copy.home_goals = source.home_goals
	copy.away_goals = source.away_goals
	copy.status = source.status
	return copy


func _sort_results(results: Array[MatchResultModel]) -> void:
	for index in range(1, results.size()):
		var match_result = results[index]
		var position = index
		while position > 0 and _result_before(match_result, results[position - 1]):
			results[position] = results[position - 1]
			position -= 1
		results[position] = match_result


func _result_before(left: MatchResultModel, right: MatchResultModel) -> bool:
	if left.season_id != right.season_id:
		return left.season_id < right.season_id
	return left.fixture_id < right.fixture_id


func _field_failure(code: String, message: String, field: String) -> Dictionary:
	var result = _failure(code, message)
	result.errors[0]["field"] = field
	return result


func _indexed_failure(code: String, message: String, index: int,
		fixture_id: String, season_id: String, source: String = "fixtures") -> Dictionary:
	var result = _failure(code, message)
	result.errors[0]["index"] = index
	result.errors[0]["fixture_id"] = fixture_id
	result.errors[0]["season_id"] = season_id
	result.errors[0]["source"] = source
	return result


func _result_failure(code: String, message: String, index: int,
		match_result: MatchResultModel, source: String = "incoming") -> Dictionary:
	return _indexed_failure(code, message, index,
		match_result.fixture_id, match_result.season_id, source)


func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "data": null, "errors": [{"code": code, "message": message}]}
