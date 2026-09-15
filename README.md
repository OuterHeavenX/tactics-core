# Tactics Core

An isometric 2.5D turn-based tactics game, in the spirit of *Final Fantasy Tactics*.

It ships twice, from one set of rules:

| Build | Where | How to run |
| --- | --- | --- |
| **HTML5** (zero build step) | repository root — `index.html` | open the file, or `npm run serve` |
| **Godot 4** | `godot/` | open in Godot 4.4+, or export to web |

Both use the same data tables, the same combat formulas and the same AI, and a
[parity test](#tests) fails the build if they ever disagree.

---

## The game

You command five characters against an enemy squad across four chapters. Turn
order is charge-time based, the terrain has real height, and which way a unit is
facing changes how much damage it takes.

### What makes a turn interesting

- **Charge time.** Every unit accumulates CT equal to its Speed; at 100 it acts.
  What you *do* on your turn sets how much CT you keep: move *and* act and you
  restart from 0, act only from 20, move only from 40, and simply waiting leaves
  you 60. Doing less gets you back sooner — the core tempo decision.
- **Height is geometry, not decoration.** Attacking downhill adds accuracy and
  damage; your Jump stat caps the step you can climb, so a terrace is a wall
  until you find the ramp. The camera rotates through four corners (`Q`/`E`)
  because cliffs genuinely hide tiles behind them.
- **Facing.** Each unit has a facing wedge. Hit from the side for +25% damage,
  from behind for **+50%** and a much better chance to land it — and a much
  better chance to crit. Positioning beats raw stats.
- **One move, one action, either order.** Move first and you can undo it right
  up until you act, so probing the range preview costs you nothing.
- **Terrain that does something.** Forest grants evasion, rock grants defence,
  lava burns anything that stops in it, water is impassable, bridges are choke
  points.
- **Readable numbers.** Before you commit, the preview shows expected damage,
  hit chance, which side you are striking from, and whether the blow is lethal.
- **Cast times.** Big spells — Fire, Frost, Meteor, Judgment, Dark Pulse — do not
  land when cast. They charge on the timeline and hit whatever is standing there
  when they resolve, so you can walk out of one, and so can the enemy. The tiles
  under a charging spell glow, the caster gets a ring, and the timeline shows
  the spell as its own entry.
- **Learning.** Every action earns JP alongside XP. Between chapters you spend
  it on new abilities — Rally, Guard Break, Judgment, Leg Shot, Arrow Rain,
  Frost, Meteor, Regen, Cura, Haste, Raise — so the party you finish with is
  not the party you started with.
- **Deployment.** Before turn one you place your five units anywhere in the
  deploy zone. Cliffs and choke points are decided here.
- **Difficulty.** Story (enemies a level lower, and you can rewind any turn),
  Normal, or Hard (two levels higher, no rewinds).

### The party

| Unit | Job | Signature |
| --- | --- | --- |
| Ramza | Knight | Shield Bash (knockback + stun), Rally. Counters melee automatically. |
| Agrias | Holy Knight | Stasis Sword — a ranged holy line attack that can Slow. Protect. |
| Mustadio | Archer | Power Shot, Arrow Rain. +25% damage from higher ground. |
| Rapha | Mage | Fire, Bolt, Frost. Regains MP whenever she Waits. |
| Alma | Priest | Cure, Protect, and — once learned — Regen, Cura, Haste and **Raise**. |

Enemies get their own kit: goblins fight harder in packs and poison you, orcs
cleave a whole radius, shades float over height limits and drain HP, bandit
archers camp the high walls, dark knights counter and break your guard, the
dragon breathes a three-deep cone of fire, and the Necromancer keeps clawing
skeletons out of the ground until you cut the head off.

### The campaign

1. **Ambush** — open field, a lesson in facing.
2. **The Sluice Gate** — bridges and water, archers on the high walls.
3. **Ziggurat of Dust** — four terraces and a lava pit; Jump decides your route.
4. **Grog Hill** — a night ambush from every corner, and a caravan master who
   cannot fight. If he dies, you lose. Body-block for him.
5. **Bervenia Ramparts** — a wall two steps up from the rubble, stairs at each
   end, dark knights in the courtyard.
6. **Wyrm's Roost** — a dragon in a crater. Never stand in front of it, never
   stand next to it in a group.
7. **Necrohol** — a boss who summons. Kill him and the battle ends.

Units carry levels and XP between chapters; progress is saved to local storage
(`localStorage` in the browser build, `user://` in Godot).

### Controls

| | |
| --- | --- |
| Select / move / target | click or tap a tile |
| Pan | drag |
| Zoom | wheel, pinch, or `+` / `-` |
| Rotate camera | `Q` / `E` |
| Wait (end turn) | `Space` |
| Undo move | `U` |
| Rewind whole turn (Story mode) | `R` |
| Start battle (deployment) | `Enter` |
| Cancel / pause | `Esc` |
| Recentre | `F` |
| Move / Item | `M` / `I` |
| Inspect next unit | `Tab` (HTML5 build) |

The layout reflows for phones: the board keeps the middle of the screen, the
panels move to the corners, and the toolbar collapses into the pause sheet.

---

## Running it

### HTML5

```bash
npm run serve      # then open http://localhost:8080/
```

There is no build step and no dependency — `index.html` plus `css/` and `js/`
is the whole game, and it also runs straight off the filesystem. Sound and music
are synthesised with WebAudio at runtime, so nothing is downloaded.

### Godot

Open `godot/` in Godot **4.4** or newer and press play. To export for the web:

```bash
godot --headless --path godot --export-release "Web" ../build/web/index.html
```

The web preset deliberately has **thread support off**. Godot's threaded web
build needs `SharedArrayBuffer`, which needs cross-origin-isolation response
headers that static hosts (GitHub Pages, itch.io, S3) do not send.
Single-threaded WebGL2 runs everywhere, mobile Safari included, with no server
configuration at all. `godot/web/shell.html` is a custom loading shell so the
~43 MB engine download shows real progress instead of a blank page.

The Godot build also accepts a few developer flags after a bare `--`, and the
web shell forwards a whitelisted subset from the query string:

```bash
godot --path godot -- --autoplay --chapter=3      # the AI plays both sides
```
```
index.html?autoplay=1&chapter=3                   # same, in the browser
```

---

## Layout

```
index.html              the HTML5 game
css/style.css
js/data.js              terrain, jobs, abilities, statuses, items, maps, campaign
js/core.js              isometric projection, grid, pathfinding, travel-cost field
js/battle.js            rules: CT turn engine, damage, status, XP  (runs headless)
js/ai.js                enemy AI
js/render.js            isometric renderer
js/audio.js             WebAudio synthesiser
js/ui.js                screens, menus, targeting previews, input
js/main.js

godot/                  the Godot 4 reconstruction (same architecture)
  scripts/core/         Iso.gd, BattleGrid.gd
  scripts/battle/       Unit.gd, Battle.gd, EnemyAI.gd
  scripts/view/         BoardView.gd
  scripts/ui/           HUD.gd
  scripts/data/         GameData.gd  (generated — do not edit)
  tests/                headless rules, balance and parity tests
  web/shell.html        custom loading shell for the web export

tools/                  validators, generators and test runners
```

### Sprites

`assets/sprites.json` describes an optional pixel-art atlas. Drop a
`sprites.png` beside it (a 4×4 grid of 128 px cells in job order), set
`"enabled": true`, and the HTML5 build draws units as billboarded sprites;
otherwise it draws the vector pawns. A sheet was generated with SpriteCook for this project (asset
`2907f0e2-4de4-4e65-9825-3dcdba754438` on the connected account) but the
sandbox could not download it, so it ships un-integrated.

### One source of truth

`js/data.js` is the only place game content lives. `tools/gen-godot-data.js`
compiles it into `godot/scripts/data/GameData.gd`, and CI fails if the checked-in
copy is stale. To change balance, edit the JavaScript tables and run:

```bash
npm run gen:godot
```

---

## Tests

```bash
npm test                # data validation + generated-file check + engine tests
npm run test:browser    # Playwright playtest at 3 viewport sizes
```

```bash
godot --headless --path godot --script tests/HeadlessTest.gd   # rules + balance
godot --headless --path godot --script tests/ParityTest.gd     # vs the JS engine
```

What they actually check:

- **Rules invariants** — back attacks beat front attacks, healing never
  overshoots, damage never goes negative, the turn engine never wakes a fallen
  unit, bosses shrug off stun, summons are capped, waiting leaves more CT than
  move-and-act.
- **Isometric maths** — camera rotation round-trips at all four angles, and
  screen-to-tile picking is exact at every angle (the only misses allowed are
  tiles genuinely occluded by a taller tile in front).
- **Balance** — every chapter is played out AI-vs-AI dozens of times. Battles
  must always reach a result (no stalemates) and must be winnable without being
  free. The current curve is roughly 100% / 87% / 58% / 57%.
- **Parity** — deterministic scenarios recorded from the JavaScript engine are
  replayed through the GDScript engine and diffed exactly: ~4,250 comparisons
  covering stats, known abilities, hit chances, expected damage, reachable
  sets, travel-cost fields, deploy zones, breath cones, AI decisions and turn
  order.
- **New systems** — a charged spell does not resolve on cast, shows on the
  timeline, and lands on empty ground if its target walks away; cones are the
  right shape; rewind restores HP, position and flags; learning spends JP and
  refuses a repeat; losing the civilian loses the battle.
- **The real thing in a real browser** — a campaign is started, a unit is
  repositioned in deployment, moved and the move undone, attacks are resolved,
  a whole battle is played to a victory screen, and an ability is bought on
  the learn screen — on desktop, tablet and phone viewports, with zero console
  errors.

---

## License

MIT.
