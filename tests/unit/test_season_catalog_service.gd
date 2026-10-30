extends SceneTree

const Catalog = preload("res://game/scripts/services/season_catalog_service.gd")

var failures: Array[String] = []
var checks = 0
var temporary_root: String


func _initialize() -> void:
	temporary_root = "/tmp/neofutbol_catalog_%s" % OS.get_process_id()
	_remove_tree(temporary_root)
	DirAccess.make_dir_recursive_absolute(temporary_root)

	var real = Catalog.new().get_catalog()
	_check(real.ok and real.errors.is_empty(), "consulta del catálogo real")
	_check(real.data.seasons.size() == 29, "horizonte de 29 temporadas")
	_check(real.data.horizon.first_season_id == "1982-83"
		and real.data.horizon.last_season_id == "2010-11", "límites inclusivos")
	var ids: Array[String] = []
	for season in real.data.seasons:
		ids.append(season.season_id)
	_check(ids[0] == "1982-83" and ids[17] == "1999-00" and ids[-1] == "2010-11",
		"identificadores y cambio de siglo")
	var unique: Dictionary = {}
	for season_id in ids:
		unique[season_id] = true
	_check(unique.size() == 29, "sin temporadas duplicadas")
	var real_first = real.data.seasons[0]
	_check(real_first.data_discovered and not real_first.data_validated
		and not real_first.playable, "pack real descubierto pero incompleto")
	_check(real_first.status_code == "incomplete"
		and real_first.missing_content == ["fixtures.json"], "carencia real explicada")
	for index in range(1, real.data.seasons.size()):
		_check(not real.data.seasons[index].data_discovered
			and not real.data.seasons[index].playable,
			"temporada ausente no jugable %s" % real.data.seasons[index].season_id)

	var empty = Catalog.new().get_catalog(temporary_root)
	_check(empty.data.seasons.size() == 29, "horizonte independiente del disco")
	_check(_all_unavailable(empty.data.seasons), "raíz vacía sin falsos positivos")

	var pack_path = temporary_root.path_join("1982-83")
	DirAccess.make_dir_recursive_absolute(pack_path)
	_write_json(pack_path.path_join("manifest.json"), _manifest())
	var partial = Catalog.new().get_catalog(temporary_root).data.seasons[0]
	_check(partial.data_discovered and partial.status_code == "incomplete",
		"pack parcial descubierto")
	_check(not partial.data_validated and not partial.playable,
		"pack parcial no validado ni jugable")
	_check(partial.missing_content == [
		"rules.json", "clubs.json", "players.json", "fixtures.json"
	], "lista determinista de archivos pendientes")

	_write_text(pack_path.path_join("manifest.json"), "{ invalid")
	_write_complete_pack(pack_path, [])
	var malformed = Catalog.new().get_catalog(temporary_root).data.seasons[0]
	_check(malformed.status_code == "invalid" and not malformed.data_validated,
		"JSON inválido rechazado")
	_check(not malformed.diagnostics.is_empty()
		and malformed.diagnostics[0].code == "json_syntax", "diagnóstico del parser conservado")

	_write_json(pack_path.path_join("manifest.json"), _manifest())
	var empty_calendar = Catalog.new().get_catalog(temporary_root).data.seasons[0]
	_check(empty_calendar.data_validated, "pack vacío puede ser estructuralmente válido")
	_check(empty_calendar.validation_scope == "structural_and_referential"
		and empty_calendar.provenance_declared, "alcance y procedencia declarados")
	_check(not empty_calendar.playable
		and empty_calendar.status_code == "validated_not_playable",
		"validación no implica jugabilidad")
	_check(empty_calendar.diagnostics[0].code == "empty_calendar",
		"calendario vacío explicado")

	_write_json(pack_path.path_join("fixtures.json"), [_fixture()])
	var complete_result = Catalog.new().get_catalog(temporary_root)
	var complete = complete_result.data.seasons[0]
	_check(complete.data_discovered and complete.data_validated and complete.playable,
		"pack mínimo coherente jugable")
	_check(complete.status_code == "playable" and complete.missing_content.is_empty()
		and complete.diagnostics.is_empty(), "estado jugable limpio")
	var repeated = Catalog.new().get_catalog(temporary_root)
	_check(repeated == complete_result, "catálogo determinista")

	# Una referencia exacta rota invalida el pack antes de probar la sesión.
	var broken_fixture = _fixture()
	broken_fixture.home_club_id = "club_missing"
	_write_json(pack_path.path_join("fixtures.json"), [broken_fixture])
	var broken = Catalog.new().get_catalog(temporary_root).data.seasons[0]
	_check(not broken.data_validated and not broken.playable and broken.status_code == "invalid",
		"referencia deportiva inválida rechazada")
	_check(broken.diagnostics[0].code == "missing_home_club_reference",
		"diagnóstico referencial conservado")

	var unknown_fixture = _fixture()
	unknown_fixture.home_club_id = null
	_write_json(pack_path.path_join("fixtures.json"), [unknown_fixture])
	var unknown = Catalog.new().get_catalog(temporary_root).data.seasons[0]
	_check(unknown.data_validated and not unknown.playable
		and unknown.diagnostics[0].code == "incomplete_fixture_clubs",
		"club desconocido se conserva pero impide declarar el pack jugable")

	_remove_tree(temporary_root)
	_finish()


func _write_complete_pack(pack_path: String, fixtures: Array) -> void:
	_write_json(pack_path.path_join("rules.json"), {
		"season_id": "1982-83", "competition_id": "league",
		"points_win": 2, "points_draw": 1, "points_loss": 0,
		"team_count": 2, "round_count": 1,
		"tiebreakers": ["goal_difference"],
		"substitution_rules": {}, "promotion_relegation_rules": {},
		"competition_format": {
			"kind": "round_robin", "legs": null, "head_to_head_policy": "single_pass"
		},
	})
	_write_json(pack_path.path_join("clubs.json"), [
		{"club_id": "club_a", "season_id": "1982-83", "division_id": "first"},
		{"club_id": "club_b", "season_id": "1982-83", "division_id": "first"},
	])
	_write_json(pack_path.path_join("players.json"), [{
		"player_id": "player_a", "season_id": "1982-83", "club_id": "club_a",
		"historical_data": {}, "game_data": {}, "metadata": {},
	}])
	_write_json(pack_path.path_join("fixtures.json"), fixtures)


func _manifest() -> Dictionary:
	return {
		"schema_version": 1,
		"season_id": "1982-83",
		"sources": ["synthetic-test-source"],
		"checksum": {"pack": "synthetic-test-checksum"},
	}


func _fixture() -> Dictionary:
	return {
		"fixture_id": "fixture_1", "season_id": "1982-83",
		"competition_id": "league", "stage_id": "regular", "group_id": null,
		"home_club_id": "club_a", "away_club_id": "club_b",
		"round_number": 1, "scheduled_date": "1982-09-05", "metadata": {},
	}


func _all_unavailable(seasons: Array) -> bool:
	for season in seasons:
		if season.data_discovered or season.data_validated or season.playable:
			return false
	return true


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
