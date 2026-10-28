extends SceneTree

const Service = preload("res://game/scripts/services/calendar_service.gd")
const Fixture = preload("res://game/scripts/data/match_fixture.gd")

var failures: Array[String] = []
var checks = 0


func _initialize() -> void:
	var service = Service.new()
	var fixtures: Array[Fixture] = [
		_fixture("zeta", "season_a", "league", "regular", "group_a",
			"club_a", "club_b", 2, "2000-01-05"),
		_fixture("shared_id", "season_b", "league", "regular", "group_a",
			"club_a", "club_b", 1, "2001-01-01"),
		_fixture("null_fields", "season_a", null, null, null,
			null, "club_a", null, null),
		_fixture("alpha", "season_a", "cup", "knockout", null,
			"club_b", "club_a", 1, "2000-01-03"),
		_fixture("beta", "season_a", "league", "regular", "group_b",
			"club_a", "club_c", 1, null),
		_fixture("gamma", "season_a", "league", "second", "group_a",
			"club_c", "Club_A", 3, "2000-01-01"),
		_fixture("shared_id", "season_a", "league", "regular", "group_a",
			"club_b", "club_a", 2, "2000-01-05"),
	]
	var original_ids = _ids(fixtures)
	var snapshot = _snapshot(fixtures)

	_expect_ids(service.get_fixtures(fixtures, "season_a"),
		["zeta", "null_fields", "alpha", "beta", "gamma", "shared_id"],
		"selección por temporada en orden original")
	_expect_ids(service.get_fixtures(fixtures, "season_b"), ["shared_id"],
		"temporada distinta con fixture_id coincidente")
	_expect_ids(service.get_fixtures(fixtures, "Season_A"), [],
		"temporada comparada exactamente")

	_expect_ids(service.get_fixtures(fixtures, "season_a", {"competition_id": "league"}),
		["zeta", "beta", "gamma", "shared_id"], "filtro de competición")
	_expect_ids(service.get_fixtures(fixtures, "season_a", {"competition_id": "cup"}),
		["alpha"], "otra competición")
	_expect_ids(service.get_fixtures(fixtures, "season_a", {"competition_id": "League"}),
		[], "competición exacta")
	_expect_ids(service.get_fixtures(fixtures, "season_a", {"stage_id": "regular"}),
		["zeta", "beta", "shared_id"], "filtro de fase")
	_expect_ids(service.get_fixtures(fixtures, "season_a", {"group_id": "group_a"}),
		["zeta", "gamma", "shared_id"], "filtro de grupo")
	_expect_ids(service.get_fixtures(fixtures, "season_a", {
		"competition_id": "league", "stage_id": "regular", "group_id": "group_a"
	}), ["zeta", "shared_id"], "filtros combinados")

	_expect_ids(service.get_fixtures(fixtures, "season_a"),
		["zeta", "null_fields", "alpha", "beta", "gamma", "shared_id"],
		"filtro omitido conserva valores conocidos y null")
	_expect_ids(service.get_fixtures(fixtures, "season_a", {"competition_id": null}),
		["null_fields"], "competición null explícita")
	_expect_ids(service.get_fixtures(fixtures, "season_a", {"stage_id": null}),
		["null_fields"], "fase null explícita")
	_expect_ids(service.get_fixtures(fixtures, "season_a", {"group_id": null}),
		["null_fields", "alpha"], "grupo null explícito")

	_expect_ids(service.get_round_fixtures(fixtures, "season_a", 1),
		["alpha", "beta"], "partidos de una jornada")
	_expect_ids(service.get_round_fixtures(fixtures, "season_a", 1,
		{"competition_id": "league"}), ["beta"], "jornada con filtros")
	_expect_ids(service.get_round_fixtures(fixtures, "season_a", 99), [],
		"jornada sin resultados")
	_check(service.get_round_numbers(fixtures, "season_a") == [1, 2, 3],
		"jornadas conocidas ordenadas y únicas")
	_check(service.get_round_numbers(fixtures, "season_a", {"stage_id": "regular"}) == [1, 2],
		"jornadas de una fase")
	_check(service.get_round_numbers(fixtures, "season_a", {"competition_id": null}).is_empty(),
		"jornada null no se inventa")

	_expect_ids(service.get_club_fixtures(fixtures, "season_a", "club_a"),
		["zeta", "null_fields", "alpha", "beta", "shared_id"],
		"partidos del club como local y visitante")
	_expect_ids(service.get_club_fixtures(fixtures, "season_a", "Club_A"), ["gamma"],
		"identificador de club exacto")
	_expect_ids(service.get_club_fixtures(fixtures, "season_a", " club_a "), [],
		"espacios del identificador no normalizados")
	_expect_ids(service.get_club_fixtures(fixtures, "season_a", "missing"), [],
		"club sin partidos")

	_expect_ids(service.get_fixtures(fixtures, "season_a", {}, Service.Order.ROUND),
		["alpha", "beta", "zeta", "shared_id", "gamma", "null_fields"],
		"orden determinista por jornada con null al final")
	_expect_ids(service.get_fixtures(fixtures, "season_a", {}, Service.Order.DATE),
		["gamma", "alpha", "zeta", "shared_id", "null_fields", "beta"],
		"orden determinista por fecha con null al final")
	_expect_ids(service.get_fixtures(fixtures, "season_a", {}, Service.Order.FIXTURE_ID),
		["alpha", "beta", "gamma", "null_fields", "shared_id", "zeta"],
		"orden determinista por identificador")
	_expect_ids(service.get_round_fixtures(fixtures, "season_a", 2, {},
		Service.Order.FIXTURE_ID), ["shared_id", "zeta"],
		"orden solicitado en consulta de jornada")
	_expect_ids(service.get_club_fixtures(fixtures, "season_a", "club_a", {},
		Service.Order.DATE), ["alpha", "zeta", "shared_id", "null_fields", "beta"],
		"orden solicitado en consulta de club")

	var empty: Array[Fixture] = []
	_check(service.get_fixtures(empty, "season_a").is_empty(), "colección vacía")
	_check(service.get_round_numbers(empty, "season_a").is_empty(),
		"jornadas de colección vacía")
	_expect_ids(service.get_fixtures(fixtures, "missing_season"), [],
		"selección sin resultados")

	var filters = {"competition_id": "league", "group_id": "group_a"}
	var first = service.get_fixtures(fixtures, "season_a", filters, Service.Order.DATE)
	var second = service.get_fixtures(fixtures, "season_a", filters, Service.Order.DATE)
	_check(_ids(first) == _ids(second), "consultas repetidas con el mismo orden")
	_check(_same_objects(first, second), "consultas repetidas conservan los objetos")
	_check(filters == {"competition_id": "league", "group_id": "group_a"},
		"filtros sin modificar")
	_check(_ids(fixtures) == original_ids, "colección de entrada sin reordenar")
	_check(_snapshot(fixtures) == snapshot, "modelos de entrada sin modificar")
	_check(service.get_fixtures(fixtures, "season_a")[0] == fixtures[0],
		"identidad de objetos conservada")

	if failures.is_empty():
		print("PASS: %d comprobaciones" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)


func _fixture(fixture_id: String, season_id: String, competition_id: Variant,
		stage_id: Variant, group_id: Variant, home_club_id: Variant,
		away_club_id: Variant, round_number: Variant, scheduled_date: Variant) -> Fixture:
	var fixture = Fixture.new()
	fixture.fixture_id = fixture_id
	fixture.season_id = season_id
	fixture.competition_id = competition_id
	fixture.stage_id = stage_id
	fixture.group_id = group_id
	fixture.home_club_id = home_club_id
	fixture.away_club_id = away_club_id
	fixture.round_number = round_number
	fixture.scheduled_date = scheduled_date
	fixture.metadata = {"synthetic": true, "fixture": fixture_id}
	return fixture


func _expect_ids(actual: Array[Fixture], expected: Array, message: String) -> void:
	_check(_ids(actual) == expected, message)


func _ids(fixtures: Array[Fixture]) -> Array[String]:
	var ids: Array[String] = []
	for fixture in fixtures:
		ids.append(fixture.fixture_id)
	return ids


func _same_objects(left: Array[Fixture], right: Array[Fixture]) -> bool:
	if left.size() != right.size():
		return false
	for index in left.size():
		if left[index] != right[index]:
			return false
	return true


func _snapshot(fixtures: Array[Fixture]) -> Array[Dictionary]:
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
