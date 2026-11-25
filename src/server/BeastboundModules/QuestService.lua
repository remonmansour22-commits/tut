-- Path: ServerScriptService/BeastboundModules/QuestService
-- Sequential objective chain per player. One active objective at a time;
-- tags map gameplay events to progress. Cheap and perfectly broadcastable.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("BeastboundShared")
local QuestConfig = require(Shared.QuestConfig)

local QuestService = {}

local PlayerDataService, RemotesService, ProgressionService, SyncService

function QuestService.init(deps)
	PlayerDataService = deps.PlayerDataService
	RemotesService = deps.RemotesService
	ProgressionService = deps.ProgressionService
	SyncService = deps.SyncService
end

--=====================================================================

local function activeQuest(profile)
	if not profile then
		return nil
	end
	return QuestConfig.Quests[profile.quests.index]
end

function QuestService.mark(player, tag)
	local profile = PlayerDataService.get(player)
	if not profile then
		return
	end
	local quest = activeQuest(profile)
	if not quest or quest.Tag ~= tag then
		return
	end

	profile.quests.progress += 1
	if profile.quests.progress >= quest.Target then
		profile.quests.index += 1
		profile.quests.progress = 0
		ProgressionService.award(player, quest.RewardXp)
		RemotesService.toast(player, "Objective complete", quest.Title .. "  (+" .. quest.RewardXp .. " XP)", "quest")
	else
		RemotesService.toast(player, quest.Title, profile.quests.progress .. " / " .. quest.Target, "quest")
	end
	SyncService.playerSync(player)
end

function QuestService.broadcastServerEvent(tag, excludes)
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		if not (excludes and excludes[player]) then
			QuestService.mark(player, tag)
		end
	end
end

return QuestService
