class_name SeasonManifestParser
extends RefCounted

const Manifest = preload("res://game/scripts/data/season_manifest.gd")
const REQUIRED_FIELDS = ["schema_version", "season_id", "sources", "checksum"]

## Entrada: ruta de un manifiesto. Salida: {ok: bool, data: SeasonManifest o null,
## errors: Array[Dictionary]}. Cada error contiene code, file y message.
## Los errores JSON incluyen line. Nunca devuelve un modelo parcial.
## El éxito no certifica fuentes, hashes ni integridad histórica del pack.
func parse_file(path: String) -> Dictionary:
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
	for field in REQUIRED_FIELDS:
		if not fields.has(field):
			return _failure("missing_field", path, "Falta el campo obligatorio: " + field)
	if not _exact_integer_version(text, fields.schema_version):
		return _failure("invalid_type", path, "schema_version debe ser un entero exacto representable.")
	if fields.schema_version != 1:
		return _failure("unsupported_schema", path, "Solo se admite schema_version = 1.")
	if not fields.season_id is String or fields.season_id.strip_edges().is_empty():
		return _failure("invalid_type", path, "season_id debe ser una cadena no vacía.")
	if not fields.sources is Array:
		return _failure("invalid_type", path, "sources debe ser una lista.")
	if not fields.checksum is Dictionary:
		return _failure("invalid_type", path, "checksum debe ser un diccionario.")
	var manifest = Manifest.new()
	manifest.schema_version = int(fields.schema_version)
	manifest.season_id = fields.season_id
	manifest.sources = fields.sources
	manifest.checksum = fields.checksum
	return {"ok": true, "data": manifest, "errors": []}


func _failure(code: String, path: String, message: String) -> Dictionary:
	return {"ok": false, "data": null, "errors": [
		{"code": code, "file": path, "message": message}
	]}


## Comprueba también el token original: el float de JSON puede haber redondeado
## un decimal a 1. Limita los enteros al intervalo exacto seguro de binary64.
func _exact_integer_version(text: String, value: Variant) -> bool:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return false
	if not is_finite(value) or value != floor(value) or abs(value) > 9007199254740991:
		return false
	var tokens = RegEx.new()
	tokens.compile('"([^"\\\\]|\\\\.)*"|[{}\\[\\]:,]|[^\\s{}\\[\\]:,]+')
	var depth = 0
	var awaiting_value = false
	var found = false
	var matches = tokens.search_all(text)
	for index in matches.size():
		var token = matches[index].get_string()
		if awaiting_value and token != ":":
			if not _integer_token(token):
				return false
			awaiting_value = false
			found = true
		if depth == 1 and token.begins_with('"') and index + 1 < matches.size() \
				and matches[index + 1].get_string() == ":":
			if JSON.parse_string(token) == "schema_version":
				awaiting_value = true
		if token == "{" or token == "[":
			depth += 1
		elif token == "}" or token == "]":
			depth -= 1
	return found


func _integer_token(token: String) -> bool:
	var number = RegEx.new()
	number.compile("^-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?$")
	if number.search(token) == null:
		return false
	var parts = token.to_lower().trim_prefix("-").split("e")
	var exponent = 0
	if parts.size() == 2:
		# Evita conversiones de exponentes desmesurados; cero sigue siendo exacto.
		var exponent_digits = parts[1].trim_prefix("+").trim_prefix("-")
		while exponent_digits.begins_with("0"):
			exponent_digits = exponent_digits.substr(1)
		if exponent_digits.length() > 4:
			return parts[0].replace(".", "").replace("0", "").is_empty()
		exponent = parts[1].to_int()
	var decimal_parts = parts[0].split(".")
	var digits = parts[0].replace(".", "")
	var shift = exponent
	if decimal_parts.size() == 2:
		shift -= decimal_parts[1].length()
	while digits.begins_with("0"):
		digits = digits.substr(1)
	if digits.is_empty():
		return true
	while shift < 0 and digits.ends_with("0"):
		digits = digits.left(-1)
		shift += 1
	if shift < 0 or digits.length() + shift > 16:
		return false
	digits += "0".repeat(shift)
	return digits.length() < 16 or digits <= "9007199254740991"
