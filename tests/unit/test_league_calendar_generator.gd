extends SceneTree

const Generator = preload("res://game/scripts/services/league_calendar_generator.gd")
const Calendar = preload("res://game/scripts/services/calendar_service.gd")
const Validator = preload(
	"res://game/scripts/infrastructure/match_fixture_integrity_validator.gd"
)
const Club = preload("res://game/scripts/data/club_season.gd")
const Fixture = preload("res://game/scripts/data/match_fixture.gd")

var failures: Array[String] = []
var checks = 0


func _initialize() -> void:
	var generator = Generator.new()
	_assert_schedule(generator, 2, 1, 1, 1)
	_assert_schedule(generator, 4, 1, 3, 6)
	_assert_schedule(generator, 6, 2, 10, 30)
	_assert_schedule(generator, 18, 1, 17, 153)
	_assert_schedule(generator, 18, 2, 34, 306)
	_assert_schedule(generator, 3, 1, 3, 3)
	_assert_schedule(generator, 5, 1, 5, 10)

	var clubs = _clubs(4)
	var options = _options()
	var club_snapshot = _snapshot_clubs(clubs)
	var options_snapshot = options.duplicate(true)
	var first = generator.generate(clubs, options)
	var second = generator.generate(clubs, options)
	_check(first.ok and second.ok, "generaciones repetidas correctas")
	if first.ok and second.ok:
		_check(_snapshot_fixtures(first.data) == _snapshot_fixtures(second.data),
			"mismos parámetros producen el mismo calendario")
		_check(_fixture_ids(first.data) == _fixture_ids(second.data),
			"identificadores estables entre ejecuciones")
		_check(Validator.new().validate(clubs, first.data) == {"ok": true, "errors": []},
			"integración con MatchFixtureIntegrityValidator")
		var calendar = Calendar.new()
		_check(calendar.get_round_numbers(first.data, "synthetic_season") == [1, 2, 3],
			"jornadas consultables con CalendarService")
		_check(calendar.get_round_fixtures(first.data, "synthetic_season", 1).size() == 2,
			"partidos de jornada consultables")
		_check(calendar.get_fixtures(first.data, "synthetic_season", {
			"competition_id": "synthetic_league",
			"stage_id": "regular",
			"group_id": null,
		}).size() == 6, "fase y grupo consultables")
	_check(_snapshot_clubs(clubs) == club_snapshot, "clubes de entrada sin modificar")
	_check(options == options_snapshot, "opciones sin modificar")

	var exact_options = _options(" Exact Season ", " League A ", " Stage 1 ", " Group A ", 1)
	var exact_clubs = _clubs(4, " Exact Season ", " Club ")
	var exact = generator.generate(exact_clubs, exact_options)
	_check(exact.ok, "identificadores exactos con mayúsculas y espacios")
	if exact.ok:
		for fixture in exact.data:
			_check(fixture.season_id == " Exact Season ", "temporada exacta asignada")
			_check(fixture.competition_id == " League A ", "competición exacta asignada")
			_check(fixture.stage_id == " Stage 1 ", "fase exacta asignada")
			_check(fixture.group_id == " Group A ", "grupo exacto asignado")
	var other_options = exact_options.duplicate(true)
	other_options.season_id = "Other Season"
	var other_clubs = _clubs(4, "Other Season", " Club ")
	var other = generator.generate(other_clubs, other_options)
	_check(other.ok, "otra temporada válida")
	if exact.ok and other.ok:
		_check(_fixture_ids(exact.data) != _fixture_ids(other.data),
			"otra temporada produce identificadores diferentes")
	other_options = _options(" Exact Season ", "Other League", " Stage 1 ", " Group A ", 1)
	other = generator.generate(exact_clubs, other_options)
	_check(other.ok, "otra competición válida")
	if exact.ok and other.ok:
		_check(_fixture_ids(exact.data) != _fixture_ids(other.data),
			"otra competición produce identificadores diferentes")

	var duplicate_clubs: Array[Club] = [
		_club("duplicate", "synthetic_season"),
		_club("duplicate", "synthetic_season"),
	]
	var result = generator.generate(duplicate_clubs, _options())
	_expect_error(result, "duplicate_club")
	_check(result.errors[0].get("index") == 1
		and result.errors[0].get("first_index") == 0
		and result.errors[0].get("club_id") == "duplicate",
		"diagnóstico localizable de club duplicado")
	var exact_case_clubs: Array[Club] = [
		_club("Club", "synthetic_season"),
		_club("club", "synthetic_season"),
	]
	_check(generator.generate(exact_case_clubs, _options()).ok,
		"identificadores parecidos no se consideran duplicados")

	var mismatched = _clubs(3)
	mismatched[1].season_id = "other_season"
	result = generator.generate(mismatched, _options())
	_expect_error(result, "season_mismatch")
	_check(result.errors[0].get("index") == 1
		and result.errors[0].get("club_id") == "club_02"
		and result.errors[0].get("season_id") == "other_season"
		and result.errors[0].get("expected_season_id") == "synthetic_season",
		"diagnóstico localizable de temporada incompatible")

	var empty_clubs: Array[Club] = []
	_expect_error(generator.generate(empty_clubs, _options()), "insufficient_clubs")
	var one_club: Array[Club] = [_club("only", "synthetic_season")]
	_expect_error(generator.generate(one_club, _options()), "insufficient_clubs")
	var invalid_clubs: Array[Club] = [
		_club("valid", "synthetic_season"),
		_club(" ", "synthetic_season"),
	]
	result = generator.generate(invalid_clubs, _options())
	_expect_error(result, "invalid_club")
	_check(result.errors[0].get("index") == 1, "índice del club inválido")

	for option in ["format", "season_id", "competition_id", "stage_id", "group_id", "legs"]:
		var missing = _options()
		missing.erase(option)
		result = generator.generate(clubs, missing)
		_expect_error(result, "missing_option")
		_check(result.errors[0].get("option") == option, "opción ausente " + option)
	for option in ["season_id", "competition_id"]:
		for value in [null, 1, true, [], {}, "", " "]:
			var invalid = _options()
			invalid[option] = value
			result = generator.generate(clubs, invalid)
			_expect_option_error(result, "invalid_option", option)
	for option in ["stage_id", "group_id"]:
		for value in [1, true, [], {}, "", " "]:
			var invalid = _options()
			invalid[option] = value
			result = generator.generate(clubs, invalid)
			_expect_option_error(result, "invalid_option", option)
	for value in [0, 3, -1, 1.0, true, "2", null]:
		var invalid = _options()
		invalid.legs = value
		result = generator.generate(clubs, invalid)
		_expect_option_error(result, "invalid_option", "legs")
	for value in [null, 1, true, [], {}]:
		var invalid = _options()
		invalid.format = value
		result = generator.generate(clubs, invalid)
		_expect_option_error(result, "invalid_option", "format")
	var unsupported = _options()
	unsupported.format = "knockout"
	_expect_option_error(generator.generate(clubs, unsupported), "unsupported_format", "format")
	_check(generator.generate(clubs, unsupported) == generator.generate(clubs, unsupported),
		"diagnósticos deterministas")

	if failures.is_empty():
		print("PASS: %d comprobaciones" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)


func _assert_schedule(generator: Generator, club_count: int, legs: int,
		expected_rounds: int, expected_matches: int) -> void:
	var clubs = _clubs(club_count)
	var options = _options("synthetic_season", "synthetic_league", "regular", null, legs)
	var result = generator.generate(clubs, options)
	_check(result.ok and result.errors.is_empty(), "%d clubes y %d vueltas" % [club_count, legs])
	if not result.ok:
		return
	var fixtures: Array[Fixture] = result.data
	_check(fixtures.size() == expected_matches,
		"número de partidos %d clubes %d vueltas" % [club_count, legs])
	_check(fixtures.is_typed() and fixtures.get_typed_script() == Fixture,
		"colección MatchFixture tipada")
	var ids: Dictionary = {}
	var pairs: Dictionary = {}
	var directed: Dictionary = {}
	var round_clubs: Dictionary = {}
	var home_counts: Dictionary = {}
	var away_counts: Dictionary = {}
	var fields_valid = true
	var dates_unknown = true
	var no_self_matches = true
	var unique_ids = true
	for fixture in fixtures:
		if ids.has(fixture.fixture_id):
			unique_ids = false
		ids[fixture.fixture_id] = true
		fields_valid = fields_valid and fixture.season_id == options.season_id \
			and fixture.competition_id == options.competition_id \
			and fixture.stage_id == options.stage_id and fixture.group_id == options.group_id
		dates_unknown = dates_unknown and fixture.scheduled_date == null
		no_self_matches = no_self_matches and fixture.home_club_id != fixture.away_club_id
		var pair = [fixture.home_club_id, fixture.away_club_id]
		pair.sort()
		var pair_key = JSON.stringify(pair)
		pairs[pair_key] = pairs.get(pair_key, 0) + 1
		var directed_key = JSON.stringify([fixture.home_club_id, fixture.away_club_id])
		directed[directed_key] = directed.get(directed_key, 0) + 1
		if not round_clubs.has(fixture.round_number):
			round_clubs[fixture.round_number] = {}
		var participants: Dictionary = round_clubs[fixture.round_number]
		if participants.has(fixture.home_club_id) or participants.has(fixture.away_club_id):
			no_self_matches = false
		participants[fixture.home_club_id] = true
		participants[fixture.away_club_id] = true
		home_counts[fixture.home_club_id] = home_counts.get(fixture.home_club_id, 0) + 1
		away_counts[fixture.away_club_id] = away_counts.get(fixture.away_club_id, 0) + 1
	_check(unique_ids, "identificadores únicos")
	_check(fields_valid, "campos configurables asignados")
	_check(dates_unknown, "fechas desconocidas como null")
	_check(no_self_matches, "un partido máximo por club y jornada")
	_check(pairs.size() == club_count * (club_count - 1) / 2,
		"todas las parejas presentes")
	for count in pairs.values():
		_check(count == legs, "un enfrentamiento por pareja y vuelta")
	var expected_round_numbers: Array[int] = []
	for round_number in range(1, expected_rounds + 1):
		expected_round_numbers.append(round_number)
	_check(Calendar.new().get_round_numbers(fixtures, options.season_id) == expected_round_numbers,
		"jornadas consecutivas desde 1")
	_check(round_clubs.size() == expected_rounds, "número esperado de jornadas")
	var matches_per_round = int(club_count / 2)
	for round_number in expected_round_numbers:
		_check(Calendar.new().get_round_fixtures(
			fixtures, options.season_id, round_number
		).size() == matches_per_round, "partidos esperados por jornada")
	for club in clubs:
		var home = home_counts.get(club.club_id, 0)
		var away = away_counts.get(club.club_id, 0)
		_check(abs(home - away) <= 1, "localía razonablemente equilibrada")
	if legs == 2:
		var first_leg_matches = int(fixtures.size() / 2)
		for index in first_leg_matches:
			var first = fixtures[index]
			var second = fixtures[first_leg_matches + index]
			_check(first.home_club_id == second.away_club_id
				and first.away_club_id == second.home_club_id,
				"local y visitante invertidos en segunda vuelta")
			_check(second.round_number == first.round_number + expected_rounds / 2,
				"jornada correspondiente de segunda vuelta")
			_check(directed[JSON.stringify([first.home_club_id, first.away_club_id])] == 1
				and directed[JSON.stringify([first.away_club_id, first.home_club_id])] == 1,
				"cada orientación aparece una vez")
	_check(Validator.new().validate(clubs, fixtures).ok,
		"calendario compatible con el validador")


func _options(season_id: String = "synthetic_season",
		competition_id: String = "synthetic_league", stage_id: Variant = "regular",
		group_id: Variant = null, legs: int = 1) -> Dictionary:
	return {
		"format": "round_robin",
		"season_id": season_id,
		"competition_id": competition_id,
		"stage_id": stage_id,
		"group_id": group_id,
		"legs": legs,
	}


func _clubs(count: int, season_id: String = "synthetic_season",
		prefix: String = "club_") -> Array[Club]:
	var clubs: Array[Club] = []
	for index in count:
		clubs.append(_club("%s%02d" % [prefix, index + 1], season_id))
	return clubs


func _club(club_id: String, season_id: String) -> Club:
	var club = Club.new()
	club.club_id = club_id
	club.season_id = season_id
	club.division_id = "synthetic_division"
	return club


func _expect_option_error(result: Dictionary, code: String, option: String) -> void:
	_expect_error(result, code)
	if not result.errors.is_empty():
		_check(result.errors[0].get("option") == option, "opción del diagnóstico " + option)


func _expect_error(result: Dictionary, code: String) -> void:
	_check(not result.ok and result.data == null, "fallo sin calendario parcial " + code)
	_check(result.errors.size() == 1, "un diagnóstico " + code)
	if not result.errors.is_empty():
		_check(result.errors[0].get("code") == code, "código " + code)
		_check(result.errors[0].get("message") is String
			and not result.errors[0].message.is_empty(), "mensaje " + code)


func _fixture_ids(fixtures: Array[Fixture]) -> Array[String]:
	var ids: Array[String] = []
	for fixture in fixtures:
		ids.append(fixture.fixture_id)
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


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
