extends SceneTree

const MenuScene = preload("res://game/scenes/main_menu.tscn")
const SquadScene = preload("res://game/scenes/manager_squad.tscn")
const SquadScript = preload("res://game/scripts/ui/manager_squad.gd")
const SessionLoader = preload("res://game/scripts/services/season_session_loader.gd")
const Player = preload("res://game/scripts/data/player_season.gd")

const DEV_ROOT = "res://data/dev/seasons"
const SAVE_DIRECTORY = "user://neofutbol/sporting_state"
const EXPECTED = {
	"dev_aurora_union": ["dev_player_aurora_01", "Ariel Norte"],
	"dev_bruma_atletico": ["dev_player_bruma_01", "Berto Niebla"],
	"dev_cometa_fc": ["dev_player_cometa_01", "Ciro Estela"],
	"dev_duna_deportivo": ["dev_player_duna_01", "Dario Arena"],
}

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var saves_before = _save_files()
	await _test_validated_players_and_all_clubs()
	await _test_fallback_empty_and_exact_filtering()
	await _test_office_navigation_and_keyboard()
	await _test_recoverable_navigation_error()
	_check(_save_files() == saves_before, "consultar Plantilla no crea partidas guardadas")
	_finish()


func _test_validated_players_and_all_clubs() -> void:
	var prepared = SessionLoader.new().prepare_session("1982-83", DEV_ROOT)
	_check(prepared.ok and prepared.data.players.size() == 4,
		"SeasonSessionLoader expone los cuatro PlayerSeason ya validados")
	if not prepared.ok:
		return
	var original_snapshot = _player_snapshot(prepared.data.players)
	for club_id in EXPECTED:
		var view = SquadScene.instantiate()
		root.add_child(view)
		await process_frame
		var configured = view.configure(
			prepared.data.players, prepared.data.selection,
			prepared.data.presentation, club_id
		)
		var rows = _rows(view.players_tree)
		var expected = EXPECTED[club_id]
		_check(configured.ok and configured.data.club_id == club_id
			and configured.data.player_count == 1,
			"%s configura exactamente un jugador" % club_id)
		_check(rows.size() == 1 and rows[0].name == expected[1]
			and rows[0].player_id == expected[0]
			and rows[0].metadata == {
				"player_id": expected[0], "season_id": "1982-83", "club_id": club_id,
			}, "muestra nombre e identificadores exactos de %s" % club_id)
		_check(view.club_label.text.contains(prepared.data.presentation.club_names[club_id])
			and view.season_label.text.contains("1982-83")
			and view.warning_label.text.contains("DATOS SINTÉTICOS"),
			"la cabecera conserva club, temporada y advertencia para %s" % club_id)
		_check(view.count_label.text.contains("1 jugador disponible")
			and view.count_label.text.contains("cobertura parcial")
			and rows[0].data == "Sin datos",
			"documenta cobertura parcial y ausencia de datos para %s" % club_id)
		view.queue_free()
		await process_frame
		var menu = MenuScene.instantiate()
		menu.command_line_user_args = PackedStringArray(["--dev-season-pack"])
		root.add_child(menu)
		await process_frame
		await menu.show_manager_club_selection()
		menu._club_selection_view.select_club(club_id)
		menu._club_selection_view.continue_button.pressed.emit()
		await process_frame
		await process_frame
		menu._office_view.squad_button.pressed.emit()
		await process_frame
		await process_frame
		_check(menu._squad_view != null
			and _rows(menu._squad_view.players_tree)[0].player_id == expected[0],
			"el flujo Menú → club → Despacho abre Plantilla para %s" % club_id)
		menu._squad_view.back_button.pressed.emit()
		await process_frame
		menu._office_view.exit_button.pressed.emit()
		await process_frame
		menu.queue_free()
		await process_frame
	_check(_player_snapshot(prepared.data.players) == original_snapshot,
		"renderizar los cuatro clubes no modifica los PlayerSeason de la sesión")


func _test_fallback_empty_and_exact_filtering() -> void:
	var selection = {
		"season_id": "1982-83", "competition_id": "dev_league",
		"stage_id": "regular", "group_id": null,
	}
	var presentation = {"club_names": {"club_a": "Club A"}}
	var valid = _player("b_player", "1982-83", "club_a", " Nombre exacto ")
	var fallback = _player("a_player", "1982-83", "club_a", "Nombre\ninválido")
	var historical = _player("c_historical", "1982-83", "club_a", "Histórico")
	historical.historical_data = {"source_value": 1}
	var game = _player("d_game", "1982-83", "club_a", "Juego")
	game.game_data = {"rating": 1}
	var other_club = _player("other", "1982-83", "Club_A", "No visible")
	var other_season = _player("old", "1981-82", "club_a", "No visible")
	var view = SquadScene.instantiate()
	root.add_child(view)
	await process_frame
	var candidates: Array[Player] = [
		valid, fallback, historical, game, other_club, other_season,
	]
	var configured = view.configure(candidates, selection, presentation, "club_a")
	var rows = _rows(view.players_tree)
	_check(configured.ok and rows.map(func(row): return row.player_id)
		== ["a_player", "b_player", "c_historical", "d_game"],
		"filtra temporada y club exactamente y ordena por player_id")
	_check(rows[0].name == "a_player" and rows[1].name == " Nombre exacto ",
		"un nombre inválido usa player_id y un nombre válido se conserva exactamente")
	valid.metadata.display_name = "Mutado fuera"
	_check(_rows(view.players_tree)[1].name == " Nombre exacto ",
		"la vista mantiene una copia defensiva del nombre presentado")
	rows = _rows(view.players_tree)
	_check(rows[0].data == "Sin datos" and rows[1].data == "Sin datos"
		and rows[2].data == "Datos históricos" and rows[3].data == "Datos de juego",
		"distingue datos históricos, datos de juego y ausencia de ambos")
	var no_players: Array[Player] = []
	var empty = view.configure(no_players, selection, presentation, "club_a")
	_check(empty.ok and empty.data.player_count == 0 and view.empty_label.visible
		and not view.players_tree.visible and view.count_label.text.contains("0 jugadores"),
		"una colección vacía muestra un estado no fatal sin tabla ficticia")
	view.focus_initial_control()
	_check(_focus_owner() == view.back_button,
		"el estado vacío mantiene disponible el retorno por teclado")
	var invalid = view.configure(no_players, selection, {"club_names": {}}, "club_a")
	_check(not invalid.ok and invalid.errors[0].code == "missing_club_display_name"
		and view.empty_label.visible,
		"un error recuperable no reemplaza el último estado válido")
	view.queue_free()
	await process_frame


func _test_office_navigation_and_keyboard() -> void:
	var menu = MenuScene.instantiate()
	menu.command_line_user_args = PackedStringArray(["--dev-season-pack"])
	root.add_child(menu)
	await process_frame
	await menu.show_manager_club_selection()
	menu._club_selection_view.select_club("dev_cometa_fc")
	menu._club_selection_view.continue_button.pressed.emit()
	await process_frame
	await process_frame
	var office = menu._office_view
	var office_context = office.get_context()
	var sporting_before = _sporting_snapshot(menu._office_session.controller)
	var players_before = _player_snapshot(menu._office_session.players)
	_check(not office.squad_button.disabled
		and not office.tactics_button.disabled and office.market_button.disabled
		and office.advance_button.disabled,
		"el Despacho mantiene Plantilla y Tácticas disponibles")
	office.calendar_button.grab_focus()
	await _press_key(KEY_TAB)
	_check(_focus_owner() == office.squad_button,
		"Tab alcanza Plantilla desde el calendario")
	await _press_key(KEY_ENTER)
	await process_frame
	await process_frame
	var squad = menu._squad_view
	_check(squad != null and squad.get_script() == SquadScript
		and menu._office_module == "squad" and menu.season_host.get_child_count() == 1,
		"Enter abre una sola pantalla funcional de Plantilla")
	_check(squad.get_context() == {
		"selection": menu._office_session.selection,
		"club_id": "dev_cometa_fc", "player_ids": ["dev_player_cometa_01"],
	}, "la pantalla conserva sesión, club y jugador seleccionados")
	_check(not menu.back_button.visible and squad.back_button.is_visible_in_tree()
		and _visible_return_buttons(menu).size() == 1,
		"Plantilla presenta un único botón visible Volver al Despacho")
	_check(_focus_owner() == squad.players_tree,
		"la tabla recibe foco visible al entrar")
	await _press_key(KEY_TAB)
	_check(_focus_owner() == squad.back_button, "Tab alcanza Volver al Despacho")
	await _press_key(KEY_TAB, true)
	_check(_focus_owner() == squad.players_tree, "Mayús+Tab regresa a la tabla")
	squad.back_button.grab_focus()
	await _press_key(KEY_ENTER)
	await process_frame
	office = menu._office_view
	_check(office.get_parent() == menu.season_host
		and office.get_context() == office_context and _focus_owner() == office.squad_button,
		"volver conserva club, sesión y agenda y restaura el foco de Plantilla")
	_check(_sporting_snapshot(menu._office_session.controller) == sporting_before
		and _player_snapshot(menu._office_session.players) == players_before,
		"la navegación no altera resultados, calendario ni jugadores")
	office.squad_button.pressed.emit()
	office.squad_button.pressed.emit()
	await process_frame
	await process_frame
	_check(menu._squad_view != null and menu.season_host.get_child_count() == 1,
		"activaciones repetidas no crean vistas duplicadas")
	menu._squad_view.back_button.pressed.emit()
	await process_frame
	menu._office_view.standings_button.pressed.emit()
	await process_frame
	await process_frame
	_check(menu._season_view != null and menu._office_module == "standings",
		"la clasificación continúa funcionando después de Plantilla")
	_check(menu.back_button.is_visible_in_tree()
		and _visible_return_buttons(menu).size() == 1,
		"clasificación conserva un único retorno global")
	menu.back_button.pressed.emit()
	await process_frame
	menu._office_view.calendar_button.pressed.emit()
	await process_frame
	await process_frame
	_check(menu._season_view != null and menu._office_module == "calendar",
		"el calendario continúa funcionando después de Plantilla")
	menu.back_button.pressed.emit()
	await process_frame
	menu._office_view.exit_button.pressed.emit()
	await process_frame
	_check(menu._office_view == null and menu._squad_view == null
		and menu._office_session.is_empty(),
		"salir libera la vista y la sesión visual")
	menu.queue_free()
	await process_frame


func _test_recoverable_navigation_error() -> void:
	var menu = MenuScene.instantiate()
	menu.command_line_user_args = PackedStringArray(["--dev-season-pack"])
	root.add_child(menu)
	await process_frame
	await menu.show_manager_club_selection()
	menu._club_selection_view.continue_button.pressed.emit()
	await process_frame
	await process_frame
	var office = menu._office_view
	menu.squad_scene = null
	var failed = await menu.open_office_module("squad")
	_check(not failed.ok and failed.errors[0].code == "squad_scene_unavailable"
		and menu._office_view == office and office.get_parent() == menu.season_host,
		"una escena no disponible conserva el Despacho válido")
	_check(office.error_label.visible and office.error_label.text.contains("squad_scene_unavailable"),
		"el fallo queda visible y localizado")
	var export_file = FileAccess.open("res://export_presets.cfg", FileAccess.READ)
	var presets = export_file.get_as_text() if export_file != null else ""
	if export_file != null:
		export_file.close()
	_check(presets.contains("exclude_filter=\"data/dev/**,tests/**,tools/**,docs/**\""),
		"la exportación pública mantiene aislados pack y pruebas de desarrollo")
	menu.queue_free()
	await process_frame


func _player(player_id: String, season_id: String, club_id: String,
		display_name: Variant) -> Player:
	var player = Player.new()
	player.player_id = player_id
	player.season_id = season_id
	player.club_id = club_id
	player.historical_data = {}
	player.game_data = {}
	player.metadata = {"display_name": display_name}
	return player


func _rows(tree: Tree) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var item = tree.get_root().get_first_child() if tree.get_root() != null else null
	while item != null:
		rows.append({
			"name": item.get_text(0), "player_id": item.get_text(1),
			"data": item.get_text(2), "metadata": item.get_metadata(0),
		})
		item = item.get_next()
	return rows


func _visible_return_buttons(parent: Node) -> Array[Node]:
	var buttons: Array[Node] = []
	for candidate in parent.find_children("*", "Button", true, false):
		if candidate.text == "Volver al Despacho" and candidate.is_visible_in_tree():
			buttons.append(candidate)
	return buttons


func _player_snapshot(players: Array) -> Array[Dictionary]:
	return players.map(func(player): return {
		"player_id": player.player_id, "season_id": player.season_id,
		"club_id": player.club_id, "historical_data": player.historical_data.duplicate(true),
		"game_data": player.game_data.duplicate(true), "metadata": player.metadata.duplicate(true),
	})


func _sporting_snapshot(controller) -> Dictionary:
	var context = controller.get_session_context()
	var results = controller.get_results()
	return {
		"selection": context.data.selection.duplicate(true),
		"fixtures": context.data.fixtures.map(func(fixture): return {
			"id": fixture.fixture_id, "date": fixture.scheduled_date,
			"round": fixture.round_number, "metadata": fixture.metadata.duplicate(true),
		}),
		"results": results.data.results.map(func(result): return result.fixture_id),
	}


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
