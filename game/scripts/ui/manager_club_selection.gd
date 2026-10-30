class_name ManagerClubSelection
extends Control

const Controller = preload("res://game/scripts/services/season_controller.gd")

const SEASON_ID = "1982-83"

signal club_confirmed(club_id: String)
signal back_requested

@onready var warning_label: Label = %WarningLabel
@onready var club_selector: OptionButton = %ClubSelector
@onready var continue_button: Button = %ContinueButton
@onready var back_button: Button = %BackButton
@onready var error_label: Label = %ErrorLabel

var _club_ids: Array[String] = []
var _request_in_progress := false


func _ready() -> void:
	club_selector.item_selected.connect(_on_club_selected)
	club_selector.gui_input.connect(_on_club_selector_input)
	continue_button.pressed.connect(_on_continue_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_configure_focus_navigation()
	continue_button.disabled = true


## Construye las opciones desde la clasificación pública de una sesión ya
## validada. Los nombres proceden exclusivamente de presentation.club_names.
func configure(controller: Controller, selection: Dictionary,
		presentation: Dictionary) -> Dictionary:
	if not is_node_ready():
		return _failure("view_not_ready", "El selector todavía no está preparado.")
	if controller == null:
		return _show_failure("invalid_controller", "Falta el controlador deportivo.")
	if selection.get("season_id") != SEASON_ID:
		return _show_failure(
			"unsupported_development_season",
			"El prototipo solo admite la temporada técnica 1982-83."
		)
	var context = controller.get_session_context()
	if not context.ok:
		return _show_result(context)
	if context.data.selection != selection:
		return _show_failure(
			"controller_selection_mismatch",
			"La selección no coincide con la sesión del controlador."
		)
	var names = presentation.get("club_names")
	if not names is Dictionary:
		return _show_failure(
			"invalid_club_names", "Falta el mapeo validado de nombres de clubes."
		)
	var standings = controller.get_standings()
	if not standings.ok:
		return _show_result(standings)
	var options: Array[Dictionary] = []
	var seen: Dictionary = {}
	for row in standings.data.rows:
		var club_id = row.get("club_id")
		if not club_id is String or club_id.is_empty() or seen.has(club_id):
			return _show_failure(
				"invalid_session_club", "La sesión contiene un identificador de club inválido."
			)
		var display_name = names.get(club_id)
		if not display_name is String or display_name.strip_edges().is_empty():
			return _show_failure(
				"missing_club_display_name",
				"Falta el nombre visible validado para %s." % club_id
			)
		seen[club_id] = true
		options.append({"club_id": club_id, "display_name": display_name})
	options.sort_custom(func(left, right):
		if left.display_name == right.display_name:
			return left.club_id < right.club_id
		return left.display_name < right.display_name
	)
	if options.is_empty():
		return _show_failure("empty_club_selection", "La sesión no contiene clubes seleccionables.")

	club_selector.clear()
	_club_ids.clear()
	for option in options:
		var index = club_selector.item_count
		club_selector.add_item(option.display_name)
		club_selector.set_item_metadata(index, option.club_id)
		_club_ids.append(option.club_id)
	club_selector.select(0)
	continue_button.disabled = false
	warning_label.text = "MODO DESARROLLO — DATOS SINTÉTICOS"
	_clear_error()
	return {
		"ok": true,
		"data": {
			"club_ids": _club_ids.duplicate(),
			"selected_club_id": get_selected_club_id(),
		},
		"errors": [],
	}


func get_selected_club_id() -> String:
	var index = club_selector.selected
	if index < 0 or index >= club_selector.item_count:
		return ""
	var club_id = club_selector.get_item_metadata(index)
	return club_id if club_id is String else ""


func get_club_ids() -> Array[String]:
	return _club_ids.duplicate()


func select_club(club_id: String) -> bool:
	for index in club_selector.item_count:
		if club_selector.get_item_metadata(index) == club_id:
			club_selector.select(index)
			_on_club_selected(index)
			return true
	return false


func focus_initial_control() -> void:
	club_selector.grab_focus()


func set_request_in_progress(in_progress: bool) -> void:
	_request_in_progress = in_progress
	club_selector.disabled = in_progress
	continue_button.disabled = in_progress or get_selected_club_id().is_empty()
	back_button.disabled = in_progress


func show_request_errors(errors: Array) -> void:
	if errors.is_empty():
		return
	var first = errors[0]
	error_label.text = "%s: %s" % [
		first.get("code", "club_selection_error"),
		first.get("message", "No se pudo abrir el Despacho."),
	]
	error_label.visible = true
	set_request_in_progress(false)
	focus_initial_control()


func _configure_focus_navigation() -> void:
	club_selector.focus_next = club_selector.get_path_to(continue_button)
	club_selector.focus_previous = club_selector.get_path_to(back_button)
	continue_button.focus_next = continue_button.get_path_to(back_button)
	continue_button.focus_previous = continue_button.get_path_to(club_selector)
	back_button.focus_next = back_button.get_path_to(club_selector)
	back_button.focus_previous = back_button.get_path_to(continue_button)


func _on_club_selected(_index: int) -> void:
	continue_button.disabled = _request_in_progress or get_selected_club_id().is_empty()
	_clear_error()


func _on_club_selector_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo \
			or club_selector.item_count == 0:
		return
	var direction = 0
	if event.keycode == KEY_DOWN:
		direction = 1
	elif event.keycode == KEY_UP:
		direction = -1
	if direction == 0:
		return
	var next_index = wrapi(club_selector.selected + direction, 0, club_selector.item_count)
	club_selector.select(next_index)
	_on_club_selected(next_index)
	club_selector.accept_event()


func _on_continue_pressed() -> void:
	if _request_in_progress:
		return
	var club_id = get_selected_club_id()
	if club_id.is_empty() or club_id not in _club_ids:
		_show_failure("invalid_club_selection", "Seleccione un club válido.")
		return
	set_request_in_progress(true)
	club_confirmed.emit(club_id)


func _on_back_pressed() -> void:
	if not _request_in_progress:
		back_requested.emit()


func _show_result(result: Dictionary) -> Dictionary:
	if not result.ok:
		show_request_errors(result.errors)
	return result


func _show_failure(code: String, message: String) -> Dictionary:
	var result = _failure(code, message)
	show_request_errors(result.errors)
	return result


func _clear_error() -> void:
	error_label.text = ""
	error_label.visible = false


func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "data": null, "errors": [{"code": code, "message": message}]}
