-- Path: ServerScriptService/BeastboundModules/BuilderKit
-- Procedural construction helpers. Every world asset is generated from code so
-- the project needs zero external model files.

local BuilderKit = {}

function BuilderKit.part(props)
	local part = Instance.new(props.className or "Part")
	if props.shape then
		part.Shape = props.shape
	end
	part.Name = props.name or "KitPart"
	part.Size = props.size or Vector3.new(4, 4, 4)
	part.CFrame = props.cframe or CFrame.new(0, 0, 0)
	part.Color = props.color or Color3.fromRGB(160, 160, 160)
	part.Material = props.material or Enum.Material.SmoothPlastic
	part.Anchored = props.anchored ~= false
	part.CanCollide = props.canCollide ~= false
	part.CanQuery = props.canQuery ~= false
	part.CanTouch = false
	part.CastShadow = props.castShadow ~= false
	part.Transparency = props.transparency or 0
	part.Reflectance = props.reflectance or 0
	if props.parent then
		part.Parent = props.parent
	end
	return part
end

function BuilderKit.sphere(props)
	local copy = table.clone(props)
	copy.shape = Enum.PartType.Ball
	return BuilderKit.part(copy)
end

function BuilderKit.wedge(props)
	local copy = table.clone(props)
	copy.shape = Enum.PartType.Wedge
	return BuilderKit.part(copy)
end

-- Upright cylinder: props.size = Vector3.new(height, diameter, diameter)
function BuilderKit.pillar(props)
	local part = BuilderKit.part(props)
	part.Shape = Enum.PartType.Cylinder
	part.Size = props.size or Vector3.new(10, 4, 4)
	part.CFrame = (props.cframe or CFrame.new(0, 0, 0)) * CFrame.Angles(0, 0, math.rad(90))
	return part
end

-- Solid ramp between two points. a/b are Vector3 surface positions.
function BuilderKit.ramp(props)
	local a, b = props.a, props.b
	local mid = (a + b) / 2
	local dist = (b - a).Magnitude
	local cf = CFrame.lookAt(mid + Vector3.new(0, 0.6, 0), b)
	return BuilderKit.part({
		parent = props.parent,
		name = props.name or "Ramp",
		size = Vector3.new(props.width or 10, 1.4, dist),
		cframe = cf,
		color = props.color,
		material = props.material or Enum.Material.SmoothPlastic,
	})
end

function BuilderKit.glow(props)
	local part = BuilderKit.part(props)
	part.Material = Enum.Material.Neon
	part.Color = props.color or Color3.fromRGB(120, 255, 190)
	part.Anchored = true
	return part
end

function BuilderKit.pointLight(parent, color, brightness, range)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Parent = parent
	return light
end

function BuilderKit.sparkle(parent, color, rate, speed, lifetime)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color)
	emitter.Rate = rate
	emitter.Speed = NumberRange.new(speed * 0.25, speed)
	emitter.Lifetime = NumberRange.new(lifetime * 0.6, lifetime)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.SpreadAngle = Vector2.new(35, 35)
	emitter.LightEmission = 0.8
	emitter.Parent = parent
	return emitter
end

function BuilderKit.playSoundAt(position, soundDef)
	local holder = Instance.new("Part")
	holder.Name = "BeastboundSFX"
	holder.Size = Vector3.new(1, 1, 1)
	holder.Position = position
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.Transparency = 1
	holder.Parent = workspace

	local sound = Instance.new("Sound")
	sound.SoundId = soundDef.SoundId
	sound.Volume = soundDef.Volume or 0.7
	sound.PlaybackSpeed = soundDef.Pitch or 1
	sound.RollOffMaxDistance = 260
	sound.Parent = holder
	sound.Ended:Once(function()
		holder:Destroy()
	end)
	sound:Play()
	task.delay(8, function()
		if holder.Parent then
			holder:Destroy()
		end
	end)
end

return BuilderKit
