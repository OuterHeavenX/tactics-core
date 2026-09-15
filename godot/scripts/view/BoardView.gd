# ============================================================================
# The isometric board renderer.
#
# Every tile is a 2:1 diamond top plus two shaded side faces, so terrain height
# reads as real geometry rather than a colour change. Terrain and units share
# one back-to-front diagonal sweep, which is what keeps a unit correctly hidden
# behind a cliff instead of floating over it.
#
# Everything is drawn in "world" space (the raw isometric projection). The
# parent node carries the camera transform, so zoom and pan cost nothing here.
# ============================================================================
class_name BoardView
extends Node2D

signal walk_finished(unit: Unit)

var battle: Battle
var rot: int = 0
var rot_from: int = 0
var rot_t: float = 1.0                  # 1.0 = settled

var overlay_move: Dictionary = {}       # Vector2i -> true
var overlay_act: Dictionary = {}
var overlay_aoe: Dictionary = {}
var overlay_path: Array[Vector2i] = []
var cursor = null                       # Vector2i or null

var _time := 0.0
var _tile_order: Array[Vector2i] = []
var _order_rot := -1
var _anims: Dictionary = {}             # unit id -> walk state
var _fx: Dictionary = {}                # unit id -> {flash, bob}
var _floaters: Array = []
var _particles: Array = []

const JOB_LETTER := {
	"Knight": "K", "HolyKnight": "H", "Archer": "A", "Mage": "M", "Priest": "P",
	"Goblin": "g", "Orc": "O", "Bandit": "b", "Shade": "s", "Skeleton": "k",
	"Necromancer": "N",
}

func setup(p_battle: Battle) -> void:
	battle = p_battle
	rot = 0
	rot_from = 0
	rot_t = 1.0
	_order_rot = -1
	_anims.clear()
	_fx.clear()
	_floaters.clear()
	_particles.clear()
	clear_overlays()
	queue_redraw()

func clear_overlays() -> void:
	overlay_move.clear()
	overlay_act.clear()
	overlay_aoe.clear()
	overlay_path.clear()

func rotate_by(d: int) -> void:
	rot_from = rot
	rot = (rot + d + 4) & 3
	rot_t = 0.0
	_order_rot = -1

func is_busy() -> bool:
	return not _anims.is_empty()

# ------------------------------------------------------------- projection --
## Board coords -> world position, blended while the camera is turning.
func project(x: float, y: float, h: float) -> Vector2:
	var to := Iso.project(x, y, h, battle.grid.cols, battle.grid.rows, rot)
	if rot_t >= 1.0:
		return Vector2(to.x, to.y)
	var from := Iso.project(x, y, h, battle.grid.cols, battle.grid.rows, rot_from)
	var t := ease(rot_t, 0.4)
	return Vector2(lerpf(from.x, to.x, t), lerpf(from.y, to.y, t))

func depth_of(x: float, y: float) -> float:
	var to := Iso.project(x, y, 0.0, battle.grid.cols, battle.grid.rows, rot)
	if rot_t >= 1.0:
		return to.z
	var from := Iso.project(x, y, 0.0, battle.grid.cols, battle.grid.rows, rot_from)
	return lerpf(from.z, to.z, ease(rot_t, 0.4))

## Back-to-front diagonal sweep in the current view space.
func tile_order() -> Array[Vector2i]:
	if _order_rot == rot:
		return _tile_order
	var g := battle.grid
	var vd := Iso.view_dims(g.cols, g.rows, rot)
	var out: Array[Vector2i] = []
	for s in range(0, vd.x + vd.y - 1):
		for rx in range(maxi(0, s - vd.y + 1), mini(vd.x - 1, s) + 1):
			var b := Iso.unrotate(rx, s - rx, g.cols, g.rows, rot)
			if not g.is_void(b.x, b.y):
				out.append(b)
	_tile_order = out
	_order_rot = rot
	return out

## How far each front face drops before it meets its neighbour.
func face_drop(tile: Vector2i) -> Vector2:
	var g := battle.grid
	var r := Iso.rotate_xy(tile.x, tile.y, g.cols, g.rows, rot)
	var vd := Iso.view_dims(g.cols, g.rows, rot)
	var h := g.height_at(tile.x, tile.y)
	var nl := -1
	var nr := -1
	if r.y + 1 < vd.y:
		var bl := Iso.unrotate(r.x, r.y + 1, g.cols, g.rows, rot)
		nl = -1 if g.is_void(bl.x, bl.y) else g.height_at(bl.x, bl.y)
	if r.x + 1 < vd.x:
		var br := Iso.unrotate(r.x + 1, r.y, g.cols, g.rows, rot)
		nr = -1 if g.is_void(br.x, br.y) else g.height_at(br.x, br.y)
	return Vector2(maxf(0.6, h - nl), maxf(0.6, h - nr))

## World position -> board tile, testing front-to-back so the nearest solid
## surface wins. Returns Vector2i(-1, -1) when the click missed the board.
func pick(world: Vector2) -> Vector2i:
	if battle == null:
		return Vector2i(-1, -1)
	var order := tile_order()
	for i in range(order.size() - 1, -1, -1):
		var tile: Vector2i = order[i]
		var p := project(tile.x, tile.y, battle.grid.height_at(tile.x, tile.y))
		var d := world - p
		if absf(d.x) / (Iso.TW * 0.5) + absf(d.y) / (Iso.TH * 0.5) <= 1.0:
			return tile
		var drop := face_drop(tile)
		if d.y > 0.0 and d.y < Iso.TH * 0.5 + maxf(drop.x, drop.y) * Iso.HS:
			if d.x <= 0.0 and d.x >= -Iso.TW * 0.5 and d.y <= Iso.TH * 0.5 + drop.x * Iso.HS + d.x * (Iso.TH / Iso.TW):
				return tile
			if d.x >= 0.0 and d.x <= Iso.TW * 0.5 and d.y <= Iso.TH * 0.5 + drop.y * Iso.HS - d.x * (Iso.TH / Iso.TW):
				return tile
	return Vector2i(-1, -1)

# ----------------------------------------------------------------- effects --
func float_text(cell: Vector2i, text: String, color: Color, size: int = 18) -> void:
	_floaters.append({
		"x": float(cell.x), "y": float(cell.y),
		"h": float(battle.grid.height_at(cell.x, cell.y)) + 1.1,
		"text": text, "color": color, "life": 1.0, "size": size,
		"dx": randf_range(-6.0, 6.0),
	})

func burst(cell: Vector2i, color: Color, count: int = 12, power: float = 1.0) -> void:
	var h := float(battle.grid.height_at(cell.x, cell.y)) + 0.4
	for i in count:
		var a := randf() * TAU
		var s := (0.4 + randf()) * power
		_particles.append({
			"x": float(cell.x), "y": float(cell.y), "h": h,
			"vx": cos(a) * s * 0.06, "vy": sin(a) * s * 0.06,
			"vz": 1.4 + randf() * 2.2, "life": 1.0, "color": color,
		})

func flash_unit(u: Unit, color: Color = Color.WHITE) -> void:
	var f := _unit_fx(u)
	f["flash"] = 1.0
	f["flash_color"] = color

func _unit_fx(u: Unit) -> Dictionary:
	if not _fx.has(u.id):
		_fx[u.id] = {"flash": 0.0, "flash_color": Color.WHITE, "bob": randf() * TAU}
	return _fx[u.id]

## Slides a unit along a walked path, hopping over height changes.
func walk(u: Unit, from: Vector2i, path: Array, on_done: Callable = Callable()) -> void:
	if path.is_empty():
		if on_done.is_valid():
			on_done.call()
		return
	_anims[u.id] = {"unit": u, "from": from, "path": path, "i": 0, "t": 0.0, "done": on_done}

func snap(u: Unit) -> void:
	_anims.erase(u.id)

# -------------------------------------------------------------------- loop --
func _process(delta: float) -> void:
	if battle == null:
		return
	_time += delta
	if rot_t < 1.0:
		rot_t = minf(1.0, rot_t + delta * 3.2)

	for key in _fx:
		var f: Dictionary = _fx[key]
		f["bob"] = float(f["bob"]) + delta * 2.4
		f["flash"] = maxf(0.0, float(f["flash"]) - delta * 3.4)

	for key in _anims.keys().duplicate():
		var a: Dictionary = _anims[key]
		a["t"] = float(a["t"]) + delta * 5.6
		if float(a["t"]) >= 1.0:
			a["i"] = int(a["i"]) + 1
			a["t"] = 0.0
			if int(a["i"]) >= (a["path"] as Array).size():
				var cb: Callable = a["done"]
				var u: Unit = a["unit"]
				_anims.erase(key)
				emit_signal("walk_finished", u)
				if cb.is_valid():
					cb.call()

	for i in range(_particles.size() - 1, -1, -1):
		var q: Dictionary = _particles[i]
		q["x"] = float(q["x"]) + float(q["vx"])
		q["y"] = float(q["y"]) + float(q["vy"])
		q["h"] = float(q["h"]) + float(q["vz"]) * delta * 2.4
		q["vz"] = float(q["vz"]) - delta * 9.0
		q["life"] = float(q["life"]) - delta * 1.5
		if float(q["life"]) <= 0.0:
			_particles.remove_at(i)

	for i in range(_floaters.size() - 1, -1, -1):
		var fl: Dictionary = _floaters[i]
		fl["life"] = float(fl["life"]) - delta * 1.05
		fl["h"] = float(fl["h"]) + delta * 1.6
		if float(fl["life"]) <= 0.0:
			_floaters.remove_at(i)

	queue_redraw()

# -------------------------------------------------------------------- draw --
func _draw() -> void:
	if battle == null:
		return
	var order := tile_order()

	# Bucket units by the diagonal they stand on so they interleave correctly
	# with the terrain instead of all drawing on top of it.
	var buckets := {}
	for u in battle.units:
		var gp := _unit_grid_pos(u)
		var d := depth_of(gp.x, gp.y)
		var key := int(floor(d))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(u)

	var g := battle.grid
	var vd := Iso.view_dims(g.cols, g.rows, rot)
	var i := 0
	for s in range(0, vd.x + vd.y - 1):
		while i < order.size():
			var tile: Vector2i = order[i]
			var r := Iso.rotate_xy(tile.x, tile.y, g.cols, g.rows, rot)
			if r.x + r.y != s:
				break
			_draw_tile(tile)
			i += 1
		if buckets.has(s):
			for u in buckets[s]:
				_draw_unit(u)

	for q in _particles:
		var p := project(float(q["x"]), float(q["y"]), float(q["h"]))
		var c: Color = q["color"]
		c.a = clampf(float(q["life"]), 0.0, 1.0)
		var sz := 3.0 * float(q["life"])
		draw_rect(Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), c)

	var font := ThemeDB.fallback_font
	for fl in _floaters:
		var p := project(float(fl["x"]), float(fl["y"]), float(fl["h"]))
		var c: Color = fl["color"]
		var alpha := clampf(float(fl["life"]) * 1.6, 0.0, 1.0)
		var sz := int(fl["size"])
		var txt := String(fl["text"])
		var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		var at := p + Vector2(float(fl["dx"]) - w * 0.5, 0.0)
		draw_string_outline(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, alpha))
		c.a = alpha
		draw_string(font, at, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)

func _unit_grid_pos(u: Unit) -> Vector2:
	if not _anims.has(u.id):
		return Vector2(u.pos)
	var a: Dictionary = _anims[u.id]
	var path: Array = a["path"]
	var idx: int = a["i"]
	var step: Vector2i = path[idx]
	var prev: Vector2i = a["from"] if idx == 0 else path[idx - 1]
	var t: float = clampf(a["t"], 0.0, 1.0)
	return Vector2(prev).lerp(Vector2(step), t)

func _unit_height(u: Unit) -> float:
	var g := battle.grid
	if not _anims.has(u.id):
		return float(g.height_at(u.pos.x, u.pos.y))
	var a: Dictionary = _anims[u.id]
	var path: Array = a["path"]
	var idx: int = a["i"]
	var step: Vector2i = path[idx]
	var prev: Vector2i = a["from"] if idx == 0 else path[idx - 1]
	var t: float = clampf(a["t"], 0.0, 1.0)
	var h0 := float(g.height_at(prev.x, prev.y))
	var dh := float(g.height_at(step.x, step.y)) - h0
	# A little hop sells the step up or down a terrace.
	return h0 + dh * t + sin(t * PI) * (0.35 + absf(dh) * 0.28)

func _draw_tile(tile: Vector2i) -> void:
	var g := battle.grid
	var t := g.terrain_at(tile.x, tile.y)
	var h := g.height_at(tile.x, tile.y)
	var p := project(tile.x, tile.y, h)
	var drop := face_drop(tile)
	var hw := Iso.TW * 0.5
	var hh := Iso.TH * 0.5
	var base := Color(String(t["top"]))

	# Side faces first; left darker than right, as if lit from the upper right.
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(-hw, 0), p + Vector2(0, hh),
		p + Vector2(0, hh + drop.x * Iso.HS), p + Vector2(-hw, drop.x * Iso.HS)]),
		base.darkened(0.45))
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(hw, 0), p + Vector2(0, hh),
		p + Vector2(0, hh + drop.y * Iso.HS), p + Vector2(hw, drop.y * Iso.HS)]),
		base.darkened(0.25))

	var top_color := base
	if t.get("liquid", false):
		top_color = base.lightened(0.06 + 0.06 * sin(_time * 2.0 + (tile.x + tile.y) * 0.8))
	var diamond := PackedVector2Array([
		p + Vector2(0, -hh), p + Vector2(hw, 0), p + Vector2(0, hh), p + Vector2(-hw, 0)])
	draw_colored_polygon(diamond, top_color)
	draw_polyline(diamond + PackedVector2Array([p + Vector2(0, -hh)]), Color(0, 0, 0, 0.25), 1.0)

	if t.has("glow"):
		var glow := Color(String(t["glow"]))
		glow.a = 0.25 + 0.2 * sin(_time * 3.0 + tile.x)
		draw_colored_polygon(diamond, glow)

	_draw_overlay(tile, p, diamond)
	if t.has("decor"):
		_draw_decor(tile, p, String(t["decor"]))

func _draw_overlay(tile: Vector2i, p: Vector2, diamond: PackedVector2Array) -> void:
	var fill := Color(0, 0, 0, 0)
	if overlay_aoe.has(tile):
		fill = Color(1.0, 0.59, 0.24, 0.5 + 0.2 * sin(_time * 7.0))
	elif overlay_act.has(tile):
		fill = Color(0.91, 0.28, 0.28, 0.46)
	elif overlay_move.has(tile):
		fill = Color(0.31, 0.59, 1.0, 0.46)
	if fill.a > 0.0:
		draw_colored_polygon(diamond, fill)
	if overlay_path.has(tile):
		draw_circle(p, 5.0, Color(1, 1, 1, 0.55))
	if cursor != null and cursor == tile:
		draw_polyline(diamond + PackedVector2Array([diamond[0]]), Color(0.91, 0.78, 0.42, 0.95), 2.0)

func _draw_decor(tile: Vector2i, p: Vector2, kind: String) -> void:
	var seed_v := (tile.x * 31 + tile.y * 17) % 7
	match kind:
		"tree":
			draw_rect(Rect2(p + Vector2(-2, -12), Vector2(4, 12)), Color("#3a2a19"))
			for i in 3:
				var col: Color = [Color("#3f7a4a"), Color("#356a40"), Color("#2c5a36")][i]
				var top_y := -30.0 + i * 7.0
				var base_y := -12.0 + i * 7.0
				var wid := 12.0 - i * 2.0
				draw_colored_polygon(PackedVector2Array([
					p + Vector2(0, top_y), p + Vector2(wid, base_y), p + Vector2(-wid, base_y)]), col)
		"rock":
			var off := Vector2((seed_v - 3) * 2.0, -5.0)
			draw_circle(p + off, 8.0, Color("#8b8275"))
			draw_circle(p + off + Vector2(-2, -3), 4.0, Color("#a89d8c"))
		"plank":
			for i in range(-1, 2):
				draw_line(p + Vector2(-Iso.TW * 0.5 + 6, i * 7), p + Vector2(Iso.TW * 0.5 - 6, i * 7),
					Color(0, 0, 0, 0.28), 1.0)

func _draw_unit(u: Unit) -> void:
	var gp := _unit_grid_pos(u)
	var p := project(gp.x, gp.y, _unit_height(u))
	var f := _unit_fx(u)
	var font := ThemeDB.fallback_font

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var alive := u.alive()
	var team_color := Color(0.47, 0.67, 1.0) if u.team == "P" else Color(1.0, 0.47, 0.47)

	# Ground shadow and the team ring.
	draw_set_transform(p + Vector2(0, 2), 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, 14.0, Color(0, 0, 0, 0.4))
	draw_arc(Vector2.ZERO, 16.0, 0.0, TAU, 24, team_color, 2.0)
	if battle.active == u and alive:
		draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 28,
			Color(0.91, 0.78, 0.42, 0.5 + 0.4 * sin(_time * 5.0)), 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if not alive:
		var mark := "x"
		var mw := font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string(font, p + Vector2(-mw * 0.5, -6), mark, HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
			Color(1, 1, 1, 0.45))
		return

	# Facing wedge, so back attacks are readable at a glance.
	var fd: Vector2i = Iso.DIRS[u.facing]
	var fp := project(gp.x + fd.x * 0.6, gp.y + fd.y * 0.6, _unit_height(u))
	var ang := (fp - (p + Vector2(0, 2))).angle()
	draw_set_transform(p + Vector2(0, 2), ang, Vector2.ONE)
	draw_colored_polygon(PackedVector2Array([Vector2(15, 0), Vector2(8, -4), Vector2(8, 4)]),
		Color(team_color.r, team_color.g, team_color.b, 0.8))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var bob := sin(float(f["bob"])) * 1.4
	var body_h := 30.0
	var body_w := 15.0
	var cy := p.y - body_h * 0.55 + bob
	var col: Color = f["flash_color"] if float(f["flash"]) > 0.0 else u.color()

	# A tapered pawn reads better in isometric than a flat circle.
	var body := PackedVector2Array([
		Vector2(p.x - body_w * 0.45, p.y),
		Vector2(p.x - body_w * 0.62, cy + 2),
		Vector2(p.x - body_w * 0.8, cy - body_h * 0.35),
		Vector2(p.x, cy - body_h * 0.5),
		Vector2(p.x + body_w * 0.8, cy - body_h * 0.35),
		Vector2(p.x + body_w * 0.62, cy + 2),
		Vector2(p.x + body_w * 0.45, p.y)])
	draw_colored_polygon(body, col)
	draw_polyline(body + PackedVector2Array([body[0]]), Color(0, 0, 0, 0.45), 1.2)
	# A lighter cap gives the pawn a shaded, rounded top.
	draw_colored_polygon(PackedVector2Array([
		Vector2(p.x - body_w * 0.7, cy - body_h * 0.28),
		Vector2(p.x, cy - body_h * 0.5),
		Vector2(p.x + body_w * 0.7, cy - body_h * 0.28),
		Vector2(p.x, cy - body_h * 0.12)]), col.lightened(0.25))

	var letter: String = JOB_LETTER.get(u.job, "?")
	var lw := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	draw_string(font, Vector2(p.x - lw * 0.5, cy - body_h * 0.14), letter,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 0, 0, 0.75))

	# HP (and MP) bar above the head.
	var bw := 30.0
	var by := cy - body_h * 0.78
	draw_rect(Rect2(p.x - bw * 0.5, by, bw, 4.5), Color(0.02, 0.03, 0.06, 0.85))
	var frac := float(u.hp) / u.max_hp
	var hp_col := Color("#6fd08c") if frac > 0.5 else (Color("#e8c66a") if frac > 0.25 else Color("#e05b5b"))
	draw_rect(Rect2(p.x - bw * 0.5, by, bw * frac, 4.5), hp_col)
	if u.max_mp > 0:
		draw_rect(Rect2(p.x - bw * 0.5, by + 5.4, bw, 2.4), Color(0.02, 0.03, 0.06, 0.8))
		draw_rect(Rect2(p.x - bw * 0.5, by + 5.4, bw * (float(u.mp) / u.max_mp), 2.4), Color("#7aa5ff"))

	# Status pips
	var ids: Array = u.status.keys()
	if not ids.is_empty():
		var shown := mini(ids.size(), 4)
		for k in shown:
			var sd: Dictionary = GameData.STATUS[ids[k]]
			draw_rect(Rect2(p.x - (shown - 1) * 4.0 + k * 8.0 - 3.0, by - 9.0, 6.0, 6.0),
				Color(String(sd["color"])))
