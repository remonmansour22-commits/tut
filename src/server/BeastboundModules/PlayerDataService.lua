-- Path: ServerScriptService/BeastboundModules/PlayerDataService
-- Server-authoritative player profiles: loading, validation, mutation API,
-- autosave, leave/shutdown saves. Persistent progress only; no session state.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("BeastboundShared")
local Config = require(Shared.Config)
local ResourceConfig = require(Shared.ResourceConfig)

local SCHEMA_VERSION = 1

local PlayerDataService = {}

local profiles = {}      -- [player] = profile
local loadFailed = {}    -- [player] = true => do not overwrite stored data
local dataStore = nil

pcall(function()
	dataStore = DataStoreService:GetDataStore(Config.DataStoreName)
end)

--=====================================================================
-- Profile shape
--=====================================================================

local function freshProfile()
	return {
		schemaVersion = SCHEMA_VERSION,
		level = 1,
		xp = 0,
		inventory = { Driftwood = 0, Stone = 0, Glowseed = 0 },
		counts = { gathered = 0, built = 0, contributed = 0, discoveries = 0 },
		discoveredLandmarks = {},
		plots = {},
		quests = { index = 1, progress = 0 },
		journeyStageSeen = 1,
	}
end

local function validResourceName(name)
	return ResourceConfig.ById[name] ~= nil
end

local function validate(profile)
	if type(profile) ~= "table" then
		return nil
	end
	local clean = freshProfile()

	clean.level = math.clamp(tonumber(profile.level) or 1, 1, #Config.LevelXpThresholds)
	clean.xp = math.max(tonumber(profile.xp) or 0, 0)
	clean.journeyStageSeen = math.max(tonumber(profile.journeyStageSeen) or 1, 1)

	if type(profile.inventory) == "table" then
		for key, value in pairs(profile.inventory) do
			if validResourceName(key) and type(value) == "number" then
				clean.inventory[key] = math.clamp(math.floor(value), 0, 9999)
			end
		end
	end
	if type(profile.counts) == "table" then
		for key, value in pairs(profile.counts) do
			if type(value) == "number" then
				clean.counts[key] = math.clamp(math.floor(value), 0, 1e9)
			end
		end
	end
	if type(profile.discoveredLandmarks) == "table" then
		for key, value in pairs(profile.discoveredLandmarks) do
			if value == true then
				clean.discoveredLandmarks[tostring(key)] = true
			end
		end
	end
	if type(profile.plots) == "table" then
		for key, value in pairs(profile.plots) do
			if type(key) == "string" and type(value) == "string" then
				clean.plots[key] = value
			end
		end
	end
	if type(profile.quests) == "table" then
		clean.quests.index = math.clamp(tonumber(profile.quests.index) or 1, 1, 99)
		clean.quests.progress = math.max(tonumber(profile.quests.progress) or 0, 0)
	end

	return clean
end

--=====================================================================
-- Persistence
--=====================================================================

local function loadProfile(player)
	if not dataStore then
		return freshProfile()
	end
	local ok, stored = pcall(function()
		return dataStore:GetAsync("player_" .. player.UserId)
	end)
	if not ok then
		warn("[PlayerDataService] load failed for " .. player.Name .. "; profile is provisional")
		loadFailed[player] = true
		return freshProfile()
	end
	if type(stored) ~= "table" or stored.schemaVersion ~= SCHEMA_VERSION then
		-- migrate hook: future schema upgrades convert stored data here
		return freshProfile()
	end
	local clean = validate(stored)
	if not clean then
		loadFailed[player] = true
		return freshProfile()
	end
	return clean
end

local function saveProfile(player, force)
	local profile = profiles[player]
	if not profile then
		return
	end
	if loadFailed[player] and not force then
		-- never overwrite real data with a profile we could not load
		return
	end
	if not dataStore then
		return
	end
	local budget = force and Config.MaxSaveRetries or 1
	for attempt = 1, budget do
		local ok, err = pcall(function()
			dataStore:UpdateAsync("player_" .. player.UserId, function(stored)
				-- stored is never trusted; we always persist our validated profile
				local _ = stored
				return profile
			end)
		end)
		if ok then
			loadFailed[player] = nil
			return true
		end
		warn("[PlayerDataService] save failed (attempt " .. attempt .. "): " .. tostring(err))
		if not force then
			break
		end
		task.wait(1)
	end
	return false
end

--=====================================================================
-- Mutation API (the only way gameplay code touches a profile)
--=====================================================================

function PlayerDataService.get(player)
	return profiles[player]
end

function PlayerDataService.addItem(player, resourceId, amount)
	local profile = profiles[player]
	if not profile or not validResourceName(resourceId) then
		return 0
	end
	amount = math.clamp(math.floor(amount), 0, 9999)
	profile.inventory[resourceId] = (profile.inventory[resourceId] or 0) + amount
	return profile.inventory[resourceId]
end

function PlayerDataService.takeItem(player, resourceId, amount)
	local profile = profiles[player]
	if not profile or not validResourceName(resourceId) then
		return false
	end
	amount = math.clamp(math.floor(amount), 0, 9999)
	local held = profile.inventory[resourceId] or 0
	if held < amount then
		return false
	end
	profile.inventory[resourceId] = held - amount
	return true
end

function PlayerDataService.countItem(player, resourceId)
	local profile = profiles[player]
	if not profile then
		return 0
	end
	return profile.inventory[resourceId] or 0
end

function PlayerDataService.markPlot(player, plotId, structureId)
	local profile = profiles[player]
	if profile then
		profile.plots[plotId] = structureId
	end
end

function PlayerDataService.isProvisional(player)
	return loadFailed[player] == true
end

--=====================================================================
-- Lifecycle
--=====================================================================

local onProfileReady -- callback set by Bootstrap (UI snapshot push)

function PlayerDataService.setOnProfileReady(callback)
	onProfileReady = callback
end

function PlayerDataService.setupPlayer(player)
	local profile = loadProfile(player)
	profiles[player] = profile

	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	leaderstats.Parent = player
	local level = Instance.new("IntValue")
	level.Name = "Level"
	level.Value = profile.level
	level.Parent = leaderstats

	if onProfileReady then
		task.spawn(onProfileReady, player, profile)
	end
end

function PlayerDataService.updateLeaderstat(player)
	local profile = profiles[player]
	local leaderstats = player:FindFirstChild("leaderstats")
	local level = leaderstats and leaderstats:FindFirstChild("Level")
	if profile and level then
		level.Value = profile.level
	end
end

function PlayerDataService.startAutosave()
	task.spawn(function()
		while true do
			task.wait(Config.AutosaveIntervalSeconds)
			for _, player in ipairs(Players:GetPlayers()) do
				saveProfile(player, false)
			end
		end
	end)
end

Players.PlayerRemoving:Connect(function(player)
	saveProfile(player, true)
	profiles[player] = nil
	loadFailed[player] = nil
end)

game:BindToClose(function()
	if RunService:IsStudio() then
		return
	end
	for _, player in ipairs(Players:GetPlayers()) do
		saveProfile(player, true)
	end
end)

PlayerDataService.freshProfile = freshProfile

return PlayerDataService
