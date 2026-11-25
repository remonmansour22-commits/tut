-- Path: StarterPlayer/StarterPlayerScripts/BuildingController (LocalScript)
-- Build menu, ghost preview over plot pads, rotation, confirm/cancel.
-- The client never sets costs or validity — it only submits intentions.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("BeastboundShared")
local Net = require(Shared.Net)
local BuildingConfig = require(Shared.BuildingConfig)

local player = Players.LocalPlayer
local buildRemote = Net.get("BuildRequest")

local state = {
	open = false,
	placing = nil,
	rotationStep = 0,
	targetPad = nil,
	inventory = {},
	catalogue = {},
}

local PAD_FOLDER = workspace:WaitForChild("Aruun"):WaitForChild("BuildPlots")

--=====================================================================
-- UI construction (pure code, mobile friendly)
--=====================================================================

local gui = Instance.new("ScreenGui")
gui.Name = "BeastboundBuild"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local function card(parent, size, position, corner)
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = Color3.fromRGB(18, 26, 24)
	frame.BackgroundTransparency = 0.12
	frame.BorderSizePixel = 0
	frame.Parent = parent
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(0, corner or 14)
	uiCorner.Parent = frame
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(120, 255, 190)
	stroke.Transparency = 0.7
	stroke.Parent = frame
	return frame
end

local toggle = Instance.new("TextButton")
toggle.Size = UDim2.fromOffset(150, 52)
toggle.Position = UDim2.new(1, -170, 1, -76)
toggle.Font = Enum.Font.GothamBold
toggle.TextSize = 22
toggle.Text = "BUILD"
toggle.TextColor3 = Color3.fromRGB(20, 30, 25)
toggle.BackgroundColor3 = Color3.fromRGB(120, 255, 190)
toggle.Parent = gui
Instance.new("UICorner").Parent = toggle

local panel = card(gui, UDim2.fromOffset(330, 420), UDim2.new(1, -354, 1, -540), 16)
panel.Visible = false
do
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = panel
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 12)
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = panel
end

local panelTitle = Instance.new("TextLabel")
panelTitle.Size = UDim2.new(1, 0, 0, 28)
panelTitle.BackgroundTransparency = 1
panelTitle.Font = Enum.Font.GothamBold
panelTitle.TextSize = 20
panelTitle.TextXAlignment = Enum.TextXAlignment.Left
panelTitle.LayoutOrder = 0
panelTitle.Text = "Constructions"
panelTitle.TextColor3 = Color3.fromRGB(230, 245, 235)
panelTitle.Parent = panel

local rows = {}

for index, id in ipairs(BuildingConfig.Order) do
	local def = BuildingConfig.ById[id]
	local row = card(panel, UDim2.new(1, 0, 0, 88), UDim2.new(0, 0, 0, 0), 10)
	row.LayoutOrder = index

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -16, 0, 22)
	nameLabel.Position = UDim.new(0, 8, 0, 4)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 18
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.Text = def.DisplayName
	nameLabel.TextColor3 = Color3.fromRGB(230, 245, 235)
	nameLabel.Parent = row

	local descLabel = Instance.new("TextLabel")
	descLabel.Size = UDim2.new(1, -16, 0, 32)
	descLabel.Position = UDim.new(0, 8, 0, 26)
	descLabel.BackgroundTransparency = 1
	descLabel.Font = Enum.Font.Gotham
	descLabel.TextSize = 13
	descLabel.TextWrapped = true
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextColor3 = Color3.fromRGB(170, 195, 180)
	descLabel.Text = def.Description
	descLabel.Parent = row

	local costLabel = Instance.new("TextLabel")
	costLabel.Size = UDim2.new(1, -16, 0, 20)
	costLabel.Position = UDim.new(0, 8, 1, -26)
	costLabel.BackgroundTransparency = 1
	costLabel.Font = Enum.Font.GothamMedium
	costLabel.TextSize = 14
	costLabel.TextXAlignment = Enum.TextXAlignment.Left
	costLabel.TextColor3 = Color3.fromRGB(120, 255, 190)
	costLabel.Parent = row

	row.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			state.placing = id
			state.rotationStep = 0
			panel.Visible = false
			bar.Visible = true
			barLabel.Text = "Walk to a glowing plot pad, then Confirm."
		end
	end)
	rows[id] = { row = row, cost = costLabel }
end

-- placement bar
local bar = card(gui, UDim2.fromOffset(470, 64), UDim2.new(0.5, -235, 1, -180), 16)
bar.Visible = false
local barLabel = Instance.new("TextLabel")
barLabel.Size = UDim2.new(1, -260, 1, -12)
barLabel.Position = UDim.new(0, 12, 0, 6)
barLabel.BackgroundTransparency = 1
barLabel.Font = Enum.Font.GothamBold
barLabel.TextSize = 15
barLabel.TextXAlignment = Enum.TextXAlignment.Left
barLabel.TextColor3 = Color3.fromRGB(230, 245, 235)
barLabel.Parent = bar

local rotateButton = Instance.new("TextButton")
rotateButton.Size = UDim2.fromOffset(110, 44)
rotateButton.Position = UDim2.new(1, -238, 0.5, -22)
rotateButton.Font = Enum.Font.GothamBold
rotateButton.TextSize = 18
rotateButton.Text = "Rotate"
rotateButton.TextColor3 = Color3.fromRGB(20, 30, 25)
rotateButton.BackgroundColor3 = Color3.fromRGB(120, 255, 190)
rotateButton.Parent = bar
Instance.new("UICorner").Parent = rotateButton

local confirmButton = Instance.new("TextButton")
confirmButton.Size = UDim2.fromOffset(110, 44)
confirmButton.Position = UDim2.new(1, -120, 0.5, -22)
confirmButton.Font = Enum.Font.GothamBold
confirmButton.TextSize = 18
confirmButton.Text = "Confirm"
confirmButton.TextColor3 = Color3.fromRGB(20, 30, 25)
confirmButton.BackgroundColor3 = Color3.fromRGB(255, 220, 120)
confirmButton.Parent = bar
Instance.new("UICorner").Parent = confirmButton

local ghost = Instance.new("Part")
ghost.Name = "BuildGhost"
ghost.Size = Vector3.new(16, 12, 16)
ghost.Transparency = 1
ghost.Color = Color3.fromRGB(120, 255, 190)
ghost.Material = Enum.Material.ForceField
ghost.Anchored = true
ghost.CanCollide = false
ghost.CanQuery = false
ghost.Parent = workspace

--=====================================================================
-- Behavior
--=====================================================================

local function costText(def)
	local parts = {}
	for resourceId, amount in pairs(def.Cost or {}) do
		table.insert(parts, amount .. " " .. resourceId)
	end
	table.sort(parts)
	return table.concat(parts, "   ")
end

local function refreshCatalogue()
	for _, entry in ipairs(state.catalogue) do
		local row = rows[entry.id]
		if row then
			row.cost.Text = (entry.unlocked and "" or ("Locked — Level " .. entry.unlockLevel .. " — ")) .. costText(entry)
			row.cost.TextColor3 = entry.unlocked and Color3.fromRGB(120, 255, 190) or Color3.fromRGB(220, 170, 110)
		end
	end
end

toggle.Activated:Connect(function()
	state.open = not state.open
	panel.Visible = state.open
end)

rotateButton.Activated:Connect(function()
	state.rotationStep = (state.rotationStep + 1) % 4
	ghost.CFrame = ghost.CFrame * CFrame.Angles(0, math.rad(90), 0)
end)

confirmButton.Activated:Connect(function()
	if not state.placing then
		return
	end
	if not state.targetPad then
		barLabel.Text = "Stand near a glowing plot pad first."
		return
	end
	buildRemote:FireServer(state.placing, state.targetPad.Name, state.rotationStep)
	state.placing = nil
	state.rotationStep = 0
	state.targetPad = nil
	bar.Visible = false
	ghost.Transparency = 1
end)

RunService.RenderStepped:Connect(function()
	if not state.placing then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end

	local best, bestDist = nil, 26
	for _, pad in ipairs(PAD_FOLDER:GetChildren()) do
		if pad:IsA("BasePart") and pad:GetAttribute("StructureId") == "" then
			local dist = (pad.Position - root.Position).Magnitude
			if dist < bestDist then
				best, bestDist = pad, dist
			end
		end
	end

	state.targetPad = best
	if best then
		ghost.Transparency = 0.7
		ghost.CFrame = CFrame.new(best.Position + Vector3.new(0, 7, 0)) * CFrame.Angles(0, math.rad(state.rotationStep * 90), 0)
	else
		ghost.Transparency = 1
	end
end)

Net.get("PlayerSync").OnClientEvent:Connect(function(snapshot)
	if type(snapshot) ~= "table" then
		return
	end
	state.inventory = snapshot.inventory or {}
	state.catalogue = snapshot.catalogue or {}
	refreshCatalogue()
end)
