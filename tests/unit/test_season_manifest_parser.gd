extends SceneTree

const Parser = preload("res://game/scripts/infrastructure/season_manifest_parser.gd")
const Manifest = preload("res://game/scripts/data/season_manifest.gd")

var failures: Array[String] = []
var cases = 0
var temporary_path: String


func _initialize() -> void:
	# Solo datos sintéticos temporales; nunca se escribe en el pack histórico.
	temporary_path = "/tmp/neofutbol_manifest_test_%s.json" % OS.get_process_id()
	var valid = {
		"schema_version": 1, "season_id": "test_season",
		"sources": [{"source_id": "test_source", "unknown": null}],
		"checksum": {"test_file": "synthetic_hash"},
		"extra": {"ignored": true}
	}
	var result = _parse(JSON.stringify(valid))
	_check(result.ok and result.errors.is_empty(), "manifiesto válido y claves adicionales")
	_check(result.data is Manifest, "conversión a SeasonManifest")
	if result.data is Manifest:
		_check(typeof(result.data.schema_version) == TYPE_INT, "versión convertida a int")
		_check(result.data.season_id == "test_season", "identificador conservado")
		_check(result.data.sources == valid.sources, "fuentes y null conservados")
		_check(result.data.checksum == valid.checksum, "checksum conservado sin verificar")
	_expect_error(Parser.new().parse_file(temporary_path + ".missing"), "file_open")
	result = _parse("{\ninvalid")
	_expect_error(result, "json_syntax")
	_check(result.errors[0].has("line") and result.errors[0].line >= 0, "línea JSON")
	for root in ["[]", "null", "true", "1", '"text"']:
		_expect_error(_parse(root), "invalid_root")
	for field in valid:
		if field == "extra":
			continue
		var missing = valid.duplicate(true)
		missing.erase(field)
		_expect_error(_parse(JSON.stringify(missing)), "missing_field")
	var wrong_types = {
		"schema_version": ["1", null, true, [], {}, 1.5],
		"season_id": [null, 1, true, [], {}, "", "   "],
		"sources": [null, 1, true, "text", {}],
		"checksum": [null, 1, true, "text", []]
	}
	for field in wrong_types:
		for wrong_value in wrong_types[field]:
			var invalid = valid.duplicate(true)
			invalid[field] = wrong_value
			_expect_error(_parse(JSON.stringify(invalid)), "invalid_type")
	for version in ["0", "-1", "2", "9007199254740991"]:
		_expect_error(_version(version), "unsupported_schema")
	for version in ["1.0000000000000001", "0.99999999999999999",
			"9007199254740993", "9223372036854775808", "1e999", "1e-999"]:
		_expect_error(_version(version), "invalid_type")
	for version in ["1", "1.0", "1e0", "10e-1", "0.01e2", "1e0000000000"]:
		result = _version(version)
		_check(result.ok and result.data.schema_version == 1, "entero exacto: " + version)
	result = _version("1")
	_check(result.data.sources == [] and result.data.checksum == {}, "colecciones vacías")
	# La clave escapada y los objetos anidados no deben confundir la comprobación.
	result = _parse('{"nested":{"schema_version":2},"schema_\\u0076ersion":1,'
		+ '"season_id":"test","sources":[],"checksum":{}}')
	_check(result.ok, "clave escapada y clave anidada")
	result = _parse('{"schema_version":1,"season_id":"schema_version",'
		+ '"sources":["schema_version"],"checksum":{}}')
	_check(result.ok, "valores de texto que coinciden con el nombre de la clave")
	_check(Parser.new().parse_file("res://data/seasons/1982-83/manifest.json").ok,
		"lectura del manifiesto existente sin modificarlo")
	DirAccess.remove_absolute(temporary_path)
	if failures.is_empty():
		print("PASS: %d comprobaciones" % cases)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)


func _parse(text: String) -> Dictionary:
	var file = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		failures.append("No se pudo crear la entrada temporal")
		return {"ok": false, "data": null, "errors": []}
	file.store_string(text)
	file.close()
	return Parser.new().parse_file(temporary_path)


func _version(token: String) -> Dictionary:
	return _parse('{"schema_version":' + token
		+ ',"season_id":"test_season","sources":[],"checksum":{}}')


func _expect_error(result: Dictionary, code: String) -> void:
	_check(not result.ok and result.data == null, "fallo sin modelo parcial: " + code)
	_check(not result.errors.is_empty(), "diagnóstico presente: " + code)
	if not result.errors.is_empty():
		var error = result.errors[0]
		_check(error.code == code, "código: " + code)
		_check(error.file is String and not error.file.is_empty(), "archivo del error")
		_check(error.message is String and not error.message.is_empty(), "mensaje del error")


func _check(condition: bool, message: String) -> void:
	cases += 1
	if not condition:
		failures.append(message)
