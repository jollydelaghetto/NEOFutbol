class_name MatchResult
extends RefCounted

enum Status {
	PENDING,
	FINAL,
}

## Identificador del partido al que pertenece el resultado.
var fixture_id: String = ""

## Identificador estable de la temporada.
var season_id: String = ""

## Marcador local: int conocido o null mientras está pendiente.
var home_goals = null

## Marcador visitante: int conocido o null mientras está pendiente.
var away_goals = null

## Estado explícito; los únicos valores admitidos son Status.PENDING y Status.FINAL.
var status: int = Status.PENDING
