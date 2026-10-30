class_name ManagerOffice
extends Control

const Calendar = preload("res://game/scripts/services/calendar_service.gd")
const Controller = preload("res://game/scripts/services/season_controller.gd")
const Fixture = preload("res://game/scripts/data/match_fixture.gd")
const Result = preload("res://game/scripts/data/match_result.gd")

const CLUB_ID = "dev_aurora_union"
const SEASON_ID = "1982-83"

signal module_requested(module: String)
signal exit_requested

@onready var season_label: Label = %SeasonLabel
@onready var club_label: Label = %ClubLabel
@onready var warning_label: Label = %WarningLabel
@onready var agenda_fixture_label: Label = %AgendaFixtureLabel
@onready var agenda_date_label: Label = %AgendaDateLabel
@onready var standings_summary: Label = %StandingsSummary
@onready var calendar_summary: Label = %CalendarSummary
@onready var news_status: Label = %NewsStatus
@onready var finance_status: Label = %FinanceStatus
@onready var standings_button: Button = %StandingsButton
@onready var calendar_button: Button = %CalendarButton
@onready var squad_button: Button = %SquadButton
@onready var tactics_button: Button = %TacticsButton
@onready var market_button: Button = %MarketButton
@onready var advance_button: Button = %AdvanceButton
@onready var exit_button: Button = %ExitButton
@onready var error_label: Label = %ErrorLabel

var _controller: Controller = null
var _fixtures: Array[Fixture] = []
var _selection: Dictionary = {}
var _presentation: Dictionary = {}
var _club_id := CLUB_ID


func _ready() -> void:
	standings_button.pressed.connect(_request_standings)
	calendar_button.pressed.connect(_request_calendar)
	exit_button.pressed.connect(_request_exit)
	_configure_focus_navigation()
	_set_future_actions_pending()


## Vincula una sesión deportiva ya preparada. El Despacho solo consulta las
## APIs públicas del controlador y CalendarService; no mantiene estado temporal.
func configure(controller: Controller, fixtures: Array[Fixture], selection: Dictionary,
		presentation: Dictionary, club_id: String = CLUB_ID) -> Dictionary:
	if not is_node_ready():
		return _failure("view_not_ready", "El Despacho todavía no está preparado.")
	if controller == null:
		return _show_failure("invalid_controller", "Falta el controlador deportivo.")
	if selection.get("season_id") != SEASON_ID or club_id != CLUB_ID:
		return _show_failure(
			"unsupported_development_context",
			"Este prototipo solo admite Aurora Unión en la temporada técnica 1982-83."
		)
	var context = controller.get_session_context()
	if not context.ok:
		return _show_result(context)
	if context.data.selection != selection:
		return _show_failure(
			"controller_selection_mismatch",
			"La selección no coincide con la sesión del controlador."
		)
	if not _same_calendar(context.data.fixtures, fixtures):
		return _show_failure(
			"controller_calendar_mismatch",
			"El calendario no coincide con la sesión del controlador."
		)
	var standings = controller.get_standings()
	if not standings.ok:
		return _show_result(standings)
	if not standings.data.rows.any(func(row): return row.club_id == club_id):
		return _show_failure(
			"assigned_club_unavailable", "El club provisional no pertenece a la sesión."
		)
	var results = controller.get_results()
	if not results.ok:
		return _show_result(results)

	_controller = controller
	_fixtures = fixtures.duplicate()
	_selection = selection.duplicate(true)
	_presentation = presentation.duplicate(true)
	_club_id = club_id
	_render_header()
	_render_agenda(results.data.results)
	_render_modules(standings.data.rows.size())
	_clear_error()
	return {
		"ok": true,
		"data": {
			"club_id": _club_id,
			"season_id": _selection.season_id,
			"fixture_count": _fixtures.size(),
			"standings_row_count": standings.data.rows.size(),
		},
		"errors": [],
	}


func focus_initial_control() -> void:
	standings_button.grab_focus()


func focus_module_control(module: String) -> void:
	if module == "calendar":
		calendar_button.grab_focus()
	else:
		standings_button.grab_focus()


func get_context() -> Dictionary:
	return {
		"club_id": _club_id,
		"selection": _selection.duplicate(true),
		"fixture_count": _fixtures.size(),
	}


func show_navigation_error(errors: Array) -> void:
	if errors.is_empty():
		return
	var first = errors[0]
	error_label.text = "%s: %s" % [
		first.get("code", "office_navigation_error"),
		first.get("message", "No se pudo abrir el módulo."),
	]
	error_label.visible = true


func _render_header() -> void:
	season_label.text = "Temporada técnica 1982-83"
	club_label.text = "Club dirigido: %s · elección provisional de desarrollo" % _club_name(_club_id)
	warning_label.text = "MODO DESARROLLO — DATOS SINTÉTICOS"


func _render_agenda(results: Array) -> void:
	var finished: Dictionary = {}
	for result in results:
		if result.status == Result.Status.FINAL:
			finished[result.fixture_id] = true
	var candidates = Calendar.new().get_club_fixtures(
		_fixtures,
		_selection.season_id,
		_club_id,
		{
			"competition_id": _selection.competition_id,
			"stage_id": _selection.stage_id,
			"group_id": _selection.group_id,
		},
		Calendar.Order.DATE
	)
	var next_fixture: Fixture = null
	for fixture in candidates:
		if not finished.has(fixture.fixture_id):
			next_fixture = fixture
			break
	if next_fixture == null:
		agenda_fixture_label.text = "No hay partidos pendientes en el calendario suministrado."
		agenda_date_label.text = "Sin fecha deportiva pendiente."
		return
	var round_text = "Sin jornada" if next_fixture.round_number == null \
		else "Jornada %d" % next_fixture.round_number
	agenda_fixture_label.text = "%s · %s — %s" % [
		round_text,
		_club_name(next_fixture.home_club_id),
		_club_name(next_fixture.away_club_id),
	]
	agenda_fixture_label.set_meta("fixture_id", next_fixture.fixture_id)
	agenda_date_label.text = (
		"Fecha deportiva: %s · dato de consulta, sin avance temporal"
		% (next_fixture.scheduled_date if next_fixture.scheduled_date != null
			else "por determinar")
	)


func _render_modules(row_count: int) -> void:
	standings_summary.text = "Clasificación disponible · %d clubes · servicio deportivo existente" % row_count
	var rounds = Calendar.new().get_round_numbers(
		_fixtures, _selection.season_id, {
			"competition_id": _selection.competition_id,
			"stage_id": _selection.stage_id,
			"group_id": _selection.group_id,
		}
	)
	calendar_summary.text = "Calendario disponible · %d jornadas · %d partidos" % [
		rounds.size(), _fixtures.size(),
	]
	news_status.text = "Noticias — pendiente de implementación"
	finance_status.text = "Finanzas — pendiente de implementación"


func _set_future_actions_pending() -> void:
	for button in [squad_button, tactics_button, market_button, advance_button]:
		button.disabled = true
		button.focus_mode = Control.FOCUS_NONE


func _configure_focus_navigation() -> void:
	standings_button.focus_next = standings_button.get_path_to(calendar_button)
	standings_button.focus_previous = standings_button.get_path_to(exit_button)
	calendar_button.focus_next = calendar_button.get_path_to(exit_button)
	calendar_button.focus_previous = calendar_button.get_path_to(standings_button)
	exit_button.focus_next = exit_button.get_path_to(standings_button)
	exit_button.focus_previous = exit_button.get_path_to(calendar_button)


func _request_standings() -> void:
	module_requested.emit("standings")


func _request_calendar() -> void:
	module_requested.emit("calendar")


func _request_exit() -> void:
	exit_requested.emit()


func _club_name(club_id: Variant) -> String:
	if club_id == null:
		return "Club desconocido"
	return _presentation.get("club_names", {}).get(club_id, club_id)


func _same_calendar(left: Array, right: Array) -> bool:
	if left.size() != right.size():
		return false
	var right_by_id: Dictionary = {}
	for fixture in right:
		if fixture == null or right_by_id.has(fixture.fixture_id):
			return false
		right_by_id[fixture.fixture_id] = fixture
	for fixture in left:
		if fixture == null or not right_by_id.has(fixture.fixture_id):
			return false
		var other = right_by_id[fixture.fixture_id]
		for field in ["season_id", "competition_id", "stage_id", "group_id",
				"home_club_id", "away_club_id", "round_number", "scheduled_date", "metadata"]:
			if fixture.get(field) != other.get(field):
				return false
	return true


func _show_result(result: Dictionary) -> Dictionary:
	if not result.ok:
		show_navigation_error(result.errors)
	return result


func _show_failure(code: String, message: String) -> Dictionary:
	var result = _failure(code, message)
	show_navigation_error(result.errors)
	return result


func _clear_error() -> void:
	error_label.text = ""
	error_label.visible = false


func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "data": null, "errors": [{"code": code, "message": message}]}
