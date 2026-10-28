extends SceneTree

const Parser = preload("res://game/scripts/infrastructure/match_fixture_parser.gd")
const Fixture = preload("res://game/scripts/data/match_fixture.gd")
const FIELDS = [
	"fixture_id", "season_id", "competition_id", "stage_id", "group_id",
	"home_club_id", "away_club_id", "round_number", "scheduled_date", "metadata"
]
const OPTIONAL_IDENTIFIERS = [
	"competition_id", "stage_id", "group_id", "home_club_id", "away_club_id"
]

var failures: Array[String] = []
var checks = 0
var temporary_path: String


func _initialize() -> void:
	temporary_path = "/tmp/neofutbol_fixtures_test_%s.json" % OS.get_process_id()
	var valid = _valid()
	var result = _parse(JSON.stringify([valid]), "test_season")
	_check(result.ok and result.errors.is_empty(), "partido válido")
	_check(result.data is Array and result.data.size() == 1, "colección con un partido")
	if result.ok:
		_check(result.data[0] is Fixture, "modelo MatchFixture")
		for field in FIELDS:
			_check(result.data[0].get(field) == valid[field], "conservación " + field)
		_check(typeof(result.data[0].round_number) == TYPE_INT, "jornada convertida a int")

	result = _parse("[]", "test_season")
	_check(result.ok and result.data.is_empty() and result.errors.is_empty(), "lista vacía")
	if result.ok:
		_check(result.data.is_typed() and result.data.get_typed_script() == Fixture,
			"lista vacía tipada")
	_expect_error(Parser.new().parse_file(temporary_path + ".missing"), "file_open")
	result = _parse("[\ninvalid")
	_expect_error(result, "json_syntax")
	_check(result.errors[0].has("line") and result.errors[0].line >= 0, "línea JSON")
	for root in ["{}", "null", "1", "true", '"text"']:
		_expect_error(_parse(root), "invalid_root")
	for value in [null, 1, true, false, [], "text"]:
		_expect_error(_parse(JSON.stringify([valid, value])), "invalid_record", 1)

	for field in FIELDS:
		var missing = valid.duplicate(true)
		missing.erase(field)
		_expect_error(_parse(JSON.stringify([valid, missing])), "missing_field", 1, field)

	for field in ["fixture_id", "season_id"]:
		for value in [null, 1, 1.5, true, false, [], {}, "", " ", "\t\r\n"]:
			var invalid = valid.duplicate(true)
			invalid[field] = value
			_expect_error(_parse(JSON.stringify([invalid])), "invalid_type", 0, field)
	for field in OPTIONAL_IDENTIFIERS:
		for value in [1, 1.5, true, false, [], {}, "", " ", "\t\r\n"]:
			var invalid = valid.duplicate(true)
			invalid[field] = value
			_expect_error(_parse(JSON.stringify([invalid])), "invalid_type", 0, field)
	for value in ["1", true, false, [], {}]:
		var invalid = valid.duplicate(true)
		invalid.round_number = value
		_expect_error(_parse(JSON.stringify([invalid])), "invalid_type", 0, "round_number")
	for value in [1, true, false, [], {}]:
		var invalid = valid.duplicate(true)
		invalid.scheduled_date = value
		_expect_error(_parse(JSON.stringify([invalid])), "invalid_type", 0, "scheduled_date")
	for value in [null, 1, true, false, [], "text"]:
		var invalid = valid.duplicate(true)
		invalid.metadata = value
		_expect_error(_parse(JSON.stringify([invalid])), "invalid_type", 0, "metadata")

	var unknown = valid.duplicate(true)
	for field in OPTIONAL_IDENTIFIERS + ["round_number", "scheduled_date"]:
		unknown[field] = null
	unknown.metadata = {}
	result = _parse(JSON.stringify([unknown]))
	_check(result.ok, "campos opcionales desconocidos")
	if result.ok:
		for field in OPTIONAL_IDENTIFIERS + ["round_number", "scheduled_date"]:
			_check(result.data[0].get(field) == null, "null conservado " + field)
		_check(result.data[0].metadata == {}, "metadata vacía conservada")

	var exact = valid.duplicate(true)
	exact.fixture_id = " Test_Fixture_Á \"\\{}[] "
	exact.season_id = " Test_Season "
	exact.competition_id = " Test_Competition "
	exact.stage_id = " Test_Stage "
	exact.group_id = " Test_Group "
	exact.home_club_id = " Test_Home "
	exact.away_club_id = " Test_Away "
	result = _parse(JSON.stringify([exact]), " Test_Season ")
	_check(result.ok, "identificadores exactos")
	if result.ok:
		for field in ["fixture_id", "season_id"] + OPTIONAL_IDENTIFIERS:
			_check(result.data[0].get(field) == exact[field], "identificador sin normalizar " + field)
	_expect_error(_parse(JSON.stringify([exact]), "Test_Season"),
		"season_mismatch", 0, "season_id")
	_check(_parse(JSON.stringify([valid]), "").ok, "comparación de temporada desactivada")

	for token in ["1", "1.0", "10e-1", "0.01e2", "2e0", "9007199254740991"]:
		result = _round(token)
		_check(result.ok, "jornada entera exacta " + token)
		if result.ok:
			var expected = 9007199254740991 if token == "9007199254740991" else (
				2 if token == "2e0" else 1
			)
			_check(result.data[0].round_number == expected, "valor exacto " + token)
			_check(typeof(result.data[0].round_number) == TYPE_INT, "tipo entero " + token)
	for token in ["1.5", "1.0000000000000001", "0.99999999999999999",
			"9007199254740992", "9007199254740993", "9223372036854775808",
			"1e999", "1e-999", "0e99999"]:
		_expect_error(_round(token), "invalid_type", 0, "round_number", token)
	for token in ["0", "-0", "-1", "-2.0"]:
		_expect_error(_round(token), "invalid_value", 0, "round_number", token)

	for date in ["0001-01-01", "1900-02-28", "2000-02-29", "2004-02-29", "9999-12-31"]:
		var dated = valid.duplicate(true)
		dated.scheduled_date = date
		result = _parse(JSON.stringify([dated]))
		_check(result.ok and result.data[0].scheduled_date == date, "fecha válida " + date)
	for date in ["0000-01-01", "1900-02-29", "2001-02-29", "2000-00-01",
			"2000-13-01", "2000-04-31", "2000-01-00", "2000-01-32",
			"2000-2-29", "00-02-29", "2000/02/29", "2000-02-29T12:00:00",
			" 2000-02-29", "text"]:
		var dated = valid.duplicate(true)
		dated.scheduled_date = date
		_expect_error(_parse(JSON.stringify([dated])), "invalid_value", 0, "scheduled_date")

	var phase_less = valid.duplicate(true)
	phase_less.stage_id = null
	phase_less.group_id = null
	result = _parse(JSON.stringify([phase_less]))
	_check(result.ok and result.data[0].stage_id == null and result.data[0].group_id == null,
		"fase y grupo opcionales")
	var phased = valid.duplicate(true)
	phased.stage_id = "knockout_stage"
	phased.group_id = "group_alpha"
	result = _parse(JSON.stringify([phased]))
	_check(result.ok and result.data[0].stage_id == "knockout_stage"
		and result.data[0].group_id == "group_alpha", "fase y grupo conservados")

	for field in FIELDS:
		var encoded = JSON.stringify(field)
		var escaped = '"\\u%04x%s"' % [field.unicode_at(0), field.substr(1)]
		for key in [encoded, escaped]:
			var text = JSON.stringify(valid).left(-1)
			text += "," + key + ":" + JSON.stringify(valid[field]) + "}"
			_expect_error(_parse("[" + text + "]"), "duplicate_field", 0, field)
		var escaped_text = JSON.stringify(valid).replace(encoded + ":", escaped + ":")
		_check(_parse("[" + escaped_text + "]").ok, "clave escapada única " + field)

	var extra = valid.duplicate(true)
	extra["unknown"] = {"fixture_id": null, "round_number": 1.5}
	extra.metadata["nested"] = [{"scheduled_date": null}, "synthetic"]
	result = _parse(JSON.stringify([extra]))
	_check(result.ok and result.data[0].get("unknown") == null, "campos adicionales ignorados")
	if result.ok:
		_check(result.data[0].metadata == extra.metadata, "metadata anidada conservada")

	var second = valid.duplicate(true)
	second.fixture_id = "second_fixture"
	second.metadata = valid.metadata.duplicate(true)
	result = _parse(JSON.stringify([valid, second]))
	_check(result.ok and result.data.size() == 2, "varios partidos")
	if result.ok:
		result.data[0].metadata.nested.values[0]["unknown"] = "modified"
		_check(result.data[1].metadata == second.metadata, "metadata independiente entre registros")
		var again = _parse(JSON.stringify([valid, second]))
		_check(again.ok and again.data[0].metadata == valid.metadata,
			"metadata independiente entre llamadas")
	_check(_read_temporary() == JSON.stringify([valid, second]), "archivo de entrada sin modificar")

	var other_season = valid.duplicate(true)
	other_season.season_id = "other_season"
	_check(_parse(JSON.stringify([valid, other_season])).ok,
		"mismo fixture_id permitido en temporadas diferentes")
	result = _parse(JSON.stringify([second, valid, valid]))
	_expect_error(result, "duplicate_fixture", 2, "fixture_id")
	_check(result.errors[0].get("first_index") == 1, "primera aparición del partido")
	var unlisted = valid.duplicate(true)
	unlisted.home_club_id = "unlisted_home"
	unlisted.away_club_id = "unlisted_away"
	_check(_parse(JSON.stringify([unlisted])).ok, "sin validación cruzada de clubes")

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
		"fixture_id": "test_fixture", "season_id": "test_season",
		"competition_id": "test_competition", "stage_id": "test_stage",
		"group_id": "test_group", "home_club_id": "test_home",
		"away_club_id": "test_away", "round_number": 1,
		"scheduled_date": "2000-02-29",
		"metadata": {"nested": {"values": [{"unknown": null}, true, "synthetic"]}}
	}


func _parse(text: String, expected_season_id: String = "") -> Dictionary:
	var file = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		failures.append("No se pudo crear la entrada temporal")
		return {"ok": false, "data": null, "errors": []}
	file.store_string(text)
	file.close()
	return Parser.new().parse_file(temporary_path, expected_season_id)


func _round(token: String) -> Dictionary:
	var record = _valid()
	record.round_number = "__number_token__"
	return _parse(JSON.stringify([record]).replace('"__number_token__"', token))


func _read_temporary() -> String:
	var file = FileAccess.open(temporary_path, FileAccess.READ)
	if file == null:
		return ""
	var text = file.get_as_text()
	file.close()
	return text


func _expect_error(result: Dictionary, code: String, index: int = -1,
		field: String = "", context: String = "") -> void:
	_check(not result.ok and result.data == null, "fallo sin colección parcial " + code)
	_check(result.errors.size() == 1, "primer diagnóstico " + code)
	if result.errors.is_empty():
		return
	var error = result.errors[0]
	_check(error.code == code, "código esperado %s, recibido %s%s" % [
		code, error.get("code"), " para " + context if not context.is_empty() else ""
	])
	_check(error.file is String and not error.file.is_empty(), "archivo del error " + code)
	_check(error.message is String and not error.message.is_empty(), "mensaje " + code)
	if index >= 0:
		_check(error.get("index") == index, "índice exacto " + code)
	if not field.is_empty():
		_check(error.get("field") == field, "campo exacto " + code)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
