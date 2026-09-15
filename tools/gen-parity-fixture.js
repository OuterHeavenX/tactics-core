#!/usr/bin/env node
/* Builds a deterministic snapshot of the JavaScript rules engine's answers and
   writes it to godot/tests/parity_fixture.json. godot/tests/ParityTest.gd
   replays the same states through the GDScript engine and diffs the numbers,
   so the two implementations cannot silently drift apart.               */
"use strict";
global.window = {};
for (const f of ["data", "core", "battle", "ai"]) require(`../js/${f}.js`);
const TC = global.window.TC;
const fs = require("fs"), path = require("path");

/* A fixed board: no RNG anywhere below this line. */
function scenario(chapterId) {
  const ch = TC.CAMPAIGN.find(c => c.id === chapterId);
  const battle = new TC.Battle(ch, TC.PARTY.map(p => ({ ...p, level: 5 })));
  battle.units.forEach((u, i) => {
    u.ct = (i * 13) % 100;               // deterministic charge times
    u.hp = Math.max(1, Math.round(u.maxHp * (0.5 + ((i * 7) % 5) / 10)));
    u.mp = u.maxMp;
    u.facing = i % 4;
  });
  return battle;
}

const out = { chapters: {} };
for (const chapterId of ["ch1", "ch3", "ch4"]) {
  const b = scenario(chapterId);
  const rec = { units: [], combat: [], reach: [], field: [], plans: [], forecast: [] };

  for (const u of b.units) {
    rec.units.push({
      name: u.name, job: u.job, team: u.team, x: u.x, y: u.y, facing: u.facing,
      level: u.level, hp: u.hp, maxHp: u.maxHp, mp: u.mp, maxMp: u.maxMp,
      atk: u.stat("atk"), def: u.stat("def"), mag: u.stat("mag"), res: u.stat("res"),
      spd: u.stat("spd"), move: u.stat("move"), jump: u.stat("jump"), ct: u.ct,
    });
  }

  // Every attacker x every reachable defender x every ability the attacker has.
  for (const a of b.units) {
    for (const d of b.units) {
      if (a === d || a.team === d.team) continue;
      for (const id of a.abilities) {
        const ab = TC.ABILITIES[id];
        if (ab.type === "summon") continue;
        rec.combat.push({
          att: a.name, def: d.name, ability: id,
          acc: b.hitChance(a, d, ab),
          dmg: b.estimateDamage(a, d, ab),
          crit: b.critChance(a, d),
          side: TC.relativeSide(d, a),
          valid: b.validTarget(a, ab, d.x, d.y),
        });
      }
    }
  }

  for (const u of b.units) {
    const r = b.reachableFor(u);
    rec.reach.push({ name: u.name, tiles: r.tiles.length,
      sum: r.tiles.reduce((s, t) => s + t.x * 31 + t.y * 17, 0) });
    const foes = b.living(u.team === "P" ? "E" : "P");
    const fld = TC.distanceField(b.grid, foes, u.stat("jump"));
    let sum = 0, reachable = 0;
    for (let i = 0; i < fld.length; i++) if (fld[i] >= 0) { sum += fld[i]; reachable++; }
    rec.field.push({ name: u.name, reachable, sum });
  }

  // plan_turn has no randomness, so both engines must pick the same action.
  for (const u of b.units) {
    const p = TC.planTurn(b, u);
    rec.plans.push({
      name: u.name,
      move: p.move ? `${p.move.x},${p.move.y}` : null,
      ability: p.ability ? p.ability.id : null,
      target: p.ability ? `${p.tx},${p.ty}` : null,
      score: Math.round(p.score * 1000) / 1000,
    });
  }

  rec.forecast = b.forecast(8).map(u => u.name);
  out.chapters[chapterId] = rec;
}

const dest = path.join(__dirname, "..", "godot", "tests", "parity_fixture.json");
fs.mkdirSync(path.dirname(dest), { recursive: true });
fs.writeFileSync(dest, JSON.stringify(out, null, 1));
const n = Object.values(out.chapters).reduce((s, c) => s + c.combat.length + c.plans.length + c.reach.length, 0);
console.log(`Wrote ${path.relative(process.cwd(), dest)} — ${n} recorded answers across ${Object.keys(out.chapters).length} chapters.`);
