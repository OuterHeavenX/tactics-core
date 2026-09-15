"use strict";
/* ============================================================================
   TACTICS CORE — ENEMY AI
   Scores every (where I could stand) x (what I could do) x (where I aim it)
   combination and takes the best one. That is enough to make enemies flank,
   climb for height, avoid lava, refuse to clump for your Fire, and retreat
   when they are nearly dead.
   ========================================================================== */
var TC = window.TC || (window.TC = {});   /* var, not const: these are classic scripts sharing one global scope */

const W = {
  damage:      1.0,
  kill:        45,
  overkill:   -0.35,   // damping so it stops valuing damage past lethal
  allyHit:    -2.2,    // friendly fire is heavily discouraged, not forbidden
  heal:        1.1,
  buff:        16,
  revive:     110,
  summon:      36,
  status:      14,
  height:      2.5,
  cover:       0.35,
  hazard:     -45,
  exposure:   -1.5,    // being reachable by many player units
  approach:   -1.6,    // per tile of distance to the nearest target
  backstab:    8,
  selfPreserve: 30,
};

/* How many living player units could reach and strike this tile next turn. */
function exposure(battle, tile, self) {
  let n = 0;
  for (const p of battle.living(self.team === "P" ? "E" : "P")) {
    const reach = p.stat("move") + Math.max(p.range, 1);
    if (TC.manhattan(p, tile) <= reach) n++;
  }
  return n;
}

/* Long battles get progressively pushier so two cautious sides cannot stare at
   each other across a river forever. */
function aggression(battle) { return Math.min(5, 1 + battle.turn / 35); }

/* Steps to the nearest foe, walking the map rather than flying over it. */
function approachCost(battle, field, tile, nearestFoe) {
  const d = field ? field[tile.y * battle.grid.cols + tile.x] : -1;
  if (d >= 0) return d;
  // Unreachable on foot: fall back to straight-line, heavily penalised.
  return nearestFoe ? TC.manhattan(tile, nearestFoe) * 3 + 20 : 0;
}

function tileScore(battle, unit, tile, nearestFoe, field) {
  const g = battle.grid;
  const aggro = aggression(battle);
  let s = 0;
  s += g.height(tile.x, tile.y) * W.height;
  s += (g.eva(tile.x, tile.y) + g.def(tile.x, tile.y) * 4) * W.cover;
  if (g.hazard(tile.x, tile.y)) s += W.hazard;
  s += exposure(battle, tile, unit) * (W.exposure / aggro);
  const reach = approachCost(battle, field, tile, nearestFoe);
  s += reach * W.approach * aggro;
  // Hurt units want to be further away; healthy ones want to be in your face.
  const hpFrac = unit.hp / unit.maxHp;
  if (hpFrac < 0.3) s -= reach * W.approach * 1.8 / aggro;
  return s;
}

/* Value of firing `ability` from (fx,fy) at (tx,ty). */
function actionScore(battle, unit, from, ability, tx, ty) {
  const saved = { x: unit.x, y: unit.y, facing: unit.facing };
  unit.x = from.x; unit.y = from.y;
  unit.facing = TC.facingToward(from, { x: tx, y: ty });
  let s = 0;
  try {
    if (!battle.validTarget(unit, ability, tx, ty)) return -Infinity;

    if (ability.type === "summon") {
      const pals = battle.living(unit.team).length;
      return W.summon + Math.max(0, 5 - pals) * 12;
    }

    const { hits } = battle.affected(unit, ability, tx, ty);
    if (!hits.length && ability.type !== "buff") return -Infinity;

    for (const target of hits) {
      const friendly = target.team === unit.team;
      if (ability.type === "heal") {
        if (!friendly) continue;
        const missing = target.maxHp - target.hp;
        if (missing <= 0) continue;
        const amount = Math.min(missing, Math.round(unit.stat("mag") * (ability.power || 1) * 1.6));
        s += amount * W.heal * (target.hp / target.maxHp < 0.35 ? 2 : 1);
      } else if (ability.type === "buff") {
        if (!friendly) continue;
        if (ability.status && target.has(ability.status.id)) continue;
        s += W.buff;
      } else if (ability.type === "revive") {
        s += W.revive;
      } else {
        const acc = battle.hitChance(unit, target, ability) / 100;
        const dmg = battle.estimateDamage(unit, target, ability);
        let v = Math.min(dmg, target.hp) * W.damage * acc;
        if (dmg > target.hp) v += (dmg - target.hp) * W.overkill;
        if (dmg >= target.hp) v += W.kill * acc;
        if (ability.status && !target.has(ability.status.id)) v += W.status * (ability.status.chance / 100);
        if (TC.relativeSide(target, unit) === "back") v += W.backstab;
        s += friendly ? v * W.allyHit : v;
      }
    }
    // Spend MP on the cheapest thing that gets the job done.
    s -= (ability.mp || 0) * 0.35;
  } finally {
    unit.x = saved.x; unit.y = saved.y; unit.facing = saved.facing;
  }
  return s;
}

/* Returns a plan: { move:{x,y}|null, ability, tx, ty } — or just a move. */
TC.planTurn = function (battle, unit) {
  const foes = battle.living(unit.team === "P" ? "E" : "P");
  if (!foes.length) return { move: null, ability: null };
  const byDist = foes.slice().sort((a, b) => TC.manhattan(unit, a) - TC.manhattan(unit, b));
  const nearest = byDist[0];

  const field = TC.distanceField(battle.grid, foes, unit.stat("jump"));
  const res = battle.reachableFor(unit);
  const stands = [{ x: unit.x, y: unit.y, d: 0, stay: true }].concat(res.tiles);
  const abilities = unit.usableAbilities();

  // Panic heal: a nearly-dead unit that can retreat out of reach usually should.
  const desperate = unit.hp / unit.maxHp < 0.28 && battle.turn < 80;

  let best = null;
  for (const tile of stands) {
    const base = tileScore(battle, unit, tile, nearest, field) + (desperate ? W.selfPreserve * (exposure(battle, tile, unit) === 0 ? 1 : 0) : 0);
    // Option A: stand here and do nothing (pure repositioning).
    if (!best || base > best.score) best = { score: base, move: tile.stay ? null : tile, ability: null };

    for (const ability of abilities) {
      const aim = ability.selfCentered
        ? [{ x: tile.x, y: tile.y }]
        : TC.tilesInRange(battle.grid, tile.x, tile.y, ability);
      for (const t of aim) {
        const v = actionScore(battle, unit, tile, ability, t.x, t.y);
        if (v === -Infinity) continue;
        const total = base + v;
        if (!best || total > best.score) best = { score: total, move: tile.stay ? null : tile, ability, tx: t.x, ty: t.y };
      }
    }
  }
  return best || { move: null, ability: null };
};

/* Drive one enemy turn. `step(fn, delay)` lets the caller pace the animation. */
TC.runEnemyTurn = function (battle, unit, step, done) {
  const plan = TC.planTurn(battle, unit);
  const act = () => {
    if (plan.ability && battle.validTarget(unit, plan.ability, plan.tx, plan.ty)) {
      battle.useAbility(unit, plan.ability, plan.tx, plan.ty);
    } else {
      // Nothing worth doing from here — at least look at the enemy.
      unit.facing = battle.faceNearestFoe(unit);
    }
    step(() => done(), 420);
  };
  if (plan.move) {
    battle.moveUnit(unit, plan.move.x, plan.move.y);
    step(act, 260);
  } else act();
};
