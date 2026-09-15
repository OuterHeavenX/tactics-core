#!/usr/bin/env node
/* Sanity-checks js/data.js: map rectangularity, spawn legality, ability refs.
   Run with `node tools/validate-data.js` (also runs in CI).                  */
"use strict";
global.window = {};
require("../js/data.js");
const TC = global.window.TC;
let errors = 0;
const bad = (...m) => { errors++; console.error("  ✗", ...m); };

console.log("Maps");
for (const [key, m] of Object.entries(TC.MAPS)) {
  const w = m.t[0].length, h = m.t.length;
  m.t.forEach((r, i) => r.length !== w && bad(`${key}: terrain row ${i} is ${r.length}, expected ${w}`));
  m.h.forEach((r, i) => r.length !== w && bad(`${key}: height row ${i} is ${r.length}, expected ${w}`));
  if (m.h.length !== h) bad(`${key}: ${m.h.length} height rows vs ${h} terrain rows`);
  m.t.forEach((r, y) => [...r].forEach((c, x) => {
    if (!TC.TERRAIN[c]) bad(`${key}: unknown terrain '${c}' at ${x},${y}`);
  }));
  console.log(`  ✓ ${key} ${w}x${h} (${m.name})`);
}

console.log("Jobs");
for (const [name, j] of Object.entries(TC.JOBS)) {
  for (const a of j.abilities) if (!TC.ABILITIES[a]) bad(`${name}: unknown ability '${a}'`);
  for (const k of ["hp","mp","atk","def","mag","res","spd","move","jump","eva","range"])
    if (typeof j[k] !== "number") bad(`${name}: missing stat ${k}`);
}
console.log(`  ✓ ${Object.keys(TC.JOBS).length} jobs, ${Object.keys(TC.ABILITIES).length} abilities`);

console.log("Campaign");
const walkable = (m, x, y) => {
  if (y < 0 || y >= m.t.length || x < 0 || x >= m.t[0].length) return false;
  return TC.TERRAIN[m.t[y][x]].walk;
};
for (const ch of TC.CAMPAIGN) {
  const m = TC.MAPS[ch.map];
  if (!m) { bad(`${ch.id}: unknown map ${ch.map}`); continue; }
  const before0 = errors;
  const used = new Set();
  const claim = (x, y, who) => {
    const k = x + "," + y;
    if (used.has(k)) bad(`${ch.id}: two units start on ${k} (${who})`);
    used.add(k);
  };
  ch.deploy.forEach(([x, y], i) => {
    if (!walkable(m, x, y)) bad(`${ch.id}: deploy slot ${i} at ${x},${y} is not walkable`);
    claim(x, y, `deploy ${i}`);
  });
  if (ch.deploy.length < TC.PARTY.length) bad(`${ch.id}: ${ch.deploy.length} deploy slots for ${TC.PARTY.length} party members`);
  if (ch.npc) {
    const [nm, job, x, y] = ch.npc;
    if (!TC.JOBS[job]) bad(`${ch.id}: unknown npc job ${job}`);
    if (!walkable(m, x, y)) bad(`${ch.id}: npc ${nm} spawns on non-walkable ${x},${y}`);
    claim(x, y, nm);
  }
  if (ch.objective === "protect" && !ch.npc) bad(`${ch.id}: protect objective needs an npc`);
  for (const [nm, job, x, y] of ch.enemies) {
    if (!TC.JOBS[job]) bad(`${ch.id}: unknown job ${job}`);
    if (!walkable(m, x, y)) bad(`${ch.id}: ${nm} spawns on non-walkable ${x},${y}`);
    claim(x, y, nm);
  }
  if (ch.objective === "boss" && !ch.enemies.some(e => TC.JOBS[e[1]].passive === "boss"))
    bad(`${ch.id}: boss objective but no boss unit`);
  if (errors === before0) console.log(`  ✓ ${ch.id} — ${ch.title} (${ch.enemies.length} enemies)`);
}

if (errors) { console.error(`\n${errors} problem(s) found.`); process.exit(1); }
console.log("\nAll data valid.");
