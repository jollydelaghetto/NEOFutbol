class_name ManagerTactics
extends Control

const Controller = preload("res://game/scripts/services/season_controller.gd")

const SEASON_ID = "1982-83"
const DEFAULT_FORMATION_ID = "4-4-2"
const FORMATION_IDS: Array[String] = ["4-4-2", "4-3-3", "4-2-3-1"]

signal back_requested

@onready var season_label: Label = %SeasonLabel
@onready var club_label: Label = %ClubLabel
@onready var warning_label: Label = %WarningLabel
@onready var formation_selector: OptionButton = %FormationSelector
@onready var formation_label: Label = %FormationLabel
@onready var directed_club_value: Label = %DirectedClubValue
@onready var formation_value: Label = %FormationValue
@onready var assigned_value: Label = %AssignedValue
@onready var state_value: Label = %StateValue
@onready var simulation_notice: Label = %SimulationNotice
@onready var info_scroll: ScrollContainer = %InfoScroll
@onready var selection_prompt: Label = %SelectionPrompt
@onready var selection_details: VBoxContainer = %SelectionDetails
@onready var selected_label_value: Label = %SelectedLabelValue
@onready var selected_slot_value: Label = %SelectedSlotValue
@onready var selected_line_value: Label = %SelectedLineValue
@onready var selected_status_value: Label = %SelectedStatusValue
@onready var field: TacticsField = %TacticsField
@onready var error_label: Label = %ErrorLabel
@onready var back_button: Button = %BackButton

var _selection: Dictionary = {}
var _presentation: Dictionary = {}
var _club_id := ""
var _formation_id := DEFAULT_FORMATION_ID
var _selection_render_revision := 0


func _ready() -> void:
	_populate_formation_selector()
	formation_selector.item_selected.connect(_on_formation_selected)
	field.selection_changed.connect(_on_position_selection_changed)
	back_button.pressed.connect(func(): back_requested.emit())
	formation_selector.focus_next = formation_selector.get_path_to(field)
	formation_selector.focus_previous = formation_selector.get_path_to(back_button)
	back_button.focus_next = back_button.get_path_to(formation_selector)
	back_button.focus_previous = back_button.get_path_to(field)
	field.focus_next = field.get_path_to(back_button)
	field.focus_previous = field.get_path_to(formation_selector)
	_render_selected_position(null)


## Configura una representación visual de solo lectura. La formación y sus
## posiciones son locales a la interfaz: no se escriben en el controlador.
func configure(controller: Controller, selection: Dictionary,
		presentation: Dictionary, club_id: String) -> Dictionary:
	if not is_node_ready():
		return _failure("view_not_ready", "La pantalla de Tácticas todavía no está preparada.")
	if controller == null:
		return _show_failure("invalid_controller", "Falta el controlador deportivo.")
	if selection.get("season_id") != SEASON_ID:
		return _show_failure(
			"unsupported_development_context",
			"Este prototipo solo admite la temporada técnica 1982-83."
		)
	if club_id.is_empty():
		return _show_failure("missing_assigned_club", "Debe existir un club seleccionado.")
	var context = controller.get_session_context()
	if not context.ok:
		return _show_result(context)
	if context.data.selection != selection:
		return _show_failure(
			"controller_selection_mismatch",
			"La selección no coincide con la sesión del controlador."
		)
	var standings = controller.get_standings()
	if not standings.ok:
		return _show_result(standings)
	if not standings.data.rows.any(func(row): return row.club_id == club_id):
		return _show_failure(
			"assigned_club_unavailable", "El club seleccionado no pertenece a la sesión."
		)
	var club_names = presentation.get("club_names")
	if not club_names is Dictionary or not _valid_display_name(club_names.get(club_id)):
		return _show_failure(
			"missing_club_display_name",
			"El club seleccionado no tiene un nombre visible validado."
		)

	_selection = selection.duplicate(true)
	_presentation = presentation.duplicate(true)
	_club_id = club_id
	_render()
	field.clear_selection()
	var selected = select_formation(DEFAULT_FORMATION_ID)
	if not selected.ok:
		return selected
	_clear_error()
	return {
		"ok": true,
		"data": {
			"season_id": _selection.season_id,
			"club_id": _club_id,
			"formation": _formation_id,
			"assigned_players": 0,
			"position_count": field.get_reference_positions().size(),
		},
		"errors": [],
	}


func focus_initial_control() -> void:
	formation_selector.grab_focus()


func get_context() -> Dictionary:
	return {
		"selection": _selection.duplicate(true),
		"club_id": _club_id,
		"formation": _formation_id,
		"assigned_players": 0,
	}


func _render() -> void:
	var club_name: String = _presentation.club_names[_club_id]
	season_label.text = "Temporada técnica %s" % _selection.season_id
	club_label.text = "Club dirigido: %s" % club_name
	warning_label.text = "MODO DESARROLLO — DATOS SINTÉTICOS"
	directed_club_value.text = club_name
	assigned_value.text = "0"
	state_value.text = "Prototipo de visualización táctica"
	simulation_notice.text = "La formación no afecta a la simulación deportiva"


## Cambia únicamente la referencia visual. Una solicitud inválida no modifica
## el campo, el selector ni el último contexto válido.
func select_formation(formation_id: String) -> Dictionary:
	var selected = field.set_formation(formation_id)
	if not selected.ok:
		return _show_result(selected)
	_formation_id = formation_id
	_sync_selector()
	formation_label.text = (
		"Formación de referencia %s · sin jugadores asignados" % _formation_id
	)
	formation_value.text = _formation_id
	_render_selected_position(field.get_selected_position())
	_clear_error()
	return {
		"ok": true,
		"data": {
			"formation_id": _formation_id,
			"position_count": field.get_reference_positions().size(),
			"assigned_players": 0,
		},
		"errors": [],
	}


func _populate_formation_selector() -> void:
	formation_selector.clear()
	for formation_id in FORMATION_IDS:
		formation_selector.add_item(formation_id)
		formation_selector.set_item_metadata(
			formation_selector.item_count - 1, formation_id
		)
	formation_selector.select(0)


func _sync_selector() -> void:
	for index in formation_selector.item_count:
		if formation_selector.get_item_metadata(index) == _formation_id:
			formation_selector.select(index)
			return


func _on_formation_selected(index: int) -> void:
	if index < 0 or index >= formation_selector.item_count:
		return
	select_formation(formation_selector.get_item_metadata(index))


func _on_position_selection_changed(position: Variant) -> void:
	_render_selected_position(position)


func _render_selected_position(position: Variant) -> void:
	_selection_render_revision += 1
	var revision = _selection_render_revision
	if position == null:
		selection_prompt.text = "Selecciona una posición del campo"
		selection_prompt.visible = true
		selection_details.visible = false
		_reset_info_scroll(revision)
		return
	selection_prompt.text = "Posición seleccionada"
	selection_prompt.visible = true
	selection_details.visible = true
	selected_label_value.text = position.label
	selected_slot_value.text = position.slot_id
	selected_line_value.text = _line_name(position.role)
	selected_status_value.text = "Sin jugador asignado"
	_keep_selection_details_visible(revision)


func _keep_selection_details_visible(revision: int) -> void:
	# La visibilidad cambia el tamaño mínimo del contenido. Esperar al siguiente
	# frame permite que los contenedores actualicen el límite de desplazamiento.
	await get_tree().process_frame
	if revision == _selection_render_revision and is_instance_valid(selection_details):
		# Los detalles son el último bloque del contenido. El valor se limita al
		# máximo real, dejando el bloque completo dentro del área visible.
		info_scroll.scroll_vertical = ceili(info_scroll.get_v_scroll_bar().max_value)


func _reset_info_scroll(revision: int) -> void:
	call_deferred("_apply_info_scroll_reset", revision)


func _apply_info_scroll_reset(revision: int) -> void:
	if revision == _selection_render_revision and is_instance_valid(info_scroll):
		info_scroll.scroll_vertical = 0


func _line_name(role: String) -> String:
	match role:
		"goalkeeper":
			return "Portería"
		"defender":
			return "Defensa"
		"midfielder":
			return "Centro del campo"
		"forward":
			return "Delantera"
	return ""


func _valid_display_name(value: Variant) -> bool:
	if not value is String or value.strip_edges().is_empty():
		return false
	for index in value.length():
		var codepoint = value.unicode_at(index)
		if codepoint < 32 or (codepoint >= 127 and codepoint <= 159):
			return false
	return true


func _show_result(result: Dictionary) -> Dictionary:
	if not result.ok:
		error_label.text = "%s: %s" % [
			result.errors[0].get("code", "tactics_configuration_failed"),
			result.errors[0].get("message", "No se pudo configurar Tácticas."),
		]
		error_label.visible = true
	return result


func _show_failure(code: String, message: String) -> Dictionary:
	var result = _failure(code, message)
	error_label.text = "%s: %s" % [code, message]
	error_label.visible = true
	return result


func _clear_error() -> void:
	error_label.text = ""
	error_label.visible = false


func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "data": null, "errors": [{"code": code, "message": message}]}
