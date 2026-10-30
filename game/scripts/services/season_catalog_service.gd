class_name SeasonCatalogService
extends RefCounted

const ManifestParser = preload("res://game/scripts/infrastructure/season_manifest_parser.gd")
const ClubParser = preload("res://game/scripts/infrastructure/club_season_parser.gd")
const PlayerParser = preload("res://game/scripts/infrastructure/player_season_parser.gd")
const RulesParser = preload("res://game/scripts/infrastructure/competition_rules_parser.gd")
const FixtureParser = preload("res://game/scripts/infrastructure/match_fixture_parser.gd")
const PlayerReferences = preload(
	"res://game/scripts/infrastructure/player_club_reference_validator.gd"
)
const FixtureIntegrity = preload(
	"res://game/scripts/infrastructure/match_fixture_integrity_validator.gd"
)
const Controller = preload("res://game/scripts/services/season_controller.gd")

const DEFAULT_ROOT = "res://data/seasons"
const FIRST_START_YEAR = 1982
const LAST_START_YEAR = 2010
const REQUIRED_FILES = [
	"manifest.json", "rules.json", "clubs.json", "players.json", "fixtures.json"
]


## Devuelve siempre las 29 temporadas del horizonte, en orden cronológico.
## Cada entrada distingue presencia de archivos, validación estructural y
## referencial, y capacidad real de inicializar una SeasonController.
func get_catalog(root_path: String = DEFAULT_ROOT) -> Dictionary:
	var seasons: Array[Dictionary] = []
	for start_year in range(FIRST_START_YEAR, LAST_START_YEAR + 1):
		var season_id = _season_id(start_year)
		seasons.append(_inspect_season(root_path, season_id))
	return {
		"ok": true,
		"data": {
			"seasons": seasons,
			"root_path": root_path,
			"horizon": {
				"first_season_id": _season_id(FIRST_START_YEAR),
				"last_season_id": _season_id(LAST_START_YEAR),
				"count": seasons.size(),
			},
		},
		"errors": [],
	}


## Relee y prepara un pack sin confiar en consultas anteriores del catálogo.
## Esta API es la fuente única de los criterios de aptitud deportiva usados
## también por SeasonSessionLoader. Nunca devuelve un controlador parcial.
func prepare_playable_pack(season_id: String, root_path: String = DEFAULT_ROOT) -> Dictionary:
	var identifier = _validate_season_id(season_id)
	if not identifier.ok:
		return identifier
	var directory_path = root_path.path_join(season_id)
	var missing_content = _missing_required_files(directory_path)
	if not missing_content.is_empty():
		var result = _failure("missing_required_files",
			"El pack no contiene todos los archivos obligatorios.")
		result.errors[0]["missing_content"] = missing_content
		result.errors[0]["pack_path"] = directory_path
		return result
	var parsed = _parse_pack(directory_path, season_id)
	if not parsed.ok:
		return parsed
	return _prepare_validated_pack(parsed.data, season_id, directory_path)


func _inspect_season(root_path: String, season_id: String) -> Dictionary:
	var directory_path = root_path.path_join(season_id)
	var missing_content = _missing_required_files(directory_path)
	var present_count = REQUIRED_FILES.size() - missing_content.size()
	var discovered = DirAccess.dir_exists_absolute(directory_path) or present_count > 0
	var entry = {
		"season_id": season_id,
		"label": season_id,
		"in_project_horizon": true,
		"data_discovered": discovered,
		"data_validated": false,
		"validation_scope": "none",
		"provenance_declared": false,
		"playable": false,
		"status_code": "not_discovered",
		"status_label": "Datos no disponibles",
		"pack_path": directory_path,
		"missing_content": missing_content,
		"diagnostics": [],
	}
	if not discovered:
		entry.missing_content = REQUIRED_FILES.duplicate()
		return entry
	if not missing_content.is_empty():
		entry.status_code = "incomplete"
		entry.status_label = "Pack incompleto"
		return entry

	var parsed = _parse_pack(directory_path, season_id)
	if not parsed.ok:
		entry.status_code = "invalid"
		entry.status_label = "Datos no válidos"
		entry.diagnostics = parsed.errors.duplicate(true)
		return entry
	entry.data_validated = true
	entry.validation_scope = "structural_and_referential"
	entry.provenance_declared = not parsed.data.manifest.sources.is_empty() \
		and not parsed.data.manifest.checksum.is_empty()

	var readiness = _prepare_validated_pack(parsed.data, season_id, directory_path)
	if not readiness.ok:
		entry.status_code = "validated_not_playable"
		entry.status_label = "Datos validados; inicio no disponible"
		entry.diagnostics = readiness.errors.duplicate(true)
		return entry
	entry.playable = true
	entry.status_code = "playable"
	entry.status_label = "Temporada disponible"
	return entry


func _parse_pack(directory_path: String, season_id: String) -> Dictionary:
	var manifest_result = ManifestParser.new().parse_file(
		directory_path.path_join("manifest.json")
	)
	if not manifest_result.ok:
		return manifest_result
	if manifest_result.data.season_id != season_id:
		return _failure("manifest_season_mismatch",
			"El manifest no corresponde al directorio de la temporada.")

	var clubs_result = ClubParser.new().parse_file(
		directory_path.path_join("clubs.json"), season_id
	)
	if not clubs_result.ok:
		return clubs_result
	var players_result = PlayerParser.new().parse_file(
		directory_path.path_join("players.json"), season_id
	)
	if not players_result.ok:
		return players_result
	var rules_result = RulesParser.new().parse_file(
		directory_path.path_join("rules.json"), season_id
	)
	if not rules_result.ok:
		return rules_result
	var fixtures_result = FixtureParser.new().parse_file(
		directory_path.path_join("fixtures.json"), season_id
	)
	if not fixtures_result.ok:
		return fixtures_result

	var player_references = PlayerReferences.new().validate(
		clubs_result.data, players_result.data
	)
	if not player_references.ok:
		return {"ok": false, "data": null, "errors": player_references.errors}
	var fixture_integrity = FixtureIntegrity.new().validate(
		clubs_result.data, fixtures_result.data
	)
	if not fixture_integrity.ok:
		return {"ok": false, "data": null, "errors": fixture_integrity.errors}
	return {
		"ok": true,
		"data": {
			"manifest": manifest_result.data,
			"clubs": clubs_result.data,
			"players": players_result.data,
			"rules": rules_result.data,
			"fixtures": fixtures_result.data,
		},
		"errors": [],
	}


## La validación del pack no implica que pueda iniciarse. Para declararlo
## jugable se exige trazabilidad declarada, contenido deportivo no vacío y una
## selección exacta que la API pública de SeasonController acepte.
func _prepare_validated_pack(pack: Dictionary, season_id: String,
		directory_path: String) -> Dictionary:
	if pack.manifest.sources.is_empty() or pack.manifest.checksum.is_empty():
		return _failure("missing_provenance",
			"El manifest no declara fuentes y checksum suficientes.")
	if pack.clubs.size() < 2:
		return _failure("insufficient_clubs",
			"Se necesitan al menos dos clubes para iniciar la temporada.")
	if pack.fixtures.is_empty():
		return _failure("empty_calendar", "El calendario no contiene partidos.")
	var rules = pack.rules
	if not rules.competition_id is String or rules.competition_id.is_empty():
		return _failure("unknown_competition",
			"Las reglas no identifican una competición jugable.")
	for field in ["points_win", "points_draw", "points_loss"]:
		if rules.get(field) == null:
			return _failure("incomplete_scoring_rules",
				"Falta una regla de puntuación necesaria: %s." % field)
	if not rules.tiebreakers is Array or not rules.competition_format is Dictionary:
		return _failure("incomplete_competition_rules",
			"Faltan los desempates o el formato de competición.")

	var selections: Array[Dictionary] = []
	for fixture in pack.fixtures:
		if fixture.competition_id == rules.competition_id:
			if fixture.home_club_id == null or fixture.away_club_id == null:
				return _failure("incomplete_fixture_clubs",
					"Un partido de la competición no identifica ambos clubes.")
			var candidate = {
				"season_id": season_id,
				"competition_id": rules.competition_id,
				"stage_id": fixture.stage_id,
				"group_id": fixture.group_id,
			}
			if not candidate in selections:
				selections.append(candidate)
	if selections.is_empty():
		return _failure("calendar_without_rules",
			"Ningún partido corresponde a la competición de las reglas.")
	if selections.size() > 1:
		var ambiguous = _failure("ambiguous_sporting_selection",
			"El pack contiene varias fases o grupos compatibles con las mismas reglas.")
		ambiguous.errors[0]["selection_count"] = selections.size()
		return ambiguous
	var selection = selections[0]
	var controller = Controller.new()
	var initialized = controller.initialize(
		pack.clubs, pack.fixtures, rules, selection
	)
	if not initialized.ok:
		return {"ok": false, "data": null, "errors": initialized.errors.duplicate(true)}
	return {
		"ok": true,
		"data": {
			"season_id": season_id,
			"selection": selection.duplicate(true),
			"controller": controller,
			"manifest": pack.manifest,
			"clubs": pack.clubs,
			"players": pack.players,
			"rules": pack.rules,
			"fixtures": pack.fixtures,
			"pack_path": directory_path,
		},
		"errors": [],
	}


func _validate_season_id(season_id: String) -> Dictionary:
	var format = RegEx.new()
	format.compile("^[0-9]{4}-[0-9]{2}$")
	if format.search(season_id) == null:
		return _failure("invalid_season_id",
			"El identificador de temporada no tiene el formato permitido.")
	for start_year in range(FIRST_START_YEAR, LAST_START_YEAR + 1):
		if season_id == _season_id(start_year):
			return {"ok": true, "data": season_id, "errors": []}
	return _failure("season_out_of_horizon",
		"La temporada no pertenece al horizonte 1982-83 a 2010-11.")


func _missing_required_files(directory_path: String) -> Array[String]:
	var missing: Array[String] = []
	for file_name in REQUIRED_FILES:
		if not FileAccess.file_exists(directory_path.path_join(file_name)):
			missing.append(file_name)
	return missing


func _season_id(start_year: int) -> String:
	return "%d-%02d" % [start_year, (start_year + 1) % 100]


func _failure(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"data": null,
		"errors": [{"code": code, "message": message}],
	}
