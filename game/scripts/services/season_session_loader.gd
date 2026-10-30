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
	var club_names = _load_club_names(
		source.pack_path.path_join("clubs.json"), source.clubs
	)
	if not club_names.ok:
		return club_names
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
				"club_names": club_names.data,
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


## Recupera metadatos visuales que ClubSeasonParser descarta deliberadamente.
## Un display_name ausente o inválido se omite: SeasonOverview usa club_id como
## alternativa. Nunca se normalizan nombres ni se aceptan clubes ajenos a la
## colección deportiva ya validada.
func _load_club_names(path: String, clubs: Array) -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _presentation_failure(
			"display_metadata_file_open", path, error_string(FileAccess.get_open_error())
		)
	var text = file.get_as_text()
	var read_error = file.get_error()
	file.close()
	if read_error != OK:
		return _presentation_failure(
			"display_metadata_file_read", path, error_string(read_error)
		)
	var json = JSON.new()
	if json.parse(text) != OK:
		var invalid_json = _presentation_failure(
			"display_metadata_json_syntax", path, json.get_error_message()
		)
		invalid_json.errors[0]["line"] = json.get_error_line()
		return invalid_json
	if not json.data is Array:
		return _presentation_failure(
			"display_metadata_invalid_root", path,
			"Los metadatos de clubes deben estar en una lista JSON."
		)

	var allowed: Dictionary = {}
	for club in clubs:
		if club != null and club.club_id is String and not club.club_id.is_empty():
			allowed[club.club_id] = club.season_id
	var names: Dictionary = {}
	for record in json.data:
		if not record is Dictionary:
			continue
		var club_id = record.get("club_id")
		if not club_id is String or not allowed.has(club_id):
			continue
		if record.get("season_id") != allowed[club_id] or not record.has("display_name"):
			continue
		var display_name = record.display_name
		if _valid_display_name(display_name):
			names[club_id] = display_name
	return {"ok": true, "data": names, "errors": []}


func _valid_display_name(value: Variant) -> bool:
	if not value is String or value.strip_edges().is_empty():
		return false
	for index in value.length():
		var codepoint = value.unicode_at(index)
		if codepoint < 32 or (codepoint >= 127 and codepoint <= 159):
			return false
	return true


func _presentation_failure(code: String, path: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"data": null,
		"errors": [{"code": code, "file": path, "message": message}],
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
