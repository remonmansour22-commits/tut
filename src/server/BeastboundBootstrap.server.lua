-- Path: ServerScriptService/BeastboundBootstrap (Script)
-- Milestone vertical-slice entry point: builds the world, wires every
-- service once, then handles player lifecycle.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = script.Parent:WaitForChild("BeastboundModules")
local RemotesService = require(Modules.RemotesService)
local WorldBuilder = require(Modules.WorldBuilder)
local CreatureService = require(Modules.CreatureService)
local JourneyService = require(Modules.JourneyService)
local SyncService = require(Modules.SyncService)
local QuestService = require(Modules.QuestService)
local InteractionService = require(Modules.InteractionService)
local BuildingService = require(Modules.BuildingService)
local ProjectService = require(Modules.ProjectService)
local ProgressionService = require(Modules.ProgressionService)
local PlayerDataService = require(Modules.PlayerDataService)

-- 1. Remotes must exist before any client asks for them.
RemotesService.init()

-- 2. Build the shared world once per server.
local world = WorldBuilder.build()

-- 3. Services (explicit dependency graph, no require cycles).
local deps = {
	RemotesService = RemotesService,
	PlayerDataService = PlayerDataService,
	ProgressionService = ProgressionService,
	QuestService = QuestService,
	InteractionService = InteractionService,
	BuildingService = BuildingService,
	ProjectService = ProjectService,
	CreatureService = CreatureService,
	JourneyService = JourneyService,
	SyncService = SyncService,
}

CreatureService.init(world)
ProgressionService.init(deps)
QuestService.init(deps)
SyncService.init(deps)
JourneyService.init(deps, world)
InteractionService.init(deps, world)
InteractionService.setProjectService(ProjectService)
BuildingService.init(deps, world)
ProjectService.init(deps, world)

-- 4. Creature bond reacts to milestones; push world state on level-ups.
CreatureService.onBondChanged(function(_level)
	SyncService.worldBroadcast()
end)

-- 5. Player lifecycle (join-in-progress: full snapshot on load; returning
-- players get their structures rebuilt on their plots).
PlayerDataService.setOnProfileReady(function(player)
	BuildingService.restoreFromProfile(player)
	SyncService.playerSync(player)
	SyncService.worldBroadcast()
end)

local function onPlayerAdded(player)
	PlayerDataService.setupPlayer(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

-- 6. Persistence heartbeat.
PlayerDataService.startAutosave()

print("[Beastbound] The Great Migration — server systems online. Aruun is walking.")
