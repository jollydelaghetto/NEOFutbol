class_name ManagerSquad
extends Control

const Player = preload("res://game/scripts/data/player_season.gd")

signal back_requested

@onready var season_label: Label = %SeasonLabel
@onready var club_label: Label = %ClubLabel
@onready var warning_label: Label = %WarningLabel
@onready var count_label: Label = %CountLabel
@onready var players_tree: Tree = %PlayersTree
@onready var empty_label: Label = %EmptyLabel
@onready var error_label: Label = %ErrorLabel
@onready var back_button: Button = %BackButton

var _players: Array[Player] = []
var _selection: Dictionary = {}
var _presentation: Dictionary = {}
var _club_id := ""


func _ready() -> void:
	back_button.pressed.connect(func(): back_requested.emit())
	players_tree.set_column_title(0, "Jugador")
	players_tree.set_column_title(1, "Identificador")
	players_tree.set_column_title(2, "Datos deportivos")
	players_tree.set_column_expand(0, true)
	players_tree.set_column_expand(1, true)
	players_tree.set_column_expand(2, true)
	players_tree.focus_next = players_tree.get_path_to(back_button)
	players_tree.focus_previous = players_tree.get_path_to(back_button)
	back_button.focus_next = back_button.get_path_to(players_tree)
	back_button.focus_previous = back_button.get_path_to(players_tree)


## Presenta una copia de los PlayerSeason ya validados para la sesión. Esta
## vista no lee datos ni interpreta campos deportivos sin contrato visible.
func configure(players: Array[Player], selection: Dictionary,
		presentation: Dictionary, club_id: String) -> Dictionary:
	if not is_node_ready():
		return _failure("view_not_ready", "La Plantilla todavía no está preparada.")
	for field in ["season_id", "competition_id", "stage_id", "group_id"]:
		if not selection.has(field):
			return _show_failure("invalid_selection", "Falta el campo de selección %s." % field)
	if club_id.is_empty():
		return _show_failure("missing_assigned_club", "Debe existir un club seleccionado.")
	var club_names = presentation.get("club_names")
	if not club_names is Dictionary or not _valid_display_name(club_names.get(club_id)):
		return _show_failure(
			"missing_club_display_name", "El club seleccionado no tiene un nombre visible validado."
		)

	var selected: Array[Player] = []
	for original in players:
		if original == null:
			continue
		if original.season_id == selection.season_id and original.club_id == club_id:
			selected.append(_copy_player(original))
	selected.sort_custom(func(left: Player, right: Player):
		return left.player_id < right.player_id)

	_players = selected
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
			"player_count": _players.size(),
		},
		"errors": [],
	}


func focus_initial_control() -> void:
	if _players.is_empty():
		back_button.grab_focus()
	else:
		players_tree.grab_focus()


func get_context() -> Dictionary:
	return {
		"selection": _selection.duplicate(true),
		"club_id": _club_id,
		"player_ids": _players.map(func(player: Player): return player.player_id),
	}


func _render() -> void:
	season_label.text = "Temporada técnica %s" % _selection.season_id
	club_label.text = "Plantilla de %s" % _presentation.club_names[_club_id]
	warning_label.text = "MODO DESARROLLO — DATOS SINTÉTICOS"
	count_label.text = "%d jugador%s disponible%s · cobertura parcial del pack sintético" % [
		_players.size(), "" if _players.size() == 1 else "es",
		"" if _players.size() == 1 else "s",
	]
	players_tree.clear()
	var root_item = players_tree.create_item()
	for player in _players:
		var item = players_tree.create_item(root_item)
		item.set_text(0, _player_name(player))
		item.set_text(1, player.player_id)
		item.set_text(2, _data_summary(player))
		item.set_metadata(0, {
			"player_id": player.player_id,
			"season_id": player.season_id,
			"club_id": player.club_id,
		})
	players_tree.visible = not _players.is_empty()
	empty_label.visible = _players.is_empty()
	empty_label.text = "No hay jugadores disponibles para este club en el pack validado."


func _player_name(player: Player) -> String:
	var candidate = player.metadata.get("display_name")
	return candidate if _valid_display_name(candidate) else player.player_id


func _data_summary(player: Player) -> String:
	if player.historical_data.is_empty() and player.game_data.is_empty():
		return "Sin datos"
	return "Datos documentados"


func _valid_display_name(value: Variant) -> bool:
	if not value is String or value.strip_edges().is_empty():
		return false
	for index in value.length():
		var codepoint = value.unicode_at(index)
		if codepoint < 32 or (codepoint >= 127 and codepoint <= 159):
			return false
	return true


func _copy_player(original: Player) -> Player:
	var copied = Player.new()
	copied.player_id = original.player_id
	copied.season_id = original.season_id
	copied.club_id = original.club_id
	copied.historical_data = original.historical_data.duplicate(true)
	copied.game_data = original.game_data.duplicate(true)
	copied.metadata = original.metadata.duplicate(true)
	return copied


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
