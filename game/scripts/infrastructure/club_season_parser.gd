class_name ClubSeasonParser
extends RefCounted

const Club = preload("res://game/scripts/data/club_season.gd")
const REQUIRED = ["club_id", "season_id", "division_id"]

## Devuelve {ok: bool, data: Array[ClubSeason] o null, errors: Array}.
## [] es válido y no certifica la cobertura histórica del pack.
## El primer diagnóstico contiene code, file, message y, cuando corresponda,
## index (base cero), field, line o first_index.
## Códigos: file_open, file_read, json_syntax, invalid_root, invalid_record,
## missing_field, invalid_type, season_mismatch, duplicate_field, duplicate_club.
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
			if not record[field] is String or record[field].strip_edges().is_empty():
				return _failure("invalid_type", path, "Debe ser una cadena no vacía.", index, field)
		if not expected_season_id.is_empty() and record.season_id != expected_season_id:
			return _failure("season_mismatch", path, "La temporada no coincide con la esperada.", index, "season_id")
		if not seen.has(record.season_id):
			seen[record.season_id] = {}
		var season: Dictionary = seen[record.season_id]
		if season.has(record.club_id):
			var result = _failure("duplicate_club", path, "Club repetido en la misma temporada.", index, "club_id")
			result.errors[0]["first_index"] = season[record.club_id]
			return result
		season[record.club_id] = index
	# Solo construye los modelos después de validar todos los registros.
	var clubs: Array[Club] = []
	for record in records:
		var club = Club.new()
		club.club_id = record.club_id
		club.season_id = record.season_id
		club.division_id = record.division_id
		clubs.append(club)
	return {"ok": true, "data": clubs, "errors": []}


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
