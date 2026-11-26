# UNIT CLASH

A 2D autonomous battle sandbox. Place units on opposing sides, press START, and watch
them fight entirely on their own — then analyze the results, adjust your army, and run
it again. Inspired by the broad concept of Totally Accurate Battle Simulator, with
original units, factions, arenas and systems.

Built as a zero-dependency web app: HTML5 Canvas + vanilla ES modules. The simulation
is fully headless and deterministic (seeded), which powers the Battle Lab's fast,
reproducible multi-run experiments.

## Running the game

Any static file server from this directory works:

```bash
npm start            # python3 -m http.server 8080 (fallback: npx serve .)
# then open http://localhost:8080
```

Or open `index.html` through any other static server. A server (not file://) is
required because the game uses ES modules.

## Controls

**Setup phase**
- Click a unit card in the left palette, then click your half of the battlefield to place it.
- Drag placed units to move them; right-click removes; Alt+click duplicates.
- Shift-drag or right-drag pans the camera; wheel zooms.
- Formation tools (right panel): Line, Wedge, Wall, Spread, Mirror, Clear. Or roll a Random Army.
- Configure arena, time limit, team budgets and unit limit in the top bar. The ∞ toggle enables unrestricted sandbox.
- Save/load army configurations (right panel); the last setup autosaves.
- **🔗 Code / ⬇ Import** — share any battle setup as a compact code (base64 JSON).

**Results screen**
- Battle-flow chart: units alive per team across the whole fight.
- MVP, evidence-based insights, XP and achievements.

**Battle phase**
- **⚡ Quick Battle** — one click: fresh arena, two random armies, fight starts immediately.
- The bottom **momentum bar** shows live cost-weighted remaining army strength.
- Start / Pause / Resume / Reset / Speed (0.5x-4x) in the top bar.
- `Space` pause - `R` reset - `O` overview camera - `Delete` remove selection.
- Click a unit to inspect it; toggle Follow to have the camera track it.
- On the outcome, a short cinematic slow-motion plays before results.

## Modes

- **Sandbox** - unrestricted placement and budgets.
- **Campaign** - 5 missions, each teaching one strategic idea (armor walls, bouncing bolts, snipers, kiting a Colossus, full compositions).
- **Survival** - endless waves; survivors keep their wounds, you earn budget between waves.
- **Challenge of the Day** - deterministic date-seeded arena/budget/restrictions/enemy.
- **Battle Lab** - see below.
- **Custom Battle** - save/load configurations from sandbox.

## Battle Lab

The experimentation engine. From the results screen (or the Lab tab), send your battle
as a **baseline**, duplicate it, change one variable (composition, formation, arena,
upgrades, budgets), and run N headless simulations per configuration with
deterministic seeds (`seed + runIndex * 7919`). Compare win rates, average duration,
survivors, damage, healing and losses, per-unit performance, and read insights that are
generated strictly from tracked battle statistics. Experiments (names, notes, results)
persist in localStorage history. Runs are chunked (~30 ms slices) so the UI never freezes.
**⚔ Formation Variants** auto-generates defensive / balanced / scattered re-positionings of
your baseline army so formation effects can be measured directly. **🧪 Synergy Scan** builds
one extra-copy variant per unit type and runs them against the baseline to surface which
additions actually help *your* army, under *your* tested conditions.

Results include healing received as well as damage dealt/taken, so sustain compositions
can be judged honestly.

## Architecture

```
js/
  rng.js          mulberry32 + FNV-1a - all sim randomness is seeded and reproducible
  units.js        config-driven unit definitions (15 units), categories, 30 upgrades
  factions.js     4 factions with per-unit passive bonuses
  arenas.js       6 arenas + environmental modifiers (slippery, wind, low gravity, heavy knockback)
  ai.js           reusable behavior brains (brawler, skirmisher, guardian, healer, ...) + focus-fire coordination, prime-target selection and a flee/brave retreat cycle
  sim.js          headless BattleSim: fixed 30 Hz tick, spatial grid, projectiles, devices, statuses
  stats.js        StatsTracker + multi-run aggregation + evidence-based insight generation
  battlelab.js    experiment model + chunked headless multi-run scheduler
  modes.js        random army generator, formation layout, campaign, daily challenge
  progression.js  XP/levels, unit mastery, achievements, upgrade gating
  save.js         localStorage persistence (guarded for private mode / Node)
  render.js       Canvas renderer - consumes sim events, never mutates sim state
  audio.js        WebAudio synthesized SFX (no assets)
  ui.js           GameController: placement, budgeting, battle loop, modes, Lab UI
  main.js         bootstrap
```

Simulation and presentation are strictly separated: `BattleSim` has no DOM access,
`runToEnd()` finishes a battle without any rendering, and the renderer only reads sim
state plus an event stream. Same seed + same config = identical battle - verified by tests.

## Testing

```bash
npm test            # node --test - 26 tests, no browser needed
```

Covers: roster integrity, upgrade resolution, battle completion, determinism,
event-collection purity, stats consistency, cost math, lab aggregation, insights,
army generation, campaign/daily data, progression math, lab end-to-end runs,
persistence fallbacks — plus v0.2 systems: Phoenix rebirth, Reaper lifesteal,
focus-fire determinism, auto-formation variants, timeline data integrity, and
share-code round-trips.

## Units (15)

Scout · Brawler · Guardian · Medic · Juggernaut · Spark Caster · Longshot · Engineer ·
Disruptor · Commander · Trickster · Artificer · Colossus · **Phoenix** (dies twice: a death
nova and a rebirth) · **Reaper** (melee lifesteal drain tank)

## Extending

- **New unit**: add a def to `UNITS` in `js/units.js` (cost/hp/speed/attack/ability/
  brain/visual) and pick or add a brain in `js/ai.js`. The palette, budgets, costs,
  Lab integration and insights pick it up automatically.
- **New upgrade**: add an entry to `UPGRADES` (with `apply(d)` for def-level stats) and
  behavior hooks via `u.hasUpgrade('...')` in `sim.js`/`ai.js`.
- **New faction/arena**: entries in `factions.js`/`arenas.js` - bonuses apply at spawn,
  arenas bring palettes and default modifiers.

## Status / transparency

- The simulation layer, determinism, stats, Lab pipeline and persistence are covered by
  automated Node tests (all passing).
- Rendering, audio and mouse/keyboard wiring are implemented but were not executed in a
  browser in this environment - no visual claims are made beyond the code being written
  and syntax/import-checked.
