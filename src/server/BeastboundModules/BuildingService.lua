-- Path: ServerScriptService/BeastboundModules/BuildingService
-- Plot-based construction. The server owns: costs, unlocks, ownership,
-- placement validity, rate limits. Clients only ever submit intentions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("BeastboundShared")
local Config = require(Shared.Config)
local BuildingConfig = require(Shared.BuildingConfig)
local AudioConfig = require(Shared.AudioConfig)

local Kit = require(script.Parent.BuilderKit)
local StructureBuilder = require(script.Parent.StructureBuilder)

local BuildingService = {}

local PlayerDataService, RemotesService, QuestService, ProgressionService, CreatureService, JourneyService, SyncService
local plots = {}           -- plotId -> pad part
local plotOccupants = {}   -- plotId -> { userId = n, structureId = s }
local lastBuild = {}       -- [player] = timestamp

function BuildingService.init(deps, worldHandle)
	PlayerDataService = deps.PlayerDataService
	RemotesService = deps.RemotesService
	QuestService = deps.QuestService
	ProgressionService = deps.ProgressionService
	CreatureService = deps.CreatureService
	JourneyService = deps.JourneyService
	SyncService = deps.SyncService

	for plotId, pad in pairs(worldHandle.plots) do
		plots[plotId] = pad
		plotOccupants[plotId] = nil
	end

	RemotesService.remote("BuildRequest").OnServerEvent:Connect(BuildingService.onBuildRequest)
end

--=====================================================================
-- Validation
--=====================================================================

local function costAffordable(profile, cost)
	for resourceId, amount in pairs(cost or {}) do
		if (profile.inventory[resourceId] or 0) < amount then
			return false
		end
	end
	return true
end

local function nearCharacter(player, position)
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return false
	end
	local dx = root.Position.X - position.X
	local dz = root.Position.Z - position.Z
	return math.sqrt(dx * dx + dz * dz) <= 30
end

function BuildingService.onBuildRequest(player, structureId, plotId, rotationStep)
	if type(structureId) ~= "string" or type(plotId) ~= "string" or type(rotationStep) ~= "number" then
		return
	end

	local now = os.clock()
	if lastBuild[player] and now - lastBuild[player] < Config.BuildRateLimitSeconds then
		return
	end
	lastBuild[player] = now

	local pad = plots[plotId]
	if not pad then
		return
	end
	if type(rotationStep) ~= "number" or rotationStep % 1 ~= 0 or rotationStep < 0 or rotationStep >= Config.MaxRotationSteps then
		return
	end
	if not nearCharacter(player, pad.Position) then
		RemotesService.toast(player, "Too far", "Walk up to the plot you want to build on.", "warn")
		return
	end

	local occupant = plotOccupants[plotId]
	if occupant and occupant.userId ~= player.UserId then
		RemotesService.toast(player, "Plot occupied", "Another wayfarer already built here.", "warn")
		return
	end

	local def = BuildingConfig.ById[structureId]
	if not def then
		return
	end

	local profile = PlayerDataService.get(player)
	if not profile then
		return
	end
	if profile.level < (def.UnlockLevel or 1) then
		RemotesService.toast(player, "Locked", def.DisplayName .. " requires level " .. tostring(def.UnlockLevel) .. ".", "warn")
		return
	end
	if not costAffordable(profile, def.Cost) then
		RemotesService.toast(player, "Not enough resources", "You need more materials for " .. def.DisplayName .. ".", "warn")
		return
	end

	for resourceId, amount in pairs(def.Cost or {}) do
		if not PlayerDataService.takeItem(player, resourceId, amount) then
			return -- re-validated to defeat races between count and take
		end
	end

	-- all checks passed: place
	plotOccupants[plotId] = { userId = player.UserId, structureId = structureId }
	pad:SetAttribute("OwnerUserId", player.UserId)
	pad:SetAttribute("StructureId", structureId)
	PlayerDataService.markPlot(player, plotId, structureId)

	local model = StructureBuilder.build(structureId, pad.CFrame, rotationStep)
	model:SetAttribute("OwnerUserId", player.UserId)
	model:SetAttribute("OwnerName", player.DisplayName)
	model.Parent = pad.Parent

	local label = Instance.new("BillboardGui")
	label.Name = "OwnerLabel"
	label.Size = UDim2.fromScale(6, 1.4)
	label.StudsOffset = Vector3.new(0, 8, 0)
	label.MaxDistance = 60
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamMedium
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(230, 240, 230)
	text.TextStrokeTransparency = 0.6
	text.Text = def.DisplayName .. " — " .. player.DisplayName
	text.Parent = label
	label.Parent = model:FindFirstChildWhichIsA("BasePart")

	StructureBuilder.fadeIn(model, 1.4)
	Kit.playSoundAt(pad.Position, AudioConfig.Build)
	Kit.sparkle(pad, Color3.fromRGB(200, 230, 200), 10, 6, 1)

	profile.counts.built += 1
	ProgressionService.award(player, Config.XpRewards.Build)
	CreatureService.addBond(def.BondGain or 1)
	JourneyService.addMomentum(Config.JourneyMomentumPerBuild)
	CreatureService.react("build", pad.Position)
	QuestService.mark(player, "build")
	SyncService.playerSync(player)
	RemotesService.toast(player, "Built: " .. def.DisplayName, "+" .. Config.XpRewards.Build .. " XP", "build")
end

--=====================================================================
-- Join-in-progress: returning players reclaim their structures
--=====================================================================

function BuildingService.restoreFromProfile(player)
	local profile = PlayerDataService.get(player)
	if not profile then
		return
	end
	for plotId, structureId in pairs(profile.plots) do
		local pad = plots[plotId]
		if pad and BuildingConfig.ById[structureId] and plotOccupants[plotId] == nil then
			plotOccupants[plotId] = { userId = player.UserId, structureId = structureId }
			pad:SetAttribute("OwnerUserId", player.UserId)
			pad:SetAttribute("StructureId", structureId)
			local model = StructureBuilder.build(structureId, pad.CFrame, 0)
			model:SetAttribute("OwnerUserId", player.UserId)
			model:SetAttribute("OwnerName", player.DisplayName)
			model.Parent = pad.Parent
			for _, part in ipairs(model:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Transparency = 0
				end
			end
		end
	end
end

function BuildingService.buildCatalogueFor(player)
	local profile = PlayerDataService.get(player)
	local catalogue = {}
	for _, id in ipairs(BuildingConfig.Order) do
		local def = BuildingConfig.ById[id]
		local unlocked = profile and profile.level >= (def.UnlockLevel or 1)
		table.insert(catalogue, {
			id = def.Id,
			name = def.DisplayName,
			category = def.Category,
			description = def.Description,
			cost = def.Cost,
			unlockLevel = def.UnlockLevel,
			unlocked = unlocked == true,
		})
	end
	return catalogue
end

return BuildingService
