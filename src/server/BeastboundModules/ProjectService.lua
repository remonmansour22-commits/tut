-- Path: ServerScriptService/BeastboundModules/ProjectService
-- "Restore the Heartroot" — the shared community project. The server holds
-- all progress; contributions are clamped to what the player actually has.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Shared = ReplicatedStorage:WaitForChild("BeastboundShared")
local Config = require(Shared.Config)
local AudioConfig = require(Shared.AudioConfig)

local Kit = require(script.Parent.BuilderKit)

local ProjectService = {}

local PlayerDataService, RemotesService, QuestService, ProgressionService, CreatureService, JourneyService, SyncService

local progress = 0
local target = 0
local completed = false
local contributions = {} -- [userId] = glowseeds given
local laurelPart

function ProjectService.init(deps, worldHandle)
	PlayerDataService = deps.PlayerDataService
	RemotesService = deps.RemotesService
	QuestService = deps.QuestService
	ProgressionService = deps.ProgressionService
	CreatureService = deps.CreatureService
	JourneyService = deps.JourneyService
	SyncService = deps.SyncService

	target = Config.HeartrootGlowseedsNeeded
	completed = false
	ProjectService.heartroot = worldHandle.heartroot
	ProjectService.updateOrbVisual()
end

function ProjectService.snapshot()
	return {
		id = "Heartroot",
		name = "Restore the Heartroot",
		progress = progress,
		target = target,
		completed = completed,
	}
end

function ProjectService.updateOrbVisual()
	local orb = ProjectService.heartroot.Orb
	if not orb or not orb.Parent then
		return
	end
	local ratio = target > 0 and math.clamp(progress / target, 0, 1) or 0
	local size = 4 + ratio * 5
	TweenService:Create(orb, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(size, size, size),
		Color = Color3.fromRGB(120, 255, 190):Lerp(Color3.fromRGB(255, 220, 120), ratio),
	}):Play()
end

function ProjectService.contribute(player)
	if completed then
		RemotesService.toast(player, "Already restored", "The Heartroot shines fully. Next project unlocks via the journey.", "info")
		return
	end
	local held = PlayerDataService.countItem(player, "Glowseed")
	local chunk = math.min(Config.ContributeChunk, held)
	if chunk <= 0 then
		RemotesService.toast(player, "No Glowseeds", "Gather Glowseeds on the middle terraces, then return.", "warn")
		return
	end

	if not PlayerDataService.takeItem(player, "Glowseed", chunk) then
		return
	end

	progress += chunk
	contributions[player.UserId] = (contributions[player.UserId] or 0) + chunk

	local profile = PlayerDataService.get(player)
	if profile then
		profile.counts.contributed += chunk
	end
	ProgressionService.award(player, Config.XpRewards.Contribute)
	QuestService.mark(player, "contribute")
	CreatureService.addBond(Config.BondPerContribution * chunk)
	ProjectService.updateOrbVisual()
	SyncService.playerSync(player)
	SyncService.worldBroadcast()

	CreatureService.react("contribute", ProjectService.heartroot.Altar.Position)

	if progress % 10 == 0 then
		RemotesService.toastAll("Heartroot stirring", progress .. " / " .. target .. " Glowseed light gathered.", "info")
	end

	if progress >= target and not completed then
		ProjectService.complete()
	end
end

function ProjectService.complete()
	completed = true
	local orb = ProjectService.heartroot.Orb
	if orb and orb.Parent then
		TweenService:Create(orb, TweenInfo.new(2, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
			Size = Vector3.new(11, 11, 11),
			Color = Color3.fromRGB(255, 230, 140),
		}):Play()
	end
	CreatureService.react("restored", orb and orb.Position)
	JourneyService.addMomentum(Config.JourneyMomentumPerProject)

	-- visible world change: a bloom ring grows around the settlement plateau
	for index = 1, 10 do
		local angle = math.rad(index * 36)
		local bloom = Kit.glow({
			parent = ProjectService.heartroot.Model,
			name = "RestoredBloom" .. index,
			shape = Enum.PartType.Ball,
			size = Vector3.new(2, 2, 2),
			cframe = CFrame.new(math.cos(angle) * 18, 60.6, -14 + math.sin(angle) * 18),
			color = Color3.fromRGB(255, 220, 120),
			canCollide = false,
		})
		bloom.Transparency = 1
		TweenService:Create(bloom, TweenInfo.new(1.2 + index * 0.1), { Transparency = 0.1 }):Play()
	end

	-- reward everyone who contributed
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		ProgressionService.award(player, Config.XpRewards.ProjectCompleteBonus)
	end
	RemotesService.toastAll("HEARTROOT RESTORED", "Aruun answers. A bloom spreads across the terrace.", "project")
	Kit.playSoundAt(orb and orb.Position or Vector3.new(0, 66, -14), AudioConfig.ProjectComplete)
	SyncService.worldBroadcast()
end

return ProjectService
