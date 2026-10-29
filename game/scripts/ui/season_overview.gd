class_name SeasonOverview
extends Control

const Controller = preload("res://game/scripts/services/season_controller.gd")
const Calendar = preload("res://game/scripts/services/calendar_service.gd")
const Generator = preload("res://game/scripts/services/league_calendar_generator.gd")
const Club = preload("res://game/scripts/data/club_season.gd")
const Fixture = preload("res://game/scripts/data/match_fixture.gd")
const Result = preload("res://game/scripts/data/match_result.gd")
const Rules = preload("res://game/scripts/data/competition_rules.gd")

const SELECTION_FIELDS = ["season_id", "competition_id", "stage_id", "group_id"]
const TABLE_COLUMNS = ["Pos", "Club", "PJ", "G", "E", "P", "GF", "GC", "DG", "Pts"]

@export var auto_demo := true

@onready var competition_title: Label = %CompetitionTitle
@onready var scope_label: Label = %ScopeLabel
@onready var synthetic_badge: Label = %SyntheticBadge
@onready var error_label: Label = %ErrorLabel
@onready var diagnostics_panel: PanelContainer = %DiagnosticsPanel
@onready var provisional_label: Label = %ProvisionalLabel
@onready var pending_diagnostics_label: Label = %PendingDiagnosticsLabel
@onready var standings_tree: Tree = %StandingsTree
@onready var round_selector: OptionButton = %RoundSelector
@onready var match_list: VBoxContainer = %MatchList

var _controller: Controller = null
var _fixtures: Array[Fixture] = []
var _selection: Dictionary = {}
var _display_metadata: Dictionary = {}
var _round_numbers: Array[int] = []
var _selected_round: Variant = null


func _ready() -> void:
	for index in TABLE_COLUMNS.size():
		standings_tree.set_column_title(index, TABLE_COLUMNS[index])
	standings_tree.set_column_expand(0, false)
	standings_tree.set_column_custom_minimum_width(0, 42)
	for index in range(2, TABLE_COLUMNS.size()):
		standings_tree.set_column_expand(index, false)
		standings_tree.set_column_custom_minimum_width(index, 48)
	round_selector.item_selected.connect(_on_round_selected)
	if auto_demo and _controller == null:
		_configure_demo()


## Vincula una sesión ya inicializada. La escena conserva copias defensivas de
## calendario, selección y metadatos; toda estadística procede del controlador.
func configure(controller: Controller, fixtures: Array[Fixture], selection: Dictionary,
		display_metadata: Dictionary = {}) -> Dictionary:
	if not is_node_ready():
		return _failure("view_not_ready", "La vista todavía no está preparada.")
	if controller == null:
		return _show_failure("invalid_controller", "Se requiere un controlador de temporada.")
	var selection_error = _validate_selection(selection)
	if selection_error != null:
		return _show_result(selection_error)
	var metadata_error = _validate_metadata(display_metadata)
	if metadata_error != null:
		return _show_result(metadata_error)
	for index in fixtures.size():
		if fixtures[index] == null:
			return _show_failure(
				"invalid_fixture", "El partido en el índice %d es nulo." % index
			)
	var context = controller.get_session_context()
	if not context.ok:
		return _show_result(context)
	if not _same_selection(selection, context.data.selection):
		return _show_failure(
			"controller_selection_mismatch",
			"La selección solicitada no coincide con la sesión del controlador."
		)
	if not _same_calendar(fixtures, context.data.fixtures):
		return _show_failure(
			"controller_calendar_mismatch",
			"El calendario proporcionado no coincide con la sesión del controlador."
		)
	var standings = controller.get_standings()
	if not standings.ok:
		return _show_result(standings)
	var results = controller.get_results()
	if not results.ok:
		return _show_result(results)

	_controller = controller
	_fixtures = _copy_fixtures(fixtures)
	_selection = selection.duplicate(true)
	_display_metadata = display_metadata.duplicate(true)
	_selected_round = null
	_update_header()
	return refresh_view()


## Consulta de nuevo el estado deportivo y reconstruye solo su representación.
func refresh_view() -> Dictionary:
	if _controller == null:
		return _show_failure("not_configured", "La vista no tiene una temporada configurada.")
	var standings = _controller.get_standings()
	if not standings.ok:
		return _show_result(standings)
	var result_query = _controller.get_results()
	if not result_query.ok:
		return _show_result(result_query)

	_clear_error()
	_render_standings(standings.data.rows)
	_render_diagnostics(standings.data)
	var filters = _calendar_filters()
	_round_numbers = Calendar.new().get_round_numbers(
		_fixtures, _selection.season_id, filters
	)
	if _selected_round == null or not _round_numbers.has(_selected_round):
		_selected_round = _round_numbers[0] if not _round_numbers.is_empty() else null
	_rebuild_round_selector()
	var match_count = _render_selected_round(result_query.data.results)
	return {
		"ok": true,
		"data": {
			"selected_round": _selected_round,
			"round_numbers": _round_numbers.duplicate(),
			"standings_row_count": standings.data.rows.size(),
			"match_count": match_count,
			"provisional": standings.data.provisional,
			"pending_tiebreaker_count": standings.data.pending_tiebreakers.size(),
		},
		"errors": [],
	}


func _render_standings(rows: Array) -> void:
	standings_tree.clear()
	var root = standings_tree.create_item()
	for row in rows:
		var item = standings_tree.create_item(root)
		var values = [
			row.position, _club_name(row.club_id), row.played, row.wins, row.draws,
			row.losses, row.goals_for, row.goals_against, row.goal_difference, row.points,
		]
		for index in values.size():
			item.set_text(index, str(values[index]))


func _render_diagnostics(data: Dictionary) -> void:
	var pending: Array = data.get("pending_tiebreakers", [])
	provisional_label.visible = data.get("provisional", false)
	var lines: Array[String] = []
	for diagnostic in pending:
		lines.append("%s · %s: %s" % [
			diagnostic.get("code", "diagnostic"),
			diagnostic.get("reason", "sin_detalle"),
			diagnostic.get("message", ""),
		])
	pending_diagnostics_label.text = "\n".join(lines)
	pending_diagnostics_label.visible = not lines.is_empty()
	diagnostics_panel.visible = provisional_label.visible or pending_diagnostics_label.visible


func _rebuild_round_selector() -> void:
	round_selector.clear()
	var selected_index = -1
	for index in _round_numbers.size():
		var round_number = _round_numbers[index]
		round_selector.add_item("Jornada %d" % round_number, round_number)
		if round_number == _selected_round:
			selected_index = index
	round_selector.disabled = _round_numbers.is_empty()
	if selected_index >= 0:
		round_selector.select(selected_index)


func _render_selected_round(results: Array) -> int:
	for child in match_list.get_children():
		match_list.remove_child(child)
		child.queue_free()
	if _selected_round == null:
		_add_calendar_message("No hay jornadas disponibles para esta selección.")
		return 0
	var results_by_fixture: Dictionary = {}
	for match_result in results:
		results_by_fixture[match_result.fixture_id] = match_result
	var fixtures = Calendar.new().get_round_fixtures(
		_fixtures, _selection.season_id, _selected_round,
		_calendar_filters(), Calendar.Order.FIXTURE_ID
	)
	for fixture in fixtures:
		var panel = PanelContainer.new()
		panel.name = "Match_%s" % fixture.fixture_id.validate_node_name()
		panel.set_meta("fixture_id", fixture.fixture_id)
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		panel.add_child(row)
		var date = Label.new()
		date.custom_minimum_size.x = 155
		date.text = fixture.scheduled_date if fixture.scheduled_date != null \
			else "Fecha por determinar"
		row.add_child(date)
		var match_text = Label.new()
		match_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var score = "Pendiente"
		if results_by_fixture.has(fixture.fixture_id):
			var match_result = results_by_fixture[fixture.fixture_id]
			if match_result.status == Result.Status.FINAL:
				score = "%d – %d" % [match_result.home_goals, match_result.away_goals]
		match_text.text = "%s  %s  %s" % [
			_club_name(fixture.home_club_id), score, _club_name(fixture.away_club_id)
		]
		row.add_child(match_text)
		match_list.add_child(panel)
	return fixtures.size()


func _add_calendar_message(message: String) -> void:
	var label = Label.new()
	label.text = message
	match_list.add_child(label)


func _on_round_selected(index: int) -> void:
	if index < 0 or index >= _round_numbers.size():
		return
	_selected_round = _round_numbers[index]
	if _controller != null:
		var result_query = _controller.get_results()
		if result_query.ok:
			_render_selected_round(result_query.data.results)
		else:
			_show_result(result_query)


func _calendar_filters() -> Dictionary:
	return {
		"competition_id": _selection.competition_id,
		"stage_id": _selection.stage_id,
		"group_id": _selection.group_id,
	}


func _club_name(club_id: Variant) -> String:
	if club_id == null:
		return "Club desconocido"
	var names = _display_metadata.get("club_names", {})
	return names.get(club_id, club_id)


func _update_header() -> void:
	var season_name = _display_metadata.get("season_name", _selection.season_id)
	var competition_name = _display_metadata.get(
		"competition_name", str(_selection.competition_id)
	)
	competition_title.text = "%s · %s" % [season_name, competition_name]
	var stage = "fase sin especificar" if _selection.stage_id == null \
		else "fase %s" % _selection.stage_id
	var group = "sin grupo" if _selection.group_id == null \
		else "grupo %s" % _selection.group_id
	scope_label.text = "%s · %s" % [stage, group]
	synthetic_badge.visible = _display_metadata.get("synthetic", false)


func _validate_selection(selection: Dictionary) -> Variant:
	for field in SELECTION_FIELDS:
		if not selection.has(field):
			return _failure("missing_selection", "Falta el campo de selección %s." % field)
	if not selection.season_id is String or selection.season_id.is_empty():
		return _failure("invalid_selection", "season_id debe ser una cadena no vacía.")
	for field in ["competition_id", "stage_id", "group_id"]:
		var value = selection[field]
		if value != null and not value is String:
			return _failure("invalid_selection", "%s debe ser String o null." % field)
	return null


func _validate_metadata(metadata: Dictionary) -> Variant:
	if metadata.has("club_names") and not metadata.club_names is Dictionary:
		return _failure("invalid_display_metadata", "club_names debe ser un diccionario.")
	if metadata.has("club_names"):
		for club_id in metadata.club_names:
			if not club_id is String or not metadata.club_names[club_id] is String:
				return _failure(
					"invalid_display_metadata",
					"club_names debe relacionar identificadores y nombres de tipo String."
				)
	if metadata.has("synthetic") and not metadata.synthetic is bool:
		return _failure("invalid_display_metadata", "synthetic debe ser booleano.")
	for field in ["season_name", "competition_name"]:
		if metadata.has(field) and not metadata[field] is String:
			return _failure("invalid_display_metadata", "%s debe ser una cadena." % field)
	return null


func _same_selection(left: Dictionary, right: Dictionary) -> bool:
	for field in SELECTION_FIELDS:
		if not right.has(field) or left[field] != right[field]:
			return false
	return true


func _same_calendar(left: Array[Fixture], right: Array[Fixture]) -> bool:
	if left.size() != right.size():
		return false
	var left_by_id = _fixtures_by_id(left)
	var right_by_id = _fixtures_by_id(right)
	if left_by_id.size() != left.size() or right_by_id.size() != right.size():
		return false
	if left_by_id.size() != right_by_id.size():
		return false
	for fixture_id in left_by_id:
		if not right_by_id.has(fixture_id) \
				or not _same_fixture(left_by_id[fixture_id], right_by_id[fixture_id]):
			return false
	return true


func _fixtures_by_id(fixtures: Array[Fixture]) -> Dictionary:
	var by_id: Dictionary = {}
	for fixture in fixtures:
		if by_id.has(fixture.fixture_id):
			return {}
		by_id[fixture.fixture_id] = fixture
	return by_id


func _same_fixture(left: Fixture, right: Fixture) -> bool:
	return left.fixture_id == right.fixture_id \
		and left.season_id == right.season_id \
		and left.competition_id == right.competition_id \
		and left.stage_id == right.stage_id \
		and left.group_id == right.group_id \
		and left.home_club_id == right.home_club_id \
		and left.away_club_id == right.away_club_id \
		and left.round_number == right.round_number \
		and left.scheduled_date == right.scheduled_date \
		and left.metadata == right.metadata


func _copy_fixtures(source: Array[Fixture]) -> Array[Fixture]:
	var copies: Array[Fixture] = []
	for original in source:
		var copy = Fixture.new()
		copy.fixture_id = original.fixture_id
		copy.season_id = original.season_id
		copy.competition_id = original.competition_id
		copy.stage_id = original.stage_id
		copy.group_id = original.group_id
		copy.home_club_id = original.home_club_id
		copy.away_club_id = original.away_club_id
		copy.round_number = original.round_number
		copy.scheduled_date = original.scheduled_date
		copy.metadata = original.metadata.duplicate(true)
		copies.append(copy)
	return copies


func _configure_demo() -> void:
	var clubs: Array[Club] = []
	for club_id in ["demo_aurora", "demo_brisa", "demo_cometa", "demo_duna"]:
		var club = Club.new()
		club.club_id = club_id
		club.season_id = "demo-season"
		club.division_id = "demo-division"
		clubs.append(club)
	var generated = Generator.new().generate(clubs, {
		"format": "round_robin", "season_id": "demo-season",
		"competition_id": "demo-league", "stage_id": "regular",
		"group_id": null, "legs": 1,
	})
	if not generated.ok:
		_show_result(generated)
		return
	var fixtures: Array[Fixture] = generated.data
	fixtures[0].scheduled_date = "2099-09-01"
	var rules = Rules.new()
	rules.season_id = "demo-season"
	rules.competition_id = "demo-league"
	rules.points_win = 3
	rules.points_draw = 1
	rules.points_loss = 0
	rules.team_count = 4
	rules.round_count = 3
	rules.tiebreakers = ["goal_difference", "head_to_head_points"]
	rules.competition_format = {
		"kind": "round_robin", "legs": 1, "head_to_head_policy": "single_pass"
	}
	var controller = Controller.new()
	var selection = {
		"season_id": "demo-season", "competition_id": "demo-league",
		"stage_id": "regular", "group_id": null,
	}
	var initialized = controller.initialize(clubs, fixtures, rules, selection)
	if not initialized.ok:
		_show_result(initialized)
		return
	var result = Result.new()
	result.fixture_id = fixtures[0].fixture_id
	result.season_id = "demo-season"
	result.home_goals = 2
	result.away_goals = 1
	result.status = Result.Status.FINAL
	var applied = controller.apply_round([result], fixtures[0].round_number)
	if not applied.ok:
		_show_result(applied)
		return
	configure(controller, fixtures, selection, {
		"season_name": "Temporada de demostración",
		"competition_name": "Liga sintética",
		"synthetic": true,
		"club_names": {
			"demo_aurora": "Aurora Ficticio", "demo_brisa": "Brisa Ficticio",
			"demo_cometa": "Cometa Ficticio", "demo_duna": "Duna Ficticio",
		},
	})


func _show_result(result: Dictionary) -> Dictionary:
	var messages: Array[String] = []
	for error in result.get("errors", []):
		messages.append("%s: %s" % [error.get("code", "error"), error.get("message", "")])
	error_label.text = "\n".join(messages) if not messages.is_empty() else "Error desconocido."
	error_label.visible = true
	return result


func _show_failure(code: String, message: String) -> Dictionary:
	return _show_result(_failure(code, message))


func _clear_error() -> void:
	error_label.text = ""
	error_label.visible = false


func _failure(code: String, message: String) -> Dictionary:
	return {"ok": false, "data": null, "errors": [{"code": code, "message": message}]}
