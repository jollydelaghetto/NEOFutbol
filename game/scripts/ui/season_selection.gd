class_name SeasonSelection
extends Control

signal back_requested
signal season_view_requested(season_id: String)

const CatalogService = preload("res://game/scripts/services/season_catalog_service.gd")

@export var catalog_root_path := CatalogService.DEFAULT_ROOT

@onready var season_list: ItemList = %SeasonList
@onready var status_label: Label = %StatusLabel
@onready var details_label: Label = %DetailsLabel
@onready var consult_button: Button = %ConsultButton
@onready var back_button: Button = %BackButton
@onready var error_label: Label = %ErrorLabel

var catalog_service = CatalogService.new()
var _seasons: Array[Dictionary] = []
var _request_in_progress := false


func _ready() -> void:
	season_list.item_selected.connect(_on_season_selected)
	consult_button.pressed.connect(_on_consult_pressed)
	back_button.pressed.connect(_on_back_pressed)
	refresh_catalog()


## Vuelve a consultar el catálogo conservando la temporada seleccionada si
## sigue dentro del horizonte. Un fallo se muestra sin bloquear el retorno.
func refresh_catalog() -> Dictionary:
	var previous_id = get_selected_season_id()
	season_list.clear()
	_seasons.clear()
	var result = catalog_service.get_catalog(catalog_root_path)
	if not result.ok:
		_show_catalog_error(result.errors)
		return result
	if not result.data is Dictionary or not result.data.get("seasons") is Array:
		var invalid = _failure("invalid_catalog", "El catálogo no contiene una lista de temporadas.")
		_show_catalog_error(invalid.errors)
		return invalid

	for season in result.data.seasons:
		if not season is Dictionary:
			continue
		_seasons.append(season.duplicate(true))
		var display_status = _display_status(season)
		var index = season_list.add_item("%s · %s" % [season.label, display_status])
		season_list.set_item_metadata(index, season.season_id)
		season_list.set_item_tooltip(index, display_status)
	_clear_error()
	if _seasons.is_empty():
		status_label.text = "No hay temporadas en el catálogo."
		details_label.text = ""
		consult_button.disabled = true
		return result
	var selected_index = 0
	for index in _seasons.size():
		if _seasons[index].season_id == previous_id:
			selected_index = index
			break
	season_list.select(selected_index)
	season_list.ensure_current_is_visible()
	_update_selected_state(selected_index)
	return result


func get_selected_season_id() -> String:
	var selected = season_list.get_selected_items() if is_instance_valid(season_list) else []
	if selected.is_empty():
		return ""
	var value = season_list.get_item_metadata(selected[0])
	return value if value is String else ""


func _on_season_selected(index: int) -> void:
	_update_selected_state(index)


func _on_consult_pressed() -> void:
	if _request_in_progress:
		return
	var selected = season_list.get_selected_items()
	if selected.is_empty():
		return
	var index = selected[0]
	if index < 0 or index >= _seasons.size() or not _seasons[index].playable:
		return
	season_view_requested.emit(_seasons[index].season_id)


func _on_back_pressed() -> void:
	back_requested.emit()


func select_season(season_id: String) -> bool:
	for index in _seasons.size():
		if _seasons[index].season_id == season_id:
			season_list.select(index)
			season_list.ensure_current_is_visible()
			_update_selected_state(index)
			return true
	return false


func set_request_in_progress(in_progress: bool) -> void:
	_request_in_progress = in_progress
	if in_progress:
		consult_button.disabled = true
		return
	var selected = season_list.get_selected_items()
	consult_button.disabled = selected.is_empty() \
		or not _seasons[selected[0]].playable


func show_request_errors(errors: Array) -> void:
	var messages: Array[String] = []
	for error in errors:
		if error is Dictionary:
			messages.append("%s: %s" % [
				error.get("code", "error"), error.get("message", "")
			])
	error_label.text = "\n".join(messages) if not messages.is_empty() else "Error desconocido."
	error_label.visible = true


func _update_selected_state(index: int) -> void:
	if index < 0 or index >= _seasons.size():
		status_label.text = "Seleccione una temporada."
		details_label.text = ""
		consult_button.disabled = true
		return
	var season = _seasons[index]
	status_label.text = "%s · %s" % [season.label, _display_status(season)]
	consult_button.disabled = not season.playable
	if not season.missing_content.is_empty():
		details_label.text = "Contenido pendiente: %s" % ", ".join(season.missing_content)
	elif not season.diagnostics.is_empty():
		var diagnostic = season.diagnostics[0]
		details_label.text = diagnostic.get("message", "El pack requiere revisión.")
	elif season.playable:
		details_label.text = (
			"Puede consultar la clasificación y el calendario. "
			+ "Esta opción no inicia una carrera de entrenador."
		)
	else:
		details_label.text = "El pack está validado, pero aún no reúne los datos mínimos para jugar."


func _display_status(season: Dictionary) -> String:
	if season.get("playable", false):
		return "Datos deportivos disponibles · Consulta habilitada"
	return season.get("status_label", "Estado desconocido")


func _show_catalog_error(errors: Array) -> void:
	_seasons.clear()
	status_label.text = "No se pudo consultar el catálogo."
	details_label.text = "Puede volver al menú y seguir usando la demostración."
	consult_button.disabled = true
	var message = "Error desconocido"
	if not errors.is_empty() and errors[0] is Dictionary:
		message = errors[0].get("message", message)
	error_label.text = message
	error_label.visible = true


func _clear_error() -> void:
	error_label.text = ""
	error_label.visible = false


func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "data": null, "errors": [{"code": code, "message": message}]}
