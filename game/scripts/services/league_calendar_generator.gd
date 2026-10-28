class_name LeagueCalendarGenerator
extends RefCounted

const Club = preload("res://game/scripts/data/club_season.gd")
const Fixture = preload("res://game/scripts/data/match_fixture.gd")
const REQUIRED_OPTIONS = [
	"format", "season_id", "competition_id", "stage_id", "group_id", "legs"
]

## Genera una liga regular mediante el método circular, sin aleatoriedad.
## options requiere:
## - format: "round_robin".
## - season_id y competition_id: String no vacío.
## - stage_id y group_id: String no vacío o null.
## - legs: 1 o 2.
## Devuelve {ok: true, data: Array[MatchFixture], errors: []} o, ante el
## primer error determinista, {ok: false, data: null, errors: [diagnóstico]}.
func generate(clubs: Array[Club], options: Dictionary) -> Dictionary:
	var option_error = _validate_options(options)
	if option_error != null:
		return option_error
	if clubs.size() < 2:
		return _failure(
			"insufficient_clubs", "La liga necesita al menos dos clubes."
		)

	var club_ids: Array[String] = []
	var seen: Dictionary = {}
	for index in clubs.size():
		var club = clubs[index]
		if club.club_id.strip_edges().is_empty():
			var invalid = _failure(
				"invalid_club", "El identificador del club debe ser una cadena no vacía."
			)
			invalid.errors[0]["index"] = index
			invalid.errors[0]["club_id"] = club.club_id
			return invalid
		if club.season_id != options.season_id:
			var mismatch = _failure(
				"season_mismatch", "El club no pertenece a la temporada solicitada."
			)
			mismatch.errors[0]["index"] = index
			mismatch.errors[0]["club_id"] = club.club_id
			mismatch.errors[0]["season_id"] = club.season_id
			mismatch.errors[0]["expected_season_id"] = options.season_id
			return mismatch
		if seen.has(club.club_id):
			var duplicate = _failure(
				"duplicate_club", "El club está duplicado en la colección de entrada."
			)
			duplicate.errors[0]["index"] = index
			duplicate.errors[0]["first_index"] = seen[club.club_id]
			duplicate.errors[0]["club_id"] = club.club_id
			return duplicate
		seen[club.club_id] = index
		club_ids.append(club.club_id)

	var rotation: Array = []
	for club_id in club_ids:
		rotation.append(club_id)
	if rotation.size() % 2 != 0:
		rotation.append(null)
	var rounds_per_leg = rotation.size() - 1
	var first_leg: Array[Dictionary] = []
	for round_index in rounds_per_leg:
		for pair_index in int(rotation.size() / 2):
			var left = rotation[pair_index]
			var right = rotation[rotation.size() - 1 - pair_index]
			if left == null or right == null:
				continue
			var home = left
			var away = right
			# Alternar la pareja de la posición fija evita concentrar su localía.
			if pair_index == 0 and round_index % 2 != 0:
				home = right
				away = left
			first_leg.append({
				"round_number": round_index + 1,
				"home_club_id": home,
				"away_club_id": away,
			})
		var last = rotation.pop_back()
		rotation.insert(1, last)

	var fixtures: Array[Fixture] = []
	for match in first_leg:
		fixtures.append(_fixture(options, match.round_number,
			match.home_club_id, match.away_club_id))
	if options.legs == 2:
		for match in first_leg:
			fixtures.append(_fixture(options, match.round_number + rounds_per_leg,
				match.away_club_id, match.home_club_id))
	return {"ok": true, "data": fixtures, "errors": []}


func _validate_options(options: Dictionary) -> Variant:
	for option in REQUIRED_OPTIONS:
		if not options.has(option):
			var missing = _failure("missing_option", "Falta una opción obligatoria.")
			missing.errors[0]["option"] = option
			return missing
	if not options.format is String:
		return _option_failure("invalid_option", "format debe ser una cadena.", "format")
	if options.format != "round_robin":
		return _option_failure(
			"unsupported_format", "El generador solo admite el formato round_robin.", "format"
		)
	for option in ["season_id", "competition_id"]:
		if not options[option] is String or options[option].strip_edges().is_empty():
			return _option_failure(
				"invalid_option", "%s debe ser una cadena no vacía." % option, option
			)
	for option in ["stage_id", "group_id"]:
		if options[option] != null and (
			not options[option] is String or options[option].strip_edges().is_empty()
		):
			return _option_failure(
				"invalid_option", "%s debe ser una cadena no vacía o null." % option, option
			)
	if typeof(options.legs) != TYPE_INT or options.legs not in [1, 2]:
		return _option_failure("invalid_option", "legs debe ser 1 o 2.", "legs")
	return null


func _fixture(options: Dictionary, round_number: int,
		home_club_id: String, away_club_id: String) -> Fixture:
	var fixture = Fixture.new()
	fixture.fixture_id = _fixture_id(options, round_number, home_club_id, away_club_id)
	fixture.season_id = options.season_id
	fixture.competition_id = options.competition_id
	fixture.stage_id = options.stage_id
	fixture.group_id = options.group_id
	fixture.home_club_id = home_club_id
	fixture.away_club_id = away_club_id
	fixture.round_number = round_number
	fixture.scheduled_date = null
	fixture.metadata = {"generated": true, "generator": "league_round_robin_v1"}
	return fixture


## La codificación con longitud evita ambigüedades aunque los IDs contengan
## separadores. La jornada y las localías forman parte de la identidad.
func _fixture_id(options: Dictionary, round_number: int,
		home_club_id: String, away_club_id: String) -> String:
	return "league_fixture|%s|%s|%s|%s|r%d|%s|%s" % [
		_encode(options.season_id),
		_encode(options.competition_id),
		_encode(options.stage_id),
		_encode(options.group_id),
		round_number,
		_encode(home_club_id),
		_encode(away_club_id),
	]


func _encode(value: Variant) -> String:
	if value == null:
		return "n"
	return "s%d:%s" % [value.length(), value]


func _option_failure(code: String, message: String, option: String) -> Dictionary:
	var result = _failure(code, message)
	result.errors[0]["option"] = option
	return result


func _failure(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"data": null,
		"errors": [{"code": code, "message": message}],
	}
