extends SceneTree

const MenuScene = preload("res://game/scenes/main_menu.tscn")
const SessionLoader = preload("res://game/scripts/services/season_session_loader.gd")
const SAVE_DIRECTORY = "user://neofutbol/sporting_state"


class FailingSessionLoader:
	extends RefCounted

	func prepare_session(_season_id: String, _root_path: String) -> Dictionary:
		return {
			"ok": false,
			"data": null,
			"errors": [{
				"code": "audit_session_failure",
				"message": "Fallo controlado para auditar la recuperación.",
			}],
		}


var checks := 0
var failures: Array[String] = []
var requested_seasons: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var saves_before = _save_files()
	await _audit_normal_navigation()
	await _audit_development_navigation()
	await _audit_missing_development_pack()
	_check(_save_files() == saves_before, "la auditoría de navegación no crea guardados")
	_finish()


func _audit_normal_navigation() -> void:
	var menu = MenuScene.instantiate()
	menu.command_line_user_args = PackedStringArray()
	root.add_child(menu)
	await process_frame

	_check(_only_main_menu_visible(menu), "el arranque normal muestra solo el menú")
	_check(_focus_owner() == menu.demo_button, "el menú asigna foco inicial a la demostración")
	_check(menu.demo_button.pressed.get_connections().size() == 1
		and menu.selection_button.pressed.get_connections().size() == 1
		and menu.back_button.pressed.get_connections().size() == 1,
		"el menú conecta una sola vez cada acción de navegación")
	_check(menu.season_root_path == "res://data/seasons"
		and not menu.development_mode_banner.visible,
		"el modo normal mantiene aislados los datos sintéticos")

	await _press_key(KEY_TAB)
	_check(_focus_owner() == menu.selection_button, "Tab avanza al selector de temporadas")
	await _press_key(KEY_ENTER)
	var selector = menu._selection_view
	_check(selector != null and _only_content_visible(menu, selector, false),
		"Enter abre exclusivamente el selector histórico")
	_check(not menu.back_button.is_visible_in_tree()
		and selector.back_button.is_visible_in_tree(),
		"el selector presenta una sola acción visible de regreso")
	_check(_focus_owner() == selector.season_list, "el selector enfoca inicialmente la lista")
	_check(selector.season_list.item_count == 29, "el catálogo normal conserva 29 temporadas")
	_check(selector.catalog_root_path == "res://data/seasons"
		and not menu.development_mode_banner.visible,
		"el catálogo normal no activa datos ficticios")
	_check(selector.consult_button.disabled,
		"una temporada histórica incompleta mantiene deshabilitada la consulta")

	var first_id = selector.get_selected_season_id()
	await _press_key(KEY_DOWN)
	_check(selector.get_selected_season_id() != first_id
		and _focus_owner() == selector.season_list,
		"la flecha inferior cambia la temporada sin perder el foco de la lista")
	await _press_key(KEY_UP)
	_check(selector.get_selected_season_id() == first_id,
		"la flecha superior restaura la selección anterior")
	await _press_key(KEY_TAB)
	_check(_focus_owner() == selector.back_button
		and _focus_owner() != selector.consult_button,
		"Tab omite la consulta deshabilitada y enfoca Volver")
	await _press_key(KEY_ENTER)
	await process_frame
	_check(_only_main_menu_visible(menu) and not is_instance_valid(selector),
		"volver libera el selector y restaura solo el menú")
	_check(_focus_owner() == menu.demo_button, "volver al menú restaura su foco inicial")

	await _press_key(KEY_TAB)
	await _press_key(KEY_ENTER)
	selector = menu._selection_view
	var selector_id = selector.get_instance_id()
	await _press_key(KEY_ENTER)
	_check(menu.season_host.get_child_count() == 1
		and menu._selection_view.get_instance_id() == selector_id,
		"una activación repetida de la lista no crea otro selector")
	selector.back_button.grab_focus()
	await _press_key(KEY_ENTER)
	await process_frame

	menu.queue_free()
	await process_frame


func _audit_development_navigation() -> void:
	var menu = MenuScene.instantiate()
	menu.command_line_user_args = PackedStringArray(["--dev-season-pack"])
	root.add_child(menu)
	await process_frame

	_check(menu._development_season_pack_active
		and menu.development_mode_banner.visible,
		"el argumento explícito activa el pack de desarrollo disponible")
	_check(_focus_owner() == menu.demo_button, "el modo desarrollo conserva el foco inicial")
	await _press_key(KEY_TAB)
	await _press_key(KEY_ENTER)
	var selector = menu._selection_view
	_check(selector != null and selector.get_selected_season_id() == "1982-83"
		and not selector.consult_button.disabled,
		"el selector técnico ofrece la temporada sintética consultable")
	_check(_focus_owner() == selector.season_list
		and menu.development_mode_banner.visible,
		"la lista recibe foco y mantiene visible la advertencia sintética")

	await _press_key(KEY_DOWN)
	_check(selector.consult_button.disabled and _focus_owner() == selector.season_list,
		"una temporada no disponible deshabilita la consulta sin robar foco")
	await _press_key(KEY_UP)
	_check(not selector.consult_button.disabled
		and selector.get_selected_season_id() == "1982-83",
		"volver a la temporada disponible restaura la acción de consulta")
	await _press_key(KEY_TAB)
	_check(_focus_owner() == selector.consult_button,
		"Tab enfoca Consultar cuando la selección es válida")
	selector.season_view_requested.connect(_record_season_request)

	_send_key(KEY_ENTER)
	_send_key(KEY_ENTER)
	await process_frame
	await process_frame
	var overview = menu._season_view
	_check(requested_seasons == ["1982-83"],
		"las pulsaciones consecutivas generan una sola solicitud de consulta")
	_check(overview != null and _only_content_visible(menu, overview, true)
		and menu.season_host.get_child_count() == 1,
		"la consulta termina con una sola pantalla y sin instancias antiguas")
	_check(not is_instance_valid(selector), "la transición libera el selector sustituido")
	_check(_focus_owner() == menu.back_button and not menu.back_button.disabled,
		"la consulta enfoca el retorno a temporadas")
	_check(menu.development_mode_banner.visible and overview.synthetic_badge.visible,
		"las advertencias sintéticas persisten en la consulta")
	_check(_tree_row_count(overview.standings_tree) == 4,
		"la clasificación sintética presenta cuatro clubes")
	_check(overview._controller.get_results().data.results.is_empty(),
		"la navegación no inventa resultados deportivos")
	_check(overview.round_selector.item_count > 1 and not overview.round_selector.disabled,
		"el calendario consultado ofrece varias jornadas navegables")

	var previous_round = overview.round_selector.selected
	var next_round = (previous_round + 1) % overview.round_selector.item_count
	overview.round_selector.select(next_round)
	overview.round_selector.item_selected.emit(next_round)
	await process_frame
	_check(overview.round_selector.selected != previous_round,
		"la señal de OptionButton cambia de jornada de forma determinista")
	menu.back_button.grab_focus()
	await _press_key(KEY_ENTER)
	await process_frame
	selector = menu._selection_view
	_check(selector != null and selector.get_selected_season_id() == "1982-83"
		and _only_content_visible(menu, selector, false),
		"volver del calendario restaura el selector y su selección")
	_check(_focus_owner() == selector.season_list,
		"volver del calendario restaura el foco en la lista")

	menu.session_loader = FailingSessionLoader.new()
	await _press_key(KEY_TAB)
	await _press_key(KEY_ENTER)
	await process_frame
	_check(menu._selection_view == selector and menu._season_view == null
		and menu.season_host.get_child_count() == 1,
		"un fallo de carga conserva la pantalla válida anterior")
	_check(selector.error_label.visible
		and selector.error_label.text.contains("audit_session_failure"),
		"el fallo controlado muestra un diagnóstico recuperable")
	_check(not menu._transition_in_progress and not menu.back_button.disabled
		and _focus_owner() == selector.season_list,
		"la recuperación desbloquea la navegación y restaura el foco")

	menu.session_loader = SessionLoader.new()
	await _press_key(KEY_TAB, true)
	_check(_focus_owner() == selector.back_button,
		"Mayús+Tab ofrece retorno determinista desde la lista")
	await _press_key(KEY_ENTER)
	await process_frame
	_check(_only_main_menu_visible(menu) and _focus_owner() == menu.demo_button,
		"volver desde el selector recuperado restaura el menú")

	var first_demo = menu.show_season_demo()
	var demo_results_before = menu._season_view._controller.get_results().data.results.size()
	var repeated_demo = menu.show_season_demo()
	_check(first_demo.ok and repeated_demo.ok
		and first_demo.data.season_view == repeated_demo.data.season_view
		and menu.season_host.get_child_count() == 1,
		"la demostración repetida reutiliza una única instancia")
	_check(menu._season_view.synthetic_badge.visible
		and _tree_row_count(menu._season_view.standings_tree) == 4,
		"la demostración independiente conserva su identificación y clasificación")
	_check(menu._season_view._controller.get_results().data.results.size()
		== demo_results_before,
		"la navegación repetida no añade resultados a la demostración")
	_check(_focus_owner() == menu.back_button,
		"la demostración enfoca su acción de regreso")
	await _press_key(KEY_ENTER)
	await process_frame
	_check(_only_main_menu_visible(menu), "regresar de la demostración restaura un estado único")

	menu.queue_free()
	await process_frame


func _audit_missing_development_pack() -> void:
	var menu = MenuScene.instantiate()
	menu.development_season_root_path = "res://data/dev/unavailable"
	menu.command_line_user_args = PackedStringArray(["--dev-season-pack"])
	root.add_child(menu)
	await process_frame

	_check(not menu._development_season_pack_active
		and menu._development_pack_request_rejected
		and menu.season_root_path == "res://data/seasons",
		"un pack ausente se rechaza y conserva el catálogo histórico")
	_check(menu.error_label.visible
		and menu.error_label.text.contains("development_pack_unavailable")
		and not menu.development_mode_banner.visible,
		"el rechazo se comunica sin mostrar una advertencia sintética falsa")
	_check(_focus_owner() == menu.demo_button,
		"el rechazo no impide la navegación inicial por teclado")
	await _press_key(KEY_TAB)
	await _press_key(KEY_ENTER)
	var selector = menu._selection_view
	_check(selector != null and selector.season_list.item_count == 29
		and selector.catalog_root_path == "res://data/seasons",
		"la variante sin pack conserva utilizable el catálogo normal")
	_check(menu.error_label.visible
		and menu.error_label.text.contains("development_pack_unavailable"),
		"la advertencia de pack ausente persiste durante la navegación")
	selector.back_button.grab_focus()
	await _press_key(KEY_ENTER)
	await process_frame
	menu.demo_button.grab_focus()
	await _press_key(KEY_ENTER)
	_check(menu._season_view != null and menu._season_view.synthetic_badge.visible,
		"el rechazo no bloquea la demostración independiente")
	await _press_key(KEY_ENTER)
	await process_frame

	menu.queue_free()
	await process_frame


func _send_key(keycode: Key, shift_pressed := false) -> void:
	var pressed = InputEventKey.new()
	pressed.keycode = keycode
	pressed.pressed = true
	pressed.shift_pressed = shift_pressed
	Input.parse_input_event(pressed)
	var released = InputEventKey.new()
	released.keycode = keycode
	released.pressed = false
	released.shift_pressed = shift_pressed
	Input.parse_input_event(released)


func _record_season_request(season_id: String) -> void:
	requested_seasons.append(season_id)


func _press_key(keycode: Key, shift_pressed := false) -> void:
	_send_key(keycode, shift_pressed)
	await process_frame


func _focus_owner() -> Control:
	return root.gui_get_focus_owner()


func _only_main_menu_visible(menu: Control) -> bool:
	return menu.menu_presentation.is_visible_in_tree() \
		and not menu.season_host.is_visible_in_tree() \
		and not menu.back_button.is_visible_in_tree() \
		and menu.season_host.get_child_count() == 0


func _only_content_visible(menu: Control, expected: Control,
		global_back_visible: bool) -> bool:
	return not menu.menu_presentation.is_visible_in_tree() \
		and menu.season_host.is_visible_in_tree() \
		and menu.back_button.is_visible_in_tree() == global_back_visible \
		and expected.is_visible_in_tree() \
		and _visible_content_count(menu) == 1


func _visible_content_count(menu: Control) -> int:
	var count = 0
	for child in menu.season_host.get_children():
		if child is CanvasItem and child.is_visible_in_tree():
			count += 1
	return count


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
