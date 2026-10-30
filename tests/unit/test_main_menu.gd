extends SceneTree

const MenuScene = preload("res://game/scenes/main_menu.tscn")
const MenuScript = preload("res://game/scripts/ui/main_menu.gd")
const SeasonScene = preload("res://game/scenes/season_overview.tscn")
const SeasonScript = preload("res://game/scripts/ui/season_overview.gd")
const SelectionScene = preload("res://game/scenes/season_selection.tscn")
const SelectionScript = preload("res://game/scripts/ui/season_selection.gd")
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
	var files_before = _save_files()
	var external_controller = _external_controller()
	var external_before = _controller_snapshot(external_controller)
	var menu = MenuScene.instantiate()
	_check(menu != null, "carga la escena del menú")
	root.add_child(menu)
	await process_frame

	_test_initial_screen(menu)
	await _test_basic_navigation(menu)
	await _test_season_selection_navigation(menu)
	await _test_repeated_navigation(menu)
	await _test_instantiation_failure(menu)

	_check(_controller_snapshot(external_controller) == external_before,
		"la navegación no modifica un estado deportivo externo")
	_check(_save_files() == files_before,
		"la navegación no crea archivos de guardado")
	_check(ProjectSettings.get_setting("rendering/renderer/rendering_method")
		== "gl_compatibility", "conserva el renderizador Compatibility")

	menu.queue_free()
	await process_frame
	_finish()


func _test_initial_screen(menu) -> void:
	_check(menu.get_script() == MenuScript, "la raíz utiliza la clase MainMenu")
	_check(menu.get_node("%BrandLabel").text == "NEOFutbol"
		and menu.get_node("%ProjectTitle").text == "NEOFutbol",
		"muestra la identidad NEOFutbol")
	_check(menu.get_node("%ProjectSubtitle").text.contains(
		"gestión futbolística histórica"), "muestra el subtítulo del proyecto")
	_check(menu.get_node("%DemoButton").text == "Demostración de temporada",
		"conserva la demostración implementada")
	_check(menu.get_node("%SelectionButton").text == "Seleccionar temporada",
		"ofrece el selector histórico")
	_check(menu.get_node("%SyntheticNotice").text.contains("datos ficticios"),
		"avisa de los datos ficticios")
	_check(menu.get_node("%DevelopmentStatus").text.contains("desarrollo"),
		"muestra el estado de desarrollo")
	_check(menu.menu_presentation.visible and not menu.season_host.visible
		and not menu.back_button.visible, "presenta inicialmente el menú activo")
	_check(menu.demo_button.focus_mode == Control.FOCUS_ALL
		and menu.selection_button.focus_mode == Control.FOCUS_ALL
		and menu.back_button.focus_mode == Control.FOCUS_ALL,
		"los controles admiten foco de teclado")
	_check(menu.demo_button.pressed.is_connected(menu._on_demo_button_pressed)
		and menu.selection_button.pressed.is_connected(menu._on_selection_button_pressed)
		and menu.back_button.pressed.is_connected(menu._on_back_button_pressed),
		"la navegación está conectada a señales de controles")


func _test_basic_navigation(menu) -> void:
	menu.demo_button.pressed.emit()
	await process_frame
	_check(menu.season_host.visible and not menu.menu_presentation.visible
		and menu.back_button.visible, "entrar activa el contenido de temporada")
	_check(menu.season_host.get_child_count() == 1,
		"instancia una única vista de temporada")
	var first_view = menu.season_host.get_child(0)
	_check(first_view.get_script() == SeasonScript,
		"la vista instanciada es SeasonOverview")
	_check(_tree_row_count(first_view.standings_tree) == 4,
		"la demostración muestra cuatro clubes ficticios")
	_check(first_view.standings_tree.visible,
		"la clasificación está visible en la demostración")
	_check(first_view.round_selector.item_count > 0,
		"el calendario de demostración está disponible")
	var first_instance_id = first_view.get_instance_id()

	menu.back_button.pressed.emit()
	_check(menu.season_host.get_child_count() == 0,
		"retira la vista del contenedor al regresar")
	_check(menu.menu_presentation.visible and not menu.season_host.visible
		and not menu.back_button.visible, "regresar restaura el menú activo")
	_check(menu._season_view == null, "elimina la referencia a la vista anterior")
	await process_frame
	_check(not is_instance_valid(first_view), "libera la vista anterior")

	menu.demo_button.pressed.emit()
	await process_frame
	_check(menu.season_host.get_child_count() == 1,
		"permite una segunda apertura")
	_check(menu.season_host.get_child(0).get_instance_id() != first_instance_id,
		"la segunda apertura usa una instancia nueva")
	menu.back_button.pressed.emit()
	await process_frame


func _test_season_selection_navigation(menu) -> void:
	menu.selection_button.pressed.emit()
	await process_frame
	_check(menu.season_host.get_child_count() == 1
		and menu._selection_view != null, "abre una única vista de selección")
	var selection_view = menu.season_host.get_child(0)
	_check(selection_view.get_script() == SelectionScript,
		"la vista instanciada es SeasonSelection")
	_check(selection_view.get_node("%SeasonList").item_count == 29,
		"el menú presenta las 29 temporadas")
	_check(selection_view.get_node("%StartButton").disabled,
		"el pack incompleto no se puede iniciar desde el menú")
	for repetition in 6:
		menu.selection_button.pressed.emit()
	_check(menu.season_host.get_child_count() == 1,
		"pulsaciones repetidas no duplican el selector")
	selection_view.get_node("%BackButton").pressed.emit()
	_check(menu.season_host.get_child_count() == 0 and menu._selection_view == null,
		"el retorno propio retira el selector")
	await process_frame
	_check(not is_instance_valid(selection_view) and menu.menu_presentation.visible,
		"el retorno propio libera la vista y restaura el menú")

	menu.selection_button.pressed.emit()
	await process_frame
	_check(menu.season_host.get_child_count() == 1,
		"permite volver a abrir el selector")
	menu.back_button.pressed.emit()
	await process_frame
	menu.demo_button.pressed.emit()
	await process_frame
	_check(menu.season_host.get_child_count() == 1
		and menu.season_host.get_child(0).get_script() == SeasonScript,
		"la demostración sigue disponible después del selector")
	menu.back_button.pressed.emit()
	await process_frame


func _test_repeated_navigation(menu) -> void:
	for cycle in 10:
		menu.demo_button.pressed.emit()
		await process_frame
		_check(menu.season_host.get_child_count() == 1,
			"ciclo %d crea una sola vista" % (cycle + 1))
		_check(menu._season_view != null and is_instance_valid(menu._season_view),
			"ciclo %d mantiene una referencia válida" % (cycle + 1))
		menu.back_button.pressed.emit()
		await process_frame
		_check(menu.season_host.get_child_count() == 0 and menu._season_view == null,
			"ciclo %d regresa sin referencias obsoletas" % (cycle + 1))

	for repetition in 6:
		menu.demo_button.pressed.emit()
	_check(menu.season_host.get_child_count() == 1,
		"pulsaciones repetidas de entrada no duplican vistas")
	await process_frame
	_check(menu.season_host.get_child_count() == 1,
		"la entrada repetida sigue estable tras procesar el frame")
	for repetition in 6:
		menu.back_button.pressed.emit()
	_check(menu.season_host.get_child_count() == 0 and menu._season_view == null,
		"pulsaciones repetidas de regreso son idempotentes")
	await process_frame
	_check(menu.menu_presentation.visible and not menu.back_button.visible,
		"el menú permanece activo tras regresos repetidos")


func _test_instantiation_failure(menu) -> void:
	menu.season_scene = null
	menu.demo_button.pressed.emit()
	await process_frame
	_check(menu.error_label.visible
		and menu.error_label.text.contains("season_scene_unavailable"),
		"muestra un error explícito si falta la escena")
	_check(menu.menu_presentation.visible and not menu.season_host.visible
		and menu.season_host.get_child_count() == 0,
		"un fallo mantiene disponible el menú")
	_check(not menu.demo_button.disabled,
		"un fallo no bloquea nuevas acciones")

	menu.selection_scene = null
	menu.selection_button.pressed.emit()
	await process_frame
	_check(menu.error_label.visible
		and menu.error_label.text.contains("selection_scene_unavailable"),
		"muestra un error explícito si falta el selector")
	_check(menu.menu_presentation.visible and not menu.selection_button.disabled,
		"el fallo del selector conserva el menú utilizable")
	menu.selection_scene = SelectionScene

	menu.season_scene = SeasonScene
	menu.demo_button.pressed.emit()
	await process_frame
	_check(menu.season_host.get_child_count() == 1 and not menu.error_label.visible,
		"la navegación se recupera después del error")
	menu.back_button.pressed.emit()
	await process_frame


func _external_controller() -> Controller:
	var clubs: Array[Club] = []
	for club_id in ["external_a", "external_b"]:
		var club = Club.new()
		club.club_id = club_id
		club.season_id = "external_season"
		club.division_id = "external_division"
		clubs.append(club)
	var fixtures: Array[Fixture] = []
	var rules = Rules.new()
	rules.season_id = "external_season"
	rules.competition_id = "external_league"
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
		"season_id": "external_season", "competition_id": "external_league",
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
