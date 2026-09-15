"use strict";
/* ============================================================================
   TACTICS CORE — ISOMETRIC RENDERER
   Every tile is a 2:1 diamond top plus two shaded side faces, so terrain
   height reads as real geometry. Units, terrain and effects go into one
   depth-sorted draw list, which is what keeps a unit correctly hidden behind
   a cliff instead of floating over it.
   ========================================================================== */
var TC = window.TC || (window.TC = {});   /* var, not const: these are classic scripts sharing one global scope */

const KEY = TC.KEY;

/* Pixel-art atlas built by tools/build-atlas.py from 0x72's CC0 tileset.
   assets/sprites.json lists, per job, four idle frames and a display scale.
   If the manifest is missing or disabled, units fall back to the vector pawn
   below — the game never depends on the image being there.               */
class SpriteAtlas {
  constructor() {
    this.ready = false; this.img = null; this.cells = {}; this.fps = 6;
    fetch("assets/sprites.json").then(r => r.ok ? r.json() : null).then(meta => {
      if (!meta || !meta.enabled) return;
      const img = new Image();
      img.onload = () => { this.img = img; this.cells = meta.cells || {}; this.scale = meta.scale || 2; this.fps = meta.fps || 6; this.ready = true; };
      img.onerror = () => { /* no sheet on disk: keep the vector pawns */ };
      img.src = meta.image || "assets/sprites.png";
    }).catch(() => {});
  }
  /* The frame to draw right now for a job, or null for the vector fallback. */
  frame(job, time, phase) {
    if (!this.ready) return null;
    const c = this.cells[job];
    if (!c || !c.frames || !c.frames.length) return null;
    return c.frames[Math.floor(time * this.fps + phase) % c.frames.length];
  }
}
TC.atlas = new SpriteAtlas();

class Renderer {
  constructor(canvas) {
    this.cv = canvas;
    this.ctx = canvas.getContext("2d");
    this.cam = { x: 0, y: 0, zoom: 1, targetZoom: 1 };
    this.rot = 0;
    this.rotFrom = 0;
    this.rotT = 1;                 // 1 = settled
    this.time = 0;
    this.shake = 0;
    this.floaters = [];
    this.particles = [];
    this.shots = [];
    this.casters = new Set();
    this.overlays = { move: new Set(), act: new Set(), aoe: new Set(), path: [], threat: new Set() };
    this.cursor = null;
    this.battle = null;
    this.unitFx = new Map();       // unit.id -> { flash, flashColor, bobPhase, anim }
    this.dpr = 1;
    this.resize();
  }

  attach(battle) {
    this.battle = battle;
    this.unitFx.clear();
    this.floaters.length = 0;
    this.particles.length = 0;
    this.shots.length = 0;
    this.casters = new Set();
    this.fit();
  }

  resize() {
    const rect = this.cv.getBoundingClientRect();
    this.dpr = Math.min(window.devicePixelRatio || 1, 2);
    const w = Math.max(320, Math.round(rect.width)), h = Math.max(240, Math.round(rect.height));
    this.cv.width = Math.round(w * this.dpr);
    this.cv.height = Math.round(h * this.dpr);
    this.vw = w; this.vh = h;
  }

  /* Frame the board. On a narrow screen fitting the whole diagonal would make
     the tiles unreadably small, so we keep a legible floor zoom and let the
     camera follow whoever is acting instead. */
  fit() {
    if (!this.battle) return;
    const g = this.battle.grid;
    const spanW = (g.cols + g.rows) * TC.TW / 2 + 70;
    const spanH = (g.cols + g.rows) * TC.TH / 2 + 8 * TC.HS + 150;
    const zFit = Math.min(this.vw / spanW, this.vh / spanH);
    const floor = this.vw < 720 ? 0.58 : 0.62;
    this.cam.zoom = this.cam.targetZoom = TC.clamp(Math.max(zFit, floor), 0.42, 1.7);
    this.fitsWholeBoard = zFit >= floor;
    this.centerOnBoard();
  }

  /* True when the board does not fit the viewport, in which case the camera
     should track the action rather than sit still. */
  get shouldFollow() { return !this.fitsWholeBoard; }

  centerOnBoard() {
    const g = this.battle.grid;
    // Centre of the board in view space, whatever the rotation.
    const c = TC.project((g.cols - 1) / 2, (g.rows - 1) / 2, 1.2, g.cols, g.rows, this.rot);
    this.cam.x = -c.sx;
    this.cam.y = -c.sy + this.uiBias();
  }

  /* Top and bottom chrome are about the same height on both layouts, so the
     geometric centre is already the right place to aim. Kept as a hook. */
  uiBias() { return 0; }

  /* Smoothly pan so a board tile sits in the middle of the free space. */
  focusOn(x, y, h, snap) {
    if (!this.battle) return;
    const g = this.battle.grid;
    const p = TC.project(x, y, h == null ? g.height(x, y) : h, g.cols, g.rows, this.rot);
    this.camTarget = { x: -p.sx, y: -p.sy + this.uiBias() };
    if (snap) { this.cam.x = this.camTarget.x; this.cam.y = this.camTarget.y; this.camTarget = null; }
  }

  rotateBy(d) {
    // Keep whatever is under the middle of the screen roughly in place.
    const anchor = this.cursor || (this.battle && this.battle.active ? this.battle.active : null);
    this.rotFrom = this.rot;
    this.rot = (this.rot + d + 4) & 3;
    this.rotT = 0;
    this._order = null;
    if (anchor) this.focusOn(anchor.x, anchor.y, null, false);
    else this.centerOnBoard();
  }

  zoomBy(f) { this.cam.targetZoom = TC.clamp(this.cam.targetZoom * f, 0.38, 2.2); }
  panBy(dx, dy) { this.camTarget = null; this.cam.x += dx / this.cam.zoom; this.cam.y += dy / this.cam.zoom; }

  /* ------------------------------------------------------------ helpers */
  project(x, y, h) {
    const g = this.battle.grid;
    const to = TC.project(x, y, h, g.cols, g.rows, this.rot);
    if (this.rotT >= 1) return to;
    const from = TC.project(x, y, h, g.cols, g.rows, this.rotFrom);
    const t = TC.easeOut(this.rotT);
    return { sx: TC.lerp(from.sx, to.sx, t), sy: TC.lerp(from.sy, to.sy, t), depth: TC.lerp(from.depth, to.depth, t) };
  }

  toScreen(p) {
    return { x: (p.sx + this.cam.x) * this.cam.zoom + this.vw / 2,
             y: (p.sy + this.cam.y) * this.cam.zoom + this.vh / 2 };
  }

  /* Reverse painter order hit-test: the first tile whose top face or visible
     side contains the point is the one the player means.                    */
  screenToTile(px, py) {
    if (!this.battle) return null;
    const g = this.battle.grid;
    const order = this.tileOrder();
    for (let i = order.length - 1; i >= 0; i--) {
      const t = order[i];
      const p = this.toScreen(this.project(t.x, t.y, t.h));
      const z = this.cam.zoom;
      const dx = (px - p.x) / z, dy = (py - p.y) / z;
      if (Math.abs(dx) / (TC.TW / 2) + Math.abs(dy) / (TC.TH / 2) <= 1) return { x: t.x, y: t.y };
      // Side faces, so clicking the wall of a cliff still selects its top.
      const drop = this.faceDrop(t);
      if (dy > 0 && dy < TC.TH / 2 + Math.max(drop.l, drop.r) * TC.HS) {
        if (dx <= 0 && dx >= -TC.TW / 2 && dy <= TC.TH / 2 + drop.l * TC.HS + dx * (TC.TH / TC.TW)) return { x: t.x, y: t.y };
        if (dx >= 0 && dx <= TC.TW / 2 && dy <= TC.TH / 2 + drop.r * TC.HS - dx * (TC.TH / TC.TW)) return { x: t.x, y: t.y };
      }
    }
    return null;
  }

  /* How far each front face has to drop before it meets its neighbour. */
  faceDrop(tile) {
    const g = this.battle.grid;
    const rot = this.rot;
    const r = TC.rotate(tile.x, tile.y, g.cols, g.rows, rot);
    const vd = TC.viewDims(g.cols, g.rows, rot);
    const nb = (rx, ry) => {
      if (rx < 0 || ry < 0 || rx >= vd.cols || ry >= vd.rows) return -1;
      const b = TC.unrotate(rx, ry, g.cols, g.rows, rot);
      const t = g.at(b.x, b.y);
      return (!t || t.terrain.void) ? -1 : t.h;
    };
    return { l: Math.max(0.6, tile.h - nb(r.x, r.y + 1)), r: Math.max(0.6, tile.h - nb(r.x + 1, r.y)) };
  }

  /* Back-to-front diagonal sweep in the current view space. */
  tileOrder() {
    if (this._orderRot === this.rot && this._order && this._orderGrid === this.battle.grid) return this._order;
    const g = this.battle.grid;
    const vd = TC.viewDims(g.cols, g.rows, this.rot);
    const out = [];
    for (let s = 0; s <= vd.cols + vd.rows - 2; s++) {
      for (let rx = Math.max(0, s - vd.rows + 1); rx <= Math.min(vd.cols - 1, s); rx++) {
        const ry = s - rx;
        const b = TC.unrotate(rx, ry, g.cols, g.rows, this.rot);
        const t = g.at(b.x, b.y);
        if (t && !t.terrain.void) out.push(t);
      }
    }
    this._order = out; this._orderRot = this.rot; this._orderGrid = g;
    return out;
  }

  /* ---------------------------------------------------------- effects */
  float(x, y, h, text, color, opts) {
    this.floaters.push(Object.assign({ x, y, h, text, color, life: 1, size: 18, vy: -38, dx: (Math.random() - .5) * 10 }, opts || {}));
  }
  burst(x, y, h, color, n, power) {
    for (let i = 0; i < (n || 12); i++) {
      const a = Math.random() * Math.PI * 2, s = (0.4 + Math.random()) * (power || 1);
      this.particles.push({ x, y, h, vx: Math.cos(a) * s * 0.06, vy: Math.sin(a) * s * 0.06, vz: 1.4 + Math.random() * 2.2, life: 1, color });
    }
  }
  flashUnit(u, color) { this.fx(u).flash = 1; this.fx(u).flashColor = color; }
  fx(u) {
    let f = this.unitFx.get(u.id);
    if (!f) { f = { flash: 0, flashColor: "#fff", bob: Math.random() * 6.28, anim: null, ox: 0, oy: 0, oz: 0 }; this.unitFx.set(u.id, f); }
    return f;
  }
  /* Slides a unit along a walked path, hopping over height changes. */
  walk(u, from, path, onDone) {
    if (!path || !path.length) { onDone && onDone(); return; }
    this.fx(u).anim = { path, i: 0, t: 0, from: { x: from.x, y: from.y }, onDone };
  }
  shakeBy(n) { this.shake = Math.min(18, this.shake + n); }

  /* A short step toward the target and back: the melee swing. */
  lunge(u, toward) {
    const f = this.fx(u);
    f.lunge = { dx: toward.x - u.x, dy: toward.y - u.y, t: 0 };
  }
  /* A dot travelling on a parabola from a unit to a tile. */
  projectile(from, to, color) {
    const g = this.battle.grid;
    this.shots.push({ x0: from.x, y0: from.y, h0: g.height(from.x, from.y) + 0.9,
                      x1: to.x, y1: to.y, h1: g.height(to.x, to.y) + 0.6, t: 0, color });
  }

  /* ------------------------------------------------------------- draw */
  draw(dt) {
    const ctx = this.ctx, b = this.battle;
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    ctx.clearRect(0, 0, this.vw, this.vh);
    if (!b) return;

    this.time += dt;
    if (this.rotT < 1) this.rotT = Math.min(1, this.rotT + dt * 3.2);
    this.cam.zoom += (this.cam.targetZoom - this.cam.zoom) * Math.min(1, dt * 10);
    if (this.camTarget) {
      const k = Math.min(1, dt * 6);
      this.cam.x += (this.camTarget.x - this.cam.x) * k;
      this.cam.y += (this.camTarget.y - this.cam.y) * k;
      if (Math.abs(this.camTarget.x - this.cam.x) < 0.5 && Math.abs(this.camTarget.y - this.cam.y) < 0.5) this.camTarget = null;
    }
    if (this.shake > 0) this.shake = Math.max(0, this.shake - dt * 46);

    const sx = this.shake ? (Math.random() - .5) * this.shake : 0;
    const sy = this.shake ? (Math.random() - .5) * this.shake : 0;
    ctx.save();
    ctx.translate(sx, sy);

    this.drawSky();
    const list = [];
    this.collectTerrain(list);
    this.collectUnits(list, dt);
    this.collectEffects(list, dt);
    list.sort((a, c) => (a.depth - c.depth) || (a.order - c.order));
    for (const item of list) item.fn(ctx);
    this.drawWeather();
    ctx.restore();
  }

  drawSky() {
    const ctx = this.ctx, w = this.vw, h = this.vh;
    const weather = this.battle.grid.weather;
    const tints = {
      clear: ["#1d2742", "#0d0f1a"], rain: ["#1a2233", "#080a12"],
      dusk: ["#3a2340", "#120c18"], night: ["#141030", "#05040c"],
    };
    const [a, c] = tints[weather] || tints.clear;
    const gr = ctx.createLinearGradient(0, 0, 0, h);
    gr.addColorStop(0, a); gr.addColorStop(1, c);
    ctx.fillStyle = gr; ctx.fillRect(0, 0, w, h);
  }

  drawWeather() {
    const ctx = this.ctx, w = this.vw, h = this.vh, t = this.time;
    if (this.battle.grid.weather === "rain") {
      ctx.strokeStyle = "rgba(160,200,255,.22)"; ctx.lineWidth = 1;
      ctx.beginPath();
      for (let i = 0; i < 90; i++) {
        const x = (i * 97 + t * 420) % (w + 60) - 30;
        const y = (i * 53 + t * 900) % (h + 60) - 30;
        ctx.moveTo(x, y); ctx.lineTo(x - 5, y + 14);
      }
      ctx.stroke();
    } else if (this.battle.grid.weather === "night") {
      ctx.fillStyle = "rgba(90,60,150,.06)"; ctx.fillRect(0, 0, w, h);
    }
    // Vignette keeps the eye on the board.
    const g = ctx.createRadialGradient(w / 2, h / 2, Math.min(w, h) * .35, w / 2, h / 2, Math.max(w, h) * .75);
    g.addColorStop(0, "rgba(0,0,0,0)"); g.addColorStop(1, "rgba(0,0,0,.55)");
    ctx.fillStyle = g; ctx.fillRect(0, 0, w, h);
  }

  /* ---------------------------------------------------------- terrain */
  collectTerrain(list) {
    const b = this.battle, g = b.grid, z = this.cam.zoom;
    const order = this.tileOrder();
    for (const tile of order) {
      const pr = this.project(tile.x, tile.y, tile.h);
      const p = this.toScreen(pr);
      if (p.x < -120 || p.x > this.vw + 120 || p.y < -160 || p.y > this.vh + 220) continue;
      const drop = this.faceDrop(tile);
      list.push({ depth: pr.depth, order: 0, fn: ctx => this.drawTile(ctx, tile, p, z, drop) });
    }
  }

  drawTile(ctx, tile, p, z, drop) {
    const T = tile.terrain;
    const hw = TC.TW / 2 * z, hh = TC.TH / 2 * z, hs = TC.HS * z;
    const lDrop = drop.l * hs, rDrop = drop.r * hs;

    // Side faces first (left darker than right, as if lit from the upper right)
    ctx.fillStyle = TC.shade(T.top, -46);
    ctx.beginPath();
    ctx.moveTo(p.x - hw, p.y); ctx.lineTo(p.x, p.y + hh);
    ctx.lineTo(p.x, p.y + hh + lDrop); ctx.lineTo(p.x - hw, p.y + lDrop);
    ctx.closePath(); ctx.fill();

    ctx.fillStyle = TC.shade(T.top, -24);
    ctx.beginPath();
    ctx.moveTo(p.x + hw, p.y); ctx.lineTo(p.x, p.y + hh);
    ctx.lineTo(p.x, p.y + hh + rDrop); ctx.lineTo(p.x + hw, p.y + rDrop);
    ctx.closePath(); ctx.fill();

    // Top face
    let top = T.top;
    if (T.liquid) {
      const wob = Math.sin(this.time * 2 + (tile.x + tile.y) * 0.8) * 10;
      top = TC.shade(T.top, wob);
    }
    ctx.fillStyle = top;
    ctx.beginPath();
    ctx.moveTo(p.x, p.y - hh); ctx.lineTo(p.x + hw, p.y);
    ctx.lineTo(p.x, p.y + hh); ctx.lineTo(p.x - hw, p.y);
    ctx.closePath(); ctx.fill();
    ctx.strokeStyle = "rgba(0,0,0,.25)"; ctx.lineWidth = 1; ctx.stroke();

    if (T.glow) {
      ctx.save(); ctx.globalAlpha = .25 + .2 * Math.sin(this.time * 3 + tile.x);
      ctx.fillStyle = T.glow; ctx.fill(); ctx.restore();
    }

    this.drawOverlay(ctx, tile, p, hw, hh);
    if (T.decor) this.drawDecor(ctx, tile, p, z);
  }

  drawOverlay(ctx, tile, p, hw, hh) {
    const k = KEY(tile.x, tile.y), o = this.overlays;
    let fill = null, glow = 0;
    if (o.aoe.has(k))         { fill = "rgba(255,150,60,.55)"; glow = 1; }
    else if (o.act.has(k))    { fill = "rgba(232,72,72,.46)"; }
    else if (o.move.has(k))   { fill = "rgba(78,150,255,.46)"; }
    else if (o.threat.has(k)) { fill = "rgba(255,120,60," + (0.22 + 0.12 * Math.sin(this.time * 6)) + ")"; }
    if (fill) {
      ctx.save();
      ctx.globalAlpha = glow ? .7 + .25 * Math.sin(this.time * 7) : 1;
      ctx.fillStyle = fill;
      ctx.beginPath();
      ctx.moveTo(p.x, p.y - hh); ctx.lineTo(p.x + hw, p.y);
      ctx.lineTo(p.x, p.y + hh); ctx.lineTo(p.x - hw, p.y);
      ctx.closePath(); ctx.fill();
      ctx.restore();
    }
    if (this.overlays.path.some(s => s.x === tile.x && s.y === tile.y)) {
      ctx.fillStyle = "rgba(255,255,255,.55)";
      ctx.beginPath(); ctx.ellipse(p.x, p.y, hw * .18, hh * .18, 0, 0, 6.3); ctx.fill();
    }
    if (this.cursor && this.cursor.x === tile.x && this.cursor.y === tile.y) {
      ctx.strokeStyle = "rgba(232,198,106,.95)"; ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(p.x, p.y - hh); ctx.lineTo(p.x + hw, p.y);
      ctx.lineTo(p.x, p.y + hh); ctx.lineTo(p.x - hw, p.y);
      ctx.closePath(); ctx.stroke();
    }
  }

  drawDecor(ctx, tile, p, z) {
    const seed = (tile.x * 31 + tile.y * 17) % 7;
    if (tile.terrain.decor === "tree") {
      const s = z * (0.9 + seed * 0.03);
      ctx.fillStyle = "#3a2a19";
      ctx.fillRect(p.x - 2 * s, p.y - 12 * s, 4 * s, 12 * s);
      for (let i = 0; i < 3; i++) {
        ctx.fillStyle = i === 0 ? "#3f7a4a" : i === 1 ? "#356a40" : "#2c5a36";
        ctx.beginPath();
        ctx.moveTo(p.x, p.y - (30 + i * -7) * s);
        ctx.lineTo(p.x + (12 - i * 2) * s, p.y - (12 + i * -7) * s);
        ctx.lineTo(p.x - (12 - i * 2) * s, p.y - (12 + i * -7) * s);
        ctx.closePath(); ctx.fill();
      }
    } else if (tile.terrain.decor === "rock") {
      const s = z;
      ctx.fillStyle = "#8b8275";
      ctx.beginPath();
      ctx.ellipse(p.x + (seed - 3) * 2 * s, p.y - 5 * s, 9 * s, 6 * s, 0, 0, 6.3);
      ctx.fill();
      ctx.fillStyle = "#a89d8c";
      ctx.beginPath(); ctx.ellipse(p.x + (seed - 3) * 2 * s - 2 * s, p.y - 7 * s, 5 * s, 3 * s, 0, 0, 6.3); ctx.fill();
    } else if (tile.terrain.decor === "plank") {
      ctx.strokeStyle = "rgba(0,0,0,.28)"; ctx.lineWidth = 1;
      for (let i = -1; i <= 1; i++) {
        ctx.beginPath();
        ctx.moveTo(p.x - TC.TW / 2 * z + 6 * z, p.y + i * 7 * z);
        ctx.lineTo(p.x + TC.TW / 2 * z - 6 * z, p.y + i * 7 * z);
        ctx.stroke();
      }
    }
  }

  /* ------------------------------------------------------------ units */
  collectUnits(list, dt) {
    const b = this.battle, g = b.grid, z = this.cam.zoom;
    for (const u of b.units) {
      const f = this.fx(u);
      f.bob += dt * 2.4;
      if (f.flash > 0) f.flash = Math.max(0, f.flash - dt * 3.4);

      let gx = u.x, gy = u.y, h = g.height(u.x, u.y);
      if (f.anim) {
        const a = f.anim;
        a.t += dt * 5.6;
        const step = a.path[a.i];
        const prev = a.i === 0 ? a.from : a.path[a.i - 1];
        const t = Math.min(1, a.t);
        gx = TC.lerp(prev.x, step.x, t);
        gy = TC.lerp(prev.y, step.y, t);
        const h0 = g.height(prev.x, prev.y);
        const dh = g.height(step.x, step.y) - h0;
        // A little hop sells the step up or down a terrace.
        h = h0 + dh * t + Math.sin(t * Math.PI) * (0.35 + Math.abs(dh) * 0.28);
        if (a.t >= 1) {
          a.i++; a.t = 0;
          if (a.i >= a.path.length) { const d = a.onDone; f.anim = null; d && d(); }
        }
      }
      if (f.lunge) {
        f.lunge.t += dt * 6;
        const k = Math.sin(Math.min(1, f.lunge.t) * Math.PI) * 0.35;
        const n = Math.max(1, Math.abs(f.lunge.dx) + Math.abs(f.lunge.dy));
        gx += f.lunge.dx / n * k; gy += f.lunge.dy / n * k;
        if (f.lunge.t >= 1) f.lunge = null;
      }
      const pr = this.project(gx, gy, h);
      const p = this.toScreen(pr);
      list.push({ depth: pr.depth + 0.5, order: 1, fn: ctx => this.drawUnit(ctx, u, p, z, f, gx, gy, h) });
    }
  }

  drawUnit(ctx, u, p, z, f, gx, gy, h) {
    const alive = u.alive;
    const active = this.battle.active === u;
    const bob = alive ? Math.sin(f.bob) * 1.4 * z : 0;
    const bodyH = 30 * z, bodyW = 15 * z;

    // Ground ring + shadow
    ctx.save();
    ctx.globalAlpha = alive ? 1 : .45;
    ctx.fillStyle = "rgba(0,0,0,.4)";
    ctx.beginPath(); ctx.ellipse(p.x, p.y + 2 * z, 13 * z, 7 * z, 0, 0, 6.3); ctx.fill();
    ctx.strokeStyle = u.npc ? "rgba(255,225,130,.95)" : u.team === "P" ? "rgba(120,170,255,.95)" : "rgba(255,120,120,.95)";
    ctx.lineWidth = 2 * z;
    ctx.beginPath(); ctx.ellipse(p.x, p.y + 2 * z, 15 * z, 8 * z, 0, 0, 6.3); ctx.stroke();

    if (alive && this.casters && this.casters.has(u.id)) {
      ctx.save();
      ctx.strokeStyle = "rgba(255,157,92," + (0.55 + 0.35 * Math.sin(this.time * 6)) + ")";
      ctx.lineWidth = 2 * z; ctx.setLineDash([4 * z, 3 * z]);
      ctx.beginPath(); ctx.ellipse(p.x, p.y + 2 * z, 21 * z, 11 * z, this.time * 1.5, 0, 6.3); ctx.stroke();
      ctx.restore();
    }
    if (active && alive) {
      ctx.strokeStyle = "rgba(232,198,106," + (0.5 + 0.4 * Math.sin(this.time * 5)) + ")";
      ctx.lineWidth = 3 * z;
      ctx.beginPath(); ctx.ellipse(p.x, p.y + 2 * z, 19 * z, 10 * z, 0, 0, 6.3); ctx.stroke();
    }

    if (!alive) {
      ctx.globalAlpha = .55;
      ctx.font = `${Math.round(20 * z)}px serif`;
      ctx.textAlign = "center"; ctx.textBaseline = "middle";
      ctx.fillText("✝", p.x, p.y - 8 * z);
      ctx.restore();
      return;
    }

    // Facing wedge on the ground, so back-attacks are readable at a glance.
    // Uses the animated position so it points correctly mid-walk.
    const fd = TC.DIRS[u.facing];
    const fs = this.toScreen(this.project(gx + fd[0] * .6, gy + fd[1] * .6, h));
    ctx.fillStyle = u.team === "P" ? "rgba(120,170,255,.8)" : "rgba(255,120,120,.8)";
    const ang = Math.atan2(fs.y - (p.y + 2 * z), fs.x - p.x);
    ctx.save(); ctx.translate(p.x, p.y + 2 * z); ctx.rotate(ang);
    ctx.beginPath(); ctx.moveTo(15 * z, 0); ctx.lineTo(8 * z, -4 * z); ctx.lineTo(8 * z, 4 * z);
    ctx.closePath(); ctx.fill(); ctx.restore();

    const cy = p.y - bodyH * .55 + bob;
    const cell = TC.atlas.frame(u.job, this.time, f.bob);
    if (cell) {
      // Sprite billboard: feet on the tile, idle frames cycling, flipped to
      // face the way the unit is looking (the source art faces right).
      const sw = cell.w * TC.atlas.scale * z, sh = cell.h * TC.atlas.scale * z;
      const flip = u.facing === TC.FACING.W || u.facing === TC.FACING.N;
      const top = p.y - sh + 4 * z;
      ctx.save();
      ctx.imageSmoothingEnabled = false;
      ctx.translate(p.x, 0); if (flip) ctx.scale(-1, 1);
      ctx.drawImage(TC.atlas.img, cell.x, cell.y, cell.w, cell.h, -sw / 2, top, sw, sh);
      if (f.flash > 0) {
        ctx.globalCompositeOperation = "source-atop"; ctx.globalAlpha = f.flash * .8;
        ctx.fillStyle = f.flashColor; ctx.fillRect(-sw / 2, top, sw, sh);
      }
      ctx.restore();
      this.drawUnitBars(ctx, u, p, z, top - 9 * z);
      ctx.restore();
      return;
    }
    // Body: a tapered pawn reads better than a flat circle in isometric.
    const grad = ctx.createLinearGradient(p.x, cy - bodyH / 2, p.x, p.y);
    const base = f.flash > 0 ? f.flashColor : u.color;
    grad.addColorStop(0, TC.shade(u.color, 40));
    grad.addColorStop(1, TC.shade(u.color, -40));
    ctx.fillStyle = f.flash > 0 ? base : grad;
    ctx.beginPath();
    ctx.moveTo(p.x - bodyW * .45, p.y);
    ctx.lineTo(p.x - bodyW * .62, cy + 2 * z);
    ctx.quadraticCurveTo(p.x - bodyW * .8, cy - bodyH * .45, p.x, cy - bodyH * .5);
    ctx.quadraticCurveTo(p.x + bodyW * .8, cy - bodyH * .45, p.x + bodyW * .62, cy + 2 * z);
    ctx.lineTo(p.x + bodyW * .45, p.y);
    ctx.closePath(); ctx.fill();
    ctx.strokeStyle = "rgba(0,0,0,.45)"; ctx.lineWidth = 1.2 * z; ctx.stroke();

    ctx.font = `${Math.round(16 * z)}px serif`;
    ctx.textAlign = "center"; ctx.textBaseline = "middle";
    ctx.fillText(u.icon, p.x, cy - bodyH * .18);

    this.drawUnitBars(ctx, u, p, z, cy - bodyH * .72);
    ctx.restore();
  }

  /* HP/MP bars and status pips, shared by the sprite and vector paths. */
  drawUnitBars(ctx, u, p, z, by) {
    const bw = 30 * z;
    ctx.fillStyle = "rgba(6,8,16,.85)"; ctx.fillRect(p.x - bw / 2, by, bw, 4.5 * z);
    const frac = u.hp / u.maxHp;
    ctx.fillStyle = frac > .5 ? "#6fd08c" : frac > .25 ? "#e8c66a" : "#e05b5b";
    ctx.fillRect(p.x - bw / 2, by, bw * frac, 4.5 * z);
    if (u.maxMp > 0) {
      ctx.fillStyle = "rgba(6,8,16,.8)"; ctx.fillRect(p.x - bw / 2, by + 5.4 * z, bw, 2.4 * z);
      ctx.fillStyle = "#7aa5ff"; ctx.fillRect(p.x - bw / 2, by + 5.4 * z, bw * (u.mp / u.maxMp), 2.4 * z);
    }

    // Status pips
    const ids = Object.keys(u.status);
    if (ids.length) {
      ctx.font = `${Math.round(10 * z)}px sans-serif`;
      ids.slice(0, 4).forEach((id, i) => {
        const d = TC.STATUS[id];
        ctx.fillStyle = d.color;
        ctx.fillText(d.icon, p.x - (ids.length - 1) * 5 * z + i * 10 * z, by - 7 * z);
      });
    }
  }

  /* ---------------------------------------------------------- effects */
  collectEffects(list, dt) {
    const g = this.battle.grid;
    for (let i = this.shots.length - 1; i >= 0; i--) {
      const s = this.shots[i];
      s.t += dt * 3.2;
      if (s.t >= 1) { this.shots.splice(i, 1); continue; }
      const t = s.t, arc = Math.sin(t * Math.PI) * 1.6;
      const x = TC.lerp(s.x0, s.x1, t), y = TC.lerp(s.y0, s.y1, t), h = TC.lerp(s.h0, s.h1, t) + arc;
      const pr = this.project(x, y, h);
      const p = this.toScreen(pr);
      list.push({ depth: pr.depth + 0.6, order: 2, fn: ctx => {
        ctx.fillStyle = s.color;
        ctx.shadowColor = s.color; ctx.shadowBlur = 10 * this.cam.zoom;
        ctx.beginPath(); ctx.arc(p.x, p.y, 3.2 * this.cam.zoom, 0, 6.3); ctx.fill();
        ctx.shadowBlur = 0;
      } });
    }
    for (let i = this.particles.length - 1; i >= 0; i--) {
      const q = this.particles[i];
      q.x += q.vx; q.y += q.vy; q.h += q.vz * dt * 2.4; q.vz -= dt * 9;
      q.life -= dt * 1.5;
      if (q.life <= 0) { this.particles.splice(i, 1); continue; }
      const pr = this.project(q.x, q.y, q.h);
      const p = this.toScreen(pr);
      list.push({ depth: pr.depth + 0.7, order: 2, fn: ctx => {
        ctx.globalAlpha = Math.max(0, q.life);
        ctx.fillStyle = q.color;
        const s = 3 * this.cam.zoom * q.life;
        ctx.fillRect(p.x - s / 2, p.y - s / 2, s, s);
        ctx.globalAlpha = 1;
      } });
    }
    for (let i = this.floaters.length - 1; i >= 0; i--) {
      const fl = this.floaters[i];
      fl.life -= dt * 1.05;
      fl.h += dt * 1.6;
      if (fl.life <= 0) { this.floaters.splice(i, 1); continue; }
      const pr = this.project(fl.x, fl.y, fl.h + 1.1);
      const p = this.toScreen(pr);
      list.push({ depth: 9999, order: 3, fn: ctx => {
        ctx.save();
        ctx.globalAlpha = Math.min(1, fl.life * 1.6);
        ctx.font = `bold ${Math.round(fl.size * this.cam.zoom)}px "Segoe UI", system-ui, sans-serif`;
        ctx.textAlign = "center"; ctx.textBaseline = "middle";
        ctx.lineWidth = 3.5; ctx.strokeStyle = "rgba(0,0,0,.85)";
        ctx.strokeText(fl.text, p.x + fl.dx, p.y);
        ctx.fillStyle = fl.color;
        ctx.fillText(fl.text, p.x + fl.dx, p.y);
        ctx.restore();
      } });
    }
  }
}
TC.Renderer = Renderer;
