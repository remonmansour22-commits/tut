-- Path: ServerScriptService/BeastboundModules/InteractionService
-- Gathering + landmark discovery. All grants are server-side; the client never
-- sends a gather request at all (ProximityPrompt.Triggered is authoritative and
-- distance-limited by the engine).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("BeastboundShared")
local Config = require(Shared.Config)
local ResourceConfig = require(Shared.ResourceConfig)
local BiomeConfig = require(Shared.BiomeConfig)
local AudioConfig = require(Shared.AudioConfig)

local Kit = require(script.Parent.BuilderKit)

local InteractionService = {}

local PlayerDataService, RemotesService, QuestService, ProgressionService, CreatureService, JourneyService, SyncService

local lastGather = {} -- [node] = timestamp

function InteractionService.init(deps, worldHandle)
	PlayerDataService = deps.PlayerDataService
	RemotesService = deps.RemotesService
	QuestService = deps.QuestService
	ProgressionService = deps.ProgressionService
	CreatureService = deps.CreatureService
	JourneyService = deps.JourneyService
	SyncService = deps.SyncService

	InteractionService.wireNodes(worldHandle.creature.GatherNodes)
	InteractionService.wireHeartrootAltar(worldHandle)
	InteractionService.startLandmarkScan(worldHandle.creature)
end

--=====================================================================
-- Gather nodes
--=====================================================================

function InteractionService.wireNodes(nodesFolder)
	for _, node in ipairs(nodesFolder:GetChildren()) do
		local primary = node.PrimaryPart
		if primary then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Gather"
			prompt.ObjectText = ResourceConfig.ById[node:GetAttribute("ResourceId")].DisplayName
			prompt.HoldDuration = 0.7
			prompt.MaxActivationDistance = 10
			prompt.RequiresLineOfSight = false
			prompt.Enabled = true
			prompt.Parent = primary
			prompt.Triggered:Connect(function(player)
				InteractionService.gather(player, node)
			end)
		end
	end
end

function InteractionService.gather(player, node)
	if node:GetAttribute("Available") ~= true then
		return
	end

	local now = os.clock()
	if lastGather[node] and now - lastGather[node] < Config.NodeRespawnSeconds then
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local primary = node.PrimaryPart
	if not root or not primary then
		return
	end
	-- defense in depth beyond the prompt's own activation distance
	if (root.Position - primary.Position).Magnitude > Config.MaxGatherDistance then
		return
	end

	local resourceId = node:GetAttribute("ResourceId")
	local def = ResourceConfig.ById[resourceId]
	if not def then
		return
	end

	lastGather[node] = now
	node:SetAttribute("Available", false)

	-- hide visuals, dim prompt feedback
	for _, part in ipairs(node:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = part.Material == Enum.Material.Neon and 1 or 0.85
		end
	end
	Kit.playSoundAt(primary.Position, AudioConfig.Gather)

	local amount = def.DropMin
	if def.DropMax > def.DropMin and math.random() < Config.RareDoubleChance then
		amount = def.DropMax
	end
	PlayerDataService.addItem(player, resourceId, amount)

	local profile = PlayerDataService.get(player)
	if profile then
		profile.counts.gathered += amount
	end

	ProgressionService.award(player, Config.XpRewards.Gather)
	QuestService.mark(player, "gather:" .. resourceId)
	CreatureService.react("gather", primary.Position)
	SyncService.playerSync(player)

	-- respawn (all node parts are opaque by default; restoreNodeVisuals is safe)
	task.delay(Config.NodeRespawnSeconds, function()
		if node.Parent then
			InteractionService.restoreNodeVisuals(node)
			node:SetAttribute("Available", true)
		end
	end)
end

function InteractionService.restoreNodeVisuals(node)
	for _, part in ipairs(node:GetDescendants()) do
		if part:IsA("BasePart") then
			if part.Material == Enum.Material.Neon then
				part.Transparency = 0
			else
				part.Transparency = 0
			end
		end
	end
end

--=====================================================================
-- Landmark discovery (Atlas-lite)
--=====================================================================

function InteractionService.startLandmarkScan(creature)
	local knownThisSession = {}
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, player in ipairs(Players:GetPlayers()) do
				local profile = PlayerDataService.get(player)
				local character = player.Character
				local root = character and character:FindFirstChild("HumanoidRootPart")
				if profile and root then
					for _, landmark in ipairs(BiomeConfig.Landmarks) do
						if not profile.discoveredLandmarks[landmark.Id] and not knownThisSession[player.UserId .. landmark.Id] then
							local dx = root.Position.X - landmark.Position.X
							local dz = root.Position.Z - landmark.Position.Z
							if math.sqrt(dx * dx + dz * dz) <= landmark.Radius then
								knownThisSession[player.UserId .. landmark.Id] = true
								InteractionService.discover(player, landmark)
							end
						end
					end
				end
			end
		end
	end)
end

function InteractionService.discover(player, landmark)
	local profile = PlayerDataService.get(player)
	if not profile or profile.discoveredLandmarks[landmark.Id] then
		return
	end

	profile.discoveredLandmarks[landmark.Id] = true
	profile.counts.discoveries += 1
	ProgressionService.award(player, landmark.Xp or Config.XpRewards.Discover)
	QuestService.mark(player, "discover")
	JourneyService.addMomentum(Config.JourneyMomentumPerDiscover)
	CreatureService.react("discover", landmark.Position)

	RemotesService.toast(player, "Discovered: " .. landmark.Name, landmark.Lore, "discover")
	SyncService.playerSync(player)
end

--=====================================================================
-- Heartroot altar prompt (handled with ProjectService)
--=====================================================================

local ProjectService

function InteractionService.setProjectService(service)
	ProjectService = service
end

function InteractionService.wireHeartrootAltar(worldHandle)
	local altar = worldHandle.heartroot.Altar
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Feed Glowseeds"
	prompt.ObjectText = "The Heartroot"
	prompt.HoldDuration = 0.6
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = altar
	prompt.Triggered:Connect(function(player)
		if ProjectService then
			ProjectService.contribute(player)
		end
	end)
end

return InteractionService
