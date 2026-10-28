class_name MatchFixture
extends RefCounted

## Identificador estable del encuentro; se conserva al reprogramarlo.
var fixture_id: String = ""

## Identificador estable de la temporada.
var season_id: String = ""

## Identificador estable de la competición: String conocido o null.
var competition_id = null

## Identificador de fase para formatos con varias fases: String conocido o null.
var stage_id = null

## Identificador de grupo dentro de la fase: String conocido o null.
var group_id = null

## Identificador estable del club local: String conocido o null.
var home_club_id = null

## Identificador estable del club visitante: String conocido o null.
var away_club_id = null

## Jornada dentro de la fase y grupo: int conocido o null.
var round_number = null

## Fecha prevista completa: String YYYY-MM-DD o null si se desconoce.
var scheduled_date = null

## Fuentes, confianza, revisión y aclaraciones del calendario; desconocidos como null.
var metadata: Dictionary = {}
