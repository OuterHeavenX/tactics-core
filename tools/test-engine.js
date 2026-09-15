#!/usr/bin/env node
/* Headless tests for the JavaScript rules engine — the same invariants
   godot/tests/HeadlessTest.gd checks on the GDScript side, plus an AI-vs-AI
   balance sweep over every chapter.

   Usage: node tools/test-engine.js [--runs N]                                */
"use strict";
global.window = {};
for (const f of ["data", "core", "battle", "ai"]) require(`../js/${f}.js`);
const TC = global.window.TC;

let failures = 0, checks = 0;
const check = (label, ok, extra) => {
  checks++;
  if (ok) console.log(`  [ok] ${label}${extra ? "  " + extra : ""}`);
  else { failures++; console.error(`  [FAIL] ${label}  ${extra || ""}`); }
};
const RUNS = (() => { const i = process.argv.indexOf("--runs"); return i > 0 ? parseInt(process.argv[i + 1], 10) : 40; })();

console.log("Tactics Core — engine tests\n");

/* ------------------------------------------------------------------ iso -- */
console.log("Isometric projection");
{
  const cols = 12, rows = 10;
  let roundTrip = true, inBounds = true;
  for (let rot = 0; rot < 4; rot++) {
    const vd = TC.viewDims(cols, rows, rot);
    for (let y = 0; y < rows; y++) for (let x = 0; x < cols; x++) {
      const r = TC.rotate(x, y, cols, rows, rot);
      if (r.x < 0 || r.y < 0 || r.x >= vd.cols || r.y >= vd.rows) inBounds = false;
      const u = TC.unrotate(r.x, r.y, cols, rows, rot);
      if (u.x !== x || u.y !== y) roundTrip = false;
    }
  }
  check("rotate/unrotate round-trips at all 4 angles", roundTrip);
  check("rotation stays inside the view grid", inBounds);
  const p = TC.project(0, 0, 0, cols, rows, 0);
  check("origin projects to (0,0)", p.sx === 0 && p.sy === 0);
  const lifted = TC.project(3, 3, 2, cols, rows, 0), flat = TC.project(3, 3, 0, cols, rows, 0);
  check("height raises the tile on screen", lifted.sy === flat.sy - 2 * TC.HS);
  check("back attack detected", TC.relativeSide({ x: 5, y: 5, facing: 3 }, { x: 5, y: 6 }) === "back");
  check("front attack detected", TC.relativeSide({ x: 5, y: 5, facing: 3 }, { x: 5, y: 4 }) === "front");
  check("side attack detected", TC.relativeSide({ x: 5, y: 5, facing: 3 }, { x: 6, y: 5 }) === "side");
}

/* ------------------------------------------------------- grid & movement -- */
console.log("Grid and pathfinding");
{
  const g = new TC.Grid(TC.MAPS.ziggurat);
  check("grid size", g.cols === 12 && g.rows === 10);
  check("water is impassable", !new TC.Grid(TC.MAPS.sluice).walkable(0, 3));
  check("lava is walkable but hurts", g.walkable(4, 4) && g.hazard(4, 4) > 0);

  const climber = { x: 5, y: 9, team: "P", stat: k => ({ move: 4, jump: 3 })[k] };
  const res = TC.reachable(g, climber, () => null);
  check("reachable returns tiles", res.tiles.length > 5, `${res.tiles.length} tiles`);
  let legal = true, contiguous = true;
  for (const t of res.tiles) {
    const path = TC.pathTo(g, res, climber, t.x, t.y);
    let prev = { x: climber.x, y: climber.y };
    for (const step of path) {
      if (TC.manhattan(prev, step) !== 1) contiguous = false;
      if (Math.abs(g.height(step.x, step.y) - g.height(prev.x, prev.y)) > climber.stat("jump")) legal = false;
      prev = step;
    }
  }
  check("every path step is adjacent", contiguous);
  check("jump limits every step of every path", legal);

  // Travel cost must charge extra for lava, or the AI treats it as a shortcut.
  const foes = [{ x: 6, y: 2 }];
  const field = TC.distanceField(g, foes, 3);
  const viaLava = field[6 * g.cols + 6];
  check("hazard tiles cost extra to cross", viaLava > TC.manhattan({ x: 6, y: 6 }, foes[0]),
    `cost ${viaLava} vs manhattan ${TC.manhattan({ x: 6, y: 6 }, foes[0])}`);
}

/* --------------------------------------------------------------- combat -- */
console.log("Combat rules");
{
  const b = new TC.Battle(TC.CAMPAIGN[0], TC.PARTY.map(p => ({ ...p, level: 1 })));
  check("both squads deployed", b.units.length === 10);
  const seen = new Set();
  check("no two units share a tile", b.units.every(u => { const k = u.x + "," + u.y; if (seen.has(k)) return false; seen.add(k); return true; }));

  const knight = b.units[0], goblin = b.living("E")[0];
  knight.x = goblin.x + 1; knight.y = goblin.y;
  goblin.facing = 0;
  const front = b.estimateDamage(knight, goblin, TC.ABILITIES.attack);
  const frontAcc = b.hitChance(knight, goblin, TC.ABILITIES.attack);
  goblin.facing = 1;
  const back = b.estimateDamage(knight, goblin, TC.ABILITIES.attack);
  const backAcc = b.hitChance(knight, goblin, TC.ABILITIES.attack);
  check("back attacks hit harder", back > front, `${back} vs ${front}`);
  check("back attacks hit more often", backAcc > frontAcc, `${backAcc}% vs ${frontAcc}%`);

  const spd = goblin.stat("spd");
  goblin.addStatus("slow", 3);
  check("slow reduces speed", goblin.stat("spd") < spd);
  goblin.status = {};

  const boss = new TC.Unit("Vetrix", "Necromancer", "E", 0, 0, 5);
  check("bosses ignore stun", boss.addStatus("stun", 1) === false);
  check("bosses still take poison", boss.addStatus("poison", 3) === true);

  const u = b.beginTurn();
  u.moved = true; u.acted = true; b.endTurn(u);
  const ctBoth = u.ct;
  u.moved = false; u.acted = false; b.endTurn(u);
  check("waiting leaves more CT than move+act", u.ct > ctBoth, `${u.ct} vs ${ctBoth}`);

  const priest = b.units[4];
  priest.hp = priest.maxHp - 3;
  check("healing caps at max HP", b.heal(priest, 999) === 3 && priest.hp === priest.maxHp);
  check("damage floors at zero HP", b.damage(priest, 99999) > 0 && priest.hp === 0);
  check("the fallen leave the living list", !b.living().includes(priest));

  let pickedDead = false;
  for (let i = 0; i < 30; i++) {
    const n = b.beginTurn();
    if (!n) break;
    if (!n.alive) pickedDead = true;
    b.endTurn(n);
  }
  check("turn engine never wakes the fallen", !pickedDead);

  const finale = TC.CAMPAIGN.find(c => c.map === "necrohol");
  const nb = new TC.Battle(finale, TC.PARTY.map(p => ({ ...p, level: 9 })));
  const necro = nb.living("E").find(e => e.job === "Necromancer");
  check("boss present in the finale", !!necro);
  const summon = TC.ABILITIES.summonBone;
  for (let i = 0; i < 12; i++) {
    necro.mp = necro.maxMp; necro.cooldowns = {};
    const spot = TC.tilesInRange(nb.grid, necro.x, necro.y, summon).find(t => nb.validTarget(necro, summon, t.x, t.y));
    if (spot) nb.useAbility(necro, summon, spot.x, spot.y);
  }
  const bones = nb.living("E").filter(e => e.job === "Skeleton").length;
  check("summons are capped", bones <= 7, `${bones} skeletons after 12 attempts`);
}

/* ---------------------------------------------------- charge, cone, rewind -- */
console.log("Cast-time spells, cones, rewind, learning");
{
  const b = new TC.Battle(TC.CAMPAIGN[0], TC.PARTY.map(p => ({ ...p, level: 3 })));
  const mage = b.units.find(u => u.job === "Mage"), gob = b.living("E")[0];
  mage.x = gob.x - 2; mage.y = gob.y;
  const hp = gob.hp;
  const r = b.useAbility(mage, TC.ABILITIES.fire, gob.x, gob.y);
  check("a charged spell does not resolve on cast", !!r.charging && gob.hp === hp && b.pending.length === 1);
  check("the timeline shows the pending spell", b.forecast(8).some(e => e.spell));
  gob.x += 3;                                             // walk out of it
  for (const u of b.units) u.ct = 0;
  let guard = 0; while (b.pending.length && guard++ < 30) { b.beginTurn(); b.endTurn(b.active); }
  check("a dodged spell lands on empty ground", gob.hp === hp && b.pending.length === 0);

  const roost = TC.CAMPAIGN.find(c => c.map === "roost");
  const rb = new TC.Battle(roost, TC.PARTY.map(p => ({ ...p, level: 8 })));
  const dragon = rb.living("E").find(u => u.job === "Dragon");
  const cone = TC.coneTiles(rb.grid, dragon.x, dragon.y, dragon.x, dragon.y + 1, 3);
  check("breath cone is 1+3+3 tiles deep", cone.length === 7, JSON.stringify(cone.map(t => t.x + "," + t.y)));
  check("cone never includes the caster", !cone.some(t => t.x === dragon.x && t.y === dragon.y));

  const s = new TC.Battle(TC.CAMPAIGN[0], TC.PARTY.map(p => ({ ...p, level: 1 })));
  const u = s.beginTurn(); const snap = s.snapshot();
  const victim = s.units[5], before = victim.hp; victim.hp = 1; u.x = 9; u.acted = true;
  s.restore(snap);
  check("rewind restores HP, position and flags", victim.hp === before && u.x !== 9 && !u.acted);

  const k = s.units[0]; k.jp = 500;
  check("learnable lists unknown JP abilities", k.learnable().includes("rally") && !k.abilities.includes("rally"));
  check("learning spends JP and adds the ability", k.learn("rally") && k.jp === 350 && k.abilities.includes("rally"));
  check("cannot learn twice or without JP", !k.learn("rally") && !s.units[1].learn("judgment"));

  // Rewinding twice in one turn must not leak the first rewind's state.
  const snap2 = s.snapshot();
  s.units[5].addStatus("protect", 3); s.restore(snap2);
  s.units[5].addStatus("protect", 3); s.restore(snap2);
  check("a second rewind still restores a clean state", !s.units[5].has("protect"));

  // A charged spell that kills the last enemy must end the battle at once.
  const last = new TC.Battle(TC.CAMPAIGN[0], TC.PARTY.map(p => ({ ...p, level: 9 })));
  const foes = last.living("E"); const keep = foes[0];
  for (const f of foes) if (f !== keep) f.hp = 0;
  const caster = last.units.find(u => u.job === "Mage");
  caster.x = keep.x - 2; caster.y = keep.y; keep.hp = 1;
  last.useAbility(caster, TC.ABILITIES.fire, keep.x, keep.y);
  for (const u of last.units) u.ct = 0;
  const next = last.beginTurn();
  check("a spell that lands the killing blow ends the battle immediately", next === null && last.over === "victory",
    `next=${next && next.name} over=${last.over}`);
  check("deploy zone is a walkable superset of the slots", s.deployZone().length >= TC.PARTY.length &&
    s.deployZone().every(t => s.grid.walkable(t.x, t.y)));

  const pb = new TC.Battle(TC.CAMPAIGN.find(c => c.objective === "protect"), TC.PARTY.map(p => ({ ...p, level: 5 })));
  const npc = pb.units.find(x => x.npc);
  check("protect chapter fields an npc on the player side", !!npc && npc.team === "P" && npc.abilities.length === 0);
  npc.hp = 0;
  check("losing the npc loses the battle", pb.checkEnd() && pb.over === "defeat");
}

/* -------------------------------------------------------------- balance -- */
console.log(`Campaign balance (AI vs AI, ${RUNS} runs each)`);
for (let ci = 0; ci < TC.CAMPAIGN.length; ci++) {
  const ch = TC.CAMPAIGN[ci];
  let wins = 0, losses = 0, stalls = 0, turns = 0;
  for (let i = 0; i < RUNS; i++) {
    // The party is assumed to arrive at roughly the enemies' level.
    const b = new TC.Battle(ch, TC.PARTY.map(p => ({ ...p, level: ch.enemyLevel || 1 + ci * 2 })));
    let guard = 0;
    while (!b.checkEnd() && guard++ < 400) {
      const u = b.beginTurn();
      if (!u) break;
      const plan = TC.planTurn(b, u);
      if (plan.move) b.moveUnit(u, plan.move.x, plan.move.y);
      if (plan.ability) b.useAbility(u, plan.ability, plan.tx, plan.ty);
      b.endTurn(u);
      b.drain();
    }
    turns += guard;
    if (b.over === "victory") wins++; else if (b.over === "defeat") losses++; else stalls++;
  }
  const detail = `wins ${wins} losses ${losses} stalls ${stalls} avg turns ${Math.round(turns / RUNS)}`;
  check(`${ch.id} always reaches a result`, stalls === 0, detail);
  check(`${ch.id} is winnable but not free`, wins >= Math.max(1, Math.round(RUNS * 0.15)) && wins <= RUNS, detail);
}

console.log(`\n${checks} checks, ${failures} failure(s)`);
process.exit(failures ? 1 : 0);
