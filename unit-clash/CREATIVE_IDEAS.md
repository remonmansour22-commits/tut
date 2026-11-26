# CREATIVE IDEAS — UNIT CLASH Backlog

Ideas beyond the initial spec, recorded so strong concepts aren't lost. Format:
name / description / gameplay benefit / complexity / dependencies / priority / status.

## Implemented (grew out of the spec during development)

- **Deterministic replay core** — mulberry32 + FNV-1a seeded RNG across the whole sim; the
  same seed + config replays a battle tick-for-tick. Benefit: Battle Lab comparisons are
  statistically meaningful and any result is reproducible. Complexity: M. Status: DONE.
- **Cinematic slow-mo finish** — when the outcome is decided, time drops to 0.3x for ~1.4s
  and the camera zooms to the last kill before results appear. Benefit: a signature
  "moment" on every battle ending. Complexity: S. Status: DONE.
- **Evidence-only insights** — result analysis is generated exclusively from tracked
  statistics (frontline collapse timing, sustain absence, unprotected ranged, MVP,
  overspent roles). Benefit: players learn real causes, not flavor text. Complexity: M.
  Status: DONE.
- **Survivor wound carryover** — Survival waves keep survivors' HP fraction and grant
  between-wave budget. Benefit: wave-to-wave resource decisions. Complexity: S. Status: DONE.
- **Chunked headless lab runs** — experiments simulate in ~30ms slices with
  `collectEvents:false`. Benefit: the lab never freezes the game. Complexity: M. Status: DONE.

## Implemented in v0.2 (autonomous improvement cycle)

- **Focus-fire coordination** — 45% of each army converges on the squad's prime target each
  think tick instead of everyone fighting their own duel. Benefit: armies feel like armies;
  abilities (Bulwark, Cleave, Heal Beam) now visibly turn fights. Complexity: S. Status: DONE.
- **Backline self-preservation** — fragile brains (medic, artificer, caster, sniper,
  engineer, disruptor, commander) retreat when badly hurt. Benefit: supports survive and
  battles get chase/intercept dynamics; produced a Phoenix kiting 3 Juggernauts to a draw.
  Complexity: S. Status: DONE.
- **Phoenix (new unit)** — one-time rebirth with a damaging nova; upgradeable into a larger,
  slowing nova or a stronger caster. Benefit: signature "memorable moment" unit. Status: DONE.
- **Reaper (new unit)** — melee lifesteal drain-tank; Bloodmoon/Deathwing upgrades. Status: DONE.
- **Quick Battle** — one-click instant battle for brand-new players. Status: DONE.
- **Momentum bar** — live cost-weighted team-strength readout during battle. Status: DONE.
- **Battle-flow timeline chart** — units-alive SVG chart on the results screen, built from the
  previously unused stats.timeline. Status: DONE.
- **Battle share codes** — export/import configs as UC1. base64 codes. Status: DONE.
- **Formation Variants (Lab)** — one click generates defensive/balanced/scattered variants of
  the baseline for direct comparison. Status: DONE.

## Balance pass v0.2.1 (data-driven, measured)

Method: 40-seed round robins via headless `BattleSim` (seeds `1000 + i*7919`), reported as
`A-win% / B-win% (draws)`. Perfect-mirror control (same army vs itself, sides swapped every
other run) confirmed no side bias: 27/30/3 over 60 runs after the patches below.

Findings and patches (before -> after, same 40-seed methodology):

- **Degenerate infinite-kiting found and fixed.** After the v0.2 retreat system shipped,
  Phoenixes could kite melee units indefinitely and end battles at full HP. Fix: a
  flee/brave cycle (`ai.js` — fleeing units disengage at 0.85x speed for 3s, then fight
  through fear for 4s via `BRAVE_DURATION`). Post-fix, Phoenixes engage, die and rebirth
  as designed. This was the most important bug-class fix of the cycle.
- **Dominant meta diagnosed:** `heavyWall` and medic-sustain compositions beat nearly
  everything (balanced lost 33/65 to heavyWall pre-patch).
- Patches applied (two iterations):
  - Medic heal 34 -> 26 (sustain loops were unkillable).
  - Vanguard formation armor 0.12 -> 0.08 (stacked armor made walls unbreakable).
  - Longshot damage 50 -> 70 (ranged needed an answer to armor walls).
  - Juggernaut armor 0.2 -> 0.15 (heavy wall still strong, less absolute).
  - Phoenix: cost 170 -> 160, hp 115, rebirth hpFrac 0.45 -> 0.35, nova 30 -> 20.
  - Reaper: final values cost 150 / hp 165 / armor 0.05 / lifesteal 0.6.
- Measured outcomes after patching: balanced vs heavyWall 40/60 (was 33/65);
  sniperRanged vs heavyWall 23/78 (was 5/95); balanced vs 2xPhoenix 93/8
  (Phoenix not OP vs real comps); balanced vs reaperB 100/0.

Known remaining texture (time-boxed, documented not hidden):
- `balanced` comp still hard-counters the reaper comp (100/0). Next-cycle priority.
- heavyWall dominance is loosened (60% vs balanced, 78% vs sniperRanged) but was not
  re-measured against the full archetype set after iteration 2.
- Focus-fire convergence (45%) is a first guess and is Lab-tunable, not verified optimal.

## Backlog

- **Device counterplay depth** — turrets/totems are now destructible (v0.4). Next step:
  AI explicitly targets enemy devices when they dominate an area, and Engineer gains an
  upgrade to repair/relocate turrets. Complexity: M. Status: partially done.
- **Device statistics in reports** — track damage/healing dealt by turrets and totems in
  StatsTracker so insights can credit "your turret dealt 340 damage" and Lab comparisons
  include device value. Complexity: S. Status: backlog.
- **Mid-battle dynamic events** — announced hazards (meteor, supply drop, sudden freeze)
  at seeded times. Benefit: battles gain an arc; Lab seeds make them reproducible.
  Complexity: M. Status: backlog.
- **Battle "story moments"** — auto-generated highlight reel: biggest single hit, longest
  survive-at-1-HP, biggest nova. Benefit: memorable moments, shareable. Complexity: M.
  Dependencies: event stream (done). Status: backlog.
- **Obstacles & line-of-sight** — cover blocks on some arenas; projectiles check LOS.
  Benefit: positioning gains a new dimension; Sniper Alley becomes literal. Complexity: L.
  Dependencies: sim collision layer, arena props. Priority: HIGH. Status: backlog.
- **Replay recording** — record sim inputs (config + seed is already 95% of it) and
  re-play with scrubbing. Benefit: share/inspect key battles; feeds Lab replay bookmarks.
  Complexity: M (config+seed already deterministic). Priority: HIGH. Status: backlog.
- **Unit-versus-unit tournament brackets** — auto-run 1v1/3v3 round robins in the Lab,
  rank all units with context (arena, budget). Benefit: makes cost/value visible;
  great "research" content. Complexity: M. Dependencies: battlelab.runAll (done).
  Priority: MEDIUM. Status: **DONE v0.4** — Matchup Matrix (headless 1v1 round-robin,
  color-coded heatmap + ranking) in the Lab; 3v3 brackets remain open.
- **Unit performance heatmaps** — per-unit damage/survival heat overlay aggregated over
  lab runs. Benefit: visualize where armies win and die. Complexity: M. Dependencies:
  sim position tracking at death. Priority: MEDIUM. Status: backlog.
- **Custom unit workshop** — compose units from balanced components (body, weapon,
  ability, trait) with automatic cost calculation and balance validation. Benefit: deep
  personal expression; endless experimentation. Complexity: XL. Dependencies: balance
  model, UI. Priority: MEDIUM (post-progression polish). Status: backlog (framework
  exists: config-driven defs + resolveDef).
- **Formation recommendation engine** — after lab runs, suggest spacing tweaks from
  survival-time data. Benefit: closes the "analyze -> improve" loop automatically.
  Complexity: L. Dependencies: aggregate() extensions. Priority: LOW. Status: backlog.
- **Community experiment sharing** — export/import experiments as compact JSON codes.
  Benefit: strategy sharing without servers. Complexity: S. Dependencies: none.
  Priority: MEDIUM. Status: backlog.
- **Weather events mid-battle** — timed arena events (sandstorm gusts, lightning) announced
  in advance. Benefit: battles gain a watchable arc. Complexity: M. Status: backlog.
- **Unit museum** — gallery of fielded units with lifetime stats and mastery badges.
  Benefit: progression feel for collectors. Complexity: S. Dependencies: progression
  mastery data (done). Priority: MEDIUM. Status: backlog.
- **Side-by-side lab viewing** — run two configurations in split-screen view simultaneously.
  Benefit: direct visual comparison instead of only numbers. Complexity: M. Status: backlog.
- **Moving platforms modifier** — arenas with drifting platforms; units carried by them.
  Benefit: positional dynamics in spectator battles. Complexity: L. Status: backlog.
- **Co-op team editor** — two players alternate placing A/B armies on one keyboard.
  Benefit: couch play. Complexity: S. Status: backlog.
- **Asymmetric handicap modifiers** — toggles like "enemy loses 10% HP" for fair
  testing of experimental comps. Benefit: cleaner what-if experiments. Complexity: S.
  Status: backlog.
