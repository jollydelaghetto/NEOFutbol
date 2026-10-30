class_name SeasonSessionLoader
extends RefCounted

const Catalog = preload("res://game/scripts/services/season_catalog_service.gd")
const Fixture = preload("res://game/scripts/data/match_fixture.gd")


## Relee, valida y prepara una sesión deportiva nueva. data contiene season_id,
## selection, controller, calendar, presentation y origin. Los metadatos de
## origen describen declaraciones del pack; no certifican hashes ni derechos.
func prepare_session(season_id: String,
		root_path: String = Catalog.DEFAULT_ROOT) -> Dictionary:
	var prepared = Catalog.new().prepare_playable_pack(season_id, root_path)
	if not prepared.ok:
		return {"ok": false, "data": null, "errors": prepared.errors.duplicate(true)}
	var source = prepared.data
	var manifest = source.manifest
	return {
		"ok": true,
		"data": {
			"season_id": season_id,
			"selection": source.selection.duplicate(true),
			"controller": source.controller,
			"calendar": _copy_fixtures(source.fixtures),
			"presentation": {
				"season_name": season_id,
				"competition_name": source.selection.competition_id,
			},
			"origin": {
				"root_path": root_path,
				"pack_path": source.pack_path,
				"schema_version": manifest.schema_version,
				"sources": manifest.sources.duplicate(true),
				"checksum": manifest.checksum.duplicate(true),
				"checksum_verified": false,
				"reuse_rights_verified": false,
			},
		},
		"errors": [],
	}


func _copy_fixtures(source: Array[Fixture]) -> Array[Fixture]:
	var copied: Array[Fixture] = []
	for original in source:
		var fixture = Fixture.new()
		fixture.fixture_id = original.fixture_id
		fixture.season_id = original.season_id
		fixture.competition_id = original.competition_id
		fixture.stage_id = original.stage_id
		fixture.group_id = original.group_id
		fixture.home_club_id = original.home_club_id
		fixture.away_club_id = original.away_club_id
		fixture.round_number = original.round_number
		fixture.scheduled_date = original.scheduled_date
		fixture.metadata = original.metadata.duplicate(true)
		copied.append(fixture)
	return copied
