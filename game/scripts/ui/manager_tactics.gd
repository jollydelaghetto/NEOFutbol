class_name ManagerTactics
extends Control

const Controller = preload("res://game/scripts/services/season_controller.gd")

const SEASON_ID = "1982-83"
const FORMATION = "4-4-2"

signal back_requested

@onready var season_label: Label = %SeasonLabel
@onready var club_label: Label = %ClubLabel
@onready var warning_label: Label = %WarningLabel
@onready var formation_label: Label = %FormationLabel
@onready var directed_club_value: Label = %DirectedClubValue
@onready var formation_value: Label = %FormationValue
@onready var assigned_value: Label = %AssignedValue
@onready var state_value: Label = %StateValue
@onready var simulation_notice: Label = %SimulationNotice
@onready var field: TacticsField = %TacticsField
@onready var error_label: Label = %ErrorLabel
@onready var back_button: Button = %BackButton

var _selection: Dictionary = {}
var _presentation: Dictionary = {}
var _club_id := ""


func _ready() -> void:
	back_button.pressed.connect(func(): back_requested.emit())
	back_button.focus_next = back_button.get_path_to(back_button)
	back_button.focus_previous = back_button.get_path_to(back_button)


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
	_clear_error()
	return {
		"ok": true,
		"data": {
			"season_id": _selection.season_id,
			"club_id": _club_id,
			"formation": FORMATION,
			"assigned_players": 0,
			"position_count": field.get_reference_positions().size(),
		},
		"errors": [],
	}


func focus_initial_control() -> void:
	back_button.grab_focus()


func get_context() -> Dictionary:
	return {
		"selection": _selection.duplicate(true),
		"club_id": _club_id,
		"formation": FORMATION,
		"assigned_players": 0,
	}


func _render() -> void:
	var club_name: String = _presentation.club_names[_club_id]
	season_label.text = "Temporada técnica %s" % _selection.season_id
	club_label.text = "Club dirigido: %s" % club_name
	warning_label.text = "MODO DESARROLLO — DATOS SINTÉTICOS"
	formation_label.text = "Formación de referencia 4-4-2 · sin jugadores asignados"
	directed_club_value.text = club_name
	formation_value.text = FORMATION
	assigned_value.text = "0"
	state_value.text = "Prototipo de visualización táctica"
	simulation_notice.text = "La formación no afecta a la simulación deportiva"
	field.queue_redraw()


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
