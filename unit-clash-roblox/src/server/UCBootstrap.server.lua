-- UNIT CLASH - server bootstrap. Arena build, remotes, mode switching, the
-- live battle loop (core + presenter), Battle Lab endpoints, progression,
-- saves and share codes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UCConfig = require(ReplicatedStorage:WaitForChild("UCShared"):WaitForChild("UCConfig"))
local UCShareCodec = require(ReplicatedStorage:WaitForChild("UCShared"):WaitForChild("UCShareCodec"))
local UCRng = require(script.Parent:WaitForChild("UCModules"):WaitForChild("UCRng"))
local UCSimCore = require(script.Parent:WaitForChild("UCModules"):WaitForChild("UCSimCore"))
local UCModes = require(script.Parent:WaitForChild("UCModules"):WaitForChild("UCModes"))
local UCLab = require(script.Parent:WaitForChild("UCModules"):WaitForChild("UCLab"))
local UCProgress = require(script.Parent:WaitForChild("UCModules"):WaitForChild("UCProgress"))

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

local evAction = remote("UCAction")
local evState = remote("UCState")
local evResults = remote("UCResults")
local evLab = remote("UCLab")
local evToast = remote("UCToast")
local evBattle = remote("UCBattle")

-- ---------- session state ----------

local session = {
	mode = "sandbox",
	mission = nil,
	arenaId = "grassland",
	factions = { A = nil, B = nil },
	seed = os.time() % 100000,
	restrict = nil,
	wave = 0,
	budgets = { A = UCConfig.BUDGET.A, B = UCConfig.BUDGET.B },
	staged = { A = {}, B = {} },
	phase = "setup",
	battle = nil,
	speed = 1,
	paused = false,
	cinematic = false,
}

local lab = UCLab.new()
local profiles = {}

local function profileFor(player)
	if not profiles[player.UserId] then
		profiles[player.UserId] = UCProgress.load(player)
	end
	return profiles[player.UserId]
end

-- ---------- arena ----------

local arenaFolder = Instance.new("Folder")
arenaFolder.Name = "UCBattle"
arenaFolder.Parent = workspace

local unitsFolder = Instance.new("Folder")
unitsFolder.Name = "Units"
unitsFolder.Parent = arenaFolder

local function buildArena(arenaId)
	for _, child in ipairs(arenaFolder:GetChildren()) do
		if child ~= unitsFolder then
			child:Destroy()
		end
	end
	local arena = UCConfig.ARENAS[arenaId] or UCConfig.ARENAS.grassland
	local A = UCConfig.ARENA
	local base = Instance.new("Part")
	base.Name = "UCBase"
	base.Anchored = true
	base.Size = Vector3.new(A.HALF * 2 + 8, 2, A.DEPTH * 2 + 8)
	base.Position = Vector3.new(0, A.BASE_Y - 1, 0)
	base.Color = arena.ground
	base.Material = arena.material
	base.TopSurface = Enum.SurfaceType.Smooth
	base.Parent = arenaFolder

	for team, xSign in pairs({ A = -1, B = 1 }) do
		local zone = Instance.new("Part")
		zone.Anchored = true
		zone.CanCollide = false
		zone.Size = Vector3.new(A.HALF, 0.15, A.DEPTH * 2)
		zone.Position = Vector3.new(xSign * A.HALF / 2, A.BASE_Y + 0.1, 0)
		zone.Color = UCConfig.TEAMS[team].color
		zone.Material = Enum.Material.SmoothPlastic
		zone.Transparency = 0.8
		zone.Parent = arenaFolder
	end

	local line = Instance.new("Part")
	line.Anchored = true
	line.CanCollide = false
	line.Size = Vector3.new(0.6, 0.3, A.DEPTH * 2)
	line.Position = Vector3.new(0, A.BASE_Y + 0.12, 0)
	line.Color = Color3.fromRGB(255, 255, 255)
	line.Material = Enum.Material.Neon
	line.Parent = arenaFolder
end

buildArena(session.arenaId)

-- ---------- staging helpers ----------

local function stagedCost(team)
	local total = 0
	for _, e in ipairs(session.staged[team]) do
		local def = UCConfig.get(e.type)
		if def then
			total = total + def.cost
		end
	end
	return total
end

local function categoryBlocked(team, unitId)
	if not session.restrict or not session.restrict.categories then
		return false
	end
	local def = UCConfig.get(unitId)
	return session.restrict.categories[def.category] or false
end

local function toast(player, message)
	evToast:FireClient(player, message)
end

local function momentumOf(core)
	local mA, mB = 0, 0
	for _, u in ipairs(core.units) do
		if u.alive then
			local value = u.def.cost * (u.hp / u.maxHp)
			if u.team == "A" then
				mA = mA + value
			else
				mB = mB + value
			end
		end
	end
	return { A = mA, B = mB }
end

-- Compact live snapshot for the 2D client renderer. The server keeps no visuals.
local function snapshotFor(core)
	local units, projs, devs, fx = {}, {}, {}, {}
	for _, u in ipairs(core.units) do
		if u.alive then
			table.insert(units, { u.id, u.type, u.team, u.x, u.z, u.hp, u.maxHp, u.def.radius or 1, (core.t - (u.lastAtk or -9)) < 0.22 })
		end
	end
	for _, p in ipairs(core.projectiles) do
		table.insert(projs, { p.x, p.z, p.team })
	end
	for _, d in ipairs(core.devices) do
		if d.alive ~= false and d.hp > 0 then
			table.insert(devs, { d.kind, d.team, d.x, d.z, d.hp, d.maxHp, d.radius or (d.def and d.def.radius) or 3 })
		end
	end
	local events = core:drainEvents()
	for i, e in ipairs(events) do
		if i > 24 then
			break
		end
		table.insert(fx, { e.type, e.x or e.fx or 0, e.z or e.fz or 0, e.amount or e.r or 0, e.name or e.team or "" })
	end
	return { units = units, projs = projs, devs = devs, fx = fx, aliveA = core:aliveOf("A"), aliveB = core:aliveOf("B") }
end

local function broadcastState()
	local momentum = session.battle and momentumOf(session.battle.core) or { A = 0, B = 0 }
	evState:FireAllClients({
		phase = session.phase,
		mode = session.mode,
		mission = session.mission,
		wave = session.wave,
		arena = session.arenaId,
		arenaName = UCConfig.ARENAS[session.arenaId].name,
		factions = session.factions,
		spent = { A = stagedCost("A"), B = stagedCost("B") },
		budgets = session.budgets,
		deployed = { A = #session.staged.A, B = #session.staged.B },
		speed = session.speed,
		paused = session.paused,
		clock = session.battle and math.floor(session.battle.core.t) or 0,
		timeLimit = UCConfig.BATTLE_TIME_LIMIT,
		momentum = momentum,
		seed = session.seed,
		staged = { A = session.staged.A, B = session.staged.B },
	})
end

-- ---------- battle lifecycle ----------

local function buildConfigFromStaged(seedOverride)
	local teams = {}
	for team in pairs({ A = true, B = true }) do
		teams[team] = {}
		for _, e in ipairs(session.staged[team]) do
			table.insert(teams[team], { type = e.type, upgrade = e.upgrade, x = e.x, z = e.z, hpFrac = e.hpFrac })
		end
	end
	return {
		arena = session.arenaId,
		seed = seedOverride or session.seed,
		timeLimit = UCConfig.BATTLE_TIME_LIMIT,
		factions = session.factions,
		budgets = session.budgets,
		teams = teams,
	}
end

local function loadStagedFromConfig(config)
	session.arenaId = config.arena or session.arenaId
	session.factions = config.factions or { A = nil, B = nil }
	session.budgets = config.budgets or { A = UCConfig.BUDGET.A, B = UCConfig.BUDGET.B }
	session.staged = { A = {}, B = {} }
	for team in pairs({ A = true, B = true }) do
		for _, e in ipairs(config.teams and config.teams[team] or {}) do
			table.insert(session.staged[team], { type = e.type, upgrade = e.upgrade, x = e.x, z = e.z, hpFrac = e.hpFrac })
		end
	end
	buildArena(session.arenaId)
end

local function endBattle(result, core)
	session.phase = "results"
	local insights = lab:insights(result)
	evResults:FireAllClients({ result = result, timeline = core.timeline, insights = insights })

	local player = Players_GetFirst()
	if player then
		local profile = profileFor(player)
		local types = {}
		for _, e in ipairs(session.staged.A) do
			table.insert(types, e.type)
		end
		UCProgress.awardBattle(player, profile, result.winner == "A")
		UCProgress.trackMastery(player, profile, types)
		if session.mode == "campaign" and result.winner == "A" and session.mission then
			UCProgress.completeCampaign(player, profile, session.mission)
		end
	end

	if session.mode == "survival" and result.winner == "A" then
		task.delay(5, function()
			local player2 = Players_GetFirst()
			if player2 then
				local profile = profileFor(player2)
				local survivors = {}
				for _, u in ipairs(core.units) do
					if u.alive and u.team == "A" then
						table.insert(survivors, { type = u.type, upgrade = u.upgrade, x = u.x, z = u.z, hpFrac = u.hp / u.maxHp })
					end
				end
				session.staged.A = survivors
				session.wave = session.wave + 1
				local rng = UCRng.new(UCRng.hashSeed("wave" .. session.wave .. os.time()))
				session.staged.B = UCModes.randomArmy("B", 200 + session.wave * 100, rng)
				session.budgets.B = 200 + session.wave * 100
				session.phase = "setup"
				toast(player2, string.format("Wave %d cleared! %d survivors. Budget +150 for redeploying.", session.wave, #survivors))
				broadcastState()
			end
		end)
	end

	task.delay(8, function()
		if session.phase == "results" then
			session.phase = "setup"
			broadcastState()
		end
	end)
end

local function stopBattle()
	if session.battle then
		if session.battle.connection then
			session.battle.connection:Disconnect()
		end
		session.battle = nil
	end
end

local function startBattle()
	if session.phase ~= "setup" then
		return false, "Battle already running"
	end
	if #session.staged.A == 0 or #session.staged.B == 0 then
		return false, "Both teams need at least one unit"
	end
	local config = buildConfigFromStaged()
	local core = UCSimCore.new(config)
	session.battle = { core = core, acc = 0, stateTimer = 0, snapTimer = 0, cinematicDone = false }
	session.phase = "battle"
	session.speed = 1
	session.paused = false

	session.battle.connection = RunService.Heartbeat:Connect(function(dt)
		local b = session.battle
		if not b or b.paused or b.core.outcome then
			return
		end
		b.acc = b.acc + dt * session.speed
		local stepTime = 1 / UCConfig.TICK_RATE
		while b.acc >= stepTime and not b.core.outcome do
			b.acc = b.acc - stepTime
			b.core:step(stepTime)
		end
		b.snapTimer = b.snapTimer + dt
		if b.snapTimer >= 0.05 then
			b.snapTimer = 0
			evBattle:FireAllClients(snapshotFor(b.core))
		end
		b.stateTimer = b.stateTimer + dt
		if b.stateTimer >= 1 then
			b.stateTimer = 0
			broadcastState()
		end
		local aAlive, bAlive = core:aliveOf("A"), core:aliveOf("B")
		if not b.cinematicDone and aAlive > 0 and bAlive > 0 and (aAlive <= 2 or bAlive <= 2) then
			b.cinematicDone = true
			session.speed = 0.4
			evToast:FireAllClients("Final moments - slow motion")
			task.delay(3, function()
				session.speed = 1
			end)
		end
		if core.outcome then
			evBattle:FireAllClients(snapshotFor(core))
			local connection = b.connection
			session.battle = nil
			if connection then
				connection:Disconnect()
			end
			endBattle(core:results(), core)
		end
	end)
	return true, nil
end

function Players_GetFirst()
	for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
		return p
	end
	return nil
end

-- ---------- mode switching ----------

local function applyMode(mode, missionIndex)
	stopBattle()
	session.phase = "setup"
	session.mode = mode
	session.wave = 0
	session.restrict = nil
	session.mission = nil
	session.staged = { A = {}, B = {} }
	session.budgets = { A = UCConfig.BUDGET.A, B = UCConfig.BUDGET.B }

	if mode == "campaign" then
		local index = missionIndex or 1
		local mission = UCConfig.MISSIONS[index]
		session.mission = index
		session.arenaId = mission.arena
		session.budgets = { A = mission.budgetA, B = mission.budgetB }
		session.restrict = mission.restrict
		session.staged.B = {}
		for _, e in ipairs(mission.enemy) do
			table.insert(session.staged.B, { type = e.type, x = e.x, z = e.z })
		end
		if mission.mirror then
			session.staged.B = UCModes.formation("wall", mission.enemy, "B")
		end
		buildArena(session.arenaId)
	elseif mode == "daily" then
		local daily = UCModes.daily()
		session.arenaId = daily.arena
		session.seed = daily.seed
		session.budgets = { A = daily.budgetA, B = daily.budgetB }
		session.staged.B = daily.enemy
		buildArena(session.arenaId)
	elseif mode == "survival" then
		session.budgets = { A = 400, B = 200 }
		local rng = UCRng.new(UCRng.hashSeed("survival" .. os.time()))
		session.staged.B = UCModes.randomArmy("B", 200, rng)
		buildArena("grassland")
		session.arenaId = "grassland"
	end
	broadcastState()
end

-- ---------- action handlers ----------

local function inBounds(team, x, z)
	if math.abs(z) > UCConfig.ARENA.DEPTH - 3 then
		return false
	end
	if team == "A" then
		return x < -3 and x > -UCConfig.ARENA.HALF + 3
	elseif team == "B" then
		return x > 3 and x < UCConfig.ARENA.HALF - 3
	end
	return false
end

local handlers = {}

handlers.place = function(player, args)
	if session.phase ~= "setup" then
		return toast(player, "Battle already started")
	end
	local team, unitId = args.team, args.type
	local def = UCConfig.get(unitId)
	if not def or not UCConfig.TEAMS[team] then
		return toast(player, "Unknown unit")
	end
	local profile = profileFor(player)
	if not UCProgress.isUnlocked(profile, unitId) then
		return toast(player, def.name .. " unlocks at level " .. def.unlockLevel)
	end
	if categoryBlocked(team, unitId) then
		return toast(player, def.category .. " units are restricted in this mode")
	end
	if stagedCost(team) + def.cost > session.budgets[team] then
		return toast(player, "Not enough budget")
	end
	if #session.staged[team] >= UCConfig.UNIT_LIMIT then
		return toast(player, "Unit limit reached")
	end
	if not inBounds(team, args.x, args.z) then
		return toast(player, "Place inside the team's half")
	end
	table.insert(session.staged[team], { type = unitId, upgrade = args.upgrade, x = args.x, z = args.z })
	broadcastState()
end

handlers.remove = function(player, args)
	if session.phase ~= "setup" then
		return toast(player, "Battle already started")
	end
	local team = args.team
	local best, bestDist, bestIndex = nil, 6, nil
	for i, e in ipairs(session.staged[team]) do
		local def = UCConfig.get(e.type)
		local d = math.sqrt((e.x - args.x) ^ 2 + (e.z - args.z) ^ 2)
		if def and d < bestDist then
			best, bestDist, bestIndex = e, d, i
		end
	end
	if bestIndex then
		table.remove(session.staged[team], bestIndex)
		broadcastState()
	end
end

handlers.clear = function(player)
	if session.phase ~= "setup" then
		return toast(player, "Reset is for setup phase")
	end
	session.staged = { A = {}, B = {} }
	broadcastState()
end

handlers.fillEnemy = function(player, args)
	if session.phase ~= "setup" then
		return toast(player, "Battle already started")
	end
	local rng = UCRng.new(UCRng.hashSeed("fill" .. os.time()))
	session.staged.B = UCModes.randomArmy("B", args.budget or (session.budgets.B - stagedCost("B")), rng, session.restrict)
	broadcastState()
end

handlers.randomArmyA = function(player, args)
	if session.phase ~= "setup" then
		return toast(player, "Battle already started")
	end
	local rng = UCRng.new(UCRng.hashSeed("ra" .. os.time()))
	session.staged.A = UCModes.randomArmy("A", args.budget or session.budgets.A, rng, session.restrict)
	broadcastState()
end

handlers.formation = function(player, args)
	if session.phase ~= "setup" then
		return toast(player, "Battle already started")
	end
	local team = args.team == "B" and "B" or "A"
	if #session.staged[team] == 0 then
		return toast(player, "Nothing to arrange")
	end
	session.staged[team] = UCModes.formation(args.kind, session.staged[team], team)
	broadcastState()
end

handlers.setArena = function(player, args)
	if session.phase ~= "setup" then
		return toast(player, "Battle already started")
	end
	if UCConfig.ARENAS[args.id] then
		session.arenaId = args.id
		buildArena(args.id)
		broadcastState()
	end
end

handlers.setFaction = function(player, args)
	if session.phase ~= "setup" then
		return toast(player, "Battle already started")
	end
	if UCConfig.FACTIONS[args.id] and (args.team == "A" or args.team == "B") then
		session.factions[args.team] = args.id
		broadcastState()
	end
end

handlers.setSeed = function(player, args)
	if session.phase == "setup" and type(args.seed) == "number" then
		session.seed = math.floor(args.seed) % 4294967296
		broadcastState()
	end
end

handlers.start = function(player)
	local ok, err = startBattle()
	if not ok then
		toast(player, err)
	else
		broadcastState()
	end
end

handlers.pause = function(player)
	if session.battle then
		session.paused = not session.paused
		broadcastState()
	end
end

handlers.speed = function(player, args)
	if session.battle then
		local allowed = { [0.5] = true, [1] = true, [2] = true, [4] = true }
		if allowed[args.value] then
			session.speed = args.value
			broadcastState()
		end
	end
end

handlers.setMode = function(player, args)
	if args.mode == "sandbox" or args.mode == "campaign" or args.mode == "daily" or args.mode == "survival" then
		if args.mode == "campaign" then
			local profile = profileFor(player)
			local index = args.mission or 1
			if not UCProgress.campaignUnlocked(profile, index) then
				return toast(player, "Win earlier missions first")
			end
			applyMode("campaign", index)
		else
			applyMode(args.mode)
		end
		toast(player, "Mode: " .. args.mode)
	end
end

handlers.saveSetup = function(player, args)
	if type(args.name) ~= "string" or #args.name == 0 or #args.name > 40 then
		return toast(player, "Bad name")
	end
	local profile = profileFor(player)
	UCProgress.saveSetup(player, profile, args.name, buildConfigFromStaged())
	toast(player, "Saved: " .. args.name)
end

handlers.loadSetup = function(player, args)
	local profile = profileFor(player)
	local saved = UCProgress.savedSetups(profile)[args.name]
	if saved then
		if session.phase == "setup" then
			loadStagedFromConfig(saved.config)
			broadcastState()
			toast(player, "Loaded: " .. args.name)
		else
			toast(player, "Battle already started")
		end
	end
end

handlers.deleteSetup = function(player, args)
	local profile = profileFor(player)
	UCProgress.deleteSetup(player, profile, args.name)
	toast(player, "Deleted: " .. tostring(args.name))
end

handlers.importCode = function(player, args)
	local config = UCShareCodec.decode(args.code)
	if not config then
		return toast(player, "Invalid share code")
	end
	if session.phase ~= "setup" then
		return toast(player, "Battle already started")
	end
	loadStagedFromConfig(config)
	broadcastState()
	toast(player, "Setup imported")
end

-- ---------- Battle Lab handlers ----------

handlers.labBaseline = function(player)
	if #session.staged.A == 0 or #session.staged.B == 0 then
		return toast(player, "Set up both teams first")
	end
	lab:setBaseline(buildConfigFromStaged())
	toast(player, "Baseline saved to the Lab")
end

local function labRunAll(configs, runs, label)
	task.spawn(function()
		evLab:FireAllClients({ stage = "progress", done = 0, total = #configs * runs, label = label })
		local aggregated = lab:runExperiment(configs, runs, function(done, total)
			evLab:FireAllClients({ stage = "progress", done = done, total = total, label = label })
		end)
		evLab:FireAllClients({ stage = "done", label = label, aggregated = aggregated })
	end)
end

handlers.labRun = function(player, args)
	if not lab.baseline then
		return toast(player, "Save a baseline first (LAB: BASELINE)")
	end
	local runs = math.clamp(args.runs or 10, 1, 30)
	labRunAll({ { name = "Baseline", config = lab.baseline } }, runs, "Baseline x" .. runs)
end

handlers.labSynergy = function(player)
	if not lab.baseline then
		return toast(player, "Save a baseline first (LAB: BASELINE)")
	end
	local variants = lab:synergyVariants(lab.baseline, 200)
	labRunAll(variants, 8, "Synergy Scan (8 runs each)")
end

handlers.labFormations = function(player)
	if not lab.baseline then
		return toast(player, "Save a baseline first (LAB: BASELINE)")
	end
	local variants = lab:formationVariants(lab.baseline)
	if #variants == 0 then
		return toast(player, "Baseline has no units")
	end
	labRunAll(variants, 8, "Formation Variants (8 runs each)")
end

local matrixBusy = false
handlers.labMatrix = function(player, args)
	if matrixBusy then
		return toast(player, "A matchup matrix run is already in progress")
	end
	local runs = math.clamp(args and args.runs or 4, 1, 10)
	matrixBusy = true
	task.spawn(function()
		evLab:FireAllClients({ stage = "matrixProgress", done = 0, total = 0, runs = runs })
		local matrix = lab:matchupMatrix(runs, function(done, total)
			evLab:FireAllClients({ stage = "matrixProgress", done = done, total = total, runs = runs })
		end)
		matrixBusy = false
		evLab:FireAllClients({ stage = "matrixDone", runs = matrix.runs, results = matrix.results, scores = UCLab.matrixScores(matrix) })
	end)
end

handlers.labHistory = function(player, args)
	if args.op == "save" then
		if not args.name then
			return toast(player, "Name required")
		end
		lab:saveExperiment(args.name, args.note, args.results or {})
		toast(player, "Experiment saved: " .. args.name)
		evLab:FireAllClients({ stage = "history", history = lab:loadHistory() })
	else
		evLab:FireAllClients({ stage = "history", history = lab:loadHistory() })
	end
end

evState.OnServerEvent:Connect(function(player)
	broadcastState()
end)

evAction.OnServerEvent:Connect(function(player, cmd, args)
	if type(cmd) ~= "string" then
		return
	end
	local handler = handlers[cmd]
	if handler then
		local ok, err = pcall(handler, player, args or {})
		if not ok then
			warn("[UNIT CLASH] action failed: " .. cmd .. " - " .. tostring(err))
			toast(player, "Something went wrong - check server output")
		end
	end
end)

game:GetService("Players").PlayerAdded:Connect(function(player)
	profileFor(player)
	broadcastState()
end)

broadcastState()
print("[UNIT CLASH] server ready - 15 units, upgrades, factions, 6 arenas, 4 modes, Battle Lab")
