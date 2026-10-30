extends SceneTree

const MenuScene = preload("res://game/scenes/main_menu.tscn")
const SelectionScene = preload("res://game/scenes/manager_club_selection.tscn")
const OfficeScene = preload("res://game/scenes/manager_office.tscn")
const SessionLoader = preload("res://game/scripts/services/season_session_loader.gd")

const DEV_ROOT = "res://data/dev/seasons"
const SAVE_DIRECTORY = "user://neofutbol/sporting_state"
const EXPECTED_NAMES = {
	"dev_aurora_union": "Aurora Unión",
	"dev_bruma_atletico": "Bruma Atlético",
	"dev_cometa_fc": "Cometa FC",
	"dev_duna_deportivo": "Duna Deportivo",
}
const EXPECTED_AGENDA = {
	"dev_aurora_union": {
		"fixture_id": "dev_round_01_match_01", "condition": "Local",
		"rival": "Duna Deportivo", "date": "1982-09-04",
	},
	"dev_bruma_atletico": {
		"fixture_id": "dev_round_01_match_02", "condition": "Local",
		"rival": "Cometa FC", "date": "1982-09-04",
	},
	"dev_cometa_fc": {
		"fixture_id": "dev_round_01_match_02", "condition": "Visitante",
		"rival": "Bruma Atlético", "date": "1982-09-04",
	},
	"dev_duna_deportivo": {
		"fixture_id": "dev_round_01_match_01", "condition": "Visitante",
		"rival": "Aurora Unión", "date": "1982-09-04",
	},
}

var checks := 0
var failures: Array[String] = []
var confirmed_ids: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var saves_before = _save_files()
	await _test_selection_contract_and_keyboard()
	await _test_every_club_navigation()
	await _test_invalid_clubs()
	_check(_save_files() == saves_before, "la selección no crea partidas guardadas")
	_finish()


func _test_selection_contract_and_keyboard() -> void:
	var prepared = SessionLoader.new().prepare_session("1982-83", DEV_ROOT)
	_check(prepared.ok, "prepara la sesión sintética validada")
	if not prepared.ok:
		return
	var view = SelectionScene.instantiate()
	root.add_child(view)
	await process_frame
	var configured = view.configure(
		prepared.data.controller, prepared.data.selection, prepared.data.presentation
	)
	_check(configured.ok and configured.data.club_ids.size() == 4,
		"muestra exclusivamente los cuatro clubes de la sesión")
	var option_names: Dictionary = {}
	for index in view.club_selector.item_count:
		option_names[view.club_selector.get_item_metadata(index)] = \
			view.club_selector.get_item_text(index)
	_check(option_names == prepared.data.presentation.club_names
		and option_names == EXPECTED_NAMES,
		"obtiene cada nombre legible del mapeo validado del loader")
	_check(view.get_club_ids() == [
		"dev_aurora_union", "dev_bruma_atletico", "dev_cometa_fc", "dev_duna_deportivo",
	], "conserva los identificadores internos como metadata determinista")
	_check(view.warning_label.text == "MODO DESARROLLO — DATOS SINTÉTICOS",
		"muestra la advertencia obligatoria")
	view.focus_initial_control()
	_check(_focus_owner() == view.club_selector, "el selector recibe el foco inicial")
	var first_id = view.get_selected_club_id()
	await _press_key(KEY_DOWN)
	_check(view.get_selected_club_id() != first_id,
		"la flecha abajo cambia el club conservando su ID")
	await _press_key(KEY_UP)
	_check(view.get_selected_club_id() == first_id,
		"la flecha arriba recupera el club anterior")
	await _press_key(KEY_TAB)
	_check(_focus_owner() == view.continue_button,
		"Tab avanza a Continuar al Despacho")
	await _press_key(KEY_TAB, true)
	_check(_focus_owner() == view.club_selector,
		"Mayús+Tab regresa al selector")
	view.club_confirmed.connect(_record_confirmation)
	await _press_key(KEY_TAB)
	await _press_key(KEY_ENTER)
	_check(confirmed_ids == [first_id], "Enter confirma exactamente el ID seleccionado")
	view.queue_free()
	await process_frame


func _test_every_club_navigation() -> void:
	for club_id in EXPECTED_NAMES:
		var menu = MenuScene.instantiate()
		menu.command_line_user_args = PackedStringArray(["--dev-season-pack"])
		root.add_child(menu)
		await process_frame
		var opened = await menu.show_manager_club_selection()
		_check(opened.ok and menu._club_selection_view != null
			and menu._office_view == null and menu.season_host.get_child_count() == 1,
			"%s abre primero una sola selección" % club_id)
		var selector = menu._club_selection_view
		_check(selector.select_club(club_id)
			and selector.get_selected_club_id() == club_id,
			"%s puede seleccionarse por su identificador interno" % club_id)
		var fixtures_before = _fixture_snapshot(menu._office_session.calendar)
		var results_before = menu._office_session.controller.get_results().data.results.size()
		selector.continue_button.pressed.emit()
		await process_frame
		await process_frame
		var office = menu._office_view
		var expected = EXPECTED_AGENDA[club_id]
		_check(office != null and menu._club_selection_view == null
			and office.get_context().club_id == club_id
			and office.club_label.text == "Club dirigido: %s" % EXPECTED_NAMES[club_id],
			"el Despacho muestra el club confirmado %s" % club_id)
		_check(office.agenda_fixture_label.get_meta("fixture_id", "") == expected.fixture_id
			and office.agenda_fixture_label.text.contains(expected.condition)
			and office.agenda_fixture_label.text.contains("Rival: %s" % expected.rival)
			and office.agenda_date_label.text.contains(expected.date),
			"la agenda identifica partido, condición, rival y fecha para %s" % club_id)
		var context = office.get_context()

		office.standings_button.pressed.emit()
		await process_frame
		await process_frame
		_check(menu._office_module == "standings"
			and menu._office_session.club_id == club_id,
			"clasificación conserva el club %s" % club_id)
		menu.back_button.pressed.emit()
		await process_frame
		office = menu._office_view
		_check(office.get_context() == context and _focus_owner() == office.standings_button,
			"volver de clasificación recupera contexto y foco para %s" % club_id)

		office.calendar_button.pressed.emit()
		await process_frame
		await process_frame
		_check(menu._office_module == "calendar"
			and menu._office_session.club_id == club_id,
			"calendario conserva el club %s" % club_id)
		menu.back_button.pressed.emit()
		await process_frame
		office = menu._office_view
		_check(office.get_context() == context and _focus_owner() == office.calendar_button,
			"volver del calendario recupera contexto y foco para %s" % club_id)
		_check(menu._office_session.controller.get_results().data.results.size()
			== results_before and _fixture_snapshot(menu._office_session.calendar) == fixtures_before,
			"el recorrido de %s no genera resultados ni modifica fechas" % club_id)
		office.exit_button.pressed.emit()
		await process_frame
		_check(menu._office_session.is_empty() and menu._office_view == null,
			"salir de %s limpia el club antes de una sesión nueva" % club_id)
		menu.queue_free()
		await process_frame


func _test_invalid_clubs() -> void:
	var prepared = SessionLoader.new().prepare_session("1982-83", DEV_ROOT)
	var office = OfficeScene.instantiate()
	root.add_child(office)
	await process_frame
	var missing = office.configure(
		prepared.data.controller, prepared.data.calendar,
		prepared.data.selection, prepared.data.presentation, ""
	)
	_check(not missing.ok and missing.errors[0].code == "missing_assigned_club",
		"ManagerOffice rechaza una selección nula")
	var unknown = office.configure(
		prepared.data.controller, prepared.data.calendar,
		prepared.data.selection, prepared.data.presentation, "unknown_club"
	)
	_check(not unknown.ok and unknown.errors[0].code == "assigned_club_unavailable",
		"ManagerOffice rechaza un club desconocido")
	var other_season = office.configure(
		prepared.data.controller, prepared.data.calendar,
		prepared.data.selection, prepared.data.presentation, "club_from_1983-84"
	)
	_check(not other_season.ok and other_season.errors[0].code == "assigned_club_unavailable",
		"un club de otra temporada no pertenece a la sesión")
	office.queue_free()
	await process_frame

	var menu = MenuScene.instantiate()
	menu.command_line_user_args = PackedStringArray(["--dev-season-pack"])
	root.add_child(menu)
	await process_frame
	await menu.show_manager_club_selection()
	var selector = menu._club_selection_view
	var invalid_open = await menu.open_manager_office("unknown_club")
	_check(not invalid_open.ok and menu._office_view == null
		and menu._club_selection_view == selector
		and menu.season_host.get_child_count() == 1,
		"un ID inválido no sustituye la selección por una vista parcial")
	_check(selector.error_label.visible
		and selector.error_label.text.contains("assigned_club_unavailable"),
		"el error de club queda visible y recuperable")
	selector.back_button.pressed.emit()
	await process_frame
	_check(menu.menu_presentation.visible and menu._club_selection_view == null
		and menu._office_session.is_empty(),
		"volver desde la selección no crea Despacho y descarta la sesión")
	await menu.show_manager_club_selection()
	menu._club_selection_view.select_club("dev_duna_deportivo")
	menu._club_selection_view.continue_button.pressed.emit()
	await process_frame
	await process_frame
	menu._office_view.exit_button.pressed.emit()
	await process_frame
	await menu.show_manager_club_selection()
	_check(menu._club_selection_view.get_selected_club_id() == "dev_aurora_union"
		and not menu._office_session.has("club_id"),
		"una sesión nueva no conserva accidentalmente el club anterior")
	menu._club_selection_view.back_button.pressed.emit()
	await process_frame
	menu.queue_free()
	await process_frame


func _record_confirmation(club_id: String) -> void:
	confirmed_ids.append(club_id)


func _fixture_snapshot(fixtures: Array) -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for fixture in fixtures:
		snapshot.append({
			"fixture_id": fixture.fixture_id,
			"home": fixture.home_club_id,
			"away": fixture.away_club_id,
			"round": fixture.round_number,
			"date": fixture.scheduled_date,
			"metadata": fixture.metadata.duplicate(true),
		})
	return snapshot


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
