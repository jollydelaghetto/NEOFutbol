extends SceneTree

const Parser = preload("res://game/scripts/infrastructure/player_season_parser.gd")
const Player = preload("res://game/scripts/data/player_season.gd")
const IDS = ["player_id", "season_id", "club_id"]
const CONTAINERS = ["historical_data", "game_data", "metadata"]

var failures: Array[String] = []
var checks = 0
var temporary_path: String


func _initialize() -> void:
	# Identificadores y datos sintéticos; nunca escribe en los packs históricos.
	temporary_path = "/tmp/neofutbol_players_test_%s.json" % OS.get_process_id()
	var first = _player("test_player_a")
	var second = _player("test_player_b")
	var result = _parse(JSON.stringify([first]), "test_season")
	_check(result.ok and result.errors.is_empty(), "jugador válido")
	if result.ok:
		_check(result.data.size() == 1 and result.data[0] is Player, "modelo PlayerSeason")
		for field in first:
			_check(result.data[0].get(field) == first[field], "conservación " + field)
	var exact = _player(" Test_Player_Á \"\\{}[] ")
	exact.season_id = " Test_Season "
	exact.club_id = " Test_Club "
	result = _parse(JSON.stringify([second, first, exact]))
	_check(result.ok and result.data.size() == 3, "varios jugadores")
	if result.ok:
		for index in 3:
			for field in IDS:
				_check(result.data[index].get(field) == [second, first, exact][index][field],
					"orden e identificador exacto")
	result = _parse("[]", "test_season")
	_check(result.ok and result.data.is_empty() and result.errors.is_empty(), "lista vacía")
	if result.ok:
		_check(result.data.is_typed() and result.data.get_typed_script() == Player, "lista tipada")
	result = Parser.new().parse_file("res://data/seasons/1982-83/players.json", "1982-83")
	_check(result.ok and result.data.is_empty(), "archivo real vacío")
	_expect_error(Parser.new().parse_file(temporary_path + ".missing"), "file_open")
	result = _parse("[\ninvalid")
	_expect_error(result, "json_syntax")
	_check(result.errors[0].has("line") and result.errors[0].line >= 0, "línea JSON")
	for root in ["{}", "null", "1", "true", '"text"']:
		_expect_error(_parse(root), "invalid_root")
	for value in [null, 1, true, false, [], "text"]:
		_expect_error(_parse(JSON.stringify([second, value])), "invalid_record", 1)
	for field in first:
		var missing = first.duplicate(true)
		missing.erase(field)
		_expect_error(_parse(JSON.stringify([second, missing])), "missing_field", 1, field)
		var invalid_values: Array = [null, true, false, 1, 1.5, [], "text"]
		if field in IDS:
			invalid_values = [null, true, false, 1, 1.5, [], {}, "", " ", "\t\r\n"]
		for value in invalid_values:
			var invalid = first.duplicate(true)
			invalid[field] = value
			_expect_error(_parse(JSON.stringify([second, invalid])), "invalid_type", 1, field)
	var empty = first.duplicate(true)
	for field in CONTAINERS:
		empty[field] = {}
	result = _parse(JSON.stringify([empty]))
	_check(result.ok, "diccionarios vacíos")
	if result.ok:
		for field in CONTAINERS:
			_check(result.data[0].get(field) == {}, "sin valores predeterminados")
	_check(_parse(JSON.stringify([first, second]), "test_season").ok, "temporada coincidente")
	_expect_error(_parse(JSON.stringify([first]), "other_season"), "season_mismatch", 0, "season_id")
	_expect_error(_parse(JSON.stringify([first]), "test_season "), "season_mismatch", 0, "season_id")
	var other = first.duplicate(true)
	other.season_id = "other_season"
	_check(_parse(JSON.stringify([first, other])).ok, "mismo jugador en temporadas diferentes")
	_expect_error(_parse(JSON.stringify([first, other]), "test_season"), "season_mismatch", 1, "season_id")
	for club in ["test_club", "other_club"]:
		var repeated = first.duplicate(true)
		repeated.club_id = club
		result = _parse(JSON.stringify([second, first, repeated]))
		_expect_error(result, "duplicate_player", 2, "player_id")
		_check(result.errors[0].get("first_index") == 1, "primera aparición")
	for field in first:
		var encoded = JSON.stringify(field)
		var escaped = '"\\u%04x%s"' % [field.unicode_at(0), field.substr(1)]
		for key in [encoded, escaped]:
			var text = JSON.stringify(first).left(-1)
			text += "," + key + ":" + JSON.stringify(first[field]) + "}"
			_expect_error(_parse("[" + JSON.stringify(second) + "," + text + "]"),
				"duplicate_field", 1, field)
		var escaped_text = JSON.stringify(first).replace(encoded + ":", escaped + ":")
		_check(_parse("[" + escaped_text + "]").ok, "clave escapada única")
	var extra = first.duplicate(true)
	extra["additional"] = {"player_id": null, "array": [
		{"season_id": 1}, "player_id", "quotes \" \\ {}[],:"]}
	result = _parse(JSON.stringify([extra, second]))
	_check(result.ok, "campos adicionales y anidamiento")
	if result.ok:
		_check(result.data[0].get("additional") == null, "campo adicional ignorado")
		for field in CONTAINERS:
			_check(result.data[0].get(field) == first[field], "anidamiento conservado " + field)
	var nested_duplicates = JSON.stringify(first).left(-1) \
		+ ',"extra":{"player_id":"a","player_id":"b"}}'
	_check(_parse("[" + nested_duplicates + "]").ok, "duplicados anidados ignorados")
	_expect_error(_parse("[" + JSON.stringify(first) + ',[{"player_id":"a","player_id":"b"}]]'),
		"invalid_record", 1)
	# El mismo parser no comparte modelos ni diccionarios entre cargas.
	var parser = Parser.new()
	result = _parse(JSON.stringify([first, second]))
	var later = parser.parse_file(temporary_path)
	var baseline = JSON.parse_string(JSON.stringify([first, second]))
	_check(result.ok and later.ok, "cargas independientes")
	if result.ok and later.ok:
		for field in CONTAINERS:
			result.data[0].get(field).nested.values[0]["unknown"] = "modified"
			_check(result.data[1].get(field) == baseline[1][field], "independencia entre registros")
			_check(later.data[0].get(field) == baseline[0][field], "independencia entre llamadas")
		var again = parser.parse_file(temporary_path)
		_check(again.ok and again.data[0].metadata == baseline[0].metadata, "sin caché mutable")
		_check(later.data[0].metadata.sources == first.metadata.sources, "fuentes conservadas")
		_check(later.data[0].metadata.confidence == first.metadata.confidence, "confianza conservada")
	var unlisted = first.duplicate(true)
	unlisted.club_id = "test_unlisted_club"
	_check(_parse(JSON.stringify([unlisted])).ok, "sin validación cruzada de clubes")
	var pair_a = _player("a:b")
	pair_a.season_id = "c"
	var pair_b = _player("b")
	pair_b.season_id = "c:a"
	_check(_parse(JSON.stringify([pair_a, pair_b])).ok, "parejas sin colisiones")
	DirAccess.remove_absolute(temporary_path)
	if failures.is_empty():
		print("PASS: %d comprobaciones" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)


func _player(identifier: String) -> Dictionary:
	var record = {"player_id": identifier, "season_id": "test_season", "club_id": "test_club"}
	for field in CONTAINERS:
		record[field] = {"nested": {"values": [{"unknown": null}, true, "synthetic", 1.5]}}
	record.historical_data["test_fact"] = null
	record.game_data["test_attribute"] = null
	record.metadata["sources"] = [{"source_id": "test_source", "checked_at": null}]
	record.metadata["confidence"] = {"kind": "test_kind", "value": null}
	return record


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
