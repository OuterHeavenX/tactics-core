# Tactics Core — fixes (2026-09-15)

Drop-in replacement for the original `index.html`. All changes verified with
automated browser playtests (10/10 checks pass).

## 1. Dead units no longer get turns
`tickCT()` skipped KO'd units when accumulating charge time and when picking
the next unit. Before, a KO'd unit would keep its CT, get "turns" with nothing
on the board, and the turn-order panel hid it — looked like the game skipped you.

## 2. Priest gets Cure (8 MP)
- On the Priest's turn, wounded allies in range 3 get a green outline; click one
  to heal 10–16 HP (capped at max HP). Costs 8 MP, ends the turn like an attack.
- Healed units flash green; the cast is logged; the how-to-play card explains it.
- Self-targeting and full-HP allies are excluded on purpose — tapping your own
  priest (or a healthy ally) stays a no-op instead of burning MP by accident.

## 3. Phone-friendly layout
- The board now scales to the screen width (CSS) instead of being fixed 816px,
  and the side panel stacks full-width under 720px.
- Click/tap coordinates are computed from the canvas's on-screen size, so taps
  land on the right tile at any scale. `touch-action: manipulation` removes the
  mobile double-tap zoom delay.
