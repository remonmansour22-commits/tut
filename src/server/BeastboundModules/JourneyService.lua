-- Path: ServerScriptService/BeastboundModules/JourneyService
-- Community migration: momentum accrues from builds, discoveries, projects
-- and time. Crossing a threshold triggers a full biome transition —
-- Lighting, Atmosphere, world palette, signpost and creature reaction.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Shared = ReplicatedStorage:WaitForChild("BeastboundShared")
local Config = require(Shared.Config)
local BiomeConfig = require(Shared.BiomeConfig)
local AudioConfig = require(Shared.AudioConfig)

local Kit = require(script.Parent.BuilderKit)

local JourneyService = {}

local PlayerDataService, RemotesService, QuestService, CreatureService, SyncService
local world

local stage = 0 -- 0 = "not yet started"; bootstrap calls applyStage(1)
local momentum = 0

function JourneyService.init(deps, worldHandle)
	PlayerDataService = deps.PlayerDataService
	RemotesService = deps.RemotesService
	QuestService = deps.QuestService
	CreatureService = deps.CreatureService
	SyncService = deps.SyncService
	world = worldHandle

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	world.atmosphere = atmosphere

	JourneyService.applyStage(1)
	JourneyService.startPassiveMomentum()
end

function JourneyService.snapshot()
	local current = BiomeConfig.Stages[math.max(stage, 1)]
	local nextStage = BiomeConfig.Stages[stage + 1]
	return {
		stage = math.max(stage, 1),
		name = current and current.Name or "Mosslight Meadow",
		headline = current and current.Headline or "",
		momentum = math.floor(momentum),
		target = nextStage and nextStage.MomentumTarget or current and current.MomentumTarget or 0,
		finalStage = nextStage == nil,
	}
end

function JourneyService.startPassiveMomentum()
	task.spawn(function()
		while true do
			task.wait(60)
			JourneyService.addMomentum(Config.JourneyMomentumPerMinute)
		end
	end)
end

function JourneyService.addMomentum(amount)
	if amount <= 0 then
		return
	end
	momentum += amount

	local nextStage = BiomeConfig.Stages[stage + 1]
	if nextStage and momentum >= nextStage.MomentumTarget then
		JourneyService.advance()
		return
	end
	SyncService.worldBroadcast()
end

function JourneyService.advance()
	stage += 1
	JourneyService.applyStage(stage)
	CreatureService.react("stage")
	RemotesService.toastAll("Migration onward", "Aruun strides into " .. (BiomeConfig.Stages[stage].Name or "new lands") .. ".", "journey")
	QuestService.broadcastServerEvent("journey")
	SyncService.worldBroadcast()
end

--=====================================================================
-- Biome transition
--=====================================================================

local function tweenLighting(thresholds)
	local env = thresholds.Environment
	local lightingInfo = TweenInfo.new(8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)
	for key, value in pairs(env) do
		if key == "FogColor" then
			TweenService:Create(Lighting, lightingInfo, { FogColor = value, FogEnd = env.FogEnd or 900 }):Play()
		elseif key ~= "FogEnd" then
			TweenService:Create(Lighting, lightingInfo, { [key] = value }):Play()
		end
	end

	local atmo = thresholds.Atmosphere
	if world.atmosphere then
		TweenService:Create(world.atmosphere, lightingInfo, atmo):Play()
	end
end

function JourneyService.applyStage(index)
	local thresholds = BiomeConfig.Stages[index]
	if not thresholds then
		return
	end
	stage = index
	tweenLighting(thresholds)

	-- recolor the tintable world groups toward the new palette
	local palette = thresholds.Palette
	local tintTargets = {
		FoliageTint = palette.FoliageTint,
		GroundTint = palette.GroundTint,
		AccentTint = palette.AccentTint,
	}
	for group, color in pairs(tintTargets) do
		for _, part in ipairs(world.tintGroups[group] or {}) do
			if part.Parent then
				TweenService:Create(part, TweenInfo.new(6, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Color = color }):Play()
			end
		end
	end

	-- update the in-world signpost label
	if world.refs.signLabel then
		world.refs.signLabel.Text = thresholds.Name
	end
end

return JourneyService
