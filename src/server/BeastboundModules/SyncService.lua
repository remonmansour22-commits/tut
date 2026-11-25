-- Path: ServerScriptService/BeastboundModules/SyncService
-- Assembles and pushes the two snapshot types the HUD renders:
--   PlayerSync: personal (level, xp, inventory, quests, atlas)
--   WorldSync:  shared (journey, project, creature bond)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("BeastboundShared")
local Config = require(Shared.Config)
local QuestConfig = require(Shared.QuestConfig)

local SyncService = {}

local PlayerDataService, RemotesService, JourneyService, ProjectService, CreatureService, BuildingService

function SyncService.init(deps)
	PlayerDataService = deps.PlayerDataService
	RemotesService = deps.RemotesService
	JourneyService = deps.JourneyService
	ProjectService = deps.ProjectService
	CreatureService = deps.CreatureService
	BuildingService = deps.BuildingService
end

function SyncService.playerSnapshot(player)
	local profile = PlayerDataService.get(player)
	if not profile then
		return nil
	end

	local quest = QuestConfig.Quests[profile.quests.index]
	local xpFloor = Config.LevelXpThresholds[profile.level] or 0
	local xpCeiling = Config.LevelXpThresholds[profile.level + 1]

	return {
		level = profile.level,
		xp = profile.xp,
		xpFloor = xpFloor,
		xpCeiling = xpCeiling,
		inventory = profile.inventory,
		counts = profile.counts,
		discoveredLandmarks = profile.discoveredLandmarks,
		plots = profile.plots,
		provisional = PlayerDataService.isProvisional(player),
		quest = quest and {
			title = quest.Title,
			hint = quest.Hint,
			progress = profile.quests.progress,
			target = quest.Target,
		} or { title = QuestConfig.IdleTitle, hint = "", progress = 1, target = 1 },
		catalogue = BuildingService.buildCatalogueFor(player),
	}
end

function SyncService.worldSnapshot()
	return {
		journey = JourneyService.snapshot(),
		project = ProjectService.snapshot(),
		bond = CreatureService.bondSnapshot(),
	}
end

function SyncService.playerSync(player)
	local snapshot = SyncService.playerSnapshot(player)
	if snapshot then
		RemotesService.playerSync(player, snapshot)
	end
end

function SyncService.worldBroadcast()
	RemotesService.worldBroadcast(SyncService.worldSnapshot())
end

return SyncService
