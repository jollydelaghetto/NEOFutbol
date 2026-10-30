extends SceneTree

const Loader = preload("res://game/scripts/services/season_session_loader.gd")
const Catalog = preload("res://game/scripts/services/season_catalog_service.gd")
const Controller = preload("res://game/scripts/services/season_controller.gd")
const Fixture = preload("res://game/scripts/data/match_fixture.gd")

const SAVE_DIRECTORY = "user://neofutbol/sporting_state"

var failures: Array[String] = []
var checks = 0
var temporary_root: String


func _initialize() -> void:
	temporary_root = "/tmp/neofutbol_session_loader_%s" % OS.get_process_id()
	_remove_tree(temporary_root)
	DirAccess.make_dir_recursive_absolute(temporary_root)
	var saves_before = _save_files()
	var loader = Loader.new()

	# El formato y el horizonte se validan antes de resolver una ruta de pack.
	for invalid_id in ["", "1982", "1982-3", "1982-83/../../tmp", "../1982-83",
			"1982-83\\..\\tmp", " 1982-83", "1982-83 "]:
		_expect_error(loader.prepare_session(invalid_id, temporary_root),
			"invalid_season_id", "identificador inseguro %s" % invalid_id)
	for outside_id in ["1981-82", "1982-84", "2011-12", "9999-00"]:
		_expect_error(loader.prepare_session(outside_id, temporary_root),
			"season_out_of_horizon", "temporada fuera del horizonte %s" % outside_id)

	var first_missing = loader.prepare_session("1982-83", temporary_root)
	_expect_error(first_missing, "missing_required_files", "límite inicial reconocido")
	_check(first_missing.errors[0].missing_content == Catalog.REQUIRED_FILES,
		"directorio inicial inexistente enumera los cinco archivos")
	var last_missing = loader.prepare_session("2010-11", temporary_root)
	_expect_error(last_missing, "missing_required_files", "límite final reconocido")
	_check(last_missing.errors[0].pack_path == temporary_root.path_join("2010-11"),
		"resuelve exclusivamente el directorio del límite final")

	var pack_path = temporary_root.path_join("1982-83")
	_write_valid_pack("1982-83")
	DirAccess.remove_absolute(pack_path.path_join("fixtures.json"))
	var incomplete = loader.prepare_session("1982-83", temporary_root)
	_expect_error(incomplete, "missing_required_files", "archivo obligatorio ausente")
	_check(incomplete.errors[0].missing_content == ["fixtures.json"],
		"archivo ausente localizado de forma determinista")

	_write_valid_pack("1982-83")
	_write_text(pack_path.path_join("manifest.json"), "{ invalid")
	_expect_error(loader.prepare_session("1982-83", temporary_root),
		"json_syntax", "JSON inválido")

	_write_valid_pack("1982-83")
	_write_json(pack_path.path_join("manifest.json"), _manifest("1983-84"))
	_expect_error(loader.prepare_session("1982-83", temporary_root),
		"manifest_season_mismatch", "manifest de otra temporada")

	_write_valid_pack("1982-83")
	var invalid_rules = _rules("1982-83")
	invalid_rules.competition_id = 7
	_write_json(pack_path.path_join("rules.json"), invalid_rules)
	_expect_error(loader.prepare_session("1982-83", temporary_root),
		"invalid_type", "reglas inválidas")

	_write_valid_pack("1982-83")
	_write_json(pack_path.path_join("players.json"), [{
		"player_id": "player_a", "season_id": "1982-83", "club_id": "missing_club",
		"historical_data": {}, "game_data": {}, "metadata": {},
	}])
	_expect_error(loader.prepare_session("1982-83", temporary_root),
		"missing_club_reference", "referencia de jugador inválida")

	_write_valid_pack("1982-83")
	_write_json(pack_path.path_join("fixtures.json"), [
		_fixture("1982-83", "fixture_invalid", "missing_club", "club_b")
	])
	_expect_error(loader.prepare_session("1982-83", temporary_root),
		"missing_home_club_reference", "referencia de calendario inválida")

	_write_valid_pack("1982-83", [])
	var empty_calendar = loader.prepare_session("1982-83", temporary_root)
	_expect_error(empty_calendar, "empty_calendar", "pack válido sin calendario jugable")
	_check(not _catalog_entry("1982-83").playable,
		"catálogo también rechaza el calendario vacío")

	_write_valid_pack("1982-83", null, [], {})
	var no_provenance = loader.prepare_session("1982-83", temporary_root)
	_expect_error(no_provenance, "missing_provenance", "procedencia insuficiente")
	_check(not _catalog_entry("1982-83").playable,
		"catálogo comparte el rechazo de procedencia")

	var ambiguous_fixtures = [
		_fixture("1982-83", "fixture_regular", "club_a", "club_b", "regular", "group_a"),
		_fixture("1982-83", "fixture_playoff", "club_b", "club_a", "playoff", "group_a"),
	]
	_write_valid_pack("1982-83", ambiguous_fixtures)
	var ambiguous = loader.prepare_session("1982-83", temporary_root)
	_expect_error(ambiguous, "ambiguous_sporting_selection", "selección deportiva ambigua")
	_check(ambiguous.errors[0].selection_count == 2, "alternativas ambiguas contabilizadas")
	var ambiguous_catalog = _catalog_entry("1982-83")
	_check(not ambiguous_catalog.playable
		and ambiguous_catalog.diagnostics[0].code == "ambiguous_sporting_selection",
		"catálogo y cargador comparten la regla de selección única")

	# Pack completo: la única selección compatible se deriva sin normalizaciones.
	_write_valid_pack("1982-83")
	_check(_catalog_entry("1982-83").playable, "catálogo acepta el pack completo")
	_write_text(pack_path.path_join("fixtures.json"), "[ invalid")
	_expect_error(loader.prepare_session("1982-83", temporary_root),
		"json_syntax", "preparación relee un pack modificado tras catalogarlo")
	_write_valid_pack("1982-83")
	var files_before = _pack_snapshot(pack_path)
	var first = loader.prepare_session("1982-83", temporary_root)
	_check(first.ok and first.errors.is_empty(), "pack sintético completo")
	_check(first.data.season_id == "1982-83", "temporada exacta devuelta")
	_check(first.data.selection == {
		"season_id": "1982-83", "competition_id": "league_1982-83",
		"stage_id": "regular", "group_id": "group_a",
	}, "selección deportiva exacta y determinista")
	_check(first.data.controller is Controller, "controlador inicializado devuelto")
	_check(first.data.calendar is Array and first.data.calendar.size() == 1
		and first.data.calendar[0] is Fixture, "calendario tipado devuelto")
	_check(first.data.presentation == {
		"season_name": "1982-83", "competition_name": "league_1982-83",
	}, "metadatos de presentación derivados")
	_check(first.data.origin.root_path == temporary_root
		and first.data.origin.pack_path == pack_path,
		"origen identifica raíz y pack calculados")
	_check(first.data.origin.sources == ["synthetic-test-source"]
		and first.data.origin.checksum == {"pack": "synthetic-test-checksum"},
		"declaraciones de procedencia conservadas")
	_check(not first.data.origin.checksum_verified
		and not first.data.origin.reuse_rights_verified,
		"declaraciones no se presentan como verificación criptográfica o jurídica")
	var catalog_entry = _catalog_entry("1982-83")
	_check(catalog_entry.playable and catalog_entry.status_code == "playable",
		"pack aceptado por cargador también es jugable para el catálogo")

	var context = first.data.controller.get_session_context()
	var results = first.data.controller.get_results()
	_check(context.ok and context.data.selection == first.data.selection,
		"controlador conserva la selección exacta")
	_check(results.ok and results.data.results.is_empty(),
		"sesión inicial sin resultados ficticios")
	_check(context.data.fixtures.size() == 1
		and context.data.fixtures[0].metadata.nested.value == "original",
		"controlador contiene el calendario original")

	# Las mutaciones del consumidor no alcanzan el controlador ni otra carga.
	first.data.calendar[0].home_club_id = "mutated_home"
	first.data.calendar[0].metadata.nested.value = "mutated_calendar"
	first.data.selection.stage_id = "mutated_stage"
	first.data.origin.sources.append("mutated_source")
	var fresh_context = first.data.controller.get_session_context()
	_check(fresh_context.data.selection.stage_id == "regular"
		and fresh_context.data.fixtures[0].home_club_id == "club_a",
		"selección y calendario no comparten referencias con el controlador")
	_check(fresh_context.data.fixtures[0].metadata.nested.value == "original",
		"metadata anidada aislada del controlador")

	var second = loader.prepare_session("1982-83", temporary_root)
	_check(second.ok and second.data.controller != first.data.controller,
		"segunda carga crea un controlador independiente")
	_check(second.data.calendar[0].home_club_id == "club_a"
		and second.data.calendar[0].metadata.nested.value == "original",
		"segunda carga relee datos sin mutaciones previas")
	_check(second.data.selection.stage_id == "regular"
		and second.data.origin.sources == ["synthetic-test-source"],
		"selección y origen independientes entre sesiones")
	_check(_pack_snapshot(pack_path) == files_before, "archivos históricos intactos")

	# El otro extremo del horizonte puede preparar su propia sesión.
	_write_valid_pack("2010-11")
	var last = loader.prepare_session("2010-11", temporary_root)
	_check(last.ok and last.data.selection == {
		"season_id": "2010-11", "competition_id": "league_2010-11",
		"stage_id": "regular", "group_id": "group_a",
	}, "límite final prepara una selección exacta")
	_check(_catalog_entry("2010-11").playable,
		"coherencia del catálogo en el límite final")

	_check(_save_files() == saves_before, "la preparación no crea ni modifica guardados")
	_remove_tree(temporary_root)
	_finish()


func _catalog_entry(season_id: String) -> Dictionary:
	var catalog = Catalog.new().get_catalog(temporary_root)
	for season in catalog.data.seasons:
		if season.season_id == season_id:
			return season
	return {}


func _write_valid_pack(season_id: String, fixtures: Variant = null,
		sources: Array = ["synthetic-test-source"],
		checksum: Dictionary = {"pack": "synthetic-test-checksum"}) -> void:
	var pack_path = temporary_root.path_join(season_id)
	DirAccess.make_dir_recursive_absolute(pack_path)
	var manifest = _manifest(season_id)
	manifest.sources = sources.duplicate(true)
	manifest.checksum = checksum.duplicate(true)
	# Campo ajeno permitido: nunca se usa como ruta de entrada.
	manifest["pack_path"] = "../../untrusted"
	_write_json(pack_path.path_join("manifest.json"), manifest)
	_write_json(pack_path.path_join("rules.json"), _rules(season_id))
	_write_json(pack_path.path_join("clubs.json"), [
		{"club_id": "club_a", "season_id": season_id, "division_id": "first"},
		{"club_id": "club_b", "season_id": season_id, "division_id": "first"},
	])
	_write_json(pack_path.path_join("players.json"), [{
		"player_id": "player_a", "season_id": season_id, "club_id": "club_a",
		"historical_data": {}, "game_data": {}, "metadata": {"reviewed": null},
	}])
	var calendar = fixtures
	if calendar == null:
		calendar = [_fixture(season_id, "fixture_1", "club_a", "club_b")]
	_write_json(pack_path.path_join("fixtures.json"), calendar)


func _manifest(season_id: String) -> Dictionary:
	return {
		"schema_version": 1, "season_id": season_id,
		"sources": ["synthetic-test-source"],
		"checksum": {"pack": "synthetic-test-checksum"},
	}


func _rules(season_id: String) -> Dictionary:
	return {
		"season_id": season_id, "competition_id": "league_%s" % season_id,
		"points_win": 3, "points_draw": 1, "points_loss": 0,
		"team_count": 2, "round_count": 1,
		"tiebreakers": ["goal_difference"],
		"substitution_rules": {}, "promotion_relegation_rules": {},
		"competition_format": {
			"kind": "round_robin", "legs": null, "head_to_head_policy": "single_pass"
		},
	}


func _fixture(season_id: String, fixture_id: String, home_id: Variant, away_id: Variant,
		stage_id: Variant = "regular", group_id: Variant = "group_a") -> Dictionary:
	return {
		"fixture_id": fixture_id, "season_id": season_id,
		"competition_id": "league_%s" % season_id,
		"stage_id": stage_id, "group_id": group_id,
		"home_club_id": home_id, "away_club_id": away_id,
		"round_number": 1, "scheduled_date": "%s-09-05" % season_id.left(4),
		"metadata": {"nested": {"value": "original"}},
	}


func _pack_snapshot(pack_path: String) -> Dictionary:
	var snapshot: Dictionary = {}
	for file_name in Catalog.REQUIRED_FILES:
		var file = FileAccess.open(pack_path.path_join(file_name), FileAccess.READ)
		if file == null:
			snapshot[file_name] = null
			continue
		snapshot[file_name] = file.get_as_text()
		file.close()
	return snapshot


func _save_files() -> Array[String]:
	var files: Array[String] = []
	var directory = DirAccess.open(SAVE_DIRECTORY)
	if directory == null:
		return files
	directory.list_dir_begin()
	var entry = directory.get_next()
	while not entry.is_empty():
		if not directory.current_is_dir():
			files.append(entry)
		entry = directory.get_next()
	directory.list_dir_end()
	files.sort()
	return files


func _write_json(path: String, value: Variant) -> void:
	_write_text(path, JSON.stringify(value))


func _write_text(path: String, value: String) -> void:
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		failures.append("no se pudo escribir %s" % path)
		return
	file.store_string(value)
	file.close()


func _remove_tree(path: String) -> void:
	var directory = DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry = directory.get_next()
	while not entry.is_empty():
		var child = path.path_join(entry)
		if directory.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
		entry = directory.get_next()
	directory.list_dir_end()
	DirAccess.remove_absolute(path)


func _expect_error(result: Dictionary, code: String, description: String) -> void:
	_check(not result.ok and result.data == null, "%s falla sin preparación parcial" % description)
	_check(not result.errors.is_empty(), "%s incluye diagnóstico" % description)
	if not result.errors.is_empty():
		_check(result.errors[0].code == code,
			"%s usa código %s" % [description, code])


func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)


func _finish() -> void:
	if failures.is_empty():
		print("PASS: %d comprobaciones" % checks)
		quit(0)
		return
	for failure in failures:
		push_error("FAIL: %s" % failure)
	print("FAIL: %d de %d comprobaciones" % [failures.size(), checks])
	quit(1)
