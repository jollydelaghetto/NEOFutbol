extends SceneTree

const Scene = preload("res://game/scenes/season_overview.tscn")
const Controller = preload("res://game/scripts/services/season_controller.gd")
const Club = preload("res://game/scripts/data/club_season.gd")
const Fixture = preload("res://game/scripts/data/match_fixture.gd")
const Result = preload("res://game/scripts/data/match_result.gd")
const Rules = preload("res://game/scripts/data/competition_rules.gd")

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	await _test_scene_and_demo()
	await _test_configuration_and_rendering()
	await _test_updates_and_errors()
	_finish()


func _test_scene_and_demo() -> void:
	var view = Scene.instantiate()
	_check(view != null, "carga la escena independiente")
	root.add_child(view)
	await process_frame
	_check(view.synthetic_badge.visible, "la demostración se identifica como sintética")
	_check(view.competition_title.text.contains("Liga sintética"),
		"la demostración publica temporada y competición")
	_check(_tree_rows(view.standings_tree).size() == 4,
		"la demostración presenta cuatro clubes ficticios")
	_check(view.round_selector.item_count == 3, "la demostración genera tres jornadas")
	_check(_match_texts(view).any(func(text): return text.contains("Pendiente")),
		"la demostración incluye partidos pendientes")
	_check(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility",
		"el proyecto conserva el renderizador Compatibility")
	view.queue_free()
	await process_frame


func _test_configuration_and_rendering() -> void:
	var clubs = _clubs()
	var fixtures = _fixtures()
	var rules = _rules(["goal_difference", "goals_for", "wins"])
	var controller = Controller.new()
	_check(controller.initialize(clubs, fixtures, rules, _selection()).ok,
		"inicializa el controlador sintético")
	var source_snapshot = _fixture_snapshot(fixtures)
	var selection = _selection()
	var metadata = {
		"season_name": "Temporada visible", "competition_name": "Copa visible",
		"synthetic": true,
		"club_names": {"club_a": "Águilas", "club_b": "Bosque", "club_c": "Cauce", "club_d": "Delta"},
	}
	var selection_snapshot = selection.duplicate(true)
	var metadata_snapshot = metadata.duplicate(true)
	var view = await _new_view()
	var configured = view.configure(controller, fixtures, selection, metadata)
	_check(configured.ok, "configura una temporada inicializada")
	_check(configured.data.round_numbers == [1, 2, 3] and configured.data.selected_round == 1,
		"descubre las jornadas y selecciona la primera")
	_check(configured.data.standings_row_count == 4 and configured.data.match_count == 2,
		"informa filas y partidos representados")
	_check(view.competition_title.text == "Temporada visible · Copa visible",
		"muestra los nombres de temporada y competición")
	_check(view.scope_label.text.contains("regular") and view.scope_label.text.contains("sin grupo"),
		"muestra el ámbito exacto")
	_check(view.synthetic_badge.visible, "muestra la etiqueta sintética configurada")

	var expected_titles = ["Pos", "Club", "PJ", "G", "E", "P", "GF", "GC", "DG", "Pts"]
	_check(view.standings_tree.columns == 10, "la tabla tiene diez columnas")
	var titles: Array[String] = []
	for column in view.standings_tree.columns:
		titles.append(view.standings_tree.get_column_title(column))
	_check(titles == expected_titles, "la tabla conserva los encabezados deportivos")
	var initial_rows = _tree_rows(view.standings_tree)
	_check(initial_rows.size() == 4, "crea una fila por club")
	_check(initial_rows.all(func(row): return row[0] == "1" and row.slice(2) == ["0", "0", "0", "0", "0", "0", "0", "0"]),
		"la clasificación inicial conserva posiciones compartidas y estadísticas a cero")
	_check(initial_rows[0][1] == "Águilas", "usa el nombre visible del club")
	_check(view.round_selector.get_item_text(0) == "Jornada 1"
		and view.round_selector.get_item_text(2) == "Jornada 3",
		"el selector etiqueta todas las jornadas")
	var round_one_text = "\n".join(_match_texts(view))
	_check(round_one_text.contains("Pendiente") and not round_one_text.contains("0 – 0"),
		"un partido sin resultado aparece pendiente y no como empate")
	_check(round_one_text.contains("2099-01-01") and round_one_text.contains("Fecha por determinar"),
		"distingue fechas conocidas y desconocidas")

	view.round_selector.select(1)
	view.round_selector.item_selected.emit(1)
	_check(_match_fixture_ids(view) == ["fixture_03", "fixture_04"],
		"cambiar el selector muestra la jornada elegida en orden determinista")
	_check(view.refresh_view().data.selected_round == 2,
		"refrescar conserva la jornada seleccionada")

	var extended: Array[Fixture] = _copy_fixtures(fixtures)
	extended.append(_fixture("other_comp", "club_a", "club_b", 8, null, "other", "regular", null))
	extended.append(_fixture("other_stage", "club_a", "club_b", 9, null, "league", "playoff", null))
	extended.append(_fixture("other_group", "club_a", "club_b", 10, null, "league", "regular", "x"))
	var filtered_view = await _new_view()
	var filtered = filtered_view.configure(controller, extended, _selection(), {})
	_check(filtered.ok and filtered.data.round_numbers == [1, 2, 3],
		"excluye otras competiciones, fases y grupos")
	_check(_tree_rows(filtered_view.standings_tree)[0][1].begins_with("club_"),
		"usa el identificador estable cuando falta nombre visible")

	fixtures[0].fixture_id = "alterado"
	fixtures[0].metadata["alterado"] = true
	selection.season_id = "alterada"
	metadata.club_names.club_a = "Alterado"
	_check(_fixture_snapshot(view._fixtures) == source_snapshot,
		"la vista conserva una copia defensiva del calendario")
	_check(view._selection == selection_snapshot and view._display_metadata == metadata_snapshot,
		"la vista conserva copias defensivas de selección y metadatos")
	var before_refresh = _controller_snapshot(controller)
	view.refresh_view()
	_check(_controller_snapshot(controller) == before_refresh,
		"refrescar no modifica el estado deportivo")

	view.queue_free()
	filtered_view.queue_free()
	await process_frame


func _test_updates_and_errors() -> void:
	var fixtures = _fixtures()
	var controller = Controller.new()
	_check(controller.initialize(_clubs(), fixtures,
		_rules(["head_to_head_points", "head_to_head_goal_difference"]), _selection()).ok,
		"inicializa reglas directas para diagnósticos")
	var view = await _new_view()
	_check(view.configure(controller, fixtures, _selection(), {}).ok,
		"configura la vista de actualización")
	var result = _result("fixture_01", 2, 1)
	_check(controller.apply_round([result], 1).ok, "aplica un resultado parcial mediante el controlador")
	var refreshed = view.refresh_view()
	_check(refreshed.ok and refreshed.data.provisional
		and refreshed.data.pending_tiebreaker_count > 0,
		"refresca el estado provisional y sus diagnósticos")
	_check(view.diagnostics_panel.visible
		and view.pending_diagnostics_label.text.contains("pending_head_to_head_tiebreaker")
		and view.pending_diagnostics_label.text.contains("missing_results"),
		"presenta código y motivo del desempate pendiente")
	_check("\n".join(_match_texts(view)).contains("2 – 1"),
		"presenta el marcador final del controlador")
	_check(controller.apply_round([_result("fixture_02", 1, 1)], 1).ok,
		"aplica un empate sintético mediante el controlador")
	view.refresh_view()
	var sporting_rows = controller.get_standings().data.rows
	var visual_rows = _tree_rows(view.standings_tree)
	_check(_visual_matches_rows(visual_rows, sporting_rows),
		"la tabla reproduce posiciones, puntos, balance, goles y empates del servicio")

	var correction = {
		"season_id": "season_a", "fixture_id": "fixture_01",
		"expected_home_goals": 2, "expected_away_goals": 1,
		"new_home_goals": 0, "new_away_goals": 3,
		"reason": "Acta sintética rectificada", "correction_id": "ui-correction-1",
	}
	_check(controller.correct_results([correction]).ok, "rectifica el resultado mediante el controlador")
	view.refresh_view()
	_check("\n".join(_match_texts(view)).contains("0 – 3"),
		"el refresco refleja una rectificación")

	var empty_controller = Controller.new()
	var no_fixtures: Array[Fixture] = []
	_check(empty_controller.initialize(_clubs(), no_fixtures,
		_rules(["goal_difference"]), _selection()).ok,
		"admite una selección sin calendario")
	var empty_view = await _new_view()
	var empty = empty_view.configure(empty_controller, no_fixtures, _selection(), {})
	_check(empty.ok and empty.data.round_numbers.is_empty() and empty.data.match_count == 0,
		"representa un calendario vacío")
	_check(empty_view.round_selector.disabled
		and "\n".join(_match_texts(empty_view)).contains("No hay jornadas"),
		"explica el estado vacío")

	var invalid_view = await _new_view()
	var invalid = invalid_view.configure(controller, fixtures, {"season_id": "season_a"}, {})
	_check(not invalid.ok and invalid.errors[0].code == "missing_selection"
		and invalid_view.error_label.visible, "muestra una configuración inválida")
	var uninitialized = invalid_view.configure(Controller.new(), fixtures, _selection(), {})
	_check(not uninitialized.ok and uninitialized.errors[0].code == "not_initialized"
		and invalid_view.error_label.visible, "muestra el error de controlador no inicializado")
	_check(not invalid_view.refresh_view().ok and invalid_view.error_label.visible,
		"refrescar sin configuración mantiene un error visible")

	view.queue_free()
	empty_view.queue_free()
	invalid_view.queue_free()
	await process_frame


func _new_view():
	var view = Scene.instantiate()
	view.auto_demo = false
	root.add_child(view)
	await process_frame
	return view


func _clubs() -> Array[Club]:
	var clubs: Array[Club] = []
	for club_id in ["club_a", "club_b", "club_c", "club_d"]:
		var club = Club.new()
		club.club_id = club_id
		club.season_id = "season_a"
		club.division_id = "division_a"
		clubs.append(club)
	return clubs


func _fixtures() -> Array[Fixture]:
	return [
		_fixture("fixture_02", "club_c", "club_d", 1),
		_fixture("fixture_01", "club_a", "club_b", 1, "2099-01-01"),
		_fixture("fixture_04", "club_b", "club_d", 2),
		_fixture("fixture_03", "club_a", "club_c", 2),
		_fixture("fixture_05", "club_a", "club_d", 3),
		_fixture("fixture_06", "club_b", "club_c", 3),
	]


func _fixture(id: String, home: String, away: String, round_number: int,
		date: Variant = null, competition: Variant = "league",
		stage: Variant = "regular", group: Variant = null) -> Fixture:
	var fixture = Fixture.new()
	fixture.fixture_id = id
	fixture.season_id = "season_a"
	fixture.competition_id = competition
	fixture.stage_id = stage
	fixture.group_id = group
	fixture.home_club_id = home
	fixture.away_club_id = away
	fixture.round_number = round_number
	fixture.scheduled_date = date
	fixture.metadata = {"synthetic": true}
	return fixture


func _copy_fixtures(source: Array[Fixture]) -> Array[Fixture]:
	var copies: Array[Fixture] = []
	for fixture in source:
		copies.append(_fixture(fixture.fixture_id, fixture.home_club_id,
			fixture.away_club_id, fixture.round_number, fixture.scheduled_date,
			fixture.competition_id, fixture.stage_id, fixture.group_id))
	return copies


func _rules(tiebreakers: Array) -> Rules:
	var rules = Rules.new()
	rules.season_id = "season_a"
	rules.competition_id = "league"
	rules.points_win = 3
	rules.points_draw = 1
	rules.points_loss = 0
	rules.team_count = 4
	rules.round_count = 3
	rules.tiebreakers = tiebreakers.duplicate()
	rules.competition_format = {"kind": "round_robin", "legs": 1,
		"head_to_head_policy": "single_pass"}
	return rules


func _selection() -> Dictionary:
	return {"season_id": "season_a", "competition_id": "league",
		"stage_id": "regular", "group_id": null}


func _result(fixture_id: String, home: int, away: int) -> Result:
	var result = Result.new()
	result.fixture_id = fixture_id
	result.season_id = "season_a"
	result.home_goals = home
	result.away_goals = away
	result.status = Result.Status.FINAL
	return result


func _tree_rows(tree: Tree) -> Array:
	var rows: Array = []
	var root_item = tree.get_root()
	if root_item == null:
		return rows
	var item = root_item.get_first_child()
	while item != null:
		var row: Array[String] = []
		for column in tree.columns:
			row.append(item.get_text(column))
		rows.append(row)
		item = item.get_next()
	return rows


func _match_texts(view) -> Array[String]:
	var texts: Array[String] = []
	for child in view.match_list.get_children():
		texts.append(_node_text(child))
	return texts


func _node_text(node: Node) -> String:
	var parts: Array[String] = []
	if node is Label:
		parts.append(node.text)
	for child in node.get_children():
		parts.append(_node_text(child))
	return " ".join(parts)


func _match_fixture_ids(view) -> Array[String]:
	var ids: Array[String] = []
	for child in view.match_list.get_children():
		if child.has_meta("fixture_id"):
			ids.append(child.get_meta("fixture_id"))
	return ids


func _visual_matches_rows(visual: Array, sporting: Array) -> bool:
	if visual.size() != sporting.size():
		return false
	for index in sporting.size():
		var row = sporting[index]
		var expected = [row.position, row.club_id, row.played, row.wins, row.draws,
			row.losses, row.goals_for, row.goals_against, row.goal_difference, row.points]
		for column in expected.size():
			if visual[index][column] != str(expected[column]):
				return false
	return true


func _fixture_snapshot(fixtures: Array) -> Array:
	var snapshot: Array = []
	for fixture in fixtures:
		snapshot.append([fixture.fixture_id, fixture.season_id, fixture.competition_id,
			fixture.stage_id, fixture.group_id, fixture.home_club_id, fixture.away_club_id,
			fixture.round_number, fixture.scheduled_date, fixture.metadata.duplicate(true)])
	return snapshot


func _controller_snapshot(controller: Controller) -> Dictionary:
	return {"standings": controller.get_standings().duplicate(true),
		"results": _result_snapshot(controller.get_results().data.results)}


func _result_snapshot(results: Array) -> Array:
	var snapshot: Array = []
	for result in results:
		snapshot.append([result.fixture_id, result.season_id, result.home_goals,
			result.away_goals, result.status])
	return snapshot


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
