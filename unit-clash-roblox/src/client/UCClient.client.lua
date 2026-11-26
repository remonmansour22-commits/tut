-- UNIT CLASH - client v0.6: genuine 2D presentation. Full-screen battlefield
-- canvas (the 3D world is never visible), entry screen, unit roster, live 2D
-- battle renderer with pooled frames, effects, results and Battle Lab.
-- Server sends compact snapshots; this script draws everything.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer

local UCConfig = require(ReplicatedStorage:WaitForChild("UCShared"):WaitForChild("UCConfig"))
local UCShareCodec = require(ReplicatedStorage:WaitForChild("UCShared"):WaitForChild("UCShareCodec"))

local remotes = ReplicatedStorage:WaitForChild("UCRemotes")
local evAction = remotes:WaitForChild("UCAction")
local evState = remotes:WaitForChild("UCState")
local evResults = remotes:WaitForChild("UCResults")
local evLab = remotes:WaitForChild("UCLab")
local evToast = remotes:WaitForChild("UCToast")
local evBattle = remotes:WaitForChild("UCBattle")

local function act(cmd, args)
	evAction:FireServer(cmd, args or {})
end

-- ---------- SFX: pooled built-in Roblox sounds, throttled ----------
local SoundService = game:GetService("SoundService")
local SFX_DEFS = {
	hit = { id = "rbxasset://sounds/electronicpingshort.wav", vol = 0.22, pitch = { 0.9, 1.5 }, gap = 0.045 },
	shoot = { id = "rbxasset://sounds/snap.mp3", vol = 0.12, pitch = { 1.1, 1.7 }, gap = 0.07 },
	death = { id = "rbxasset://sounds/uuhhh.mp3", vol = 0.35, pitch = { 0.8, 1.15 }, gap = 0.09 },
	ability = { id = "rbxasset://sounds/swoosh.wav", vol = 0.28, pitch = { 0.95, 1.2 }, gap = 0.08 },
	impact = { id = "rbxasset://sounds/swordslash.wav", vol = 0.3, pitch = { 0.8, 1.1 }, gap = 0.1 },
	victory = { id = "rbxasset://sounds/swordlunge.wav", vol = 0.5, pitch = { 0.55, 0.55 }, gap = 0.5 },
	click = { id = "rbxasset://sounds/button.wav", vol = 0.35, pitch = { 0.95, 1.05 }, gap = 0.03 },
	place = { id = "rbxasset://sounds/unsheath.wav", vol = 0.25, pitch = { 1.0, 1.25 }, gap = 0.05 },
}
local SFX_FOR_EVENT = {
	hit = "hit", shoot = "shoot", death = "death", ability = "ability",
	rebirth = "ability", deviceDown = "impact",
}
local sfxPool, sfxLast = {}, {}
for i = 1, 12 do
	local snd = Instance.new("Sound")
	snd.Name = "UCSFX" .. i
	snd.Volume = 0.3
	snd.Parent = SoundService
	sfxPool[i] = snd
end
local sfxNext = 0
local function playSfx(kind)
	local def = SFX_DEFS[kind]
	if not def then
		return
	end
	local now = os.clock()
	if sfxLast[kind] and now - sfxLast[kind] < def.gap then
		return
	end
	sfxLast[kind] = now
	sfxNext = (sfxNext % #sfxPool) + 1
	local snd = sfxPool[sfxNext]
	snd.SoundId = def.id
	snd.Volume = def.vol * (0.85 + math.random() * 0.3)
	snd.PlaybackSpeed = def.pitch[1] + math.random() * (def.pitch[2] - def.pitch[1])
	snd:Play()
end

local THEME = {
	bg = Color3.fromRGB(11, 13, 24),
	panel = Color3.fromRGB(17, 20, 33),
	panel2 = Color3.fromRGB(24, 28, 45),
	card = Color3.fromRGB(30, 34, 52),
	gold = Color3.fromRGB(255, 208, 84),
	text = Color3.fromRGB(235, 238, 248),
	dim = Color3.fromRGB(148, 154, 175),
	red = Color3.fromRGB(255, 96, 88),
	green = Color3.fromRGB(88, 220, 130),
}

local state = {
	phase = "setup",
	mode = "sandbox",
	mission = nil,
	wave = 0,
	arena = "grassland",
	spent = { A = 0, B = 0 },
	budgets = { A = 500, B = 500 },
	deployed = { A = 0, B = 0 },
	factions = { A = nil, B = nil },
	selectedUnit = nil,
	selectedUpgrade = {},
	activeTeam = "A",
	speed = 1,
	paused = false,
	clock = 0,
	stagedCache = nil,
}

local function mk(class, props, parent)
	local inst = Instance.new(class)
	for k, v in pairs(props) do
		inst[k] = v
	end
	inst.Parent = parent
	return inst
end

local function corner(parent, radius)
	mk("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, parent)
end

local function panel(props, parent)
	local f = mk("Frame", props, parent)
	f.Active = true
	corner(f, 10)
	return f
end

local function label(props, parent)
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.Font = props.Font or Enum.Font.Gotham
	return mk("TextLabel", props, parent)
end

local function button(text, color, props, parent)
	local b = mk("TextButton", props or {}, parent)
	b.Text = text
	b.BackgroundColor3 = color or THEME.panel2
	b.TextColor3 = THEME.text
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.AutoButtonColor = true
	corner(b, 6)
	b.MouseButton1Click:Connect(function()
		playSfx("click")
	end)
	return b
end

local gui = mk("ScreenGui", {
	Name = "UCUI", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false,
}, player:WaitForChild("PlayerGui"))

-- ============================================================
-- BATTLEFIELD CANVAS - full-screen 2D arena, covers the 3D world
-- ============================================================

local field = mk("Frame", {
	Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = THEME.bg, BorderSizePixel = 0, ZIndex = 1,
}, gui)

local BAND_TOP, BAND_BOTTOM = 0.12, 0.92
local X0, X1 = 0.015, 0.985

local sky = mk("Frame", {
	Size = UDim2.new(1, 0, BAND_TOP, 0), BackgroundColor3 = Color3.fromRGB(24, 28, 52),
	BorderSizePixel = 0, ZIndex = 1,
}, field)
mk("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new(Color3.fromRGB(30, 34, 66), Color3.fromRGB(14, 16, 30)),
}, sky)

local ground = mk("Frame", {
	Size = UDim2.new(1, 0, BAND_BOTTOM - BAND_TOP, 0), Position = UDim2.new(0, 0, BAND_TOP, 0),
	BackgroundColor3 = UCConfig.ARENAS.grassland.ground, BorderSizePixel = 0, ZIndex = 1,
}, field)
mk("UIGradient", {
	Rotation = 90,
	Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 150, 150)),
}, ground)

mk("Frame", {
	Size = UDim2.new(1, 0, 1 - BAND_BOTTOM, 0), Position = UDim2.new(0, 0, BAND_BOTTOM, 0),
	BackgroundColor3 = Color3.fromRGB(9, 10, 18), BorderSizePixel = 0, ZIndex = 1,
}, field)

mk("Frame", { -- center line
	Size = UDim2.new(0, 2, BAND_BOTTOM - BAND_TOP, 0), Position = UDim2.new(0.5, -1, BAND_TOP, 0),
	BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.75, BorderSizePixel = 0, ZIndex = 2,
}, field)
mk("Frame", { -- azure half tint
	Size = UDim2.new(0.48, 0, BAND_BOTTOM - BAND_TOP, 0), Position = UDim2.new(0.01, 0, BAND_TOP, 0),
	BackgroundColor3 = UCConfig.TEAMS.A.color, BackgroundTransparency = 0.93, BorderSizePixel = 0, ZIndex = 2,
}, field)
mk("Frame", { -- crimson half tint
	Size = UDim2.new(0.48, 0, BAND_BOTTOM - BAND_TOP, 0), Position = UDim2.new(0.51, 0, BAND_TOP, 0),
	BackgroundColor3 = UCConfig.TEAMS.B.color, BackgroundTransparency = 0.93, BorderSizePixel = 0, ZIndex = 2,
}, field)

local centerCircle = mk("Frame", { -- stadium center circle
	Size = UDim2.new(0.16, 0, 0.62, 0), Position = UDim2.new(0.5, 0, (BAND_TOP + BAND_BOTTOM) / 2, 0),
	AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, ZIndex = 2,
}, field)
mk("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Thickness = 2, Transparency = 0.82 }, centerCircle)
for _, sx in ipairs({ 0.26, 0.74 }) do
	mk("Frame", {
		Size = UDim2.new(0, 2, BAND_BOTTOM - BAND_TOP, 0), Position = UDim2.new(sx, 0, BAND_TOP, 0),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.9, BorderSizePixel = 0, ZIndex = 2,
	}, field)
end

local dust = {}
for i = 1, 8 do
	local d = mk("Frame", {
		Size = UDim2.fromScale(0.004, 0.008), Position = UDim2.fromScale(math.random(), 0.2 + math.random() * 0.6),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.8, BorderSizePixel = 0, ZIndex = 2,
	}, field)
	corner(d, 999)
	table.insert(dust, { frame = d, speed = 0.01 + math.random() * 0.02, x = math.random(), y = 0.15 + math.random() * 0.65 })
end

local arenaNameTag = label({
	Size = UDim2.new(0, 300, 0, 22), Position = UDim2.new(0.5, -150, BAND_BOTTOM + 0.005, 0),
	Text = "", TextColor3 = THEME.dim, TextSize = 12, ZIndex = 2,
}, field)

local layerStaged = mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, ZIndex = 3 }, field)
local layerDevices = mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, ZIndex = 4 }, field)
local layerUnits = mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, ZIndex = 5 }, field)
local layerProj = mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, ZIndex = 6 }, field)
local layerFx = mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, ZIndex = 7 }, field)

local function simToScale(x, z)
	local fx = X0 + (x + UCConfig.ARENA.HALF) / (UCConfig.ARENA.HALF * 2) * (X1 - X0)
	local fy = BAND_TOP + (z + UCConfig.ARENA.DEPTH) / (UCConfig.ARENA.DEPTH * 2) * (BAND_BOTTOM - BAND_TOP)
	return math.clamp(fx, 0, 1), math.clamp(fy, 0, 1)
end

local function scaleToSim(fx, fy)
	local x = (fx - X0) / (X1 - X0) * (UCConfig.ARENA.HALF * 2) - UCConfig.ARENA.HALF
	local z = (fy - BAND_TOP) / (BAND_BOTTOM - BAND_TOP) * (UCConfig.ARENA.DEPTH * 2) - UCConfig.ARENA.DEPTH
	return x, z
end

-- ============================================================
-- 2D RENDERER - pooled frames, smooth interpolation
-- ============================================================

local unitPool = {}
local devicePool = {}
local projPool = {}
local targetPos = {}

local function unitSize(radius)
	return math.clamp(radius * 0.05, 0.035, 0.085)
end

local CATEGORY_GLYPHS = {
	Frontline = "\u{2B1F}", Heavy = "\u{2B22}", Agile = "\u{25B2}", Support = "\u{271A}",
	Ranged = "\u{25C6}", Specialist = "\u{2726}", Commander = "\u{2605}",
}
local CATEGORY_WIDTH = { Heavy = 1.28, Agile = 0.82, Ranged = 0.95, Support = 0.9 }

local function makeUnitVisual(id, def, team)
	local sz = unitSize(def.radius or 1)
	local szx = sz * (CATEGORY_WIDTH[def.category] or 1)
	local root = mk("Frame", {
		Size = UDim2.fromScale(szx, sz), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = def.color or Color3.fromRGB(200, 200, 200), BorderSizePixel = 0, ZIndex = 5,
	}, layerUnits)
	corner(root, 999)
	mk("UIGradient", { Rotation = 60, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(140, 140, 150)) }, root)
	mk("UIStroke", { Color = UCConfig.TEAMS[team].color, Thickness = 3, Transparency = 0.05 }, root)
	local shadow = mk("Frame", { -- ground shadow ellipse
		Size = UDim2.new(1.15, 0, 0.34, 0), Position = UDim2.fromScale(0.5, 0.94), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0), BackgroundTransparency = 0.65, BorderSizePixel = 0, ZIndex = 4,
	}, root)
	corner(shadow, 999)
	local core = mk("Frame", {
		Size = UDim2.fromScale(0.38, 0.38), Position = UDim2.fromScale(0.31, 0.24),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 6,
	}, root)
	corner(core, 999)
	local glyph = mk("TextLabel", {
		Size = UDim2.fromScale(0.72, 0.72), Position = UDim2.fromScale(0.5, 0.5), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1, Text = CATEGORY_GLYPHS[def.category] or "",
		TextColor3 = Color3.fromRGB(255, 255, 255), TextTransparency = 0.18,
		Font = Enum.Font.GothamBold, TextScaled = true, ZIndex = 6,
	}, root)
	local barBg = mk("Frame", {
		Size = UDim2.new(1.25, 0, 0.1, 0), Position = UDim2.fromScale(0.5, -0.1), AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Color3.fromRGB(8, 9, 14), BorderSizePixel = 0, Visible = false, ZIndex = 7,
	}, root)
	corner(barBg, 999)
	local barFill = mk("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundColor3 = THEME.green, BorderSizePixel = 0, ZIndex = 8,
	}, barBg)
	corner(barFill, 999)
	unitPool[id] = { root = root, barBg = barBg, barFill = barFill, size = sz, team = team, phase = (id:len() * 13) % 6.28, pulse = 0, wasAtk = false }
	targetPos[id] = nil
	return unitPool[id]
end

local function destroyUnitVisual(id)
	local v = unitPool[id]
	if v then
		v.root:Destroy()
		unitPool[id] = nil
		targetPos[id] = nil
	end
end

local function deviceKey(entry)
	return string.format("%s_%s_%d_%d", entry[1], entry[3], entry[4], entry[5])
end

local function makeDeviceVisual(key, entry)
	local kind, team = entry[1], entry[3]
	local r = entry[7] or 3
	local isTurret = kind == "turret"
	local sz = math.clamp(r * 0.055, 0.03, 0.075)
	local root = mk("Frame", {
		Size = UDim2.fromScale(sz, sz * 0.72), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = isTurret and UCConfig.TEAMS[team].color or Color3.fromRGB(90, 230, 160),
		BackgroundTransparency = isTurret and 0 or 0.55, BorderSizePixel = 0, ZIndex = 4,
	}, layerDevices)
	if isTurret then
		corner(root, 4)
		mk("UIStroke", { Color = Color3.fromRGB(255, 255, 255), Thickness = 2, Transparency = 0.35 }, root)
		mk("UIGradient", { Rotation = 60, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 150, 160)) }, root)
	else
		corner(root, 999)
		mk("UIStroke", { Color = Color3.fromRGB(160, 255, 200), Thickness = 2, Transparency = 0.5 }, root)
	end
	local barBg = mk("Frame", {
		Size = UDim2.new(1.1, 0, 0, 4), Position = UDim2.fromScale(0.5, -0.22), AnchorPoint = Vector2.new(0.5, 1),
		BackgroundColor3 = Color3.fromRGB(8, 9, 14), BorderSizePixel = 0, ZIndex = 4,
	}, root)
	corner(barBg, 999)
	local barFill = mk("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = THEME.green, BorderSizePixel = 0, ZIndex = 5 }, barBg)
	corner(barFill, 999)
	devicePool[key] = { root = root, barFill = barFill }
	return devicePool[key]
end

local function makeProjVisual()
	local p = mk("Frame", {
		Size = UDim2.fromScale(0.009, 0.016), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255), BorderSizePixel = 0, ZIndex = 6, Visible = false,
	}, layerProj)
	corner(p, 999)
	local tail = mk("Frame", {
		Size = UDim2.fromScale(0.55, 0.55), AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = Color3.fromRGB(255, 255, 255), BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 5,
	}, p)
	corner(tail, 999)
	return p
end

-- ---------- effect pools ----------

local popupPool, ringPool = {}, {}

local function spawnPopup(text, color, x, z, big)
	local entry
	for _, p in ipairs(popupPool) do
		if not p.active then
			entry = p
			break
		end
	end
	if not entry then
		if #popupPool >= 14 then
			return
		end
		entry = {
			frame = label({
				Size = UDim2.new(0, 120, 0, 18), AnchorPoint = Vector2.new(0.5, 0.5),
				Text = "", TextColor3 = THEME.text, TextSize = 14, Font = Enum.Font.GothamBold,
				TextStrokeTransparency = 0.5, BackgroundTransparency = 1, ZIndex = 9,
			}, layerFx),
			active = false,
		}
		table.insert(popupPool, entry)
	end
	entry.active = true
	entry.age = 0
	entry.dur = big and 1.1 or 0.8
	entry.text = text
	entry.color = color
	entry.big = big
	entry.fx, entry.fz = simToScale(x, z)
	entry.frame.Visible = true
	entry.frame.Text = text
	entry.frame.TextColor3 = color
	entry.frame.TextSize = big and 18 or 13
end

local function spawnRing(color, x, z, r, dur)
	local entry
	for _, p in ipairs(ringPool) do
		if not p.active then
			entry = p
			break
		end
	end
	if not entry then
		if #ringPool >= 10 then
			return
		end
		local frame = mk("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 8,
		}, layerFx)
		local stroke = mk("UIStroke", { Color = color, Thickness = 3, Transparency = 0 }, frame)
		corner(frame, 999)
		entry = { frame = frame, stroke = stroke, active = false }
		table.insert(ringPool, entry)
	end
	entry.active = true
	entry.age = 0
	entry.dur = dur or 0.45
	entry.color = color
	entry.r = r or 4
	entry.fx, entry.fz = simToScale(x, z)
	entry.frame.Visible = true
	entry.stroke.Color = color
end

local function teamColorOf(team)
	return UCConfig.TEAMS[team] and UCConfig.TEAMS[team].color or Color3.fromRGB(200, 200, 200)
end

local FX_STYLES = {
	hit = function(e) spawnPopup("-" .. math.max(1, math.floor(e[4] or 1)), THEME.red, e[2], e[3], false) end,
	heal = function(e) spawnPopup("+" .. math.max(1, math.floor(e[4] or 1)), THEME.green, e[2], e[3], false) end,
	death = function(e) spawnRing(teamColorOf(e[5]), e[2], e[3], 3, 0.5) end,
	rebirth = function(e)
		spawnPopup("REBIRTH!", Color3.fromRGB(255, 190, 90), e[2], e[3], true)
		spawnRing(Color3.fromRGB(255, 150, 60), e[2], e[3], e[4] or 8, 0.6)
	end,
	ring = function(e) spawnRing(Color3.fromRGB(200, 120, 255), e[2], e[3], e[4] or 6, 0.45) end,
	ability = function(e) spawnPopup(tostring(e[5] or "ABILITY"), Color3.fromRGB(255, 230, 150), e[2], e[3], false) end,
	deviceDown = function(e)
		spawnPopup("DOWN", Color3.fromRGB(200, 200, 210), e[2], e[3], false)
		spawnRing(Color3.fromRGB(255, 120, 90), e[2], e[3], 4, 0.5)
	end,
	shoot = function(e) spawnRing(Color3.fromRGB(255, 255, 255), e[2], e[3], 1.2, 0.18) end,
	despawn = function(e) spawnRing(Color3.fromRGB(120, 120, 130), e[2], e[3], 2, 0.3) end,
	victory = function()
		playSfx("victory")
	end,
	turret = function() end,
	pad = function() end,
}

local animClock = 0
local shake = 0

local function handleFx(fxList)
	for _, e in ipairs(fxList) do
		local fn = FX_STYLES[e[1]]
		if fn then
			fn(e)
		end
		local sk = SFX_FOR_EVENT[e[1]]
		if sk then
			playSfx(sk)
		end
		if e[1] == "death" or e[1] == "deviceDown" then
			shake = math.min(0.014, shake + 0.006)
		elseif e[1] == "rebirth" then
			shake = math.min(0.02, shake + 0.01)
		end
	end
end

-- ---------- live snapshot application ----------

local latestSnapshot = nil

evBattle.OnClientEvent:Connect(function(snap)
	latestSnapshot = snap
end)

local function applySnapshot(snap)
	local seen = {}
	for _, e in ipairs(snap.units) do
		local id = tostring(e[1])
		seen[id] = true
		local def = UCConfig.get(e[2]) or { color = nil, radius = 1 }
		local v = unitPool[id] or makeUnitVisual(id, def, e[3])
		local fx, fz = simToScale(e[4], e[5])
		if not targetPos[id] then
			v.root.Position = UDim2.fromScale(fx, fz)
		end
		targetPos[id] = { fx, fz }
		local atk = e[9] == true
		if atk and not v.wasAtk then
			v.pulse = 1
		end
		v.wasAtk = atk
		local frac = math.clamp(e[6] / math.max(1, e[7]), 0, 1)
		v.barBg.Visible = frac < 0.999
		v.barFill.Size = UDim2.fromScale(frac, 1)
		v.barFill.BackgroundColor3 = Color3.fromRGB(255, 90, 80):Lerp(THEME.green, frac)
	end
	for id in pairs(unitPool) do
		if not seen[id] then
			destroyUnitVisual(id)
		end
	end

	local devSeen = {}
	for _, d in ipairs(snap.devs or {}) do
		local key = deviceKey(d)
		devSeen[key] = true
		local v = devicePool[key] or makeDeviceVisual(key, d)
		local fx, fz = simToScale(d[4], d[5])
		v.root.Position = UDim2.fromScale(fx, fz)
		v.barFill.Size = UDim2.fromScale(math.clamp(d[5] / math.max(1, d[6]), 0, 1), 1)
	end
	for key, v in pairs(devicePool) do
		if not devSeen[key] then
			v.root:Destroy()
			devicePool[key] = nil
		end
	end

	local projCount = 0
	for _, p in ipairs(snap.projs or {}) do
		projCount = projCount + 1
		local v = projPool[projCount]
		if not v then
			v = makeProjVisual()
			projPool[projCount] = v
		end
		local fx, fz = simToScale(p[1], p[2])
		if v.Visible then
			v.prevX, v.prevY = v.Position.X.Scale, v.Position.Y.Scale
		else
			v.prevX, v.prevY = fx, fz
		end
		v.Position = UDim2.fromScale(fx, fz)
		v.BackgroundColor3 = teamColorOf(p[3])
		v.Visible = true
		local dirX, dirY = fx - (v.prevX or fx), fz - (v.prevY or fz)
		local len = math.sqrt(dirX * dirX + dirY * dirY)
		if len > 0.0001 then
			v.Rotation = math.deg(math.atan2(dirY, dirX))
		end
	end
	for i = projCount + 1, #projPool do
		projPool[i].Visible = false
	end

	handleFx(snap.fx or {})
end

-- ---------- animation loop ----------

RunService.Heartbeat:Connect(function(dt)
	local cam = workspace.CurrentCamera
	if cam and cam.CameraType ~= Enum.CameraType.Scriptable then
		cam.CameraType = Enum.CameraType.Scriptable
		cam.CFrame = CFrame.new(Vector3.new(0, 300, 0), Vector3.new(0, 0, 0))
	end
	animClock = animClock + dt

	if latestSnapshot then
		applySnapshot(latestSnapshot)
		latestSnapshot = nil
	end

	for id, v in pairs(unitPool) do
		local t = targetPos[id]
		if t then
			v.root.Position = v.root.Position:Lerp(UDim2.fromScale(t[1], t[2]), 0.35)
		end
		v.pulse = v.pulse * math.exp(-dt * 7)
		local pop = 1 + 0.3 * v.pulse
		v.root.Size = UDim2.fromScale(v.size * pop, v.size * pop)
		local bob = math.sin(animClock * 3 + v.phase) * 0.003
		local lunge = v.pulse * (v.team == "A" and 0.008 or -0.008)
		local base = v.root.Position
		v.root.Position = UDim2.fromScale(base.X.Scale + lunge, base.Y.Scale + bob - v.pulse * 0.004)
	end

	for _, d in ipairs(dust) do
		d.x = (d.x + d.speed * dt) % 1
		d.frame.Position = UDim2.fromScale(d.x, d.y + math.sin(animClock + d.speed * 100) * 0.01)
	end

	if shake > 0.0005 then
		field.Position = UDim2.fromOffset((math.random() * 2 - 1) * shake * 900, (math.random() * 2 - 1) * shake * 600)
		shake = shake * math.exp(-dt * 6)
	else
		field.Position = UDim2.fromOffset(0, 0)
	end

	for _, p in ipairs(popupPool) do
		if p.active then
			p.age = p.age + dt
			local a = p.age / p.dur
			if a >= 1 then
				p.active = false
				p.frame.Visible = false
			else
				p.frame.Position = UDim2.new(p.fx, 0, p.fz - a * 0.06, 0)
				p.frame.TextTransparency = a
				p.frame.TextStrokeTransparency = 0.5 + a * 0.5
			end
		end
	end

	for _, r in ipairs(ringPool) do
		if r.active then
			r.age = r.age + dt
			local a = r.age / r.dur
			if a >= 1 then
				r.active = false
				r.frame.Visible = false
			else
				local rr = r.r * (0.4 + a * 1.1)
				r.frame.Size = UDim2.new(rr / (UCConfig.ARENA.HALF * 2) * (X1 - X0), 0, rr / (UCConfig.ARENA.DEPTH * 2) * (BAND_BOTTOM - BAND_TOP), 0)
				r.frame.Position = UDim2.new(r.fx, 0, r.fz, 0)
				r.stroke.Transparency = a
			end
		end
	end
end)

-- ============================================================
-- ENTRY MENU
-- ============================================================

local menu = mk("ScreenGui", {
	Name = "UCMenu", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 50,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, player:WaitForChild("PlayerGui"))

local menuBg = mk("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(10, 12, 22), BorderSizePixel = 0 }, menu)
mk("UIGradient", {
	Rotation = 115,
	Color = ColorSequence.new(Color3.fromRGB(16, 18, 38), Color3.fromRGB(34, 20, 48)),
}, menuBg)

local clashA = mk("Frame", {
	Size = UDim2.new(0, 340, 0, 340), Position = UDim2.new(0.5, -510, 0.42, -170),
	BackgroundColor3 = UCConfig.TEAMS.A.color, BackgroundTransparency = 0.82, BorderSizePixel = 0, ZIndex = 2,
}, menu)
corner(clashA, 999)
local clashB = mk("Frame", {
	Size = UDim2.new(0, 340, 0, 340), Position = UDim2.new(0.5, 170, 0.42, -170),
	BackgroundColor3 = UCConfig.TEAMS.B.color, BackgroundTransparency = 0.82, BorderSizePixel = 0, ZIndex = 2,
}, menu)
corner(clashB, 999)

local title = label({ Size = UDim2.new(1, 0, 0, 96), Position = UDim2.new(0, 0, 0.24, 0), Text = "UNIT CLASH", TextColor3 = Color3.fromRGB(255, 255, 255), Font = Enum.Font.GothamBlack, TextSize = 76, ZIndex = 3 }, menu)
mk("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 232, 150), Color3.fromRGB(255, 170, 60)) }, title)
mk("UIStroke", { Color = Color3.fromRGB(60, 40, 10), Thickness = 2, Transparency = 0.2 }, title)
label({ Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 0.24, 98), Text = "2D  AUTONOMOUS  BATTLE  SANDBOX", TextColor3 = THEME.dim, Font = Enum.Font.GothamBold, TextSize = 16, ZIndex = 3 }, menu)

local btnPlay = button("ENTER BATTLE", Color3.fromRGB(52, 160, 92), { Size = UDim2.new(0, 280, 0, 58), Position = UDim2.new(0.5, -140, 0.52, 0), TextSize = 20, ZIndex = 3 }, menu)
local btnQuick = button("QUICK START - auto-fill both armies and fight", Color3.fromRGB(90, 70, 130), { Size = UDim2.new(0, 340, 0, 40), Position = UDim2.new(0.5, -170, 0.52, 70), TextSize = 13, ZIndex = 3 }, menu)
btnQuick.MouseButton1Click:Connect(function()
	menu.Enabled = false
	gui.Enabled = true
	act("randomArmyA", {})
	act("fillEnemy", {})
	act("start", {})
end)
label({ Size = UDim2.new(1, 0, 0, 22), Position = UDim2.new(0, 0, 0.52, 118), Text = "15 units - 4 factions - 6 arenas - Battle Lab - tournaments", TextColor3 = THEME.dim, TextSize = 13, ZIndex = 3 }, menu)
label({ Size = UDim2.new(1, 0, 0, 20), Position = UDim2.new(0, 0, 1, -30), Text = "v0.6 - pick a unit, click your half, START. Deterministic simulation, real counterplay.", TextColor3 = Color3.fromRGB(110, 115, 135), TextSize = 11, ZIndex = 3 }, menu)

task.spawn(function()
	local t = 0
	while menu.Parent do
		local dt = RunService.RenderStepped:Wait()
		t = t + dt
		local pull = 60 + math.sin(t * 1.6) * 34
		clashA.Position = UDim2.new(0.5, -170 - pull, 0.42, -170)
		clashB.Position = UDim2.new(0.5, 170 + pull, 0.42, -170)
	end
end)

btnPlay.MouseButton1Click:Connect(function()
	menu.Enabled = false
	gui.Enabled = true
end)

-- ============================================================
-- COMMAND UI
-- ============================================================

local hintBar = label({
	Size = UDim2.new(0, 560, 0, 34), Position = UDim2.new(0.5, -280, 0.5, 12),
	BackgroundColor3 = Color3.fromRGB(20, 24, 40), BackgroundTransparency = 0.1,
	Text = "1) PICK A UNIT ON THE LEFT      2) CLICK YOUR HALF TO PLACE      3) PRESS START",
	TextColor3 = THEME.gold, TextSize = 13, Font = Enum.Font.GothamBold, ZIndex = 12,
}, gui)
corner(hintBar, 6)

local toast = label({
	Size = UDim2.new(0, 380, 0, 34), Position = UDim2.new(0.5, -190, 0, 46),
	BackgroundColor3 = Color3.fromRGB(25, 25, 35), BackgroundTransparency = 0.15,
	TextColor3 = Color3.fromRGB(255, 230, 160), TextSize = 15, Text = "", Visible = false, ZIndex = 20,
}, gui)
corner(toast)

task.spawn(function()
	while true do
		local message = evToast.OnClientEvent:Wait()
		toast.Text = tostring(message)
		toast.Visible = true
		task.wait(2.2)
		toast.Visible = false
	end
end)

-- ---------- top bar ----------

local topBar = panel({ Size = UDim2.new(1, -20, 0, 44), Position = UDim2.new(0, 10, 0, 6), BackgroundColor3 = THEME.panel, BackgroundTransparency = 0.08, ZIndex = 10 }, gui)
label({ Size = UDim2.new(0, 140, 1, 0), Position = UDim2.new(0, 10, 0, 0), Text = "UNIT CLASH", TextColor3 = THEME.gold, Font = Enum.Font.GothamBlack, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11 }, topBar)
local statusLabel = label({ Size = UDim2.new(0, 470, 1, 0), Position = UDim2.new(0, 150, 0, 0), Text = "", TextColor3 = THEME.text, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11 }, topBar)

local function barButton(text, color, order)
	return button(text, color, { Size = UDim2.new(0, 88, 0, 32), Position = UDim2.new(1, -(order * 96) - 10, 0.5, -16), ZIndex = 11 }, topBar)
end

local btnStart = barButton("START", Color3.fromRGB(50, 160, 80), 1)
local btnPause = barButton("PAUSE", THEME.panel2, 2)
local btnSpeed = barButton("1x", THEME.panel2, 3)
local btnClear = barButton("CLEAR", Color3.fromRGB(90, 70, 70), 4)
local btnModes = barButton("MODES", Color3.fromRGB(80, 70, 110), 5)
local btnMenu = barButton("MENU", Color3.fromRGB(60, 65, 90), 6)
local btnLab = barButton("LAB", Color3.fromRGB(70, 75, 105), 7)

local SPEEDS = { 1, 2, 4, 0.5 }
local speedIndex = 1
btnStart.MouseButton1Click:Connect(function() act("start") end)
btnPause.MouseButton1Click:Connect(function() act("pause") end)
btnClear.MouseButton1Click:Connect(function() act("clear") end)
btnSpeed.MouseButton1Click:Connect(function()
	speedIndex = speedIndex % #SPEEDS + 1
	btnSpeed.Text = SPEEDS[speedIndex] .. "x"
	act("speed", { value = SPEEDS[speedIndex] })
end)
btnMenu.MouseButton1Click:Connect(function()
	menu.Enabled = true
end)

-- ---------- modes panel ----------

local modesPanel = panel({ Size = UDim2.new(0, 300, 0, 330), Position = UDim2.new(0.5, -150, 0.5, -165), BackgroundColor3 = THEME.panel, BackgroundTransparency = 0.03, Visible = false, ZIndex = 15 }, gui)
label({ Size = UDim2.new(1, 0, 0, 40), Text = "GAME MODES", TextColor3 = THEME.gold, Font = Enum.Font.GothamBlack, TextSize = 18, ZIndex = 16 }, modesPanel)

local modeList = mk("ScrollingFrame", { Size = UDim2.new(1, -20, 1, -100), Position = UDim2.new(0, 10, 0, 44), BackgroundTransparency = 1, ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 16 }, modesPanel)
mk("UIListLayout", { Padding = UDim.new(0, 6) }, modeList)

local function modeRow(name, desc, onClick)
	local row = button(name, THEME.card, { Size = UDim2.new(1, -8, 0, 52), ZIndex = 16 }, modeList)
	label({ Size = UDim2.new(1, -16, 0, 18), Position = UDim2.new(0, 8, 0, 6), Text = name, TextColor3 = THEME.text, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 17 }, row)
	label({ Size = UDim2.new(1, -16, 0, 26), Position = UDim2.new(0, 8, 0, 24), Text = desc, TextColor3 = THEME.dim, TextSize = 10, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 17 }, row)
	row.MouseButton1Click:Connect(onClick)
end

modeRow("Sandbox", "Free placement, 500 budgets, no restrictions.", function() act("setMode", { mode = "sandbox" }) end)
modeRow("Survival", "Endless waves. Survivors keep their wounds.", function() act("setMode", { mode = "survival" }) end)
modeRow("Challenge of the Day", "Same seeded challenge for everyone today.", function() act("setMode", { mode = "daily" }) end)
for i, mission in ipairs(UCConfig.MISSIONS) do
	modeRow(i .. ". " .. mission.name, mission.blurb, function() act("setMode", { mode = "campaign", mission = i }) end)
end
button("CLOSE", Color3.fromRGB(90, 70, 70), { Size = UDim2.new(0, 100, 0, 32), Position = UDim2.new(0.5, -50, 1, -40), ZIndex = 16 }, modesPanel).MouseButton1Click:Connect(function()
	modesPanel.Visible = false
end)
btnModes.MouseButton1Click:Connect(function()
	modesPanel.Visible = not modesPanel.Visible
end)

-- ---------- team toggle + faction ----------

local teamToggle = panel({ Size = UDim2.new(0, 300, 0, 72), Position = UDim2.new(0.5, -150, 0, 56), BackgroundColor3 = THEME.panel, BackgroundTransparency = 0.12, ZIndex = 10 }, gui)
local btnTeamA, btnTeamB
local function refreshTeamButtons()
	btnTeamA.BackgroundColor3 = state.activeTeam == "A" and UCConfig.TEAMS.A.color or Color3.fromRGB(45, 50, 70)
	btnTeamB.BackgroundColor3 = state.activeTeam == "B" and UCConfig.TEAMS.B.color or Color3.fromRGB(45, 50, 70)
end
local function teamButton(team, offset)
	local t = UCConfig.TEAMS[team]
	local b = button("PLACE: " .. t.name, t.color, { Size = UDim2.new(0.42, -6, 0, 30), Position = UDim2.new(offset, 4, 0, 4), ZIndex = 11 }, teamToggle)
	b.MouseButton1Click:Connect(function()
		state.activeTeam = team
		refreshTeamButtons()
	end)
	return b
end
btnTeamA = teamButton("A", 0)
btnTeamB = teamButton("B", 0.42)
local factionLabel = label({ Size = UDim2.new(1, -10, 0, 26), Position = UDim2.new(0, 6, 0, 40), Text = "", TextColor3 = THEME.dim, TextSize = 11, ZIndex = 11 }, teamToggle)

local function cycleFaction(team)
	local ids = {}
	for id in pairs(UCConfig.FACTIONS) do
		table.insert(ids, id)
	end
	table.sort(ids)
	local current = state.factions[team]
	local nextIndex = 1
	for i, id in ipairs(ids) do
		if id == current then
			nextIndex = i + 1
		end
	end
	if nextIndex > #ids then
		nextIndex = 1
	end
	act("setFaction", { team = team, id = ids[nextIndex] })
end

btnTeamA.MouseButton2Click:Connect(function() cycleFaction("A") end)
btnTeamB.MouseButton2Click:Connect(function() cycleFaction("B") end)

-- ---------- unit palette + upgrades ----------

local palette = mk("ScrollingFrame", { Size = UDim2.new(0, 230, 1, -230), Position = UDim2.new(0, 10, 0, 140), BackgroundColor3 = THEME.panel, BackgroundTransparency = 0.08, ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 10 }, gui)
corner(palette)
mk("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, palette)

local cardByUnit = {}
local upgradePanel = panel({ Size = UDim2.new(0, 230, 0, 84), Position = UDim2.new(0, 10, 1, -84), BackgroundColor3 = THEME.panel, BackgroundTransparency = 0.08, Visible = false, ZIndex = 10 }, gui)
local upgradeTitle = label({ Size = UDim2.new(1, -10, 0, 18), Position = UDim2.new(0, 6, 0, 4), Text = "", TextColor3 = THEME.gold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11 }, upgradePanel)
local up1, up2

for order, unitId in ipairs(UCConfig.ORDER) do
	local def = UCConfig.get(unitId)
	local card = button("", THEME.card, { Size = UDim2.new(1, -12, 0, 64), LayoutOrder = order, ZIndex = 11 }, palette)
	corner(card, 6)
	local selStroke = mk("UIStroke", { Color = THEME.gold, Thickness = 2, Transparency = 1 }, card)
	mk("Frame", { Size = UDim2.new(0, 8, 1, -10), Position = UDim2.new(0, 5, 0, 5), BackgroundColor3 = def.color, BorderSizePixel = 0, ZIndex = 12 }, card)
	label({ Size = UDim2.new(1, -30, 0, 18), Position = UDim2.new(0, 20, 0, 6), Text = def.name .. "  (" .. def.cost .. ")", TextColor3 = THEME.text, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 12 }, card)
	label({ Size = UDim2.new(1, -30, 0, 26), Position = UDim2.new(0, 20, 0, 25), Text = def.desc .. "  -  Lv" .. def.unlockLevel .. "+", TextColor3 = THEME.dim, TextSize = 9, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 12 }, card)
	cardByUnit[unitId] = card
	card.MouseButton1Click:Connect(function()
		state.selectedUnit = unitId
		for cid, c in pairs(cardByUnit) do
			c.BackgroundColor3 = cid == unitId and Color3.fromRGB(52, 66, 46) or THEME.card
			local st = c:FindFirstChildOfClass("UIStroke")
			if st then
				st.Transparency = cid == unitId and 0 or 1
			end
		end
		local ups = UCConfig.upgradesFor(unitId)
		upgradeTitle.Text = "UPGRADE - " .. def.name
		if up1 then
			up1:Destroy()
		end
		if up2 then
			up2:Destroy()
		end
		local function upgradeButton(index)
			local b = button(ups[index] and (ups[index].name .. ": " .. ups[index].desc) or "No upgrade", THEME.panel2, { Size = UDim2.new(0.5, -8, 0, 44), Position = UDim2.new(index == 1 and 0 or 0.5, 4, 0, 30), ZIndex = 12 }, upgradePanel)
			b.MouseButton1Click:Connect(function()
				state.selectedUpgrade[unitId] = ups[index] and ups[index].id or nil
				b.BackgroundColor3 = Color3.fromRGB(70, 90, 60)
				local other = index == 1 and up2 or up1
				if other then
					other.BackgroundColor3 = THEME.panel2
				end
			end)
			return b
		end
		up1 = upgradeButton(1)
		up2 = upgradeButton(2)
		upgradePanel.Visible = true
	end)
end

-- ---------- arena + tools row ----------

local toolsRow = panel({ Size = UDim2.new(0, 250, 0, 120), Position = UDim2.new(1, -260, 1, -130), BackgroundColor3 = THEME.panel, BackgroundTransparency = 0.08, ZIndex = 10 }, gui)
local arenaBtn = button("ARENA: Grassland", THEME.panel2, { Size = UDim2.new(1, -16, 0, 28), Position = UDim2.new(0, 8, 0, 8), ZIndex = 11 }, toolsRow)
arenaBtn.MouseButton1Click:Connect(function()
	local ids = {}
	for id in pairs(UCConfig.ARENAS) do
		table.insert(ids, id)
	end
	table.sort(ids)
	local current = 1
	for i, id in ipairs(ids) do
		if id == state.arena then
			current = i
		end
	end
	local nextId = ids[current % #ids + 1]
	act("setArena", { id = nextId })
	arenaBtn.Text = "ARENA: " .. UCConfig.ARENAS[nextId].name
end)

local btnLine = button("LINE", THEME.panel2, { Size = UDim2.new(0.31, -6, 0, 26), Position = UDim2.new(0, 8, 0, 42), ZIndex = 11 }, toolsRow)
local btnWall = button("WALL", THEME.panel2, { Size = UDim2.new(0.31, -6, 0, 26), Position = UDim2.new(0.345, 0, 0, 42), ZIndex = 11 }, toolsRow)
local btnSpread = button("SPREAD", THEME.panel2, { Size = UDim2.new(0.31, -6, 0, 26), Position = UDim2.new(0.69, 0, 0, 42), ZIndex = 11 }, toolsRow)
local btnRandom = button("RANDOM ARMY", Color3.fromRGB(70, 60, 90), { Size = UDim2.new(1, -16, 0, 26), Position = UDim2.new(0, 8, 0, 74), ZIndex = 11 }, toolsRow)
local btnEnemy = button("ENEMY AI", Color3.fromRGB(150, 80, 60), { Size = UDim2.new(1, -16, 0, 26), Position = UDim2.new(0, 8, 0, 104), ZIndex = 11 }, toolsRow)

btnLine.MouseButton1Click:Connect(function() act("formation", { team = state.activeTeam, kind = "line" }) end)
btnWall.MouseButton1Click:Connect(function() act("formation", { team = state.activeTeam, kind = "wall" }) end)
btnSpread.MouseButton1Click:Connect(function() act("formation", { team = state.activeTeam, kind = "spread" }) end)
btnRandom.MouseButton1Click:Connect(function() act("randomArmyA", {}) end)
btnEnemy.MouseButton1Click:Connect(function() act("fillEnemy", {}) end)

-- ---------- saves + share ----------

local savesRow = panel({ Size = UDim2.new(0, 250, 0, 106), Position = UDim2.new(1, -260, 1, -242), BackgroundColor3 = THEME.panel, BackgroundTransparency = 0.08, ZIndex = 10 }, gui)
local saveBox = mk("TextBox", { Size = UDim2.new(0.55, -12, 0, 26), Position = UDim2.new(0, 8, 0, 8), BackgroundColor3 = THEME.card, TextColor3 = THEME.text, Text = "", PlaceholderText = "setup name", TextSize = 12, Font = Enum.Font.Gotham, ClearTextOnFocus = false, ZIndex = 11 }, savesRow)
corner(saveBox, 6)
local btnSave = button("SAVE", THEME.panel2, { Size = UDim2.new(0.45, -12, 0, 26), Position = UDim2.new(0.55, 0, 0, 8), ZIndex = 11 }, savesRow)
local btnShare = button("SHARE CODE", Color3.fromRGB(60, 70, 100), { Size = UDim2.new(0.55, -12, 0, 26), Position = UDim2.new(0, 8, 0, 40), ZIndex = 11 }, savesRow)
local btnImport = button("IMPORT", Color3.fromRGB(60, 70, 100), { Size = UDim2.new(0.45, -12, 0, 26), Position = UDim2.new(0.55, 0, 0, 40), ZIndex = 11 }, savesRow)
local shareBox = mk("TextBox", { Size = UDim2.new(1, -16, 0, 44), Position = UDim2.new(0, 8, 0, 70), BackgroundColor3 = THEME.card, TextColor3 = THEME.text, Text = "", PlaceholderText = "UC1.... paste code here", TextSize = 10, Font = Enum.Font.Code, TextWrapped = true, ClearTextOnFocus = false, ZIndex = 11 }, savesRow)
corner(shareBox, 6)

btnSave.MouseButton1Click:Connect(function()
	local name = saveBox.Text
	if #name > 0 then
		act("saveSetup", { name = name })
	end
end)
btnImport.MouseButton1Click:Connect(function()
	local code = shareBox.Text
	if #code > 4 then
		local config = UCShareCodec.decode(code)
		if config then
			act("importCode", { code = code })
		else
			toast.Text = "Invalid share code"
			toast.Visible = true
			task.delay(2, function() toast.Visible = false end)
		end
	end
end)

btnShare.MouseButton1Click:Connect(function()
	if state.stagedCache then
		local code = UCShareCodec.encode(state.stagedCache)
		if code then
			shareBox.Text = code
			toast.Text = "Share code generated"
			toast.Visible = true
			task.delay(1.5, function() toast.Visible = false end)
		end
	end
end)

-- ---------- momentum bar ----------

local momWrap = mk("Frame", { Size = UDim2.new(0.6, 0, 0, 18), Position = UDim2.new(0.2, 0, 1, -30), BackgroundColor3 = Color3.fromRGB(25, 28, 38), BackgroundTransparency = 0.2, ZIndex = 10 }, gui)
corner(momWrap, 4)
local momA = mk("Frame", { Size = UDim2.new(0.5, 0, 1, 0), BackgroundColor3 = UCConfig.TEAMS.A.color, BorderSizePixel = 0, ZIndex = 11 }, momWrap)
local momB = mk("Frame", { Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.new(0.5, 0, 0, 0), BackgroundColor3 = UCConfig.TEAMS.B.color, BorderSizePixel = 0, ZIndex = 11 }, momWrap)

-- ---------- Battle Lab panel ----------

local labPanel = panel({ Size = UDim2.new(0, 340, 0, 340), Position = UDim2.new(0.5, -170, 0.5, -150), BackgroundColor3 = THEME.panel, BackgroundTransparency = 0.02, Visible = false, ZIndex = 15 }, gui)
label({ Size = UDim2.new(1, 0, 0, 36), Text = "BATTLE LAB", TextColor3 = THEME.gold, Font = Enum.Font.GothamBlack, TextSize = 18, ZIndex = 16 }, labPanel)

local btnLabBase = button("1. SAVE CURRENT AS BASELINE", THEME.panel2, { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 40), ZIndex = 16 }, labPanel)
local btnLabRun = button("2. RUN BASELINE x10", THEME.panel2, { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 76), ZIndex = 16 }, labPanel)
local btnLabSyn = button("3. SYNERGY SCAN (+200 of each unit)", THEME.panel2, { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 112), ZIndex = 16 }, labPanel)
local btnLabForm = button("4. FORMATION VARIANTS", THEME.panel2, { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 148), ZIndex = 16 }, labPanel)
local btnLabHist = button("5. EXPERIMENT HISTORY", THEME.panel2, { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 184), ZIndex = 16 }, labPanel)
local btnLabMatrix = button("6. MATCHUP MATRIX (1v1 tournament)", THEME.panel2, { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 220), ZIndex = 16 }, labPanel)
local labStatus = label({ Size = UDim2.new(1, -20, 0, 70), Position = UDim2.new(0, 10, 0, 256), Text = "Save a baseline, then run experiments. Results are statistics over seeded runs - a few runs prove nothing absolute.", TextColor3 = THEME.dim, TextSize = 10, TextWrapped = true, ZIndex = 16 }, labPanel)
local btnLabClose = button("CLOSE", Color3.fromRGB(90, 70, 70), { Size = UDim2.new(0, 80, 0, 26), Position = UDim2.new(1, -90, 0, 4), ZIndex = 16 }, labPanel)

btnLabClose.MouseButton1Click:Connect(function() labPanel.Visible = false end)
btnLabBase.MouseButton1Click:Connect(function() act("labBaseline", {}) end)
btnLabRun.MouseButton1Click:Connect(function() act("labRun", { runs = 10 }) end)
btnLabSyn.MouseButton1Click:Connect(function() act("labSynergy", {}) end)
btnLabForm.MouseButton1Click:Connect(function() act("labFormations", {}) end)
btnLabHist.MouseButton1Click:Connect(function() act("labHistory", { op = "list" }) end)
btnLabMatrix.MouseButton1Click:Connect(function() act("labMatrix", { runs = 4 }) end)

btnLab.MouseButton1Click:Connect(function()
	labPanel.Visible = not labPanel.Visible
end)

evLab.OnClientEvent:Connect(function(payload)
	if payload.stage == "progress" then
		labPanel.Visible = true
		labStatus.Text = string.format("%s - running %d/%d simulations...", payload.label, payload.done, payload.total)
	elseif payload.stage == "done" then
		labStatus.Text = payload.label .. " - done. Results:"
		for _, agg in ipairs(payload.aggregated) do
			labStatus.Text = labStatus.Text .. string.format("\n%s: A wins %d%% (draws %d), avg %ds, surv %.1f/%.1f, heal %d/%d, dev %d/%d",
				agg.name, agg.winRate, agg.draws, agg.avgDuration, agg.avgSurvA, agg.avgSurvB, agg.avgHealA, agg.avgHealB, agg.avgDevA or 0, agg.avgDevB or 0)
			if #labStatus.Text > 900 then
				break
			end
		end
	elseif payload.stage == "matrixProgress" then
		labPanel.Visible = true
		if payload.total and payload.total > 0 then
			labStatus.Text = string.format("Matchup Matrix - duel %d/%d (%d runs each)...", payload.done, payload.total, payload.runs)
		else
			labStatus.Text = "Matchup Matrix - starting 1v1 round-robin..."
		end
	elseif payload.stage == "matrixDone" then
		labPanel.Visible = true
		labStatus.Text = string.format("MATCHUP MATRIX done (%d runs per duel). Top 1v1:", payload.runs)
		local shown = 0
		for _, sc in ipairs(payload.scores) do
			shown = shown + 1
			labStatus.Text = labStatus.Text .. string.format("\n%d. %s - %d%% avg win rate", shown, sc.name, sc.score)
			if shown >= 5 or #labStatus.Text > 700 then
				break
			end
		end
		labStatus.Text = labStatus.Text .. "\n1v1 strength is not army value - supports score low here."
	elseif payload.stage == "history" then
		labStatus.Text = "Saved experiments: "
		for _, entry in ipairs(payload.history) do
			labStatus.Text = labStatus.Text .. "\n" .. os.date("%m/%d %H:%M", entry.at) .. " - " .. entry.name .. " (" .. entry.kind .. ")"
			if #labStatus.Text > 800 then
				break
			end
		end
	end
end)

-- ---------- results panel + victory banner ----------

local banner = label({
	Size = UDim2.new(1, 0, 0, 70), Position = UDim2.new(0, 0, 0.32, 0), Text = "",
	TextColor3 = THEME.gold, Font = Enum.Font.GothamBlack, TextSize = 46, TextStrokeTransparency = 0.3,
	BackgroundTransparency = 1, Visible = false, ZIndex = 30,
}, gui)

local resultsPanel = panel({ Size = UDim2.new(0, 440, 0, 320), Position = UDim2.new(0.5, -220, 0.5, -160), BackgroundColor3 = THEME.panel, BackgroundTransparency = 0.01, Visible = false, ZIndex = 25 }, gui)
local resultsTitle = label({ Size = UDim2.new(1, 0, 0, 40), Text = "", TextColor3 = THEME.gold, Font = Enum.Font.GothamBlack, TextSize = 22, ZIndex = 26 }, resultsPanel)
local timelineFrame = mk("Frame", { Size = UDim2.new(1, -40, 0, 70), Position = UDim2.new(0, 20, 0, 44), BackgroundColor3 = Color3.fromRGB(12, 14, 20), ZIndex = 26 }, resultsPanel)
local resultsBody = label({ Size = UDim2.new(1, -30, 1, -230), Position = UDim2.new(0, 15, 0, 120), Text = "", TextColor3 = Color3.fromRGB(210, 215, 230), TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 26 }, resultsPanel)
local btnAgain = button("NEW BATTLE", Color3.fromRGB(50, 160, 80), { Size = UDim2.new(0, 150, 0, 34), Position = UDim2.new(0.5, -75, 1, -44), ZIndex = 26 }, resultsPanel)
btnAgain.MouseButton1Click:Connect(function()
	resultsPanel.Visible = false
	banner.Visible = false
	act("clear", {})
end)

local function showTimeline(timeline)
	for _, child in ipairs(timelineFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local n = #timeline
	if n == 0 then
		return
	end
	local maxAlive = 1
	for _, point in ipairs(timeline) do
		maxAlive = math.max(maxAlive, point.a, point.b)
	end
	for i, point in ipairs(timeline) do
		local w = 1 / n
		mk("Frame", { Size = UDim2.new(w, 0, point.a / maxAlive, 0), Position = UDim2.new((i - 1) / n, 0, 1 - point.a / maxAlive, 0), BackgroundColor3 = UCConfig.TEAMS.A.color, BorderSizePixel = 0, ZIndex = 27 }, timelineFrame)
		mk("Frame", { Size = UDim2.new(w, 0, point.b / maxAlive, 0), Position = UDim2.new((i - 1) / n, 0, 1 - point.b / maxAlive, 0), BackgroundColor3 = UCConfig.TEAMS.B.color, BorderSizePixel = 0, ZIndex = 27 }, timelineFrame)
	end
end

evResults.OnClientEvent:Connect(function(payload)
	local result = payload.result
	resultsPanel.Visible = true
	showTimeline(payload.timeline or {})
	local function line(teamId)
		local t = result[teamId]
		return string.format("%s - %d deployed, %d survivors, %d damage, %d healing, %d abilities, %d device dmg",
			UCConfig.TEAMS[teamId].name, t.deployed, t.survivors, t.damage, t.healing, t.abilities, t.deviceDamage or 0)
	end
	if result.winner == "draw" then
		resultsTitle.Text = "DRAW"
		resultsTitle.TextColor3 = Color3.fromRGB(180, 180, 180)
		banner.Text = "DRAW"
		banner.TextColor3 = Color3.fromRGB(180, 180, 180)
	else
		resultsTitle.Text = UCConfig.TEAMS[result.winner].name .. " WINS  (level up: +XP)"
		resultsTitle.TextColor3 = UCConfig.TEAMS[result.winner].color
		banner.Text = UCConfig.TEAMS[result.winner].name .. " WINS!"
		banner.TextColor3 = UCConfig.TEAMS[result.winner].color
	end
	banner.Visible = true
	local insightsText = ""
	for _, insight in ipairs(payload.insights or {}) do
		insightsText = insightsText .. "- " .. insight .. "\n"
	end
	resultsBody.Text = string.format("Reason: %s   Duration: %ds\n\n%s\n\n%s\nINSIGHTS:\n%s",
		result.reason, result.duration, line("A"), line("B"), insightsText)
	task.delay(2.5, function()
		banner.Visible = false
	end)
end)

-- ---------- placement input on the 2D canvas ----------

local function fieldPoint()
	local m = UserInputService:GetMouseLocation()
	local fx = (m.X - field.AbsolutePosition.X) / math.max(1, field.AbsoluteSize.X)
	local fy = (m.Y - field.AbsolutePosition.Y) / math.max(1, field.AbsoluteSize.Y)
	return fx, fy
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if state.phase ~= "setup" or not state.selectedUnit then
			return
		end
		local fx, fy = fieldPoint()
		if fx < X0 or fx > X1 or fy < BAND_TOP or fy > BAND_BOTTOM then
			return
		end
		local x, z = scaleToSim(fx, fy)
		if state.selectedUnit then
			playSfx("place")
		end
		act("place", { team = state.activeTeam, type = state.selectedUnit, upgrade = state.selectedUpgrade[state.selectedUnit], x = x, z = z })
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		if state.phase ~= "setup" then
			return
		end
		local fx, fy = fieldPoint()
		local x, z = scaleToSim(fx, fy)
		act("remove", { team = state.activeTeam, x = x, z = z })
	end
end)

-- ---------- staged markers (setup phase) ----------

local stagedMarkers = {}

local function clearStagedMarkers()
	for _, m in ipairs(stagedMarkers) do
		m:Destroy()
	end
	stagedMarkers = {}
end

local function showStaged(staged)
	clearStagedMarkers()
	for team, list in pairs(staged or {}) do
		for _, e in ipairs(list) do
			local def = UCConfig.get(e.type)
			if def then
				local sz = unitSize(def.radius or 1)
				local fx, fz = simToScale(e.x, e.z)
				local dot = mk("Frame", {
					Size = UDim2.fromScale(sz, sz), Position = UDim2.fromScale(fx, fz), AnchorPoint = Vector2.new(0.5, 0.5),
					BackgroundColor3 = def.color, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 3,
				}, layerStaged)
				corner(dot, 999)
				mk("UIStroke", { Color = UCConfig.TEAMS[team].color, Thickness = 2, Transparency = 0.2 }, dot)
				table.insert(stagedMarkers, dot)
			end
		end
	end
end

-- ---------- state sync ----------

evState.OnClientEvent:Connect(function(s)
	state.phase = s.phase
	state.mode = s.mode
	state.mission = s.mission
	state.wave = s.wave or 0
	state.arena = s.arena
	state.factions = s.factions
	state.spent = s.spent
	state.budgets = s.budgets
	state.deployed = s.deployed
	state.paused = s.paused
	state.clock = s.clock
	state.seed = s.seed
	if s.staged then
		state.stagedCache = { arena = s.arena, seed = s.seed or 1, budgets = s.budgets, teams = s.staged }
	end
	btnPause.Text = s.paused and "RESUME" or "PAUSE"
	arenaBtn.Text = "ARENA: " .. s.arenaName
	ground.BackgroundColor3 = (UCConfig.ARENAS[s.arena] or UCConfig.ARENAS.grassland).ground
	arenaNameTag.Text = string.upper(s.arenaName or "")

	local factionText = {}
	for team in pairs({ A = true, B = true }) do
		local f = s.factions and s.factions[team]
		table.insert(factionText, UCConfig.TEAMS[team].name .. ": " .. (f and UCConfig.FACTIONS[f].name or "no faction (right-click team button)"))
	end
	factionLabel.Text = table.concat(factionText, "   |   ")

	if s.momentum then
		local total = math.max(1, s.momentum.A + s.momentum.B)
		momA.Size = UDim2.new(s.momentum.A / total, 0, 1, 0)
		momB.Size = UDim2.new(s.momentum.B / total, 0, 1, 0)
		momB.Position = UDim2.new(s.momentum.A / total, 0, 0, 0)
	end

	if s.phase == "setup" then
		showStaged(s.staged)
		hintBar.Visible = true
	else
		clearStagedMarkers()
		hintBar.Visible = false
	end

	if s.mode == "survival" and s.wave > 0 then
		statusLabel.Text = string.format("SURVIVAL WAVE %d - %ds", s.wave, s.clock)
	elseif s.phase == "setup" then
		statusLabel.Text = string.format("SETUP (%s) - Azure %d/%d (%d) | Crimson %d/%d (%d) | seed %d",
			s.mode, s.spent.A, s.budgets.A, s.deployed.A, s.spent.B, s.budgets.B, s.deployed.B, s.seed or 0)
	elseif s.phase == "battle" then
		statusLabel.Text = string.format("BATTLE - %ds / %ds | %dx%s", s.clock, s.timeLimit, s.speed, s.paused and " PAUSED" or "")
		resultsPanel.Visible = false
	elseif s.phase == "results" then
		statusLabel.Text = "BATTLE OVER"
	end
end)

evState:FireServer()
print("[UNIT CLASH] client ready - 2D renderer, " .. #UCConfig.ORDER .. " units, Battle Lab, 4 modes")
