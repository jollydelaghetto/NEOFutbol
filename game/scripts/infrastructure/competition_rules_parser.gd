class_name CompetitionRulesParser
extends RefCounted

const Rules = preload("res://game/scripts/data/competition_rules.gd")
const NUMBERS = ["points_win", "points_draw", "points_loss", "team_count", "round_count"]
const CONTAINERS = {
	"tiebreakers": TYPE_ARRAY, "substitution_rules": TYPE_DICTIONARY,
	"promotion_relegation_rules": TYPE_DICTIONARY, "competition_format": TYPE_DICTIONARY
}
const REQUIRED = [
	"season_id", "competition_id", "points_win", "points_draw", "points_loss",
	"team_count", "round_count", "tiebreakers", "substitution_rules",
	"promotion_relegation_rules", "competition_format"
]

## Lee únicamente reglas estructurales, sin certificar su validez histórica.
## Devuelve {ok: bool, data: CompetitionRules o null, errors: Array}.
## El primer error contiene code, file, message y, si corresponde, field o line.
## expected_season_id vacío desactiva la comparación con la temporada esperada.
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
	if not json.data is Dictionary:
		return _failure("invalid_root", path, "La raíz debe ser un objeto JSON.")
	var fields: Dictionary = json.data
	var scan = _root_tokens(text)
	if not scan.duplicate.is_empty():
		return _failure("duplicate_field", path, "Campo obligatorio duplicado.", scan.duplicate)
	if not scan.competition_format_duplicate.is_empty():
		return _failure("duplicate_field", path, "Campo anidado duplicado.",
			scan.competition_format_duplicate)
	for field in REQUIRED:
		if not fields.has(field):
			return _failure("missing_field", path, "Falta el campo obligatorio.", field)
	for field in ["season_id", "competition_id"]:
		if field == "competition_id" and fields[field] == null:
			continue
		if not fields[field] is String or fields[field].strip_edges().is_empty():
			return _failure("invalid_type", path, "Debe ser una cadena no vacía.", field)
	if not expected_season_id.is_empty() and fields.season_id != expected_season_id:
		return _failure("season_mismatch", path, "La temporada no coincide con la esperada.", "season_id")
	var integers: Dictionary = {}
	for field in NUMBERS:
		var value = fields[field]
		integers[field] = null
		if value == null:
			continue
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return _failure("invalid_type", path, "Debe ser un entero exacto o null.", field)
		var exact = _safe_integer(scan.tokens.get(field, ""))
		if exact == null or not is_finite(value) or value != exact:
			return _failure("invalid_type", path, "Número no entero, inexacto o fuera del intervalo seguro.", field)
		if field in ["team_count", "round_count"] and exact <= 0:
			return _failure("invalid_value", path, "Debe ser un entero positivo o null.", field)
		integers[field] = exact
	for field in CONTAINERS:
		if fields[field] != null and typeof(fields[field]) != CONTAINERS[field]:
			return _failure("invalid_type", path, "Tipo de contenedor incorrecto.", field)
	var competition_format = fields.competition_format
	if competition_format is Dictionary and competition_format.has("legs"):
		var value = competition_format.legs
		if value != null:
			if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
				return _failure("invalid_type", path,
					"competition_format.legs debe ser un entero exacto positivo o null.",
					"competition_format.legs")
			var exact = _safe_integer(scan.competition_format_legs_token)
			if exact == null or not is_finite(value) or value != exact:
				return _failure("invalid_type", path,
					"competition_format.legs no es un entero exacto representable.",
					"competition_format.legs")
			if exact <= 0:
				return _failure("invalid_value", path,
					"competition_format.legs debe ser positivo o null.",
					"competition_format.legs")
			competition_format = competition_format.duplicate(true)
			competition_format["legs"] = exact
	var rules = Rules.new()
	rules.season_id = fields.season_id
	rules.competition_id = fields.competition_id
	rules.points_win = integers.points_win
	rules.points_draw = integers.points_draw
	rules.points_loss = integers.points_loss
	rules.team_count = integers.team_count
	rules.round_count = integers.round_count
	rules.tiebreakers = fields.tiebreakers
	rules.substitution_rules = fields.substitution_rules
	rules.promotion_relegation_rules = fields.promotion_relegation_rules
	rules.competition_format = competition_format
	return {"ok": true, "data": rules, "errors": []}


func _failure(code: String, path: String, message: String, field: String = "") -> Dictionary:
	var diagnostic = {"code": code, "file": path, "message": message}
	if not field.is_empty():
		diagnostic["field"] = field
	return {"ok": false, "data": null, "errors": [diagnostic]}


## JSON.parse ya ha comprobado la sintaxis. Conserva tokens de valores de raíz
## y de competition_format.legs. El seguimiento de profundidad impide confundir
## claves homónimas en otros objetos o en estructuras anidadas.
func _root_tokens(text: String) -> Dictionary:
	var lexer = RegEx.new()
	lexer.compile('"([^"\\\\]|\\\\.)*"|[{}\\[\\]:,]|[^\\s{}\\[\\]:,]+')
	var matches = lexer.search_all(text)
	var depth = 0
	var values: Dictionary = {}
	var competition_format_depth = -1
	var competition_format_legs_token = ""
	var competition_format_legs_seen = false
	var competition_format_duplicate = ""
	for index in matches.size():
		var token = matches[index].get_string()
		if depth == 1 and token.begins_with('"') and index + 2 < matches.size() \
				and matches[index + 1].get_string() == ":":
			var key = JSON.parse_string(token)
			if key in REQUIRED:
				if values.has(key):
					return {
						"tokens": {}, "duplicate": key,
						"competition_format_legs_token": "",
						"competition_format_duplicate": "",
					}
				values[key] = matches[index + 2].get_string()
				if key == "competition_format" and values[key] == "{":
					competition_format_depth = depth + 1
		elif depth == competition_format_depth and token.begins_with('"') \
				and index + 2 < matches.size() \
				and matches[index + 1].get_string() == ":":
			var nested_key = JSON.parse_string(token)
			if nested_key == "legs":
				if competition_format_legs_seen:
					competition_format_duplicate = "competition_format.legs"
				else:
					competition_format_legs_seen = true
					competition_format_legs_token = matches[index + 2].get_string()
		if token == "{" or token == "[":
			depth += 1
		elif token == "}" or token == "]":
			depth -= 1
			if depth < competition_format_depth:
				competition_format_depth = -1
	return {
		"tokens": values,
		"duplicate": "",
		"competition_format_legs_token": competition_format_legs_token,
		"competition_format_duplicate": competition_format_duplicate,
	}


## Normaliza el token decimal con cadenas antes de convertirlo a int.
## Acepta enteros matemáticos (también con exponente) en ±(2^53 - 1).
## null indica fracción o valor no representable; nunca trunca ni redondea.
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
		# Un exponente mayor que el texto no puede compensarse con su mantisa.
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
