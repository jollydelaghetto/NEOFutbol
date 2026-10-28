class_name CompetitionRules
extends RefCounted

## Reglas de una competición por temporada.
## null significa «dato todavía no documentado».
## Los campos dinámicos permiten cargar números, listas y diccionarios.

## Identificador estable de la temporada.
var season_id: String = ""

## Identificador estable de la competición.
var competition_id = null

## Puntos otorgados por victoria.
var points_win = null

## Puntos otorgados por empate.
var points_draw = null

## Puntos otorgados por derrota.
var points_loss = null

## Número de equipos participantes.
var team_count = null

## Número de jornadas.
var round_count = null

## Criterios de desempate ordenados.
var tiebreakers = null

## Reglas de sustituciones.
var substitution_rules = null

## Reglas de ascensos, descensos y promociones.
var promotion_relegation_rules = null

## Formato de la competición.
var competition_format = null
