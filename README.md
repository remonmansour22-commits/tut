# BEASTBOUND: THE GREAT MIGRATION — Vertical Slice

A complete, code-only Roblox vertical slice: everything (world, creature, UI, sounds)
is generated from the scripts in this folder. No models, meshes, images, or Rojo
mapping are required to run it.

---

## How to install the engine

> Important: **DataStores only work in a published game.** Build in Studio for
> visuals, then publish (File → Publish to Roblox) before testing saves. Also
> enable **Game Settings → Security → "Enable Studio Access to API Services"**
> to hit the DataStore from Studio playtests.

### Option A — Download the built place file from GitHub (zero install)

Every push to `main` runs a GitHub Actions workflow (`.github/workflows/rojo-build.yml`)
that compiles `default.project.json` into `build/Beastbound_TheGreatMigration.rbxlx` with
Rojo and uploads it as a build artifact. To get it: open the repo on GitHub →
**Actions** → the latest "Build Roblox place file" run → **Artifacts** →
download `Beastbound_TheGreatMigration` → unzip → open the `.rbxlx` in Studio.

### Option B — One-paste GitHub loader (no Rojo, live from this repo)

`tools/load_from_github.lua` rebuilds the whole script tree inside an open Studio place
by fetching the latest `src/**` files from GitHub:

1. Open any place in Studio and enable **Game Settings → Security → Allow HTTP Requests**.
2. Copy the entire contents of `tools/load_from_github.lua` into the **Command Bar**
   (View → Command Bar) and press Enter.
3. Watch the Output window; when it prints `DONE — N scripts loaded`, press Play.

It creates the same mapping as `default.project.json`: `src/shared` →
`ReplicatedStorage.BeastboundShared`, `src/server` → `ServerScriptService`
(`BeastboundBootstrap` as a Script, everything else as ModuleScripts under
`BeastboundModules`), `src/client` → `StarterPlayerScripts` as LocalScripts.
Re-running it refreshes scripts to the newest GitHub state.

### Option C — Rojo live sync (fastest iteration)

If you have Rojo installed: clone this repo, run `rojo serve default.project.json`,
install the Rojo plugin in Studio and press **Connect** — edits to `src/` sync into
Studio instantly. Or build once with `rojo build -o Beastbound.rbxlx`.

### Option D — Manual paste into Studio (about 10 minutes)

Create empty Folders/Instances first, then paste each script.

1. In **ReplicatedStorage**: create a **Folder** named `BeastboundShared`.
2. In **ServerScriptService**: create a **Folder** named `BeastboundModules`.
3. Paste the scripts below. The instance **Name** must match the file name
   (without `.lua` / `.client.lua` / `.server.lua`). The type matters:

| Instance in Studio | Type | Source file |
|---|---|---|
| `ReplicatedStorage/BeastboundShared/Config` | ModuleScript | `src/shared/Config.lua` |
| `ReplicatedStorage/BeastboundShared/Net` | ModuleScript | `src/shared/Net.lua` |
| `ReplicatedStorage/BeastboundShared/ResourceConfig` | ModuleScript | `src/shared/ResourceConfig.lua` |
| `ReplicatedStorage/BeastboundShared/BuildingConfig` | ModuleScript | `src/shared/BuildingConfig.lua` |
| `ReplicatedStorage/BeastboundShared/BiomeConfig` | ModuleScript | `src/shared/BiomeConfig.lua` |
| `ReplicatedStorage/BeastboundShared/QuestConfig` | ModuleScript | `src/shared/QuestConfig.lua` |
| `ReplicatedStorage/BeastboundShared/AudioConfig` | ModuleScript | `src/shared/AudioConfig.lua` |
| `ReplicatedStorage/BeastboundShared/Types` | ModuleScript | `src/shared/Types.lua` |
| `ServerScriptService/BeastboundBootstrap` | **Script** (not Module) | `src/server/BeastboundModules/BeastboundBootstrap.server.lua` |
| `ServerScriptService/BeastboundModules/BuilderKit` | ModuleScript | `src/server/BeastboundModules/BuilderKit.lua` |
| `ServerScriptService/BeastboundModules/StructureBuilder` | ModuleScript | `src/server/BeastboundModules/StructureBuilder.lua` |
| `ServerScriptService/BeastboundModules/WorldBuilder` | ModuleScript | `src/server/BeastboundModules/WorldBuilder.lua` |
| `ServerScriptService/BeastboundModules/RemotesService` | ModuleScript | `src/server/BeastboundModules/RemotesService.lua` |
| `ServerScriptService/BeastboundModules/PlayerDataService` | ModuleScript | `src/server/BeastboundModules/PlayerDataService.lua` |
| `ServerScriptService/BeastboundModules/ProgressionService` | ModuleScript | `src/server/BeastboundModules/ProgressionService.lua` |
| `ServerScriptService/BeastboundModules/CreatureService` | ModuleScript | `src/server/BeastboundModules/CreatureService.lua` |
| `ServerScriptService/BeastboundModules/InteractionService` | ModuleScript | `src/server/BeastboundModules/InteractionService.lua` |
| `ServerScriptService/BeastboundModules/BuildingService` | ModuleScript | `src/server/BeastboundModules/BuildingService.lua` |
| `ServerScriptService/BeastboundModules/ProjectService` | ModuleScript | `src/server/BeastboundModules/ProjectService.lua` |
| `ServerScriptService/BeastboundModules/JourneyService` | ModuleScript | `src/server/BeastboundModules/JourneyService.lua` |
| `ServerScriptService/BeastboundModules/QuestService` | ModuleScript | `src/server/BeastboundModules/QuestService.lua` |
| `ServerScriptService/BeastboundModules/SyncService` | ModuleScript | `src/server/BeastboundModules/SyncService.lua` |
| `StarterPlayer/StarterPlayerScripts/IntroController` | **LocalScript** | `src/client/IntroController.client.lua` |
| `StarterPlayer/StarterPlayerScripts/BuildingController` | **LocalScript** | `src/client/BuildingController.client.lua` |
| `StarterPlayer/StarterPlayerScripts/HUDController` | **LocalScript** | `src/client/HUDController.client.lua` |

Notes:
- Every file also has its intended path on line 1 as a comment.
- `Types.lua` is a reference module; paste it even though nothing requires it yet.
- Paste ModuleScripts by opening the file, selecting all (`Ctrl+A`, `Ctrl+C`),
  then in Studio right-click the target folder → Insert Object → ModuleScript,
  and paste over its default contents.

### Studio settings

- **Game Settings → Security → Enable Studio Access to API Services: ON**
  (required for DataStore saves to work from Studio).
- Do **not** enable StreamingEnabled (creature and plots are workspace-scoped).
- Leave default character settings; spawn location is created on Aruun's back
  at runtime, so you do not need to place any parts manually.

---

## What the slice contains (the Part-16 checklist)

1. **One enormous creature** — Aruun: terraced body, belly, neck/head, tail, sails,
   horns, bioluminescent strips, all anchored + Motor6D-driven.
2. **One starting biome** — Mosslight Meadow (tweened lighting, atmosphere, tint groups).
3. **One settlement** — heartroot altar, signpost, spawn plaza, build plots.
4. **Three resource types** — Driftwood, Stone, Glowseed.
5. **Three collectible interactions** — Driftwood/Stone/Glowseed nodes via
   server-side ProximityPrompts (PC/controller/mobile agnostic).
6. **Working inventory** — server-authoritative profile with validated adds/takes.
7. **Three structures** — Basic Shelter, Lookout Tower, Resonance Beacon.
8. **Building placement** — ghost preview, rotation, free-pad targeting, full
   server validation (cost/unlock/distance/ownership/rate limit).
9. **One shared project** — the Heartroot restoration orb (server-wide contributions).
10. **Creature reactions** — breathing, sway, head look-at, gather/build/contribute/
    discovery reactions, glow waves, bond levels.
11. **Journey progression** — momentum, milestones, next-destination state.
12. **Visible biome transition** — stage tweens of lighting + all tint groups.
13. **Basic progression** — XP, levels, leaderstats, unlock gates on structures.
14. **Functional UI** — HUD (level/XP, resources, quest, journey, bond, project),
    Atlas panel, toast stack, build panel — all generated in code, all mobile-safe.
15. **Multiplayer sync** — PlayerSync/WorldSync snapshots, shared project + journey
    state, late-joiners get full state (`restoreFromProfile`).
16. **Data saving** — DataStore `Beastbound_PlayerData_v1`, UpdateAsync, autosave,
    PlayerRemoving/BindToClose saves, load-failure protection (never overwrites
    real data with a fresh profile).

## Verification status (honest)

- ✅ All 25 Luau files pass a structural block-balance check (`tools/lua_block_check.py`).
- ✅ Cross-checked: every service API that Bootstrap or other services call is defined;
  every `Net.*` remote name used on client matches server creation; workspace paths
  (`workspace/Aruun/BuildPlots`) match what WorldBuilder creates.
- ⚠️ **Nothing has been run inside Roblox Studio** — this sandbox has no Studio
  access. Treat the first Studio playtest as Milestone 8: the checklist below is
  what to run, and report any errors you see in the Output window.

## First-session flow (what the player sees)

Minutes 0–1: skippable cinematic title + camera fly-in to Aruun. Minutes 1–3:
gather Glowseeds, contribute to the Heartroot (shared project). Minutes 3–6:
unlock + build the Basic Shelter via the build panel. Minutes 6–10: discover
landmarks (Tail Spire, Hidden Garden, Lantern Crest — Atlas entries). Minutes
10–15: Heartroot completes — species-wide bloom, bonus XP, creature glow wave.
15–30: journey milestones push toward the Glasswind Expanse stage transition.

## Tuning knobs (all config-driven)

- `src/shared/Config.lua` — XP curve, momentum rates, bond rates, Heartroot target.
- `src/shared/ResourceConfig.lua` — nodes, respawn, yields.
- `src/shared/BuildingConfig.lua` — structures, costs, unlock levels,
  construction XP, bond gains.
- `src/shared/BiomeConfig.lua` — stage palettes/environments; landmark positions.
- `src/shared/QuestConfig.lua` — the objective chain (add tags freely; `QuestService.mark()` drives it).

## Known placeholders

- **Sounds** are engine-bundled `rbxasset://sounds/...` files (quieter than real assets).
- Creature skin is currently part-color/particle work in `WorldBuilder` — a mesh
  pass later will replace only geometry, not services.
- Solo professions are framework-ready but not yet wired (out of slice scope).

## Test checklist (run all in Studio before shipping)

- [ ] Single-player: intro plays/renders, HUD updates, all 3 node types gather.
- [ ] Build all three structures on a plot; costs deducted; fade-in plays.
- [ ] Rotation + free-pad targeting for the structure ghost.
- [ ] Heartroot: contribute until the orb completes; toast + bloom.
- [ ] Atlas panel fills as landmarks are discovered.
- [ ] 2-player server (Studio "Local Server → 2 players"): both see shared project
  and journey progress; helping each other doesn't desync.
- [ ] Late joiner: second client joins mid-session → gets plot structures + full HUD.
- [ ] Rejoin after leaving: level/inventory/plot structures restored from DataStore.
- [ ] Deliberately break one build request (out of range / insufficient funds) →
  denied server-side, no errors.
- [ ] Mobile tap: gather prompts, build confirm, HUD readability on a phone layout.
- [ ] Performance: ~6 clients, stable frame rate, creature animation smooth.
