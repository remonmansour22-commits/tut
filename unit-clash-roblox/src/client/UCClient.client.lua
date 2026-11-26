-- UNIT CLASH - client: full UI. Palette + upgrades, factions, arenas, modes,
-- saves, share codes, Battle Lab panel, momentum bar, timeline chart,
-- battle controls, camera follow, results + insights.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local UCConfig = require(ReplicatedStorage:WaitForChild("UCShared"):WaitForChild("UCConfig"))
local UCShareCodec = require(ReplicatedStorage:WaitForChild("UCShared"):WaitForChild("UCShareCodec"))

local remotes = ReplicatedStorage:WaitForChild("UCRemotes")
local evAction = remotes:WaitForChild("UCAction")
local evState = remotes:WaitForChild("UCState")
local evResults = remotes:WaitForChild("UCResults")
local evLab = remotes:WaitForChild("UCLab")
local evToast = remotes:WaitForChild("UCToast")

local function act(cmd, args)
	evAction:FireServer(cmd, args or {})
end

local state = {
	phase = "setup",
	mode = "sandbox",
	mission = nil,
	wave = 0,
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
	level = 1,
	xp = 0,
	followModel = nil,
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
	b.BackgroundColor3 = color or Color3.fromRGB(60, 70, 95)
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	corner(b, 6)
	return b
end

local gui = mk("ScreenGui", { Name = "UCUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))

-- ---------- toast ----------

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

local topBar = panel({ Size = UDim2.new(1, -20, 0, 44), Position = UDim2.new(0, 10, 0, 6), BackgroundColor3 = Color3.fromRGB(18, 20, 28), BackgroundTransparency = 0.1 }, gui)
label({ Size = UDim2.new(0, 140, 1, 0), Position = UDim2.new(0, 10, 0, 0), Text = "UNIT CLASH", TextColor3 = Color3.fromRGB(255, 210, 90), Font = Enum.Font.GothamBlack, TextSize = 20, TextXAlignment = Enum.TextXAlignment.Left }, topBar)
local statusLabel = label({ Size = UDim2.new(0, 480, 1, 0), Position = UDim2.new(0, 150, 0, 0), Text = "", TextColor3 = Color3.fromRGB(220, 220, 230), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left }, topBar)

local function barButton(text, color, order)
	return button(text, color, { Size = UDim2.new(0, 88, 0, 32), Position = UDim2.new(1, -(order * 96) - 10, 0.5, -16) }, topBar)
end

local btnStart = barButton("START", Color3.fromRGB(50, 160, 80), 1)
local btnPause = barButton("PAUSE", Color3.fromRGB(70, 80, 110), 2)
local btnSpeed = barButton("1x", Color3.fromRGB(70, 80, 110), 3)
local btnClear = barButton("CLEAR", Color3.fromRGB(90, 70, 70), 4)
local btnModes = barButton("MODES", Color3.fromRGB(80, 70, 110), 5)

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

-- ---------- modes panel ----------

local modesPanel = panel({ Size = UDim2.new(0, 300, 0, 330), Position = UDim2.new(0.5, -150, 0.5, -165), BackgroundColor3 = Color3.fromRGB(18, 20, 28), BackgroundTransparency = 0.05, Visible = false, ZIndex = 15 }, gui)
label({ Size = UDim2.new(1, 0, 0, 40), Text = "GAME MODES", TextColor3 = Color3.fromRGB(255, 210, 90), Font = Enum.Font.GothamBlack, TextSize = 18, ZIndex = 16 }, modesPanel)

local modeList = mk("ScrollingFrame", { Size = UDim2.new(1, -20, 1, -100), Position = UDim2.new(0, 10, 0, 44), BackgroundTransparency = 1, ScrollBarThickness = 4, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, modesPanel)
mk("UIListLayout", { Padding = UDim.new(0, 6) }, modeList)

local function modeRow(name, desc, onClick)
	local row = button(name, Color3.fromRGB(40, 46, 66), { Size = UDim2.new(1, -8, 0, 52), AutoButtonColor = true }, modeList)
	label({ Size = UDim2.new(1, -16, 0, 18), Position = UDim2.new(0, 8, 0, 6), Text = name, TextColor3 = Color3.fromRGB(240, 240, 250), TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 17 }, row)
	label({ Size = UDim2.new(1, -16, 0, 26), Position = UDim2.new(0, 8, 0, 24), Text = desc, TextColor3 = Color3.fromRGB(150, 155, 170), TextSize = 10, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 17 }, row)
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

local teamToggle = panel({ Size = UDim2.new(0, 300, 0, 72), Position = UDim2.new(0.5, -150, 0, 56), BackgroundColor3 = Color3.fromRGB(18, 20, 28), BackgroundTransparency = 0.15 }, gui)
local function teamButton(team, offset)
	local t = UCConfig.TEAMS[team]
	local b = button("PLACE: " .. t.name, t.color, { Size = UDim2.new(0.42, -6, 0, 30), Position = UDim2.new(offset, 4, 0, 4) }, teamToggle)
	b.MouseButton1Click:Connect(function()
		state.activeTeam = team
		refreshTeamButtons()
	end)
	return b
end
local btnTeamA = teamButton("A", 0)
local btnTeamB = teamButton("B", 0.42)
local factionLabel = label({ Size = UDim2.new(1, -10, 0, 26), Position = UDim2.new(0, 6, 0, 40), Text = "", TextColor3 = Color3.fromRGB(170, 175, 190), TextSize = 11 }, teamToggle)

local function refreshTeamButtons()
	btnTeamA.BackgroundColor3 = state.activeTeam == "A" and UCConfig.TEAMS.A.color or Color3.fromRGB(45, 50, 70)
	btnTeamB.BackgroundColor3 = state.activeTeam == "B" and UCConfig.TEAMS.B.color or Color3.fromRGB(45, 50, 70)
end

local function cycleFaction(team)
	local ids, n = {}, 0
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

local palette = mk("ScrollingFrame", { Size = UDim2.new(0, 230, 1, -230), Position = UDim2.new(0, 10, 0, 140), BackgroundColor3 = Color3.fromRGB(18, 20, 28), BackgroundTransparency = 0.1, ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new() }, gui)
corner(palette)
mk("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, palette)

local cardByUnit = {}
local upgradePanel = panel({ Size = UDim2.new(0, 230, 0, 84), Position = UDim2.new(0, 10, 1, -84), BackgroundColor3 = Color3.fromRGB(18, 20, 28), BackgroundTransparency = 0.1, Visible = false }, gui)
local upgradeTitle = label({ Size = UDim2.new(1, -10, 0, 18), Position = UDim2.new(0, 6, 0, 4), Text = "", TextColor3 = Color3.fromRGB(255, 210, 90), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left }, upgradePanel)
local up1, up2

for order, unitId in ipairs(UCConfig.ORDER) do
	local def = UCConfig.get(unitId)
	local card = button("", Color3.fromRGB(30, 34, 48), { Size = UDim2.new(1, -12, 0, 56), LayoutOrder = order, AutoButtonColor = true }, palette)
	corner(card, 6)
	mk("Frame", { Size = UDim2.new(0, 8, 1, -10), Position = UDim2.new(0, 5, 0, 5), BackgroundColor3 = def.color }, card)
	label({ Size = UDim2.new(1, -30, 0, 18), Position = UDim2.new(0, 20, 0, 6), Text = def.name .. "  (" .. def.cost .. ")", TextColor3 = Color3.fromRGB(240, 240, 250), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left }, card)
	local descText = def.desc .. "  -  Lv" .. def.unlockLevel .. "+"
	label({ Size = UDim2.new(1, -30, 0, 26), Position = UDim2.new(0, 20, 0, 25), Text = descText, TextColor3 = Color3.fromRGB(150, 155, 170), TextSize = 9, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top }, card)
	cardByUnit[unitId] = card
	card.MouseButton1Click:Connect(function()
		state.selectedUnit = unitId
		for id, c in pairs(cardByUnit) do
			c.BackgroundColor3 = id == unitId and Color3.fromRGB(70, 90, 60) or Color3.fromRGB(30, 34, 48)
		end
		local ups = UCConfig.upgradesFor(unitId)
		upgradeTitle.Text = "UPGRADE - " .. def.name
		if up1 then
			up1:Destroy()
		end
		if up2 then
			up2:Destroy()
		end
		local function upgradeButton(index, up)
			local b = button(ups[index] and (ups[index].name .. ": " .. ups[index].desc) or "No upgrade", Color3.fromRGB(45, 52, 76), { Size = UDim2.new(0.5, -8, 0, 44), Position = UDim2.new(index == 1 and 0 or 0.5, 4, 0, 30) }, upgradePanel)
			b.MouseButton1Click:Connect(function()
				state.selectedUpgrade[unitId] = ups[index] and ups[index].id or nil
				b.BackgroundColor3 = Color3.fromRGB(70, 90, 60)
				local other = index == 1 and up2 or up1
				if other then
					other.BackgroundColor3 = Color3.fromRGB(45, 52, 76)
				end
			end)
			return b
		end
		up1 = upgradeButton(1, ups[1])
		up2 = upgradeButton(2, ups[2])
		upgradePanel.Visible = true
	end)
end

-- ---------- arena + tools row ----------

local toolsRow = panel({ Size = UDim2.new(0, 250, 0, 120), Position = UDim2.new(1, -260, 1, -130), BackgroundColor3 = Color3.fromRGB(18, 20, 28), BackgroundTransparency = 0.1 }, gui)
local arenaBtn = button("ARENA: Grassland", Color3.fromRGB(45, 52, 76), { Size = UDim2.new(1, -16, 0, 28), Position = UDim2.new(0, 8, 0, 8) }, toolsRow)
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

local btnLine = button("LINE", Color3.fromRGB(45, 52, 76), { Size = UDim2.new(0.31, -6, 0, 26), Position = UDim2.new(0, 8, 0, 42) }, toolsRow)
local btnWall = button("WALL", Color3.fromRGB(45, 52, 76), { Size = UDim2.new(0.31, -6, 0, 26), Position = UDim2.new(0.345, 0, 0, 42) }, toolsRow)
local btnSpread = button("SPREAD", Color3.fromRGB(45, 52, 76), { Size = UDim2.new(0.31, -6, 0, 26), Position = UDim2.new(0.69, 0, 0, 42) }, toolsRow)
local btnRandom = button("RANDOM ARMY", Color3.fromRGB(70, 60, 90), { Size = UDim2.new(1, -16, 0, 26), Position = UDim2.new(0, 8, 0, 74) }, toolsRow)
local btnEnemy = button("ENEMY AI", Color3.fromRGB(150, 80, 60), { Size = UDim2.new(1, -16, 0, 26), Position = UDim2.new(0, 8, 0, 104) }, toolsRow)

btnLine.MouseButton1Click:Connect(function() act("formation", { team = state.activeTeam, kind = "line" }) end)
btnWall.MouseButton1Click:Connect(function() act("formation", { team = state.activeTeam, kind = "wall" }) end)
btnSpread.MouseButton1Click:Connect(function() act("formation", { team = state.activeTeam, kind = "spread" }) end)
btnRandom.MouseButton1Click:Connect(function() act("randomArmyA", {}) end)
btnEnemy.MouseButton1Click:Connect(function() act("fillEnemy", {}) end)

-- ---------- saves + share ----------

local savesRow = panel({ Size = UDim2.new(0, 250, 0, 106), Position = UDim2.new(1, -260, 1, -242), BackgroundColor3 = Color3.fromRGB(18, 20, 28), BackgroundTransparency = 0.1 }, gui)
local saveBox = mk("TextBox", { Size = UDim2.new(0.55, -12, 0, 26), Position = UDim2.new(0, 8, 0, 8), BackgroundColor3 = Color3.fromRGB(30, 34, 48), TextColor3 = Color3.fromRGB(240, 240, 250), Text = "", PlaceholderText = "setup name", TextSize = 12, Font = Enum.Font.Gotham, ClearTextOnFocus = false }, savesRow)
corner(saveBox, 6)
local btnSave = button("SAVE", Color3.fromRGB(45, 52, 76), { Size = UDim2.new(0.45, -12, 0, 26), Position = UDim2.new(0.55, 0, 0, 8) }, savesRow)
local btnShare = button("SHARE CODE", Color3.fromRGB(60, 70, 100), { Size = UDim2.new(0.55, -12, 0, 26), Position = UDim2.new(0, 8, 0, 40) }, savesRow)
local btnImport = button("IMPORT", Color3.fromRGB(60, 70, 100), { Size = UDim2.new(0.45, -12, 0, 26), Position = UDim2.new(0.55, 0, 0, 40) }, savesRow)
local shareBox = mk("TextBox", { Size = UDim2.new(1, -16, 0, 44), Position = UDim2.new(0, 8, 0, 70), BackgroundColor3 = Color3.fromRGB(30, 34, 48), TextColor3 = Color3.fromRGB(240, 240, 250), Text = "", PlaceholderText = "UC1.... paste code here", TextSize = 10, Font = Enum.Font.Code, TextWrapped = true, ClearTextOnFocus = false }, savesRow)
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

local momWrap = mk("Frame", { Size = UDim2.new(0.6, 0, 0, 18), Position = UDim2.new(0.2, 0, 1, -30), BackgroundColor3 = Color3.fromRGB(25, 28, 38), BackgroundTransparency = 0.2 }, gui)
corner(momWrap, 4)
local momA = mk("Frame", { Size = UDim2.new(0.5, 0, 1, 0), BackgroundColor3 = UCConfig.TEAMS.A.color, BorderSizePixel = 0 }, momWrap)
local momB = mk("Frame", { Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.new(0.5, 0, 0, 0), BackgroundColor3 = UCConfig.TEAMS.B.color, BorderSizePixel = 0 }, momWrap)

-- ---------- Battle Lab panel ----------

local labPanel = panel({ Size = UDim2.new(0, 340, 0, 340), Position = UDim2.new(0.5, -170, 0.5, -150), BackgroundColor3 = Color3.fromRGB(18, 20, 28), BackgroundTransparency = 0.05, Visible = false, ZIndex = 15 }, gui)
label({ Size = UDim2.new(1, 0, 0, 36), Text = "BATTLE LAB", TextColor3 = Color3.fromRGB(255, 210, 90), Font = Enum.Font.GothamBlack, TextSize = 18, ZIndex = 16 }, labPanel)

local btnLabBase = button("1. SAVE CURRENT AS BASELINE", Color3.fromRGB(45, 52, 76), { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 40), ZIndex = 16 }, labPanel)
local btnLabRun = button("2. RUN BASELINE x10", Color3.fromRGB(45, 52, 76), { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 76), ZIndex = 16 }, labPanel)
local btnLabSyn = button("3. SYNERGY SCAN (+200 of each unit)", Color3.fromRGB(45, 52, 76), { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 112), ZIndex = 16 }, labPanel)
local btnLabForm = button("4. FORMATION VARIANTS", Color3.fromRGB(45, 52, 76), { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 148), ZIndex = 16 }, labPanel)
local btnLabHist = button("5. EXPERIMENT HISTORY", Color3.fromRGB(45, 52, 76), { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 184), ZIndex = 16 }, labPanel)
local btnLabMatrix = button("6. MATCHUP MATRIX (1v1 tournament)", Color3.fromRGB(45, 52, 76), { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.new(0, 10, 0, 220), ZIndex = 16 }, labPanel)
local labStatus = label({ Size = UDim2.new(1, -20, 0, 70), Position = UDim2.new(0, 10, 0, 256), Text = "Save a baseline, then run experiments. Results are statistics over seeded runs - a few runs prove nothing absolute.", TextColor3 = Color3.fromRGB(150, 155, 170), TextSize = 10, TextWrapped = true, ZIndex = 16 }, labPanel)
local btnLabClose = button("CLOSE", Color3.fromRGB(90, 70, 70), { Size = UDim2.new(0, 80, 0, 26), Position = UDim2.new(1, -90, 0, 4), ZIndex = 16 }, labPanel)

btnLabClose.MouseButton1Click:Connect(function() labPanel.Visible = false end)
btnLabBase.MouseButton1Click:Connect(function() act("labBaseline", {}) end)
btnLabRun.MouseButton1Click:Connect(function() act("labRun", { runs = 10 }) end)
btnLabSyn.MouseButton1Click:Connect(function() act("labSynergy", {}) end)
btnLabForm.MouseButton1Click:Connect(function() act("labFormations", {}) end)
btnLabHist.MouseButton1Click:Connect(function() act("labHistory", { op = "list" }) end)
btnLabMatrix.MouseButton1Click:Connect(function() act("labMatrix", { runs = 4 }) end)

local resultsPanel = panel({ Size = UDim2.new(0, 440, 0, 320), Position = UDim2.new(0.5, -220, 0.5, -160), BackgroundColor3 = Color3.fromRGB(18, 20, 28), BackgroundTransparency = 0.03, Visible = false, ZIndex = 25 }, gui)
local resultsTitle = label({ Size = UDim2.new(1, 0, 0, 40), Text = "", TextColor3 = Color3.fromRGB(255, 210, 90), Font = Enum.Font.GothamBlack, TextSize = 22, ZIndex = 26 }, resultsPanel)
local timelineFrame = mk("Frame", { Size = UDim2.new(1, -40, 0, 70), Position = UDim2.new(0, 20, 0, 44), BackgroundColor3 = Color3.fromRGB(12, 14, 20), ZIndex = 26 }, resultsPanel)
local resultsBody = label({ Size = UDim2.new(1, -30, 1, -230), Position = UDim2.new(0, 15, 0, 120), Text = "", TextColor3 = Color3.fromRGB(210, 215, 230), TextSize = 12, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 26 }, resultsPanel)
local btnAgain = button("NEW BATTLE", Color3.fromRGB(50, 160, 80), { Size = UDim2.new(0, 150, 0, 34), Position = UDim2.new(0.5, -75, 1, -44), ZIndex = 26 }, resultsPanel)
btnAgain.MouseButton1Click:Connect(function()
	resultsPanel.Visible = false
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
	else
		resultsTitle.Text = UCConfig.TEAMS[result.winner].name .. " WINS  (level up: +XP)"
		resultsTitle.TextColor3 = UCConfig.TEAMS[result.winner].color
	end
	local insightsText = ""
	for _, insight in ipairs(payload.insights or {}) do
		insightsText = insightsText .. "- " .. insight .. "\n"
	end
	resultsBody.Text = string.format("Reason: %s   Duration: %ds\n\n%s\n\n%s\nINSIGHTS:\n%s",
		result.reason, result.duration, line("A"), line("B"), insightsText)
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

-- ---------- placement input + camera follow ----------

local arenaRoot = workspace:WaitForChild("UCBattle")

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	if state.phase == "setup" and state.selectedUnit then
		local hit = mouse.Hit
		if hit then
			local p = hit.Position
			if math.abs(p.Z) <= UCConfig.ARENA.DEPTH and math.abs(p.X) <= UCConfig.ARENA.HALF then
				act("place", { team = state.activeTeam, type = state.selectedUnit, upgrade = state.selectedUpgrade[state.selectedUnit], x = p.X, z = p.Z })
			end
		end
	else
		local target = mouse.Target
		if target and target.Parent and target.Parent:FindFirstChild("Health") then
			state.followModel = target.Parent
		end
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseButton2 then
		return
	end
	if state.phase == "setup" then
		local hit = mouse.Hit
		if hit then
			act("remove", { team = state.activeTeam, x = hit.Position.X, z = hit.Position.Z })
		end
	else
		state.followModel = nil
	end
end)

RunService.RenderStepped:Connect(function()
	if state.followModel and state.followModel.Parent then
		local cam = workspace.CurrentCamera
		local pos = state.followModel:GetPivot().Position
		cam.CFrame = cam.CFrame:Lerp(CFrame.new(pos + Vector3.new(0, 26, 30), pos), 0.15)
	end
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.O then
		state.followModel = nil
		local cam = workspace.CurrentCamera
		cam.CFrame = CFrame.new(Vector3.new(0, 90, 95), Vector3.new(0, 0, 0))
	end
end)

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
	local factionText = {}
	for team in pairs({ A = true, B = true }) do
		local f = s.factions and s.factions[team]
		table.insert(factionText, UCConfig.TEAMS[team].name .. ": " .. (f and UCConfig.FACTIONS[f].name or "no faction (right-click team button)") )
	end
	factionLabel.Text = table.concat(factionText, "   |   ")
	if s.momentum then
		local total = math.max(1, s.momentum.A + s.momentum.B)
		momA.Size = UDim2.new(s.momentum.A / total, 0, 1, 0)
		momB.Size = UDim2.new(s.momentum.B / total, 0, 1, 0)
		momB.Position = UDim2.new(s.momentum.A / total, 0, 0, 0)
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
print("[UNIT CLASH] client ready - " .. #UCConfig.ORDER .. " units, 30 upgrades, 4 factions, 6 arenas")
