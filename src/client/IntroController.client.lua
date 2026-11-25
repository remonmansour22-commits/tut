-- Path: StarterPlayer/StarterPlayerScripts/IntroController (LocalScript)
-- Minute 0 reveal: a short, skippable cinematic that frames Aruun and the
-- settlement, then hands the camera back to the player.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local gui = Instance.new("ScreenGui")
gui.Name = "BeastboundIntro"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 50
gui.Parent = player:WaitForChild("PlayerGui")

local backdrop = Instance.new("Frame")
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.BackgroundColor3 = Color3.fromRGB(10, 16, 18)
backdrop.BackgroundTransparency = 0.35
backdrop.BorderSizePixel = 0
backdrop.Parent = gui

local gradient = Instance.new("UIGradient")
gradient.Color = ColorSequence.new(Color3.fromRGB(10, 16, 18), Color3.fromRGB(20, 40, 38))
gradient.Rotation = 90
gradient.Parent = backdrop

local title = Instance.new("TextLabel")
title.Size = UDim2.fromScale(1, 0.2)
title.Position = UDim2.fromScale(0, 0.34)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.Text = "BEASTBOUND"
title.TextScaled = true
title.TextColor3 = Color3.fromRGB(255, 240, 200)
title.TextStrokeTransparency = 0.7
title.Parent = backdrop

local subtitle = Instance.new("TextLabel")
subtitle.Size = UDim2.fromScale(1, 0.06)
subtitle.Position = UDim2.fromScale(0, 0.54)
subtitle.BackgroundTransparency = 1
subtitle.Font = Enum.Font.GothamMedium
subtitle.TextScaled = true
subtitle.Text = "The Great Migration — you live on the back of a giant named Aruun"
subtitle.TextColor3 = Color3.fromRGB(200, 230, 205)
subtitle.Parent = backdrop

local skip = Instance.new("TextButton")
skip.Size = UDim2.fromScale(0.2, 0.07)
skip.Position = UDim2.fromScale(0.4, 0.88)
skip.Font = Enum.Font.GothamBold
skip.TextScaled = true
skip.Text = "Begin"
skip.TextColor3 = Color3.fromRGB(20, 30, 25)
skip.BackgroundColor3 = Color3.fromRGB(120, 255, 190)
skip.Parent = gui
Instance.new("UICorner").Parent = skip

local started = false

local function endIntro()
	if started then
		return
	end
	started = true
	local fade = TweenService:Create(gui, TweenInfo.new(0.8), { Enabled = false })
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	fade:Play()
	task.delay(1, function()
		gui:Destroy()
	end)
end

skip.Activated:Connect(endIntro)

task.spawn(function()
	if not workspace:FindFirstChild("Aruun") then
		workspace:WaitForChild("Aruun", 10)
	end
	camera.CameraType = Enum.CameraType.Scriptable

	camera.CFrame = CFrame.new(0, 40, 330) * CFrame.Angles(math.rad(6), 0, 0)
	TweenService:Create(camera, TweenInfo.new(9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
		CFrame = CFrame.new(0, 88, 210) * CFrame.Angles(0, 0, 0),
	}):Play()

	task.delay(9, endIntro)
end)
