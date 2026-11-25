-- Path: ServerScriptService/BeastboundModules/StructureBuilder
-- Builds models for each structure in BuildingConfig.
-- Add a new building by adding a config entry PLUS a builder function here.

local ServerScriptService = game:GetService("ServerScriptService")
local TweenService = game:GetService("TweenService")
local Kit = require(ServerScriptService.BeastboundModules.BuilderKit)

local WOOD = Color3.fromRGB(122, 88, 58)
local WOOD_DARK = Color3.fromRGB(96, 68, 45)
local LEAF = Color3.fromRGB(96, 156, 74)
local STONE = Color3.fromRGB(140, 142, 148)
local GLOW = Color3.fromRGB(120, 255, 190)

local StructureBuilder = {}

-- Sits exactly on top of the 1-stud-thick plot pad.
local function canvas(base: CFrame)
	return base * CFrame.new(0, 0.5, 0)
end

local builders = {}

builders.Shelter = function(model, base)
	local c = canvas(base)
	Kit.part({ parent = model, name = "Floor", size = Vector3.new(16, 1, 16), cframe = c, color = WOOD_DARK, material = Enum.Material.WoodPlanks })
	Kit.part({ parent = model, name = "WallBack", size = Vector3.new(16, 9, 1.4), cframe = c * CFrame.new(0, 5, -7.3), color = WOOD, material = Enum.Material.WoodPlanks })
	Kit.part({ parent = model, name = "WallLeft", size = Vector3.new(1.4, 9, 14.6), cframe = c * CFrame.new(-7.3, 5, 0), color = WOOD, material = Enum.Material.WoodPlanks })
	Kit.part({ parent = model, name = "WallRight", size = Vector3.new(1.4, 9, 14.6), cframe = c * CFrame.new(7.3, 5, 0), color = WOOD, material = Enum.Material.WoodPlanks })
	Kit.part({ parent = model, name = "FrontL", size = Vector3.new(5, 9, 1.4), cframe = c * CFrame.new(-5.5, 5, 7.3), color = WOOD, material = Enum.Material.WoodPlanks })
	Kit.part({ parent = model, name = "FrontR", size = Vector3.new(5, 9, 1.4), cframe = c * CFrame.new(5.5, 5, 7.3), color = WOOD, material = Enum.Material.WoodPlanks })
	Kit.part({ parent = model, name = "FrontTop", size = Vector3.new(6, 3.4, 1.4), cframe = c * CFrame.new(0, 7.8, 7.3), color = WOOD, material = Enum.Material.WoodPlanks })
	Kit.wedge({ parent = model, name = "RoofL", size = Vector3.new(10.4, 5, 19), cframe = c * CFrame.new(-4.6, 12, 0) * CFrame.Angles(0, 0, math.rad(-34)), color = LEAF, material = Enum.Material.Grass })
	Kit.wedge({ parent = model, name = "RoofR", size = Vector3.new(10.4, 5, 19), cframe = c * CFrame.new(4.6, 12, 0) * CFrame.Angles(0, 0, math.rad(34)), color = LEAF, material = Enum.Material.Grass })
	local window = Kit.glow({ parent = model, name = "Window", size = Vector3.new(2, 2, 0.4), cframe = c * CFrame.new(-6.9, 6, 3.5), color = Color3.fromRGB(255, 190, 110) })
	Kit.pointLight(window, Color3.fromRGB(255, 190, 110), 0.8, 18)
	return c * CFrame.new(0, 9.5, 0)
end

builders.LookoutTower = function(model, base)
	local c = canvas(base)
	for _, corner in ipairs({ Vector3.new(-3, 0, -3), Vector3.new(3, 0, -3), Vector3.new(-3, 0, 3), Vector3.new(3, 0, 3) }) do
		Kit.part({ parent = model, name = "Leg", size = Vector3.new(1.6, 18, 1.6), cframe = c * CFrame.new(corner.X, 9, corner.Z), color = WOOD, material = Enum.Material.WoodPlanks })
	end
	Kit.part({ parent = model, name = "Deck", size = Vector3.new(11, 1.2, 11), cframe = c * CFrame.new(0, 18.5, 0), color = WOOD_DARK, material = Enum.Material.WoodPlanks })
	Kit.part({ parent = model, name = "RailA", size = Vector3.new(11, 1, 0.8), cframe = c * CFrame.new(0, 20.4, 5.1), color = WOOD, material = Enum.Material.WoodPlanks })
	Kit.part({ parent = model, name = "RailB", size = Vector3.new(11, 1, 0.8), cframe = c * CFrame.new(0, 20.4, -5.1), color = WOOD, material = Enum.Material.WoodPlanks })
	Kit.part({ parent = model, name = "RailC", size = Vector3.new(0.8, 1, 11), cframe = c * CFrame.new(-5.1, 20.4, 0), color = WOOD, material = Enum.Material.WoodPlanks })
	Kit.part({ parent = model, name = "RailD", size = Vector3.new(0.8, 1, 11), cframe = c * CFrame.new(5.1, 20.4, 0), color = WOOD, material = Enum.Material.WoodPlanks })
	for i = 1, 9 do
		Kit.part({
			parent = model,
			name = "Step",
			size = Vector3.new(5, 0.6, 2.2),
			cframe = c * CFrame.new(8.6, 1 + i * 2, -8.5 + i * 2.1),
			color = WOOD_DARK,
			material = Enum.Material.WoodPlanks,
		})
	end
	local lamp = Kit.glow({ parent = model, name = "Lantern", shape = Enum.PartType.Ball, size = Vector3.new(3, 3, 3), cframe = c * CFrame.new(0, 22.5, 0), color = GLOW })
	Kit.sparkle(lamp, GLOW, 1.5, 2, 1.4)
	Kit.pointLight(lamp, GLOW, 1.4, 40)
	return c * CFrame.new(0, 20, 0)
end

builders.ResonanceBeacon = function(model, base)
	local c = canvas(base)
	Kit.pillar({ parent = model, name = "Base", size = Vector3.new(4, 10, 10), cframe = c * CFrame.new(0, 2, 0), color = STONE, material = Enum.Material.Slate })
	Kit.pillar({ parent = model, name = "Column", size = Vector3.new(7, 2.2, 2.2), cframe = c * CFrame.new(0, 7, 0), color = STONE, material = Enum.Material.Slate })
	local crystal = Kit.glow({ parent = model, name = "Crystal", shape = Enum.PartType.Ball, size = Vector3.new(5, 5, 5), cframe = c * CFrame.new(0, 12, 0), color = GLOW })
	Kit.sparkle(crystal, GLOW, 4, 3, 1.8)
	Kit.pointLight(crystal, GLOW, 2, 55)

	local ring = Kit.glow({ parent = model, name = "Ring", size = Vector3.new(0.4, 8.5, 8.5), cframe = c * CFrame.new(0, 12, 0), color = GLOW, canCollide = false })
	ring.Shape = Enum.PartType.Cylinder
	ring.CFrame = c * CFrame.new(0, 12, 0) * CFrame.Angles(0, 0, math.rad(90))

	-- slow looping spin of the halo ring
	task.spawn(function()
		local spinCount = 0
		while ring.Parent do
			spinCount += 1
			local to = c * CFrame.new(0, 12, 0)
				* CFrame.Angles(0, 0, math.rad(90))
				* CFrame.Angles(math.rad(90 * spinCount), 0, 0)
			TweenService:Create(ring, TweenInfo.new(4, Enum.EasingStyle.Linear), { CFrame = to }):Play()
			task.wait(4)
		end
	end)
	return c * CFrame.new(0, 12, 0)
end

function StructureBuilder.build(structureId, baseCFrame, rotationStep)
	local builder = builders[structureId]
	assert(builder, "No StructureBuilder for " .. tostring(structureId))

	local model = Instance.new("Model")
	model.Name = structureId .. "_Structure"

	local orientedBase = baseCFrame * CFrame.Angles(0, math.rad(rotationStep * 90), 0)
	builder(model, orientedBase)

	model.PrimaryPart = model:FindFirstChild("Floor") or model:FindFirstChild("Base") or model:FindFirstChild("Deck")
	model:SetAttribute("StructureId", structureId)

	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Anchored = true
			inst.Transparency = 1
		end
	end
	model:PivotTo(orientedBase * CFrame.new(0, -6, 0))

	return model
end

function StructureBuilder.fadeIn(model, duration)
	local info = TweenInfo.new(duration or 1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local parts = {}
	for _, inst in ipairs(model:GetDescendants()) do
		if inst:IsA("BasePart") then
			table.insert(parts, inst)
		end
	end
	model:PivotTo(model:GetPivot() * CFrame.new(0, 6, 0))
	for _, part in ipairs(parts) do
		TweenService:Create(part, info, { Transparency = 0 }):Play()
	end
end

return StructureBuilder
