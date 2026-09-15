# ============================================================================
# The tile board: terrain code plus height for every cell, and the height-aware
# pathfinding the rules and the AI both run on.
# ============================================================================
class_name BattleGrid
extends RefCounted

var cols: int
var rows: int
var weather: String = "clear"
var map_name: String = ""
var codes: Array[String] = []          # row-major, one char per tile
var heights: PackedInt32Array = PackedInt32Array()

func _init(def: Dictionary) -> void:
	map_name = def.get("name", "")
	weather = def.get("weather", "clear")
	var t: Array = def["t"]
	var h: Array = def["h"]
	rows = t.size()
	cols = String(t[0]).length()
	for y in rows:
		var trow := String(t[y])
		var hrow := String(h[y])
		for x in cols:
			codes.append(trow[x])
			heights.append(int(hrow[x]))

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < cols and y < rows

func code_at(x: int, y: int) -> String:
	return codes[y * cols + x] if in_bounds(x, y) else "."

func terrain_at(x: int, y: int) -> Dictionary:
	return GameData.terrain(code_at(x, y))

func height_at(x: int, y: int) -> int:
	return heights[y * cols + x] if in_bounds(x, y) else -1

func is_void(x: int, y: int) -> bool:
	return not in_bounds(x, y) or terrain_at(x, y).get("void", false)

func walkable(x: int, y: int) -> bool:
	return in_bounds(x, y) and terrain_at(x, y).get("walk", false)

func eva_at(x: int, y: int) -> int:
	return terrain_at(x, y).get("eva", 0)

func def_at(x: int, y: int) -> int:
	return terrain_at(x, y).get("def", 0)

func hazard_at(x: int, y: int) -> int:
	return terrain_at(x, y).get("hazard", 0)

# --------------------------------------------------------------------------
## Dijkstra over move points. A height difference greater than the unit's jump
## is a wall, which is what makes terraces and cliffs matter.
## `blocker` is a Callable(x, y) -> Unit or null.
func reachable(unit, blocker: Callable) -> Dictionary:
	var move_pts: int = unit.stat("move")
	var jump: int = unit.stat("jump")
	var start: int = unit.pos.y * cols + unit.pos.x
	var cost := {start: 0}
	var came := {}
	var tiles: Array[Vector2i] = []
	var frontier: Array = [[unit.pos, 0]]
	while not frontier.is_empty():
		var next: Array = []
		for entry in frontier:
			var cur: Vector2i = entry[0]
			var d: int = entry[1]
			if d >= move_pts:
				continue
			for step in Iso.DIRS:
				var np: Vector2i = cur + step
				if not walkable(np.x, np.y):
					continue
				if absi(height_at(np.x, np.y) - height_at(cur.x, cur.y)) > jump:
					continue
				var occ = blocker.call(np.x, np.y)
				# You may walk through allies but never stop on them.
				if occ != null and occ.team != unit.team:
					continue
				var nd := d + 1
				var k := np.y * cols + np.x
				if cost.has(k) and int(cost[k]) <= nd:
					continue
				cost[k] = nd
				came[k] = cur.y * cols + cur.x
				next.append([np, nd])
				if occ == null:
					tiles.append(np)
		frontier = next
	return {"tiles": tiles, "cost": cost, "came": came}

## Rebuilds the walk produced by reachable(). Empty array when unreachable.
func path_to(res: Dictionary, unit, target: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var came: Dictionary = res["came"]
	var k := target.y * cols + target.x
	var start: int = unit.pos.y * cols + unit.pos.x
	var guard := 0
	while k != start and guard < 512:
		guard += 1
		out.append(Vector2i(k % cols, k / cols))
		if not came.has(k):
			return [] as Array[Vector2i]
		k = int(came[k])
	out.reverse()
	return out

## Extra travel cost charged for stepping onto a hazard tile.
const HAZARD_COST := 5

## Multi-source travel-cost field: for every tile, the cheapest walking cost to
## the nearest source, respecting walls and a jump limit. Hazard tiles cost
## extra, so the AI routes around a lava channel instead of treating it as a
## shortcut it will never actually take - which used to deadlock two melee
## squads either side of the ziggurat's lava. Dial's algorithm, since the edge
## weights are tiny integers.
func distance_field(sources: Array, jump: int) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(cols * rows)
	dist.fill(-1)
	var buckets: Array = []
	var push := func(d: int, p: Vector2i) -> void:
		while buckets.size() <= d:
			buckets.append([])
		buckets[d].append(p)
	for s in sources:
		var p: Vector2i = s
		if not in_bounds(p.x, p.y):
			continue
		var k := p.y * cols + p.x
		if dist[k] != -1:
			continue
		dist[k] = 0
		push.call(0, p)
	var d := 0
	while d < buckets.size():
		for cur in buckets[d]:
			var c: Vector2i = cur
			if dist[c.y * cols + c.x] != d:
				continue                                # superseded entry
			for step in Iso.DIRS:
				var np: Vector2i = c + step
				if not walkable(np.x, np.y):
					continue
				if absi(height_at(np.x, np.y) - height_at(c.x, c.y)) > jump:
					continue
				var nd: int = d + 1 + (HAZARD_COST if hazard_at(np.x, np.y) > 0 else 0)
				var k2 := np.y * cols + np.x
				if dist[k2] != -1 and dist[k2] <= nd:
					continue
				dist[k2] = nd
				push.call(nd, np)
		d += 1
	return dist

## Tiles an ability can be aimed at from a given stance.
func tiles_in_range(ox: int, oy: int, ability: Dictionary) -> Array[Vector2i]:
	var r: int = int(ability.get("range", 1))
	var min_r: int = int(ability.get("minRange", 0))
	var vert: int = int(ability.get("vert", 4))
	var oh := height_at(ox, oy)
	var out: Array[Vector2i] = []
	for dy in range(-r, r + 1):
		for dx in range(-r + absi(dy), r - absi(dy) + 1):
			var d := absi(dx) + absi(dy)
			if d < min_r or d > r:
				continue
			var x := ox + dx
			var y := oy + dy
			if is_void(x, y):
				continue
			if absi(height_at(x, y) - oh) > vert:
				continue
			if ability.get("line", false) and dx != 0 and dy != 0:
				continue
			out.append(Vector2i(x, y))
	return out

## A cone `len` tiles deep opening from the caster toward `aim`. Row k of the
## cone is 2*floor(k/2)+1 wide, so breath reaches three tiles straight ahead
## and fans out to the sides.
func cone_tiles(cx: int, cy: int, ax: int, ay: int, len: int) -> Array[Vector2i]:
	var dir: Vector2i = Iso.DIRS[Iso.facing_from_delta(ax - cx, ay - cy)]
	var side := Vector2i(1, 0) if dir.x == 0 else Vector2i(0, 1)
	var out: Array[Vector2i] = []
	for k in range(1, len + 1):
		var half := k / 2
		for w in range(-half, half + 1):
			var p := Vector2i(cx, cy) + dir * k + side * w
			if not is_void(p.x, p.y):
				out.append(p)
	return out

## Every tile an ability lands on, given who is casting and where it is aimed.
func footprint(actor, ability: Dictionary, target: Vector2i) -> Array[Vector2i]:
	if ability.get("shape", "") == "cone":
		return cone_tiles(actor.pos.x, actor.pos.y, target.x, target.y, int(ability.get("coneLen", 3)))
	if int(ability.get("aoe", 0)) > 0:
		return aoe_tiles(target.x, target.y, ability)
	return [target] as Array[Vector2i]

## Where the player may stand at the start of a chapter: every walkable tile
## within two steps of a default deploy slot that no enemy spawns on.
func deploy_zone(chapter: Dictionary) -> Array[Vector2i]:
	var taken := {}
	for e in chapter["enemies"]:
		taken[Vector2i(int(e[2]), int(e[3]))] = true
	if chapter.has("npc"):
		taken[Vector2i(int(chapter["npc"][2]), int(chapter["npc"][3]))] = true
	var seen := {}
	var zone: Array[Vector2i] = []
	for slot in chapter["deploy"]:
		var origin := Vector2i(int(slot[0]), int(slot[1]))
		for dy in range(-2, 3):
			for dx in range(-2 + absi(dy), 2 - absi(dy) + 1):
				var p := origin + Vector2i(dx, dy)
				if seen.has(p) or taken.has(p) or not walkable(p.x, p.y):
					continue
				seen[p] = true
				zone.append(p)
	return zone

## Splash footprint centred on a tile.
func aoe_tiles(cx: int, cy: int, ability: Dictionary) -> Array[Vector2i]:
	var r: int = int(ability.get("aoe", 0))
	var out: Array[Vector2i] = []
	for dy in range(-r, r + 1):
		for dx in range(-r + absi(dy), r - absi(dy) + 1):
			var x := cx + dx
			var y := cy + dy
			if not is_void(x, y):
				out.append(Vector2i(x, y))
	return out
