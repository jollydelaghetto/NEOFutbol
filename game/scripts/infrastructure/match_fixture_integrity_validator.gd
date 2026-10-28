class_name MatchFixtureIntegrityValidator
extends RefCounted

const Club = preload("res://game/scripts/data/club_season.gd")
const Fixture = preload("res://game/scripts/data/match_fixture.gd")

## Comprueba referencias y reglas lógicas básicas de MatchFixture ya interpretados.
## Las referencias de club se comparan mediante la pareja exacta
## (season_id, club_id). Un identificador null permanece desconocido y no genera
## un error de referencia; el otro lado del partido se valida si es conocido.
## Devuelve {ok: bool, errors: Array[Dictionary]}. Los diagnósticos conservan el
## orden de los partidos e incluyen index (base cero), fixture_id y season_id.
func validate(clubs: Array[Club], fixtures: Array[Fixture]) -> Dictionary:
	var clubs_by_season: Dictionary = {}
	for club in clubs:
		if not clubs_by_season.has(club.season_id):
			clubs_by_season[club.season_id] = {}
		clubs_by_season[club.season_id][club.club_id] = true

	var seen_fixtures: Dictionary = {}
	var errors: Array[Dictionary] = []
	for index in fixtures.size():
		var fixture = fixtures[index]
		var season_clubs: Dictionary = clubs_by_season.get(fixture.season_id, {})
		if fixture.home_club_id != null and not season_clubs.has(fixture.home_club_id):
			errors.append(_club_error(
				"missing_home_club_reference",
				"El club local no existe en la temporada del partido.",
				index,
				fixture,
				fixture.home_club_id,
			))
		if fixture.away_club_id != null and not season_clubs.has(fixture.away_club_id):
			errors.append(_club_error(
				"missing_away_club_reference",
				"El club visitante no existe en la temporada del partido.",
				index,
				fixture,
				fixture.away_club_id,
			))
		if fixture.home_club_id != null and fixture.away_club_id != null \
				and fixture.home_club_id == fixture.away_club_id:
			errors.append(_club_error(
				"self_match",
				"Un club no puede enfrentarse a sí mismo.",
				index,
				fixture,
				fixture.home_club_id,
			))

		if not seen_fixtures.has(fixture.season_id):
			seen_fixtures[fixture.season_id] = {}
		var season_fixtures: Dictionary = seen_fixtures[fixture.season_id]
		if season_fixtures.has(fixture.fixture_id):
			errors.append({
				"code": "duplicate_fixture",
				"message": "El identificador de partido está duplicado en la misma temporada.",
				"index": index,
				"first_index": season_fixtures[fixture.fixture_id],
				"fixture_id": fixture.fixture_id,
				"season_id": fixture.season_id,
			})
		else:
			season_fixtures[fixture.fixture_id] = index

	return {"ok": errors.is_empty(), "errors": errors}


func _club_error(code: String, message: String, index: int,
		fixture: Fixture, club_id: String) -> Dictionary:
	return {
		"code": code,
		"message": message,
		"index": index,
		"fixture_id": fixture.fixture_id,
		"season_id": fixture.season_id,
		"club_id": club_id,
	}
