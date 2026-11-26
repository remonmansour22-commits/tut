-- UNIT CLASH - client: palette, placement, battle controls, results UI.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local UCConfig = require(ReplicatedStorage:WaitForChild("UCShared"):WaitForChild("UCConfig"))

local remotes = ReplicatedStorage:WaitForChild("UCRemotes")
local evPlace = remotes:WaitForChild("UCPlace")
local evRemove = remotes:WaitForChild("UCRemove")
local evStart = remotes:WaitForChild("UCStart")
local evReset = remotes:WaitForChild("UCReset")
local evPause = remotes:WaitForChild("UCPause")
local evSpeed = remotes:WaitForChild("UCSpeed")
local evFill = remotes:WaitForChild("UCFillEnemy")
local evState = remotes:WaitForChild("UCState")
local evToast = remotes:WaitForChild("UCToast")

local state = {
	phase = "setup",
	spent = { A = 0, B = 0 },
	deployed = { A = 0, B = 0 },
	selectedUnit = nil,
	activeTeam = "A",
	speed = 1,
	paused = false,
	clock = 0,
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

local gui = mk("ScreenGui", { Name = "UCUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))

-- ---------- toast ----------

local toast = mk("TextLabel", {
	Size = UDim2.new(0, 340, 0, 34),
	Position = UDim2.new(0.5, -170, 0, 46),
	BackgroundColor3 = Color3.fromRGB(25, 25, 35),
	BackgroundTransparency = 0.15,
	TextColor3 = Color3.fromRGB(255, 230, 160),
	Font = Enum.Font.GothamBold,
	TextSize = 15,
	Text = "",
	Visible = false,
	ZIndex = 10,
}, gui)
corner(toast)

task.spawn(function()
	while true do
		local message = evToast.OnClientEvent:Wait()
		toast.Visible = true
		toast.Text = tostring(message)
		task.wait(2)
		toast.Visible = false
	end
end)

-- ---------- top bar ----------

local topBar = mk("Frame", {
	Size = UDim2.new(1, -20, 0, 44),
	Position = UDim2.new(0, 10, 0, 6),
	BackgroundColor3 = Color3.fromRGB(18, 20, 28),
	BackgroundTransparency = 0.1,
}, gui)
corner(topBar)

local titleLabel = mk("TextLabel", {
	Size = UDim2.new(0, 150, 1, 0),
	Position = UDim2.new(0, 10, 0, 0),
	BackgroundTransparency = 1,
	Text = "UNIT CLASH",
	TextColor3 = Color3.fromRGB(255, 210, 90),
	Font = Enum.Font.GothamBlack,
	TextSize = 20,
	TextXAlignment = Enum.TextXAlignment.Left,
}, topBar)

local statusLabel = mk("TextLabel", {
	Size = UDim2.new(0, 330, 1, 0),
	Position = UDim2.new(0, 160, 0, 0),
	BackgroundTransparency = 1,
	Text = "",
	TextColor3 = Color3.fromRGB(220, 220, 230),
	Font = Enum.Font.Gotham,
	TextSize = 14,
	TextXAlignment = Enum.TextXAlignment.Left,
}, topBar)

local function actionButton(text, color, order)
	local btn = mk("TextButton", {
		Size = UDim2.new(0, 92, 0, 32),
		Position = UDim2.new(1, -(order * 100) - 10, 0.5, -16),
		BackgroundColor3 = color or Color3.fromRGB(60, 70, 95),
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		Text = text,
	}, topBar)
	corner(btn, 6)
	return btn
end

local btnStart = actionButton("START", Color3.fromRGB(50, 160, 80), 1)
local btnPause = actionButton("PAUSE", Color3.fromRGB(70, 80, 110), 2)
local btnSpeed = actionButton("1x", Color3.fromRGB(70, 80, 110), 3)
local btnFill = actionButton("ENEMY AI", Color3.fromRGB(150, 80, 60), 4)
local btnClear = actionButton("CLEAR", Color3.fromRGB(90, 70, 70), 5)

local SPEEDS = { 1, 2, 4, 0.5 }
local speedIndex = 1

btnStart.MouseButton1Click:Connect(function() evStart:FireServer() end)
btnPause.MouseButton1Click:Connect(function() evPause:FireServer() end)
btnFill.MouseButton1Click:Connect(function() evFill:FireServer() end)
btnClear.MouseButton1Click:Connect(function() evReset:FireServer() end)
btnSpeed.MouseButton1Click:Connect(function()
	speedIndex = speedIndex % #SPEEDS + 1
	btnSpeed.Text = SPEEDS[speedIndex] .. "x"
	evSpeed:FireServer(SPEEDS[speedIndex])
end)

-- ---------- team toggle ----------

local teamToggle = mk("Frame", {
	Size = UDim2.new(0, 240, 0, 36),
	Position = UDim2.new(0.5, -120, 0, 56),
	BackgroundColor3 = Color3.fromRGB(18, 20, 28),
	BackgroundTransparency = 0.15,
}, gui)
corner(teamToggle)

local function teamButton(team, offset)
	local t = UCConfig.TEAMS[team]
	local btn = mk("TextButton", {
		Size = UDim2.new(0.5, -6, 1, -8),
		Position = UDim2.new(offset, 4, 0, 4),
		BackgroundColor3 = t.color,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		Text = "PLACE: " .. t.name,
		Name = team,
	}, teamToggle)
	corner(btn, 6)
	return btn
end

local btnTeamA = teamButton("A", 0)
local btnTeamB = teamButton("B", 0.5)

local function refreshTeamButtons()
	local t = UCConfig.TEAMS[state.activeTeam]
	btnTeamA.BackgroundColor3 = state.activeTeam == "A" and UCConfig.TEAMS.A.color or Color3.fromRGB(45, 50, 70)
	btnTeamB.BackgroundColor3 = state.activeTeam == "B" and UCConfig.TEAMS.B.color or Color3.fromRGB(45, 50, 70)
end

btnTeamA.MouseButton1Click:Connect(function()
	state.activeTeam = "A"
	refreshTeamButtons()
end)
btnTeamB.MouseButton1Click:Connect(function()
	state.activeTeam = "B"
	refreshTeamButtons()
end)
refreshTeamButtons()

-- ---------- unit palette ----------

local palette = mk("ScrollingFrame", {
	Size = UDim2.new(0, 220, 1, -160),
	Position = UDim2.new(0, 10, 0, 100),
	BackgroundColor3 = Color3.fromRGB(18, 20, 28),
	BackgroundTransparency = 0.1,
	ScrollBarThickness = 6,
	CanvasSize = UDim2.new(0, 0, 0, 0),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, gui)
corner(palette)
mk("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, palette)

local cardByUnit = {}

for order, unitId in ipairs(UCConfig.ORDER) do
	local def = UCConfig.get(unitId)
	local card = mk("TextButton", {
		Size = UDim2.new(1, -12, 0, 58),
		BackgroundColor3 = Color3.fromRGB(30, 34, 48),
		Text = "",
		LayoutOrder = order,
		AutoButtonColor = true,
	}, palette)
	corner(card, 6)
	mk("Frame", {
		Size = UDim2.new(0, 8, 1, -10),
		Position = UDim2.new(0, 5, 0, 5),
		BackgroundColor3 = def.color,
	}, card)
	mk("TextLabel", {
		Size = UDim2.new(1, -30, 0, 20),
		Position = UDim2.new(0, 20, 0, 6),
		BackgroundTransparency = 1,
		Text = def.name .. "  (" .. def.cost .. ")",
		TextColor3 = Color3.fromRGB(240, 240, 250),
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, card)
	mk("TextLabel", {
		Size = UDim2.new(1, -30, 0, 26),
		Position = UDim2.new(0, 20, 0, 27),
		BackgroundTransparency = 1,
		Text = def.category .. " - " .. def.desc,
		TextColor3 = Color3.fromRGB(160, 165, 180),
		Font = Enum.Font.Gotham,
		TextSize = 10,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	}, card)
	cardByUnit[unitId] = card
	card.MouseButton1Click:Connect(function()
		state.selectedUnit = unitId
		for id, c in pairs(cardByUnit) do
			c.BackgroundColor3 = id == unitId and Color3.fromRGB(70, 90, 60) or Color3.fromRGB(30, 34, 48)
		end
	end)
end

-- ---------- placement input ----------

local base = workspace:WaitForChild("UCBattle"):WaitForChild("UCBase")

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return
	end
	if state.phase ~= "setup" or not state.selectedUnit then
		return
	end
	local hit = mouse.Hit
	if not hit then
		return
	end
	local p = hit.Position
	if math.abs(p.Z) > UCConfig.ARENA.DEPTH or math.abs(p.X) > UCConfig.ARENA.HALF then
		return
	end
	evPlace:FireServer(state.activeTeam, state.selectedUnit, p.X, p.Z)
end)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed or input.UserInputType ~= Enum.UserInputType.MouseButton2 then
		return
	end
	if state.phase ~= "setup" then
		return
	end
	local hit = mouse.Hit
	if hit then
		evRemove:FireServer(state.activeTeam, hit.Position.X, hit.Position.Z)
	end
end)

-- ---------- results panel ----------

local resultsPanel = mk("Frame", {
	Size = UDim2.new(0, 400, 0, 260),
	Position = UDim2.new(0.5, -200, 0.5, -130),
	BackgroundColor3 = Color3.fromRGB(18, 20, 28),
	BackgroundTransparency = 0.05,
	Visible = false,
	ZIndex = 5,
}, gui)
corner(resultsPanel, 10)

local resultsTitle = mk("TextLabel", {
	Size = UDim2.new(1, 0, 0, 44),
	BackgroundTransparency = 1,
	Text = "",
	TextColor3 = Color3.fromRGB(255, 210, 90),
	Font = Enum.Font.GothamBlack,
	TextSize = 24,
	ZIndex = 6,
}, resultsPanel)

local resultsBody = mk("TextLabel", {
	Size = UDim2.new(1, -30, 1, -100),
	Position = UDim2.new(0, 15, 0, 48),
	BackgroundTransparency = 1,
	Text = "",
	TextColor3 = Color3.fromRGB(210, 215, 230),
	Font = Enum.Font.Gotham,
	TextSize = 14,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Left,
	TextYAlignment = Enum.TextYAlignment.Top,
	ZIndex = 6,
}, resultsPanel)

local btnAgain = mk("TextButton", {
	Size = UDim2.new(0, 160, 0, 36),
	Position = UDim2.new(0.5, -80, 1, -46),
	BackgroundColor3 = Color3.fromRGB(50, 160, 80),
	TextColor3 = Color3.fromRGB(255, 255, 255),
	Font = Enum.Font.GothamBold,
	TextSize = 16,
	Text = "NEW BATTLE",
	ZIndex = 6,
}, resultsPanel)
corner(btnAgain, 8)
btnAgain.MouseButton1Click:Connect(function()
	resultsPanel.Visible = false
	evReset:FireServer()
end)

local function showResults(results)
	resultsPanel.Visible = true
	local line = function(teamId)
		local t = results[teamId]
		return string.format("%s - deployed %d, survivors %d, damage %d, healing %d, abilities %d (spent %d)",
			UCConfig.TEAMS[teamId].name, t.deployed, t.survivors, t.damage, t.healing, t.abilities, t.spent)
	end
	if results.winner == "draw" then
		resultsTitle.Text = "DRAW"
		resultsTitle.TextColor3 = Color3.fromRGB(180, 180, 180)
	else
		resultsTitle.Text = UCConfig.TEAMS[results.winner].name .. " WINS"
		resultsTitle.TextColor3 = UCConfig.TEAMS[results.winner].color
	end
	resultsBody.Text = string.format("Reason: %s   Duration: %ds\n\n%s\n\n%s",
		results.reason, results.duration, line("A"), line("B"))
end

-- ---------- state sync ----------

evState.OnClientEvent:Connect(function(s)
	if s.results then
		showResults(s.results)
		state.phase = "results"
		return
	end
	state.phase = s.phase
	state.spent = s.spent
	state.deployed = s.deployed
	state.paused = s.paused
	state.clock = s.clock or 0
	btnPause.Text = s.paused and "RESUME" or "PAUSE"
	if s.phase == "setup" then
		statusLabel.Text = string.format("SETUP - Azure %d/%d (%d) | Crimson %d/%d (%d) | pick a unit, click a half",
			state.spent.A, s.budget.A, state.deployed.A, state.spent.B, s.budget.B, state.deployed.B)
	elseif s.phase == "battle" then
		statusLabel.Text = string.format("BATTLE - %ds / %ds | speed %sx", state.clock, s.timeLimit, s.speed)
		resultsPanel.Visible = false
	elseif s.phase == "results" then
		statusLabel.Text = "BATTLE OVER"
	end
end)

evState:FireServer()
print("[UNIT CLASH] client ready")
