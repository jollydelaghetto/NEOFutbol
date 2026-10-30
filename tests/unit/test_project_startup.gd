extends SceneTree

const EXPECTED_MAIN_SCENE = "res://game/scenes/main_menu.tscn"
const OLD_MAIN_SCENE = "res://game/scenes/ui/Main.tscn"
const MainMenuScript = preload("res://game/scripts/ui/main_menu.gd")
const SeasonOverviewScript = preload("res://game/scripts/ui/season_overview.gd")
const Controller = preload("res://game/scripts/services/season_controller.gd")
const Club = preload("res://game/scripts/data/club_season.gd")
const Fixture = preload("res://game/scripts/data/match_fixture.gd")
const Rules = preload("res://game/scripts/data/competition_rules.gd")

const SAVE_DIRECTORY = "user://neofutbol/sporting_state"

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var configured_path = ProjectSettings.get_setting("application/run/main_scene")
	_check(configured_path == EXPECTED_MAIN_SCENE,
		"la escena principal apunta al menú mediante una ruta explícita")
	_check(ResourceLoader.exists(configured_path), "la escena principal configurada existe")
	_check(ResourceLoader.exists(OLD_MAIN_SCENE), "la escena de arranque anterior se conserva")
	var packed_scene = load(configured_path)
	_check(packed_scene is PackedScene, "la escena principal puede cargarse")
	if not packed_scene is PackedScene:
		_finish()
		return

	var saves_before = _save_files()
	var external_controller = _external_controller()
	var external_before = _controller_snapshot(external_controller)
	var menu = packed_scene.instantiate()
	_check(menu.get_script() == MainMenuScript, "la raíz configurada es MainMenu")
	root.add_child(menu)
	await process_frame
	_check(menu.menu_presentation.visible and not menu.season_host.visible,
		"el menú aparece inicialmente activo")
	_check(menu.demo_button.visible and not menu.demo_button.disabled,
		"el botón de demostración está disponible")

	menu.demo_button.pressed.emit()
	await process_frame
	_check(menu.season_host.get_child_count() == 1,
		"el arranque integrado permite abrir la demostración")
	var season_view = menu.season_host.get_child(0)
	_check(season_view.get_script() == SeasonOverviewScript,
		"la navegación abre SeasonOverview")
	_check(_tree_row_count(season_view.standings_tree) == 4,
		"la clasificación contiene cuatro clubes ficticios")
	_check(season_view.round_selector.item_count > 0,
		"el calendario de la demostración está disponible")
	menu.demo_button.pressed.emit()
	_check(menu.season_host.get_child_count() == 1,
		"la integración no crea vistas duplicadas")

	menu.back_button.pressed.emit()
	await process_frame
	_check(menu.menu_presentation.visible and menu.season_host.get_child_count() == 0,
		"el regreso restaura el menú inicial")
	menu.demo_button.pressed.emit()
	await process_frame
	_check(menu.season_host.get_child_count() == 1,
		"el menú puede abrir de nuevo la demostración")
	menu.back_button.pressed.emit()
	await process_frame

	_check(_controller_snapshot(external_controller) == external_before,
		"la navegación de arranque no modifica servicios deportivos externos")
	_check(_save_files() == saves_before,
		"la navegación de arranque no crea partidas guardadas")
	_test_unchanged_project_settings()

	menu.queue_free()
	await process_frame
	_finish()


func _test_unchanged_project_settings() -> void:
	var features = ProjectSettings.get_setting("application/config/features")
	_check(ProjectSettings.get_setting("application/config/name") == "NEOFutbol"
		and ProjectSettings.get_setting("application/config/icon") == "res://icon.svg",
		"conserva la identidad y el icono del proyecto")
	_check(features.has("4.7") and features.has("GL Compatibility"),
		"conserva las características declaradas del proyecto")
	_check(ProjectSettings.get_setting("display/window/stretch/mode") == "canvas_items"
		and ProjectSettings.get_setting("display/window/stretch/aspect") == "expand",
		"conserva la configuración de escalado")
	_check(ProjectSettings.get_setting("physics/3d/physics_engine") == "Jolt Physics",
		"conserva el motor de física")
	_check(ProjectSettings.get_setting("rendering/rendering_device/driver.windows") == "d3d12",
		"conserva el controlador de renderizado de Windows")
	_check(ProjectSettings.get_setting("rendering/renderer/rendering_method")
		== "gl_compatibility"
		and ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile")
		== "gl_compatibility", "mantiene el renderizador Compatibility")


func _external_controller() -> Controller:
	var clubs: Array[Club] = []
	for club_id in ["startup_external_a", "startup_external_b"]:
		var club = Club.new()
		club.club_id = club_id
		club.season_id = "startup_external_season"
		club.division_id = "startup_external_division"
		clubs.append(club)
	var fixtures: Array[Fixture] = []
	var rules = Rules.new()
	rules.season_id = "startup_external_season"
	rules.competition_id = "startup_external_league"
	rules.points_win = 3
	rules.points_draw = 1
	rules.points_loss = 0
	rules.team_count = 2
	rules.round_count = 0
	rules.tiebreakers = ["goal_difference"]
	rules.competition_format = {
		"kind": "round_robin", "legs": 1, "head_to_head_policy": "single_pass"
	}
	var controller = Controller.new()
	var initialized = controller.initialize(clubs, fixtures, rules, {
		"season_id": "startup_external_season",
		"competition_id": "startup_external_league",
		"stage_id": "regular", "group_id": null,
	})
	_check(initialized.ok, "prepara un estado deportivo externo")
	return controller


func _controller_snapshot(controller: Controller) -> Dictionary:
	var context = controller.get_session_context()
	var standings = controller.get_standings()
	var results = controller.get_results()
	return {
		"selection": context.data.selection.duplicate(true),
		"fixture_count": context.data.fixtures.size(),
		"standings": standings.data.duplicate(true),
		"result_count": results.data.results.size(),
	}


func _tree_row_count(tree: Tree) -> int:
	var count = 0
	var root_item = tree.get_root()
	if root_item == null:
		return count
	var item = root_item.get_first_child()
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
