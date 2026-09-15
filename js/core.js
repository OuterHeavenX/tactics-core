"use strict";
/* ============================================================================
   TACTICS CORE — CORE
   Isometric projection, the tile grid, and height-aware pathfinding.
   ========================================================================== */
var TC = window.TC || (window.TC = {});   /* var, not const: these are classic scripts sharing one global scope */

/* --------------------------------------------------------------- iso math */
/* A tile's top face is a 2:1 diamond. Height raises it by HS pixels a step,
   which is the whole reason the board reads as 2.5D instead of flat.        */
TC.TW = 64;   // tile width  (screen px)
TC.TH = 32;   // tile height (screen px) — exactly half of TW for a 2:1 iso
TC.HS = 16;   // pixels per height step

/* The camera can sit at any of 4 corners. `rotate` maps board coords into the
   current view's coords so the painter's algorithm stays a simple diagonal
   sweep no matter which way we are looking.                                 */
TC.rotate = function (x, y, cols, rows, rot) {
  switch (rot & 3) {
    case 0:  return { x: x,               y: y };
    case 1:  return { x: y,               y: cols - 1 - x };
    case 2:  return { x: cols - 1 - x,    y: rows - 1 - y };
    default: return { x: rows - 1 - y,    y: x };
  }
};
/* Inverse of the above, for turning a picked view tile back into board space */
TC.unrotate = function (rx, ry, cols, rows, rot) {
  switch (rot & 3) {
    case 0:  return { x: rx,               y: ry };
    case 1:  return { x: cols - 1 - ry,    y: rx };
    case 2:  return { x: cols - 1 - rx,    y: rows - 1 - ry };
    default: return { x: ry,               y: rows - 1 - rx };
  }
};
/* View dimensions swap on the odd rotations. */
TC.viewDims = (cols, rows, rot) => (rot & 1) ? { cols: rows, rows: cols } : { cols, rows };

/* Board coords (may be fractional, for units mid-step) -> screen px. */
TC.project = function (x, y, h, cols, rows, rot) {
  let rx, ry;
  switch (rot & 3) {
    case 0:  rx = x;                ry = y;                break;
    case 1:  rx = y;                ry = cols - 1 - x;     break;
    case 2:  rx = cols - 1 - x;     ry = rows - 1 - y;     break;
    default: rx = rows - 1 - y;     ry = x;                break;
  }
  return { sx: (rx - ry) * (TC.TW / 2), sy: (rx + ry) * (TC.TH / 2) - h * TC.HS, depth: rx + ry };
};

/* ------------------------------------------------------------------- grid */
class Grid {
  constructor(def) {
    this.name = def.name;
    this.weather = def.weather || "clear";
    this.rows = def.t.length;
    this.cols = def.t[0].length;
    this.tiles = [];
    for (let y = 0; y < this.rows; y++) {
      const row = [];
      for (let x = 0; x < this.cols; x++) {
        const code = def.t[y][x];
        row.push({ x, y, code, h: parseInt(def.h[y][x], 10) || 0, terrain: TC.TERRAIN[code] });
      }
      this.tiles.push(row);
    }
  }
  inBounds(x, y) { return x >= 0 && y >= 0 && x < this.cols && y < this.rows; }
  at(x, y) { return this.inBounds(x, y) ? this.tiles[y][x] : null; }
  height(x, y) { const t = this.at(x, y); return t ? t.h : -1; }
  walkable(x, y) { const t = this.at(x, y); return !!t && t.terrain.walk; }
  /* Flat evasion granted by whatever the unit is standing on. */
  eva(x, y) { const t = this.at(x, y); return t ? t.terrain.eva : 0; }
  def(x, y) { const t = this.at(x, y); return t ? t.terrain.def : 0; }
  hazard(x, y) { const t = this.at(x, y); return (t && t.terrain.hazard) || 0; }
  forEach(fn) { for (let y = 0; y < this.rows; y++) for (let x = 0; x < this.cols; x++) fn(this.tiles[y][x]); }
}
TC.Grid = Grid;

const DIRS = [[1, 0], [-1, 0], [0, 1], [0, -1]];
TC.DIRS = DIRS;
TC.manhattan = (a, b) => Math.abs(a.x - b.x) + Math.abs(a.y - b.y);

/* Facing is stored as 0..3 matching DIRS: east, west, south, north. */
TC.FACING = { E: 0, W: 1, S: 2, N: 3 };
TC.facingFromDelta = function (dx, dy) {
  if (Math.abs(dx) >= Math.abs(dy)) return dx >= 0 ? 0 : 1;
  return dy >= 0 ? 2 : 3;
};
TC.facingToward = (from, to) => TC.facingFromDelta(to.x - from.x, to.y - from.y);

/* Which side of `target` is `attacker` on? Drives the FFT-style damage bonus. */
TC.relativeSide = function (target, attacker) {
  const dx = attacker.x - target.x, dy = attacker.y - target.y;
  if (dx === 0 && dy === 0) return "front";
  const inc = TC.facingFromDelta(dx, dy);           // direction attacker lies in
  if (inc === target.facing) return "front";
  const opposite = { 0: 1, 1: 0, 2: 3, 3: 2 };
  if (inc === opposite[target.facing]) return "back";
  return "side";
};

/* ------------------------------------------------------------ pathfinding */
/* Dijkstra over move points. Height differences larger than `jump` are walls,
   which is what makes the ziggurat's terraces matter.                       */
TC.reachable = function (grid, unit, occupied) {
  const key = (x, y) => y * grid.cols + x;
  const cost = new Map([[key(unit.x, unit.y), 0]]);
  const from = new Map();
  const out = [];
  let frontier = [{ x: unit.x, y: unit.y, d: 0 }];
  while (frontier.length) {
    const next = [];
    for (const cur of frontier) {
      if (cur.d >= unit.stat("move")) continue;
      for (const [dx, dy] of DIRS) {
        const nx = cur.x + dx, ny = cur.y + dy;
        if (!grid.walkable(nx, ny)) continue;
        const climb = Math.abs(grid.height(nx, ny) - grid.height(cur.x, cur.y));
        if (climb > unit.stat("jump")) continue;
        const blocker = occupied(nx, ny);
        // You may walk *through* allies but never stop on them.
        if (blocker && blocker.team !== unit.team) continue;
        const nd = cur.d + 1, k = key(nx, ny);
        if (cost.has(k) && cost.get(k) <= nd) continue;
        cost.set(k, nd);
        from.set(k, key(cur.x, cur.y));
        next.push({ x: nx, y: ny, d: nd });
        if (!blocker) out.push({ x: nx, y: ny, d: nd });
      }
    }
    frontier = next;
  }
  return { tiles: out, cost, from, key };
};

/* Rebuild the step-by-step walk produced by `reachable`. */
TC.pathTo = function (grid, res, unit, tx, ty) {
  const path = [];
  let k = res.key(tx, ty);
  const startK = res.key(unit.x, unit.y);
  let guard = 0;
  while (k !== startK && guard++ < 512) {
    path.push({ x: k % grid.cols, y: Math.floor(k / grid.cols) });
    if (!res.from.has(k)) return null;
    k = res.from.get(k);
  }
  return path.reverse();
};

/* Multi-source travel-cost field: for every tile, the cheapest walking cost to
   the nearest source, respecting walls and a jump limit. Hazard tiles cost
   extra, so the AI routes around a lava channel instead of treating it as a
   shortcut it will never actually take — which used to deadlock two melee
   squads either side of the ziggurat's lava. Dial's algorithm, since the edge
   weights are tiny integers. */
TC.HAZARD_COST = 5;
TC.distanceField = function (grid, sources, jump) {
  const n = grid.cols * grid.rows;
  const dist = new Int32Array(n).fill(-1);
  const buckets = [];
  const push = (d, x, y) => { (buckets[d] || (buckets[d] = [])).push(x, y); };
  for (const s of sources) {
    if (!grid.inBounds(s.x, s.y)) continue;
    const k = s.y * grid.cols + s.x;
    if (dist[k] !== -1) continue;
    dist[k] = 0;
    push(0, s.x, s.y);
  }
  for (let d = 0; d < buckets.length; d++) {
    const b = buckets[d];
    if (!b) continue;
    for (let i = 0; i < b.length; i += 2) {
      const x = b[i], y = b[i + 1];
      if (dist[y * grid.cols + x] !== d) continue;      // superseded entry
      for (const [dx, dy] of DIRS) {
        const nx = x + dx, ny = y + dy;
        if (!grid.walkable(nx, ny)) continue;
        if (Math.abs(grid.height(nx, ny) - grid.height(x, y)) > jump) continue;
        const nd = d + 1 + (grid.hazard(nx, ny) ? TC.HAZARD_COST : 0);
        const k2 = ny * grid.cols + nx;
        if (dist[k2] !== -1 && dist[k2] <= nd) continue;
        dist[k2] = nd;
        push(nd, nx, ny);
      }
    }
  }
  return dist;
};

/* Tiles an ability can be aimed at from a given stance. Range is manhattan
   plus a vertical clamp, so a cliff really does put you out of reach.       */
TC.tilesInRange = function (grid, ox, oy, ability) {
  const r = ability.range | 0, min = ability.minRange || 0;
  const vert = ability.vert == null ? 4 : ability.vert;
  const oh = grid.height(ox, oy);
  const out = [];
  for (let dy = -r; dy <= r; dy++) {
    for (let dx = -r + Math.abs(dy); dx <= r - Math.abs(dy); dx++) {
      const x = ox + dx, y = oy + dy, d = Math.abs(dx) + Math.abs(dy);
      if (d < min || d > r) continue;
      if (!grid.inBounds(x, y) || grid.at(x, y).terrain.void) continue;
      if (Math.abs(grid.height(x, y) - oh) > vert) continue;
      if (ability.line && dx !== 0 && dy !== 0) continue;   // straight lines only
      out.push({ x, y, d });
    }
  }
  return out;
};

/* A cone `len` tiles deep, opening from the caster toward `aim`. Row k of the
   cone (k tiles out) is 2*floor(k/2)+1 wide, so breath reaches three tiles
   straight ahead and fans out to the sides. */
TC.coneTiles = function (grid, cx, cy, ax, ay, len) {
  const dir = TC.DIRS[TC.facingFromDelta(ax - cx, ay - cy)];
  const side = dir[0] === 0 ? [1, 0] : [0, 1];
  const out = [];
  for (let k = 1; k <= len; k++) {
    const half = Math.floor(k / 2);
    for (let w = -half; w <= half; w++) {
      const x = cx + dir[0] * k + side[0] * w, y = cy + dir[1] * k + side[1] * w;
      if (grid.inBounds(x, y) && !grid.at(x, y).terrain.void) out.push({ x, y });
    }
  }
  return out;
};

/* Every tile an ability lands on, given who is casting and where it is aimed. */
TC.footprint = function (grid, actor, ability, tx, ty) {
  if (ability.shape === "cone") return TC.coneTiles(grid, actor.x, actor.y, tx, ty, ability.coneLen || 3);
  return ability.aoe ? TC.aoeTiles(grid, tx, ty, ability) : [{ x: tx, y: ty }];
};

/* Where the player may stand at the start of a chapter: every walkable tile
   within two steps of a default deploy slot that no enemy spawns on. */
TC.deployZone = function (grid, chapter) {
  const taken = new Set(chapter.enemies.map(e => TC.KEY(e[2], e[3])));
  if (chapter.npc) taken.add(TC.KEY(chapter.npc[2], chapter.npc[3]));
  const zone = [], seen = new Set();
  for (const [dx0, dy0] of chapter.deploy) {
    for (let dy = -2; dy <= 2; dy++) for (let dx = -2 + Math.abs(dy); dx <= 2 - Math.abs(dy); dx++) {
      const x = dx0 + dx, y = dy0 + dy, k = TC.KEY(x, y);
      if (seen.has(k) || taken.has(k) || !grid.walkable(x, y)) continue;
      seen.add(k); zone.push({ x, y });
    }
  }
  return zone;
};

/* The splash footprint of an ability centred on a tile. */
TC.aoeTiles = function (grid, cx, cy, ability) {
  const r = ability.aoe | 0;
  const out = [];
  for (let dy = -r; dy <= r; dy++)
    for (let dx = -r + Math.abs(dy); dx <= r - Math.abs(dy); dx++) {
      const x = cx + dx, y = cy + dy;
      if (grid.inBounds(x, y) && !grid.at(x, y).terrain.void) out.push({ x, y });
    }
  return out;
};

/* --------------------------------------------------------------- utility */
TC.KEY = (x, y) => x + "," + y;          // tile key shared by rules, AI and renderer
TC.clamp = (v, lo, hi) => v < lo ? lo : v > hi ? hi : v;
TC.lerp = (a, b, t) => a + (b - a) * t;
TC.easeOut = t => 1 - Math.pow(1 - t, 3);
TC.chance = p => Math.random() * 100 < p;
TC.randInt = (lo, hi) => lo + Math.floor(Math.random() * (hi - lo + 1));
TC.shade = function (hex, amt) {
  const n = parseInt(hex.slice(1), 16);
  const r = TC.clamp(((n >> 16) & 255) + amt, 0, 255);
  const g = TC.clamp(((n >> 8) & 255) + amt, 0, 255);
  const b = TC.clamp((n & 255) + amt, 0, 255);
  return `rgb(${r},${g},${b})`;
};
