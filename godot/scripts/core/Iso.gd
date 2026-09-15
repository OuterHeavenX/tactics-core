# ============================================================================
# Isometric projection helpers.
#
# A tile's top face is a 2:1 diamond (TW x TH); every height step lifts it by
# HS pixels. The camera can sit at any of four corners, so board coordinates
# are rotated into "view space" before projecting, which keeps the painter's
# algorithm a plain diagonal sweep at every angle.
# ============================================================================
class_name Iso
extends RefCounted

const TW := 64.0
const TH := 32.0
const HS := 16.0

## Board coords -> view coords for the given camera rotation (0-3).
static func rotate_xy(x: int, y: int, cols: int, rows: int, rot: int) -> Vector2i:
	match rot & 3:
		0: return Vector2i(x, y)
		1: return Vector2i(y, cols - 1 - x)
		2: return Vector2i(cols - 1 - x, rows - 1 - y)
		_: return Vector2i(rows - 1 - y, x)

## View coords -> board coords. Exact inverse of rotate_xy.
static func unrotate(rx: int, ry: int, cols: int, rows: int, rot: int) -> Vector2i:
	match rot & 3:
		0: return Vector2i(rx, ry)
		1: return Vector2i(cols - 1 - ry, rx)
		2: return Vector2i(cols - 1 - rx, rows - 1 - ry)
		_: return Vector2i(ry, rows - 1 - rx)

## View-space grid dimensions; the odd rotations swap width and height.
static func view_dims(cols: int, rows: int, rot: int) -> Vector2i:
	return Vector2i(rows, cols) if (rot & 1) == 1 else Vector2i(cols, rows)

## Returns (screen_x, screen_y, depth). Accepts fractional coords so a unit can
## be projected mid-step between two tiles.
static func project(x: float, y: float, h: float, cols: int, rows: int, rot: int) -> Vector3:
	var rx := 0.0
	var ry := 0.0
	match rot & 3:
		0:
			rx = x
			ry = y
		1:
			rx = y
			ry = float(cols - 1) - x
		2:
			rx = float(cols - 1) - x
			ry = float(rows - 1) - y
		_:
			rx = float(rows - 1) - y
			ry = x
	return Vector3((rx - ry) * TW * 0.5, (rx + ry) * TH * 0.5 - h * HS, rx + ry)

## The four cardinal steps, matching the facing indices used by units.
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

static func facing_from_delta(dx: int, dy: int) -> int:
	if absi(dx) >= absi(dy):
		return 0 if dx >= 0 else 1
	return 2 if dy >= 0 else 3

static func facing_toward(from: Vector2i, to: Vector2i) -> int:
	return facing_from_delta(to.x - from.x, to.y - from.y)

static func manhattan(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)

## Which side of `target` an attacker standing at `from` is on.
static func relative_side(target_pos: Vector2i, target_facing: int, from: Vector2i) -> String:
	var d := from - target_pos
	if d == Vector2i.ZERO:
		return "front"
	var inc := facing_from_delta(d.x, d.y)
	if inc == target_facing:
		return "front"
	var opposite := [1, 0, 3, 2]
	if inc == opposite[target_facing]:
		return "back"
	return "side"
