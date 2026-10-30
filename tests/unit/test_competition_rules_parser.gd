extends SceneTree

const Parser = preload("res://game/scripts/infrastructure/competition_rules_parser.gd")
const Rules = preload("res://game/scripts/data/competition_rules.gd")
const NUMBERS = ["points_win", "points_draw", "points_loss", "team_count", "round_count"]
const CONTAINERS = [
	"tiebreakers", "substitution_rules", "promotion_relegation_rules", "competition_format"
]

var failures: Array[String] = []
var checks = 0
var temporary_path: String


func _initialize() -> void:
	# Datos propios sintéticos; solo se escribe el archivo temporal de esta prueba.
	temporary_path = "/tmp/neofutbol_rules_test_%s.json" % OS.get_process_id()
	var valid = _valid()
	var result = _parse(JSON.stringify(valid), "test_season")
	_check(result.ok and result.errors.is_empty(), "documento válido")
	_check(result.data is Rules, "instancia CompetitionRules")
	if result.data is Rules:
		for field in valid:
			_check(result.data.get(field) == valid[field], "asignación " + field)
		for field in NUMBERS:
			_check(typeof(result.data.get(field)) == TYPE_INT, "int final " + field)
	_expect_error(Parser.new().parse_file(temporary_path + ".missing"), "file_open")
	result = _parse("{\ninvalid")
	_expect_error(result, "json_syntax")
	_check(result.errors[0].has("line") and result.errors[0].line >= 0, "línea JSON")
	for root in ["[]", "null", "1", "true", '"text"']:
		_expect_error(_parse(root), "invalid_root")
	for field in valid:
		var missing = valid.duplicate(true)
		missing.erase(field)
		_expect_error(_parse(JSON.stringify(missing)), "missing_field", field)
		var invalid_values: Array = [true, false, [], {}, "text"]
		if field in ["season_id", "competition_id"]:
			invalid_values = [true, false, 1, [], {}, "", " ", "\t\n"]
		elif field == "tiebreakers":
			invalid_values = [true, false, 1, {}, "text"]
		elif field in CONTAINERS:
			invalid_values = [true, false, 1, [], "text"]
		if field == "season_id":
			invalid_values.append(null)
		for value in invalid_values:
			var invalid = valid.duplicate(true)
			invalid[field] = value
			_expect_error(_parse(JSON.stringify(invalid)), "invalid_type", field)
	var unknown = valid.duplicate(true)
	for field in valid:
		if field != "season_id":
			unknown[field] = null
	result = _parse(JSON.stringify(unknown))
	_check(result.ok, "todos los null permitidos")
	if result.data is Rules:
		for field in unknown:
			_check(result.data.get(field) == unknown[field], "null conservado " + field)
	_expect_error(_parse(JSON.stringify(valid), "other_season"), "season_mismatch", "season_id")
	_check(_parse(JSON.stringify(valid), "").ok, "comparación desactivada")
	_expect_error(_parse(JSON.stringify(valid), "test_season "), "season_mismatch", "season_id")
	for field in ["team_count", "round_count"]:
		for token in ["0", "-0", "-1", "-2e1"]:
			_expect_error(_number(field, token), "invalid_value", field)
	for field in NUMBERS:
		for token in ["1.5", "1.0000000000000001", "0.99999999999999999",
				"9007199254740992", "9007199254740993", "-9007199254740992",
				"9223372036854775808", "1e999", "1e-999",
				"1e999999999999999999999", "1e-999999999999999999999", "0e99999"]:
			_expect_error(_number(field, token), "invalid_type", field)
		for token in ["2", "2.0", "20e-1", "0.02e2", "2e0000000", "9007199254740991"]:
			result = _number(field, token)
			_check(result.ok, "entero exacto " + field + " " + token)
			if result.data is Rules:
				_check(typeof(result.data.get(field)) == TYPE_INT, "tipo entero " + field)
		for token in ["-2", "-2.0", "-20e-1", "-9007199254740991", "-0", "0e2"]:
			if field in ["team_count", "round_count"]:
				continue
			result = _number(field, token)
			_check(result.ok, "puntos con signo o cero " + token)
			if result.data is Rules:
				var expected = -9007199254740991 if token == "-9007199254740991" else -2
				if token in ["-0", "0e2"]:
					expected = 0
				_check(result.data.get(field) == expected, "valor exacto con signo")
	for token in ["1", "2", "1.0", "10e-1", "0.01e2", "9007199254740991"]:
		result = _competition_format(
			'{"kind":"round_robin","legs":%s,"unknown":{"kept":true}}' % token
		)
		_check(result.ok, "competition_format.legs exacto " + token)
		if result.data is Rules:
			_check(typeof(result.data.competition_format.legs) == TYPE_INT,
				"competition_format.legs normalizado a int " + token)
			_check(result.data.competition_format.unknown == {"kept": true},
				"propiedad desconocida conservada " + token)
	result = _competition_format('{"kind":"round_robin","legs":null}')
	_check(result.ok and result.data.competition_format.legs == null,
		"competition_format.legs null conservado")
	for token in [
		"9007199254740992", "9007199254740993", "1.0000000000000001",
		"0.99999999999999999", "1.5", "1e999", "1e-999",
		"1e999999999999999999999", "1e-999999999999999999999",
		"0e99999", "true", "false", '"1"', "[]", "{}",
	]:
		_expect_error(_competition_format(
			'{"kind":"round_robin","legs":%s}' % token
		), "invalid_type", "competition_format.legs")
	for token in ["0", "-0", "-1", "-2.0"]:
		_expect_error(_competition_format(
			'{"kind":"round_robin","legs":%s}' % token
		), "invalid_value", "competition_format.legs")
	_expect_error(_competition_format(
		'{"kind":"round_robin","legs":1,"legs":2}'
	), "duplicate_field", "competition_format.legs")
	_expect_error(_competition_format(
		'{"kind":"round_robin","legs":1,"l\\u0065gs":2}'
	), "duplicate_field", "competition_format.legs")
	result = _competition_format(
		'{"kind":"round_robin","l\\u0065gs":2}'
	)
	_check(result.ok and result.data.competition_format.legs == 2
		and typeof(result.data.competition_format.legs) == TYPE_INT,
		"clave competition_format.legs escapada normalizada")
	for field in valid:
		var encoded = JSON.stringify(field)
		var escaped = '"\\u%04x%s"' % [field.unicode_at(0), field.substr(1)]
		for key in [encoded, escaped]:
			var text = JSON.stringify(valid)
			text = text.left(-1) + "," + key + ":" + JSON.stringify(valid[field]) + "}"
			_expect_error(_parse(text), "duplicate_field", field)
		# Una única clave escapada sigue siendo válida.
		var escaped_text = JSON.stringify(valid).replace(encoded + ":", escaped + ":")
		_check(_parse(escaped_text).ok, "clave escapada única " + field)
	var extra = valid.duplicate(true)
	extra["unknown"] = {
		"points_win": 1.5, "season_id": "nested", "array": [
			{"team_count": 0}, "points_win", "quotes \" and brackets {}[]"]
	}
	extra["competition_id"] = "points_win"
	extra["tiebreakers"] = ["test_criterion", {"unknown": null}]
	extra["competition_format"] = {"nested": {"round_count": null}}
	result = _parse(JSON.stringify(extra))
	_check(result.ok, "claves adicionales y anidadas")
	if result.data is Rules:
		for field in CONTAINERS:
			_check(result.data.get(field) == extra[field], "contenedor conservado " + field)
	var homonyms = _valid()
	homonyms.substitution_rules = {"legs": 1.5}
	homonyms.promotion_relegation_rules = {
		"competition_format": {"legs": 0},
	}
	homonyms.competition_format = {
		"kind": "round_robin", "legs": 2,
		"nested": {"legs": 1.5}, "list": [{"legs": 0}],
		"text": "embedded {\"legs\":0}",
	}
	result = _parse(JSON.stringify(homonyms))
	_check(result.ok and result.data.competition_format.legs == 2,
		"claves legs homónimas fuera del campo directo se ignoran")
	if result.data is Rules:
		_check(result.data.substitution_rules == {"legs": 1.5}
			and result.data.promotion_relegation_rules == {
				"competition_format": {"legs": 0.0},
			}
			and result.data.competition_format.nested == {"legs": 1.5}
			and result.data.competition_format.list == [{"legs": 0.0}]
			and result.data.competition_format.text == "embedded {\"legs\":0}",
			"estructuras homónimas se conservan sin transformación")
	var real = Parser.new().parse_file("res://data/seasons/1982-83/rules.json", "1982-83")
	_check(real.ok and real.data is Rules, "lectura del archivo real")
	if real.data is Rules:
		_check(real.data.competition_id == null, "competición desconocida conservada")
	DirAccess.remove_absolute(temporary_path)
	if failures.is_empty():
		print("PASS: %d comprobaciones" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)


func _valid() -> Dictionary:
	return {
		"season_id": "test_season", "competition_id": "test_competition",
		"points_win": 4, "points_draw": 2, "points_loss": -1,
		"team_count": 6, "round_count": 10,
		"tiebreakers": ["test_criterion"],
		"substitution_rules": {"unknown": null},
		"promotion_relegation_rules": {},
		"competition_format": {"kind": "test_format"}
	}


func _parse(text: String, expected_season_id: String = "") -> Dictionary:
	var file = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		failures.append("No se pudo crear la entrada temporal")
		return {"ok": false, "data": null, "errors": []}
	file.store_string(text)
	file.close()
	return Parser.new().parse_file(temporary_path, expected_season_id)


func _number(field: String, token: String) -> Dictionary:
	var values = _valid()
	values[field] = "__number_token__"
	return _parse(JSON.stringify(values).replace('"__number_token__"', token))


func _competition_format(format_token: String) -> Dictionary:
	var values = _valid()
	values.competition_format = "__competition_format_token__"
	return _parse(JSON.stringify(values).replace(
		'"__competition_format_token__"', format_token
	))


func _expect_error(result: Dictionary, code: String, field: String = "") -> void:
	_check(not result.ok and result.data == null, "fallo sin modelo parcial " + code)
	_check(not result.errors.is_empty(), "diagnóstico presente " + code)
	if result.errors.is_empty():
		return
	var error = result.errors[0]
	_check(error.code == code, "código " + code)
	_check(error.file is String and not error.file.is_empty(), "archivo del error")
	_check(error.message is String and not error.message.is_empty(), "mensaje del error")
	if not field.is_empty():
		_check(error.get("field") == field, "campo del error " + field)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
