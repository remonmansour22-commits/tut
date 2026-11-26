-- UNIT CLASH - server-side visuals. Everything created here replicates to
-- clients automatically, so the client only draws UI and camera work.

local UCConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("UCShared"):WaitForChild("UCConfig"))

local UCVisuals = {}

local rng = Random.new()

local function basePart(props)
	local part = Instance.new(props.className or "Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in pairs(props) do
		if key ~= "className" then
			part[key] = value
		end
	end
	return part
end

function UCVisuals.createUnitModel(def, teamId, position, parent)
	local team = UCConfig.TEAMS[teamId]
	local model = Instance.new("Model")
	model.Name = def.name

	local size = def.radius * 2
	local body = basePart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(size, size, size),
		Color = def.color,
		Material = Enum.Material.SmoothPlastic,
		CFrame = CFrame.new(position),
		Name = "Body",
	})
	body.Parent = model

	local ring = basePart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, size * 2.4, size * 2.4),
		Color = team.color,
		Material = Enum.Material.Neon,
		CFrame = CFrame.new(position - Vector3.new(0, def.radius - 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Name = "TeamRing",
	})
	ring.Parent = model

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Health"
	billboard.Size = UDim2.new(3.2, 0, 0.9, 0)
	billboard.StudsOffset = Vector3.new(0, def.radius + 1.4, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = body
	billboard.Parent = body

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.new(1, 0, 1, 0)
	back.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	back.BackgroundTransparency = 0.35
	back.BorderSizePixel = 0
	back.Parent = billboard

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, 0, 1, 0)
	fill.BackgroundColor3 = team.color
	fill.BorderSizePixel = 0
	fill.Parent = back

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = def.name
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.6
	label.Parent = billboard

	model.PrimaryPart = body
	model.Parent = parent
	return model
end

function UCVisuals.updateHealth(model, hp, maxHp)
	local body = model:FindFirstChild("Body")
	if not body then
		return
	end
	local billboard = body:FindFirstChild("Health")
	local fill = billboard and billboard:FindFirstChild("Fill")
	if fill then
		fill.Size = UDim2.new(math.clamp(hp / maxHp, 0, 1), 0, 1, 0)
	end
end

function UCVisuals.hitFlash(model)
	local body = model:FindFirstChild("Body")
	if not body then
		return
	end
	local flash = basePart({
		Shape = Enum.PartType.Ball,
		Size = body.Size * 1.15,
		Color = Color3.fromRGB(255, 255, 255),
		Material = Enum.Material.Neon,
		Transparency = 0.55,
		CFrame = body.CFrame,
	})
	flash.Parent = model
	game:GetService("Debris"):AddItem(flash, 0.08)
end

function UCVisuals.floatText(position, text, color)
	local holder = basePart({
		Size = Vector3.new(0.2, 0.2, 0.2),
		Transparency = 1,
		CFrame = CFrame.new(position + Vector3.new(rng:NextNumber(-1, 1), 1, rng:NextNumber(-1, 1))),
	})
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(4, 0, 1.6, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = holder
	gui.Parent = holder
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.4
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.Parent = gui
	holder.Parent = workspace
	game:GetService("TweenService"):Create(holder, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		CFrame = holder.CFrame + Vector3.new(0, 5, 0),
	}):Play()
	game:GetService("Debris"):AddItem(holder, 0.95)
end

function UCVisuals.deathBurst(model, color)
	local body = model and model:FindFirstChild("Body")
	local at = body and body.Position
	if model then
		model:Destroy()
	end
	if not at then
		return
	end
	for _ = 1, 8 do
		local shard = basePart({
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.5, 0.5, 0.5),
			Color = color,
			Material = Enum.Material.Neon,
			CFrame = CFrame.new(at),
		})
		shard.Parent = workspace
		game:GetService("TweenService"):Create(shard, TweenInfo.new(0.5), {
			CFrame = CFrame.new(at + Vector3.new(rng:NextNumber(-5, 5), rng:NextNumber(1, 6), rng:NextNumber(-5, 5))),
			Transparency = 1,
		}):Play()
		game:GetService("Debris"):AddItem(shard, 0.55)
	end
end

function UCVisuals.ringEffect(position, radius, color)
	local ring = basePart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 1, 1),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.2,
		CFrame = CFrame.new(Vector3.new(position.X, UCConfig.ARENA.BASE_Y + 0.2, position.Z)) * CFrame.Angles(0, 0, math.rad(90)),
	})
	ring.Parent = workspace
	game:GetService("TweenService"):Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.3, radius * 2, radius * 2),
		Transparency = 1,
	}):Play()
	game:GetService("Debris"):AddItem(ring, 0.5)
end

function UCVisuals.projectilePart(spec, position)
	return basePart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(0.7, 0.7, 0.7),
		Color = spec.color or Color3.fromRGB(255, 255, 255),
		Material = Enum.Material.Neon,
		CFrame = CFrame.new(position),
		Name = "UCProjectile",
	})
end

function UCVisuals.turretModel(position, teamColor)
	local model = Instance.new("Model")
	model.Name = "Turret"
	local base = basePart({
		Size = Vector3.new(2, 1, 2),
		Color = Color3.fromRGB(90, 90, 90),
		Material = Enum.Material.Metal,
		CFrame = CFrame.new(Vector3.new(position.X, UCConfig.ARENA.BASE_Y + 0.5, position.Z)),
	})
	base.Parent = model
	local barrel = basePart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.2, 1.2, 1.2),
		Color = teamColor,
		Material = Enum.Material.Neon,
		CFrame = CFrame.new(Vector3.new(position.X, UCConfig.ARENA.BASE_Y + 1.6, position.Z)),
	})
	barrel.Parent = model
	model.PrimaryPart = barrel
	model.Parent = workspace
	return model
end

function UCVisuals.padModel(position, radius)
	local pad = basePart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, radius * 2, radius * 2),
		Color = Color3.fromRGB(140, 240, 160),
		Material = Enum.Material.Neon,
		Transparency = 0.45,
		CFrame = CFrame.new(Vector3.new(position.X, UCConfig.ARENA.BASE_Y + 0.15, position.Z)) * CFrame.Angles(0, 0, math.rad(90)),
	})
	pad.Parent = workspace
	return pad
end

function UCVisuals.victoryBanner(winnerName, color)
	local cam = workspace.CurrentCamera
	local part = basePart({
		Size = Vector3.new(30, 6, 0.5),
		Color = color,
		Material = Enum.Material.Neon,
		CFrame = CFrame.new(Vector3.new(0, 26, 0)),
		Name = "UCVictoryBanner",
	})
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.new(1, 0, 1, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = part
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = winnerName .. " WINS!"
	label.TextScaled = true
	label.Font = Enum.Font.GothamBlack
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	part.Parent = workspace
	return part
end

return UCVisuals
