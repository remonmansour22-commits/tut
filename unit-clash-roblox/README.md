# UNIT CLASH — Roblox Edition

A 2D autonomous battle sandbox, server-authoritative, built with Luau. Place units for
two teams on opposite halves of an arena, press START, and watch them fight on their own —
each unit driven by its own behavior brain.

## How to get it into Studio (pick one)

**Option 1 — no tools (recommended):** copy `tools/load_uc_from_github.lua` (repo root)
into the Studio **Command Bar** and press Enter. It downloads all scripts from GitHub and
rebuilds the game in your open place. Enable **Allow HTTP Requests** first. Press Play.

**Option 2 — Rojo:** clone the repo, then `rojo serve unit-clash-roblox/default.project.json`
and connect with the Rojo plugin, or `rojo build unit-clash-roblox/default.project.json -o UnitClash.rbxlx`.

**Option 3 — CI:** the GitHub Actions workflow builds `UnitClash.rbxlx` on every push;
download it from the Actions tab artifacts.

## How to play

1. Press Play. A dark arena appears with a blue (AZURE) and red (CRIMSON) half.
2. Click a unit card in the left palette, then click on a team's half to place it.
   Toggle PLACE: AZURE / CRIMSON to choose which side you're placing for.
   Right-click removes a nearby unit.
3. **ENEMY AI** fills the enemy team with a random army within its budget.
4. **START** locks placement and starts the battle. PAUSE / speed (0.5x-4x) / CLEAR
   stay available. The last team with units standing wins (or highest remaining value
   at the 3-minute limit).
5. Results show deployed, survivors, total damage, healing and ability uses per team.

## The roster (15 units)

Scout, Brawler, Guardian, Medic, Juggernaut, Spark Caster, Longshot, Engineer, Disruptor,
Commander, Trickster, Artificer, Colossus, Phoenix (rebirths once with a nova) and
Reaper (melee lifesteal). All definitions live in `src/shared/UCConfig.lua` — costs, HP,
speed, range, damage, cooldowns, auras and abilities. Adding a unit is one table entry.

## Architecture

```
unit-clash-roblox/
  default.project.json                Rojo mapping
  src/shared/UCConfig.lua             unit roster + budgets + arena (shared, client-readable)
  src/server/UCBootstrap.server.lua   arena build, remotes, enemy generator, state broadcast
  src/server/UCModules/UCSim.lua      battle sim: AI brains, combat, projectiles, devices
  src/server/UCModules/UCVisuals.lua  unit models, health bars, effects (server-replicated)
  src/client/UCClient.client.lua      palette, placement input, controls, results UI
```

Server-authoritative: every placement and battle tick runs on the server; the client only
draws UI and forwards clicks. Remotes validate team, bounds, budget and phase.

## Transparency

Developed outside Roblox Studio (the environment cannot run Studio), so the code was
verified with structural block-balance checking and API-usage review, but has **not** been
executed in Studio. If anything errors on Play, the Output window will name the exact
script and line — report it and it gets fixed.
