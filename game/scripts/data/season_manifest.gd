class_name SeasonManifest
extends RefCounted

## Versión del esquema del manifiesto.
var schema_version: int = 1

## Identificador estable de la temporada.
var season_id: String = ""

## Fuentes de los datos de la temporada.
var sources: Array = []

## Sumas de comprobación del contenido del paquete.
var checksum: Dictionary = {}
