#!/usr/bin/env node
/* Generates godot/scripts/data/GameData.gd from js/data.js so the two engines
   can never drift. Run `node tools/gen-godot-data.js` after editing the tables;
   CI re-runs it and fails if the checked-in file is stale.                    */
"use strict";
global.window = {};
require("../js/data.js");
const TC = global.window.TC;
const fs = require("fs"), path = require("path");

const lit = v => {
  if (v === null || v === undefined) return "null";
  if (typeof v === "string") return JSON.stringify(v);
  if (typeof v === "number") return Number.isInteger(v) ? String(v) : String(v);
  if (typeof v === "boolean") return v ? "true" : "false";
  if (Array.isArray(v)) return "[" + v.map(lit).join(", ") + "]";
  if (typeof v === "object") return "{" + Object.entries(v).map(([k, x]) => `${JSON.stringify(k)}: ${lit(x)}`).join(", ") + "}";
  throw new Error("cannot serialise " + typeof v);
};

const dict = (name, obj, indent) => {
  const pad = " ".repeat(indent || 1);
  const body = Object.entries(obj)
    .map(([k, v]) => `${pad}${JSON.stringify(k)}: ${lit(v)},`)
    .join("\n");
  return `const ${name} := {\n${body}\n}`;
};
const arr = (name, list) =>
  `const ${name} := [\n${list.map(v => "\t" + lit(v) + ",").join("\n")}\n]`;

const out = `# ============================================================================
# TACTICS CORE — GAME DATA  (GENERATED FILE — DO NOT EDIT BY HAND)
#
# Produced by tools/gen-godot-data.js from js/data.js, which is the single
# source of truth for both the HTML5 build and this Godot project. Edit the
# JavaScript tables and re-run the generator.
# ============================================================================
class_name GameData
extends RefCounted

${dict("TERRAIN", TC.TERRAIN)}

${dict("STATUS", TC.STATUS)}

${dict("ABILITIES", TC.ABILITIES)}

${dict("JOBS", TC.JOBS)}

${dict("ITEMS", TC.ITEMS)}

${dict("MAPS", TC.MAPS)}

${arr("CAMPAIGN", TC.CAMPAIGN)}

${arr("PARTY", TC.PARTY)}

${dict("START_ITEMS", TC.START_ITEMS)}

${dict("DIFFICULTY", TC.DIFFICULTY)}

# --------------------------------------------------------------- helpers --
static func terrain(code: String) -> Dictionary:
\treturn TERRAIN.get(code, TERRAIN["g"])

static func job(name: String) -> Dictionary:
\treturn JOBS[name]

static func ability(id: String) -> Dictionary:
\treturn ABILITIES[id]

static func status_def(id: String) -> Dictionary:
\treturn STATUS[id]

static func color_of(hex: String) -> Color:
\treturn Color(hex)

## Chapter lookup by its string id, e.g. "ch2".
static func chapter(id: String) -> Dictionary:
\tfor c in CAMPAIGN:
\t\tif c["id"] == id:
\t\t\treturn c
\treturn CAMPAIGN[0]
`;

const dest = path.join(__dirname, "..", "godot", "scripts", "data", "GameData.gd");
fs.mkdirSync(path.dirname(dest), { recursive: true });
const prev = fs.existsSync(dest) ? fs.readFileSync(dest, "utf8") : null;
if (process.argv.includes("--check")) {
  if (prev !== out) { console.error("GameData.gd is stale — run `node tools/gen-godot-data.js`"); process.exit(1); }
  console.log("GameData.gd is up to date.");
} else {
  fs.writeFileSync(dest, out);
  console.log(`Wrote ${path.relative(process.cwd(), dest)} (${out.length} bytes)`);
}
