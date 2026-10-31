extends SceneTree

const MenuScene = preload("res://game/scenes/main_menu.tscn")
const TacticsScene = preload("res://game/scenes/manager_tactics.tscn")
const TacticsScript = preload("res://game/scripts/ui/manager_tactics.gd")
const FieldScript = preload("res://game/scripts/ui/tactics_field.gd")
const SessionLoader = preload("res://game/scripts/services/season_session_loader.gd")

const DEV_ROOT = "res://data/dev/seasons"
const SAVE_DIRECTORY = "user://neofutbol/sporting_state"
const EXPECTED_NAMES = {
	"dev_aurora_union": "Aurora Unión",
	"dev_bruma_atletico": "Bruma Atlético",
	"dev_cometa_fc": "Cometa FC",
	"dev_duna_deportivo": "Duna Deportivo",
}

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var saves_before = _save_files()
	await _test_scene_contract_and_all_clubs()
	await _test_formation_selector()
	await _test_responsive_field_geometry()
	await _test_office_navigation_and_keyboard()
	await _test_configuration_and_navigation_failures()
	await _test_normal_mode_isolation()
	_check(_save_files() == saves_before, "consultar Tácticas no crea partidas guardadas")
	_finish()


func _test_scene_contract_and_all_clubs() -> void:
	var prepared = SessionLoader.new().prepare_session("1982-83", DEV_ROOT)
	_check(prepared.ok, "prepara la sesión sintética mediante el loader existente")
	if not prepared.ok:
		return
	var sporting_before = _sporting_snapshot(prepared.data.controller)
	var calendar_before = _fixture_snapshot(prepared.data.calendar)
	for club_id in EXPECTED_NAMES:
		var view = TacticsScene.instantiate()
		root.add_child(view)
		await process_frame
		var configured = view.configure(
			prepared.data.controller, prepared.data.selection,
			prepared.data.presentation, club_id
		)
		var positions = view.field.get_reference_positions()
		var roles = _role_counts(positions)
		_check(configured.ok and configured.data == {
			"season_id": "1982-83", "club_id": club_id, "formation": "4-4-2",
			"assigned_players": 0, "position_count": 11,
		}, "configura la referencia 4-4-2 para %s" % club_id)
		_check(view.get_script() == TacticsScript and view.field.get_script() == FieldScript
			and view.season_label.text == "Temporada técnica 1982-83"
			and view.club_label.text == "Club dirigido: %s" % EXPECTED_NAMES[club_id],
			"identifica pantalla, temporada y club %s" % club_id)
		_check(view.warning_label.text == "MODO DESARROLLO — DATOS SINTÉTICOS"
			and view.formation_label.text
			== "Formación de referencia 4-4-2 · sin jugadores asignados",
			"muestra la advertencia y el carácter provisional para %s" % club_id)
		_check(_selector_ids(view.formation_selector) == ["4-4-2", "4-3-3", "4-2-3-1"]
			and view.formation_selector.selected == 0,
			"el selector comienza en 4-4-2 y conserva el orden requerido")
		_check(view.directed_club_value.text == EXPECTED_NAMES[club_id]
			and view.formation_value.text == "4-4-2" and view.assigned_value.text == "0"
			and view.state_value.text == "Prototipo de visualización táctica"
			and view.simulation_notice.text
			== "La formación no afecta a la simulación deportiva",
			"el panel informativo no aparenta aplicar la formación para %s" % club_id)
		_check(positions.size() == 11 and roles == {
			"goalkeeper": 1, "defender": 4, "midfielder": 4, "forward": 2,
		}, "distribuye 1-4-4-2 posiciones vacías para %s" % club_id)
		_check(_valid_position_contract(positions),
			"ninguna posición de %s contiene un player_id" % club_id)
		view.queue_free()
		await process_frame

		var menu = await _open_office(club_id)
		menu._office_view.tactics_button.pressed.emit()
		await process_frame
		await process_frame
		_check(menu._tactics_view != null
			and menu._tactics_view.get_context().club_id == club_id
			and menu._tactics_view.directed_club_value.text == EXPECTED_NAMES[club_id],
			"el flujo completo abre Tácticas para %s" % club_id)
		menu._tactics_view.back_button.pressed.emit()
		await process_frame
		menu._office_view.exit_button.pressed.emit()
		await process_frame
		menu.queue_free()
		await process_frame
	_check(_sporting_snapshot(prepared.data.controller) == sporting_before
		and _fixture_snapshot(prepared.data.calendar) == calendar_before,
		"la visualización de los cuatro clubes no modifica datos deportivos")


func _test_formation_selector() -> void:
	var prepared = SessionLoader.new().prepare_session("1982-83", DEV_ROOT)
	var view = TacticsScene.instantiate()
	root.add_child(view)
	await process_frame
	view.configure(
		prepared.data.controller, prepared.data.selection,
		prepared.data.presentation, "dev_bruma_atletico"
	)
	var expected_roles = {
		"4-4-2": {"goalkeeper": 1, "defender": 4, "midfielder": 4, "forward": 2},
		"4-3-3": {"goalkeeper": 1, "defender": 4, "midfielder": 3, "forward": 3},
		"4-2-3-1": {"goalkeeper": 1, "defender": 4, "midfielder": 5, "forward": 1},
	}
	for formation_id in ["4-4-2", "4-3-3", "4-2-3-1", "4-4-2"]:
		_select_option(view, formation_id)
		var positions = view.field.get_reference_positions()
		_check(view.get_context().formation == formation_id
			and view.field.get_formation_id() == formation_id
			and view.formation_value.text == formation_id
			and view.formation_label.text
			== "Formación de referencia %s · sin jugadores asignados" % formation_id,
			"selector, cabecera, panel y campo quedan sincronizados en %s" % formation_id)
		_check(positions.size() == 11 and _role_counts(positions) == expected_roles[formation_id]
			and _valid_position_contract(positions),
			"%s contiene once posiciones únicas, normalizadas y sin jugadores" % formation_id)
		_check(view.assigned_value.text == "0"
			and view.directed_club_value.text == "Bruma Atlético"
			and view.season_label.text == "Temporada técnica 1982-83",
			"%s conserva asignaciones, club y temporada" % formation_id)
	var defensive = view.field.get_reference_positions("4-3-3")
	defensive[0].point = Vector2(9.0, 9.0)
	_check(view.field.get_reference_positions("4-3-3")[0].point == Vector2(0.10, 0.50),
		"las posiciones se devuelven mediante copias defensivas")
	view.queue_free()
	await process_frame


func _test_responsive_field_geometry() -> void:
	var prepared = SessionLoader.new().prepare_session("1982-83", DEV_ROOT)
	var view = TacticsScene.instantiate()
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	await process_frame
	view.configure(
		prepared.data.controller, prepared.data.selection,
		prepared.data.presentation, "dev_aurora_union"
	)
	for formation_id in ["4-4-2", "4-3-3", "4-2-3-1"]:
		view.select_formation(formation_id)
		for viewport_size in [Vector2(1000, 700), Vector2(800, 560)]:
			view.size = viewport_size
			await process_frame
			var pitch: Rect2 = view.field.get_pitch_rect()
			var markers: Array[Dictionary] = view.field.get_marker_rects()
			_check(markers.size() == 11 and pitch.size.x > 0.0 and pitch.size.y > 0.0,
				"%s genera once marcadores en %s" % [formation_id, viewport_size])
			_check(markers.all(func(marker): return pitch.encloses(marker.rect)),
				"%s mantiene los marcadores dentro del campo en %s" % [formation_id, viewport_size])
			_check(not _markers_overlap(markers),
				"%s evita solapamientos en %s" % [formation_id, viewport_size])
			_check(absf(view.field.size.x / view.field.size.y - 1.6) < 0.02,
				"%s conserva la proporción del campo en %s" % [formation_id, viewport_size])
	_check(view.field.focus_mode == Control.FOCUS_NONE
		and view.field.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"el dibujo no interfiere con el foco ni la entrada")
	view.queue_free()
	await process_frame


func _test_office_navigation_and_keyboard() -> void:
	var menu = await _open_office("dev_cometa_fc")
	var office = menu._office_view
	var office_context = office.get_context()
	var sporting_before = _sporting_snapshot(menu._office_session.controller)
	var calendar_before = _fixture_snapshot(menu._office_session.calendar)
	_check(not office.squad_button.disabled and not office.tactics_button.disabled
		and office.market_button.disabled and office.advance_button.disabled,
		"habilita Plantilla y Tácticas, manteniendo Mercado y Avanzar deshabilitados")
	office.squad_button.grab_focus()
	await _press_key(KEY_TAB)
	_check(_focus_owner() == office.tactics_button,
		"Tab alcanza Tácticas después de Plantilla")
	await _press_key(KEY_ENTER)
	await process_frame
	await process_frame
	var tactics = menu._tactics_view
	_check(tactics != null and tactics.get_script() == TacticsScript
		and menu._office_module == "tactics" and menu.season_host.get_child_count() == 1,
		"Enter abre una única pantalla de Tácticas")
	_check(tactics.get_context() == {
		"selection": menu._office_session.selection, "club_id": "dev_cometa_fc",
		"formation": "4-4-2", "assigned_players": 0,
	}, "Tácticas conserva exactamente el contexto de sesión y club")
	_check(not menu.back_button.visible and tactics.back_button.is_visible_in_tree()
		and _visible_return_buttons(menu).size() == 1,
		"Tácticas muestra un único retorno visible al Despacho")
	_check(_focus_owner() == tactics.formation_selector,
		"el selector recibe el foco inicial")
	await _press_key(KEY_ENTER)
	await _press_key(KEY_DOWN)
	await _press_key(KEY_ENTER)
	_check(tactics.get_context().formation == "4-3-3"
		and tactics.formation_selector.get_item_metadata(tactics.formation_selector.selected)
		== "4-3-3",
		"el teclado cambia la formación sin depender del índice como ID")
	await _press_key(KEY_TAB)
	_check(_focus_owner() == tactics.back_button,
		"Tab avanza del selector al retorno")
	await _press_key(KEY_TAB, true)
	_check(_focus_owner() == tactics.formation_selector,
		"Mayús+Tab vuelve al selector")
	await _press_key(KEY_TAB)
	await _press_key(KEY_ENTER)
	await process_frame
	office = menu._office_view
	_check(office.get_parent() == menu.season_host and office.get_context() == office_context
		and _focus_owner() == office.tactics_button,
		"Enter vuelve al Despacho y restaura el foco en Tácticas")
	_check(_sporting_snapshot(menu._office_session.controller) == sporting_before
		and _fixture_snapshot(menu._office_session.calendar) == calendar_before
		and not menu._office_session.has("formation")
		and not menu._office_session.has("tactics"),
		"navegar no genera resultados, cambia fechas ni persiste una formación")
	office.tactics_button.pressed.emit()
	await process_frame
	await process_frame
	_check(menu._tactics_view.get_context().formation == "4-4-2"
		and menu._tactics_view.formation_selector.selected == 0,
		"una vista nueva reinicia la referencia a 4-4-2")
	menu._tactics_view.back_button.pressed.emit()
	await process_frame
	office = menu._office_view

	# Una activación repetida durante la transición no crea escenas ni señales extra.
	office.tactics_button.pressed.emit()
	office.tactics_button.pressed.emit()
	await process_frame
	await process_frame
	_check(menu._tactics_view != null and menu.season_host.get_child_count() == 1,
		"activaciones repetidas no duplican la pantalla")
	menu._tactics_view.back_button.pressed.emit()
	await process_frame
	for module_button in [office.standings_button, office.calendar_button, office.squad_button]:
		module_button.pressed.emit()
		await process_frame
		await process_frame
		_check(menu._office_module in ["standings", "calendar", "squad"]
			and menu.season_host.get_child_count() == 1,
			"el módulo %s sigue funcionando después de Tácticas" % menu._office_module)
		if menu._office_module == "squad":
			menu._squad_view.back_button.pressed.emit()
		else:
			menu.back_button.pressed.emit()
		await process_frame
		office = menu._office_view
	office.exit_button.pressed.emit()
	await process_frame
	_check(menu._office_view == null and menu._tactics_view == null
		and menu._office_session.is_empty(),
		"salir libera la vista y el contexto visual")
	menu.queue_free()
	await process_frame


func _test_configuration_and_navigation_failures() -> void:
	var prepared = SessionLoader.new().prepare_session("1982-83", DEV_ROOT)
	var view = TacticsScene.instantiate()
	root.add_child(view)
	await process_frame
	var valid = view.configure(
		prepared.data.controller, prepared.data.selection,
		prepared.data.presentation, "dev_aurora_union"
	)
	var context_before = view.get_context()
	view.select_formation("4-3-3")
	var formation_before = view.get_context().formation
	var selector_before = view.formation_selector.selected
	var rejected_formation = view.select_formation("3-3-4-unknown")
	_check(not rejected_formation.ok
		and rejected_formation.errors[0].code == "unknown_reference_formation"
		and view.get_context().formation == formation_before
		and view.field.get_formation_id() == formation_before
		and view.formation_selector.selected == selector_before,
		"una formación desconocida conserva campo, selector y referencia válidos")
	context_before = view.get_context()
	var wrong_selection = prepared.data.selection.duplicate(true)
	wrong_selection.competition_id = "other_competition"
	var mismatch = view.configure(
		prepared.data.controller, wrong_selection,
		prepared.data.presentation, "dev_aurora_union"
	)
	_check(valid.ok and not mismatch.ok
		and mismatch.errors[0].code == "controller_selection_mismatch"
		and view.get_context() == context_before,
		"una selección incompatible no sustituye la configuración válida")
	var unknown = view.configure(
		prepared.data.controller, prepared.data.selection,
		prepared.data.presentation, "unknown_club"
	)
	_check(not unknown.ok and unknown.errors[0].code == "assigned_club_unavailable",
		"rechaza un club ajeno a la sesión")
	var missing_name = view.configure(
		prepared.data.controller, prepared.data.selection,
		{"club_names": {}}, "dev_aurora_union"
	)
	_check(not missing_name.ok and missing_name.errors[0].code == "missing_club_display_name"
		and view.error_label.visible,
		"un nombre ausente produce un diagnóstico visible y recuperable")
	view.queue_free()
	await process_frame

	var menu = await _open_office("dev_aurora_union")
	var office = menu._office_view
	menu.tactics_scene = null
	var failed = await menu.open_office_module("tactics")
	_check(not failed.ok and failed.errors[0].code == "tactics_scene_unavailable"
		and menu._office_view == office and office.get_parent() == menu.season_host,
		"una escena no disponible conserva el Despacho válido")
	_check(office.error_label.visible
		and office.error_label.text.contains("tactics_scene_unavailable"),
		"el error de navegación queda localizado en el Despacho")
	office.exit_button.pressed.emit()
	await process_frame
	menu.queue_free()
	await process_frame


func _test_normal_mode_isolation() -> void:
	var menu = MenuScene.instantiate()
	menu.command_line_user_args = PackedStringArray()
	root.add_child(menu)
	await process_frame
	var rejected = await menu.show_manager_club_selection()
	_check(not rejected.ok and rejected.errors[0].code == "development_mode_required"
		and menu._tactics_view == null and menu.season_host.get_child_count() == 0,
		"el modo normal no activa Tácticas ni el pack sintético")
	var export_file = FileAccess.open("res://export_presets.cfg", FileAccess.READ)
	var presets = export_file.get_as_text() if export_file != null else ""
	if export_file != null:
		export_file.close()
	_check(presets.contains("exclude_filter=\"data/dev/**,tests/**,tools/**,docs/**\""),
		"la exportación pública mantiene aislados los datos sintéticos")
	menu.queue_free()
	await process_frame


func _open_office(club_id: String):
	var menu = MenuScene.instantiate()
	menu.command_line_user_args = PackedStringArray(["--dev-season-pack"])
	root.add_child(menu)
	await process_frame
	await menu.show_manager_club_selection()
	menu._club_selection_view.select_club(club_id)
	menu._club_selection_view.continue_button.pressed.emit()
	await process_frame
	await process_frame
	return menu


func _role_counts(positions: Array[Dictionary]) -> Dictionary:
	var counts: Dictionary = {}
	for slot in positions:
		counts[slot.role] = counts.get(slot.role, 0) + 1
	return counts


func _valid_position_contract(positions: Array[Dictionary]) -> bool:
	var slot_ids: Dictionary = {}
	for slot in positions:
		if not slot.has("slot_id") or not slot.has("role") or not slot.has("label") \
				or not slot.has("point") or slot.has("player_id") \
				or slot_ids.has(slot.slot_id) or not slot.point is Vector2 \
				or slot.point.x < 0.0 or slot.point.x > 1.0 \
				or slot.point.y < 0.0 or slot.point.y > 1.0:
			return false
		slot_ids[slot.slot_id] = true
	return true


func _selector_ids(selector: OptionButton) -> Array[String]:
	var identifiers: Array[String] = []
	for index in selector.item_count:
		identifiers.append(selector.get_item_metadata(index))
	return identifiers


func _select_option(view, formation_id: String) -> void:
	for index in view.formation_selector.item_count:
		if view.formation_selector.get_item_metadata(index) == formation_id:
			view.formation_selector.select(index)
			view.formation_selector.item_selected.emit(index)
			return


func _markers_overlap(markers: Array[Dictionary]) -> bool:
	for left_index in markers.size():
		for right_index in range(left_index + 1, markers.size()):
			if markers[left_index].rect.intersects(markers[right_index].rect):
				return true
	return false


func _visible_return_buttons(parent: Node) -> Array[Node]:
	var buttons: Array[Node] = []
	for candidate in parent.find_children("*", "Button", true, false):
		if candidate.text == "Volver al Despacho" and candidate.is_visible_in_tree():
			buttons.append(candidate)
	return buttons


func _sporting_snapshot(controller) -> Dictionary:
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
	return fixtures.map(func(fixture): return {
		"fixture_id": fixture.fixture_id,
		"scheduled_date": fixture.scheduled_date,
		"round_number": fixture.round_number,
		"metadata": fixture.metadata.duplicate(true),
	})


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
