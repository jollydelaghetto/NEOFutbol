class_name MainMenu
extends Control

const DEFAULT_SEASON_SCENE = preload("res://game/scenes/season_overview.tscn")
const DEFAULT_SELECTION_SCENE = preload("res://game/scenes/season_selection.tscn")
const SessionLoader = preload("res://game/scripts/services/season_session_loader.gd")
const DEFAULT_SEASON_ROOT = "res://data/seasons"
const DEVELOPMENT_SEASON_ROOT = "res://data/dev/seasons"
const DEVELOPMENT_ARGUMENT = "--dev-season-pack"
const DEVELOPMENT_WARNING = "MODO DESARROLLO — DATOS SINTÉTICOS"
const DEVELOPMENT_SEASON_ID = "1982-83"
const DEVELOPMENT_REQUIRED_FILES = [
	"manifest.json", "rules.json", "clubs.json", "players.json", "fixtures.json",
]

@export var season_scene: PackedScene = DEFAULT_SEASON_SCENE
@export var selection_scene: PackedScene = DEFAULT_SELECTION_SCENE
@export var season_root_path := DEFAULT_SEASON_ROOT

@onready var menu_presentation: CenterContainer = %MenuPresentation
@onready var season_host: MarginContainer = %SeasonHost
@onready var demo_button: Button = %DemoButton
@onready var selection_button: Button = %SelectionButton
@onready var back_button: Button = %BackButton
@onready var error_label: Label = %ErrorLabel
@onready var development_mode_banner: Label = %DevelopmentModeBanner

var _season_view: Control = null
var _selection_view: Control = null
var _transition_in_progress := false
var _historical_view_active := false
var _historical_season_id := ""
var _development_season_pack_active := false
var _development_pack_request_rejected := false
var development_season_root_path := DEVELOPMENT_SEASON_ROOT
var command_line_user_args: PackedStringArray = OS.get_cmdline_user_args()
var session_loader = SessionLoader.new()


func _ready() -> void:
	_configure_runtime_mode(command_line_user_args)
	demo_button.pressed.connect(_on_demo_button_pressed)
	selection_button.pressed.connect(_on_selection_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)
	_configure_focus_navigation()
	_show_menu_state()


## Instancia la demostración dentro del contenedor local. Las llamadas repetidas
## reutilizan la vista activa y nunca crean un segundo SeasonOverview.
func show_season_demo() -> Dictionary:
	if _transition_in_progress:
		return _failure("navigation_in_progress", "Ya hay una navegación en curso.")
	var active_view = _active_content_view()
	if active_view != null:
		return {"ok": true, "data": {"season_view": active_view}, "errors": []}
	if season_scene == null:
		return _show_failure(
			"season_scene_unavailable",
			"No se pudo abrir la demostración de temporada."
		)

	_transition_in_progress = true
	demo_button.disabled = true
	selection_button.disabled = true
	var instance = season_scene.instantiate()
	if not instance is Control:
		if instance != null:
			instance.free()
		_transition_in_progress = false
		demo_button.disabled = false
		selection_button.disabled = false
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
	back_button.text = "Volver al inicio"
	_clear_error()
	_transition_in_progress = false
	back_button.grab_focus()
	return {"ok": true, "data": {"season_view": _season_view}, "errors": []}


## Abre el catálogo histórico dentro del mismo contenedor usado por la demo.
## El selector ofrece su propio retorno; el retorno global queda para consultas.
func show_season_selection(selected_season_id: String = "") -> Dictionary:
	if _transition_in_progress:
		return _failure("navigation_in_progress", "Ya hay una navegación en curso.")
	var active_view = _active_content_view()
	if active_view != null:
		return {"ok": true, "data": {"selection_view": active_view}, "errors": []}
	if selection_scene == null:
		return _show_failure(
			"selection_scene_unavailable",
			"No se pudo abrir el selector de temporadas."
		)

	_transition_in_progress = true
	demo_button.disabled = true
	selection_button.disabled = true
	var instance = selection_scene.instantiate()
	if not instance is Control:
		if instance != null:
			instance.free()
		_transition_in_progress = false
		demo_button.disabled = false
		selection_button.disabled = false
		return _show_failure(
			"invalid_selection_scene",
			"El selector no contiene una interfaz válida."
		)
	_selection_view = instance
	_selection_view.set("catalog_root_path", season_root_path)
	season_host.add_child(_selection_view)
	_selection_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _selection_view.has_signal("back_requested"):
		_selection_view.back_requested.connect(_on_back_button_pressed)
	if _selection_view.has_signal("season_view_requested"):
		_selection_view.season_view_requested.connect(_on_historical_season_requested)
	if not selected_season_id.is_empty() and _selection_view.has_method("select_season"):
		_selection_view.select_season(selected_season_id)
	menu_presentation.visible = false
	season_host.visible = true
	back_button.visible = false
	back_button.text = "Volver al inicio"
	_clear_error()
	_transition_in_progress = false
	if _selection_view.has_method("focus_initial_control"):
		_selection_view.focus_initial_control()
	return {"ok": true, "data": {"selection_view": _selection_view}, "errors": []}


## Revalida el pack y solo sustituye el selector después de configurar una
## SeasonOverview lista. Durante los await el selector permanece visible.
func open_historical_season(season_id: String) -> Dictionary:
	if _transition_in_progress:
		return _failure("navigation_in_progress", "Ya hay una navegación en curso.")
	var selector = _active_selection_view()
	if selector == null or _active_season_view() != null:
		return _failure("season_selection_unavailable",
			"La consulta histórica requiere un selector activo.")

	_transition_in_progress = true
	back_button.disabled = true
	if selector.has_method("set_request_in_progress"):
		selector.set_request_in_progress(true)
	var prepared = session_loader.prepare_session(season_id, season_root_path)
	if not prepared.ok:
		return _historical_failure(prepared.errors)
	if season_scene == null:
		return _historical_failure([{
			"code": "season_scene_unavailable",
			"message": "No se pudo abrir la consulta de temporada.",
		}])

	var instance = season_scene.instantiate()
	if not instance is Control or not instance.has_method("configure"):
		if instance != null:
			instance.free()
		return _historical_failure([{
			"code": "invalid_season_scene",
			"message": "La consulta no contiene una SeasonOverview configurable.",
		}])
	if not _has_property(instance, "auto_demo"):
		instance.free()
		return _historical_failure([{
			"code": "invalid_season_scene",
			"message": "La consulta no permite desactivar la demostración.",
		}])
	instance.auto_demo = false
	instance.visible = false
	season_host.add_child(instance)
	instance.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	if not is_instance_valid(instance) or not instance.is_node_ready():
		return _historical_failure([{
			"code": "season_view_not_ready",
			"message": "La consulta de temporada no terminó de prepararse.",
		}], instance if is_instance_valid(instance) else null)
	var presentation: Dictionary = prepared.data.presentation.duplicate(true)
	if _development_season_pack_active:
		presentation["synthetic"] = true
		presentation["season_name"] = "Temporada técnica 1982-83"
		presentation["competition_name"] = "Liga sintética de desarrollo"
	var configured = instance.configure(
		prepared.data.controller,
		prepared.data.calendar,
		prepared.data.selection,
		presentation
	)
	if not configured.ok:
		return _historical_failure(configured.errors, instance)

	season_host.remove_child(selector)
	selector.queue_free()
	_selection_view = null
	_season_view = instance
	_season_view.visible = true
	if _development_season_pack_active:
		var badge = _season_view.get_node_or_null("%SyntheticBadge")
		if badge is Label:
			badge.text = DEVELOPMENT_WARNING
	_historical_view_active = true
	_historical_season_id = season_id
	back_button.visible = true
	back_button.text = "Volver a temporadas"
	back_button.disabled = false
	_clear_error()
	_transition_in_progress = false
	back_button.grab_focus()
	return {"ok": true, "data": {"season_view": _season_view}, "errors": []}


func return_to_season_selection() -> Dictionary:
	if _transition_in_progress:
		return _failure("navigation_in_progress", "Ya hay una navegación en curso.")
	if not _historical_view_active:
		return _failure("historical_view_unavailable",
			"No hay una consulta histórica activa.")
	_transition_in_progress = true
	var previous_id = _historical_season_id
	var active_view = _active_season_view()
	if active_view != null:
		season_host.remove_child(active_view)
		active_view.queue_free()
	_season_view = null
	_historical_view_active = false
	_historical_season_id = ""
	_transition_in_progress = false
	return show_season_selection(previous_id)


## Retira inmediatamente la vista del contenedor y difiere su liberación al
## final del frame, permitiendo abrir una demostración nueva sin referencias.
func show_main_menu() -> Dictionary:
	if _transition_in_progress:
		return _failure("navigation_in_progress", "Ya hay una navegación en curso.")
	_transition_in_progress = true
	var active_view = _active_content_view()
	if active_view != null:
		season_host.remove_child(active_view)
		active_view.queue_free()
	_season_view = null
	_selection_view = null
	_historical_view_active = false
	_historical_season_id = ""
	_show_menu_state()
	_clear_error()
	_transition_in_progress = false
	return {"ok": true, "data": null, "errors": []}


func _on_demo_button_pressed() -> void:
	show_season_demo()


func _on_selection_button_pressed() -> void:
	show_season_selection()


func _on_back_button_pressed() -> void:
	if _transition_in_progress:
		return
	if _historical_view_active:
		return_to_season_selection()
	else:
		show_main_menu()


func _on_historical_season_requested(season_id: String) -> void:
	await open_historical_season(season_id)


func _active_season_view() -> Control:
	if _season_view == null or not is_instance_valid(_season_view):
		_season_view = null
		return null
	return _season_view


func _active_selection_view() -> Control:
	if _selection_view == null or not is_instance_valid(_selection_view):
		_selection_view = null
		return null
	return _selection_view


func _active_content_view() -> Control:
	var season = _active_season_view()
	if season != null:
		return season
	return _active_selection_view()


func _show_menu_state() -> void:
	menu_presentation.visible = true
	season_host.visible = false
	back_button.visible = false
	back_button.disabled = false
	back_button.text = "Volver al inicio"
	demo_button.disabled = false
	selection_button.disabled = false
	demo_button.grab_focus()


func _configure_focus_navigation() -> void:
	demo_button.focus_next = demo_button.get_path_to(selection_button)
	demo_button.focus_previous = demo_button.get_path_to(selection_button)
	selection_button.focus_next = selection_button.get_path_to(demo_button)
	selection_button.focus_previous = selection_button.get_path_to(demo_button)


## El modo de desarrollo solo se activa con un argumento de usuario separado
## de las opciones del motor mediante `--`. Repetir el argumento es idempotente.
func _configure_runtime_mode(user_args: PackedStringArray) -> void:
	var development_requested = DEVELOPMENT_ARGUMENT in user_args
	_development_season_pack_active = development_requested \
		and _development_pack_available()
	_development_pack_request_rejected = development_requested \
		and not _development_season_pack_active
	if _development_season_pack_active:
		season_root_path = development_season_root_path
	elif season_root_path in [DEVELOPMENT_SEASON_ROOT, development_season_root_path]:
		# Evita que una ruta guardada en la escena active el pack silenciosamente.
		season_root_path = DEFAULT_SEASON_ROOT
	development_mode_banner.visible = _development_season_pack_active
	if _development_pack_request_rejected:
		_show_development_pack_unavailable()


func _development_pack_available() -> bool:
	var pack_path = development_season_root_path.path_join(DEVELOPMENT_SEASON_ID)
	for file_name in DEVELOPMENT_REQUIRED_FILES:
		if not FileAccess.file_exists(pack_path.path_join(file_name)):
			return false
	return true


func _show_development_pack_unavailable() -> void:
	error_label.text = (
		"development_pack_unavailable: El pack sintético no está incluido en "
		+ "esta variante. Se mantiene el catálogo histórico."
	)
	error_label.visible = true


func _show_failure(code: String, message: String) -> Dictionary:
	_show_menu_state()
	error_label.text = "%s: %s" % [code, message]
	error_label.visible = true
	return _failure(code, message)


func _clear_error() -> void:
	if _development_pack_request_rejected:
		_show_development_pack_unavailable()
		return
	error_label.text = ""
	error_label.visible = false


func _historical_failure(errors: Array, provisional_view: Control = null) -> Dictionary:
	if provisional_view != null and is_instance_valid(provisional_view):
		if provisional_view.get_parent() == season_host:
			season_host.remove_child(provisional_view)
		provisional_view.queue_free()
	var selector = _active_selection_view()
	if selector != null:
		if selector.has_method("refresh_catalog"):
			selector.refresh_catalog()
		if selector.has_method("show_request_errors"):
			selector.show_request_errors(errors)
		if selector.has_method("set_request_in_progress"):
			selector.set_request_in_progress(false)
		if selector.has_method("focus_initial_control"):
			selector.focus_initial_control()
	back_button.disabled = false
	_transition_in_progress = false
	return {"ok": false, "data": null, "errors": errors.duplicate(true)}


func _has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if property.name == property_name:
			return true
	return false


func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "data": null, "errors": [{"code": code, "message": message}]}
