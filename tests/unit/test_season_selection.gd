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

	_check(not view.has_signal("season_start_requested"),
		"no publica una señal de inicio sin consumidor operativo")
	list.select(1)
	list.item_selected.emit(1)
	_check(view.get_selected_season_id() == "1983-84", "selección mediante índice de ItemList")
	_check(start.disabled and status.text.contains("Datos deportivos disponibles"),
		"pack jugable conserva su aptitud sin habilitar el inicio")
	_check(view._seasons[1].playable and source.data.seasons[1].playable,
		"la interfaz no altera la disponibilidad deportiva del catálogo")
	_check(details.text.contains("datos deportivos son aptos")
		and details.text.contains("todavía no está implementado"),
		"pack jugable explica que el flujo de inicio está pendiente")
	start.pressed.emit()
	_check(start.disabled, "una activación programática no habilita el botón")

	list.select(2)
	list.item_selected.emit(2)
	_check(view.get_selected_season_id() == "1984-85"
		and start.disabled and status.text.contains("Datos validados"),
		"pack validado pero no jugable permanece bloqueado")
	_check(details.text.contains("no reúne los datos mínimos"),
		"pack no jugable mantiene su explicación")

	list.select(3)
	list.item_selected.emit(3)
	_check(start.disabled and status.text.contains("Datos no disponibles"),
		"temporada no descubierta se distingue y no permite iniciar")

	# La vista conserva copias y la selección al refrescar.
	list.select(1)
	list.item_selected.emit(1)
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
		var validated_not_playable = start_year == 1984
		var incomplete = start_year == 1982
		var status_code = "not_discovered"
		var status_label = "Datos no disponibles"
		if incomplete:
			status_code = "incomplete"
			status_label = "Pack incompleto"
		elif playable:
			status_code = "playable"
			status_label = "Temporada disponible"
		elif validated_not_playable:
			status_code = "validated_not_playable"
			status_label = "Datos validados; inicio no disponible"
		seasons.append({
			"season_id": season_id,
			"label": season_id,
			"in_project_horizon": true,
			"data_discovered": incomplete or playable or validated_not_playable,
			"data_validated": playable or validated_not_playable,
			"validation_scope": (
				"structural_and_referential" if playable or validated_not_playable else "none"
			),
			"provenance_declared": playable or validated_not_playable,
			"playable": playable,
			"status_code": status_code,
			"status_label": status_label,
			"pack_path": "/tmp/%s" % season_id,
			"missing_content": ["fixtures.json"] if incomplete else [],
			"diagnostics": [],
		})
	return {
		"ok": true,
		"data": {"seasons": seasons, "root_path": "/tmp", "horizon": {"count": 29}},
		"errors": [],
	}


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
