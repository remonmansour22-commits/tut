-- UNIT CLASH - progression: XP, levels, unit unlocks, mastery, campaign
-- progress, saved setups. DataStore when published; in-memory fallback in
-- Studio so nothing errors before API access is enabled.

local Players = game:GetService("Players")
local UCConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("UCShared"):WaitForChild("UCConfig"))

local UCProgress = {}

local store = nil
pcall(function()
	store = game:GetService("DataStoreService"):GetDataStore("UC_PROGRESS_V1")
end)

local memory = {}

local function keyFor(player)
	return "P_" .. player.UserId
end

function UCProgress.load(player)
	local key = keyFor(player)
	if store then
		local ok, saved = pcall(function()
			return store:GetAsync(key)
		end)
		if ok and saved then
			memory[key] = saved
			return saved
		end
	end
	if not memory[key] then
		memory[key] = { xp = 0, mastery = {}, campaign = 1, setups = {} }
	end
	return memory[key]
end

function UCProgress.save(player, profile)
	local key = keyFor(player)
	memory[key] = profile
	if store then
		pcall(function()
			store:SetAsync(key, profile)
		end)
	end
end

function UCProgress.awardBattle(player, profile, won)
	profile.xp = profile.xp + 10 + (won and 25 or 0)
	UCProgress.save(player, profile)
end

function UCProgress.trackMastery(player, profile, typesUsed)
	for _, t in ipairs(typesUsed) do
		profile.mastery[t] = (profile.mastery[t] or 0) + 1
	end
	UCProgress.save(player, profile)
end

function UCProgress.isUnlocked(profile, unitId)
	local def = UCConfig.get(unitId)
	return def and UCConfig.levelFor(profile.xp) >= (def.unlockLevel or 1)
end

function UCProgress.campaignUnlocked(profile, index)
	return index <= (profile.campaign or 1)
end

function UCProgress.completeCampaign(player, profile, index)
	if index >= (profile.campaign or 1) and index < #UCConfig.MISSIONS then
		profile.campaign = index + 1
	end
	UCProgress.save(player, profile)
end

function UCProgress.savedSetups(profile)
	return profile.setups or {}
end

function UCProgress.saveSetup(player, profile, name, config)
	profile.setups = profile.setups or {}
	profile.setups[name] = { config = config, at = os.time() }
	UCProgress.save(player, profile)
end

function UCProgress.deleteSetup(player, profile, name)
	if profile.setups then
		profile.setups[name] = nil
		UCProgress.save(player, profile)
	end
end

function UCProgress.onLeave(player)
	if memory[keyFor(player)] and store then
		pcall(function()
			store:SetAsync(keyFor(player), memory[keyFor(player)])
		end)
	end
end

Players.PlayerRemoving:Connect(UCProgress.onLeave)

return UCProgress
