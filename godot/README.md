# Tactics Core — Godot 4 build

A reconstruction of the HTML5 game in Godot 4.4, sharing its rules exactly.
See the [repository README](../README.md) for the game itself.

## Opening it

Open this folder as a project in Godot **4.4** or newer and press play.
`scenes/Main.tscn` is deliberately four nodes — everything else is built in
code, so the project opens cleanly on any machine and diffs are readable.

```
Main (Node2D, Game.gd)
├── World (Node2D)            carries the camera transform (pan / zoom)
│   └── Board (BoardView.gd)  draws terrain, units and effects
├── Audio (AudioSynth.gd)     synthesises every sound at load time
└── HUD (CanvasLayer, HUD.gd) panels, action bar, sheets — built in _ready()
```

## Architecture

The split matters: **nothing in `scripts/core/` or `scripts/battle/` touches a
node.** `Battle.gd` is a `RefCounted` that takes a chapter and returns outcomes,
pushing anything worth animating onto an `events` array for the view to drain.
That is what lets `tests/HeadlessTest.gd` play thousands of battles with no
window, and what lets the GDScript rules be diffed against the JavaScript ones.

| Path | Role |
| --- | --- |
| `scripts/core/Iso.gd` | isometric projection, camera rotation, facing maths |
| `scripts/core/BattleGrid.gd` | tiles, height, pathfinding, travel-cost field |
| `scripts/battle/Unit.gd` | stats, growth, status effects |
| `scripts/battle/Battle.gd` | CT turn engine and all combat resolution |
| `scripts/battle/EnemyAI.gd` | scores every move × action × target |
| `scripts/view/BoardView.gd` | the isometric renderer |
| `scripts/ui/HUD.gd` | the whole interface |
| `scripts/Game.gd` | screen flow, camera, input |
| `scripts/data/GameData.gd` | **generated** from `js/data.js` — do not edit |

### Rendering

Every tile is a 2:1 diamond top plus two shaded side faces, drawn back-to-front
along view-space diagonals, with units interleaved into the sweep by the
diagonal they stand on. That ordering is what keeps a unit correctly hidden
behind a cliff rather than floating over it.

Drawing happens in raw projection space; `World` carries pan and zoom, so the
camera costs nothing per frame and `BoardView.pick()` can hit-test tile tops and
side faces directly in the same coordinates.

### No assets

There are no textures, fonts or audio files. Terrain, units and effects are
drawn with polygons, and `AudioSynth.gd` renders every sound effect and the
music loop into `AudioStreamWAV`s at load time. The exported `.pck` is ~110 KB.

## Tests

```bash
godot --headless --path . --script tests/HeadlessTest.gd   # rules + balance
godot --headless --path . --script tests/ParityTest.gd     # vs the JS engine
godot --headless --path . -- --autoplay --quit-frames=9000 # soak test
```

`ParityTest.gd` replays `tests/parity_fixture.json` — deterministic scenarios
recorded from the JavaScript engine by `tools/gen-parity-fixture.js` — and diffs
every stat, hit chance, expected damage, reachable set, travel-cost field, AI
decision and turn order. If the two builds ever drift apart, it names exactly
which number moved.

## Web export

```bash
mkdir -p ../build/web
godot --headless --path . --export-release "Web" ../build/web/index.html
```

`variant/thread_support` is **off** on purpose. The threaded web build requires
`SharedArrayBuffer`, which requires `Cross-Origin-Opener-Policy` and
`Cross-Origin-Embedder-Policy` headers that static hosts do not send.
Single-threaded WebGL2 (`gl_compatibility`) runs on GitHub Pages, itch.io and
mobile Safari with no server configuration.

`web/shell.html` replaces Godot's default page with a loading screen that shows
real progress, reports failures readably, and forwards two whitelisted query
parameters to the game:

```
index.html?autoplay=1&chapter=3
```

## Developer flags

Passed after a bare `--`:

| Flag | Effect |
| --- | --- |
| `--autoplay` | the AI plays the player side too, through the real UI entry points (skips deployment) |
| `--chapter=N` | start on chapter 1–4 |
| `--shots=DIR` | save a PNG every `--shot-every` frames |
| `--shot-every=N` | frames between screenshots (default 120) |
| `--quit-frames=N` | exit after N frames |
