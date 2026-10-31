class_name MainMenu
extends Control

const DEFAULT_SEASON_SCENE = preload("res://game/scenes/season_overview.tscn")
const DEFAULT_SELECTION_SCENE = preload("res://game/scenes/season_selection.tscn")
const DEFAULT_OFFICE_SCENE = preload("res://game/scenes/manager_office.tscn")
const DEFAULT_CLUB_SELECTION_SCENE = preload("res://game/scenes/manager_club_selection.tscn")
const DEFAULT_SQUAD_SCENE = preload("res://game/scenes/manager_squad.tscn")
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
@export var office_scene: PackedScene = DEFAULT_OFFICE_SCENE
@export var club_selection_scene: PackedScene = DEFAULT_CLUB_SELECTION_SCENE
@export var squad_scene: PackedScene = DEFAULT_SQUAD_SCENE
@export var season_root_path := DEFAULT_SEASON_ROOT

@onready var menu_presentation: CenterContainer = %MenuPresentation
@onready var season_host: MarginContainer = %SeasonHost
@onready var demo_button: Button = %DemoButton
@onready var selection_button: Button = %SelectionButton
@onready var office_button: Button = %OfficeButton
@onready var back_button: Button = %BackButton
@onready var error_label: Label = %ErrorLabel
@onready var development_mode_banner: Label = %DevelopmentModeBanner

var _season_view: Control = null
var _selection_view: Control = null
var _club_selection_view: Control = null
var _office_view: Control = null
var _squad_view: Control = null
var _transition_in_progress := false
var _historical_view_active := false
var _historical_season_id := ""
var _development_season_pack_active := false
var _development_pack_request_rejected := false
var _office_module_active := false
var _office_module := ""
var _office_session: Dictionary = {}
var development_season_root_path := DEVELOPMENT_SEASON_ROOT
var command_line_user_args: PackedStringArray = OS.get_cmdline_user_args()
var session_loader = SessionLoader.new()


func _ready() -> void:
	_configure_runtime_mode(command_line_user_args)
	demo_button.pressed.connect(_on_demo_button_pressed)
	selection_button.pressed.connect(_on_selection_button_pressed)
	office_button.pressed.connect(_on_office_button_pressed)
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
	office_button.disabled = true
	var instance = season_scene.instantiate()
	if not instance is Control:
		if instance != null:
			instance.free()
		_transition_in_progress = false
		demo_button.disabled = false
		selection_button.disabled = false
		office_button.disabled = not _development_season_pack_active
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
	office_button.disabled = true
	var instance = selection_scene.instantiate()
	if not instance is Control:
		if instance != null:
			instance.free()
		_transition_in_progress = false
		demo_button.disabled = false
		selection_button.disabled = false
		office_button.disabled = not _development_season_pack_active
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


## Prepara una única sesión sintética validada y abre la selección de club.
## Confirmar el club es un paso posterior; aquí no se crea aún el Despacho.
func show_manager_club_selection() -> Dictionary:
	if _transition_in_progress:
		return _failure("navigation_in_progress", "Ya hay una navegación en curso.")
	if not _development_season_pack_active:
		return _show_failure(
			"development_mode_required",
			"El prototipo del Despacho solo está disponible con --dev-season-pack."
		)
	var active_view = _active_content_view()
	if active_view != null:
		if active_view == _club_selection_view:
			return {"ok": true, "data": {"club_selection_view": active_view}, "errors": []}
		return _failure(
			"content_already_active", "Debe volver al menú antes de iniciar el prototipo."
		)
	if club_selection_scene == null:
		return _show_failure(
			"club_selection_scene_unavailable", "No se pudo abrir la selección de club."
		)

	_transition_in_progress = true
	demo_button.disabled = true
	selection_button.disabled = true
	office_button.disabled = true
	var prepared = session_loader.prepare_session(DEVELOPMENT_SEASON_ID, season_root_path)
	if not prepared.ok:
		_transition_in_progress = false
		_show_menu_state()
		return _show_errors(prepared.errors)
	var presentation: Dictionary = prepared.data.presentation.duplicate(true)
	presentation["synthetic"] = true
	presentation["season_name"] = "Temporada técnica 1982-83"
	presentation["competition_name"] = "Liga sintética de desarrollo"
	_office_session = {
		"controller": prepared.data.controller,
		"calendar": prepared.data.calendar,
		"players": prepared.data.players,
		"selection": prepared.data.selection.duplicate(true),
		"presentation": presentation.duplicate(true),
	}
	var instance = club_selection_scene.instantiate()
	if not instance is Control or not instance.has_method("configure"):
		if instance != null:
			instance.free()
		_transition_in_progress = false
		_office_session = {}
		return _show_failure(
			"invalid_club_selection_scene",
			"La selección de club no contiene una interfaz válida."
		)
	_club_selection_view = instance
	_club_selection_view.visible = false
	season_host.add_child(_club_selection_view)
	_club_selection_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	if not is_instance_valid(_club_selection_view) or not _club_selection_view.is_node_ready():
		return _club_selection_open_failure(
			"club_selection_not_ready", "La selección de club no terminó de prepararse."
		)
	var configured = _club_selection_view.configure(
		_office_session.controller,
		_office_session.selection,
		_office_session.presentation
	)
	if not configured.ok:
		return _club_selection_open_failure(
			configured.errors[0].get("code", "club_selection_configuration_failed"),
			configured.errors[0].get("message", "No se pudo configurar la selección de club.")
		)
	_club_selection_view.club_confirmed.connect(_on_manager_club_confirmed)
	_club_selection_view.back_requested.connect(_on_club_selection_back_requested)
	_club_selection_view.visible = true
	menu_presentation.visible = false
	season_host.visible = true
	back_button.visible = false
	_clear_error()
	_transition_in_progress = false
	_club_selection_view.focus_initial_control()
	return {
		"ok": true,
		"data": {"club_selection_view": _club_selection_view},
		"errors": [],
	}


## Abre el Despacho solo tras recibir un identificador confirmado por la
## selección activa. ManagerOffice vuelve a validar su pertenencia a la sesión.
func open_manager_office(club_id: String) -> Dictionary:
	if _transition_in_progress:
		return _failure("navigation_in_progress", "Ya hay una navegación en curso.")
	if not _development_season_pack_active:
		return _failure(
			"development_mode_required",
			"El prototipo del Despacho solo está disponible con --dev-season-pack."
		)
	if _club_selection_view == null or not is_instance_valid(_club_selection_view) \
			or _club_selection_view.get_parent() != season_host:
		return _failure(
			"club_selection_unavailable", "Debe seleccionar un club antes de abrir el Despacho."
		)
	if office_scene == null:
		return _club_confirmation_failure([{
			"code": "office_scene_unavailable",
			"message": "No se pudo abrir el Despacho.",
		}])
	_transition_in_progress = true
	_club_selection_view.set_request_in_progress(true)
	var instance = office_scene.instantiate()
	if not instance is Control or not instance.has_method("configure"):
		if instance != null:
			instance.free()
		_transition_in_progress = false
		return _club_confirmation_failure([{
			"code": "invalid_office_scene",
			"message": "El Despacho no contiene una interfaz válida.",
		}])
	_office_view = instance
	_office_view.visible = false
	season_host.add_child(_office_view)
	_office_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	if not is_instance_valid(_office_view) or not _office_view.is_node_ready():
		_transition_in_progress = false
		return _club_confirmation_failure([{
			"code": "office_view_not_ready",
			"message": "El Despacho no terminó de prepararse.",
		}], _office_view if is_instance_valid(_office_view) else null)
	var configured = _office_view.configure(
		_office_session.controller,
		_office_session.calendar,
		_office_session.selection,
		_office_session.presentation,
		club_id
	)
	if not configured.ok:
		_transition_in_progress = false
		return _club_confirmation_failure(configured.errors, _office_view)
	season_host.remove_child(_club_selection_view)
	_club_selection_view.queue_free()
	_club_selection_view = null
	_office_session["club_id"] = club_id
	_office_view.module_requested.connect(_on_office_module_requested)
	_office_view.exit_requested.connect(_on_office_exit_requested)
	_office_view.visible = true
	_clear_error()
	_transition_in_progress = false
	_office_view.focus_initial_control()
	return {"ok": true, "data": {"office_view": _office_view}, "errors": []}


func open_office_module(module: String) -> Dictionary:
	if _transition_in_progress:
		return _failure("navigation_in_progress", "Ya hay una navegación en curso.")
	if _office_view == null or not is_instance_valid(_office_view) \
			or _office_view.get_parent() != season_host:
		return _failure("office_unavailable", "No hay un Despacho activo.")
	if module not in ["standings", "calendar", "squad"]:
		return _failure("unknown_office_module", "El módulo solicitado no existe.")
	if module == "squad":
		return await _open_squad_module()
	if season_scene == null:
		return _office_navigation_failure([{
			"code": "season_scene_unavailable",
			"message": "No se pudo abrir la consulta deportiva.",
		}])
	_transition_in_progress = true
	var instance = season_scene.instantiate()
	if not instance is Control or not instance.has_method("configure"):
		if instance != null:
			instance.free()
		_transition_in_progress = false
		return _office_navigation_failure([{
			"code": "invalid_season_scene",
			"message": "La consulta deportiva no contiene una interfaz válida.",
		}])
	instance.auto_demo = false
	instance.visible = false
	season_host.add_child(instance)
	instance.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	var configured = instance.configure(
		_office_session.controller,
		_office_session.calendar,
		_office_session.selection,
		_office_session.presentation
	)
	if not configured.ok:
		season_host.remove_child(instance)
		instance.queue_free()
		_transition_in_progress = false
		return _office_navigation_failure(configured.errors)
	season_host.remove_child(_office_view)
	_season_view = instance
	_season_view.visible = true
	_office_module_active = true
	_office_module = module
	back_button.visible = true
	back_button.disabled = false
	back_button.text = "Volver al Despacho"
	var tabs = _season_view.get_node_or_null("%Tabs")
	if tabs is TabContainer:
		tabs.current_tab = 1 if module == "calendar" else 0
	var focus_target = _season_view.get_node_or_null(
		"%RoundSelector" if module == "calendar" else "%StandingsTree"
	)
	if focus_target is Control:
		focus_target.grab_focus()
	_transition_in_progress = false
	return {"ok": true, "data": {"season_view": _season_view, "module": module}, "errors": []}


func _open_squad_module() -> Dictionary:
	if squad_scene == null:
		return _office_navigation_failure([{
			"code": "squad_scene_unavailable",
			"message": "No se pudo abrir la Plantilla.",
		}])
	_transition_in_progress = true
	var instance = squad_scene.instantiate()
	if not instance is Control or not instance.has_method("configure"):
		if instance != null:
			instance.free()
		_transition_in_progress = false
		return _office_navigation_failure([{
			"code": "invalid_squad_scene",
			"message": "La Plantilla no contiene una interfaz válida.",
		}])
	instance.visible = false
	season_host.add_child(instance)
	instance.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	var configured = instance.configure(
		_office_session.players,
		_office_session.selection,
		_office_session.presentation,
		_office_session.club_id
	)
	if not configured.ok:
		season_host.remove_child(instance)
		instance.queue_free()
		_transition_in_progress = false
		return _office_navigation_failure(configured.errors)
	season_host.remove_child(_office_view)
	_squad_view = instance
	_squad_view.back_requested.connect(return_to_manager_office)
	_squad_view.visible = true
	_office_module_active = true
	_office_module = "squad"
	back_button.visible = true
	back_button.disabled = false
	back_button.text = "Volver al Despacho"
	_squad_view.focus_initial_control()
	_transition_in_progress = false
	return {"ok": true, "data": {"squad_view": _squad_view, "module": "squad"}, "errors": []}


func return_to_manager_office() -> Dictionary:
	if _transition_in_progress:
		return _failure("navigation_in_progress", "Ya hay una navegación en curso.")
	if not _office_module_active or _office_view == null or not is_instance_valid(_office_view):
		return _failure("office_module_unavailable", "No hay un módulo del Despacho activo.")
	_transition_in_progress = true
	var previous_module = _office_module
	var active_view: Control = _active_squad_view() if previous_module == "squad" \
		else _active_season_view()
	if active_view != null:
		season_host.remove_child(active_view)
		active_view.queue_free()
	_season_view = null
	_squad_view = null
	season_host.add_child(_office_view)
	_office_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_office_view.visible = true
	_office_module_active = false
	_office_module = ""
	back_button.visible = false
	back_button.text = "Volver al inicio"
	_transition_in_progress = false
	_office_view.focus_module_control(previous_module)
	return {"ok": true, "data": {"office_view": _office_view}, "errors": []}


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
	_squad_view = null
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
	if _office_view != null and is_instance_valid(_office_view) \
			and _office_view != active_view:
		if _office_view.get_parent() != null:
			_office_view.get_parent().remove_child(_office_view)
		_office_view.queue_free()
	_season_view = null
	_selection_view = null
	_club_selection_view = null
	_office_view = null
	_squad_view = null
	_historical_view_active = false
	_historical_season_id = ""
	_office_module_active = false
	_office_module = ""
	_office_session = {}
	_show_menu_state()
	_clear_error()
	_transition_in_progress = false
	return {"ok": true, "data": null, "errors": []}


func _on_demo_button_pressed() -> void:
	show_season_demo()


func _on_selection_button_pressed() -> void:
	show_season_selection()


func _on_office_button_pressed() -> void:
	await show_manager_club_selection()


func _on_manager_club_confirmed(club_id: String) -> void:
	await open_manager_office(club_id)


func _on_club_selection_back_requested() -> void:
	show_main_menu()


func _on_office_module_requested(module: String) -> void:
	await open_office_module(module)


func _on_office_exit_requested() -> void:
	show_main_menu()


func _on_back_button_pressed() -> void:
	if _transition_in_progress:
		return
	if _office_module_active:
		return_to_manager_office()
	elif _historical_view_active:
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


func _active_squad_view() -> Control:
	if _squad_view == null or not is_instance_valid(_squad_view):
		_squad_view = null
		return null
	return _squad_view


func _active_content_view() -> Control:
	var squad = _active_squad_view()
	if squad != null:
		return squad
	var season = _active_season_view()
	if season != null:
		return season
	var selection = _active_selection_view()
	if selection != null:
		return selection
	if _club_selection_view != null and is_instance_valid(_club_selection_view):
		return _club_selection_view
	if _office_view != null and is_instance_valid(_office_view):
		return _office_view
	return null


func _show_menu_state() -> void:
	menu_presentation.visible = true
	season_host.visible = false
	back_button.visible = false
	back_button.disabled = false
	back_button.text = "Volver al inicio"
	demo_button.disabled = false
	selection_button.disabled = false
	office_button.visible = _development_season_pack_active
	office_button.disabled = not _development_season_pack_active
	demo_button.grab_focus()


func _configure_focus_navigation() -> void:
	demo_button.focus_next = demo_button.get_path_to(selection_button)
	demo_button.focus_previous = demo_button.get_path_to(office_button) \
		if _development_season_pack_active else demo_button.get_path_to(selection_button)
	selection_button.focus_next = selection_button.get_path_to(office_button) \
		if _development_season_pack_active else selection_button.get_path_to(demo_button)
	selection_button.focus_previous = selection_button.get_path_to(demo_button)
	office_button.focus_next = office_button.get_path_to(demo_button)
	office_button.focus_previous = office_button.get_path_to(selection_button)


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
	office_button.visible = _development_season_pack_active
	office_button.disabled = not _development_season_pack_active
	_configure_focus_navigation()
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


func _club_selection_open_failure(code: String, message: String) -> Dictionary:
	if _club_selection_view != null and is_instance_valid(_club_selection_view):
		if _club_selection_view.get_parent() == season_host:
			season_host.remove_child(_club_selection_view)
		_club_selection_view.queue_free()
	_club_selection_view = null
	_office_session = {}
	_transition_in_progress = false
	return _show_failure(code, message)


func _club_confirmation_failure(errors: Array,
		provisional_view: Control = null) -> Dictionary:
	if provisional_view != null and is_instance_valid(provisional_view):
		if provisional_view.get_parent() == season_host:
			season_host.remove_child(provisional_view)
		provisional_view.queue_free()
	_office_view = null
	_transition_in_progress = false
	if _club_selection_view != null and is_instance_valid(_club_selection_view):
		_club_selection_view.show_request_errors(errors)
	return {"ok": false, "data": null, "errors": errors.duplicate(true)}


func _office_navigation_failure(errors: Array) -> Dictionary:
	if _office_view != null and is_instance_valid(_office_view) \
			and _office_view.has_method("show_navigation_error"):
		_office_view.show_navigation_error(errors)
		_office_view.focus_initial_control()
	return {"ok": false, "data": null, "errors": errors.duplicate(true)}


func _show_errors(errors: Array) -> Dictionary:
	if errors.is_empty():
		return _show_failure("office_load_failed", "No se pudo cargar la sesión del Despacho.")
	var first = errors[0]
	return _show_failure(
		first.get("code", "office_load_failed"),
		first.get("message", "No se pudo cargar la sesión del Despacho.")
	)


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
