# ============================================================================
# The rules engine: charge-time turn order and every combat resolution.
#
# No node, no rendering — it can be driven headlessly, which is exactly what
# tests/HeadlessTest.gd does. Anything the view needs to animate is pushed onto
# `events` as a plain dictionary and drained by the caller.
# ============================================================================
class_name Battle
extends RefCounted

const PHYS_K := 1.7        # physical damage scalar
const MAG_K := 1.5         # magical damage scalar
const BASE_ACC := 90.0
const CRIT_MULT := 1.5

## CT left over after a turn — the classic "do less, act sooner" trade.
const CT_AFTER := {"both": 0.0, "act": 20.0, "move": 40.0, "wait": 60.0}

var chapter: Dictionary
var grid: BattleGrid
var units: Array[Unit] = []
var events: Array[Dictionary] = []
var turn: int = 0
var over: String = ""                  # "" | "victory" | "defeat"
var active: Unit = null
var items: Dictionary = {}
var pending: Array[Dictionary] = []    # charging spells waiting to land
var level_offset: int = 0
var _next_spell_id: int = 0

func _init(p_chapter: Dictionary, party: Array, opts: Dictionary = {}) -> void:
	chapter = p_chapter
	grid = BattleGrid.new(GameData.MAPS[p_chapter["map"]])
	items = GameData.START_ITEMS.duplicate()
	level_offset = int(opts.get("levelOffset", 0))

	var deploy: Array = p_chapter["deploy"]
	for i in party.size():
		var p: Dictionary = party[i]
		var slot: Array = deploy[mini(i, deploy.size() - 1)]
		var u := add_unit(Unit.new(p["name"], p["job"], "P", Vector2i(slot[0], slot[1]), int(p.get("level", 1))))
		u.xp = int(p.get("xp", 0))
		u.jp = int(p.get("jp", 0))
		for id in p.get("learned", []):
			if not u.abilities.has(id) and (u.job_def["abilities"] as Array).has(id):
				u.abilities.append(id)
				u.learned.append(id)
	if p_chapter.has("npc"):
		var n: Array = p_chapter["npc"]
		var civ := add_unit(Unit.new(n[0], n[1], "P", Vector2i(int(n[2]), int(n[3])), maxi(1, int(p_chapter.get("enemyLevel", 1)))))
		civ.npc = true

	var chapter_index := 0
	for i in GameData.CAMPAIGN.size():
		if GameData.CAMPAIGN[i]["id"] == p_chapter["id"]:
			chapter_index = i
	var base_level: int = int(p_chapter["enemyLevel"]) if p_chapter.has("enemyLevel") else maxi(1, 1 + chapter_index * 2)
	for e in p_chapter["enemies"]:
		add_unit(Unit.new(e[0], e[1], "E", Vector2i(e[2], e[3]), maxi(1, base_level + level_offset)))

	for u in units:
		u.facing = face_nearest_foe(u)

# ------------------------------------------------------- deploy + rewind --
func deploy_zone() -> Array[Vector2i]:
	return grid.deploy_zone(chapter)

## Swap or move a party member inside the deploy zone before turn one.
func place_unit(u: Unit, target: Vector2i) -> bool:
	if turn > 0 or u.team != "P" or u.npc:
		return false
	if not deploy_zone().has(target):
		return false
	var other := unit_at(target.x, target.y)
	if other != null and (other.team != "P" or other.npc):
		return false
	if other != null:
		other.pos = u.pos
	u.pos = target
	for v in units:
		v.facing = face_nearest_foe(v)
	return true

## Everything the rules can change, copied at the start of a player turn so
## Story mode can rewind the whole turn. Unit instances are kept, so the
## view's references survive a restore.
func snapshot() -> Dictionary:
	var us: Array = []
	for u in units:
		us.append({
			"pos": u.pos, "facing": u.facing, "hp": u.hp, "mp": u.mp, "ct": u.ct,
			"moved": u.moved, "acted": u.acted, "counter_ready": u.counter_ready,
			"xp": u.xp, "jp": u.jp, "level": u.level,
			"max_hp": u.max_hp, "max_mp": u.max_mp,
			"base_atk": u.base_atk, "base_def": u.base_def, "base_mag": u.base_mag,
			"base_res": u.base_res, "base_spd": u.base_spd,
			"status": u.status.duplicate(), "cooldowns": u.cooldowns.duplicate(),
			"abilities": u.abilities.duplicate(), "learned": u.learned.duplicate(),
			"start_pos": u.start_pos, "start_facing": u.start_facing,
		})
	var ps: Array = []
	for p in pending:
		ps.append(p.duplicate())
	return {"turn": turn, "over": over, "active_id": active.id if active != null else -1,
		"items": items.duplicate(), "pending": ps, "unit_count": units.size(), "units": us}

func restore(snap: Dictionary) -> bool:
	if snap.is_empty():
		return false
	units.resize(int(snap["unit_count"]))          # drop anything summoned since
	var us: Array = snap["units"]
	for i in us.size():
		var u: Unit = units[i]
		var d: Dictionary = us[i]
		for k in d:
			match k:
				"status": u.status = (d[k] as Dictionary).duplicate()
				"cooldowns": u.cooldowns = (d[k] as Dictionary).duplicate()
				"abilities": u.abilities = (d[k] as Array).duplicate()
				"learned": u.learned = (d[k] as Array).duplicate()
				_: u.set(k, d[k])
	items = (snap["items"] as Dictionary).duplicate()
	pending.clear()
	for p in snap["pending"]:
		pending.append((p as Dictionary).duplicate())
	turn = int(snap["turn"])
	over = String(snap["over"])
	active = units[int(snap["active_id"])] if int(snap["active_id"]) >= 0 else null
	events.clear()
	emit({"type": "rewind"})
	return true

func add_unit(u: Unit) -> Unit:
	u.id = units.size()
	units.append(u)
	return u

func emit(e: Dictionary) -> void:
	events.append(e)

func drain() -> Array[Dictionary]:
	var out := events
	events = [] as Array[Dictionary]
	return out

func living(team: String = "") -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.alive() and (team == "" or u.team == team):
			out.append(u)
	return out

func unit_at(x: int, y: int) -> Unit:
	for u in units:
		if u.alive() and u.pos.x == x and u.pos.y == y:
			return u
	return null

func ko_at(x: int, y: int) -> Unit:
	for u in units:
		if not u.alive() and u.pos.x == x and u.pos.y == y:
			return u
	return null

func face_nearest_foe(u: Unit) -> int:
	var foes := living("E" if u.team == "P" else "P")
	if foes.is_empty():
		return u.facing
	var best: Unit = foes[0]
	for f in foes:
		if Iso.manhattan(u.pos, f.pos) < Iso.manhattan(u.pos, best.pos):
			best = f
	return Iso.facing_toward(u.pos, best.pos)

# ------------------------------------------------------------- turn engine --
## Advance charge time until somebody is ready. KO'd units never tick.
func tick_ct() -> Unit:
	for guard in 10000:
		var landing: Array[Dictionary] = []
		for p in pending:
			if float(p["ct"]) >= 100.0:
				landing.append(p)
		if not landing.is_empty():
			landing.sort_custom(func(a, b): return float(a["ct"]) > float(b["ct"]))
			for p in landing:
				resolve_pending(p)
			continue
		var ready: Array[Unit] = []
		for u in living():
			if u.ct >= 100.0:
				ready.append(u)
		if not ready.is_empty():
			ready.sort_custom(func(a, b):
				if a.ct != b.ct:
					return a.ct > b.ct
				if a.stat("spd") != b.stat("spd"):
					return a.stat("spd") > b.stat("spd")
				return a.id < b.id)
			return ready[0]
		for u in living():
			u.ct += u.stat("spd")
		for p in pending:
			p["ct"] = float(p["ct"]) + float(p["speed"])
	var l := living()
	return l[0] if not l.is_empty() else null

## A charged spell lands on whatever is there now - not what was there.
func resolve_pending(p: Dictionary) -> void:
	pending.erase(p)
	var caster: Unit = units[int(p["casterId"])] if int(p["casterId"]) < units.size() else null
	if caster == null or not caster.alive():
		emit({"type": "fizzle", "spell": p, "unit": caster})
		return
	var ability := GameData.ability(String(p["abilityId"]))
	var target := Vector2i(int(p["tx"]), int(p["ty"]))
	var tiles := grid.footprint(caster, ability, target)
	var hits := affected_on(caster, ability, tiles)
	emit({"type": "land", "unit": caster, "ability": ability, "target": target, "tiles": tiles})
	for t in hits:
		_resolve_on(caster, ability, t)
	emit({"type": "resolve", "unit": caster, "ability": ability, "tiles": tiles})

## Preview of the next few actors, for the turn-order strip. Entries are
## Units, or {"spell": pending} for a charged spell about to land.
func forecast(n: int) -> Array:
	var sim: Array = []
	for u in living():
		sim.append({"u": u, "ct": u.ct, "spd": float(u.stat("spd"))})
	var spells: Array = []
	for p in pending:
		spells.append({"p": p, "ct": float(p["ct"])})
	var out: Array = []
	for guard in 4000:
		if out.size() >= n:
			break
		var landing: Array = []
		for s in spells:
			if float(s["ct"]) >= 100.0:
				landing.append(s)
		if not landing.is_empty():
			for s in landing:
				out.append({"spell": s["p"]})
				spells.erase(s)
			continue
		# Same tie-break as tick_ct: higher CT, then higher Speed, then id order.
		var best = null
		for s in sim:
			if s["ct"] < 100.0:
				continue
			if best == null or s["ct"] > best["ct"] or (s["ct"] == best["ct"] and s["spd"] > best["spd"]):
				best = s
		if best != null:
			out.append(best["u"])
			best["ct"] = CT_AFTER["act"]
			continue
		for s in sim:
			s["ct"] += s["spd"]
		for s in spells:
			s["ct"] = float(s["ct"]) + float(s["p"]["speed"])
	if out.size() > n:
		out.resize(n)
	return out

func begin_turn() -> Unit:
	if check_end():
		return null
	var u := tick_ct()
	# A charged spell landing during the tick can decide the battle.
	if u == null or check_end():
		return null
	active = u
	turn += 1
	u.ct = 0.0
	u.moved = false
	u.acted = false
	u.start_pos = u.pos
	u.start_facing = u.facing

	for aid in u.cooldowns.keys().duplicate():
		u.cooldowns[aid] = int(u.cooldowns[aid]) - 1
		if int(u.cooldowns[aid]) <= 0:
			u.cooldowns.erase(aid)

	var skip := false
	for sid in u.status.keys().duplicate():
		var sd: Dictionary = GameData.STATUS[sid]
		if sd.has("hpTickPct"):
			var pct := float(sd["hpTickPct"])
			var mag := maxi(2, roundi(u.max_hp * absf(pct)))
			if pct < 0.0:
				damage(u, mag, {"kind": "status", "status": sid})
			else:
				heal(u, mag, {"kind": "status", "status": sid})
		if sd.get("skip", false):
			skip = true
		u.status[sid] = int(u.status[sid]) - 1
		if int(u.status[sid]) <= 0:
			u.status.erase(sid)
			emit({"type": "statusEnd", "unit": u, "status": sid})

	if not u.alive():
		emit({"type": "turnSkipped", "unit": u, "reason": "ko"})
		return begin_turn()
	if skip:
		emit({"type": "turnSkipped", "unit": u, "reason": "stun"})
		u.ct = CT_AFTER["wait"]
		return begin_turn()

	emit({"type": "turnStart", "unit": u})
	return u

func end_turn(u: Unit = null) -> void:
	if u == null:
		u = active
	if u == null:
		return
	if u.passive == "focus" and not u.acted:
		u.mp = mini(u.max_mp, u.mp + 4)
		emit({"type": "focus", "unit": u})
	var kind := "wait"
	if u.moved and u.acted:
		kind = "both"
	elif u.acted:
		kind = "act"
	elif u.moved:
		kind = "move"
	u.ct = CT_AFTER[kind]
	for e in units:
		e.counter_ready = true
	emit({"type": "turnEnd", "unit": u, "ctKind": kind})
	active = null

# ---------------------------------------------------------------- movement --
func reachable_for(u: Unit) -> Dictionary:
	return grid.reachable(u, func(x, y): return unit_at(x, y))

func move_unit(u: Unit, target: Vector2i) -> Array[Vector2i]:
	var res := reachable_for(u)
	var path := grid.path_to(res, u, target)
	if path.is_empty():
		return path
	var from := u.pos
	var last: Vector2i = path[path.size() - 1]
	var prev: Vector2i = path[path.size() - 2] if path.size() > 1 else from
	u.pos = last
	u.facing = Iso.facing_toward(prev, last)
	u.moved = true
	emit({"type": "move", "unit": u, "from": from, "path": path})
	var haz := grid.hazard_at(u.pos.x, u.pos.y)
	if haz > 0:
		damage(u, haz, {"kind": "hazard"})
	return path

## Only offered before acting, so restoring the snapshot is always safe.
func undo_move(u: Unit) -> bool:
	if not u.moved or u.acted:
		return false
	u.pos = u.start_pos
	u.facing = u.start_facing
	u.moved = false
	emit({"type": "undoMove", "unit": u})
	return true

# ------------------------------------------------------------------ combat --
func hit_chance(att: Unit, def_u: Unit, ability: Dictionary) -> int:
	var t := String(ability.get("type", "phys"))
	if t == "heal" or t == "buff" or t == "revive":
		return 100
	var side := Iso.relative_side(def_u.pos, def_u.facing, att.pos)
	var side_bonus := 20.0 if side == "back" else (10.0 if side == "side" else 0.0)
	var dh := grid.height_at(att.pos.x, att.pos.y) - grid.height_at(def_u.pos.x, def_u.pos.y)
	var height_bonus: float = clampf(dh * 8.0, -16.0, 16.0)
	var evasion := (def_u.stat("eva") + grid.eva_at(def_u.pos.x, def_u.pos.y)) * 0.6
	var magic_bonus := 5.0 if (t == "mag" or t == "drain") else 0.0
	return roundi(clampf(BASE_ACC + side_bonus + height_bonus + magic_bonus - evasion, 15.0, 99.0))

## Expected damage before the roll — drives the attack preview and the AI.
func estimate_damage(att: Unit, def_u: Unit, ability: Dictionary) -> int:
	var t := String(ability.get("type", "phys"))
	var magical := t == "mag" or t == "drain"
	var power := float(ability.get("power", 1.0))
	var atk := float(att.stat("mag") if magical else att.stat("atk"))
	var mitig := float(def_u.stat("res")) if magical else float(def_u.stat("def") + grid.def_at(def_u.pos.x, def_u.pos.y))
	if ability.has("pierce"):
		mitig *= 1.0 - float(ability["pierce"])
	var dmg := atk * power * (MAG_K if magical else PHYS_K) - mitig * 0.9

	var side := Iso.relative_side(def_u.pos, def_u.facing, att.pos)
	dmg *= 1.5 if side == "back" else (1.25 if side == "side" else 1.0)
	var dh := grid.height_at(att.pos.x, att.pos.y) - grid.height_at(def_u.pos.x, def_u.pos.y)
	if dh > 0:
		dmg *= 1.0 + minf(0.2, dh * 0.1)
	if att.passive == "highGround" and dh > 0:
		dmg *= 1.25
	if att.passive == "pack":
		var pals := 0
		for step in Iso.DIRS:
			var n := unit_at(att.pos.x + step.x, att.pos.y + step.y)
			if n != null and n.team == att.team and n.job == att.job:
				pals += 1
		dmg *= 1.0 + 0.2 * pals
	if def_u.passive == "tough":
		dmg *= 0.85
	return maxi(1, roundi(dmg))

func crit_chance(att: Unit, def_u: Unit) -> int:
	return 8 + (8 if Iso.relative_side(def_u.pos, def_u.facing, att.pos) == "back" else 0)

func damage(u: Unit, amount: float, meta: Dictionary = {}) -> int:
	var amt := maxi(0, roundi(amount))
	u.hp = maxi(0, u.hp - amt)
	var e := meta.duplicate()
	e["type"] = "damage"
	e["unit"] = u
	e["amount"] = amt
	emit(e)
	if not u.alive():
		emit({"type": "ko", "unit": u})
		if meta.has("source"):
			_award_xp(meta["source"], 30 + 5 * u.level)
	return amt

func heal(u: Unit, amount: float, meta: Dictionary = {}) -> int:
	var amt := maxi(0, mini(u.max_hp - u.hp, roundi(amount)))
	u.hp += amt
	var e := meta.duplicate()
	e["type"] = "heal"
	e["unit"] = u
	e["amount"] = amt
	emit(e)
	return amt

func _award_xp(u: Unit, n: int) -> void:
	if u == null:
		return
	if u.gain_xp(n) > 0:
		emit({"type": "levelup", "unit": u})

## Which units an ability actually lands on, given an aim point.
func affected(actor: Unit, ability: Dictionary, target: Vector2i) -> Array[Unit]:
	return affected_on(actor, ability, grid.footprint(actor, ability, target))

func affected_on(actor: Unit, ability: Dictionary, tiles: Array[Vector2i]) -> Array[Unit]:
	var want := String(ability.get("target", "enemy"))
	var out: Array[Unit] = []
	for t in tiles:
		var u: Unit = ko_at(t.x, t.y) if (want == "ko" or ability.get("type", "") == "revive") else unit_at(t.x, t.y)
		if u == null:
			continue
		if ability.get("healOnly", false) and u.team != actor.team:
			continue
		if want == "enemy" and u.team == actor.team:
			continue
		if want == "ally" and u.team != actor.team:
			continue
		out.append(u)
	return out

func valid_target(actor: Unit, ability: Dictionary, target: Vector2i) -> bool:
	if ability.get("selfCentered", false):
		return target == actor.pos
	var in_range := false
	for t in grid.tiles_in_range(actor.pos.x, actor.pos.y, ability):
		if t == target:
			in_range = true
			break
	if not in_range:
		return false
	if ability.get("noAdjacent", false):
		for e in living("E" if actor.team == "P" else "P"):
			if Iso.manhattan(actor.pos, e.pos) <= 1:
				return false
	if ability.get("type", "") == "summon":
		# Hard cap on the horde: without it the Necromancer can stall forever.
		var live := 0
		for u in living(actor.team):
			if u.job == String(ability["summon"]):
				live += 1
		if live >= int(ability.get("cap", 3)):
			return false
		return unit_at(target.x, target.y) == null and grid.walkable(target.x, target.y) and ko_at(target.x, target.y) == null
	if String(ability.get("target", "enemy")) == "empty":
		return true
	return not affected(actor, ability, target).is_empty()

## The one entry point for "do a thing".
func use_ability(actor: Unit, ability: Dictionary, target: Vector2i) -> bool:
	if not valid_target(actor, ability, target):
		return false
	actor.mp = maxi(0, actor.mp - int(ability.get("mp", 0)))
	if ability.has("cd"):
		actor.cooldowns[ability["id"]] = int(ability["cd"])
	if target != actor.pos:
		actor.facing = Iso.facing_toward(actor.pos, target)
	actor.acted = true
	emit({"type": "cast", "unit": actor, "ability": ability, "target": target})

	if ability.get("type", "") == "summon":
		var minion := add_unit(Unit.new("%s %d" % [ability["summon"], units.size()], String(ability["summon"]), actor.team, target, actor.level))
		minion.ct = 40.0
		emit({"type": "summon", "unit": minion, "by": actor})
		return true

	if ability.has("charge"):
		_next_spell_id += 1
		var spell := {"id": _next_spell_id, "casterId": actor.id, "abilityId": String(ability["id"]),
			"tx": target.x, "ty": target.y, "ct": 0.0, "speed": float(ability["charge"])}
		pending.append(spell)
		emit({"type": "charge", "unit": actor, "ability": ability, "target": target, "spell": spell,
			"tiles": grid.footprint(actor, ability, target)})
		return true

	var tiles := grid.footprint(actor, ability, target)
	for t in affected_on(actor, ability, tiles):
		_resolve_on(actor, ability, t)
	emit({"type": "resolve", "unit": actor, "ability": ability, "tiles": tiles})
	return true

func _resolve_on(actor: Unit, ability: Dictionary, target: Unit) -> void:
	var t := String(ability.get("type", "phys"))

	if t == "heal":
		var amount := roundi(actor.stat("mag") * float(ability.get("power", 1.0)) * 1.6)
		var healed := heal(target, amount, {"source": actor})
		_award_xp(actor, roundi(healed * (0.5 if actor.passive == "faith" else 0.2)))
		return
	if t == "revive":
		target.hp = maxi(1, roundi(target.max_hp * float(ability.get("power", 0.35))))
		target.ct = 0.0
		target.status.clear()
		emit({"type": "revive", "unit": target, "by": actor})
		_award_xp(actor, 40)
		return
	if t == "buff":
		if ability.has("status"):
			var st: Dictionary = ability["status"]
			target.add_status(String(st["id"]), int(st["turns"]))
			emit({"type": "status", "unit": target, "status": st["id"], "turns": st["turns"]})
		_award_xp(actor, 12)
		return

	# Offensive path: roll to hit, then damage.
	var acc := hit_chance(actor, target, ability)
	if randi_range(1, 100) > acc:
		emit({"type": "miss", "unit": target, "by": actor, "ability": ability})
		return
	var crit := randi_range(1, 100) <= crit_chance(actor, target)
	var side := Iso.relative_side(target.pos, target.facing, actor.pos)
	var variance := 0.9 + randf() * 0.2
	var dmg := estimate_damage(actor, target, ability) * variance * (CRIT_MULT if crit else 1.0)

	# Shield Bash shoves; with nowhere to shove, it hurts more instead.
	if ability.has("knockback"):
		var dir: Vector2i = Iso.DIRS[Iso.facing_toward(actor.pos, target.pos)]
		var np: Vector2i = target.pos + dir
		var can_shove := grid.walkable(np.x, np.y) and unit_at(np.x, np.y) == null \
			and absi(grid.height_at(np.x, np.y) - grid.height_at(target.pos.x, target.pos.y)) <= 2
		if can_shove:
			var from := target.pos
			target.pos = np
			emit({"type": "knockback", "unit": target, "from": from, "to": np})
			var haz := grid.hazard_at(np.x, np.y)
			if haz > 0:
				damage(target, haz, {"kind": "hazard"})
		else:
			dmg *= 1.25

	var dealt := damage(target, dmg, {"source": actor, "crit": crit, "side": side})
	_award_xp(actor, roundi(dealt * 0.5))

	if t == "drain" and actor.alive():
		heal(actor, dealt * 0.5, {"source": actor, "kind": "drain"})
	if ability.has("status") and target.alive():
		var st2: Dictionary = ability["status"]
		if randi_range(1, 100) <= int(st2["chance"]):
			if target.add_status(String(st2["id"]), int(st2["turns"])):
				emit({"type": "status", "unit": target, "status": st2["id"], "turns": st2["turns"]})

	# Counterattack: melee only, never against a back-strike, once per round.
	if target.alive() and target.passive == "counter" and target.counter_ready \
			and t == "phys" and Iso.manhattan(actor.pos, target.pos) <= 1 and side != "back":
		target.counter_ready = false
		var counter := estimate_damage(target, actor, {"type": "phys", "power": 0.7})
		emit({"type": "counter", "unit": target, "at": actor})
		damage(actor, counter, {"source": target, "kind": "counter"})

func use_item(actor: Unit, item_id: String, target_pos: Vector2i) -> bool:
	if int(items.get(item_id, 0)) <= 0:
		return false
	var item: Dictionary = GameData.ITEMS[item_id]
	var target: Unit = ko_at(target_pos.x, target_pos.y) if String(item["target"]) == "ko" else unit_at(target_pos.x, target_pos.y)
	if target == null:
		return false
	if String(item["target"]) == "ally" and target.team != actor.team:
		return false
	if Iso.manhattan(actor.pos, target_pos) > int(item["range"]):
		return false

	items[item_id] = int(items[item_id]) - 1
	actor.acted = true
	if item.has("revive"):
		target.hp = maxi(1, roundi(target.max_hp * float(item["revive"])))
		target.ct = 0.0
		target.status.clear()
		emit({"type": "revive", "unit": target, "by": actor})
	if item.has("hp"):
		heal(target, float(item["hp"]), {"source": actor, "kind": "item"})
	if item.has("mp"):
		target.mp = mini(target.max_mp, target.mp + int(item["mp"]))
	if item.get("cleanse", false):
		target.clear_bad_status()
	emit({"type": "item", "unit": actor, "target": target, "item": item})
	return true

# ------------------------------------------------------------------ result --
func check_end() -> bool:
	if over != "":
		return true
	var fighters := 0
	for u in living("P"):
		if not u.npc:
			fighters += 1
	if fighters == 0:
		over = "defeat"
		emit({"type": "end", "result": "defeat"})
		return true
	if String(chapter.get("objective", "rout")) == "protect":
		for u in units:
			if u.npc and not u.alive():
				over = "defeat"
				emit({"type": "end", "result": "defeat", "reason": "npc"})
				return true
	var enemies := living("E")
	if String(chapter.get("objective", "rout")) == "boss":
		for e in enemies:
			if e.passive == "boss":
				return false
		over = "victory"
		emit({"type": "end", "result": "victory"})
		return true
	if enemies.is_empty():
		over = "victory"
		emit({"type": "end", "result": "victory"})
		return true
	return false
