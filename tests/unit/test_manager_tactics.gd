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
	await _test_position_selection_contract()
	await _test_pointer_position_selection()
	await _test_keyboard_selection_details_visibility()
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
		_check(view.field.get_selected_position() == null
			and view.selection_prompt.text == "Selecciona una posición del campo"
			and not view.selection_details.visible,
			"%s comienza sin una posición seleccionada" % club_id)
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


func _test_position_selection_contract() -> void:
	var prepared = SessionLoader.new().prepare_session("1982-83", DEV_ROOT)
	var view = TacticsScene.instantiate()
	root.add_child(view)
	await process_frame
	view.configure(
		prepared.data.controller, prepared.data.selection,
		prepared.data.presentation, "dev_bruma_atletico"
	)
	var changes: Array = []
	view.field.selection_changed.connect(func(position): changes.append(position))
	var positions = view.field.get_reference_positions()
	var line_names = {
		"goalkeeper": "Portería", "defender": "Defensa",
		"midfielder": "Centro del campo", "forward": "Delantera",
	}
	for position in positions:
		var selected = view.field.select_slot(position.slot_id)
		var current = view.field.get_selected_position()
		_check(selected.ok and current == position
			and view.selected_slot_value.text == position.slot_id
			and view.selected_label_value.text == position.label,
			"selecciona %s por su slot_id y presenta su identidad" % position.slot_id)
		_check(view.selected_line_value.text == line_names[position.role]
			and view.selected_status_value.text == "Sin jugador asignado"
			and view.selection_details.visible and not current.has("player_id"),
			"presenta la línea y el estado vacío de %s" % position.slot_id)
	_check(changes.size() == 11,
		"cada una de las once posiciones produce un único cambio de selección")
	view.field.select_slot(positions[-1].slot_id)
	_check(changes.size() == 11,
		"seleccionar de nuevo la posición activa no duplica el evento")
	var defensive = view.field.get_selected_position()
	defensive.label = "ALTERADO"
	defensive.point = Vector2(9.0, 9.0)
	_check(view.field.get_selected_position().label == positions[-1].label
		and view.field.get_selected_position().point == positions[-1].point,
		"la consulta de selección devuelve una copia defensiva")
	var previous = view.field.get_selected_position()
	var rejected = view.field.select_slot("unknown_slot")
	_check(not rejected.ok and rejected.errors[0].code == "unknown_tactical_position"
		and rejected.errors[0].slot_id == "unknown_slot"
		and view.field.get_selected_position() == previous,
		"un slot_id desconocido conserva la selección y devuelve un diagnóstico")
	view.field.clear_selection()
	_check(view.field.get_selected_position() == null
		and view.selection_prompt.text == "Selecciona una posición del campo"
		and not view.selection_details.visible,
		"limpiar la selección restaura el estado inicial del panel")
	view.field.select_slot("442_mid_2")
	_select_option(view, "4-3-3")
	_check(view.field.get_selected_position() == null
		and view.get_context().formation == "4-3-3"
		and view.selection_prompt.text == "Selecciona una posición del campo"
		and view.directed_club_value.text == "Bruma Atlético"
		and view.assigned_value.text == "0",
		"cambiar de formación limpia la selección y conserva el contexto deportivo")
	view.queue_free()
	await process_frame


func _test_pointer_position_selection() -> void:
	var prepared = SessionLoader.new().prepare_session("1982-83", DEV_ROOT)
	var view = TacticsScene.instantiate()
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	await process_frame
	view.configure(
		prepared.data.controller, prepared.data.selection,
		prepared.data.presentation, "dev_duna_deportivo"
	)
	var changes: Array = []
	view.field.selection_changed.connect(func(position): changes.append(position))
	for viewport_size in [Vector2(1000, 700), Vector2(800, 560)]:
		view.size = viewport_size
		await process_frame
		var markers = view.field.get_marker_rects()
		view.field.clear_selection()
		view.formation_selector.grab_focus()
		await process_frame
		var changes_before = changes.size()
		await _click_field_via_viewport(
			view.field, _empty_field_point(view.field), true
		)
		_check(view.field.get_selected_position() == null and view.field.has_focus()
			and changes.size() == changes_before,
			"el primer clic vacío entregado por el viewport enfoca sin seleccionar en %s"
			% viewport_size)
		view.formation_selector.grab_focus()
		await process_frame
		changes_before = changes.size()
		await _click_field_via_viewport(
			view.field, markers[3].rect.get_center(), true
		)
		var clicked_position = view.field.get_selected_position()
		_check(clicked_position != null and clicked_position.slot_id == markers[3].slot_id
			and view.field.has_focus() and changes.size() == changes_before + 1,
			"el primer clic real selecciona solo su marcador y emite una señal en %s"
			% viewport_size)
		var selected_before = view.field.get_selected_position()
		await _click_field_via_viewport(view.field, _empty_field_point(view.field))
		await _click_field_via_viewport(view.field, Vector2(1.0, 1.0))
		await _click_field_via_viewport(view.field, markers[5].rect.position)
		_check(view.field.get_selected_position() == selected_before,
			"los clics vacíos, fuera del terreno o fuera del radio conservan la selección en %s"
			% viewport_size)
		changes_before = changes.size()
		await _click_field_via_viewport(view.field, markers[8].rect.get_center())
		clicked_position = view.field.get_selected_position()
		_check(clicked_position != null and clicked_position.slot_id == markers[8].slot_id,
			"un segundo clic sustituye la única selección activa en %s" % viewport_size)
		_check(changes.size() == changes_before + 1,
			"cambiar de marcador mediante el viewport emite una sola señal en %s"
			% viewport_size)
	view.queue_free()
	await process_frame


func _test_keyboard_selection_details_visibility() -> void:
	var prepared = SessionLoader.new().prepare_session("1982-83", DEV_ROOT)
	var view = TacticsScene.instantiate()
	root.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	await process_frame
	view.configure(
		prepared.data.controller, prepared.data.selection,
		prepared.data.presentation, "dev_duna_deportivo"
	)
	for viewport_size in [Vector2(1000, 700), Vector2(800, 560)]:
		view.size = viewport_size
		view.select_formation("4-4-2")
		view.field.clear_selection()
		view.formation_selector.grab_focus()
		await process_frame
		await _press_key(KEY_TAB)
		await process_frame
		await process_frame
		_check(view.field.get_selected_position().slot_id == "442_gk"
			and _control_visible_in_scroll(view.info_scroll, view.selection_details),
			"Tab selecciona el portero y muestra sus detalles completos en %s"
			% viewport_size)
		await _press_key(KEY_RIGHT)
		await process_frame
		await process_frame
		_check(view.field.get_selected_position().role == "defender"
			and _control_visible_in_scroll(view.info_scroll, view.selection_details),
			"las flechas mantienen accesibles los detalles desplazados en %s"
			% viewport_size)
		await _press_key(KEY_TAB, true)
		_select_option(view, "4-2-3-1")
		await process_frame
		_check(_focus_owner() == view.formation_selector
			and view.field.get_selected_position() == null
			and view.info_scroll.scroll_vertical == 0,
			"cambiar la formación restaura el panel sin alterar el foco en %s"
			% viewport_size)
		await _press_key(KEY_TAB)
		await process_frame
		await process_frame
		await process_frame
		_check(view.field.get_selected_position().slot_id == "4231_gk"
			and _control_visible_in_scroll(view.info_scroll, view.selection_details),
			"la nueva formación vuelve a revelar los detalles por teclado en %s"
			% viewport_size)
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
	_check(view.field.focus_mode == Control.FOCUS_ALL
		and view.field.mouse_filter == Control.MOUSE_FILTER_STOP,
		"el campo acepta foco y consume su propia entrada de interfaz")
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
	await process_frame
	_check(_focus_owner() == tactics.field and tactics.field.has_focus()
		and tactics.field.get_selected_position() != null
		and tactics.field.get_selected_position().slot_id == "433_gk",
		"Tab lleva el foco visible al campo y selecciona el portero de forma determinista")
	var formation_before_arrows = tactics.get_context().formation
	var arrow_slots: Array[String] = []
	for keycode in [KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_LEFT]:
		await _press_key(keycode)
		arrow_slots.append(tactics.field.get_selected_position().slot_id)
	_check(arrow_slots[0] != "433_gk" and arrow_slots[1] != arrow_slots[0]
		and arrow_slots[2] != arrow_slots[1] and arrow_slots[3] != arrow_slots[2],
		"las cuatro flechas recorren posiciones de manera espacial y determinista")
	_check(tactics.get_context().formation == formation_before_arrows
		and _focus_owner() == tactics.field,
		"las flechas del campo no cambian la formación ni transfieren el foco")
	var confirmations: Array = []
	var changes: Array = []
	tactics.field.position_confirmed.connect(func(position): confirmations.append(position))
	tactics.field.selection_changed.connect(func(position): changes.append(position))
	var active_before_enter = tactics.field.get_selected_position()
	await _press_key(KEY_ENTER)
	_check(confirmations.size() == 1 and confirmations[0] == active_before_enter
		and changes.is_empty() and _focus_owner() == tactics.field,
		"Enter confirma una vez la posición visual sin alterar la selección")
	await _press_key(KEY_TAB)
	_check(_focus_owner() == tactics.back_button,
		"Tab avanza del campo al retorno")
	await _press_key(KEY_TAB, true)
	_check(_focus_owner() == tactics.field,
		"Mayús+Tab vuelve del retorno al campo")
	await _press_key(KEY_TAB, true)
	_check(_focus_owner() == tactics.formation_selector,
		"Mayús+Tab vuelve del campo al selector")
	await _press_key(KEY_TAB)
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
		and menu._tactics_view.formation_selector.selected == 0
		and menu._tactics_view.field.get_selected_position() == null,
		"una vista nueva reinicia 4-4-2 y la ausencia de selección")
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
	view.field.select_slot("433_mid_2")
	var formation_before = view.get_context().formation
	var position_before = view.field.get_selected_position()
	var selector_before = view.formation_selector.selected
	var rejected_formation = view.select_formation("3-3-4-unknown")
	_check(not rejected_formation.ok
		and rejected_formation.errors[0].code == "unknown_reference_formation"
		and view.get_context().formation == formation_before
		and view.field.get_formation_id() == formation_before
		and view.field.get_selected_position() == position_before
		and view.formation_selector.selected == selector_before,
		"una formación desconocida conserva campo, selección y referencia válidos")
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


func _click_field_via_viewport(field: Control, local_position: Vector2,
		focus_before_delivery := false) -> void:
	var viewport_position = field.get_global_transform_with_canvas() * local_position
	if focus_before_delivery:
		# Reproduce el orden observado en el viewport: focus_entered puede llegar
		# antes de que el Control reciba el InputEventMouseButton.
		field.grab_focus()
	for pressed in [true, false]:
		var event = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = viewport_position
		event.global_position = viewport_position
		root.push_input(event, true)
		await process_frame
	await process_frame


func _empty_field_point(field) -> Vector2:
	var pitch: Rect2 = field.get_pitch_rect()
	var markers: Array[Dictionary] = field.get_marker_rects()
	for x_step in range(1, 10):
		for y_step in range(1, 10):
			var point = pitch.position + Vector2(
				pitch.size.x * float(x_step) / 10.0,
				pitch.size.y * float(y_step) / 10.0
			)
			var outside_markers = markers.all(func(marker):
				var radius: float = marker.rect.size.x * 0.5
				return marker.rect.get_center().distance_to(point) > radius
			)
			if outside_markers:
				return point
	return pitch.get_center()


func _control_visible_in_scroll(scroll: ScrollContainer, control: Control) -> bool:
	var viewport_rect = scroll.get_global_rect().grow(0.5)
	var control_rect = control.get_global_rect()
	return viewport_rect.encloses(control_rect)


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
