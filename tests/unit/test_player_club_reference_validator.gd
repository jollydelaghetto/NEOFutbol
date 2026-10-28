extends SceneTree

const Validator = preload("res://game/scripts/infrastructure/player_club_reference_validator.gd")
const Club = preload("res://game/scripts/data/club_season.gd")
const Player = preload("res://game/scripts/data/player_season.gd")

var failures: Array[String] = []
var checks = 0


func _initialize() -> void:
	var validator = Validator.new()
	var clubs: Array[Club] = [_club("club_a", "season_a", "division_a")]
	var players: Array[Player] = [_player("player_a", "season_a", "club_a")]
	var result = validator.validate(clubs, players)
	_check(result == {"ok": true, "errors": []}, "referencia existente")

	players = [_player("missing_player", "season_a", "missing_club")]
	result = validator.validate(clubs, players)
	_expect_missing(result, 0, "missing_player", "season_a", "missing_club")

	clubs = [_club("club_a", "other_season", "division_a")]
	players = [_player("player_a", "season_a", "club_a")]
	result = validator.validate(clubs, players)
	_expect_missing(result, 0, "player_a", "season_a", "club_a")

	clubs = [_club("club_a", "season_a", "division_a")]
	players = [
		_player("player_a", "season_a", "club_a"),
		_player("player_b", "season_a", "club_a"),
	]
	_check(validator.validate(clubs, players).ok, "varios jugadores del mismo club")

	clubs = [
		_club("shared_club", "season_a", "division_a"),
		_club("shared_club", "season_b", "division_b"),
	]
	players = [
		_player("player_a", "season_a", "shared_club"),
		_player("player_b", "season_b", "shared_club"),
	]
	_check(validator.validate(clubs, players).ok, "mismo club en distintas temporadas")

	var empty_clubs: Array[Club] = []
	var empty_players: Array[Player] = []
	_check(validator.validate(empty_clubs, empty_players) == {"ok": true, "errors": []},
		"colecciones vacías")
	_check(validator.validate(clubs, empty_players) == {"ok": true, "errors": []},
		"clubes sin jugadores")

	clubs = [
		_club("first_club", "season_a", "first_division"),
		_club("second_club", "season_a", "second_division"),
	]
	players = [
		_player("first_player", "season_a", "first_club"),
		_player("second_player", "season_a", "second_club"),
	]
	_check(validator.validate(clubs, players).ok, "varias divisiones sin inferencias")

	clubs = [
		_club("Exact_Club", "Exact_Season", "division_a"),
		_club(" exact_club ", " exact_season ", "division_b"),
	]
	players = [
		_player("upper_player", "Exact_Season", "Exact_Club"),
		_player("space_player", " exact_season ", " exact_club "),
	]
	_check(validator.validate(clubs, players).ok, "mayúsculas y espacios exactos")
	players = [
		_player("case_player", "Exact_Season", "exact_club"),
		_player("trim_player", " exact_season ", "exact_club"),
	]
	result = validator.validate(clubs, players)
	_check(not result.ok and result.errors.size() == 2, "sin normalización de identificadores")
	_expect_diagnostic(result.errors[0], 0, "case_player", "Exact_Season", "exact_club")
	_expect_diagnostic(result.errors[1], 1, "trim_player", " exact_season ", "exact_club")

	clubs = [_club("known_club", "season_a", "division_a")]
	players = [
		_player("valid_player", "season_a", "known_club"),
		_player("missing_first", "season_a", "missing_a"),
		_player("missing_second", "season_b", "known_club"),
		_player("missing_third", "season_b", "missing_b"),
	]
	var club_snapshot = _snapshot_clubs(clubs)
	var player_snapshot = _snapshot_players(players)
	var club_identity = clubs[0]
	var player_identity = players[0]
	result = validator.validate(clubs, players)
	_check(not result.ok and result.errors.size() == 3, "varios errores de referencia")
	_expect_diagnostic(result.errors[0], 1, "missing_first", "season_a", "missing_a")
	_expect_diagnostic(result.errors[1], 2, "missing_second", "season_b", "known_club")
	_expect_diagnostic(result.errors[2], 3, "missing_third", "season_b", "missing_b")
	_check(result == validator.validate(clubs, players), "diagnósticos deterministas")
	_check(_snapshot_clubs(clubs) == club_snapshot, "clubes sin modificar")
	_check(_snapshot_players(players) == player_snapshot, "jugadores sin modificar")
	_check(clubs[0] == club_identity and players[0] == player_identity, "identidad de objetos conservada")

	if failures.is_empty():
		print("PASS: %d comprobaciones" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)


func _club(club_id: String, season_id: String, division_id: String) -> Club:
	var club = Club.new()
	club.club_id = club_id
	club.season_id = season_id
	club.division_id = division_id
	return club


func _player(player_id: String, season_id: String, club_id: String) -> Player:
	var player = Player.new()
	player.player_id = player_id
	player.season_id = season_id
	player.club_id = club_id
	player.historical_data = {"synthetic": true}
	player.game_data = {"rating": 50}
	player.metadata = {"source": "test"}
	return player


func _expect_missing(result: Dictionary, index: int, player_id: String,
		season_id: String, club_id: String) -> void:
	_check(not result.ok and result.errors.size() == 1, "una referencia inexistente")
	if result.errors.size() == 1:
		_expect_diagnostic(result.errors[0], index, player_id, season_id, club_id)


func _expect_diagnostic(error: Dictionary, index: int, player_id: String,
		season_id: String, club_id: String) -> void:
	_check(error == {
		"code": "missing_club_reference",
		"message": "El jugador referencia un club inexistente en su temporada.",
		"index": index,
		"player_id": player_id,
		"season_id": season_id,
		"club_id": club_id,
	}, "diagnóstico estable y localizable")


func _snapshot_clubs(clubs: Array[Club]) -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for club in clubs:
		snapshot.append({
			"club_id": club.club_id,
			"season_id": club.season_id,
			"division_id": club.division_id,
		})
	return snapshot


func _snapshot_players(players: Array[Player]) -> Array[Dictionary]:
	var snapshot: Array[Dictionary] = []
	for player in players:
		snapshot.append({
			"player_id": player.player_id,
			"season_id": player.season_id,
			"club_id": player.club_id,
			"historical_data": player.historical_data.duplicate(true),
			"game_data": player.game_data.duplicate(true),
			"metadata": player.metadata.duplicate(true),
		})
	return snapshot


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
