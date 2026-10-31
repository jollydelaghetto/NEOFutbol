extends SceneTree

const MenuScene = preload("res://game/scenes/main_menu.tscn")
const OfficeScene = preload("res://game/scenes/manager_office.tscn")
const OfficeScript = preload("res://game/scripts/ui/manager_office.gd")
const ClubSelectionScript = preload("res://game/scripts/ui/manager_club_selection.gd")
const SeasonScript = preload("res://game/scripts/ui/season_overview.gd")
const SessionLoader = preload("res://game/scripts/services/season_session_loader.gd")

const DEV_ROOT = "res://data/dev/seasons"
const SAVE_DIRECTORY = "user://neofutbol/sporting_state"

class FailingLoader:
	extends RefCounted

	func prepare_session(_season_id: String, _root_path: String) -> Dictionary:
		return {
			"ok": false, "data": null,
			"errors": [{
				"code": "office_pack_failure",
				"message": "Fallo sintético al preparar el Despacho.",
			}],
		}


var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var saves_before = _save_files()
	await _test_office_scene_contract()
	await _test_normal_mode_isolation()
	await _test_development_navigation()
	await _test_load_failure()
	_check(_save_files() == saves_before, "la navegación no crea partidas guardadas")
	_finish()


func _test_office_scene_contract() -> void:
	var prepared = SessionLoader.new().prepare_session("1982-83", DEV_ROOT)
	_check(prepared.ok, "prepara el pack sintético mediante el loader existente")
	if not prepared.ok:
		return
	var view = OfficeScene.instantiate()
	root.add_child(view)
	await process_frame
	var fixture_snapshot = _fixture_snapshot(prepared.data.calendar)
	var controller_snapshot = _controller_snapshot(prepared.data.controller)
	var presentation = prepared.data.presentation.duplicate(true)
	presentation["synthetic"] = true
	var configured = view.configure(
		prepared.data.controller, prepared.data.calendar,
		prepared.data.selection, presentation, "dev_aurora_union"
	)
	_check(configured.ok and configured.data.club_id == "dev_aurora_union"
		and configured.data.season_id == "1982-83",
		"configura la temporada técnica y conserva el ID de Aurora Unión")
	_check(view.get_script() == OfficeScript
		and view.season_label.text == "Temporada técnica 1982-83"
		and view.club_label.text == "Club dirigido: Aurora Unión",
		"identifica el Despacho, la temporada y el club confirmado")
	_check(view.warning_label.text == "MODO DESARROLLO — DATOS SINTÉTICOS",
		"mantiene visible la advertencia sintética")
	_check(view.agenda_fixture_label.get_meta("fixture_id", "")
		== "dev_round_01_match_01"
		and view.agenda_fixture_label.text.contains("Aurora Unión")
		and view.agenda_fixture_label.text.contains("Duna Deportivo"),
		"la agenda obtiene el primer partido real de Aurora del calendario")
	_check(view.agenda_date_label.text.contains("1982-09-04")
		and view.agenda_date_label.text.contains("sin avance temporal"),
		"presenta la fecha deportiva como consulta sin simular el tiempo")
	_check(view.standings_summary.text.contains("4 clubes")
		and view.calendar_summary.text.contains("3 jornadas")
		and view.calendar_summary.text.contains("6 partidos"),
		"resume clasificación y calendario derivados de servicios existentes")
	_check(view.news_status.text == "Noticias — pendiente de implementación"
		and view.finance_status.text == "Finanzas — pendiente de implementación",
		"los paneles provisionales no inventan noticias ni finanzas")
	_check(not view.squad_button.disabled and not view.tactics_button.disabled
		and view.market_button.disabled and view.advance_button.disabled,
		"Plantilla y Tácticas están disponibles; Mercado y Avanzar siguen deshabilitados")
	_check(view.squad_button.focus_mode == Control.FOCUS_ALL
		and view.tactics_button.focus_mode == Control.FOCUS_ALL
		and [view.market_button, view.advance_button].all(
			func(button): return button.focus_mode == Control.FOCUS_NONE),
		"los módulos disponibles reciben foco y los controles pendientes no lo reciben")
	view.focus_initial_control()
	_check(_focus_owner() == view.standings_button,
		"la clasificación recibe el foco inicial visible")
	await _press_key(KEY_TAB)
	_check(_focus_owner() == view.calendar_button,
		"Tab avanza desde clasificación a calendario")
	await _press_key(KEY_TAB, true)
	_check(_focus_owner() == view.standings_button,
		"Mayús+Tab recupera la clasificación")
	await _press_key(KEY_TAB)
	await _press_key(KEY_TAB)
	_check(_focus_owner() == view.squad_button,
		"Tab incorpora Plantilla a la ruta funcional")
	await _press_key(KEY_TAB)
	_check(_focus_owner() == view.tactics_button,
		"Tab incorpora Tácticas después de Plantilla")
	_check(_fixture_snapshot(prepared.data.calendar) == fixture_snapshot
		and _controller_snapshot(prepared.data.controller) == controller_snapshot,
		"configurar y recorrer el Despacho no modifica datos deportivos")
	view.queue_free()
	await process_frame


func _test_normal_mode_isolation() -> void:
	var menu = MenuScene.instantiate()
	menu.command_line_user_args = PackedStringArray()
	root.add_child(menu)
	await process_frame
	_check(not menu.office_button.visible and menu.office_button.disabled,
		"el modo normal no muestra ni habilita el prototipo")
	var rejected = await menu.show_manager_club_selection()
	_check(not rejected.ok and rejected.errors[0].code == "development_mode_required"
		and menu._office_view == null and menu.season_host.get_child_count() == 0,
		"una llamada directa tampoco activa una carrera sintética en modo normal")
	_check(menu.selection_button.visible and menu.demo_button.visible,
		"el selector y la demostración anteriores siguen disponibles")
	var export_file = FileAccess.open("res://export_presets.cfg", FileAccess.READ)
	var presets = export_file.get_as_text() if export_file != null else ""
	if export_file != null:
		export_file.close()
	_check(presets.contains("exclude_filter=\"data/dev/**,tests/**,tools/**,docs/**\""),
		"la exportación pública continúa excluyendo el pack sintético")
	menu.queue_free()
	await process_frame


func _test_development_navigation() -> void:
	var menu = MenuScene.instantiate()
	menu.command_line_user_args = PackedStringArray(["--dev-season-pack"])
	root.add_child(menu)
	await process_frame
	_check(menu._development_season_pack_active and menu.office_button.visible
		and not menu.office_button.disabled,
		"el argumento explícito habilita la entrada diferenciada al Despacho")
	_check(menu.office_button.text == "Iniciar prototipo de entrenador",
		"la entrada no se confunde con la consulta de temporada")
	_check(_focus_owner() == menu.demo_button, "el menú conserva su foco inicial")
	await _press_key(KEY_TAB)
	_check(_focus_owner() == menu.selection_button,
		"Tab conserva primero la ruta al selector histórico")
	await _press_key(KEY_TAB)
	_check(_focus_owner() == menu.office_button,
		"Tab alcanza después la entrada al prototipo")
	await _press_key(KEY_ENTER)
	await process_frame
	await process_frame
	var club_selection = menu._club_selection_view
	_check(club_selection != null and club_selection.get_script() == ClubSelectionScript
		and menu._office_view == null and menu.season_host.get_child_count() == 1,
		"Enter abre primero una única selección de club")
	_check(_focus_owner() == club_selection.club_selector,
		"la selección transfiere el foco al selector")
	await _press_key(KEY_TAB)
	await _press_key(KEY_ENTER)
	await process_frame
	await process_frame
	var office = menu._office_view
	_check(office != null and office.get_script() == OfficeScript
		and menu.season_host.get_child_count() == 1,
		"Enter abre una única escena del Despacho")
	_check(_focus_owner() == office.standings_button,
		"la entrada transfiere el foco a la primera acción funcional")
	var context_before = office.get_context()
	var sporting_before = _controller_snapshot(menu._office_session.controller)
	var dates_before = _fixture_snapshot(menu._office_session.calendar)

	# Clasificación: Enter abre SeasonOverview en su pestaña correspondiente.
	await _press_key(KEY_ENTER)
	await process_frame
	await process_frame
	var overview = menu._season_view
	_check(overview != null and overview.get_script() == SeasonScript
		and menu._office_module_active and menu._office_module == "standings"
		and menu.season_host.get_child_count() == 1,
		"Enter abre la clasificación sin duplicar escenas")
	_check(overview.get_node("%Tabs").current_tab == 0
		and _tree_column_texts(overview.standings_tree, 1).has("Aurora Unión"),
		"la clasificación reutilizada muestra nombres legibles")
	_check(menu.back_button.visible and menu.back_button.text == "Volver al Despacho",
		"el módulo ofrece un retorno explícito")
	menu.back_button.grab_focus()
	await _press_key(KEY_ENTER)
	await process_frame
	office = menu._office_view
	_check(office.get_parent() == menu.season_host
		and menu.season_host.get_child_count() == 1
		and office.get_context() == context_before,
		"volver de clasificación conserva temporada y club")
	_check(_focus_owner() == office.standings_button,
		"el retorno restaura el foco de clasificación")

	# Calendario: Tab y Enter abren la misma consulta en su pestaña de jornadas.
	await _press_key(KEY_TAB)
	await _press_key(KEY_ENTER)
	await process_frame
	await process_frame
	overview = menu._season_view
	_check(overview != null and menu._office_module == "calendar"
		and overview.get_node("%Tabs").current_tab == 1,
		"Tab y Enter abren el calendario reutilizado")
	_check(overview.round_selector.item_count == 3
		and _visible_match_text(overview).contains("Aurora Unión")
		and _visible_match_text(overview).contains("Duna Deportivo"),
		"el calendario conserva las jornadas, partidos y nombres del pack")
	menu.back_button.grab_focus()
	await _press_key(KEY_ENTER)
	await process_frame
	office = menu._office_view
	_check(_focus_owner() == office.calendar_button
		and office.get_context() == context_before,
		"volver del calendario restaura su acción y el contexto")

	_check(_controller_snapshot(menu._office_session.controller) == sporting_before
		and _fixture_snapshot(menu._office_session.calendar) == dates_before,
		"consultar módulos no genera resultados ni cambia fechas")
	office.exit_button.grab_focus()
	await _press_key(KEY_ENTER)
	await process_frame
	_check(menu.menu_presentation.visible and not menu.season_host.visible
		and menu.season_host.get_child_count() == 0 and menu._office_view == null,
		"Salir al menú principal libera la sesión visual del prototipo")
	menu.office_button.pressed.emit()
	menu.office_button.pressed.emit()
	await process_frame
	await process_frame
	_check(menu._club_selection_view != null and menu._office_view == null
		and menu.season_host.get_child_count() == 1,
		"activaciones repetidas vuelven a crear una sola selección")
	menu._club_selection_view.continue_button.pressed.emit()
	await process_frame
	await process_frame
	_check(menu._office_view != null and menu.season_host.get_child_count() == 1,
		"confirmar el segundo ciclo crea un solo Despacho")
	menu._office_view.exit_button.pressed.emit()
	await process_frame
	_check(menu._office_view == null and menu.season_host.get_child_count() == 0,
		"el segundo ciclo se libera sin señales o vistas duplicadas")

	# Las rutas anteriores siguen operativas después del Despacho.
	menu.demo_button.pressed.emit()
	await process_frame
	_check(menu._season_view != null and menu._season_view.synthetic_badge.visible,
		"la demostración independiente continúa funcionando")
	menu.back_button.pressed.emit()
	await process_frame
	menu.selection_button.pressed.emit()
	await process_frame
	_check(menu._selection_view != null
		and menu._selection_view.get_selected_season_id() == "1982-83",
		"la consulta de temporadas conserva su navegación previa")
	menu._selection_view.back_button.pressed.emit()
	await process_frame
	var unexpected = await menu.open_office_module("calendar")
	_check(not unexpected.ok,
		"un estado inesperado sin Despacho se rechaza sin crear vistas")
	menu.queue_free()
	await process_frame


func _test_load_failure() -> void:
	var menu = MenuScene.instantiate()
	menu.command_line_user_args = PackedStringArray(["--dev-season-pack"])
	menu.session_loader = FailingLoader.new()
	root.add_child(menu)
	await process_frame
	var result = await menu.show_manager_club_selection()
	_check(not result.ok and result.errors[0].code == "office_pack_failure",
		"propaga un error localizado de carga")
	_check(menu._office_view == null and menu.season_host.get_child_count() == 0
		and menu.menu_presentation.visible and not menu._transition_in_progress,
		"un fallo conserva el menú válido sin una vista parcial")
	_check(menu.error_label.visible and menu.error_label.text.contains("office_pack_failure"),
		"el fallo queda visible y recuperable")
	menu.queue_free()
	await process_frame


func _controller_snapshot(controller) -> Dictionary:
	var context = controller.get_session_context()
	var standings = controller.get_standings()
	var results = controller.get_results()
	return {
		"selection": context.data.selection.duplicate(true),
		"fixtures": _fixture_snapshot(context.data.fixtures),
		"standings": standings.data.duplicate(true),
		"results": results.data.results.map(func(result): return result.fixture_id),
	}


func _fixture_snapshot(fixtures: Array) -> Array[Dictionary]:
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


func _tree_column_texts(tree: Tree, column: int) -> Array[String]:
	var values: Array[String] = []
	var item = tree.get_root().get_first_child() if tree.get_root() != null else null
	while item != null:
		values.append(item.get_text(column))
		item = item.get_next()
	return values


func _visible_match_text(view: Node) -> String:
	for panel in view.match_list.get_children():
		if panel.has_meta("fixture_id") and panel.get_child_count() > 0:
			var row = panel.get_child(0)
			if row.get_child_count() > 1:
				return row.get_child(1).text
	return ""


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


func _press_key(keycode: Key, shift_pressed := false) -> void:
	_send_key(keycode, shift_pressed)
	await process_frame


func _focus_owner() -> Control:
	return root.gui_get_focus_owner()


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
