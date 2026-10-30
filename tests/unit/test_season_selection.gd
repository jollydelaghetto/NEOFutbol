extends SceneTree

const SelectionScene = preload("res://game/scenes/season_selection.tscn")
const SelectionScript = preload("res://game/scripts/ui/season_selection.gd")

class FakeCatalog:
	extends RefCounted
	var result: Dictionary

	func _init(value: Dictionary) -> void:
		result = value

	func get_catalog(_root_path: String) -> Dictionary:
		return result.duplicate(true)


var failures: Array[String] = []
var checks = 0
var started_ids: Array[String] = []
var back_count = 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var source = _catalog_result()
	var view = SelectionScene.instantiate()
	view.catalog_service = FakeCatalog.new(source)
	root.add_child(view)
	await process_frame

	_check(view.get_script() == SelectionScript, "escena usa SeasonSelection")
	var list: ItemList = view.get_node("%SeasonList")
	var start: Button = view.get_node("%StartButton")
	var back: Button = view.get_node("%BackButton")
	var status: Label = view.get_node("%StatusLabel")
	var details: Label = view.get_node("%DetailsLabel")
	var error: Label = view.get_node("%ErrorLabel")
	_check(list.item_count == 29, "muestra exactamente 29 temporadas")
	_check(list.get_item_text(0).begins_with("1982-83")
		and list.get_item_text(28).begins_with("2010-11"),
		"orden cronológico visible")
	_check(list.get_item_metadata(17) == "1999-00", "metadatos de identidad exactos")
	_check(list.focus_mode == Control.FOCUS_ALL, "lista accesible por teclado")
	_check(view.get_selected_season_id() == "1982-83", "selección inicial determinista")
	_check(start.disabled and status.text.contains("Pack incompleto"),
		"temporada incompleta no iniciable")
	_check(details.text.contains("fixtures.json"), "contenido pendiente explicado")

	view.season_start_requested.connect(_on_started)
	list.select(1)
	list.item_selected.emit(1)
	_check(view.get_selected_season_id() == "1983-84", "selección mediante índice de ItemList")
	_check(not start.disabled and status.text.contains("Temporada disponible"),
		"pack jugable habilita el inicio")
	start.pressed.emit()
	_check(started_ids == ["1983-84"], "inicio emite la temporada seleccionada")

	# La vista conserva copias y la selección al refrescar.
	source.data.seasons[1].label = "mutado fuera"
	_check(list.get_item_text(1).begins_with("1983-84"),
		"catálogo mostrado no comparte datos externos")
	var refreshed = view.refresh_catalog()
	_check(refreshed.ok and view.get_selected_season_id() == "1983-84",
		"refresh conserva la selección")
	_check(list.item_count == 29, "refresh no duplica filas")

	view.back_requested.connect(_on_back)
	back.pressed.emit()
	_check(back_count == 1, "retorno al menú emitido")

	# Los fallos quedan en la propia vista y no impiden volver.
	view.catalog_service = FakeCatalog.new({
		"ok": false, "data": null,
		"errors": [{"code": "catalog_failure", "message": "fallo sintético"}],
	})
	var failed = view.refresh_catalog()
	_check(not failed.ok and error.visible and error.text == "fallo sintético",
		"error de catálogo visible y no modal")
	_check(list.item_count == 0 and start.disabled, "error no deja una acción obsoleta")
	back.pressed.emit()
	_check(back_count == 2, "retorno disponible después de un error")
	view.queue_free()
	await process_frame

	# El repositorio real expone el pack parcial sin declararlo disponible.
	var real_view = SelectionScene.instantiate()
	root.add_child(real_view)
	await process_frame
	var real_list: ItemList = real_view.get_node("%SeasonList")
	_check(real_list.item_count == 29, "catálogo real conserva el horizonte")
	_check(real_view.get_selected_season_id() == "1982-83"
		and real_view.get_node("%StartButton").disabled,
		"pack real incompleto permanece deshabilitado")
	_check(real_view.get_node("%StatusLabel").text.contains("Pack incompleto"),
		"estado real comunicado")
	real_view.queue_free()
	await process_frame
	_finish()


func _catalog_result() -> Dictionary:
	var seasons: Array[Dictionary] = []
	for start_year in range(1982, 2011):
		var season_id = "%d-%02d" % [start_year, (start_year + 1) % 100]
		var playable = start_year == 1983
		seasons.append({
			"season_id": season_id,
			"label": season_id,
			"in_project_horizon": true,
			"data_discovered": start_year <= 1983,
			"data_validated": playable,
			"validation_scope": "structural_and_referential" if playable else "none",
			"provenance_declared": playable,
			"playable": playable,
			"status_code": "playable" if playable else "incomplete",
			"status_label": "Temporada disponible" if playable else "Pack incompleto",
			"pack_path": "/tmp/%s" % season_id,
			"missing_content": [] if playable else ["fixtures.json"],
			"diagnostics": [],
		})
	return {
		"ok": true,
		"data": {"seasons": seasons, "root_path": "/tmp", "horizon": {"count": 29}},
		"errors": [],
	}


func _on_started(season_id: String) -> void:
	started_ids.append(season_id)


func _on_back() -> void:
	back_count += 1


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
