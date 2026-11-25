-- Path: StarterPlayer/StarterPlayerScripts/HUDController (LocalScript)
-- Main HUD + Wayfinder Atlas (discovery log). Everything is generated in code
-- so the file can be pasted as a single LocalScript. Renders only snapshots
-- received from the server; no client-side attempt is made to authorize state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("BeastboundShared")
local Net = require(Shared.Net)
local ResourceConfig = require(Shared.ResourceConfig)
local BiomeConfig = require(Shared.BiomeConfig)
local AudioConfig = require(Shared.AudioConfig)

local player = Players.LocalPlayer

local GLOW = Color3.fromRGB(120, 255, 190)
local PAPER = Color3.fromRGB(230, 245, 235)
local DARK = Color3.fromRGB(18, 26, 24)

local gui = Instance.new("ScreenGui")
gui.Name = "BeastboundHUD"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local function clickSound()
	local sound = Instance.new("Sound")
	sound.SoundId = AudioConfig.UiClick.SoundId
	sound.Volume = AudioConfig.UiClick.Volume
	sound.PlaybackSpeed = AudioConfig.UiClick.Pitch
	sound.Parent = gui
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	sound:Play()
end

local function card(parent, size, position)
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = DARK
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = GLOW
	stroke.Transparency = 0.75
	stroke.Parent = frame
	return frame
end

local function label(parent, size, position, text, size_font, align)
	local textLabel = Instance.new("TextLabel")
	textLabel.Size = size
	textLabel.Position = position
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.GothamBold
	textLabel.TextSize = size_font or 16
	textLabel.TextColor3 = PAPER
	textLabel.TextXAlignment = align or Enum.TextXAlignment.Left
	textLabel.Text = text or ""
	textLabel.Parent = parent
	return textLabel
end

local function bar(parent, position, size)
	local background = Instance.new("Frame")
	background.Size = size or UDim2.new(1, -16, 0, 8)
	background.Position = position
	background.BackgroundColor3 = Color3.fromRGB(10, 16, 14)
	background.BorderSizePixel = 0
	background.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = background
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = GLOW
	fill.BorderSizePixel = 0
	fill.Parent = background
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill
	return fill
end

--=====================================================================
-- Panels
--=====================================================================

-- level pill (top-left)
local levelCard = card(gui, UDim2.fromOffset(200, 58), UDim2.fromOffset(14, 14))
local levelText = label(levelCard, UDim2.new(1, -16, 0, 22), UDim.new(0, 8, 0, 6), "Wayfarer — Level 1", 17)
local xpFill = bar(levelCard, UDim2.new(0, 8, 0, 36), UDim2.new(1, -16, 0, 8))

-- objective + journey (top-center)
local objectiveCard = card(gui, UDim2.fromOffset(460, 92), UDim2.new(0.5, -230, 0, 14))
local objectiveText = label(objectiveCard, UDim2.new(1, -16, 0, 22), UDim.new(0, 8, 0, 6), "Waiting for the server…", 18)
local objectiveHint = label(objectiveCard, UDim2.new(1, -16, 0, 18), UDim.new(0, 8, 0, 28), "", 12, Enum.TextXAlignment.Center)
objectiveHint.TextColor3 = Color3.fromRGB(170, 195, 180)
local objectiveFill = bar(objectiveCard, UDim2.new(0, 8, 0, 52), UDim2.new(1, -16, 0, 8))

local journeyCard = card(gui, UDim2.fromOffset(460, 54), UDim2.new(0.5, -230, 0, 114))
journeyCard.BackgroundColor3 = Color3.fromRGB(26, 34, 30)
local journeyText = label(journeyCard, UDim2.new(1, -16, 0, 18), UDim.new(0, 8, 0, 5), "Migration: Mosslight Meadow", 15)
local journeyFill = bar(journeyCard, UDim2.new(0, 8, 0, 32), UDim2.new(1, -16, 0, 7))
journeyFill.BackgroundColor3 = Color3.fromRGB(255, 220, 120)

-- resource chips (bottom-left)
local chips = {}
local chipRow = card(gui, UDim2.fromOffset(320, 52), UDim2.new(0, 14, 1, -66))
for index, resourceId in ipairs(ResourceConfig.Order) do
	local def = ResourceConfig.ById[resourceId]
	local chip = Instance.new("Frame")
	chip.Size = UDim2.new(0, 96, 1, -12)
	chip.Position = UDim2.new(0, 4 + (index - 1) * 100, 0, 6)
	chip.BackgroundColor3 = Color3.fromRGB(10, 16, 14)
	chip.BackgroundTransparency = 0.4
	chip.BorderSizePixel = 0
	chip.Parent = chipRow
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = chip
	local dot = Instance.new("Frame")
	dot.Size = UDim2.fromOffset(10, 10)
	dot.Position = UDim2.new(0, 8, 0, 8)
	dot.BackgroundColor3 = def.IconColor
	dot.BorderSizePixel = 0
	dot.Parent = chip
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot
	local countLabel = label(chip, UDim2.new(1, -10, 0, 18), UDim.new(0, 24, 0, 4), "0", 14)
	local nameLabel = label(chip, UDim2.new(1, -10, 0, 14), UDim.new(0, 8, 1, -18), def.DisplayName, 10, Enum.TextXAlignment.Center)
	nameLabel.TextColor3 = Color3.fromRGB(150, 175, 160)
	chips[resourceId] = countLabel
end

-- creature status + community project (top-right)
local bondCard = card(gui, UDim2.fromOffset(260, 58), UDim2.new(1, -274, 0, 14))
local bondText = label(bondCard, UDim2.new(1, -16, 0, 18), UDim.new(0, 8, 0, 6), "Aruun: Distant (Bond 1)", 14)
local bondFill = bar(bondCard, UDim2.new(0, 8, 0, 32), UDim2.new(1, -16, 0, 8))

local projectCard = card(gui, UDim2.fromOffset(260, 58), UDim2.new(1, -274, 0, 80))
local projectText = label(projectCard, UDim2.new(1, -16, 0, 18), UDim.new(0, 8, 0, 6), "Heartroot: 0 / 0", 14)
local projectFill = bar(projectCard, UDim2.new(0, 8, 0, 32), UDim2.new(1, -16, 0, 8))
projectFill.BackgroundColor3 = Color3.fromRGB(255, 220, 120)

-- BOTTON: Atlas toggle
local atlasToggle = Instance.new("TextButton")
atlasToggle.Size = UDim2.fromOffset(150, 52)
atlasToggle.Position = UDim2.new(1, -340, 1, -76)
atlasToggle.Font = Enum.Font.GothamBold
atlasToggle.TextSize = 22
atlasToggle.Text = "ATLAS"
atlasToggle.TextColor3 = Color3.fromRGB(20, 30, 25)
atlasToggle.BackgroundColor3 = Color3.fromRGB(120, 255, 190)
atlasToggle.Parent = gui
Instance.new("UICorner").Parent = atlasToggle

-- Atlas panel
local atlasPanel = card(gui, UDim2.fromOffset(420, 470), UDim2.new(0.5, -210, 0.5, -235), 16)
atlasPanel.Visible = false
local atlasScroll = Instance.new("ScrollingFrame")
atlasScroll.Size = UDim2.new(1, -16, 1, -76)
atlasScroll.Position = UDim.new(0, 8, 0, 60)
atlasScroll.BackgroundTransparency = 1
atlasScroll.BorderSizePixel = 0
atlasScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
atlasScroll.CanvasSize = UDim2.fromOffset(0, 0)
atlasScroll.ScrollBarThickness = 4
atlasScroll.Parent = atlasPanel
local atlasLayout = Instance.new("UIListLayout")
atlasLayout.Padding = UDim.new(0, 8)
atlasLayout.Parent = atlasScroll
label(atlasPanel, UDim2.new(1, -16, 0, 24), UDim.new(0, 8, 0, 10), "The Wayfinder Atlas", 20)
local atlasSummary = label(atlasPanel, UDim2.new(1, -16, 0, 18), UDim.new(0, 8, 0, 36), "0 / 0 landmarks found", 13)
atlasSummary.TextColor3 = Color3.fromRGB(170, 195, 180)

local atlasRows = {}
for _, landmark in ipairs(BiomeConfig.Landmarks) do
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 52)
	row.BackgroundColor3 = Color3.fromRGB(10, 16, 14)
	row.BorderSizePixel = 0
	row.Parent = atlasScroll
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = row
	local nameText = label(row, UDim2.new(1, -48, 0, 20), UDim.new(0, 10, 0, 6), "???", 15)
	local loreText = label(row, UDim2.new(1, -48, 0, 24), UDim.new(0, 10, 0, 26), "Undiscovered — explore the edges of Aruun.", 12)
	loreText.TextColor3 = Color3.fromRGB(150, 175, 160)
	loreText.TextWrapped = true
	loreText.Font = Enum.Font.Gotham
	local mark = label(row, UDim2.new(0, 28, 1, 0), UDim.new(1, -34, 0, 0), "", 22, Enum.TextXAlignment.Right)
	atlasRows[landmark.Id] = {
		name = nameText,
		lore = loreText,
		mark = mark,
		config = landmark,
	}
end

-- toast stack (right side)
local toastFrame = Instance.new("Frame")
toastFrame.Size = UDim2.fromOffset(320, 400)
toastFrame.Position = UDim2.new(1, -344, 0.5, -80)
toastFrame.BackgroundTransparency = 1
toastFrame.Parent = gui
local toastLayout = Instance.new("UIListLayout")
toastLayout.Padding = UDim.new(0, 8)
toastLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
toastLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
toastLayout.Parent = toastFrame

local TOAST_COLORS = {
	info = Color3.fromRGB(120, 255, 190),
	quest = Color3.fromRGB(255, 220, 120),
	reward = Color3.fromRGB(255, 220, 120),
	discover = Color3.fromRGB(120, 200, 255),
	build = Color3.fromRGB(120, 255, 190),
	warn = Color3.fromRGB(255, 150, 130),
	project = Color3.fromRGB(255, 220, 120),
	journey = Color3.fromRGB(120, 200, 255),
}

local function toast(data)
	if type(data) ~= "table" then
		return
	end
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 0, 64)
	card.BackgroundColor3 = DARK
	card.BackgroundTransparency = 0.1
	card.BorderSizePixel = 0
	card.Parent = toastFrame
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = TOAST_COLORS[data.kind] or GLOW
	stroke.Transparency = 0.4
	stroke.Parent = card
	label(card, UDim2.new(1, -16, 0, 20), UDim.new(0, 8, 0, 6), tostring(data.title or ""), 15)
	local message = label(card, UDim2.new(1, -16, 0, 30), UDim.new(0, 8, 0, 28), tostring(data.message or ""), 12)
	message.Font = Enum.Font.Gotham
	message.TextColor3 = Color3.fromRGB(190, 210, 195)
	message.TextWrapped = true

	task.delay(4.5, function()
		card:Destroy()
	end)
end

--=====================================================================
-- Update logic (Renders only what the server authoritatively sends)
--=====================================================================

local function ratioOf(progress, target)
	local safeTarget = tonumber(target) or 0
	if safeTarget <= 0 then
		return 1
	end
	return math.clamp((tonumber(progress) or 0) / safeTarget, 0, 1)
end

Net.get("PlayerSync").OnClientEvent:Connect(function(snapshot)
	if type(snapshot) ~= "table" then
		return
	end

	levelText.Text = "Wayfarer — Level " .. tostring(snapshot.level)
	local xpRange = snapshot.xpCeiling and (snapshot.xpCeiling - snapshot.xpFloor) or nil
	xpFill.Size = UDim2.fromScale(ratioOf(snapshot.xp - snapshot.xpFloor, xpRange), 1)

	for resourceId, countLabel in pairs(chips) do
		countLabel.Text = tostring((snapshot.inventory or {})[resourceId] or 0)
	end

	local quest = snapshot.quest or {}
	objectiveText.Text = quest.title or ""
	objectiveHint.Text = quest.hint or ""
	objectiveFill.Size = UDim2.fromScale(ratioOf(quest.progress, quest.target), 1)

	if snapshot.provisional then
		objectiveHint.Text = "Data save unavailable this session (Studio API access is off)."
	end

	for landmarkId, row in pairs(atlasRows) do
		if (snapshot.discoveredLandmarks or {})[landmarkId] then
			row.name.Text = row.config.Name
			row.lore.Text = row.config.Lore
			row.mark.Text = "✓"
		else
			row.name.Text = "???"
			row.lore.Text = "Undiscovered — explore the edges of Aruun."
			row.mark.Text = ""
		end
	end

	local found = 0
	for _, landmarkId in pairs(snapshot.discoveredLandmarks or {}) do
		found += 1
	end
	atlasSummary.Text = found .. " / " .. #BiomeConfig.Landmarks .. " landmarks found"
end)

Net.get("WorldSync").OnClientEvent:Connect(function(snapshot)
	if type(snapshot) ~= "table" then
		return
	end

	local journey = snapshot.journey or {}
	local journeyRatio = journey.finalStage and 1 or ratioOf(journey.momentum, journey.target)
	journeyText.Text = "Migration · " .. tostring(journey.name) .. " — Stage " .. tostring(journey.stage)
	journeyFill.Size = UDim2.fromScale(journeyRatio, 1)

	local bond = snapshot.bond or {}
	bondText.Text = "Aruun: " .. tostring(bond.name) .. " (Bond " .. tostring(bond.level) .. ")"
	bondFill.Size = UDim2.fromScale(ratioOf(bond.points, bond.level * 30), 1)

	local project = snapshot.project or {}
	projectText.Text = tostring(project.name) .. ": " .. tostring(project.progress) .. " / " .. tostring(project.target)
	if project.completed then
		projectText.Text = tostring(project.name) .. " — restored!"
	end
	projectFill.Size = UDim2.fromScale(ratioOf(project.progress, project.target), 1)

	-- bind the in-world signpost to live journey data
	local creature = workspace:FindFirstChild("Aruun")
	if creature then
		local signpost = creature:FindFirstChild("MigrationSignpost")
		local board = signpost and signpost:FindFirstChild("Board")
		local signGui = board and board:FindFirstChild("SignGui")
		local signText = signGui and signGui:FindFirstChild("SignText")
		if signText then
			signText.Text = tostring(journey.name)
		end
	end
end)

Net.get("Toast").OnClientEvent:Connect(toast)

atlasToggle.Activated:Connect(function()
	clickSound()
	atlasPanel.Visible = not atlasPanel.Visible
end)
