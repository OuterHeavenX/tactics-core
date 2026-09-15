# ============================================================================
# A combatant. Stats are derived from the job table plus level growth; every
# rule reads them through stat() so status multipliers can never be forgotten
# at a call site.
# ============================================================================
class_name Unit
extends RefCounted

var id: int = -1
var unit_name: String = ""
var job: String = ""
var job_def: Dictionary = {}
var team: String = "P"                 # "P" player, "E" enemy
var pos: Vector2i = Vector2i.ZERO
var facing: int = 0
var level: int = 1
var xp: int = 0

var max_hp: int
var hp: int
var max_mp: int
var mp: int
var base_atk: int
var base_def: int
var base_mag: int
var base_res: int
var base_spd: int
var base_eva: int
var move_pts: int
var jump_pts: int
var weapon_range: int

var ct: float = 0.0
var moved := false
var acted := false
var counter_ready := true
var status: Dictionary = {}            # id -> turns remaining
var cooldowns: Dictionary = {}
var abilities: Array = []
var passive: String = "none"
var npc := false                       # protect-objective civilian
var jp: int = 0
var learned: Array = []                # ability ids bought with JP

var start_pos: Vector2i = Vector2i.ZERO
var start_facing: int = 0

func _init(p_name: String, p_job: String, p_team: String, p_pos: Vector2i, p_level: int = 1) -> void:
	unit_name = p_name
	job = p_job
	job_def = GameData.job(p_job)
	team = p_team
	pos = p_pos
	level = maxi(1, p_level)
	facing = 0 if p_team == "P" else 1
	# Enemies know their whole kit; the party starts with a subset and learns.
	if p_team == "P" and job_def.has("starting"):
		abilities = (job_def["starting"] as Array).duplicate()
	else:
		abilities = (job_def["abilities"] as Array).duplicate()
	passive = job_def.get("passive", "none")
	apply_growth()
	hp = max_hp
	mp = max_mp
	ct = randi_range(0, 45)

func apply_growth() -> void:
	var g: Dictionary = job_def["growth"]
	var n := level - 1
	max_hp = roundi(float(job_def["hp"]) + float(g["hp"]) * n)
	max_mp = roundi(float(job_def["mp"]) + float(g["mp"]) * n)
	base_atk = roundi(float(job_def["atk"]) + float(g["atk"]) * n)
	base_def = roundi(float(job_def["def"]) + float(g["def"]) * n)
	base_mag = roundi(float(job_def["mag"]) + float(g["mag"]) * n)
	base_res = roundi(float(job_def["res"]) + float(g["res"]) * n)
	base_spd = roundi(float(job_def["spd"]) + float(g["spd"]) * n)
	base_eva = int(job_def["eva"])
	move_pts = int(job_def["move"])
	# Shades float, so height never stops them.
	jump_pts = 9 if passive == "phase" else int(job_def["jump"])
	weapon_range = int(job_def["range"])

func alive() -> bool:
	return hp > 0

func xp_to_next() -> int:
	return 80 + 40 * level

func color() -> Color:
	return Color(String(job_def["color"]))

func icon() -> String:
	return String(job_def["icon"])

## Effective stat after every active status multiplier.
func stat(key: String) -> int:
	var mult := 1.0
	for sid in status.keys():
		var sd: Dictionary = GameData.STATUS.get(sid, {})
		if sd.has(key):
			mult *= float(sd[key])
	match key:
		"atk": return maxi(1, roundi(base_atk * mult))
		"def": return maxi(0, roundi(base_def * mult))
		"mag": return maxi(1, roundi(base_mag * mult))
		"res": return maxi(0, roundi(base_res * mult))
		"spd": return maxi(1, roundi(base_spd * mult))
		"eva": return maxi(0, roundi(base_eva * mult))
		"move": return maxi(1, roundi(move_pts * mult))
		"jump": return jump_pts
	return 0

func has_status(sid: String) -> bool:
	return int(status.get(sid, 0)) > 0

## Bosses shrug off Stun; everything else lands normally.
func add_status(sid: String, turns: int) -> bool:
	if passive == "boss" and sid == "stun":
		return false
	status[sid] = maxi(int(status.get(sid, 0)), turns)
	return true

func clear_bad_status() -> int:
	var n := 0
	for sid in status.keys().duplicate():
		if GameData.STATUS[sid].get("bad", false):
			status.erase(sid)
			n += 1
	return n

## Abilities this unit can actually pay for right now.
func usable_abilities() -> Array:
	var out: Array = []
	for aid in abilities:
		var a: Dictionary = GameData.ability(aid)
		if mp >= int(a.get("mp", 0)) and int(cooldowns.get(aid, 0)) <= 0:
			out.append(a)
	return out

## Abilities in the job list that are not yet known and cost JP.
func learnable() -> Array:
	var out: Array = []
	for id in job_def["abilities"]:
		if not abilities.has(id) and GameData.ABILITIES.has(id) and GameData.ABILITIES[id].has("jp"):
			out.append(id)
	return out

func learn(id: String) -> bool:
	if not GameData.ABILITIES.has(id):
		return false
	var a: Dictionary = GameData.ABILITIES[id]
	if not a.has("jp") or abilities.has(id) or not (job_def["abilities"] as Array).has(id) or jp < int(a["jp"]):
		return false
	jp -= int(a["jp"])
	abilities.append(id)
	learned.append(id)
	return true

## Returns the number of levels gained, so the caller can announce them.
func gain_xp(n: int) -> int:
	if team != "P" or n <= 0 or npc:
		return 0
	xp += n
	jp += ceili(n * 0.75)               # JP tracks XP, spent on the learn screen
	var gained := 0
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		gained += 1
		var old_hp := max_hp
		var old_mp := max_mp
		apply_growth()
		hp += max_hp - old_hp
		mp += max_mp - old_mp
	return gained
