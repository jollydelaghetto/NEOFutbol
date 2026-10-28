class_name PlayerSeason
extends RefCounted

## Identificador estable del jugador.
var player_id: String = ""

## Identificador estable de la temporada.
var season_id: String = ""

## Identificador estable del club en esta temporada.
var club_id: String = ""

## Hechos históricos documentados; los valores desconocidos se conservan como null.
var historical_data: Dictionary = {}

## Atributos y valores económicos del videojuego; los desconocidos se conservan como null.
var game_data: Dictionary = {}

## Fuentes, confianza, revisión y datos de presentación; los desconocidos se conservan como null.
var metadata: Dictionary = {}
