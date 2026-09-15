# ============================================================================
# TACTICS CORE — GAME DATA  (GENERATED FILE — DO NOT EDIT BY HAND)
#
# Produced by tools/gen-godot-data.js from js/data.js, which is the single
# source of truth for both the HTML5 build and this Godot project. Edit the
# JavaScript tables and re-run the generator.
# ============================================================================
class_name GameData
extends RefCounted

const TERRAIN := {
 ".": {"id": ".", "name": "Void", "walk": false, "void": true, "top": "#000000", "eva": 0, "def": 0},
 "g": {"id": "g", "name": "Grass", "walk": true, "top": "#4e7a45", "eva": 0, "def": 0},
 "s": {"id": "s", "name": "Stone", "walk": true, "top": "#6b6f84", "eva": 0, "def": 0},
 "d": {"id": "d", "name": "Sand", "walk": true, "top": "#9c8557", "eva": 0, "def": 0},
 "f": {"id": "f", "name": "Forest", "walk": true, "top": "#2f5a38", "eva": 20, "def": 2, "decor": "tree"},
 "r": {"id": "r", "name": "Rock", "walk": true, "top": "#7a6f63", "eva": 5, "def": 2, "decor": "rock"},
 "b": {"id": "b", "name": "Bridge", "walk": true, "top": "#6d5233", "eva": 0, "def": 0, "decor": "plank"},
 "w": {"id": "w", "name": "Water", "walk": false, "top": "#2a5a8c", "eva": 0, "def": 0, "liquid": true},
 "l": {"id": "l", "name": "Lava", "walk": true, "top": "#8c3a1e", "eva": 0, "def": 0, "liquid": true, "hazard": 8, "glow": "#ff7a3a"},
 "x": {"id": "x", "name": "Rubble", "walk": true, "top": "#54566b", "eva": 10, "def": 1, "decor": "rock"},
}

const STATUS := {
 "poison": {"name": "Poison", "icon": "☣", "color": "#8ad06f", "bad": true, "hpTickPct": -0.08},
 "regen": {"name": "Regen", "icon": "♥", "color": "#6fd08c", "bad": false, "hpTickPct": 0.1},
 "haste": {"name": "Haste", "icon": "»", "color": "#8ecaff", "bad": false, "spd": 1.5},
 "slow": {"name": "Slow", "icon": "«", "color": "#a08ed0", "bad": true, "spd": 0.5},
 "stun": {"name": "Stun", "icon": "✷", "color": "#e8c66a", "bad": true, "skip": true},
 "protect": {"name": "Protect", "icon": "◈", "color": "#7aa5ff", "bad": false, "def": 1.35, "res": 1.35},
 "might": {"name": "Might", "icon": "▲", "color": "#e0955b", "bad": false, "atk": 1.3, "mag": 1.3},
 "weaken": {"name": "Weaken", "icon": "▼", "color": "#b06a6a", "bad": true, "atk": 0.72, "mag": 0.72},
 "shell": {"name": "Shell", "icon": "◇", "color": "#b48ef0", "bad": false, "res": 1.5},
}

const ABILITIES := {
 "attack": {"id": "attack", "name": "Attack", "mp": 0, "range": 1, "aoe": 0, "type": "phys", "power": 1, "target": "enemy", "vert": 2, "desc": "Basic weapon strike. Free, and can crit."},
 "shoot": {"id": "shoot", "name": "Shoot", "mp": 0, "range": 4, "minRange": 1, "aoe": 0, "type": "phys", "power": 1, "target": "enemy", "vert": 4, "desc": "Bow shot. Reaches far and over terrain."},
 "zap": {"id": "zap", "name": "Zap", "mp": 0, "range": 2, "aoe": 0, "type": "mag", "power": 0.9, "target": "enemy", "vert": 4, "desc": "Cheap arcane bolt that costs no MP."},
 "shieldBash": {"id": "shieldBash", "name": "Shield Bash", "mp": 6, "range": 1, "aoe": 0, "type": "phys", "power": 0.8, "target": "enemy", "vert": 2, "status": {"id": "stun", "turns": 1, "chance": 70}, "knockback": 1, "desc": "0.8x damage, knocks the target back and stuns (70%)."},
 "rally": {"id": "rally", "name": "Rally", "mp": 10, "range": 0, "aoe": 2, "type": "buff", "target": "ally", "selfCentered": true, "jp": 150, "status": {"id": "might", "turns": 3, "chance": 100}, "desc": "All allies within 2 tiles gain Might (+30% ATK/MAG, 3 turns)."},
 "guardBreak": {"id": "guardBreak", "name": "Guard Break", "mp": 5, "range": 1, "aoe": 0, "type": "phys", "power": 0.9, "target": "enemy", "vert": 2, "jp": 220, "status": {"id": "weaken", "turns": 3, "chance": 90}, "desc": "0.9x damage and Weakens the target (-28% ATK/MAG, 3 turns)."},
 "stasisSword": {"id": "stasisSword", "name": "Stasis Sword", "mp": 12, "range": 3, "aoe": 0, "type": "phys", "power": 1.35, "target": "enemy", "vert": 3, "line": true, "status": {"id": "slow", "turns": 3, "chance": 60}, "desc": "A wave of holy force down a straight line. 1.35x, may Slow."},
 "judgment": {"id": "judgment", "name": "Judgment", "mp": 16, "range": 3, "aoe": 1, "type": "mag", "power": 1.3, "target": "empty", "vert": 4, "jp": 320, "charge": 50, "desc": "Holy light in a 1-tile radius. Charges for a moment before it falls."},
 "powerShot": {"id": "powerShot", "name": "Power Shot", "mp": 6, "range": 6, "minRange": 2, "aoe": 0, "type": "phys", "power": 1.6, "target": "enemy", "vert": 5, "noAdjacent": true, "desc": "1.6x damage at long range. Useless with an enemy in your face."},
 "arrowRain": {"id": "arrowRain", "name": "Arrow Rain", "mp": 10, "range": 5, "minRange": 2, "aoe": 1, "type": "phys", "power": 0.85, "target": "empty", "vert": 5, "jp": 250, "desc": "0.85x damage to everything in a 1-tile radius. Friendly fire is real."},
 "legShot": {"id": "legShot", "name": "Leg Shot", "mp": 4, "range": 4, "minRange": 1, "aoe": 0, "type": "phys", "power": 0.7, "target": "enemy", "vert": 4, "jp": 150, "status": {"id": "slow", "turns": 3, "chance": 90}, "desc": "A crippling shot: 0.7x damage and Slow (90%)."},
 "fire": {"id": "fire", "name": "Fire", "mp": 9, "range": 4, "aoe": 1, "type": "mag", "power": 1.55, "target": "empty", "vert": 4, "charge": 45, "desc": "1.55x magic damage in a 1-tile radius. Charges briefly — targets can step out."},
 "bolt": {"id": "bolt", "name": "Bolt", "mp": 7, "range": 5, "aoe": 0, "type": "mag", "power": 1.75, "target": "enemy", "vert": 5, "pierce": 0.5, "desc": "1.75x magic damage to one foe, ignoring half its RES. Instant."},
 "frost": {"id": "frost", "name": "Frost", "mp": 11, "range": 4, "aoe": 1, "type": "mag", "power": 1.15, "target": "empty", "vert": 4, "jp": 200, "charge": 40, "status": {"id": "slow", "turns": 3, "chance": 80}, "desc": "1.15x magic damage in a radius and Slows (80%). Charges briefly."},
 "meteor": {"id": "meteor", "name": "Meteor", "mp": 24, "range": 5, "aoe": 2, "type": "mag", "power": 2.1, "target": "empty", "vert": 9, "jp": 420, "charge": 22, "desc": "2.1x magic damage in a 2-tile radius. A long charge — everyone sees it coming."},
 "cure": {"id": "cure", "name": "Cure", "mp": 6, "range": 3, "aoe": 0, "type": "heal", "power": 1.5, "target": "ally", "vert": 4, "desc": "Restores 1.5x MAG health to one ally."},
 "cureAll": {"id": "cureAll", "name": "Cura", "mp": 14, "range": 3, "aoe": 1, "type": "heal", "power": 1, "target": "empty", "vert": 4, "jp": 200, "healOnly": true, "desc": "Restores 1.0x MAG to every ally in a 1-tile radius."},
 "protect": {"id": "protect", "name": "Protect", "mp": 8, "range": 3, "aoe": 0, "type": "buff", "target": "ally", "vert": 4, "status": {"id": "protect", "turns": 3, "chance": 100}, "desc": "One ally takes 26% less damage for 3 turns."},
 "regen": {"id": "regen", "name": "Regen", "mp": 7, "range": 3, "aoe": 0, "type": "buff", "target": "ally", "vert": 4, "jp": 150, "status": {"id": "regen", "turns": 3, "chance": 100}, "desc": "One ally recovers 10% HP at the start of each of its next 3 turns."},
 "haste": {"id": "haste", "name": "Haste", "mp": 12, "range": 3, "aoe": 0, "type": "buff", "target": "ally", "vert": 4, "jp": 300, "status": {"id": "haste", "turns": 3, "chance": 100}, "desc": "One ally acts 50% more often for 3 turns."},
 "raise": {"id": "raise", "name": "Raise", "mp": 20, "range": 2, "aoe": 0, "type": "revive", "power": 0.35, "target": "ko", "vert": 3, "jp": 350, "desc": "Brings a fallen ally back with 35% of their health."},
 "cleave": {"id": "cleave", "name": "Cleave", "mp": 0, "cd": 3, "range": 1, "aoe": 1, "type": "phys", "power": 0.9, "target": "empty", "vert": 2, "desc": "Sweeping blow that hits a whole 1-tile radius."},
 "drain": {"id": "drain", "name": "Drain", "mp": 8, "range": 3, "aoe": 0, "type": "drain", "power": 1.1, "target": "enemy", "vert": 4, "desc": "Magic damage; the caster heals for half of it."},
 "poisonBite": {"id": "poisonBite", "name": "Venom Bite", "mp": 0, "cd": 3, "range": 1, "aoe": 0, "type": "phys", "power": 0.75, "target": "enemy", "vert": 2, "status": {"id": "poison", "turns": 3, "chance": 75}, "desc": "Weak bite that poisons."},
 "darkPulse": {"id": "darkPulse", "name": "Dark Pulse", "mp": 14, "range": 4, "aoe": 1, "type": "mag", "power": 1.45, "target": "empty", "vert": 4, "charge": 40, "status": {"id": "weaken", "turns": 3, "chance": 50}, "desc": "Necrotic burst that can Weaken. Charges briefly."},
 "breath": {"id": "breath", "name": "Fire Breath", "mp": 0, "cd": 2, "range": 1, "aoe": 0, "type": "mag", "power": 1.5, "target": "empty", "vert": 3, "shape": "cone", "coneLen": 3, "desc": "A cone of flame three tiles deep. Aim it by picking an adjacent tile."},
 "tailSweep": {"id": "tailSweep", "name": "Tail Sweep", "mp": 0, "cd": 2, "range": 0, "aoe": 1, "type": "phys", "power": 0.95, "target": "empty", "selfCentered": true, "vert": 2, "desc": "Smashes everything adjacent to the dragon."},
 "roar": {"id": "roar", "name": "Roar", "mp": 0, "cd": 4, "range": 0, "aoe": 0, "type": "buff", "target": "ally", "selfCentered": true, "status": {"id": "might", "turns": 3, "chance": 100}, "desc": "The dragon works itself into a fury."},
 "summonBone": {"id": "summonBone", "name": "Raise Dead", "mp": 18, "cd": 3, "range": 2, "aoe": 0, "type": "summon", "target": "empty", "vert": 2, "summon": "Skeleton", "cap": 3, "desc": "Claws a skeleton out of the ground on an empty tile (max 3 at once)."},
 "curseSlow": {"id": "curseSlow", "name": "Curse", "mp": 10, "range": 4, "aoe": 0, "type": "mag", "power": 0.5, "target": "enemy", "vert": 4, "status": {"id": "slow", "turns": 3, "chance": 85}, "desc": "Light damage, heavy Slow."},
}

const JOBS := {
 "Knight": {"hp": 46, "mp": 14, "atk": 11, "def": 7, "mag": 4, "res": 4, "spd": 7, "move": 3, "jump": 2, "eva": 8, "range": 1, "color": "#5b8def", "icon": "⚔", "abilities": ["attack", "shieldBash", "rally", "guardBreak"], "starting": ["attack", "shieldBash"], "passive": "counter", "growth": {"hp": 5, "mp": 1, "atk": 1.1, "def": 0.8, "mag": 0.3, "res": 0.4, "spd": 0.2}, "blurb": "Frontline anchor. Counters melee attacks automatically."},
 "HolyKnight": {"hp": 42, "mp": 22, "atk": 11, "def": 6, "mag": 7, "res": 6, "spd": 8, "move": 3, "jump": 2, "eva": 10, "range": 1, "color": "#8fb7ff", "icon": "✧", "abilities": ["attack", "stasisSword", "protect", "judgment"], "starting": ["attack", "stasisSword"], "passive": "counter", "growth": {"hp": 4.5, "mp": 1.6, "atk": 1, "def": 0.7, "mag": 0.7, "res": 0.6, "spd": 0.25}, "blurb": "Sword-mage hybrid with a ranged holy line attack."},
 "Archer": {"hp": 32, "mp": 16, "atk": 10, "def": 3, "mag": 4, "res": 3, "spd": 11, "move": 4, "jump": 3, "eva": 16, "range": 4, "color": "#6fd08c", "icon": "🏹", "abilities": ["shoot", "powerShot", "legShot", "arrowRain"], "starting": ["shoot", "powerShot"], "passive": "highGround", "growth": {"hp": 3, "mp": 1.2, "atk": 1, "def": 0.3, "mag": 0.3, "res": 0.3, "spd": 0.5}, "blurb": "Deals +25% from higher ground. Fragile up close."},
 "Mage": {"hp": 26, "mp": 34, "atk": 5, "def": 2, "mag": 13, "res": 6, "spd": 8, "move": 3, "jump": 2, "eva": 6, "range": 2, "color": "#b48ef0", "icon": "✦", "abilities": ["zap", "fire", "bolt", "frost", "meteor"], "starting": ["zap", "fire", "bolt"], "passive": "focus", "growth": {"hp": 2.5, "mp": 2.6, "atk": 0.2, "def": 0.2, "mag": 1.4, "res": 0.7, "spd": 0.3}, "blurb": "Area damage and control. Gains +4 MP whenever she Waits."},
 "Priest": {"hp": 30, "mp": 30, "atk": 6, "def": 3, "mag": 11, "res": 8, "spd": 9, "move": 3, "jump": 2, "eva": 8, "range": 1, "color": "#f0d48e", "icon": "✚", "abilities": ["attack", "cure", "protect", "regen", "cureAll", "haste", "raise"], "starting": ["attack", "cure", "protect"], "passive": "faith", "growth": {"hp": 3, "mp": 2.4, "atk": 0.3, "def": 0.3, "mag": 1.2, "res": 0.9, "spd": 0.35}, "blurb": "Heals, shields and resurrects. Healing also grants her XP."},
 "Goblin": {"hp": 28, "mp": 0, "atk": 8, "def": 3, "mag": 2, "res": 2, "spd": 9, "move": 3, "jump": 2, "eva": 10, "range": 1, "color": "#e05b5b", "icon": "👺", "abilities": ["attack", "poisonBite"], "passive": "pack", "growth": {"hp": 3, "mp": 0, "atk": 0.8, "def": 0.3, "mag": 0, "res": 0.2, "spd": 0.3}, "blurb": "+20% damage for each adjacent goblin ally."},
 "Orc": {"hp": 52, "mp": 0, "atk": 12, "def": 6, "mag": 2, "res": 3, "spd": 6, "move": 3, "jump": 1, "eva": 4, "range": 1, "color": "#d0683a", "icon": "🐗", "abilities": ["attack", "cleave"], "passive": "tough", "growth": {"hp": 6, "mp": 0, "atk": 1.2, "def": 0.8, "mag": 0, "res": 0.3, "spd": 0.15}, "blurb": "Slow bruiser with a radius-1 Cleave."},
 "Bandit": {"hp": 34, "mp": 8, "atk": 10, "def": 3, "mag": 3, "res": 3, "spd": 10, "move": 4, "jump": 3, "eva": 18, "range": 4, "color": "#c98a4b", "icon": "🏹", "abilities": ["shoot", "powerShot"], "passive": "highGround", "growth": {"hp": 3.2, "mp": 0.6, "atk": 0.9, "def": 0.3, "mag": 0.2, "res": 0.2, "spd": 0.45}, "blurb": "Enemy archer. Loves rooftops and cliffs."},
 "Shade": {"hp": 26, "mp": 26, "atk": 6, "def": 2, "mag": 12, "res": 7, "spd": 10, "move": 4, "jump": 4, "eva": 14, "range": 2, "color": "#8a5bd6", "icon": "☠", "abilities": ["zap", "drain", "curseSlow"], "passive": "phase", "growth": {"hp": 2.4, "mp": 2, "atk": 0.2, "def": 0.2, "mag": 1.2, "res": 0.7, "spd": 0.4}, "blurb": "Floating caster. Ignores height limits when moving."},
 "Skeleton": {"hp": 22, "mp": 0, "atk": 9, "def": 4, "mag": 2, "res": 1, "spd": 8, "move": 3, "jump": 2, "eva": 6, "range": 1, "color": "#cfd4e0", "icon": "💀", "abilities": ["attack"], "passive": "none", "growth": {"hp": 2, "mp": 0, "atk": 0.6, "def": 0.3, "mag": 0, "res": 0.1, "spd": 0.2}, "blurb": "Summoned chaff. Keeps coming while the Necromancer lives."},
 "DarkKnight": {"hp": 50, "mp": 12, "atk": 13, "def": 7, "mag": 5, "res": 5, "spd": 7, "move": 3, "jump": 2, "eva": 8, "range": 1, "color": "#5a4a7a", "icon": "⚔", "abilities": ["attack", "guardBreak", "shieldBash"], "passive": "counter", "growth": {"hp": 5, "mp": 1, "atk": 1.2, "def": 0.8, "mag": 0.3, "res": 0.4, "spd": 0.2}, "blurb": "A knight who fights for the other side. Counters, breaks guards."},
 "Dragon": {"hp": 120, "mp": 20, "atk": 14, "def": 9, "mag": 13, "res": 7, "spd": 7, "move": 4, "jump": 3, "eva": 4, "range": 1, "color": "#c0392b", "icon": "🐉", "abilities": ["attack", "breath", "tailSweep", "roar"], "passive": "boss", "growth": {"hp": 8, "mp": 1, "atk": 1.1, "def": 0.8, "mag": 0.9, "res": 0.6, "spd": 0.2}, "blurb": "BOSS. Breathes fire in a cone, sweeps its tail through everything adjacent."},
 "Merchant": {"hp": 60, "mp": 0, "atk": 3, "def": 6, "mag": 2, "res": 6, "spd": 9, "move": 4, "jump": 2, "eva": 22, "range": 1, "color": "#d9c27a", "icon": "☺", "abilities": [], "passive": "none", "growth": {"hp": 3, "mp": 0, "atk": 0.2, "def": 0.3, "mag": 0, "res": 0.3, "spd": 0.2}, "blurb": "Cannot fight. Keep them alive."},
 "Necromancer": {"hp": 78, "mp": 60, "atk": 8, "def": 6, "mag": 16, "res": 12, "spd": 9, "move": 3, "jump": 2, "eva": 10, "range": 3, "color": "#6f3fb0", "icon": "☾", "abilities": ["zap", "darkPulse", "summonBone", "curseSlow"], "passive": "boss", "growth": {"hp": 8, "mp": 4, "atk": 0.5, "def": 0.6, "mag": 1.8, "res": 1.2, "spd": 0.3}, "blurb": "BOSS. Immune to Stun, resurrects skeletons, hits a whole area."},
}

const ITEMS := {
 "potion": {"id": "potion", "name": "Potion", "icon": "🧪", "range": 2, "target": "ally", "desc": "Restore 45 HP to one ally.", "hp": 45},
 "ether": {"id": "ether", "name": "Ether", "icon": "💧", "range": 2, "target": "ally", "desc": "Restore 25 MP to one ally.", "mp": 25},
 "phoenix": {"id": "phoenix", "name": "Phoenix Down", "icon": "🪶", "range": 2, "target": "ko", "desc": "Revive a fallen ally at 40% HP.", "revive": 0.4},
 "antidote": {"id": "antidote", "name": "Antidote", "icon": "🌿", "range": 2, "target": "ally", "desc": "Clear every negative status.", "cleanse": true},
}

const MAPS := {
 "plain": {"name": "Mandalia Plain", "weather": "clear", "t": ["ggggfggggggg", "gfggggwwgggf", "gggggwwwgggg", "fgggggwwgggf", "ggfgggggfggg", "ggfgggggfggg", "fggggrrggggf", "ggggrrrrgggg", "gfggrrrrggfg", "ggggfggggggg"], "h": ["000001100000", "000000000000", "000000000000", "000000000000", "000000000000", "000000000000", "000001100000", "000012210000", "000012210000", "000001100000"]},
 "sluice": {"name": "Sluice Gate", "weather": "rain", "t": ["sssswwwwssss", "ssfswwwwsfss", "sssbbbbbssss", "wwwbwwwbwwww", "wwwbwwwbwwww", "sssbbbbbssss", "ssrssssssrss", "srrsssssssrs", "ssssffffssss", "sssssffsssss"], "h": ["222200002222", "222200002222", "111111111111", "000100010000", "000100010000", "111111111111", "112111111211", "123111111321", "111111111111", "111111111111"]},
 "ziggurat": {"name": "Ziggurat of Dust", "weather": "dusk", "t": ["dddddddddddd", "ddssssssssdd", "dssrrrrrrssd", "dsrssssssrsd", "dsrsllllsrsd", "dsrsllllsrsd", "dsrssssssrsd", "dssrrrrrrssd", "ddssssssssdd", "dddddddddddd"], "h": ["000000000000", "011111111110", "012222222210", "012333333210", "012322223210", "012322223210", "012333333210", "012222222210", "011111111110", "000000000000"]},
 "grove": {"name": "Grog Hill", "weather": "night", "t": ["fgfggggfggff", "ggggfgggggfg", "fggsssssgggf", "ggfsggggsfgg", "ggfsggggsfgg", "ggfsggggsfgg", "fggsssssgggf", "ggggfgggggfg", "fgfggggfggff", "fffggffggfff"], "h": ["000000000000", "000000000000", "000111110000", "000111110000", "000111110000", "000111110000", "000111110000", "000000000000", "000000000000", "000000000000"]},
 "ramparts": {"name": "Bervenia Ramparts", "weather": "dusk", "t": ["ssssssssssss", "ssssssssssss", "sxxxxxxxxxxs", "sggggggggggs", "sggfggggfggs", "ggggggrrgggg", "gggggrrrrggg", "ggfgggggggfg", "gggggggggggg", "ggggfggggfgg"], "h": ["333333333333", "333333333333", "311111111113", "200000000002", "100000000001", "000000110000", "000001111000", "000000000000", "000000000000", "000000000000"]},
 "roost": {"name": "Wyrm's Roost", "weather": "rain", "t": ["rrrrrrrrrrrr", "rrxxxxxxxxrr", "rxxssssssxxr", "rxsssrrsssxr", "rxssrrrrssxr", "rxssrrrrssxr", "rxsssrrsssxr", "rxxssssssxxr", "rrxxxxxxxxrr", "xxxxxxxxxxxx"], "h": ["333333333333", "322222222223", "321111111123", "321122221123", "321122221123", "321122221123", "321122221123", "321111111123", "322222222223", "111111111111"]},
 "necrohol": {"name": "Necrohol of Mullonde", "weather": "night", "t": ["xxssssssssxx", "xsssxxxxsssx", "sssxxllxxsss", "ssxxllllxxss", "sxxllssllxxs", "sxxllssllxxs", "ssxxllllxxss", "sssxxllxxsss", "xsssxxxxsssx", "xxssssssssxx"], "h": ["111111111111", "122211112221", "123300003321", "123300003321", "123300003321", "123300003321", "123300003321", "123300003321", "122211112221", "111111111111"]},
}

const CAMPAIGN := [
	{"id": "ch1", "map": "plain", "title": "Chapter 1 — Ambush", "brief": "Bandit goblins cut the road south. Break them and move on.", "deploy": [[1, 4], [0, 5], [1, 6], [0, 3], [1, 3]], "enemyLevel": 1, "enemies": [["Gob A", "Goblin", 10, 3], ["Gob B", "Goblin", 10, 6], ["Gob C", "Goblin", 11, 5], ["Orc Brute", "Orc", 10, 4], ["Scrapper", "Goblin", 11, 2]], "objective": "rout", "xp": 120, "tip": "Attack from behind for +50% damage. Watch the facing arrow under each unit."},
	{"id": "ch2", "map": "sluice", "title": "Chapter 2 — The Sluice Gate", "brief": "Hold the bridges. Bandit archers have the high walls.", "deploy": [[1, 8], [2, 8], [3, 8], [1, 9], [2, 9]], "enemyLevel": 3, "enemies": [["Longshot", "Bandit", 1, 0], ["Deadeye", "Bandit", 10, 0], ["Wisp", "Shade", 2, 1], ["Wisp II", "Shade", 9, 1], ["Orc Sentry", "Orc", 5, 5], ["Orc Sentry II", "Orc", 6, 5]], "objective": "rout", "xp": 200, "tip": "Height matters: attacking from above adds accuracy and damage. Bridges are choke points."},
	{"id": "ch3", "map": "ziggurat", "title": "Chapter 3 — Ziggurat of Dust", "brief": "Climb the terraces. The lava pit at the summit burns anything that stops in it.", "deploy": [[4, 8], [5, 8], [6, 8], [7, 8], [5, 9]], "enemyLevel": 4, "enemies": [["Warlord", "Orc", 5, 1], ["Warlord II", "Orc", 6, 1], ["Sniper", "Bandit", 2, 3], ["Sniper II", "Bandit", 9, 3], ["Wraith", "Shade", 3, 4], ["Wraith II", "Shade", 8, 5]], "objective": "rout", "xp": 300, "tip": "Jump limits climbing. Use the ramps at the corners, or you will stall on the stairs."},
	{"id": "ch4", "map": "grove", "title": "Chapter 4 — Grog Hill", "brief": "A caravan master hired you for the night road. The ambush is already closing in from every side.", "deploy": [[4, 4], [6, 4], [5, 5], [4, 6], [6, 6]], "enemyLevel": 5, "npc": ["Caravan Master", "Merchant", 5, 4], "enemies": [["Cutthroat", "Goblin", 0, 0], ["Cutthroat II", "Goblin", 11, 0], ["Cutthroat III", "Goblin", 0, 9], ["Cutthroat IV", "Goblin", 11, 9], ["Wisp", "Shade", 5, 0], ["Wisp II", "Shade", 6, 9]], "objective": "protect", "xp": 340, "tip": "The Caravan Master cannot fight and will run. If he falls, the battle is lost. Body-block for him."},
	{"id": "ch5", "map": "ramparts", "title": "Chapter 5 — Bervenia Ramparts", "brief": "Archers hold the wall. Stairs at each end, or a hard climb over the rubble.", "deploy": [[4, 9], [5, 9], [6, 9], [7, 9], [5, 8]], "enemyLevel": 5, "enemies": [["Wallguard", "Bandit", 2, 1], ["Blackguard", "DarkKnight", 5, 4], ["Brute", "Orc", 6, 5], ["Haunt", "Shade", 11, 0]], "objective": "rout", "xp": 400, "tip": "Dark Knights counter melee and break your guard. Hit them from behind, or from range."},
	{"id": "ch6", "map": "roost", "title": "Chapter 6 — Wyrm's Roost", "boss": true, "brief": "A dragon nests in the crater. Its breath fills a cone three tiles deep; its tail hits everything adjacent.", "deploy": [[4, 9], [5, 9], [6, 9], [7, 9], [3, 9]], "enemyLevel": 7, "enemies": [["Varkath", "Dragon", 5, 4], ["Wraith", "Shade", 2, 2], ["Wraith II", "Shade", 9, 2], ["Poacher", "Bandit", 1, 1]], "objective": "boss", "xp": 520, "tip": "Never stand in front of the dragon, and never stand next to it in a group. Flank it and Slow it."},
	{"id": "ch7", "map": "necrohol", "title": "Chapter 7 — Necrohol", "boss": true, "brief": "The Necromancer keeps raising the dead. Cut the head off.", "deploy": [[5, 9], [6, 9], [4, 9], [7, 9], [5, 8]], "enemyLevel": 10, "enemies": [["Vetrix", "Necromancer", 5, 1], ["Bone A", "Skeleton", 4, 2], ["Bone B", "Skeleton", 7, 2], ["Shade Lord", "Shade", 6, 1], ["Bone C", "Skeleton", 3, 2], ["Bone D", "Skeleton", 8, 2]], "objective": "boss", "xp": 600, "tip": "Killing the Necromancer ends the battle — skeletons keep coming until you do."},
]

const PARTY := [
	{"name": "Ramza", "job": "Knight"},
	{"name": "Agrias", "job": "HolyKnight"},
	{"name": "Mustadio", "job": "Archer"},
	{"name": "Rapha", "job": "Mage"},
	{"name": "Alma", "job": "Priest"},
]

const START_ITEMS := {
 "potion": 3,
 "ether": 2,
 "phoenix": 1,
 "antidote": 2,
}

const DIFFICULTY := {
 "story": {"name": "Story", "levelOffset": -1, "undoTurn": true, "blurb": "Enemies a level lower. Rewind any turn."},
 "normal": {"name": "Normal", "levelOffset": 0, "undoTurn": false, "blurb": "As designed."},
 "hard": {"name": "Hard", "levelOffset": 2, "undoTurn": false, "blurb": "Enemies two levels higher. No rewinds."},
}

# --------------------------------------------------------------- helpers --
static func terrain(code: String) -> Dictionary:
	return TERRAIN.get(code, TERRAIN["g"])

static func job(name: String) -> Dictionary:
	return JOBS[name]

static func ability(id: String) -> Dictionary:
	return ABILITIES[id]

static func status_def(id: String) -> Dictionary:
	return STATUS[id]

static func color_of(hex: String) -> Color:
	return Color(hex)

## Chapter lookup by its string id, e.g. "ch2".
static func chapter(id: String) -> Dictionary:
	for c in CAMPAIGN:
		if c["id"] == id:
			return c
	return CAMPAIGN[0]
