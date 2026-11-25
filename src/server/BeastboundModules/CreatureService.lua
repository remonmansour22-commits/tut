-- Path: ServerScriptService/BeastboundModules/CreatureService
-- Aruun's life signals: breathing/sway rig animation via Motor6D.Transform,
-- reactions to gameplay events, community bond level, glow feedback.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("BeastboundShared")
local Config = require(Shared.Config)
local AudioConfig = require(Shared.AudioConfig)

local Kit = require(script.Parent.BuilderKit)

local CreatureService = {}

local world
local state = {
	bondPoints = 0,
	bondLevel = 1,
	reaction = 0,       -- 0..1 decaying envelope
	reactionKind = nil,
	headLook = nil,     -- Vector3 interest point
	headLookUntil = 0,
}
local BondLevels = {
	[1] = "Distant",
	[2] = "Aware",
	[3] = "Trusting",
	[4] = "Entwined",
	[5] = "Kindred",
	[6] = "Bonded",
	[7] = "One Path",
	[8] = "One Heart",
}
local bondListeners = {}

function CreatureService.init(worldHandle)
	world = worldHandle
	RunService.Heartbeat:Connect(CreatureService.onHeartbeat)
end

function CreatureService.onBondChanged(callback)
	table.insert(bondListeners, callback)
end

function CreatureService.bondSnapshot()
	return {
		level = state.bondLevel,
		name = BondLevels[state.bondLevel] or "Bonded",
		points = state.bondPoints,
	}
end

--=====================================================================
-- Reactions
--=====================================================================

local Reactions = {
	gather = { pitch = 0.14, yaw = 0.05, duration = 1.4, sound = AudioConfig.Gather, look = true },
	build = { pitch = 0.3, yaw = 0.14, duration = 2.6, sound = AudioConfig.CreaturePurr, look = true },
	contribute = { pitch = 0.4, yaw = 0.1, duration = 3, sound = AudioConfig.CreaturePurr, glow = true },
	discover = { pitch = 0.22, yaw = 0.2, duration = 2.4, sound = AudioConfig.Discover, look = true },
	stage = { pitch = 0.5, yaw = 0.3, duration = 5, sound = AudioConfig.CreatureCall },
	restored = { pitch = 0.7, yaw = 0.5, duration = 6, sound = AudioConfig.ProjectComplete, glow = true },
}

function CreatureService.react(kind, atPosition)
	local reaction = Reactions[kind]
	if not reaction or not world then
		return
	end
	state.reaction = 1
	state.reactionKind = kind
	state.reactionUntil = os.clock() + reaction.duration

	if reaction.look and atPosition then
		state.headLook = atPosition
		state.headLookUntil = os.clock() + reaction.duration
	end

	if reaction.sound and world.refs.lantern then
		Kit.playSoundAt(world.refs.lantern.Position, reaction.sound)
	end

	if reaction.glow then
		CreatureService.glowWave()
	end
end

function CreatureService.glowWave()
	if not world or not world.tintGroups then
		return
	end
	for _, part in ipairs(world.tintGroups.AccentTint) do
		if part:IsDescendantOf(workspace) then
			local original = part.Transparency
			local tween = TweenService:Create(part, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = math.max(original - 0.3, 0),
			})
			tween:Play()
			task.delay(1.2, function()
				if part.Parent then
					TweenService:Create(part, TweenInfo.new(1.4), { Transparency = original }):Play()
				end
			end)
		end
	end
end

--=====================================================================
-- Bond
--=====================================================================

function CreatureService.addBond(amount)
	state.bondPoints += amount
	local newLevel = math.clamp(1 + math.floor(state.bondPoints / 30), 1, Config.BondMaxLevel)
	if newLevel > state.bondLevel then
		state.bondLevel = newLevel
		CreatureService.react("restored")
		for _, callback in ipairs(bondListeners) do
			task.spawn(callback, state.bondLevel)
		end
	end
end

--=====================================================================
-- Animation: one cheap Heartbeat pass over two Motor6Ds
--=====================================================================

local function headTransform(now)
	local breath = math.sin(now * 1.1) * 0.02
	local sway = math.sin(now * 0.23) * 0.05
	local pitch = 0
	local yaw = 0

	if state.reactionKind then
		local kickEnvelope = math.clamp(1 - (state.reactionUntil - now) / 2, 0, 1)
		local reaction = Reactions[state.reactionKind or "gather"]
		if reaction then
			pitch = reaction.pitch * math.sin(now * 2.6) * kickEnvelope
			yaw = reaction.yaw * math.sin(now * 1.7) * kickEnvelope
		end
	end

	-- look toward points of interest
	if state.headLook and now < state.headLookUntil and world.refs.head then
		local headPosition = world.refs.head.Position
		local delta = state.headLook - headPosition
		local flatDelta = Vector3.new(delta.X, 0, delta.Z)
		if flatDelta.Magnitude > 1 then
			-- creature faces +Z: yaw is measured against that axis
			local targetYaw = math.atan2(delta.X, delta.Z)
			yaw += math.clamp(targetYaw, -0.9, 0.9) * 0.35
		end
	end

	return CFrame.new(0, breath * 2, 0) * CFrame.Angles(pitch + breath, yaw + sway, sway * 0.5)
end

local function tailTransform(now)
	local sway = math.sin(now * 0.31) * 0.25
	local breath = math.sin(now * 1.1 + 1.2) * 0.03
	return CFrame.Angles(0, sway, 0) * CFrame.new(0, breath, 0)
end

function CreatureService.onHeartbeat()
	if not world then
		return
	end
	local now = os.clock()

	if state.reactionKind and now > state.reactionUntil then
		state.reactionKind = nil
		state.reaction = 0
	end

	if world.refs.NeckJoint then
		world.refs.NeckJoint.Transform = headTransform(now)
	end
	if world.refs.TailJoint then
		world.refs.TailJoint.Transform = tailTransform(now)
	end
end

return CreatureService
