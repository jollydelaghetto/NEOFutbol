extends SceneTree

const Parser = preload("res://game/scripts/infrastructure/club_season_parser.gd")
const Club = preload("res://game/scripts/data/club_season.gd")
const FIELDS = ["club_id", "season_id", "division_id"]

var failures: Array[String] = []
var checks = 0
var temporary_path: String


func _initialize() -> void:
	# Únicamente identificadores sintéticos y un archivo temporal propio.
	temporary_path = "/tmp/neofutbol_clubs_test_%s.json" % OS.get_process_id()
	var first = _club("test_club_a")
	var second = _club("test_club_b")
	var result = _parse(JSON.stringify([first]), "test_season")
	_check(result.ok and result.errors.is_empty(), "registro válido")
	_check(result.data is Array and result.data.size() == 1, "colección con un registro")
	if result.ok:
		_check(result.data[0] is Club, "instancia ClubSeason")
		for field in FIELDS:
			_check(result.data[0].get(field) == first[field], "asignación " + field)
	var exact = {
		"club_id": " Test_Club_Á \"\\{}[] ",
		"season_id": " Test_Season ",
		"division_id": " Test_Division "
	}
	result = _parse(JSON.stringify([second, first, exact]))
	_check(result.ok and result.data.size() == 3, "varios registros y temporadas")
	if result.ok:
		for index in 3:
			for field in FIELDS:
				_check(result.data[index].get(field) == [second, first, exact][index][field],
					"orden e identificador exacto")
	result = _parse("[]", "test_season")
	_check(result.ok and result.data.is_empty() and result.errors.is_empty(), "lista vacía")
	if result.ok:
		_check(result.data.is_typed() and result.data.get_typed_script() == Club, "array tipado vacío")
	result = Parser.new().parse_file("res://data/seasons/1982-83/clubs.json", "1982-83")
	_check(result.ok and result.data.is_empty(), "lista real vacía sin modificar")
	_expect_error(Parser.new().parse_file(temporary_path + ".missing"), "file_open")
	result = _parse("[\ninvalid")
	_expect_error(result, "json_syntax")
	_check(result.errors[0].has("line") and result.errors[0].line >= 0, "línea JSON")
	for root in ["{}", "null", "1", "true", '"text"']:
		_expect_error(_parse(root), "invalid_root")
	for value in [null, 1, true, false, [], "text"]:
		_expect_error(_parse(JSON.stringify([first, value])), "invalid_record", 1)
	for field in FIELDS:
		var missing = first.duplicate()
		missing.erase(field)
		_expect_error(_parse(JSON.stringify([second, missing])), "missing_field", 1, field)
		for value in [null, 1, 1.5, true, false, [], {}, "", " ", "\t\r\n"]:
			var invalid = first.duplicate()
			invalid[field] = value
			_expect_error(_parse(JSON.stringify([second, invalid])), "invalid_type", 1, field)
	_check(_parse(JSON.stringify([first, second]), "test_season").ok, "temporada coincidente")
	_expect_error(_parse(JSON.stringify([first]), "other_season"), "season_mismatch", 0, "season_id")
	_expect_error(_parse(JSON.stringify([first]), "test_season "), "season_mismatch", 0, "season_id")
	var other_season = first.duplicate()
	other_season.season_id = "other_season"
	_check(_parse(JSON.stringify([first, other_season])).ok, "mismo club en distintas temporadas")
	_expect_error(_parse(JSON.stringify([first, other_season]), "test_season"),
		"season_mismatch", 1, "season_id")
	_check(_parse(JSON.stringify([first, second])).ok, "clubes distintos en misma división")
	for division in ["test_division", "other_division"]:
		var repeated = first.duplicate()
		repeated.division_id = division
		result = _parse(JSON.stringify([second, first, repeated]))
		_expect_error(result, "duplicate_club", 2, "club_id")
		_check(result.errors[0].get("first_index") == 1, "primera aparición del club")
	# La identidad distingue mayúsculas y espacios; no se normaliza.
	for identifier in ["TEST_CLUB_A", " test_club_a", "test_club_a "]:
		_check(_parse(JSON.stringify([first, _club(identifier)])).ok, "sin normalización")
	for field in FIELDS:
		var encoded = JSON.stringify(field)
		var escaped = '"\\u%04x%s"' % [field.unicode_at(0), field.substr(1)]
		for key in [encoded, escaped]:
			var text = JSON.stringify(first).left(-1)
			text += "," + key + ":" + JSON.stringify(first[field]) + "}"
			result = _parse("[" + JSON.stringify(second) + "," + text + "]")
			_expect_error(result, "duplicate_field", 1, field)
		var escaped_record = JSON.stringify(first).replace(encoded + ":", escaped + ":")
		_check(_parse("[" + escaped_record + "]").ok, "clave escapada única")
	var extra = first.duplicate()
	extra["unknown"] = {
		"club_id": null, "season_id": 1, "division_id": [],
		"nested": [{"club_id": "nested"}, ["{}[],:", "club_id", "\\\""]]
	}
	result = _parse(JSON.stringify([extra, second]))
	_check(result.ok and result.data.size() == 2, "claves anidadas y caracteres especiales")
	if result.ok:
		_check(result.data[0].club_id == first.club_id, "anidamiento no altera identificador")
		_check(result.data[0].get("unknown") == null, "campos adicionales no transferidos")
	var nested_duplicates = JSON.stringify(first).left(-1) \
		+ ',"extra":{"club_id":"nested_a","club_id":"nested_b"},"extra":null}'
	_check(_parse("[" + nested_duplicates + "]").ok, "duplicados adicionales ignorados")
	# Una lista anidada no debe tomarse por un objeto de registro.
	var nested_array = '[{"club_id":"a","club_id":"b"}]'
	_expect_error(_parse("[" + JSON.stringify(first) + "," + nested_array + "]"),
		"invalid_record", 1)
	# Clubes con delimitadores no colisionan al identificar la pareja.
	var pair_a = _club("a:b")
	pair_a.season_id = "c"
	var pair_b = _club("b")
	pair_b.season_id = "c:a"
	_check(_parse(JSON.stringify([pair_a, pair_b])).ok, "parejas sin concatenación ambigua")
	DirAccess.remove_absolute(temporary_path)
	if failures.is_empty():
		print("PASS: %d comprobaciones" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)


func _club(identifier: String) -> Dictionary:
	return {"club_id": identifier, "season_id": "test_season", "division_id": "test_division"}


func _parse(text: String, expected_season_id: String = "") -> Dictionary:
	var file = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		failures.append("No se pudo crear la entrada temporal")
		return {"ok": false, "data": null, "errors": []}
	file.store_string(text)
	file.close()
	return Parser.new().parse_file(temporary_path, expected_season_id)


func _expect_error(result: Dictionary, code: String, index: int = -1, field: String = "") -> void:
	_check(not result.ok and result.data == null, "fallo sin colección parcial " + code)
	_check(result.errors.size() == 1, "primer diagnóstico")
	if result.errors.is_empty():
		return
	var error = result.errors[0]
	_check(error.code == code, "código " + code)
	_check(error.file == temporary_path + (".missing" if code == "file_open" else ""), "archivo exacto")
	_check(error.message is String and not error.message.is_empty(), "mensaje")
	if index >= 0:
		_check(error.get("index") == index, "índice exacto")
	if not field.is_empty():
		_check(error.get("field") == field, "campo exacto")


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
