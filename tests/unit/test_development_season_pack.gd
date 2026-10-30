extends SceneTree

const MenuScene = preload("res://game/scenes/main_menu.tscn")
const Catalog = preload("res://game/scripts/services/season_catalog_service.gd")
const Loader = preload("res://game/scripts/services/season_session_loader.gd")

const DEV_ROOT = "res://data/dev/seasons"
const DEV_PACK = DEV_ROOT + "/1982-83"
const HISTORICAL_PACK = "res://data/seasons/1982-83"
const REQUIRED_FILES = [
	"manifest.json", "rules.json", "clubs.json", "players.json", "fixtures.json"
]
const WARNING = "MODO DESARROLLO — DATOS SINTÉTICOS"
const SAVE_DIRECTORY = "user://neofutbol/sporting_state"

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var dev_before = _pack_snapshot(DEV_PACK)
	var historical_before = _pack_snapshot(HISTORICAL_PACK)
	var saves_before = _save_files()

	_check(DirAccess.dir_exists_absolute(DEV_PACK), "existe el directorio permanente")
	_check(dev_before.size() == REQUIRED_FILES.size(), "contiene los cinco archivos")
	for file_name in REQUIRED_FILES:
		_check(FileAccess.file_exists(DEV_PACK.path_join(file_name)),
			"existe %s" % file_name)

	var manifest = _read_json(DEV_PACK.path_join("manifest.json"))
	var rules = _read_json(DEV_PACK.path_join("rules.json"))
	var clubs = _read_json(DEV_PACK.path_join("clubs.json"))
	var players = _read_json(DEV_PACK.path_join("players.json"))
	var fixtures = _read_json(DEV_PACK.path_join("fixtures.json"))
	_check(manifest is Dictionary and rules is Dictionary and clubs is Array
		and players is Array and fixtures is Array, "los cinco JSON son legibles")
	_check(manifest.season_id == "1982-83" and manifest.sources.size() == 2
		and "synthetic-original" in manifest.sources[0],
		"el manifest declara procedencia sintética")
	_check(manifest.checksum.kind == "development-marker-not-cryptographic"
		and not manifest.checksum.verified,
		"el checksum se identifica como marcador no criptográfico")
	_check(clubs.size() == 4 and players.size() == 4,
		"incluye cuatro clubes y jugadores referenciables")
	var club_ids: Array[String] = []
	for club in clubs:
		club_ids.append(club.club_id)
	_check(_all_prefixed(club_ids, "dev_") and _unique_count(club_ids) == 4,
		"los clubes usan identificadores sintéticos únicos")
	var player_clubs: Array[String] = []
	for player in players:
		player_clubs.append(player.club_id)
	_check(_same_string_set(player_clubs, club_ids),
		"cada club sintético tiene un jugador asociado")
	_check(rules.competition_id == "dev_synthetic_league"
		and rules.team_count == 4.0 and rules.round_count == 3.0
		and rules.competition_format.kind == "round_robin",
		"las reglas describen una liga única a una vuelta")
	_check(fixtures.size() == 6, "el calendario contiene seis partidos")
	var competitions: Dictionary = {}
	var stages: Dictionary = {}
	var groups: Dictionary = {}
	var rounds: Dictionary = {}
	var pairs: Dictionary = {}
	for fixture in fixtures:
		competitions[fixture.competition_id] = true
		stages[fixture.stage_id] = true
		groups[fixture.group_id] = true
		rounds[fixture.round_number] = true
		var pair = [fixture.home_club_id, fixture.away_club_id]
		pair.sort()
		pairs["%s|%s" % pair] = true
	_check(competitions.keys() == ["dev_synthetic_league"]
		and stages.keys() == ["dev_regular"] and groups.keys() == ["dev_group_a"],
		"no mezcla competiciones, fases ni grupos")
	_check(rounds.size() == 3 and rounds.has(1.0) and rounds.has(2.0) and rounds.has(3.0),
		"reparte el calendario en tres jornadas")
	_check(pairs.size() == 6, "cada pareja de clubes se enfrenta una sola vez")

	var normal_catalog = Catalog.new().get_catalog()
	var dev_catalog = Catalog.new().get_catalog(DEV_ROOT)
	_check(normal_catalog.ok and not normal_catalog.data.seasons[0].playable,
		"el catálogo normal no convierte el pack histórico en jugable")
	_check(dev_catalog.ok and dev_catalog.data.seasons[0].playable
		and dev_catalog.data.root_path == DEV_ROOT,
		"el catálogo de desarrollo identifica el pack como apto")
	var prepared = Loader.new().prepare_session("1982-83", DEV_ROOT)
	_check(prepared.ok, "SeasonSessionLoader prepara la sesión sintética")
	if prepared.ok:
		_check(prepared.data.selection == {
			"season_id": "1982-83", "competition_id": "dev_synthetic_league",
			"stage_id": "dev_regular", "group_id": "dev_group_a",
		}, "la selección preparada es exacta")
		_check(prepared.data.calendar.size() == 6, "el loader conserva los seis partidos")
		_check(prepared.data.controller.get_standings().data.rows.size() == 4,
			"la clasificación inicial contiene cuatro clubes")
		_check(prepared.data.controller.get_results().data.results.is_empty(),
			"la sesión no contiene resultados iniciales")

	var normal_menu = MenuScene.instantiate()
	normal_menu.command_line_user_args = PackedStringArray()
	root.add_child(normal_menu)
	await process_frame
	_check(normal_menu.season_root_path == "res://data/seasons"
		and not normal_menu.development_mode_banner.visible,
		"sin argumento conserva el modo histórico normal")
	normal_menu.queue_free()
	await process_frame

	var menu = MenuScene.instantiate()
	menu.command_line_user_args = PackedStringArray([
		"--dev-season-pack", "--dev-season-pack"
	])
	root.add_child(menu)
	await process_frame
	_check(menu._development_season_pack_active and menu.season_root_path == DEV_ROOT,
		"el argumento de usuario activa exclusivamente la raíz de desarrollo")
	_check(menu.development_mode_banner.visible
		and menu.development_mode_banner.text == WARNING,
		"el menú muestra la advertencia obligatoria")

	menu.selection_button.pressed.emit()
	await process_frame
	var selector = menu._selection_view
	_check(selector != null and selector.catalog_root_path == DEV_ROOT,
		"el selector recibe la raíz de desarrollo")
	_check(selector.get_selected_season_id() == "1982-83"
		and not selector.consult_button.disabled,
		"el pack permanente puede consultarse")
	_check(menu.development_mode_banner.visible,
		"la advertencia permanece visible en el selector")

	var invalid = await menu.open_historical_season("1983-84")
	_check(not invalid.ok and menu._selection_view == selector
		and menu.season_host.get_child_count() == 1,
		"un pack ausente no sustituye el selector")
	selector.consult_button.pressed.emit()
	selector.consult_button.pressed.emit()
	for frame in 4:
		await process_frame
	var overview = menu._season_view
	_check(overview != null and menu.season_host.get_child_count() == 1,
		"activaciones repetidas crean una sola consulta")
	if overview != null:
		_check(menu.development_mode_banner.visible
			and overview.synthetic_badge.visible and overview.synthetic_badge.text == WARNING,
			"la consulta conserva la advertencia sintética")
		_check(overview._fixtures.size() == 6 and overview.round_selector.item_count == 3,
			"la consulta muestra los seis partidos y tres jornadas")
		_check(_tree_row_count(overview.standings_tree) == 4,
			"la consulta muestra cuatro filas de clasificación")
		_check(overview._controller.get_results().data.results.is_empty(),
			"la navegación no inventa resultados")

	menu.back_button.pressed.emit()
	await process_frame
	_check(menu._selection_view != null and menu.development_mode_banner.visible,
		"volver a temporadas conserva el modo y su advertencia")
	menu._selection_view.back_button.pressed.emit()
	await process_frame
	_check(menu.menu_presentation.visible and menu.development_mode_banner.visible,
		"volver al menú conserva el modo explícito")
	menu.demo_button.pressed.emit()
	await process_frame
	_check(menu._season_view != null and menu._season_view.synthetic_badge.visible
		and _tree_row_count(menu._season_view.standings_tree) == 4,
		"la demostración independiente continúa disponible")
	menu.back_button.pressed.emit()
	await process_frame

	_check(_pack_snapshot(DEV_PACK) == dev_before,
		"la navegación no modifica el pack de desarrollo")
	_check(_pack_snapshot(HISTORICAL_PACK) == historical_before,
		"el pack histórico incompleto permanece intacto")
	_check(_save_files() == saves_before, "la navegación no crea guardados")
	menu.queue_free()
	await process_frame
	_finish()


func _read_json(path: String) -> Variant:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var value = JSON.parse_string(file.get_as_text())
	file.close()
	return value


func _pack_snapshot(path: String) -> Dictionary:
	var snapshot: Dictionary = {}
	for file_name in REQUIRED_FILES:
		var file = FileAccess.open(path.path_join(file_name), FileAccess.READ)
		if file != null:
			snapshot[file_name] = file.get_as_text()
			file.close()
	return snapshot


func _all_prefixed(values: Array[String], prefix: String) -> bool:
	for value in values:
		if not value.begins_with(prefix):
			return false
	return true


func _unique_count(values: Array[String]) -> int:
	var unique: Dictionary = {}
	for value in values:
		unique[value] = true
	return unique.size()


func _same_string_set(left: Array[String], right: Array[String]) -> bool:
	var left_copy = left.duplicate()
	var right_copy = right.duplicate()
	left_copy.sort()
	right_copy.sort()
	return left_copy == right_copy


func _tree_row_count(tree: Tree) -> int:
	var count = 0
	var item = tree.get_root().get_first_child() if tree.get_root() != null else null
	while item != null:
		count += 1
		item = item.get_next()
	return count


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
