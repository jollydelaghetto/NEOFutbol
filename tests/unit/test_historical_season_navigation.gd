extends SceneTree

const MenuScene = preload("res://game/scenes/main_menu.tscn")
const SeasonScene = preload("res://game/scenes/season_overview.tscn")
const SeasonScript = preload("res://game/scripts/ui/season_overview.gd")
const SelectionScript = preload("res://game/scripts/ui/season_selection.gd")
const Loader = preload("res://game/scripts/services/season_session_loader.gd")

const SAVE_DIRECTORY = "user://neofutbol/sporting_state"

class ControllerFailureLoader:
	extends RefCounted

	func prepare_session(_season_id: String, _root_path: String) -> Dictionary:
		return {
			"ok": false, "data": null,
			"errors": [{
				"code": "controller_preparation_failed",
				"message": "Fallo sintético al preparar el controlador.",
			}],
		}


class MismatchedCalendarLoader:
	extends RefCounted

	func prepare_session(season_id: String, root_path: String) -> Dictionary:
		var result = Loader.new().prepare_session(season_id, root_path)
		if result.ok:
			result.data.calendar[0].scheduled_date = "2000-01-01"
		return result


var failures: Array[String] = []
var checks = 0
var temporary_root: String
var requested_ids: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	temporary_root = "/tmp/neofutbol_historical_navigation_%s" % OS.get_process_id()
	_remove_tree(temporary_root)
	DirAccess.make_dir_recursive_absolute(temporary_root)
	_write_valid_pack()
	var pack_path = temporary_root.path_join("1982-83")
	var original_pack = _pack_snapshot(pack_path)
	var saves_before = _save_files()

	var menu = MenuScene.instantiate()
	menu.season_root_path = temporary_root
	root.add_child(menu)
	await process_frame
	_check(not menu._development_season_pack_active
		and not menu.development_mode_banner.visible,
		"una raíz de prueba no activa silenciosamente el modo de desarrollo")
	_check(menu.get_node("%DemoButton").text == "Demostración de temporada"
		and menu.get_node("%SelectionButton").text == "Seleccionar temporada",
		"el menú conserva las dos entradas separadas")

	menu.selection_button.pressed.emit()
	await process_frame
	var selector = menu._selection_view
	_check(selector != null and selector.get_script() == SelectionScript,
		"abre el selector desde el menú")
	_check(selector.season_list.item_count == 29, "mantiene las 29 temporadas")
	_check(selector.get_selected_season_id() == "1982-83"
		and not selector.consult_button.disabled,
		"pack sintético válido habilita Consultar temporada")
	selector.season_view_requested.connect(_on_requested)

	# Dos activaciones y un retorno durante el await no duplican ni cancelan la transición.
	selector.consult_button.pressed.emit()
	selector.consult_button.pressed.emit()
	menu.back_button.pressed.emit()
	_check(menu._transition_in_progress and menu._selection_view == selector,
		"el selector permanece durante la transición")
	await process_frame
	await process_frame
	_check(requested_ids == ["1982-83"], "la señal transmite una sola solicitud exacta")
	_check(menu.season_host.get_child_count() == 1 and menu._selection_view == null
		and menu._season_view != null, "la transición termina con una sola pantalla")
	var historical_view = menu._season_view
	_check(historical_view.get_script() == SeasonScript and not historical_view.auto_demo,
		"abre SeasonOverview con auto_demo desactivado")
	_check(not historical_view.synthetic_badge.visible,
		"la consulta histórica no se presenta como demostración sintética")
	_check(_tree_row_count(historical_view.standings_tree) == 2,
		"la clasificación usa los dos clubes del pack")
	_check(historical_view.round_selector.item_count == 1
		and historical_view._fixtures.size() == 1,
		"presenta el calendario del pack")
	var context = historical_view._controller.get_session_context()
	_check(context.ok and context.data.selection == {
		"season_id": "1982-83", "competition_id": "league_1982-83",
		"stage_id": "regular", "group_id": "group_a",
	}, "el controlador corresponde a la selección solicitada")
	_check(historical_view._controller.get_results().data.results.is_empty(),
		"la consulta histórica no inventa resultados")
	_check(menu.back_button.text == "Volver a temporadas",
		"la vista histórica ofrece regreso al selector")

	var first_historical_id = historical_view.get_instance_id()
	menu.back_button.pressed.emit()
	await process_frame
	selector = menu._selection_view
	_check(selector != null and selector.get_selected_season_id() == "1982-83"
		and menu.season_host.get_child_count() == 1,
		"regresar recrea un único selector y conserva la temporada")
	_check(not is_instance_valid(historical_view), "libera la vista histórica anterior")
	selector.back_button.pressed.emit()
	await process_frame
	_check(menu.menu_presentation.visible and menu.season_host.get_child_count() == 0,
		"regresar desde el selector restaura el menú")

	menu.demo_button.pressed.emit()
	await process_frame
	_check(menu._season_view != null and menu._season_view.synthetic_badge.visible
		and _tree_row_count(menu._season_view.standings_tree) == 4,
		"la demostración sigue separada y conserva cuatro clubes ficticios")
	menu.back_button.pressed.emit()
	await process_frame

	# Un pack cambiado después del catálogo se vuelve a leer y deja el selector activo.
	menu.selection_button.pressed.emit()
	await process_frame
	selector = menu._selection_view
	_write_text(pack_path.path_join("fixtures.json"), "[ invalid")
	selector.consult_button.pressed.emit()
	await process_frame
	_check(menu._selection_view == selector and menu._season_view == null
		and menu.season_host.get_child_count() == 1,
		"un pack modificado no crea una vista parcial")
	_check(selector.error_label.visible and selector.error_label.text.contains("json_syntax")
		and selector.consult_button.disabled,
		"el error de revalidación queda visible y recuperable")

	# Estados no aptos del catálogo permanecen bloqueados.
	DirAccess.remove_absolute(pack_path.path_join("fixtures.json"))
	selector.refresh_catalog()
	_check(selector.consult_button.disabled
		and selector.status_label.text.contains("Pack incompleto"),
		"pack incompleto bloqueado")
	_write_valid_pack()
	var ambiguous = [_fixture("fixture_regular", "regular"),
		_fixture("fixture_playoff", "playoff")]
	_write_json(pack_path.path_join("fixtures.json"), ambiguous)
	selector.refresh_catalog()
	_check(selector.consult_button.disabled
		and selector.details_label.text.contains("varias fases"),
		"selección deportiva ambigua bloqueada")

	# Fallos posteriores a la catalogación conservan el selector y limpian provisionales.
	_write_valid_pack()
	selector.refresh_catalog()
	menu.session_loader = ControllerFailureLoader.new()
	selector.consult_button.pressed.emit()
	_check(menu._selection_view == selector and selector.error_label.text.contains(
		"controller_preparation_failed"), "fallo de controlador conserva el selector")

	menu.session_loader = Loader.new()
	menu.season_scene = null
	selector.consult_button.pressed.emit()
	_check(menu._selection_view == selector and selector.error_label.text.contains(
		"season_scene_unavailable"), "fallo de instancia conserva el selector")

	menu.season_scene = SeasonScene
	menu.session_loader = MismatchedCalendarLoader.new()
	selector.consult_button.pressed.emit()
	await process_frame
	await process_frame
	_check(menu._selection_view == selector and menu._season_view == null
		and menu.season_host.get_child_count() == 1,
		"fallo de configure elimina la vista provisional")
	_check(selector.error_label.text.contains("controller_calendar_mismatch"),
		"diagnóstico de configure visible en el selector")

	# Varias aperturas completas no dejan duplicados ni referencias obsoletas.
	menu.session_loader = Loader.new()
	for cycle in 2:
		selector.consult_button.pressed.emit()
		await process_frame
		await process_frame
		_check(menu._season_view != null and menu.season_host.get_child_count() == 1,
			"ciclo histórico %d abre una sola vista" % (cycle + 1))
		if cycle == 0:
			_check(menu._season_view.get_instance_id() != first_historical_id,
				"una nueva consulta usa una instancia nueva")
		menu.back_button.pressed.emit()
		await process_frame
		selector = menu._selection_view
		_check(selector != null and menu.season_host.get_child_count() == 1,
			"ciclo histórico %d vuelve a un solo selector" % (cycle + 1))

	selector.back_button.pressed.emit()
	await process_frame
	_check(_pack_snapshot(pack_path) == original_pack,
		"la navegación no modifica los datos originales")
	_check(_save_files() == saves_before, "la navegación no crea guardados")
	_check(ProjectSettings.get_setting("rendering/renderer/rendering_method")
		== "gl_compatibility", "mantiene el renderizador Compatibility")

	menu.queue_free()
	await process_frame
	_remove_tree(temporary_root)
	_finish()


func _on_requested(season_id: String) -> void:
	requested_ids.append(season_id)


func _tree_row_count(tree: Tree) -> int:
	var count = 0
	var root_item = tree.get_root()
	if root_item == null:
		return 0
	var item = root_item.get_first_child()
	while item != null:
		count += 1
		item = item.get_next()
	return count


func _write_valid_pack() -> void:
	var season_id = "1982-83"
	var pack_path = temporary_root.path_join(season_id)
	DirAccess.make_dir_recursive_absolute(pack_path)
	_write_json(pack_path.path_join("manifest.json"), {
		"schema_version": 1, "season_id": season_id,
		"sources": ["synthetic-navigation-source"],
		"checksum": {"pack": "synthetic-navigation-checksum"},
	})
	_write_json(pack_path.path_join("rules.json"), {
		"season_id": season_id, "competition_id": "league_1982-83",
		"points_win": 3, "points_draw": 1, "points_loss": 0,
		"team_count": 2, "round_count": 1,
		"tiebreakers": ["goal_difference"],
		"substitution_rules": {}, "promotion_relegation_rules": {},
		"competition_format": {
			"kind": "round_robin", "legs": null, "head_to_head_policy": "single_pass"
		},
	})
	_write_json(pack_path.path_join("clubs.json"), [
		{"club_id": "club_a", "season_id": season_id, "division_id": "first"},
		{"club_id": "club_b", "season_id": season_id, "division_id": "first"},
	])
	_write_json(pack_path.path_join("players.json"), [{
		"player_id": "player_a", "season_id": season_id, "club_id": "club_a",
		"historical_data": {}, "game_data": {}, "metadata": {},
	}])
	_write_json(pack_path.path_join("fixtures.json"), [_fixture("fixture_1", "regular")])


func _fixture(fixture_id: String, stage_id: String) -> Dictionary:
	return {
		"fixture_id": fixture_id, "season_id": "1982-83",
		"competition_id": "league_1982-83", "stage_id": stage_id,
		"group_id": "group_a", "home_club_id": "club_a",
		"away_club_id": "club_b", "round_number": 1,
		"scheduled_date": "1982-09-05", "metadata": {},
	}


func _pack_snapshot(pack_path: String) -> Dictionary:
	var snapshot: Dictionary = {}
	for file_name in ["manifest.json", "rules.json", "clubs.json", "players.json", "fixtures.json"]:
		var file = FileAccess.open(pack_path.path_join(file_name), FileAccess.READ)
		snapshot[file_name] = file.get_as_text() if file != null else null
		if file != null:
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
