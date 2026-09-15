# Changes

## 2.1 — Depth, feel, and engineering

### Depth
- **Cast-time spells.** Fire, Frost, Meteor, Judgment and Dark Pulse charge on
  the timeline and land on whatever is there when they resolve. The tiles under
  a charging spell glow, the caster wears a ring, and the AI steps out of the
  way (and discounts a charged spell it is thinking of casting at you).
- **Ability learning.** Actions earn JP alongside XP. Between chapters, spend
  it on eleven learnable abilities across the five party jobs. Jobs now start
  with a subset of their kit.
- **Three new chapters** between the ziggurat and the finale: a night ambush
  with a **protect** objective (a civilian who cannot fight and must survive),
  castle ramparts with enemy Dark Knights, and a **Dragon boss** whose breath is
  a cone three tiles deep. The AI escorts the civilian when it has one and
  hunts it when it does not.
- **Difficulty settings.** Story, Normal, Hard — an enemy level offset, and
  Story mode can rewind an entire turn.

### Feel
- **Attack animations.** Melee lunges toward the target, shots and spells arc
  across the board on a parabola, charging casters glow.
- **Deployment phase.** Place the party anywhere in the deploy zone before
  turn one.
- **Real sprites.** Every job is now drawn from 0x72's CC0 *DungeonTileset II*
  — four cycling idle frames each, flipped to face the unit's facing — packed
  into a 7 KB atlas by `tools/build-atlas.py`. The vector pawns remain the
  fallback when the atlas is disabled.

### Engineering
- **Whole-turn rewind** via a rules-level snapshot/restore (unit instances are
  kept, so the view never loses its references).
- Balance sweep, parity fixture and both Godot suites extended to cover all
  seven chapters and every new system; the parity test now diffs ~4,250 values.
- The single-source-of-truth generator now emits the difficulty table too.

## 2.0 — Isometric 2.5D rebuild, and a Godot 4 port

Version 1 was a single `index.html`: a flat 12×10 checkerboard, four stats per
unit, one attack, one heal, and an enemy AI that walked at you. This release
keeps the charge-time skeleton and rebuilds everything around it.

### The board is now 2.5D

- **Isometric projection.** Every tile is a 2:1 diamond top plus two shaded side
  faces. Terrain height is real geometry: a cliff visibly stands above the tile
  behind it, and correctly hides it.
- **Height affects the rules, not just the picture.** Attacking downhill adds
  accuracy and damage. Your Jump stat caps the step you can climb, so terraces
  and cliffs block movement until you find the ramp.
- **A rotating camera**, because cliffs hide tiles. `Q`/`E` swing through four
  corners with the board tweening between them, and screen-to-tile picking is
  exact at every angle — verified in the test suite.
- **Pan, zoom, pinch,** and a camera that follows the acting unit when the board
  is too big for the screen.

### The combat has decisions in it

- **Facing.** Units face a direction. Side hits do +25%, back hits +50% with a
  large accuracy and crit bonus. Positioning now beats stats.
- **Hit chance and crits** replace guaranteed damage, driven by facing, height,
  terrain evasion and the defender's Evasion.
- **CT economy.** What you do sets your leftover charge time: move and act → 0,
  act → 20, move → 40, wait → 60. Restraint buys tempo.
- **Move and act in either order**, and undo a move any time before you act.
- **21 abilities** across 11 jobs, with MP costs, cooldowns, areas of effect,
  line attacks, knockback, drain, summons and friendly fire.
- **Nine status effects** — poison, regen, haste, slow, stun, protect, might,
  weaken, shell — that tick on the afflicted unit's own turn.
- **Passives** — counterattacks, high-ground bonuses, goblin pack tactics, orc
  toughness, shades that float over height limits, bosses immune to stun.
- **Items**: potions, ethers, antidotes and Phoenix Downs, in limited supply.
- **Raise.** A fallen ally can come back. Losing someone is no longer final.
- **Targeting preview**: expected damage, hit chance, which side you are hitting
  from, and whether the blow is lethal — before you commit.

### There is a campaign

Four hand-built maps with distinct terrain problems — an open field, a bridge
choke point over water, a four-terrace ziggurat around a lava pit, and a boss
arena — plus XP, levelling, stat growth carried between chapters, and a saved
campaign.

### The AI plans instead of charging

It scores every combination of where it could stand, what it could do and where
it could aim, weighing expected damage against kill potential, healing, buffs,
height, cover, hazards, exposure to your units, and back-attack angles. It
navigates on a hazard-weighted travel-cost field, so it routes *around* a lava
channel instead of treating it as a shortcut it will never take — which is what
used to deadlock two melee squads on either side of the ziggurat.

### It is built for a browser

- Full-viewport canvas with a HUD that reflows for phones: the board keeps the
  middle of the screen, panels move to the corners, the toolbar collapses into
  the pause sheet, and the hint and preview share one strip above the buttons.
- Touch: tap to act, drag to pan, pinch to zoom; first tap previews, second
  commits.
- Still **zero dependencies and zero build step**. Sound effects and music are
  synthesised with WebAudio at runtime, so nothing is downloaded.

### A Godot 4 build, kept honest

`godot/` is the same game reconstructed in Godot 4.4 — the same data, the same
formulas, the same AI — exported to the web single-threaded so it runs on static
hosting without cross-origin-isolation headers.

`js/data.js` is the single source of truth; `tools/gen-godot-data.js` compiles
it into `GameData.gd` and CI fails if the checked-in copy is stale. A parity
test replays deterministic scenarios recorded from the JavaScript engine
through the GDScript one, diffing ~2,950 values exactly.

### Tests

- Rules invariants and isometric maths, in both engines.
- An AI-vs-AI balance sweep over every chapter that fails on stalemates or
  unwinnable maps (current curve ≈ 100% / 87% / 58% / 57%).
- A Playwright playtest that starts a campaign, moves and undoes, attacks, and
  plays a battle to a victory screen at desktop, tablet and phone sizes.
- A Godot autoplay soak test that plays chapters end to end.

### Fixes carried over from 1.x

The version 1.1 fixes are still in: KO'd units never get turns, and the board
scales and takes taps correctly at any size.
