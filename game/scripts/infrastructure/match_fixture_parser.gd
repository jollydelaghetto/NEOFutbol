class_name MatchFixtureParser
extends RefCounted

const Fixture = preload("res://game/scripts/data/match_fixture.gd")
const REQUIRED = [
	"fixture_id", "season_id", "competition_id", "stage_id", "group_id",
	"home_club_id", "away_club_id", "round_number", "scheduled_date", "metadata"
]
const REQUIRED_IDENTIFIERS = ["fixture_id", "season_id"]
const OPTIONAL_IDENTIFIERS = [
	"competition_id", "stage_id", "group_id", "home_club_id", "away_club_id"
]

## Devuelve {ok: bool, data: Array[MatchFixture] o null, errors: Array}.
## [] es válido y no certifica la cobertura histórica del calendario.
## expected_season_id vacío desactiva la comparación con la temporada esperada.
## El primer diagnóstico contiene code, file, message y, cuando corresponda,
## index (base cero), field, line o first_index.
## Códigos: file_open, file_read, json_syntax, invalid_root, invalid_record,
## missing_field, invalid_type, invalid_value, season_mismatch, duplicate_field,
## duplicate_fixture.
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
	var scan = _record_tokens(text)
	var exact_rounds: Dictionary = {}
	var seen: Dictionary = {}
	for index in records.size():
		var record = records[index]
		if not record is Dictionary:
			return _failure("invalid_record", path, "El registro debe ser un objeto JSON.", index)
		if scan.duplicates.has(index):
			return _failure("duplicate_field", path, "Campo obligatorio duplicado.",
				index, scan.duplicates[index])
		for field in REQUIRED:
			if not record.has(field):
				return _failure("missing_field", path, "Falta el campo obligatorio.", index, field)
		for field in REQUIRED_IDENTIFIERS:
			if not record[field] is String or record[field].strip_edges().is_empty():
				return _failure("invalid_type", path, "Debe ser una cadena no vacía.", index, field)
		for field in OPTIONAL_IDENTIFIERS:
			if record[field] != null and (
				not record[field] is String or record[field].strip_edges().is_empty()
			):
				return _failure("invalid_type", path, "Debe ser una cadena no vacía o null.", index, field)
		if not record.metadata is Dictionary:
			return _failure("invalid_type", path, "metadata debe ser un diccionario.", index, "metadata")
		if not expected_season_id.is_empty() and record.season_id != expected_season_id:
			return _failure("season_mismatch", path, "La temporada no coincide con la esperada.",
				index, "season_id")
		var exact_round = null
		if record.round_number != null:
			if typeof(record.round_number) != TYPE_FLOAT and typeof(record.round_number) != TYPE_INT:
				return _failure("invalid_type", path, "Debe ser un entero exacto positivo o null.",
					index, "round_number")
			exact_round = _safe_integer(scan.round_tokens.get(index, ""))
			if exact_round == null or not is_finite(record.round_number) \
					or record.round_number != exact_round:
				return _failure("invalid_type", path,
					"Número no entero, inexacto o fuera del intervalo seguro.", index, "round_number")
			if exact_round <= 0:
				return _failure("invalid_value", path, "Debe ser un entero positivo o null.",
					index, "round_number")
		exact_rounds[index] = exact_round
		if record.scheduled_date != null:
			if not record.scheduled_date is String:
				return _failure("invalid_type", path, "Debe ser una fecha YYYY-MM-DD o null.",
					index, "scheduled_date")
			if not _valid_date(record.scheduled_date):
				return _failure("invalid_value", path, "Debe ser una fecha YYYY-MM-DD real.",
					index, "scheduled_date")
		if not seen.has(record.season_id):
			seen[record.season_id] = {}
		var season: Dictionary = seen[record.season_id]
		if season.has(record.fixture_id):
			var result = _failure("duplicate_fixture", path,
				"Partido repetido en la misma temporada.", index, "fixture_id")
			result.errors[0]["first_index"] = season[record.fixture_id]
			return result
		season[record.fixture_id] = index
	# Solo construye los modelos después de validar todos los registros.
	var fixtures: Array[Fixture] = []
	for index in records.size():
		var record = records[index]
		var fixture = Fixture.new()
		fixture.fixture_id = record.fixture_id
		fixture.season_id = record.season_id
		fixture.competition_id = record.competition_id
		fixture.stage_id = record.stage_id
		fixture.group_id = record.group_id
		fixture.home_club_id = record.home_club_id
		fixture.away_club_id = record.away_club_id
		fixture.round_number = exact_rounds[index]
		fixture.scheduled_date = record.scheduled_date
		fixture.metadata = record.metadata.duplicate(true)
		fixtures.append(fixture)
	return {"ok": true, "data": fixtures, "errors": []}


func _failure(code: String, path: String, message: String,
		index: int = -1, field: String = "") -> Dictionary:
	var diagnostic = {"code": code, "file": path, "message": message}
	if index >= 0:
		diagnostic["index"] = index
	if not field.is_empty():
		diagnostic["field"] = field
	return {"ok": false, "data": null, "errors": [diagnostic]}


## Examina las claves originales de los objetos directamente contenidos en la
## lista. Ignora objetos anidados y conserva el token numérico de round_number.
func _record_tokens(text: String) -> Dictionary:
	var lexer = RegEx.new()
	lexer.compile('"([^"\\\\]|\\\\.)*"|[{}\\[\\]:,]|[^\\s{}\\[\\]:,]+')
	var matches = lexer.search_all(text)
	var depth = 0
	var index = 0
	var record_is_object = false
	var seen: Dictionary = {}
	var duplicates: Dictionary = {}
	var round_tokens: Dictionary = {}
	for position in matches.size():
		var token = matches[position].get_string()
		if depth == 1 and token == ",":
			index += 1
		if depth == 1 and token in ["{", "["]:
			record_is_object = token == "{"
			seen = {}
		if depth == 2 and record_is_object and token.begins_with('"') \
				and position + 2 < matches.size() and matches[position + 1].get_string() == ":":
			var key = JSON.parse_string(token)
			if key in REQUIRED:
				if seen.has(key) and not duplicates.has(index):
					duplicates[index] = key
				seen[key] = true
				if key == "round_number":
					round_tokens[index] = matches[position + 2].get_string()
		if token == "{" or token == "[":
			depth += 1
		elif token == "}" or token == "]":
			depth -= 1
	return {"duplicates": duplicates, "round_tokens": round_tokens}


## Normaliza el token decimal con cadenas antes de convertirlo a int.
## Acepta enteros matemáticos en ±(2^53 - 1); nunca trunca ni redondea.
func _safe_integer(token: String) -> Variant:
	var syntax = RegEx.new()
	syntax.compile("^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$")
	if syntax.search(token) == null:
		return null
	var parts = token.to_lower().trim_prefix("-").split("e")
	var decimal = parts[0].split(".")
	var digits = parts[0].replace(".", "")
	while digits.begins_with("0"):
		digits = digits.substr(1)
	if digits.is_empty():
		return 0
	var exponent = 0
	if parts.size() == 2:
		var magnitude = parts[1].trim_prefix("+").trim_prefix("-")
		while magnitude.begins_with("0"):
			magnitude = magnitude.substr(1)
		var limit = str(token.length() + 16)
		if magnitude.length() > limit.length() or (
			magnitude.length() == limit.length() and magnitude > limit
		):
			return null
		exponent = magnitude.to_int()
		if parts[1].begins_with("-"):
			exponent = -exponent
	var shift = exponent
	if decimal.size() == 2:
		shift -= decimal[1].length()
	while shift < 0 and digits.ends_with("0"):
		digits = digits.left(-1)
		shift += 1
	if shift < 0 or digits.length() + shift > 16:
		return null
	digits += "0".repeat(shift)
	if digits.length() == 16 and digits > "9007199254740991":
		return null
	var exact = digits.to_int()
	return -exact if token.begins_with("-") else exact


func _valid_date(value: String) -> bool:
	var format = RegEx.new()
	format.compile("^([0-9]{4})-([0-9]{2})-([0-9]{2})$")
	var matched = format.search(value)
	if matched == null:
		return false
	var year = matched.get_string(1).to_int()
	var month = matched.get_string(2).to_int()
	var day = matched.get_string(3).to_int()
	if year == 0 or month < 1 or month > 12:
		return false
	var days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if year % 400 == 0 or (year % 4 == 0 and year % 100 != 0):
		days[1] = 29
	return day >= 1 and day <= days[month - 1]
