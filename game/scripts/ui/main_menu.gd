class_name MainMenu
extends Control

const DEFAULT_SEASON_SCENE = preload("res://game/scenes/season_overview.tscn")

@export var season_scene: PackedScene = DEFAULT_SEASON_SCENE

@onready var menu_presentation: CenterContainer = %MenuPresentation
@onready var season_host: MarginContainer = %SeasonHost
@onready var demo_button: Button = %DemoButton
@onready var back_button: Button = %BackButton
@onready var error_label: Label = %ErrorLabel

var _season_view: Control = null
var _transition_in_progress := false


func _ready() -> void:
	demo_button.pressed.connect(_on_demo_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)
	_show_menu_state()


## Instancia la demostración dentro del contenedor local. Las llamadas repetidas
## reutilizan la vista activa y nunca crean un segundo SeasonOverview.
func show_season_demo() -> Dictionary:
	if _transition_in_progress:
		return _failure("navigation_in_progress", "Ya hay una navegación en curso.")
	var active_view = _active_season_view()
	if active_view != null:
		return {"ok": true, "data": {"season_view": active_view}, "errors": []}
	if season_scene == null:
		return _show_failure(
			"season_scene_unavailable",
			"No se pudo abrir la demostración de temporada."
		)

	_transition_in_progress = true
	demo_button.disabled = true
	var instance = season_scene.instantiate()
	if not instance is Control:
		if instance != null:
			instance.free()
		_transition_in_progress = false
		demo_button.disabled = false
		return _show_failure(
			"invalid_season_scene",
			"La demostración no contiene una interfaz válida."
		)
	_season_view = instance
	season_host.add_child(_season_view)
	_season_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu_presentation.visible = false
	season_host.visible = true
	back_button.visible = true
	_clear_error()
	_transition_in_progress = false
	return {"ok": true, "data": {"season_view": _season_view}, "errors": []}


## Retira inmediatamente la vista del contenedor y difiere su liberación al
## final del frame, permitiendo abrir una demostración nueva sin referencias.
func show_main_menu() -> Dictionary:
	if _transition_in_progress:
		return _failure("navigation_in_progress", "Ya hay una navegación en curso.")
	_transition_in_progress = true
	var active_view = _active_season_view()
	if active_view != null:
		season_host.remove_child(active_view)
		active_view.queue_free()
	_season_view = null
	_show_menu_state()
	_clear_error()
	_transition_in_progress = false
	return {"ok": true, "data": null, "errors": []}


func _on_demo_button_pressed() -> void:
	show_season_demo()


func _on_back_button_pressed() -> void:
	show_main_menu()


func _active_season_view() -> Control:
	if _season_view == null or not is_instance_valid(_season_view):
		_season_view = null
		return null
	return _season_view


func _show_menu_state() -> void:
	menu_presentation.visible = true
	season_host.visible = false
	back_button.visible = false
	demo_button.disabled = false


func _show_failure(code: String, message: String) -> Dictionary:
	_show_menu_state()
	error_label.text = "%s: %s" % [code, message]
	error_label.visible = true
	return _failure(code, message)


func _clear_error() -> void:
	error_label.text = ""
	error_label.visible = false


func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "data": null, "errors": [{"code": code, "message": message}]}
