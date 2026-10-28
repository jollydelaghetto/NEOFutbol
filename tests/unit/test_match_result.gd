extends SceneTree

const Result = preload("res://game/scripts/data/match_result.gd")

var failures: Array[String] = []
var checks = 0


func _initialize() -> void:
	var pending = Result.new()
	_check(pending is RefCounted, "MatchResult deriva de RefCounted")
	_check(pending.fixture_id == "", "fixture_id inicial")
	_check(pending.season_id == "", "season_id inicial")
	_check(pending.home_goals == null and pending.away_goals == null,
		"marcadores desconocidos como null")
	_check(pending.status == Result.Status.PENDING, "estado pendiente explícito")
	_check(Result.Status.PENDING != Result.Status.FINAL, "estados diferentes")

	var final = Result.new()
	final.fixture_id = "fixture_a"
	final.season_id = "season_a"
	final.home_goals = 0
	final.away_goals = 3
	final.status = Result.Status.FINAL
	_check(final.fixture_id == "fixture_a", "fixture_id conservado")
	_check(final.season_id == "season_a", "season_id conservado")
	_check(final.home_goals == 0 and final.away_goals == 3, "marcador conservado")
	_check(final.status == Result.Status.FINAL, "estado finalizado explícito")
	_check(pending.home_goals == null and pending.away_goals == null,
		"resultado pendiente independiente")

	if failures.is_empty():
		print("PASS: %d comprobaciones" % checks)
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: " + failure)
		quit(1)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
