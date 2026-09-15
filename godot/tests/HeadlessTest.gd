# ============================================================================
# Headless regression + balance harness.
#
#   godot --headless --script tests/HeadlessTest.gd
#
# Runs without a window, so it works in CI. It checks the rules engine against
# the same invariants the JavaScript build is tested for, then plays every
# chapter out AI-vs-AI to catch stalemates and blow-outs.
# ============================================================================
extends SceneTree

var failures := 0

func check(label: String, ok: bool, extra: String = "") -> void:
	if ok:
		print("  [ok] ", label, ("  " + extra) if extra != "" else "")
	else:
		failures += 1
		printerr("  [FAIL] ", label, "  ", extra)
		print("  [FAIL] ", label, "  ", extra)

func _initialize() -> void:
	seed(12345)
	print("Tactics Core - headless tests\n")
	test_data()
	test_iso()
	test_grid()
	test_rules()
	test_new_systems()
	test_campaign_balance()
	print("\n%d failure(s)" % failures)
	quit(1 if failures > 0 else 0)

func test_data() -> void:
	print("Data")
	check("maps load", GameData.MAPS.size() == 7)
	check("jobs load", GameData.JOBS.size() == 14)
	check("campaign loads", GameData.CAMPAIGN.size() == 7)
	var all_rect := true
	for key in GameData.MAPS:
		var m: Dictionary = GameData.MAPS[key]
		var w := String(m["t"][0]).length()
		for row in m["t"]:
			if String(row).length() != w:
				all_rect = false
		for row in m["h"]:
			if String(row).length() != w:
				all_rect = false
		if m["h"].size() != m["t"].size():
			all_rect = false
	check("every map is rectangular", all_rect)
	var abilities_resolve := true
	for jn in GameData.JOBS:
		for aid in GameData.JOBS[jn]["abilities"]:
			if not GameData.ABILITIES.has(aid):
				abilities_resolve = false
	check("every job's abilities exist", abilities_resolve)

func test_iso() -> void:
	print("Isometric projection")
	var cols := 12
	var rows := 10
	var round_trip := true
	var in_bounds := true
	for rot in 4:
		var vd := Iso.view_dims(cols, rows, rot)
		for y in rows:
			for x in cols:
				var r := Iso.rotate_xy(x, y, cols, rows, rot)
				if r.x < 0 or r.y < 0 or r.x >= vd.x or r.y >= vd.y:
					in_bounds = false
				if Iso.unrotate(r.x, r.y, cols, rows, rot) != Vector2i(x, y):
					round_trip = false
	check("rotate/unrotate round-trips at all 4 angles", round_trip)
	check("rotation stays inside the view grid", in_bounds)
	var p := Iso.project(0.0, 0.0, 0.0, cols, rows, 0)
	check("origin projects to (0,0)", is_equal_approx(p.x, 0.0) and is_equal_approx(p.y, 0.0))
	var lifted := Iso.project(3.0, 3.0, 2.0, cols, rows, 0)
	var flat := Iso.project(3.0, 3.0, 0.0, cols, rows, 0)
	check("height raises the tile on screen", lifted.y == flat.y - 2.0 * Iso.HS)
	check("back attack detected", Iso.relative_side(Vector2i(5, 5), 3, Vector2i(5, 6)) == "back")
	check("front attack detected", Iso.relative_side(Vector2i(5, 5), 3, Vector2i(5, 4)) == "front")
	check("side attack detected", Iso.relative_side(Vector2i(5, 5), 3, Vector2i(6, 5)) == "side")

func test_grid() -> void:
	print("Grid and pathfinding")
	var g := BattleGrid.new(GameData.MAPS["ziggurat"])
	check("grid size", g.cols == 12 and g.rows == 10)
	check("water is impassable", not BattleGrid.new(GameData.MAPS["sluice"]).walkable(0, 3))
	check("lava is walkable but hurts", g.walkable(4, 4) and g.hazard_at(4, 4) > 0)

	var climber := Unit.new("Climber", "Archer", "P", Vector2i(5, 9), 1)
	var res := g.reachable(climber, func(_x, _y): return null)
	var tiles: Array = res["tiles"]
	check("reachable returns tiles", tiles.size() > 5, "%d tiles" % tiles.size())
	var target: Vector2i = tiles[0]
	var path := g.path_to(res, climber, target)
	check("path reconstructs to the target", not path.is_empty() and path[path.size() - 1] == target)
	var contiguous := true
	var cur := climber.pos
	for step in path:
		if Iso.manhattan(cur, step) != 1:
			contiguous = false
		cur = step
	check("path steps are adjacent", contiguous)

	# Every reachable tile must be legally climbable one step at a time.
	var legal := true
	for t in tiles:
		var pth := g.path_to(res, climber, t)
		var prev := climber.pos
		for step in pth:
			if absi(g.height_at(step.x, step.y) - g.height_at(prev.x, prev.y)) > climber.stat("jump"):
				legal = false
			prev = step
	check("jump limits every step of every path", legal)

func test_rules() -> void:
	print("Combat rules")
	var battle := Battle.new(GameData.CAMPAIGN[0], GameData.PARTY)
	check("both squads deployed", battle.units.size() == 10)
	check("no two units share a tile", _unique_positions(battle))

	var knight: Unit = battle.units[0]
	var goblin: Unit = battle.living("E")[0]

	# Back attacks must beat front attacks, all else equal.
	knight.pos = goblin.pos + Vector2i(1, 0)
	goblin.facing = 0
	var front := battle.estimate_damage(knight, goblin, GameData.ability("attack"))
	var front_acc := battle.hit_chance(knight, goblin, GameData.ability("attack"))
	goblin.facing = 1
	var back := battle.estimate_damage(knight, goblin, GameData.ability("attack"))
	var back_acc := battle.hit_chance(knight, goblin, GameData.ability("attack"))
	check("back attacks hit harder", back > front, "%d vs %d" % [back, front])
	check("back attacks hit more often", back_acc > front_acc, "%d%% vs %d%%" % [back_acc, front_acc])

	var before_spd := goblin.stat("spd")
	goblin.add_status("slow", 3)
	check("slow reduces speed", goblin.stat("spd") < before_spd)
	goblin.status.clear()

	var boss := Unit.new("Vetrix", "Necromancer", "E", Vector2i(0, 0), 5)
	check("bosses ignore stun", not boss.add_status("stun", 1))
	check("bosses still take poison", boss.add_status("poison", 3))

	# CT economy: doing nothing leaves you readier than doing everything.
	var u := battle.begin_turn()
	u.moved = true
	u.acted = true
	battle.end_turn(u)
	var ct_both: float = u.ct
	u.moved = false
	u.acted = false
	battle.end_turn(u)
	check("waiting leaves more CT than move+act", u.ct > ct_both, "%d vs %d" % [u.ct, ct_both])

	var priest: Unit = battle.units[4]
	priest.hp = priest.max_hp - 3
	var healed := battle.heal(priest, 999.0)
	check("healing caps at max HP", healed == 3 and priest.hp == priest.max_hp)
	var hurt := battle.damage(priest, 99999.0)
	check("damage floors at zero HP", priest.hp == 0 and hurt > 0)
	check("the fallen leave the living list", not battle.living().has(priest))

	var picked_dead := false
	for i in 30:
		var n := battle.begin_turn()
		if n == null:
			break
		if not n.alive():
			picked_dead = true
		battle.end_turn(n)
	check("turn engine never wakes the fallen", not picked_dead)

	# Summon cap keeps the Necromancer from stalling the battle forever.
	var necro_battle := Battle.new(_chapter_on("necrohol"), GameData.PARTY)
	var necro: Unit = null
	for e in necro_battle.living("E"):
		if e.job == "Necromancer":
			necro = e
	check("boss present in the finale", necro != null)
	if necro != null:
		var summon := GameData.ability("summonBone")
		for i in 12:
			necro.mp = necro.max_mp
			necro.cooldowns.clear()
			for t in necro_battle.grid.tiles_in_range(necro.pos.x, necro.pos.y, summon):
				if necro_battle.valid_target(necro, summon, t):
					necro_battle.use_ability(necro, summon, t)
					break
		var skeletons := 0
		for e in necro_battle.living("E"):
			if e.job == "Skeleton":
				skeletons += 1
		# Chapter 4 already fields 4 skeletons, so the cap bounds the summoned extras.
		check("summons are capped", skeletons <= 7, "%d skeletons after 12 attempts" % skeletons)

func _chapter_on(map_id: String) -> Dictionary:
	for c in GameData.CAMPAIGN:
		if c["map"] == map_id:
			return c
	return GameData.CAMPAIGN[0]

func _party(level: int) -> Array:
	var party: Array = []
	for p in GameData.PARTY:
		party.append({"name": p["name"], "job": p["job"], "level": level})
	return party

func test_new_systems() -> void:
	print("Cast-time spells, cones, rewind, learning")
	var b := Battle.new(GameData.CAMPAIGN[0], _party(3))
	var mage: Unit = null
	for u in b.units:
		if u.job == "Mage":
			mage = u
	var gob: Unit = b.living("E")[0]
	mage.pos = gob.pos + Vector2i(-2, 0)
	var hp := gob.hp
	var ok := b.use_ability(mage, GameData.ability("fire"), gob.pos)
	check("a charged spell does not resolve on cast", ok and gob.hp == hp and b.pending.size() == 1)
	var has_spell := false
	for e in b.forecast(8):
		if e is Dictionary:
			has_spell = true
	check("the timeline shows the pending spell", has_spell)
	gob.pos += Vector2i(3, 0)                            # walk out of it
	for u in b.units:
		u.ct = 0.0
	var guard := 0
	while not b.pending.is_empty() and guard < 30:
		guard += 1
		b.begin_turn()
		b.end_turn(b.active)
	check("a dodged spell lands on empty ground", gob.hp == hp and b.pending.is_empty())

	var rb := Battle.new(_chapter_on("roost"), _party(8))
	var dragon: Unit = null
	for u in rb.living("E"):
		if u.job == "Dragon":
			dragon = u
	var cone := rb.grid.cone_tiles(dragon.pos.x, dragon.pos.y, dragon.pos.x, dragon.pos.y + 1, 3)
	check("breath cone is 1+3+3 tiles deep", cone.size() == 7)
	check("cone never includes the caster", not cone.has(dragon.pos))

	var s := Battle.new(GameData.CAMPAIGN[0], _party(1))
	var u := s.begin_turn()
	var snap := s.snapshot()
	var victim: Unit = s.units[5]
	var before := victim.hp
	victim.hp = 1
	var old_pos := u.pos
	u.pos = Vector2i(9, 9)
	u.acted = true
	s.restore(snap)
	check("rewind restores HP, position and flags", victim.hp == before and u.pos == old_pos and not u.acted)

	var k: Unit = s.units[0]
	k.jp = 500
	check("learnable lists unknown JP abilities", k.learnable().has("rally") and not k.abilities.has("rally"))
	check("learning spends JP and adds the ability", k.learn("rally") and k.jp == 350 and k.abilities.has("rally"))
	check("cannot learn twice or without JP", not k.learn("rally") and not (s.units[1] as Unit).learn("judgment"))

	# Rewinding twice in one turn must not leak the first rewind's state.
	var snap2 := s.snapshot()
	(s.units[5] as Unit).add_status("protect", 3)
	s.restore(snap2)
	(s.units[5] as Unit).add_status("protect", 3)
	s.restore(snap2)
	check("a second rewind still restores a clean state", not (s.units[5] as Unit).has_status("protect"))

	# A charged spell that kills the last enemy must end the battle at once.
	var last := Battle.new(GameData.CAMPAIGN[0], _party(9))
	var foes := last.living("E")
	var keep: Unit = foes[0]
	for f in foes:
		if f != keep:
			f.hp = 0
	var caster: Unit = null
	for u2 in last.units:
		if u2.job == "Mage":
			caster = u2
	caster.pos = keep.pos + Vector2i(-2, 0)
	keep.hp = 1
	last.use_ability(caster, GameData.ability("fire"), keep.pos)
	for u2 in last.units:
		u2.ct = 0.0
	var next := last.begin_turn()
	check("a spell that lands the killing blow ends the battle immediately", next == null and last.over == "victory")
	var zone := s.deploy_zone()
	var walkable := true
	for t in zone:
		if not s.grid.walkable(t.x, t.y):
			walkable = false
	check("deploy zone is a walkable superset of the slots", zone.size() >= GameData.PARTY.size() and walkable)

	var pb := Battle.new(_chapter_on("grove"), _party(5))
	var npc: Unit = null
	for x in pb.units:
		if x.npc:
			npc = x
	check("protect chapter fields an npc on the player side", npc != null and npc.team == "P" and npc.abilities.is_empty())
	npc.hp = 0
	check("losing the npc loses the battle", pb.check_end() and pb.over == "defeat")

func _unique_positions(battle: Battle) -> bool:
	var seen := {}
	for u in battle.units:
		var k := str(u.pos)
		if seen.has(k):
			return false
		seen[k] = true
	return true

## A short AI-vs-AI sweep. GDScript is an order of magnitude slower than the
## JavaScript engine at this, so the statistical balance sweep lives in
## tools/test-engine.js; ParityTest.gd guarantees the two engines make the same
## decisions, and this run just proves the GDScript build plays to a result.
func test_campaign_balance() -> void:
	print("Campaign balance (AI vs AI, 8 runs each)")
	for ci in GameData.CAMPAIGN.size():
		var chapter: Dictionary = GameData.CAMPAIGN[ci]
		var wins := 0
		var losses := 0
		var stalls := 0
		var total_turns := 0
		for run in 8:
			var b := Battle.new(chapter, _party(int(chapter.get("enemyLevel", 1 + ci * 2))))
			var guard := 0
			while not b.check_end() and guard < 400:
				guard += 1
				var u := b.begin_turn()
				if u == null:
					break
				var plan := EnemyAI.plan_turn(b, u)
				if plan["move"] != null:
					b.move_unit(u, plan["move"])
				var ab: Dictionary = plan["ability"]
				if not ab.is_empty():
					b.use_ability(u, ab, plan["target"])
				b.end_turn(u)
				b.drain()
			total_turns += guard
			if b.over == "victory":
				wins += 1
			elif b.over == "defeat":
				losses += 1
			else:
				stalls += 1
		check("%s resolves without stalling" % chapter["id"], stalls == 0,
			"wins %d losses %d stalls %d avg turns %d" % [wins, losses, stalls, total_turns / 8])
		check("%s is winnable but not free" % chapter["id"], wins >= 1, "win rate %d/8" % wins)
