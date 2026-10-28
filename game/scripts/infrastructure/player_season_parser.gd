class_name PlayerSeasonParser
extends RefCounted

const Player = preload("res://game/scripts/data/player_season.gd")
const IDENTIFIERS = ["player_id", "season_id", "club_id"]
const CONTAINERS = ["historical_data", "game_data", "metadata"]
const REQUIRED = IDENTIFIERS + CONTAINERS

## Devuelve {ok: bool, data: Array[PlayerSeason] o null, errors: Array}.
## La unicidad por jugador y temporada es provisional; no representa traspasos.
## Los diccionarios se copian profundamente, sin interpretar su contenido.
## [] es válido y no certifica la cobertura histórica del pack.
## El primer diagnóstico contiene code, file, message y, cuando corresponda,
## index (base cero), field, line o first_index.
## Códigos: file_open, file_read, json_syntax, invalid_root, invalid_record,
## missing_field, invalid_type, season_mismatch, duplicate_field, duplicate_player.
func parse_file(path: String, expected_season_id: String = "") -> Dictionary:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("file_open", path, error_string(FileAccess.get_open_error()))
	var text = file.get_as_text()
	var read_error = file.get_error()
	file.close()
	if read_error != OK:
		return _failure("file_read", path, error_string(read_error))
	var json = JSON.new()
	if json.parse(text) != OK:
		var result = _failure("json_syntax", path, json.get_error_message())
		result.errors[0]["line"] = json.get_error_line()
		return result
	if not json.data is Array:
		return _failure("invalid_root", path, "La raíz debe ser una lista JSON.")
	var records: Array = json.data
	var duplicates = _duplicate_fields(text)
	var seen: Dictionary = {}
	for index in records.size():
		var record = records[index]
		if not record is Dictionary:
			return _failure("invalid_record", path, "El registro debe ser un objeto JSON.", index)
		if duplicates.has(index):
			return _failure("duplicate_field", path, "Campo obligatorio duplicado.", index, duplicates[index])
		for field in REQUIRED:
			if not record.has(field):
				return _failure("missing_field", path, "Falta el campo obligatorio.", index, field)
			if field in IDENTIFIERS and (not record[field] is String or record[field].strip_edges().is_empty()):
				return _failure("invalid_type", path, "Debe ser una cadena no vacía.", index, field)
		for field in CONTAINERS:
			if not record[field] is Dictionary:
				return _failure("invalid_type", path, "Debe ser un diccionario, no null.", index, field)
		if not expected_season_id.is_empty() and record.season_id != expected_season_id:
			return _failure("season_mismatch", path, "La temporada no coincide con la esperada.", index, "season_id")
		if not seen.has(record.season_id):
			seen[record.season_id] = {}
		var season: Dictionary = seen[record.season_id]
		if season.has(record.player_id):
			var result = _failure("duplicate_player", path, "Jugador repetido en la misma temporada.", index, "player_id")
			result.errors[0]["first_index"] = season[record.player_id]
			return result
		season[record.player_id] = index
	# Solo construye los modelos después de validar todos los registros.
	var players: Array[Player] = []
	for record in records:
		var player = Player.new()
		player.player_id = record.player_id
		player.season_id = record.season_id
		player.club_id = record.club_id
		player.historical_data = record.historical_data.duplicate(true)
		player.game_data = record.game_data.duplicate(true)
		player.metadata = record.metadata.duplicate(true)
		players.append(player)
	return {"ok": true, "data": players, "errors": []}


func _failure(code: String, path: String, message: String, index: int = -1, field: String = "") -> Dictionary:
	var diagnostic = {"code": code, "file": path, "message": message}
	if index >= 0:
		diagnostic["index"] = index
	if not field.is_empty():
		diagnostic["field"] = field
	return {"ok": false, "data": null, "errors": [diagnostic]}


## Tras JSON.parse, examina las claves originales de objetos directamente
## contenidos en la lista. Ignora objetos anidados y decodifica escapes JSON.
func _duplicate_fields(text: String) -> Dictionary:
	var lexer = RegEx.new()
	lexer.compile('"([^"\\\\]|\\\\.)*"|[{}\\[\\]:,]|[^\\s{}\\[\\]:,]+')
	var matches = lexer.search_all(text)
	var depth = 0
	var index = 0
	var record_is_object = false
	var seen: Dictionary = {}
	var duplicates: Dictionary = {}
	for position in matches.size():
		var token = matches[position].get_string()
		if depth == 1 and token == ",":
			index += 1
		if depth == 1 and token in ["{", "["]:
			record_is_object = token == "{"
			seen = {}
		if depth == 2 and record_is_object and token.begins_with('"') \
				and position + 1 < matches.size() and matches[position + 1].get_string() == ":":
			var key = JSON.parse_string(token)
			if key in REQUIRED:
				if seen.has(key) and not duplicates.has(index):
					duplicates[index] = key
				seen[key] = true
		if token == "{" or token == "[":
			depth += 1
		elif token == "}" or token == "]":
			depth -= 1
	return duplicates
