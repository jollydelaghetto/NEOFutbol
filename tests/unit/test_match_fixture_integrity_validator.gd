extends SceneTree

const Validator = preload(
	"res://game/scripts/infrastructure/match_fixture_integrity_validator.gd"
)
const Club = preload("res://game/scripts/data/club_season.gd")
const Fixture = preload("res://game/scripts/data/match_fixture.gd")

var failures: Array[String] = []
var checks = 0


func _initialize() -> void:
	var validator = Validator.new()
	var clubs: Array[Club] = [
		_club("home", "season_a", "first"),
		_club("away", "season_a", "first"),
	]
	var fixtures: Array[Fixture] = [_fixture("fixture_a", "season_a", "home", "away")]
	var result = validator.validate(clubs, fixtures)
	_check(result == {"ok": true, "errors": []}, "partido válido")

	fixtures = [_fixture("missing_home", "season_a", "unknown", "away")]
	result = validator.validate(clubs, fixtures)
	_expect_club_error(result, "missing_home_club_reference",
		"El club local no existe en la temporada del partido.",
		0, "missing_home", "season_a", "unknown")

	fixtures = [_fixture("missing_away", "season_a", "home", "unknown")]
	result = validator.validate(clubs, fixtures)
	_expect_club_error(result, "missing_away_club_reference",
		"El club visitante no existe en la temporada del partido.",
		0, "missing_away", "season_a", "unknown")

	fixtures = [_fixture("both_missing", "season_a", "unknown_home", "unknown_away")]
	result = validator.validate(clubs, fixtures)
	_check(not result.ok and result.errors.size() == 2, "ambos clubes inexistentes")
	_expect_club_diagnostic(result.errors[0], "missing_home_club_reference",
		"El club local no existe en la temporada del partido.",
		0, "both_missing", "season_a", "unknown_home")
	_expect_club_diagnostic(result.errors[1], "missing_away_club_reference",
		"El club visitante no existe en la temporada del partido.",
		0, "both_missing", "season_a", "unknown_away")

	clubs = [
		_club("home", "other_season", "first"),
		_club("away", "season_a", "first"),
	]
	fixtures = [_fixture("wrong_season", "season_a", "home", "away")]
	result = validator.validate(clubs, fixtures)
	_expect_club_error(result, "missing_home_club_reference",
		"El club local no existe en la temporada del partido.",
		0, "wrong_season", "season_a", "home")

	clubs = [_club("same", "season_a", "first")]
	fixtures = [_fixture("self", "season_a", "same", "same")]
	result = validator.validate(clubs, fixtures)
	_expect_club_error(result, "self_match", "Un club no puede enfrentarse a sí mismo.",
		0, "self", "season_a", "same")

	clubs = [
		_club("home", "season_a", "first"),
		_club("away", "season_a", "first"),
	]
	fixtures = [
		_fixture("duplicate", "season_a", "home", "away"),
		_fixture("duplicate", "season_a", "away", "home"),
	]
	result = validator.validate(clubs, fixtures)
	_expect_duplicate(result, 1, 0, "duplicate", "season_a")

	clubs = [
		_club("home", "season_a", "first"),
		_club("away", "season_a", "first"),
		_club("home", "season_b", "second"),
		_club("away", "season_b", "second"),
	]
	fixtures = [
		_fixture("shared_id", "season_a", "home", "away"),
		_fixture("shared_id", "season_b", "home", "away"),
	]
	_check(validator.validate(clubs, fixtures).ok, "mismo fixture_id en temporadas distintas")

	fixtures = [
		_fixture("first_leg", "season_a", "home", "away", "league"),
		_fixture("second_leg", "season_a", "home", "away", "league"),
		_fixture("cup_match", "season_a", "home", "away", "cup"),
	]
	_check(validator.validate(clubs, fixtures).ok,
		"varios partidos entre los mismos clubes y competiciones distintas")

	clubs = [
		_club("first_club", "season_a", "first_division"),
		_club("second_club", "season_a", "second_division"),
	]
	fixtures = [_fixture("cross_division", "season_a", "first_club", "second_club")]
	_check(validator.validate(clubs, fixtures).ok, "múltiples divisiones sin restricciones")

	clubs = [
		_club("Exact Club", "Exact Season", "first"),
		_club(" visitor ", "Exact Season", "first"),
	]
	fixtures = [_fixture("Exact Fixture", "Exact Season", "Exact Club", " visitor ")]
	_check(validator.validate(clubs, fixtures).ok, "mayúsculas y espacios exactos")
	fixtures = [
		_fixture("case", "Exact Season", "exact club", " visitor "),
		_fixture("space", "Exact Season", " Exact Club ", " visitor "),
	]
	result = validator.validate(clubs, fixtures)
	_check(not result.ok and result.errors.size() == 2, "identificadores sin normalización")
	_expect_club_diagnostic(result.errors[0], "missing_home_club_reference",
		"El club local no existe en la temporada del partido.",
		0, "case", "Exact Season", "exact club")
	_expect_club_diagnostic(result.errors[1], "missing_home_club_reference",
		"El club local no existe en la temporada del partido.",
		1, "space", "Exact Season", " Exact Club ")

	clubs = [_club("known", "season_a", "first")]
	fixtures = [
		_fixture("unknown_home", "season_a", null, "known"),
		_fixture("unknown_away", "season_a", "known", null),
		_fixture("both_unknown", "season_a", null, null),
	]
	_check(validator.validate(clubs, fixtures) == {"ok": true, "errors": []},
		"referencias null permanecen desconocidas")
	fixtures = [_fixture("known_missing", "season_a", null, "missing")]
	result = validator.validate(clubs, fixtures)
	_expect_club_error(result, "missing_away_club_reference",
		"El club visitante no existe en la temporada del partido.",
		0, "known_missing", "season_a", "missing")

	var empty_clubs: Array[Club] = []
	var empty_fixtures: Array[Fixture] = []
	_check(validator.validate(empty_clubs, empty_fixtures) == {"ok": true, "errors": []},
		"colecciones vacías")

	clubs = [
		_club("home", "season_a", "first"),
		_club("away", "season_a", "first"),
	]
	fixtures = [
		_fixture("duplicate", "season_a", "home", "away"),
		_fixture("missing_home", "season_a", "unknown_home", "away"),
		_fixture("missing_away", "season_a", "home", "unknown_away"),
		_fixture("self", "season_a", "home", "home"),
		_fixture("duplicate", "season_a", "away", "home"),
	]
	var club_snapshot = _snapshot_clubs(clubs)
	var fixture_snapshot = _snapshot_fixtures(fixtures)
	var club_identity = clubs[0]
	var fixture_identity = fixtures[0]
	result = validator.validate(clubs, fixtures)
	_check(not result.ok and result.errors.size() == 4, "varios errores en una colección")
	_expect_club_diagnostic(result.errors[0], "missing_home_club_reference",
		"El club local no existe en la temporada del partido.",
		1, "missing_home", "season_a", "unknown_home")
	_expect_club_diagnostic(result.errors[1], "missing_away_club_reference",
		"El club visitante no existe en la temporada del partido.",
		2, "missing_away", "season_a", "unknown_away")
	_expect_club_diagnostic(result.errors[2], "self_match",
		"Un club no puede enfrentarse a sí mismo.", 3, "self", "season_a", "home")
	_expect_duplicate_diagnostic(result.errors[3], 4, 0, "duplicate", "season_a")
	_check(result == validator.validate(clubs, fixtures), "diagnósticos deterministas")
	_check(_snapshot_clubs(clubs) == club_snapshot, "clubes sin modificar")
	_check(_snapshot_fixtures(fixtures) == fixture_snapshot, "partidos sin modificar")
	_check(clubs[0] == club_identity and fixtures[0] == fixture_identity,
		"identidad de objetos conservada")

	if failures.is_empty():
		print("PASS: %d comprobaciones" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)


func _club(club_id: String, season_id: String, division_id: String) -> Club:
	var club = Club.new()
	club.club_id = club_id
	club.season_id = season_id
	club.division_id = division_id
	return club


func _fixture(fixture_id: String, season_id: String, home_club_id: Variant,
		away_club_id: Variant, competition_id: String = "league") -> Fixture:
	var fixture = Fixture.new()
	fixture.fixture_id = fixture_id
	fixture.season_id = season_id
	fixture.competition_id = competition_id
	fixture.stage_id = "regular"
	fixture.group_id = null
	fixture.home_club_id = home_club_id
	fixture.away_club_id = away_club_id
	fixture.round_number = 1
	fixture.scheduled_date = "2000-01-01"
	fixture.metadata = {"synthetic": true, "fixture": fixture_id}
	return fixture


func _expect_club_error(result: Dictionary, code: String, message: String,
		index: int, fixture_id: String, season_id: String, club_id: String) -> void:
	_check(not result.ok and result.errors.size() == 1, "un diagnóstico de club")
	if result.errors.size() == 1:
		_expect_club_diagnostic(result.errors[0], code, message,
			index, fixture_id, season_id, club_id)


func _expect_club_diagnostic(error: Dictionary, code: String, message: String,
		index: int, fixture_id: String, season_id: String, club_id: String) -> void:
	_check(error == {
		"code": code,
		"message": message,
		"index": index,
		"fixture_id": fixture_id,
		"season_id": season_id,
		"club_id": club_id,
	}, "diagnóstico de club estable y localizable")


func _expect_duplicate(result: Dictionary, index: int, first_index: int,
		fixture_id: String, season_id: String) -> void:
	_check(not result.ok and result.errors.size() == 1, "un identificador de partido duplicado")
	if result.errors.size() == 1:
		_expect_duplicate_diagnostic(result.errors[0], index, first_index,
			fixture_id, season_id)


func _expect_duplicate_diagnostic(error: Dictionary, index: int, first_index: int,
		fixture_id: String, season_id: String) -> void:
	_check(error == {
		"code": "duplicate_fixture",
		"message": "El identificador de partido está duplicado en la misma temporada.",
		"index": index,
		"first_index": first_index,
		"fixture_id": fixture_id,
		"season_id": season_id,
	}, "diagnóstico de duplicado estable y localizable")


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
