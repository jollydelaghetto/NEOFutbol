class_name SeasonController
extends RefCounted

const Club = preload("res://game/scripts/data/club_season.gd")
const Fixture = preload("res://game/scripts/data/match_fixture.gd")
const MatchResultModel = preload("res://game/scripts/data/match_result.gd")
const Rules = preload("res://game/scripts/data/competition_rules.gd")
const Standings = preload("res://game/scripts/services/standings_service.gd")
const RoundProgression = preload("res://game/scripts/services/round_progression_service.gd")
const Correction = preload("res://game/scripts/services/match_result_correction_service.gd")
const Persistence = preload("res://game/scripts/services/sporting_state_persistence_service.gd")
const FixtureIntegrity = preload(
	"res://game/scripts/infrastructure/match_fixture_integrity_validator.gd"
)

var _initialized = false
var _clubs: Array[Club] = []
var _fixtures: Array[Fixture] = []
var _rules: Rules = null
var _selection: Dictionary = {}
var _results: Array[MatchResultModel] = []
var _audit_entries: Array[Dictionary] = []

## Inicializa una única sesión deportiva. data contiene selection, standings,
## result_count y audit_entry_count. Una instancia ya inicializada nunca puede
## reinicializarse; para cambiar de selección debe crearse otra instancia.
##
## Los modelos conocidos se clonan campo a campo y los Dictionary/Array se
## duplican en profundidad. RefCounted no ofrece inmutabilidad: la encapsulación
## depende de no añadir a esos modelos referencias mutables fuera de los campos
## que este controlador copia explícitamente.
func initialize(clubs: Array[Club], fixtures: Array[Fixture],
		rules: Rules, selection: Dictionary) -> Dictionary:
	if _initialized:
		return _failure("already_initialized",
			"El controlador ya contiene una sesión; utilice una instancia nueva.")
	var candidate_clubs = _copy_clubs(clubs)
	var candidate_fixtures = _copy_fixtures(fixtures)
	var candidate_rules = _copy_rules(rules)
	var candidate_selection = selection.duplicate(true)
	var integrity = FixtureIntegrity.new().validate(candidate_clubs, candidate_fixtures)
	if not integrity.ok:
		var normalized_integrity = integrity.duplicate(true)
		normalized_integrity["data"] = null
		return normalized_integrity
	var initial = Standings.new().calculate(
		candidate_clubs, candidate_fixtures, [], candidate_rules, candidate_selection
	)
	if not initial.ok:
		return initial
	_clubs = candidate_clubs
	_fixtures = candidate_fixtures
	_rules = candidate_rules
	_selection = candidate_selection
	_results = []
	_audit_entries = []
	_initialized = true
	return {
		"ok": true,
		"data": {
			"selection": _selection.duplicate(true),
			"standings": initial.data.duplicate(true),
			"result_count": 0,
			"audit_entry_count": 0,
		},
		"errors": [],
	}


## Devuelve data de StandingsService calculada sobre el estado actual.
func get_standings() -> Dictionary:
	var ready = _require_initialized()
	if ready != null:
		return ready
	var standings = Standings.new().calculate(
		_clubs, _fixtures, _results, _rules, _selection
	)
	if not standings.ok:
		return standings
	return {"ok": true, "data": standings.data.duplicate(true), "errors": []}


## Devuelve data.results como objetos MatchResult nuevos y ordenados.
func get_results() -> Dictionary:
	var ready = _require_initialized()
	if ready != null:
		return ready
	return {
		"ok": true,
		"data": {"results": _copy_results(_results)},
		"errors": [],
	}


## Devuelve data.audit_entries como una copia profunda del historial completo.
func get_audit_entries() -> Dictionary:
	var ready = _require_initialized()
	if ready != null:
		return ready
	return {
		"ok": true,
		"data": {"audit_entries": _audit_entries.duplicate(true)},
		"errors": [],
	}


## Delega el avance en RoundProgressionService. data contiene round_number,
## standings, applied_fixture_ids y already_applied_fixture_ids.
func apply_round(incoming_results: Array[MatchResultModel], round_number: Variant) -> Dictionary:
	var ready = _require_initialized()
	if ready != null:
		return ready
	var progressed = RoundProgression.new().apply_round(
		_clubs, _fixtures, _results, incoming_results, _rules, _selection, round_number
	)
	if not progressed.ok:
		return progressed
	var candidate_results = _copy_results(progressed.data.results)
	_results = candidate_results
	return {
		"ok": true,
		"data": {
			"round_number": progressed.data.round_number,
			"standings": progressed.data.standings.duplicate(true),
			"applied_fixture_ids": progressed.data.applied_fixture_ids.duplicate(),
			"already_applied_fixture_ids": \
				progressed.data.already_applied_fixture_ids.duplicate(),
		},
		"errors": [],
	}


## Delega la rectificación en MatchResultCorrectionService. data contiene
## standings, corrected_fixture_ids y una copia del historial audit_entries.
func correct_results(corrections: Array[Dictionary]) -> Dictionary:
	var ready = _require_initialized()
	if ready != null:
		return ready
	var historical_ids: Dictionary = {}
	for entry in _audit_entries:
		historical_ids[entry.correction_id] = true
	for index in corrections.size():
		var correction_id = corrections[index].get("correction_id", null)
		if correction_id is String and historical_ids.has(correction_id):
			var duplicate = _failure("historical_duplicate_correction_id",
				"El identificador de corrección ya existe en el historial acumulado.")
			duplicate.errors[0]["index"] = index
			duplicate.errors[0]["correction_id"] = correction_id
			return duplicate
	var corrected = Correction.new().correct_results(
		_clubs, _fixtures, _results, corrections, _rules, _selection
	)
	if not corrected.ok:
		return corrected
	var candidate_results = _copy_results(corrected.data.results)
	var combined_audit: Array[Dictionary] = _audit_entries.duplicate(true)
	for entry in corrected.data.audit_entries:
		combined_audit.append(entry.duplicate(true))
	var ordered_audit = _validate_and_order_audit(combined_audit, candidate_results)
	if not ordered_audit.ok:
		return ordered_audit
	_results = candidate_results
	_audit_entries = ordered_audit.data
	return {
		"ok": true,
		"data": {
			"standings": corrected.data.standings.duplicate(true),
			"corrected_fixture_ids": corrected.data.corrected_fixture_ids.duplicate(),
			"audit_entries": _audit_entries.duplicate(true),
		},
		"errors": [],
	}


## Guarda el estado actual mediante SportingStatePersistenceService. No cambia
## el estado interno y devuelve directamente su data de esquema, ruta y hash.
func save_state(path: String) -> Dictionary:
	var ready = _require_initialized()
	if ready != null:
		return ready
	return Persistence.new().save_state(
		path, _copy_clubs(_clubs), _copy_fixtures(_fixtures),
		_copy_results(_results), _audit_entries.duplicate(true),
		_copy_rules(_rules), _selection.duplicate(true)
	)


## Carga mediante SportingStatePersistenceService. data contiene schema_version,
## standings, result_count y audit_entry_count. Un error conserva la sesión.
func load_state(path: String) -> Dictionary:
	var ready = _require_initialized()
	if ready != null:
		return ready
	var loaded = Persistence.new().load_state(
		path, _copy_clubs(_clubs), _copy_fixtures(_fixtures),
		_copy_rules(_rules), _selection.duplicate(true)
	)
	if not loaded.ok:
		return loaded
	var candidate_results = _copy_results(loaded.data.results)
	var candidate_audit: Array[Dictionary] = loaded.data.audit_entries.duplicate(true)
	var ordered_audit = _validate_and_order_audit(candidate_audit, candidate_results)
	if not ordered_audit.ok:
		return ordered_audit
	_results = candidate_results
	_audit_entries = ordered_audit.data
	return {
		"ok": true,
		"data": {
			"schema_version": loaded.data.schema_version,
			"standings": loaded.data.standings.duplicate(true),
			"result_count": _results.size(),
			"audit_entry_count": _audit_entries.size(),
		},
		"errors": [],
	}


func _validate_and_order_audit(entries: Array[Dictionary],
		results: Array[MatchResultModel]) -> Dictionary:
	var results_by_fixture: Dictionary = {}
	for match_result in results:
		results_by_fixture[match_result.fixture_id] = match_result
	var seen_ids: Dictionary = {}
	var by_fixture: Dictionary = {}
	for index in entries.size():
		var entry = entries[index]
		var correction_id = entry.get("correction_id", null)
		if not correction_id is String or correction_id.strip_edges().is_empty():
			return _audit_failure("invalid_audit_entry",
				"La auditoría requiere un identificador de corrección no vacío.", index)
		if seen_ids.has(correction_id):
			var duplicate = _audit_failure("duplicate_correction_id",
				"El identificador de corrección está duplicado en el historial.", index)
			duplicate.errors[0]["correction_id"] = correction_id
			duplicate.errors[0]["first_index"] = seen_ids[correction_id]
			return duplicate
		seen_ids[correction_id] = index
		var fixture_id = entry.get("fixture_id", null)
		if not fixture_id is String or not results_by_fixture.has(fixture_id):
			return _audit_failure("audit_without_result",
				"La auditoría no tiene un resultado actual asociado.", index)
		if not by_fixture.has(fixture_id):
			by_fixture[fixture_id] = []
		by_fixture[fixture_id].append(entry.duplicate(true))
	var fixture_ids: Array[String] = []
	for fixture_id in by_fixture:
		fixture_ids.append(fixture_id)
	fixture_ids.sort()
	var ordered: Array[Dictionary] = []
	for fixture_id in fixture_ids:
		var current: MatchResultModel = results_by_fixture[fixture_id]
		if current.status != MatchResultModel.Status.FINAL:
			return _failure("audit_result_not_final",
				"El historial requiere un resultado actual finalizado.")
		var expected = {
			"home_goals": current.home_goals,
			"away_goals": current.away_goals,
			"status": current.status,
		}
		var remaining: Array = by_fixture[fixture_id].duplicate(true)
		var reverse_chain: Array[Dictionary] = []
		while not remaining.is_empty():
			var candidates: Array[int] = []
			for index in remaining.size():
				if _same_score(remaining[index].get("after", {}), expected):
					candidates.append(index)
			if candidates.size() != 1:
				return _failure("incoherent_audit_history",
					"La cadena acumulada de rectificaciones es incompleta o ambigua.")
			var position = candidates[0]
			var entry: Dictionary = remaining[position]
			if not entry.get("before", null) is Dictionary:
				return _failure("invalid_audit_entry",
					"La auditoría no contiene un estado anterior válido.")
			reverse_chain.append(entry)
			expected = entry.before
			remaining.remove_at(position)
		reverse_chain.reverse()
		for entry in reverse_chain:
			ordered.append(entry)
	return {"ok": true, "data": ordered, "errors": []}


func _same_score(left: Dictionary, right: Dictionary) -> bool:
	return left.get("home_goals") == right.get("home_goals") \
		and left.get("away_goals") == right.get("away_goals") \
		and left.get("status") == right.get("status")


func _copy_clubs(source: Array[Club]) -> Array[Club]:
	var copies: Array[Club] = []
	for original in source:
		var copy = Club.new()
		copy.club_id = original.club_id
		copy.season_id = original.season_id
		copy.division_id = original.division_id
		copies.append(copy)
	return copies


func _copy_fixtures(source: Array[Fixture]) -> Array[Fixture]:
	var copies: Array[Fixture] = []
	for original in source:
		var copy = Fixture.new()
		copy.fixture_id = original.fixture_id
		copy.season_id = original.season_id
		copy.competition_id = _copy_value(original.competition_id)
		copy.stage_id = _copy_value(original.stage_id)
		copy.group_id = _copy_value(original.group_id)
		copy.home_club_id = _copy_value(original.home_club_id)
		copy.away_club_id = _copy_value(original.away_club_id)
		copy.round_number = _copy_value(original.round_number)
		copy.scheduled_date = _copy_value(original.scheduled_date)
		copy.metadata = original.metadata.duplicate(true)
		copies.append(copy)
	return copies


func _copy_results(source: Array[MatchResultModel]) -> Array[MatchResultModel]:
	var copies: Array[MatchResultModel] = []
	for original in source:
		var copy = MatchResultModel.new()
		copy.fixture_id = original.fixture_id
		copy.season_id = original.season_id
		copy.status = original.status
		copy.home_goals = _copy_value(original.home_goals)
		copy.away_goals = _copy_value(original.away_goals)
		copies.append(copy)
	return copies


func _copy_rules(original: Rules) -> Rules:
	var copy = Rules.new()
	copy.season_id = original.season_id
	copy.competition_id = _copy_value(original.competition_id)
	copy.points_win = _copy_value(original.points_win)
	copy.points_draw = _copy_value(original.points_draw)
	copy.points_loss = _copy_value(original.points_loss)
	copy.team_count = _copy_value(original.team_count)
	copy.round_count = _copy_value(original.round_count)
	copy.tiebreakers = _copy_value(original.tiebreakers)
	copy.substitution_rules = _copy_value(original.substitution_rules)
	copy.promotion_relegation_rules = _copy_value(original.promotion_relegation_rules)
	copy.competition_format = _copy_value(original.competition_format)
	return copy


func _copy_value(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value


func _require_initialized() -> Variant:
	if not _initialized:
		return _failure("not_initialized", "El controlador no está inicializado.")
	return null


func _audit_failure(code: String, message: String, index: int) -> Dictionary:
	var result = _failure(code, message)
	result.errors[0]["index"] = index
	result.errors[0]["source"] = "audit_entries"
	return result


func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "data": null, "errors": [{"code": code, "message": message}]}
