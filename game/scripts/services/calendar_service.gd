class_name CalendarService
extends RefCounted

const Fixture = preload("res://game/scripts/data/match_fixture.gd")

enum Order {
	ORIGINAL,
	ROUND,
	DATE,
	FIXTURE_ID,
}

## Selecciona los partidos de season_id mediante comparaciones exactas.
## filters admite exclusivamente competition_id, stage_id y group_id. Una clave
## ausente no filtra ese campo; una clave presente con null busca null.
## order_by acepta los valores de Order. Los valores null se colocan al final al
## ordenar por jornada o fecha, y los empates conservan el índice de entrada.
func get_fixtures(fixtures: Array[Fixture], season_id: String,
		filters: Dictionary = {}, order_by: int = Order.ORIGINAL) -> Array[Fixture]:
	var selected: Array[Fixture] = []
	for fixture in fixtures:
		if fixture.season_id == season_id and _matches_filters(fixture, filters):
			selected.append(fixture)
	return _ordered(selected, order_by)


## Devuelve los partidos de una jornada conocida dentro de la selección.
## Los partidos con round_number null no coinciden con una jornada concreta.
func get_round_fixtures(fixtures: Array[Fixture], season_id: String, round_number: int,
		filters: Dictionary = {}, order_by: int = Order.ORIGINAL) -> Array[Fixture]:
	var selected: Array[Fixture] = []
	for fixture in get_fixtures(fixtures, season_id, filters):
		if fixture.round_number == round_number:
			selected.append(fixture)
	return _ordered(selected, order_by)


## Devuelve las jornadas conocidas, sin duplicados y en orden numérico.
func get_round_numbers(fixtures: Array[Fixture], season_id: String,
		filters: Dictionary = {}) -> Array[int]:
	var seen: Dictionary = {}
	for fixture in get_fixtures(fixtures, season_id, filters):
		if fixture.round_number != null:
			seen[fixture.round_number] = true
	var rounds: Array[int] = []
	for round_number in seen:
		rounds.append(round_number)
	rounds.sort()
	return rounds


## Devuelve los partidos donde club_id aparece como local o visitante.
func get_club_fixtures(fixtures: Array[Fixture], season_id: String, club_id: String,
		filters: Dictionary = {}, order_by: int = Order.ORIGINAL) -> Array[Fixture]:
	var selected: Array[Fixture] = []
	for fixture in get_fixtures(fixtures, season_id, filters):
		if fixture.home_club_id == club_id or fixture.away_club_id == club_id:
			selected.append(fixture)
	return _ordered(selected, order_by)


func _matches_filters(fixture: Fixture, filters: Dictionary) -> bool:
	for field in ["competition_id", "stage_id", "group_id"]:
		if filters.has(field) and fixture.get(field) != filters[field]:
			return false
	return true


func _ordered(fixtures: Array[Fixture], order_by: int) -> Array[Fixture]:
	var result: Array[Fixture] = fixtures.duplicate()
	if order_by == Order.ORIGINAL or result.size() < 2:
		return result
	var entries: Array[Dictionary] = []
	for index in result.size():
		entries.append({"fixture": result[index], "index": index})
	match order_by:
		Order.ROUND:
			entries.sort_custom(_round_before)
		Order.DATE:
			entries.sort_custom(_date_before)
		Order.FIXTURE_ID:
			entries.sort_custom(_fixture_id_before)
		_:
			return result
	result.clear()
	for entry in entries:
		result.append(entry.fixture)
	return result


func _round_before(left: Dictionary, right: Dictionary) -> bool:
	return _nullable_before(
		left.fixture.round_number, right.fixture.round_number, left.index, right.index
	)


func _date_before(left: Dictionary, right: Dictionary) -> bool:
	return _nullable_before(
		left.fixture.scheduled_date, right.fixture.scheduled_date, left.index, right.index
	)


func _fixture_id_before(left: Dictionary, right: Dictionary) -> bool:
	if left.fixture.fixture_id == right.fixture.fixture_id:
		return left.index < right.index
	return left.fixture.fixture_id < right.fixture.fixture_id


func _nullable_before(left: Variant, right: Variant, left_index: int, right_index: int) -> bool:
	if left == null:
		return right == null and left_index < right_index
	if right == null:
		return true
	if left == right:
		return left_index < right_index
	return left < right
