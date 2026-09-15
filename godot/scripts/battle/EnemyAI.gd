# ============================================================================
# Enemy AI.
#
# Scores every (where I could stand) x (what I could do) x (where I aim it)
# combination and takes the best one. That is enough to make enemies flank,
# climb for height, avoid lava, refuse to clump for your Fire, and back off
# when they are nearly dead.
# ============================================================================
class_name EnemyAI
extends RefCounted

const W := {
	"damage": 1.0,
	"kill": 45.0,
	"overkill": -0.35,      # stop valuing damage past lethal
	"ally_hit": -2.2,       # friendly fire is discouraged, not forbidden
	"heal": 1.1,
	"buff": 16.0,
	"revive": 110.0,
	"summon": 36.0,
	"status": 14.0,
	"height": 2.5,
	"cover": 0.35,
	"hazard": -45.0,
	"exposure": -1.5,
	"approach": -1.6,
	"backstab": 8.0,
	"self_preserve": 30.0,
	"npc_kill": 2.2,        # multiplier on value against a protect-objective civilian
	"charged": 0.8,         # a spell that lands later may miss a target that walks away
	"guard": 3.0,           # per tile an escort strays from the civilian it protects
}

## Damage a unit would eat from every enemy spell already charging over a tile.
static func incoming(battle: Battle, unit: Unit, tile: Vector2i) -> float:
	var dmg := 0.0
	for p in battle.pending:
		var cid := int(p["casterId"])
		var caster: Unit = battle.units[cid] if cid < battle.units.size() else null
		if caster == null or not caster.alive() or caster.team == unit.team:
			continue
		var ability := GameData.ability(String(p["abilityId"]))
		if battle.grid.footprint(caster, ability, Vector2i(int(p["tx"]), int(p["ty"]))).has(tile):
			dmg += battle.estimate_damage(caster, unit, ability)
	return dmg

## Long battles get progressively pushier so two cautious sides cannot stare at
## each other across a river forever.
static func aggression(battle: Battle) -> float:
	return minf(5.0, 1.0 + battle.turn / 35.0)

## How many enemies could reach and strike this tile next turn.
static func exposure(battle: Battle, tile: Vector2i, self_unit: Unit) -> int:
	var n := 0
	for p in battle.living("E" if self_unit.team == "P" else "P"):
		if Iso.manhattan(p.pos, tile) <= p.stat("move") + maxi(p.weapon_range, 1):
			n += 1
	return n

## Steps to the nearest foe, walking the map rather than flying over it.
static func approach_cost(battle: Battle, field: PackedInt32Array, tile: Vector2i, nearest: Unit) -> float:
	var d := field[tile.y * battle.grid.cols + tile.x] if field.size() > 0 else -1
	if d >= 0:
		return float(d)
	# Unreachable on foot: fall back to straight-line, heavily penalised.
	return (Iso.manhattan(tile, nearest.pos) * 3.0 + 20.0) if nearest != null else 0.0

static func tile_score(battle: Battle, unit: Unit, tile: Vector2i, nearest: Unit, field: PackedInt32Array) -> float:
	var g := battle.grid
	var aggro := aggression(battle)
	var s := 0.0
	s += g.height_at(tile.x, tile.y) * W["height"]
	s += (g.eva_at(tile.x, tile.y) + g.def_at(tile.x, tile.y) * 4) * W["cover"]
	if g.hazard_at(tile.x, tile.y) > 0:
		s += W["hazard"]
	s -= incoming(battle, unit, tile) * 1.1          # step out of charging spells
	var reach := approach_cost(battle, field, tile, nearest)
	if unit.npc:
		# Civilians only want to be far away and out of reach.
		return s - exposure(battle, tile, unit) * 6.0 + minf(reach, 12.0) * 1.5
	s += exposure(battle, tile, unit) * (W["exposure"] / aggro)
	s += reach * W["approach"] * aggro
	# Escorts stay close enough to body-block for the civilian.
	for v in battle.units:
		if v.npc and v.alive() and v.team == unit.team:
			s -= maxf(0.0, Iso.manhattan(tile, v.pos) - 1) * W["guard"]
			break
	# Hurt units want distance; healthy ones want to be in your face.
	if float(unit.hp) / unit.max_hp < 0.3:
		s -= reach * W["approach"] * 1.8 / aggro
	return s

## Value of firing `ability` from `from` at `target`.
static func action_score(battle: Battle, unit: Unit, from: Vector2i, ability: Dictionary, target: Vector2i) -> float:
	var saved_pos := unit.pos
	var saved_facing := unit.facing
	unit.pos = from
	unit.facing = Iso.facing_toward(from, target)
	var s := 0.0
	var ok := true

	if not battle.valid_target(unit, ability, target):
		ok = false
	elif ability.get("type", "") == "summon":
		s = W["summon"] + maxf(0.0, 5.0 - battle.living(unit.team).size()) * 12.0
	else:
		var hits := battle.affected(unit, ability, target)
		if hits.is_empty() and ability.get("type", "") != "buff":
			ok = false
		else:
			var t := String(ability.get("type", "phys"))
			for tgt in hits:
				var friendly := tgt.team == unit.team
				if t == "heal":
					if not friendly:
						continue
					var missing := tgt.max_hp - tgt.hp
					if missing <= 0:
						continue
					var amount := mini(missing, roundi(unit.stat("mag") * float(ability.get("power", 1.0)) * 1.6))
					s += amount * W["heal"] * (2.0 if float(tgt.hp) / tgt.max_hp < 0.35 else 1.0)
				elif t == "buff":
					if not friendly:
						continue
					if ability.has("status") and tgt.has_status(String(ability["status"]["id"])):
						continue
					s += W["buff"]
				elif t == "revive":
					s += W["revive"]
				else:
					var acc := battle.hit_chance(unit, tgt, ability) / 100.0
					var dmg := battle.estimate_damage(unit, tgt, ability)
					var v := mini(dmg, tgt.hp) * W["damage"] * acc
					if dmg > tgt.hp:
						v += (dmg - tgt.hp) * W["overkill"]
					if dmg >= tgt.hp:
						v += W["kill"] * acc
					if ability.has("status") and not tgt.has_status(String(ability["status"]["id"])):
						v += W["status"] * (float(ability["status"]["chance"]) / 100.0)
					if Iso.relative_side(tgt.pos, tgt.facing, unit.pos) == "back":
						v += W["backstab"]
					if tgt.npc and not friendly:
						v *= W["npc_kill"]                # the objective is standing right there
					if ability.has("charge"):
						v *= W["charged"]
					s += v * W["ally_hit"] if friendly else v
			# Spend MP on the cheapest thing that does the job.
			s -= int(ability.get("mp", 0)) * 0.35

	unit.pos = saved_pos
	unit.facing = saved_facing
	return s if ok else -INF

## Returns {"move": Vector2i or null, "ability": Dictionary or {}, "target": Vector2i}.
static func plan_turn(battle: Battle, unit: Unit) -> Dictionary:
	var foes := battle.living("E" if unit.team == "P" else "P")
	if foes.is_empty():
		return {"move": null, "ability": {}}
	var nearest: Unit = foes[0]
	for f in foes:
		if Iso.manhattan(unit.pos, f.pos) < Iso.manhattan(unit.pos, nearest.pos):
			nearest = f

	var foe_tiles: Array = []
	for f in foes:
		foe_tiles.append(f.pos)
	var field := battle.grid.distance_field(foe_tiles, unit.stat("jump"))
	var res := battle.reachable_for(unit)
	var stands: Array[Vector2i] = [unit.pos]
	stands.append_array(res["tiles"] as Array[Vector2i])
	var abilities := unit.usable_abilities()
	var desperate := float(unit.hp) / unit.max_hp < 0.28 and battle.turn < 80

	var best := {"score": -INF, "move": null, "ability": {}, "target": unit.pos}
	for i in stands.size():
		var tile: Vector2i = stands[i]
		var is_start := i == 0
		var base := tile_score(battle, unit, tile, nearest, field)
		if desperate and exposure(battle, tile, unit) == 0:
			base += W["self_preserve"]
		# Option A: stand here and do nothing (pure repositioning).
		if base > float(best["score"]):
			best = {"score": base, "move": null if is_start else tile, "ability": {}, "target": tile}

		for ability in abilities:
			var aims: Array[Vector2i] = ([tile] as Array[Vector2i]) if ability.get("selfCentered", false) \
				else battle.grid.tiles_in_range(tile.x, tile.y, ability)
			for aim in aims:
				var v := action_score(battle, unit, tile, ability, aim)
				if v == -INF:
					continue
				if base + v > float(best["score"]):
					best = {"score": base + v, "move": null if is_start else tile, "ability": ability, "target": aim}
	return best
