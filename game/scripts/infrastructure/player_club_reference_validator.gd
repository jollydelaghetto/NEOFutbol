class_name PlayerClubReferenceValidator
extends RefCounted

const Club = preload("res://game/scripts/data/club_season.gd")
const Player = preload("res://game/scripts/data/player_season.gd")

## Comprueba que cada PlayerSeason referencia un ClubSeason mediante la pareja
## exacta (season_id, club_id). Devuelve {ok: bool, errors: Array[Dictionary]}.
## Los diagnósticos conservan el orden de los jugadores y contienen code,
## message, index (base cero), player_id, season_id y club_id.
func validate(clubs: Array[Club], players: Array[Player]) -> Dictionary:
	var clubs_by_season: Dictionary = {}
	for club in clubs:
		if not clubs_by_season.has(club.season_id):
			clubs_by_season[club.season_id] = {}
		clubs_by_season[club.season_id][club.club_id] = true

	var errors: Array[Dictionary] = []
	for index in players.size():
		var player = players[index]
		var season_clubs: Dictionary = clubs_by_season.get(player.season_id, {})
		if not season_clubs.has(player.club_id):
			errors.append({
				"code": "missing_club_reference",
				"message": "El jugador referencia un club inexistente en su temporada.",
				"index": index,
				"player_id": player.player_id,
				"season_id": player.season_id,
				"club_id": player.club_id,
			})
	return {"ok": errors.is_empty(), "errors": errors}
