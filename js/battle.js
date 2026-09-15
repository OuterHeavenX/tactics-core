"use strict";
/* ============================================================================
   TACTICS CORE — BATTLE RULES
   Units, the charge-time turn engine and every combat resolution. This file
   has no DOM or canvas dependency: it runs headless under node, which is how
   the balance tests in tools/ work.
   ========================================================================== */
var TC = window.TC || (window.TC = {});   /* var, not const: these are classic scripts sharing one global scope */

const PHYS_K = 1.7;      // physical damage scalar
const MAG_K  = 1.5;      // magical damage scalar
const BASE_ACC = 90;     // accuracy before evasion and positioning
const CRIT_MULT = 1.5;

/* CT left over after a turn — the classic "do less, act sooner" trade. */
const CT_AFTER = { both: 0, act: 20, move: 40, wait: 60 };

class Unit {
  constructor(name, jobName, team, x, y, level) {
    const job = TC.JOBS[jobName];
    this.name = name;
    this.job = jobName;
    this.jobDef = job;
    this.team = team;                       // "P" | "E"
    this.x = x; this.y = y;
    this.facing = team === "P" ? TC.FACING.E : TC.FACING.W;
    this.level = level || 1;
    this.xp = 0;
    this.color = job.color;
    this.icon = job.icon;
    this.passive = job.passive;
    this.npc = false;                       // set for protect-objective civilians
    this.jp = 0;
    this.learned = [];                      // ability ids bought with JP
    // Enemies know their whole kit; the party starts with a subset and learns.
    this.abilities = (team === "P" && job.starting) ? job.starting.slice() : job.abilities.slice();
    this.status = {};                       // id -> turns remaining
    this.cooldowns = {};                    // abilityId -> turns remaining
    this.applyGrowth();
    this.hp = this.maxHp; this.mp = this.maxMp;
    this.ct = TC.randInt(0, 45);
    this.moved = false; this.acted = false;
    this.counterReady = true;
    this.id = -1;
  }

  /* Base stats for the unit's current level, from the job growth table. */
  applyGrowth() {
    const j = this.jobDef, g = j.growth, n = this.level - 1;
    const r = (base, per) => Math.round(base + per * n);
    this.maxHp = r(j.hp, g.hp);
    this.maxMp = r(j.mp, g.mp);
    this.baseAtk = r(j.atk, g.atk);
    this.baseDef = r(j.def, g.def);
    this.baseMag = r(j.mag, g.mag);
    this.baseRes = r(j.res, g.res);
    this.baseSpd = r(j.spd, g.spd);
    this.move = j.move; this.jump = this.passive === "phase" ? 9 : j.jump;
    this.baseEva = j.eva; this.range = j.range;
  }

  get alive() { return this.hp > 0; }
  get xpToNext() { return 80 + 40 * this.level; }

  /* Effective stat after status multipliers. Everything in the rules reads
     stats through here so buffs never get forgotten at a call site.         */
  stat(key) {
    let mult = 1;
    for (const id in this.status) {
      const def = TC.STATUS[id];
      if (def && def[key] != null) mult *= def[key];
    }
    switch (key) {
      case "atk":  return Math.max(1, Math.round(this.baseAtk * mult));
      case "def":  return Math.max(0, Math.round(this.baseDef * mult));
      case "mag":  return Math.max(1, Math.round(this.baseMag * mult));
      case "res":  return Math.max(0, Math.round(this.baseRes * mult));
      case "spd":  return Math.max(1, Math.round(this.baseSpd * mult));
      case "eva":  return Math.max(0, Math.round(this.baseEva * mult));
      case "move": return Math.max(1, Math.round(this.move * mult));
      case "jump": return this.jump;
      default:     return 0;
    }
  }

  has(s) { return this.status[s] > 0; }
  hasBadStatus() { return Object.keys(this.status).some(s => TC.STATUS[s] && TC.STATUS[s].bad); }

  addStatus(id, turns) {
    if (this.passive === "boss" && TC.STATUS[id] && TC.STATUS[id].bad && id === "stun") return false;
    this.status[id] = Math.max(this.status[id] || 0, turns);
    return true;
  }
  clearBadStatus() {
    let n = 0;
    for (const id in this.status) if (TC.STATUS[id].bad) { delete this.status[id]; n++; }
    return n;
  }

  /* Abilities this unit can pay for right now. */
  usableAbilities() {
    return this.abilities.map(id => TC.ABILITIES[id]).filter(a =>
      a && this.mp >= (a.mp || 0) && !(this.cooldowns[a.id] > 0));
  }

  /* Abilities in the job list that are not yet known. */
  learnable() {
    return this.jobDef.abilities.filter(id => !this.abilities.includes(id) && TC.ABILITIES[id] && TC.ABILITIES[id].jp);
  }
  learn(id) {
    const a = TC.ABILITIES[id];
    if (!a || !a.jp || this.abilities.includes(id) || !this.jobDef.abilities.includes(id) || this.jp < a.jp) return false;
    this.jp -= a.jp;
    this.abilities.push(id);
    this.learned.push(id);
    return true;
  }

  gainXp(n, battle) {
    if (this.team !== "P" || n <= 0 || this.npc) return;
    this.xp += n;
    this.jp += Math.ceil(n * 0.75);         // JP tracks XP, spent on the learn screen
    while (this.xp >= this.xpToNext) {
      this.xp -= this.xpToNext;
      this.level++;
      const oldHp = this.maxHp, oldMp = this.maxMp;
      this.applyGrowth();
      this.hp += this.maxHp - oldHp;
      this.mp += this.maxMp - oldMp;
      battle && battle.emit({ type: "levelup", unit: this });
    }
  }
}
TC.Unit = Unit;

/* ========================================================================== */
class Battle {
  constructor(chapter, party, opts) {
    opts = opts || {};
    this.chapter = chapter;
    this.grid = new TC.Grid(TC.MAPS[chapter.map]);
    this.units = [];
    this.events = [];
    this.pending = [];                      // charging spells waiting to land
    this.turn = 0;
    this.over = null;                       // null | "victory" | "defeat"
    this.active = null;
    this.items = Object.assign({}, TC.START_ITEMS);
    this.levelOffset = opts.levelOffset || 0;
    this.snap = null;

    party.forEach((p, i) => {
      const slot = chapter.deploy[i] || chapter.deploy[chapter.deploy.length - 1];
      const u = this.add(new Unit(p.name, p.job, "P", slot[0], slot[1], p.level || 1));
      u.xp = p.xp || 0; u.jp = p.jp || 0;
      for (const id of p.learned || []) if (!u.abilities.includes(id) && u.jobDef.abilities.includes(id)) {
        u.abilities.push(id); u.learned.push(id);
      }
    });
    if (chapter.npc) {
      const [name, job, x, y] = chapter.npc;
      const n = this.add(new Unit(name, job, "P", x, y, Math.max(1, (chapter.enemyLevel || 1))));
      n.npc = true;
    }
    const base = chapter.enemyLevel != null
      ? chapter.enemyLevel
      : 1 + TC.CAMPAIGN.findIndex(c => c.id === chapter.id) * 2;
    for (const [name, job, x, y] of chapter.enemies) {
      this.add(new Unit(name, job, "E", x, y, Math.max(1, base + this.levelOffset)));
    }
    for (const u of this.units) u.facing = this.faceNearestFoe(u);
  }

  /* ------------------------------------------------- deploy + rewind */
  deployZone() { return TC.deployZone(this.grid, this.chapter); }

  /* Swap or move a party member inside the deploy zone before turn one. */
  placeUnit(u, x, y) {
    if (this.turn > 0 || u.team !== "P" || u.npc) return false;
    if (!this.deployZone().some(t => t.x === x && t.y === y)) return false;
    const other = this.unitAt(x, y);
    if (other && (other.team !== "P" || other.npc)) return false;
    if (other) { other.x = u.x; other.y = u.y; }
    u.x = x; u.y = y;
    for (const v of this.units) v.facing = this.faceNearestFoe(v);
    return true;
  }

  /* A copy of everything the rules can change, taken at the start of a player
     turn so Story mode can rewind the whole turn. Unit objects stay the same
     instances, so the view's references survive a restore. */
  snapshot() {
    return {
      turn: this.turn, over: this.over, activeId: this.active ? this.active.id : -1,
      items: Object.assign({}, this.items),
      pending: this.pending.map(p => Object.assign({}, p)),
      unitCount: this.units.length,
      units: this.units.map(u => Object.assign({}, u, {
        status: Object.assign({}, u.status), cooldowns: Object.assign({}, u.cooldowns),
        abilities: u.abilities.slice(), learned: u.learned.slice(),
      })),
    };
  }
  restore(snap) {
    if (!snap) return false;
    this.units.length = snap.unitCount;     // drop anything summoned since
    snap.units.forEach((data, i) => Object.assign(this.units[i], data, {
      status: Object.assign({}, data.status), cooldowns: Object.assign({}, data.cooldowns),
      abilities: data.abilities.slice(), learned: data.learned.slice(),
    }));
    this.items = Object.assign({}, snap.items);
    this.pending = snap.pending.map(p => Object.assign({}, p));
    this.turn = snap.turn; this.over = snap.over;
    this.active = snap.activeId >= 0 ? this.units[snap.activeId] : null;
    this.events = [];
    this.emit({ type: "rewind" });
    return true;
  }

  add(u) { u.id = this.units.length; this.units.push(u); return u; }
  emit(e) { this.events.push(e); return e; }
  drain() { const e = this.events; this.events = []; return e; }

  living(team) { return this.units.filter(u => u.alive && (!team || u.team === team)); }
  unitAt(x, y) { return this.units.find(u => u.alive && u.x === x && u.y === y) || null; }
  koAt(x, y) { return this.units.find(u => !u.alive && u.x === x && u.y === y) || null; }
  occupied(x, y) { return this.unitAt(x, y); }

  faceNearestFoe(u) {
    const foes = this.living(u.team === "P" ? "E" : "P");
    if (!foes.length) return u.facing;
    foes.sort((a, b) => TC.manhattan(u, a) - TC.manhattan(u, b));
    return TC.facingToward(u, foes[0]);
  }

  /* ------------------------------------------------------- turn engine */
  /* Advance charge time until somebody is ready. Dead units never tick, which
     is what used to make the board look like it was skipping your turn.     */
  tickCT() {
    for (let guard = 0; guard < 10000; guard++) {
      const landing = this.pending.filter(p => p.ct >= 100).sort((a, b) => b.ct - a.ct);
      if (landing.length) { for (const p of landing) this.resolvePending(p); continue; }
      const ready = this.living().filter(u => u.ct >= 100);
      if (ready.length) {
        ready.sort((a, b) => (b.ct - a.ct) || (b.stat("spd") - a.stat("spd")) || (a.id - b.id));
        return ready[0];
      }
      for (const u of this.living()) u.ct += u.stat("spd");
      for (const p of this.pending) p.ct += p.speed;
    }
    return this.living()[0] || null;
  }

  /* A charged spell lands on whatever is there now — not what was there. */
  resolvePending(p) {
    this.pending = this.pending.filter(q => q !== p);
    const caster = this.units[p.casterId];
    if (!caster || !caster.alive) { this.emit({ type: "fizzle", spell: p, unit: caster }); return; }
    const ability = TC.ABILITIES[p.abilityId];
    const tiles = TC.footprint(this.grid, caster, ability, p.tx, p.ty);
    const hits = this.affectedOn(caster, ability, tiles);
    this.emit({ type: "land", unit: caster, ability, tx: p.tx, ty: p.ty, tiles });
    const results = hits.map(t => this.resolveOn(caster, ability, t));
    this.emit({ type: "resolve", unit: caster, ability, tiles, results });
  }

  /* Preview of the next few actors, for the timeline widget. */
  forecast(n) {
    const sim = this.living().map(u => ({ u, ct: u.ct, spd: u.stat("spd") }));
    const spells = this.pending.map(p => ({ p, ct: p.ct }));
    const out = [];
    for (let guard = 0; guard < 4000 && out.length < n; guard++) {
      const landing = spells.filter(s => s.ct >= 100);
      if (landing.length) { for (const s of landing) { out.push({ spell: s.p }); spells.splice(spells.indexOf(s), 1); } continue; }
      const ready = sim.filter(s => s.ct >= 100).sort((a, b) => (b.ct - a.ct) || (b.spd - a.spd));
      if (ready.length) { out.push(ready[0].u); ready[0].ct = CT_AFTER.act; continue; }
      for (const s of sim) s.ct += s.spd;
      for (const s of spells) s.ct += s.p.speed;
    }
    return out.slice(0, n);
  }

  beginTurn() {
    if (this.checkEnd()) return null;
    const u = this.tickCT();
    // A charged spell landing during the tick can decide the battle.
    if (!u || this.checkEnd()) return null;
    this.active = u;
    this.turn++;
    u.ct = 0;
    u.moved = false; u.acted = false;
    u.startX = u.x; u.startY = u.y; u.startFacing = u.facing;

    // Cooldowns and status both tick down on the owner's own turn.
    for (const id in u.cooldowns) if (--u.cooldowns[id] <= 0) delete u.cooldowns[id];

    let skip = false;
    for (const id of Object.keys(u.status)) {
      const def = TC.STATUS[id];
      if (def.hpTickPct) {
        const mag = Math.max(2, Math.round(u.maxHp * Math.abs(def.hpTickPct)));
        if (def.hpTickPct < 0) this.damage(u, mag, { kind: "status", status: id });
        else this.heal(u, mag, { kind: "status", status: id });
      }
      if (def.skip) skip = true;
      if (--u.status[id] <= 0) { delete u.status[id]; this.emit({ type: "statusEnd", unit: u, status: id }); }
    }
    if (!u.alive) { this.emit({ type: "turnSkipped", unit: u, reason: "ko" }); return this.beginTurn(); }
    if (skip) { this.emit({ type: "turnSkipped", unit: u, reason: "stun" }); u.ct = CT_AFTER.wait; return this.beginTurn(); }

    this.emit({ type: "turnStart", unit: u });
    return u;
  }

  endTurn(u) {
    u = u || this.active;
    if (!u) return;
    if (u.passive === "focus" && !u.acted) { u.mp = Math.min(u.maxMp, u.mp + 4); this.emit({ type: "focus", unit: u }); }
    const k = u.moved && u.acted ? "both" : u.acted ? "act" : u.moved ? "move" : "wait";
    u.ct = CT_AFTER[k];
    for (const e of this.units) e.counterReady = true;
    this.emit({ type: "turnEnd", unit: u, ctKind: k });
    this.active = null;
  }

  /* --------------------------------------------------------- movement */
  reachableFor(u) { return TC.reachable(this.grid, u, (x, y) => this.occupied(x, y)); }

  /* Commits a move. The view animates from the returned path. */
  moveUnit(u, tx, ty) {
    const res = this.reachableFor(u);
    const path = TC.pathTo(this.grid, res, u, tx, ty);
    if (!path || !path.length) return null;
    const last = path[path.length - 1];
    const prev = path.length > 1 ? path[path.length - 2] : { x: u.x, y: u.y };
    const from = { x: u.x, y: u.y };
    u.x = last.x; u.y = last.y;
    u.facing = TC.facingToward(prev, last);
    u.moved = true;
    this.emit({ type: "move", unit: u, from, path });
    const haz = this.grid.hazard(u.x, u.y);
    if (haz) this.damage(u, haz, { kind: "hazard" });
    return path;
  }

  /* Undo is only offered before acting, so restoring the snapshot is safe. */
  undoMove(u) {
    if (!u.moved || u.acted) return false;
    u.x = u.startX; u.y = u.startY; u.facing = u.startFacing;
    u.moved = false;
    this.emit({ type: "undoMove", unit: u });
    return true;
  }

  /* ------------------------------------------------------------ combat */
  hitChance(att, def, ability) {
    if (ability.type === "heal" || ability.type === "buff" || ability.type === "revive") return 100;
    const side = TC.relativeSide(def, att);
    const sideBonus = side === "back" ? 20 : side === "side" ? 10 : 0;
    const dh = this.grid.height(att.x, att.y) - this.grid.height(def.x, def.y);
    const heightBonus = TC.clamp(dh * 8, -16, 16);
    const evasion = (def.stat("eva") + this.grid.eva(def.x, def.y)) * 0.6;
    const magicBonus = ability.type === "mag" || ability.type === "drain" ? 5 : 0;
    return Math.round(TC.clamp(BASE_ACC + sideBonus + heightBonus + magicBonus - evasion, 15, 99));
  }

  /* Expected damage before the roll — used for the attack preview and the AI. */
  estimateDamage(att, def, ability) {
    const magical = ability.type === "mag" || ability.type === "drain";
    const power = ability.power || 1;
    const atk = magical ? att.stat("mag") : att.stat("atk");
    let mitig = magical ? def.stat("res") : def.stat("def") + this.grid.def(def.x, def.y);
    if (ability.pierce) mitig *= (1 - ability.pierce);
    let dmg = atk * power * (magical ? MAG_K : PHYS_K) - mitig * 0.9;

    const side = TC.relativeSide(def, att);
    dmg *= side === "back" ? 1.5 : side === "side" ? 1.25 : 1;
    const dh = this.grid.height(att.x, att.y) - this.grid.height(def.x, def.y);
    if (dh > 0) dmg *= 1 + Math.min(0.2, dh * 0.1);
    if (att.passive === "highGround" && dh > 0) dmg *= 1.25;
    if (att.passive === "pack") {
      const pals = TC.DIRS.filter(([dx, dy]) => {
        const n = this.unitAt(att.x + dx, att.y + dy);
        return n && n.team === att.team && n.job === att.job;
      }).length;
      dmg *= 1 + 0.2 * pals;
    }
    if (def.passive === "tough") dmg *= 0.85;
    return Math.max(1, Math.round(dmg));
  }

  critChance(att, def) {
    return 8 + (TC.relativeSide(def, att) === "back" ? 8 : 0);
  }

  damage(u, amount, meta) {
    amount = Math.max(0, Math.round(amount));
    u.hp = Math.max(0, u.hp - amount);
    this.emit(Object.assign({ type: "damage", unit: u, amount }, meta || {}));
    if (!u.alive) {
      this.emit({ type: "ko", unit: u });
      if (meta && meta.source) meta.source.gainXp(30 + 5 * u.level, this);
    }
    return amount;
  }

  heal(u, amount, meta) {
    amount = Math.max(0, Math.min(u.maxHp - u.hp, Math.round(amount)));
    u.hp += amount;
    this.emit(Object.assign({ type: "heal", unit: u, amount }, meta || {}));
    return amount;
  }

  /* Which units an ability actually lands on, given an aim point. */
  affected(actor, ability, tx, ty) {
    const tiles = TC.footprint(this.grid, actor, ability, tx, ty);
    return { tiles, hits: this.affectedOn(actor, ability, tiles) };
  }
  affectedOn(actor, ability, tiles) {
    const hits = [];
    for (const t of tiles) {
      const u = ability.target === "ko" || ability.type === "revive" ? this.koAt(t.x, t.y) : this.unitAt(t.x, t.y);
      if (!u) continue;
      if (ability.healOnly && u.team !== actor.team) continue;
      if (ability.target === "enemy" && u.team === actor.team) continue;
      if (ability.target === "ally" && u.team !== actor.team) continue;
      hits.push(u);
    }
    return hits;
  }

  /* Is `tile` a legal aim point for this ability from where the actor stands? */
  validTarget(actor, ability, tx, ty) {
    if (ability.selfCentered) return tx === actor.x && ty === actor.y;
    const inRange = TC.tilesInRange(this.grid, actor.x, actor.y, ability)
      .some(t => t.x === tx && t.y === ty);
    if (!inRange) return false;
    if (ability.noAdjacent && this.living(actor.team === "P" ? "E" : "P")
      .some(e => TC.manhattan(actor, e) <= 1)) return false;
    if (ability.type === "summon") {
      // Hard cap on the horde: without it the Necromancer can stall forever.
      const live = this.living(actor.team).filter(u => u.job === ability.summon).length;
      if (live >= (ability.cap || 3)) return false;
      return !this.unitAt(tx, ty) && this.grid.walkable(tx, ty) && !this.koAt(tx, ty);
    }
    const { hits } = this.affected(actor, ability, tx, ty);
    if (ability.target === "empty") return true;      // splash may legitimately miss
    return hits.length > 0;
  }

  /* The one entry point for "do a thing". Returns a report for the log/UI. */
  useAbility(actor, ability, tx, ty) {
    if (!this.validTarget(actor, ability, tx, ty)) return null;
    actor.mp = Math.max(0, actor.mp - (ability.mp || 0));
    if (ability.cd) actor.cooldowns[ability.id] = ability.cd;
    actor.facing = (tx !== actor.x || ty !== actor.y) ? TC.facingToward(actor, { x: tx, y: ty }) : actor.facing;
    actor.acted = true;
    this.emit({ type: "cast", unit: actor, ability, tx, ty });

    if (ability.type === "summon") {
      const u = this.add(new Unit(ability.summon + " " + (this.units.length), ability.summon, actor.team, tx, ty, actor.level));
      u.ct = 40;
      this.emit({ type: "summon", unit: u, by: actor });
      return { results: [{ unit: u, summoned: true }] };
    }

    if (ability.charge) {
      const spell = { id: this.nextSpellId = (this.nextSpellId || 0) + 1, casterId: actor.id, abilityId: ability.id,
                      tx, ty, ct: 0, speed: ability.charge };
      this.pending.push(spell);
      this.emit({ type: "charge", unit: actor, ability, tx, ty, spell,
                  tiles: TC.footprint(this.grid, actor, ability, tx, ty) });
      return { results: [], charging: true };
    }

    const { tiles, hits } = this.affected(actor, ability, tx, ty);
    const results = [];
    for (const target of hits) {
      const r = this.resolveOn(actor, ability, target);
      results.push(r);
    }
    this.emit({ type: "resolve", unit: actor, ability, tiles, results });
    return { results, tiles };
  }

  resolveOn(actor, ability, target) {
    const out = { unit: target };
    if (ability.type === "heal") {
      const amount = Math.round(actor.stat("mag") * (ability.power || 1) * 1.6);
      out.healed = this.heal(target, amount, { source: actor, ability });
      actor.gainXp(Math.round(out.healed * (actor.passive === "faith" ? 0.5 : 0.2)), this);
      return out;
    }
    if (ability.type === "revive") {
      target.hp = Math.max(1, Math.round(target.maxHp * (ability.power || 0.35)));
      target.ct = 0; target.status = {};
      this.emit({ type: "revive", unit: target, by: actor });
      actor.gainXp(40, this);
      out.revived = true;
      return out;
    }
    if (ability.type === "buff") {
      if (ability.status) {
        target.addStatus(ability.status.id, ability.status.turns);
        this.emit({ type: "status", unit: target, status: ability.status.id, turns: ability.status.turns });
      }
      out.buffed = true;
      actor.gainXp(12, this);
      return out;
    }

    // Offensive path: roll to hit, then damage.
    const acc = this.hitChance(actor, target, ability);
    if (!TC.chance(acc)) {
      this.emit({ type: "miss", unit: target, by: actor, ability });
      out.miss = true;
      return out;
    }
    const crit = TC.chance(this.critChance(actor, target));
    const variance = 0.9 + Math.random() * 0.2;
    let dmg = this.estimateDamage(actor, target, ability) * variance * (crit ? CRIT_MULT : 1);

    // Shield Bash shoves; if there is nowhere to shove, it hurts more instead.
    if (ability.knockback) {
      const dir = TC.DIRS[TC.facingToward(actor, target)];
      const nx = target.x + dir[0], ny = target.y + dir[1];
      const canShove = this.grid.walkable(nx, ny) && !this.unitAt(nx, ny) &&
        Math.abs(this.grid.height(nx, ny) - this.grid.height(target.x, target.y)) <= 2;
      if (canShove) {
        const from = { x: target.x, y: target.y };
        target.x = nx; target.y = ny;
        this.emit({ type: "knockback", unit: target, from, to: { x: nx, y: ny } });
        const haz = this.grid.hazard(nx, ny);
        if (haz) this.damage(target, haz, { kind: "hazard" });
      } else dmg *= 1.25;
    }

    out.crit = crit;
    out.side = TC.relativeSide(target, actor);
    out.damage = this.damage(target, dmg, { source: actor, ability, crit, side: out.side });
    actor.gainXp(Math.round(out.damage * 0.5), this);

    if (ability.type === "drain" && actor.alive) {
      out.drained = this.heal(actor, out.damage * 0.5, { source: actor, kind: "drain" });
    }
    if (ability.status && target.alive && TC.chance(ability.status.chance)) {
      if (target.addStatus(ability.status.id, ability.status.turns))
        this.emit({ type: "status", unit: target, status: ability.status.id, turns: ability.status.turns });
    }

    // Counterattack: melee only, never against a back-strike, once per round.
    if (target.alive && target.passive === "counter" && target.counterReady &&
        ability.type === "phys" && TC.manhattan(actor, target) <= 1 && out.side !== "back") {
      target.counterReady = false;
      const counter = Math.round(this.estimateDamage(target, actor, { type: "phys", power: 0.7 }));
      this.emit({ type: "counter", unit: target, at: actor });
      out.counter = this.damage(actor, counter, { source: target, kind: "counter" });
    }
    return out;
  }

  useItem(actor, itemId, tx, ty) {
    if (!this.items[itemId]) return null;
    const item = TC.ITEMS[itemId];
    const target = item.target === "ko" ? this.koAt(tx, ty) : this.unitAt(tx, ty);
    if (!target) return null;
    if (item.target === "ally" && target.team !== actor.team) return null;
    if (TC.manhattan(actor, { x: tx, y: ty }) > item.range) return null;

    this.items[itemId]--;
    actor.acted = true;
    const out = { unit: target, item };
    if (item.revive) {
      if (target.alive) { this.items[itemId]++; actor.acted = false; return null; }
      target.hp = Math.max(1, Math.round(target.maxHp * item.revive));
      target.ct = 0; target.status = {};
      this.emit({ type: "revive", unit: target, by: actor });
      out.revived = true;
    }
    if (item.hp) out.healed = this.heal(target, item.hp, { source: actor, kind: "item" });
    if (item.mp) { const before = target.mp; target.mp = Math.min(target.maxMp, target.mp + item.mp); out.mp = target.mp - before; }
    if (item.cleanse) out.cleansed = target.clearBadStatus();
    this.emit({ type: "item", unit: actor, target, item, out });
    return out;
  }

  /* ------------------------------------------------------------ result */
  checkEnd() {
    if (this.over) return true;
    const players = this.living("P").filter(u => !u.npc).length;
    const enemies = this.living("E");
    if (!players) { this.over = "defeat"; this.emit({ type: "end", result: "defeat" }); return true; }
    if (this.chapter.objective === "protect" && this.units.some(u => u.npc && !u.alive)) {
      this.over = "defeat"; this.emit({ type: "end", result: "defeat", reason: "npc" }); return true;
    }
    if (this.chapter.objective === "boss") {
      if (!enemies.some(e => e.passive === "boss")) { this.over = "victory"; this.emit({ type: "end", result: "victory" }); return true; }
      return false;
    }
    if (!enemies.length) { this.over = "victory"; this.emit({ type: "end", result: "victory" }); return true; }
    return false;
  }
}
TC.Battle = Battle;
TC.CT_AFTER = CT_AFTER;
