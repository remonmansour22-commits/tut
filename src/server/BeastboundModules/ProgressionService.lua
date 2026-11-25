-- Path: ServerScriptService/BeastboundModules/ProgressionService
-- XP + levels. Levels only gate unlocks; nothing is purchasable here.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("BeastboundShared")
local Config = require(Shared.Config)

local ProgressionService = {}

local PlayerDataService
local RemotesService
local SyncService

function ProgressionService.init(deps)
	PlayerDataService = deps.PlayerDataService
	RemotesService = deps.RemotesService
	SyncService = deps.SyncService
end

function ProgressionService.award(player, amount, reason)
	local profile = PlayerDataService.get(player)
	if not profile or amount <= 0 then
		return nil
	end

	profile.xp += math.floor(amount)
	local leveled = false

	while profile.level < #Config.LevelXpThresholds do
		local needed = Config.LevelXpThresholds[profile.level + 1]
		if profile.xp >= needed then
			profile.level += 1
			leveled = true
			RemotesService.toast(player, "Level " .. profile.level, "The settlement grows stronger.", "reward")
		else
			break
		end
	end

	PlayerDataService.updateLeaderstat(player)
	if leveled then
		SyncService.playerSync(player)
	end
	return profile.level
end

return ProgressionService
