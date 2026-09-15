# ============================================================================
# Cross-engine parity test.
#
#   godot --headless --script tests/ParityTest.gd
#
# Replays the deterministic scenarios recorded from the JavaScript engine
# (tools/gen-parity-fixture.js) through this GDScript engine and diffs every
# answer. If the two builds ever disagree about a hit chance, a damage roll's
# expectation, a reachable set or an AI decision, this fails and names it.
# ============================================================================
extends SceneTree

var failures := 0
var checks := 0

func fail(msg: String) -> void:
	failures += 1
	if failures <= 25:
		print("  [FAIL] ", msg)
		printerr("  [FAIL] ", msg)

func _initialize() -> void:
	var file := FileAccess.open("res://tests/parity_fixture.json", FileAccess.READ)
	if file == null:
		printerr("parity_fixture.json missing — run: node tools/gen-parity-fixture.js")
		quit(1)
		return
	var fixture: Dictionary = JSON.parse_string(file.get_as_text())
	print("Tactics Core - JS <-> GDScript parity\n")
	for chapter_id in fixture["chapters"]:
		check_chapter(chapter_id, fixture["chapters"][chapter_id])
	print("\n%d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures > 0 else 0)

## Rebuilds the exact board the JavaScript fixture was recorded from.
func build(chapter_id: String) -> Battle:
	var chapter := GameData.chapter(chapter_id)
	var party: Array = []
	for p in GameData.PARTY:
		party.append({"name": p["name"], "job": p["job"], "level": 5})
	var b := Battle.new(chapter, party)
	for i in b.units.size():
		var u: Unit = b.units[i]
		u.ct = float((i * 13) % 100)
		u.hp = maxi(1, roundi(u.max_hp * (0.5 + float((i * 7) % 5) / 10.0)))
		u.mp = u.max_mp
		u.facing = i % 4
	return b

func by_name(b: Battle, n: String) -> Unit:
	for u in b.units:
		if u.unit_name == n:
			return u
	return null

func eq(label: String, a, e) -> void:
	checks += 1
	if a != e:
		fail("%s: got %s, expected %s" % [label, str(a), str(e)])

func check_chapter(chapter_id: String, rec: Dictionary) -> void:
	print(chapter_id)
	var b := build(chapter_id)
	var before := failures

	# --- unit stats ------------------------------------------------------
	eq("%s unit count" % chapter_id, b.units.size(), (rec["units"] as Array).size())
	for row in rec["units"]:
		var u := by_name(b, row["name"])
		if u == null:
			fail("%s: missing unit %s" % [chapter_id, row["name"]])
			continue
		var tag := "%s/%s" % [chapter_id, u.unit_name]
		eq(tag + " pos", "%d,%d" % [u.pos.x, u.pos.y], "%d,%d" % [int(row["x"]), int(row["y"])])
		eq(tag + " maxHp", u.max_hp, int(row["maxHp"]))
		eq(tag + " hp", u.hp, int(row["hp"]))
		eq(tag + " atk", u.stat("atk"), int(row["atk"]))
		eq(tag + " def", u.stat("def"), int(row["def"]))
		eq(tag + " mag", u.stat("mag"), int(row["mag"]))
		eq(tag + " res", u.stat("res"), int(row["res"]))
		eq(tag + " spd", u.stat("spd"), int(row["spd"]))
		eq(tag + " move", u.stat("move"), int(row["move"]))
		eq(tag + " jump", u.stat("jump"), int(row["jump"]))

	# --- combat maths ----------------------------------------------------
	for row in rec["combat"]:
		var a := by_name(b, row["att"])
		var d := by_name(b, row["def"])
		if a == null or d == null:
			continue
		var ab := GameData.ability(String(row["ability"]))
		var tag := "%s/%s->%s/%s" % [chapter_id, a.unit_name, d.unit_name, row["ability"]]
		eq(tag + " side", Iso.relative_side(d.pos, d.facing, a.pos), String(row["side"]))
		eq(tag + " acc", b.hit_chance(a, d, ab), int(row["acc"]))
		eq(tag + " dmg", b.estimate_damage(a, d, ab), int(row["dmg"]))
		eq(tag + " crit", b.crit_chance(a, d), int(row["crit"]))
		eq(tag + " valid", b.valid_target(a, ab, d.pos), bool(row["valid"]))

	# --- movement --------------------------------------------------------
	for row in rec["reach"]:
		var u := by_name(b, row["name"])
		if u == null:
			continue
		var res := b.reachable_for(u)
		var tiles: Array = res["tiles"]
		var sum := 0
		for t in tiles:
			sum += t.x * 31 + t.y * 17
		eq("%s/%s reachable count" % [chapter_id, u.unit_name], tiles.size(), int(row["tiles"]))
		eq("%s/%s reachable checksum" % [chapter_id, u.unit_name], sum, int(row["sum"]))

	for row in rec["field"]:
		var u := by_name(b, row["name"])
		if u == null:
			continue
		var foe_tiles: Array = []
		for f in b.living("E" if u.team == "P" else "P"):
			foe_tiles.append(f.pos)
		var field := b.grid.distance_field(foe_tiles, u.stat("jump"))
		var sum := 0
		var reachable := 0
		for v in field:
			if v >= 0:
				sum += v
				reachable += 1
		eq("%s/%s field size" % [chapter_id, u.unit_name], reachable, int(row["reachable"]))
		eq("%s/%s field checksum" % [chapter_id, u.unit_name], sum, int(row["sum"]))

	# --- AI decisions (no RNG, so they must match exactly) ---------------
	for row in rec["plans"]:
		var u := by_name(b, row["name"])
		if u == null:
			continue
		var plan := EnemyAI.plan_turn(b, u)
		var tag := "%s/%s plan" % [chapter_id, u.unit_name]
		var got_move: String = "%d,%d" % [plan["move"].x, plan["move"].y] if plan["move"] != null else "null"
		var want_move: String = String(row["move"]) if row["move"] != null else "null"
		eq(tag + " move", got_move, want_move)
		var ab: Dictionary = plan["ability"]
		var got_ability: String = String(ab["id"]) if not ab.is_empty() else "null"
		var want_ability: String = String(row["ability"]) if row["ability"] != null else "null"
		eq(tag + " ability", got_ability, want_ability)
		if not ab.is_empty() and row["target"] != null:
			eq(tag + " target", "%d,%d" % [plan["target"].x, plan["target"].y], String(row["target"]))
		eq(tag + " score", snappedf(float(plan["score"]), 0.001), snappedf(float(row["score"]), 0.001))

	# --- turn order ------------------------------------------------------
	var got_forecast: Array = []
	for u in b.forecast(8):
		got_forecast.append(u.unit_name)
	eq("%s forecast" % chapter_id, ", ".join(PackedStringArray(got_forecast)),
		", ".join(PackedStringArray(rec["forecast"])))

	if failures == before:
		print("  [ok] %s matches the JavaScript engine" % chapter_id)
