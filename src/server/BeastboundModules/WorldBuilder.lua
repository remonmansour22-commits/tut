-- Path: ServerScriptService/BeastboundModules/WorldBuilder
-- Generates the entire vertical-slice world from code:
--   * Aruun, the giant Wayfarer (terraced back + animated neck/head/tail rig)
--   * Mosslight Meadow dressing (forest, rocks, waterfall, glow flora)
--   * The Dawnward settlement (spawn plaza, Heartroot, 6 build plots)
--   * Gather nodes and landmark props
-- All geometry is anchored; creature life comes from Motor6D.Transform only.

local Kit = require(script.Parent.BuilderKit)
local BiomeConfig = require(game:GetService("ReplicatedStorage").BeastboundShared.BiomeConfig)

local WorldBuilder = {}

local SKIN = Color3.fromRGB(70, 104, 118)
local SKIN_DARK = Color3.fromRGB(52, 80, 92)
local PAL = BiomeConfig.Stages[1].Palette
local rand = Random.new(7)

local world = {
	tintGroups = { FoliageTint = {}, GroundTint = {}, AccentTint = {} },
	plots = {},          -- plotId -> pad part
	landmarkProps = {},  -- landmarkId -> model
	refs = {},           -- rig references for CreatureService
}

local function tint(part, group)
	table.insert(world.tintGroups[group], part)
	return part
end

--=====================================================================
-- Creature body
--=====================================================================

local function terrace(parent, surfaceHeight, radius, thickness, index)
	local disc = Kit.pillar({
		parent = parent,
		name = "Terrace" .. index,
		size = Vector3.new(thickness, radius * 2, radius * 2),
		cframe = CFrame.new(0, surfaceHeight - thickness / 2, 0),
		color = PAL.GroundTint,
		material = Enum.Material.LeafyGrass,
	})
	tint(disc, "GroundTint")

	for _ = 1, 6 do
		local angle = rand:NextNumber(0, math.pi * 2)
		local radiusOffset = rand:NextNumber(4, 14)
		Kit.sphere({
			parent = parent,
			name = "TerraceBoulder",
			size = Vector3.new(10, 8, 10),
			cframe = CFrame.new(math.cos(angle) * (radius - radiusOffset), surfaceHeight + 2, math.sin(angle) * (radius - radiusOffset)),
			color = Color3.fromRGB(120, 122, 118),
			material = Enum.Material.Slate,
		})
	end
	return disc
end

local function buildBody(body)
	local specs = {
		{ surfaceHeight = 30, radius = 115, thickness = 14 },
		{ surfaceHeight = 40, radius = 95, thickness = 12 },
		{ surfaceHeight = 50, radius = 75, thickness = 12 },
		{ surfaceHeight = 60, radius = 55, thickness = 12 },
	}
	for index, spec in ipairs(specs) do
		terrace(body, spec.surfaceHeight, spec.radius, spec.thickness, index)
	end

	local sails = {
		{ z = -55, h = 18 }, { z = -70, h = 13 }, { z = -84, h = 9 }, { z = -97, h = 6 },
	}
	for index, spec in ipairs(sails) do
		Kit.wedge({
			parent = body,
			name = "DorsalSail" .. index,
			size = Vector3.new(10, spec.h, 7),
			cframe = CFrame.new(0, 30 + spec.h / 2, spec.z),
			color = SKIN_DARK,
			material = Enum.Material.Slate,
		})
	end

	Kit.sphere({
		parent = body,
		name = "Belly",
		size = Vector3.new(230, 230, 260),
		cframe = CFrame.new(0, -42, 10),
		color = SKIN_DARK,
		material = Enum.Material.Slate,
	})

	for _, offset in ipairs({ Vector3.new(-62, 12, -55), Vector3.new(62, 12, -55) }) do
		Kit.sphere({
			parent = body,
			name = "Haunch",
			size = Vector3.new(95, 80, 100),
			cframe = CFrame.new(offset),
			color = SKIN,
			material = Enum.Material.Slate,
		})
	end

	for _ = 1, 14 do
		local angle = rand:NextNumber(0, math.pi * 2)
		local radius = 96 + rand:NextNumber(-6, 6)
		Kit.glow({
			parent = body,
			name = "Biolume",
			size = Vector3.new(10, 1.4, 3),
			cframe = CFrame.new(math.cos(angle) * radius, 17, math.sin(angle) * radius) * CFrame.Angles(0, -angle, 0),
			color = PAL.AccentTint,
			canCollide = false,
		})
	end
end

local function motorize(rootPart, drivenPart, jointName)
	local motor = Instance.new("Motor6D")
	motor.Name = jointName
	motor.Part0 = rootPart
	motor.Part1 = drivenPart
	motor.Parent = rootPart
	return motor
end

local function rigPart(props)
	local part = Kit.part(props)
	part.Anchored = false
	part.Massless = true
	part.CanCollide = false
	return part
end

local function weldChain(parts)
	for index = 2, #parts do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = parts[index - 1]
		weld.Part1 = parts[index]
		weld.Parent = parts[index]
	end
end

local function buildNeck(model, refs)
	local root = Kit.part({
		parent = model,
		name = "NeckRoot",
		size = Vector3.new(10, 8, 10),
		cframe = CFrame.new(0, 29, 106),
		color = SKIN,
		material = Enum.Material.Slate,
	})

	local neckA = rigPart({ parent = model, name = "NeckA", shape = Enum.PartType.Ball, size = Vector3.new(30, 30, 30), cframe = CFrame.new(0, 34, 122), color = SKIN, material = Enum.Material.Slate })
	local neckB = rigPart({ parent = model, name = "NeckB", shape = Enum.PartType.Ball, size = Vector3.new(26, 26, 26), cframe = CFrame.new(0, 46, 138), color = SKIN, material = Enum.Material.Slate })
	local neckC = rigPart({ parent = model, name = "NeckC", shape = Enum.PartType.Ball, size = Vector3.new(22, 22, 22), cframe = CFrame.new(0, 58, 150), color = SKIN, material = Enum.Material.Slate })
	local head = rigPart({ parent = model, name = "Head", size = Vector3.new(26, 22, 38), cframe = CFrame.new(0, 72, 160) * CFrame.Angles(math.rad(18), 0, 0), color = SKIN, material = Enum.Material.Slate })
	local brow = rigPart({ parent = model, name = "Brow", size = Vector3.new(28, 6, 12), cframe = CFrame.new(0, 80, 166) * CFrame.Angles(math.rad(18), 0, 0), color = SKIN_DARK, material = Enum.Material.Slate })
	local jaw = rigPart({ parent = model, name = "Jaw", size = Vector3.new(20, 8, 28), cframe = CFrame.new(0, 64, 166), color = SKIN_DARK, material = Enum.Material.Slate })

	local lantern = rigPart({ parent = model, name = "Lantern", shape = Enum.PartType.Ball, size = Vector3.new(7, 7, 7), cframe = CFrame.new(0, 84, 170), color = PAL.AccentTint, material = Enum.Material.Neon })
	Kit.pointLight(lantern, PAL.AccentTint, 3, 130)
	Kit.sparkle(lantern, PAL.AccentTint, 2, 4, 2.5)

	local hornChains = {}
	for _, side in ipairs({ -1, 1 }) do
		local horns = {}
		local defs = {
			{ Vector3.new(10 * side, 82, 156), 6 },
			{ Vector3.new(14 * side, 90, 150), 4.5 },
			{ Vector3.new(16 * side, 97, 143), 3 },
		}
		for _, def in ipairs(defs) do
			table.insert(horns, rigPart({ parent = model, name = "Horn", shape = Enum.PartType.Ball, size = Vector3.new(def[2] * 2, def[2] * 2, def[2] * 2), cframe = CFrame.new(def[1]), color = SKIN_DARK, material = Enum.Material.Slate }))
		end
		table.insert(hornChains, { head, horns[1], horns[2], horns[3] })
	end

	weldChain({ neckA, neckB, neckC, head, brow, jaw, lantern })
	for _, chain in ipairs(hornChains) do
		weldChain(chain)
	end

	refs.NeckJoint = motorize(root, neckA, "NeckJoint")
	refs.head = head
	refs.lantern = lantern
end

local function buildTail(model, refs)
	local root = Kit.part({
		parent = model,
		name = "TailRoot",
		size = Vector3.new(10, 8, 10),
		cframe = CFrame.new(0, 29, -110),
		color = SKIN,
		material = Enum.Material.Slate,
	})

	local tailA = rigPart({ parent = model, name = "TailA", shape = Enum.PartType.Ball, size = Vector3.new(30, 30, 30), cframe = CFrame.new(0, 36, -132), color = SKIN, material = Enum.Material.Slate })
	local tailB = rigPart({ parent = model, name = "TailB", shape = Enum.PartType.Ball, size = Vector3.new(24, 24, 24), cframe = CFrame.new(0, 46, -152), color = SKIN, material = Enum.Material.Slate })
	local tailC = rigPart({ parent = model, name = "TailC", shape = Enum.PartType.Ball, size = Vector3.new(18, 18, 18), cframe = CFrame.new(0, 56, -168), color = SKIN, material = Enum.Material.Slate })
	local fin = rigPart({ parent = model, name = "Fin", size = Vector3.new(2, 26, 14), cframe = CFrame.new(0, 68, -174) * CFrame.Angles(math.rad(-14), 0, 0), color = SKIN_DARK, material = Enum.Material.Slate })

	weldChain({ tailA, tailB, tailC, fin })
	refs.TailJoint = motorize(root, tailA, "TailJoint")
end

--=====================================================================
-- Landmarks
--=====================================================================

local function buildLandmarks(model)
	local hollow = Instance.new("Model")
	hollow.Name = "WhisperingHollow"
	hollow.Parent = model
	Kit.part({ parent = hollow, name = "PillarL", size = Vector3.new(4, 14, 4), cframe = CFrame.new(-92, 47, -44), color = Color3.fromRGB(110, 112, 116), material = Enum.Material.Rock })
	Kit.part({ parent = hollow, name = "PillarR", size = Vector3.new(4, 14, 4), cframe = CFrame.new(-84, 47, -36), color = Color3.fromRGB(110, 112, 116), material = Enum.Material.Rock })
	Kit.part({ parent = hollow, name = "Arch", size = Vector3.new(13, 3, 5), cframe = CFrame.new(-88, 54, -40) * CFrame.Angles(0, math.rad(45), 0), color = Color3.fromRGB(110, 112, 116), material = Enum.Material.Rock })
	local hum = Kit.glow({ parent = hollow, name = "Hum", size = Vector3.new(2, 2, 2), cframe = CFrame.new(-88, 42, -40), color = PAL.AccentTint, canCollide = false })
	Kit.sparkle(hum, PAL.AccentTint, 3, 1, 3)
	tint(hum, "AccentTint")
	world.landmarkProps.WhisperingHollow = hollow

	local sentinel = Instance.new("Model")
	sentinel.Name = "SentinelStone"
	sentinel.Parent = model
	Kit.part({ parent = sentinel, name = "Bust", size = Vector3.new(8, 12, 8), cframe = CFrame.new(62, 36, 86), color = Color3.fromRGB(128, 130, 124), material = Enum.Material.Rock })
	Kit.part({ parent = sentinel, name = "Head", size = Vector3.new(6, 6, 6), cframe = CFrame.new(62, 45, 86), color = Color3.fromRGB(128, 130, 124), material = Enum.Material.Rock })
	Kit.part({ parent = sentinel, name = "Brow", size = Vector3.new(7, 1.6, 3), cframe = CFrame.new(62, 47, 88), color = Color3.fromRGB(104, 106, 100), material = Enum.Material.Rock })
	tint(Kit.part({ parent = sentinel, name = "Moss", size = Vector3.new(8.4, 1.2, 8.4), cframe = CFrame.new(62, 42.6, 86), color = PAL.FoliageTint, material = Enum.Material.Moss, canCollide = false }), "FoliageTint")
	world.landmarkProps.SentinelStone = sentinel

	local garden = Instance.new("Model")
	garden.Name = "HiddenGarden"
	garden.Parent = model
	for index, offset in ipairs({ Vector3.new(-4, 0, -6), Vector3.new(4, 0, 6), Vector3.new(-7, 0, 4), Vector3.new(5, 0, -6) }) do
		local bloom = Kit.glow({
			parent = garden,
			name = "Bloom" .. index,
			shape = Enum.PartType.Ball,
			size = Vector3.new(2.4, 2.4, 2.4),
			cframe = CFrame.new(106, 32.5, 10) + offset,
			color = PAL.AccentTint,
			canCollide = false,
		})
		tint(bloom, "AccentTint")
	end
	Kit.part({ parent = garden, name = "Stone", size = Vector3.new(6, 3, 6), cframe = CFrame.new(106, 31.5, 10), color = Color3.fromRGB(120, 122, 118), material = Enum.Material.Rock })
	world.landmarkProps.HiddenGarden = garden

	local crest = Instance.new("Model")
	crest.Name = "LanternCrest"
	crest.Parent = model
	Kit.part({ parent = crest, name = "Balcony", size = Vector3.new(16, 1, 14), cframe = CFrame.new(26, 44.5, 148), color = Color3.fromRGB(120, 122, 118), material = Enum.Material.Rock })
	local crestGlow = Kit.glow({ parent = crest, name = "CrestGlow", size = Vector3.new(1.4, 4, 1.4), cframe = CFrame.new(26, 47, 152), color = PAL.AccentTint, canCollide = false })
	tint(crestGlow, "AccentTint")
	world.landmarkProps.LanternCrest = crest
	-- (Tail Spire landmark prop = SpirePlatform + pin, built in buildPaths)
end

--=====================================================================
-- Gather nodes
--=====================================================================

local function makeNode(parent, resourceId, position)
	local node = Instance.new("Model")
	node.Name = "Node_" .. resourceId
	node:SetAttribute("ResourceId", resourceId)
	node:SetAttribute("Available", true)

	if resourceId == "Driftwood" then
		for index, offset in ipairs({ Vector3.new(0, 1, 0), Vector3.new(2, 1, 1.4), Vector3.new(-1.6, 1, 1.8), Vector3.new(0.8, 2.6, 1) }) do
			Kit.part({
				parent = node,
				name = "Log" .. index,
				size = Vector3.new(4.6, 1.6, 1.8),
				cframe = CFrame.new(position + offset) * CFrame.Angles(0, rand:NextNumber(0, math.pi), rand:NextNumber(-0.2, 0.2)),
				color = Color3.fromRGB(122, 88, 58),
				material = Enum.Material.WoodPlanks,
			})
		end
	elseif resourceId == "Stone" then
		for index, offset in ipairs({ Vector3.new(0, 2, 0), Vector3.new(2.6, 1.4, 1.4), Vector3.new(-2.2, 1.2, 1.8), Vector3.new(1, 3.4, 0.6) }) do
			Kit.sphere({
				parent = node,
				name = "Rock" .. index,
				size = Vector3.new(4, 3.4, 4),
				cframe = CFrame.new(position + offset),
				color = Color3.fromRGB(140, 142, 148),
				material = Enum.Material.Slate,
			})
		end
	else -- Glowseed
		Kit.part({ parent = node, name = "StalkRoot", size = Vector3.new(2.6, 3, 2.6), cframe = CFrame.new(position + Vector3.new(0, 1.5, 0)), color = Color3.fromRGB(84, 122, 84), material = Enum.Material.Grass })
		for index = 1, 3 do
			local seed = Kit.glow({
				parent = node,
				name = "Seed" .. index,
				shape = Enum.PartType.Ball,
				size = Vector3.new(1.8, 1.8, 1.8),
				cframe = CFrame.new(position + Vector3.new(math.cos(index * 2.1) * 1.6, 4 + index * 0.25, math.sin(index * 2.1) * 1.6)),
				color = Color3.fromRGB(120, 255, 190),
				canCollide = false,
			})
			tint(seed, "AccentTint")
			Kit.sparkle(seed, Color3.fromRGB(120, 255, 190), 0.6, 1, 2)
		end
	end

	node.PrimaryPart = node:FindFirstChildWhichIsA("BasePart")
	world.nodes[#world.nodes + 1] = node
	node.Parent = parent
end

local function buildNodes(nodesFolder)
	-- Glowseed clusters: L3 meadow shelf (y50, radius 75)
	for _, position in ipairs({
		Vector3.new(55, 50, -45), Vector3.new(-60, 50, 25), Vector3.new(-20, 50, -60), Vector3.new(65, 50, 30), Vector3.new(25, 50, -62),
	}) do
		makeNode(nodesFolder, "Glowseed", position)
	end
	-- Driftwood: forest belt L2 (y40, radius 95)
	for _, position in ipairs({
		Vector3.new(60, 40, 55), Vector3.new(-55, 40, -20), Vector3.new(15, 40, 75), Vector3.new(-35, 40, 60), Vector3.new(80, 40, -35),
	}) do
		makeNode(nodesFolder, "Driftwood", position)
	end
	-- Stone: outer rim L1 (y30, radius 115)
	for _, position in ipairs({
		Vector3.new(95, 30, -40), Vector3.new(-95, 30, 20), Vector3.new(70, 30, -85), Vector3.new(-70, 30, 90), Vector3.new(100, 30, 45),
	}) do
		makeNode(nodesFolder, "Stone", position)
	end
end

--=====================================================================
-- Settlement
--=====================================================================

local function buildSettlement(creature, plotsFolder)
	local top = 60

	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "DawnwardSpawn"
	spawnLocation.Size = Vector3.new(14, 1, 14)
	spawnLocation.CFrame = CFrame.new(0, top + 0.5, 14)
	spawnLocation.Color = Color3.fromRGB(150, 140, 120)
	spawnLocation.Material = Enum.Material.WoodPlanks
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0
	spawnLocation.CanQuery = false
	spawnLocation.Parent = creature

	-- campfire
	local fire = Instance.new("Model")
	fire.Name = "Campfire"
	fire.Parent = creature
	Kit.pillar({ parent = fire, name = "Pit", size = Vector3.new(1.2, 9, 9), cframe = CFrame.new(9, top + 0.6, 9), color = Color3.fromRGB(120, 122, 118), material = Enum.Material.Slate })
	for index = 1, 4 do
		local angle = math.rad(index * 90)
		Kit.part({
			parent = fire,
			name = "Log",
			size = Vector3.new(3.4, 1, 1),
			cframe = CFrame.new(9, top + 1.6, 9) * CFrame.Angles(0, angle, 0) * CFrame.new(1.4, 0, 0),
			color = Color3.fromRGB(122, 88, 58),
			material = Enum.Material.WoodPlanks,
		})
	end
	local flame = Kit.glow({ parent = fire, name = "Flame", shape = Enum.PartType.Ball, size = Vector3.new(2.6, 3.4, 2.6), cframe = CFrame.new(9, top + 2.6, 9), color = Color3.fromRGB(255, 170, 70), canCollide = false })
	Kit.pointLight(flame, Color3.fromRGB(255, 170, 70), 2, 30)
	Kit.sparkle(flame, Color3.fromRGB(255, 190, 90), 8, 3, 1.1)

	-- migration signpost (client binds the label to live journey state)
	local signpost = Instance.new("Model")
	signpost.Name = "MigrationSignpost"
	signpost.Parent = creature
	Kit.part({ parent = signpost, name = "Post", size = Vector3.new(1.2, 9, 1.2), cframe = CFrame.new(-8, top + 4.5, 12), color = Color3.fromRGB(101, 74, 50), material = Enum.Material.WoodPlanks })
	local board = Kit.part({ parent = signpost, name = "Board", size = Vector3.new(10, 4, 0.6), cframe = CFrame.new(-8, top + 8, 12) * CFrame.Angles(0, math.rad(18), 0), color = Color3.fromRGB(122, 88, 58), material = Enum.Material.WoodPlanks })
	board:SetAttribute("SignBoard", true)
	local gui = Instance.new("BillboardGui")
	gui.Name = "SignGui"
	gui.Size = UDim2.fromScale(8, 3)
	gui.StudsOffset = Vector3.new(0, 1.5, 0)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 120
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Name = "SignText"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 240, 200)
	label.TextStrokeTransparency = 0.5
	label.Text = "Mosslight Meadow"
	label.Parent = gui
	world.refs.signLabel = label

	-- build plots
	for plotIndex = 1, 6 do
		local angle = math.rad((plotIndex - 1) * 60 + 30)
		local plotId = "Plot" .. plotIndex
		local pad = Kit.part({
			parent = plotsFolder,
			name = plotId,
			size = Vector3.new(16, 1, 16),
			cframe = CFrame.new(math.cos(angle) * 40, top + 0.5, math.sin(angle) * 40),
			color = Color3.fromRGB(150, 152, 158),
			material = Enum.Material.Slate,
			canCollide = true,
		})
		pad:SetAttribute("PlotId", plotId)
		pad:SetAttribute("OwnerUserId", 0)
		pad:SetAttribute("StructureId", "")
		world.plots[plotId] = pad

		local ring = Kit.glow({
			parent = plotsFolder,
			name = plotId .. "_Mark",
			size = Vector3.new(0.4, 17, 17),
			cframe = CFrame.new(math.cos(angle) * 40, top + 1.2, math.sin(angle) * 40) * CFrame.Angles(math.rad(90), 0, 0),
			color = PAL.AccentTint,
			canCollide = false,
			transparency = 0.5,
		})
		tint(ring, "AccentTint")
	end

	-- Heartroot (ProjectService drives the orb)
	local heartroot = Instance.new("Model")
	heartroot.Name = "Heartroot"
	heartroot.Parent = creature
	Kit.pillar({ parent = heartroot, name = "Pedestal", size = Vector3.new(3, 16, 16), cframe = CFrame.new(0, top + 1.5, -14), color = Color3.fromRGB(120, 122, 118), material = Enum.Material.Slate })
	for index = 1, 5 do
		local angle = math.rad(index * 72)
		Kit.glow({
			parent = heartroot,
			name = "RootVein" .. index,
			size = Vector3.new(0.4, 0.4, 8),
			cframe = CFrame.new(0, top + 2.4, -14) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, -9),
			color = PAL.AccentTint,
			canCollide = false,
			transparency = 0.4,
		})
	end
	local orb = Kit.glow({
		parent = heartroot,
		name = "HeartOrb",
		shape = Enum.PartType.Ball,
		size = Vector3.new(4, 4, 4),
		cframe = CFrame.new(0, top + 6, -14),
		color = PAL.AccentTint,
		canCollide = false,
	})
	Kit.pointLight(orb, PAL.AccentTint, 2, 45)

	local altar = Kit.part({
		parent = heartroot,
		name = "Altar",
		size = Vector3.new(10, 0.8, 10),
		cframe = CFrame.new(0, top + 3.6, -14),
		color = Color3.fromRGB(120, 122, 118),
		material = Enum.Material.Slate,
		canCollide = true,
	})
	altar:SetAttribute("ContributionAltar", true)

	world.heartroot = { Model = heartroot, Orb = orb, Altar = altar }
end

--=====================================================================
-- Paths (so every terrace is climbable)
--=====================================================================

local function buildPaths(model)
	local pathColor = Color3.fromRGB(140, 132, 118)
	for _, def in ipairs({
		-- L1 (y30) -> L2 (y40), southwest
		{ a = Vector3.new(-45, 30, 70), b = Vector3.new(-75, 40, 40) },
		-- L2 -> L3 (northeast)
		{ a = Vector3.new(55, 40, -30), b = Vector3.new(28, 50, -2) },
		-- L3 -> L4 settlement plateau (center)
		{ a = Vector3.new(-25, 50, 30), b = Vector3.new(-2, 60, 5) },
		-- lantern crest ramp from L1
		{ a = Vector3.new(26, 30, 104), b = Vector3.new(26, 44, 140) },
	}) do
		Kit.ramp({ parent = model, a = def.a, b = def.b, width = 9, color = pathColor, material = Enum.Material.Rock, name = "PathRamp" })
	end

	-- tail spire walkway (two switchbacks against the tail)
	Kit.ramp({ parent = model, a = Vector3.new(12, 30, -108), b = Vector3.new(16, 44, -132), width = 7, color = pathColor, material = Enum.Material.Rock, name = "SpireWalkA" })
	Kit.ramp({ parent = model, a = Vector3.new(16, 44, -132), b = Vector3.new(18, 58, -156), width = 7, color = pathColor, material = Enum.Material.Rock, name = "SpireWalkB" })
	Kit.part({ parent = model, name = "SpirePlatform", size = Vector3.new(16, 1, 14), cframe = CFrame.new(18, 59.5, -166), color = pathColor, material = Enum.Material.Rock })
	local spireGlow = Kit.glow({ parent = model, name = "SpireTip", shape = Enum.PartType.Ball, size = Vector3.new(3, 3, 3), cframe = CFrame.new(18, 63, -166), color = PAL.AccentTint, canCollide = false })
	tint(spireGlow, "AccentTint")
	world.landmarkProps.TailSpire = model:FindFirstChild("SpirePlatform")
end

--=====================================================================
-- Waterfall + pond (hidden garden side)
--=====================================================================

local function buildWaterfall(model)
	Kit.part({
		parent = model,
		name = "WaterfallSheet",
		size = Vector3.new(10, 12, 1),
		cframe = CFrame.new(100, 35, 10) * CFrame.Angles(0, 0, math.rad(12)),
		color = Color3.fromRGB(160, 210, 230),
		material = Enum.Material.Glass,
		transparency = 0.45,
		canCollide = false,
	})
	local pond = Kit.pillar({
		parent = model,
		name = "Pond",
		size = Vector3.new(1.2, 22, 16),
		cframe = CFrame.new(106, 30.7, 10),
		color = Color3.fromRGB(120, 180, 200),
		material = Enum.Material.Glass,
		transparency = 0.35,
		canCollide = false,
	})
	local splash = Kit.part({
		parent = model,
		name = "SplashAnchor",
		size = Vector3.new(1, 1, 1),
		cframe = CFrame.new(100, 30.5, 10),
		color = Color3.fromRGB(120, 180, 200),
		transparency = 1,
		canCollide = false,
	})
	Kit.sparkle(splash, Color3.fromRGB(200, 230, 245), 14, 5, 0.8)
	tint(pond, "AccentTint")
end

--=====================================================================
-- Flora & horizon (with migration "movement" illusions)
--=====================================================================

local function buildFlora(model)
	-- forest belt on L2 + L3
	local treePositions = {
		Vector3.new(-60, 40, 55), Vector3.new(30, 40, 70), Vector3.new(-30, 40, 60), Vector3.new(60, 40, 40),
		Vector3.new(-15, 40, 65), Vector3.new(-72, 40, -8), Vector3.new(45, 40, 62), Vector3.new(-48, 40, 22),
		Vector3.new(38, 50, 8), Vector3.new(-40, 50, -48), Vector3.new(-62, 50, -10), Vector3.new(10, 50, -68),
	}
	for index, position in ipairs(treePositions) do
		local scale = 0.8 + (index % 3) * 0.25
		local trunk = Kit.part({
			parent = model,
			name = "Trunk" .. index,
			size = Vector3.new(2.6 * scale, 11 * scale, 2.6 * scale),
			cframe = CFrame.new(position + Vector3.new(0, 5.5 * scale, 0)),
			color = Color3.fromRGB(101, 74, 50),
			material = Enum.Material.WoodPlanks,
		})
		tint(trunk, "GroundTint")
		local canopy = Kit.sphere({
			parent = model,
			name = "Canopy" .. index,
			size = Vector3.new(11 * scale, 12 * scale, 11 * scale),
			cframe = CFrame.new(position + Vector3.new(0, 13 * scale, 0)),
			color = PAL.FoliageTint,
			material = Enum.Material.Grass,
		})
		tint(canopy, "FoliageTint")
	end

	-- scattered rocks on L1
	for _, position in ipairs({
		Vector3.new(85, 30, 80), Vector3.new(-85, 30, -70), Vector3.new(30, 30, -95), Vector3.new(-100, 30, 55),
	}) do
		Kit.sphere({
			parent = model,
			name = "Boulder",
			size = Vector3.new(9, 7, 9),
			cframe = CFrame.new(position),
			color = Color3.fromRGB(120, 122, 118),
			material = Enum.Material.Slate,
		})
	end

	-- glow flowers on the settlement plateau
	for _, position in ipairs({
		Vector3.new(-20, 60, 22), Vector3.new(18, 60, 26), Vector3.new(-24, 60, -2), Vector3.new(24, 60, 6),
	}) do
		local bloom = Kit.glow({
			parent = model,
			name = "PlazaBloom",
			shape = Enum.PartType.Ball,
			size = Vector3.new(1.6, 1.6, 1.6),
			cframe = CFrame.new(position + Vector3.new(0, 0.9, 0)),
			color = PAL.AccentTint,
			canCollide = false,
		})
		tint(bloom, "AccentTint")
	end
end

local function buildHorizon(model)
	-- distant scenery ring (recolored per journey stage)
	for index = 1, 14 do
		local angle = math.rad(index * (360 / 14) + rand:NextNumber(-6, 6))
		local distance = rand:NextNumber(420, 640)
		local height = rand:NextNumber(-60, 10)
		local thickness = rand:NextNumber(20, 55)
		local monolith = Kit.part({
			parent = model,
			name = "Horizon" .. index,
			size = Vector3.new(thickness, rand:NextNumber(90, 190), thickness * 0.7),
			cframe = CFrame.new(math.cos(angle) * distance, height, math.sin(angle) * distance) * CFrame.Angles(0, angle, rand:NextNumber(-0.08, 0.08)),
			color = Color3.fromRGB(120, 122, 118),
			material = Enum.Material.Rock,
		})
		tint(monolith, "GroundTint")
	end

	-- passing cloud banks: slow bobbing spheres reinforce that Aruun travels
	for index = 1, 8 do
		local angle = math.rad(index * 45)
		local cloud = Kit.sphere({
			parent = model,
			name = "CloudBank" .. index,
			size = Vector3.new(150, 60, 120),
			cframe = CFrame.new(math.cos(angle) * 320, -20 - rand:NextNumber(0, 20), math.sin(angle) * 320),
			color = Color3.fromRGB(235, 240, 245),
			material = Enum.Material.Neon,
			transparency = 0.86,
			castShadow = false,
		})
		task.spawn(function()
			local baseY = cloud.Position.Y
			while cloud.Parent do
				local tween = game:GetService("TweenService"):Create(
					cloud,
					TweenInfo.new(rand:NextNumber(9, 16), Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ Position = cloud.Position + Vector3.new(0, 9, 0) }
				)
				tween:Play()
				task.wait(10)
				tween:Cancel()
				cloud.Position = Vector3.new(cloud.Position.X, baseY, cloud.Position.Z)
			end
		end)
	end

	-- drift streaks: particles streaming past the head read as forward motion
	local drift = Kit.part({
		parent = model,
		name = "DriftAnchor",
		size = Vector3.new(1, 1, 1),
		cframe = CFrame.new(0, 130, -140),
		color = Color3.fromRGB(255, 255, 255),
		transparency = 1,
		canCollide = false,
	})
	local streaks = Instance.new("ParticleEmitter")
	streaks.Color = ColorSequence.new(Color3.fromRGB(220, 235, 245))
	streaks.Rate = 5
	streaks.Lifetime = NumberRange.new(6, 9)
	streaks.Speed = NumberRange.new(55, 75)
	streaks.EmissionDirection = Enum.NormalId.Front -- -Z: scenery races behind us
	streaks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 9),
		NumberSequenceKeypoint.new(1, 12),
	})
	streaks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.3, 0.94),
		NumberSequenceKeypoint.new(1, 1),
	})
	streaks.LockedToPart = false
	streaks.Parent = drift
end

--=====================================================================
-- Entry point
--=====================================================================

function WorldBuilder.build()
	local creature = Instance.new("Model")
	creature.Name = "Aruun"
	creature.Parent = workspace

	local bodyFolder = Instance.new("Folder")
	bodyFolder.Name = "Environment"
	bodyFolder.Parent = creature
	local rigFolder = Instance.new("Folder")
	rigFolder.Name = "Rig"
	rigFolder.Parent = creature
	local nodesFolder = Instance.new("Folder")
	nodesFolder.Name = "GatherNodes"
	nodesFolder.Parent = creature
	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "BuildPlots"
	plotsFolder.Parent = creature

	buildBody(rigFolder)
	buildNeck(rigFolder, world.refs)
	buildTail(rigFolder, world.refs)
	buildPaths(bodyFolder)
	buildLandmarks(bodyFolder)
	buildWaterfall(bodyFolder)
	buildFlora(bodyFolder)
	buildHorizon(bodyFolder)
	buildSettlement(creature, plotsFolder)
	buildNodes(nodesFolder)

	world.creature = creature

	-- soft idle heartbeat parallax on the horizon handled by JourneyService
	return world
end

return WorldBuilder
