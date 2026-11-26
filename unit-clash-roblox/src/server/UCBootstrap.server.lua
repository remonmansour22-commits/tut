-- UNIT CLASH - server bootstrap. Builds the arena, owns remotes, drives the sim.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UCConfig = require(ReplicatedStorage:WaitForChild("UCShared"):WaitForChild("UCConfig"))
local UCSim = require(script.Parent:WaitForChild("UCModules"):WaitForChild("UCSim"))
local UCVisuals = require(script.Parent:WaitForChild("UCModules"):WaitForChild("UCVisuals"))

-- ---------- remotes ----------

local remotes = Instance.new("Folder")
remotes.Name = "UCRemotes"
remotes.Parent = ReplicatedStorage

local function remote(name)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end

local evPlace = remote("UCPlace")
local evRemove = remote("UCRemove")
local evStart = remote("UCStart")
local evReset = remote("UCReset")
local evPause = remote("UCPause")
local evSpeed = remote("UCSpeed")
local evFill = remote("UCFillEnemy")
local evState = remote("UCState")
local evToast = remote("UCToast")

-- ---------- arena ----------

local arenaFolder = Instance.new("Folder")
arenaFolder.Name = "UCBattle"
arenaFolder.Parent = workspace

local unitsFolder = Instance.new("Folder")
unitsFolder.Name = "Units"
unitsFolder.Parent = arenaFolder

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = arenaFolder
	return p
end

local A = UCConfig.ARENA
local base = part({
	Name = "UCBase",
	Size = Vector3.new(A.HALF * 2 + 8, 2, A.DEPTH * 2 + 8),
	Position = Vector3.new(0, A.BASE_Y - 1, 0),
	Color = Color3.fromRGB(60, 66, 80),
	Material = Enum.Material.Slate,
	CanCollide = true,
})
part({
	Size = Vector3.new(A.HALF, 0.2, A.DEPTH * 2),
	Position = Vector3.new(-A.HALF / 2, A.BASE_Y + 0.05, 0),
	Color = UCConfig.TEAMS.A.color,
	Material = Enum.Material.SmoothPlastic,
	Transparency = 0.75,
})
part({
	Size = Vector3.new(A.HALF, 0.2, A.DEPTH * 2),
	Position = Vector3.new(A.HALF / 2, A.BASE_Y + 0.05, 0),
	Color = UCConfig.TEAMS.B.color,
	Material = Enum.Material.SmoothPlastic,
	Transparency = 0.75,
})
part({
	Size = Vector3.new(0.6, 0.4, A.DEPTH * 2),
	Position = Vector3.new(0, A.BASE_Y + 0.1, 0),
	Color = Color3.fromRGB(255, 255, 255),
	Material = Enum.Material.Neon,
})

-- ---------- sim + state ----------

local sim = UCSim.new(unitsFolder)

local function broadcastState()
	evState:FireAllClients({
		phase = sim.phase,
		paused = sim.paused,
		speed = sim.speed,
		spent = sim.spent,
		budget = UCConfig.BUDGET,
		deployed = sim.deployed,
		timeLimit = UCConfig.BATTLE_TIME_LIMIT,
		clock = math.floor(sim.time),
	})
end

local function announceResults()
	local results = sim:results()
	local winnerName = results.winner == "draw" and "NOBODY" or UCConfig.TEAMS[results.winner].name
	local banner = UCVisuals.victoryBanner(winnerName, results.winner == "draw" and Color3.fromRGB(160, 160, 160) or UCConfig.TEAMS[results.winner].color)
	evState:FireAllClients({ phase = "results", results = results })
	task.delay(6, function()
		banner:Destroy()
	end)
end

-- ---------- enemy army generation ----------

local rng = Random.new()

local function fillEnemy()
	if sim.phase ~= "setup" then
		evToast:FireAllClients("Battle already started")
		return
	end
	local budget = UCConfig.BUDGET.B - sim.spent.B
	local ids = UCConfig.ORDER
	local guard = 0
	while budget >= 45 and guard < 200 do
		guard = guard + 1
		local id = ids[rng:NextInteger(1, #ids)]
		local def = UCConfig.get(id)
		if def.cost <= budget then
			local x = rng:NextNumber(20, UCConfig.ARENA.HALF - 12)
			local z = rng:NextNumber(-UCConfig.ARENA.DEPTH + 8, UCConfig.ARENA.DEPTH - 8)
			local ok = sim:placeUnit("B", id, x, z)
			if ok then
				budget = budget - def.cost
			end
		end
	end
	broadcastState()
end

-- ---------- remote handlers ----------

local function inBounds(team, x, z)
	local half, depth = UCConfig.ARENA.HALF, UCConfig.ARENA.DEPTH
	if math.abs(z) > depth - 3 then
		return false
	end
	if team == "A" then
		return x < -3 and x > -half + 3
	elseif team == "B" then
		return x > 3 and x < half - 3
	end
	return false
end

evPlace.OnServerEvent:Connect(function(player, team, unitId, x, z)
	if typeof(team) ~= "string" or typeof(unitId) ~= "string" or typeof(x) ~= "number" or typeof(z) ~= "number" then
		return
	end
	if not inBounds(team, x, z) then
		evToast:FireClient(player, "Place units inside your team's half")
		return
	end
	local ok, err = sim:placeUnit(team, unitId, x, z)
	if not ok and err then
		evToast:FireClient(player, err)
	end
	broadcastState()
end)

evRemove.OnServerEvent:Connect(function(player, team, x, z)
	if typeof(team) ~= "string" or typeof(x) ~= "number" or typeof(z) ~= "number" then
		return
	end
	sim:removeUnitAt(team, x, z)
	broadcastState()
end)

evStart.OnServerEvent:Connect(function()
	if sim.phase ~= "setup" then
		return
	end
	if sim:aliveOf("A") == 0 or sim:aliveOf("B") == 0 then
		evToast:FireAllClients("Both teams need at least one unit")
		return
	end
	sim:startBattle()
	broadcastState()
	task.spawn(function()
		while not sim.outcome do
			task.wait(1)
			broadcastState()
		end
		announceResults()
	end)
end)

evReset.OnServerEvent:Connect(function()
	sim:reset()
	broadcastState()
end)

evPause.OnServerEvent:Connect(function()
	if sim.phase == "battle" then
		sim.paused = not sim.paused
		broadcastState()
	end
end)

evSpeed.OnServerEvent:Connect(function(player, value)
	if typeof(value) ~= "number" then
		return
	end
	local allowed = { [0.5] = true, [1] = true, [2] = true, [4] = true }
	if allowed[value] and sim.phase == "battle" then
		sim.speed = value
		broadcastState()
	end
end)

evFill.OnServerEvent:Connect(function()
	fillEnemy()
end)

evState.OnServerEvent:Connect(function(player)
	broadcastState()
end)

broadcastState()
print("[UNIT CLASH] server ready - place units, then START")
