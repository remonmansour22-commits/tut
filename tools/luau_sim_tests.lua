-- UNIT CLASH — headless simulation tests, executed by the real Luau VM.
-- Run via tools/run_luau_sim_tests.sh (shims Roblox services; sources stay unmodified).
local sh = require("./uc_shim")
local UCConfig = sh.get("UCConfig")
local UCSimCore = sh.get("UCSimCore")
local UCModes = sh.get("UCModes")
local UCLab = sh.get("UCLab")
local UCRng = sh.get("UCRng")

local passed, failures = 0, {}
local function check(name, cond, extra)
	if cond then
		passed = passed + 1
	else
		failures[#failures + 1] = name
		print(("FAIL: %s %s"):format(name, extra or ""))
	end
end

local function deepEq(a, b)
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	local seen = {}
	for k, v in pairs(a) do
		seen[k] = true
		if not deepEq(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if not seen[k] then
			return false
		end
	end
	return true
end

local function fullArmy(team)
	local list = {}
	local n = #UCConfig.ORDER
	for i, id in ipairs(UCConfig.ORDER) do
		list[i] = { type = id, x = team == "A" and -70 or 70, z = (i - (n + 1) / 2) * 3.5 }
	end
	return list
end

local function makeBattle(seed, arena, extra)
	local cfg = {
		arena = arena or "grassland",
		seed = seed,
		timeLimit = 120,
		teams = { A = fullArmy("A"), B = fullArmy("B") },
	}
	if extra then
		for k, v in pairs(extra) do
			cfg[k] = v
		end
	end
	return UCSimCore.new(cfg)
end

-- 1. Roster integrity
check("roster has at least 12 units", #UCConfig.ORDER >= 12, "count=" .. #UCConfig.ORDER)
for _, id in ipairs(UCConfig.ORDER) do
	local d = UCConfig.UNITS[id]
	check("unit " .. id .. " is defined", d ~= nil)
	if d then
		check(
			"unit " .. id .. " has full stat block",
			d.name ~= nil and d.category ~= nil and d.cost ~= nil and d.hp ~= nil and d.speed ~= nil
				and d.range ~= nil and d.damage ~= nil and d.cooldown ~= nil and d.brain ~= nil and d.radius ~= nil
		)
	end
end
for upId, up in pairs(UCConfig.UPGRADES) do
	check("upgrade " .. upId .. " targets a real unit", UCConfig.UNITS[up.unit] ~= nil)
	check("upgrade " .. upId .. " has apply or flag", type(up.apply) == "function" or type(up.flag) == "string")
end
for fid, f in pairs(UCConfig.FACTIONS) do
	check("faction " .. fid .. " has apply function", type(f.apply) == "function")
end
for arenaId, arena in pairs(UCConfig.ARENAS) do
	check("arena " .. arenaId .. " has modifiers table", type(arena.modifiers) == "table")
end

-- 2. Full battle resolves with real combat activity
local core = makeBattle(7)
local result = core:runToEnd()
check("battle reaches an outcome", core.outcome ~= nil)
check(
	"winner is valid",
	core.outcome.winner == "A" or core.outcome.winner == "B" or core.outcome.winner == "draw",
	tostring(core.outcome.winner)
)
check("battle duration is positive", core.outcome.duration > 0)
local evs = core:drainEvents()
check("battle emitted events", #evs > 0, "n=" .. #evs)
local sawCombat = false
for _, e in ipairs(evs) do
	if e.type == "hit" or e.type == "shoot" or e.type == "death" then
		sawCombat = true
	end
end
check("combat events present (hit/shoot/death)", sawCombat)
check("damage was dealt", (result.A.damage + result.B.damage) > 0)
check("timeline was recorded", #core.timeline > 0)

-- 3. Determinism
local r1 = makeBattle(123):runToEnd()
local r2 = makeBattle(123):runToEnd()
check("same seed reproduces identical results", deepEq(r1, r2))
local r3 = makeBattle(124):runToEnd()
check("different seed runs cleanly", r3 ~= nil and r3.winner ~= nil)

-- 4. Every unit fights (1v1 mirror across 3 seeds)
for _, id in ipairs(UCConfig.ORDER) do
	local d = UCConfig.UNITS[id]
	local anyResolve, anyActivity = false, false
	for _, seed in ipairs({ 1, 2, 3 }) do
		local c = UCSimCore.new({
			seed = seed,
			timeLimit = 60,
			teams = {
				A = { { type = id, x = -30, z = 0 } },
				B = { { type = id, x = 30, z = 0 } },
			},
		})
		local res = c:runToEnd()
		if c.outcome then
			anyResolve = true
		end
		if res.A.damage + res.B.damage > 0 then
			anyActivity = true
		end
	end
	check("1v1 " .. id .. " resolves", anyResolve)
	if d.damage > 0 then
		check("1v1 " .. id .. " shows combat activity", anyActivity)
	end
end

-- 4b. Regression: sparkcaster basic attacks must deal sustained damage, not
-- only fire when its Chain Spark ability is off cooldown (was a real bug).
local sparkDmg = 0
for _, seed in ipairs({ 1, 2, 3 }) do
	local c = UCSimCore.new({
		seed = seed,
		timeLimit = 45,
		teams = {
			A = { { type = "sparkcaster", x = -25, z = 0 } },
			B = { { type = "sparkcaster", x = 25, z = 0 } },
		},
	})
	local res = c:runToEnd()
	sparkDmg = sparkDmg + res.A.damage + res.B.damage
end
check("sparkcaster sustained dps (bounce regression)", sparkDmg > 250, "total=" .. sparkDmg)

-- 5. Survivors stay inside field bounds
local half, depth = UCConfig.ARENA.HALF, UCConfig.ARENA.DEPTH
local inBounds = true
for _, u in ipairs(core.units) do
	if u.alive and (math.abs(u.x) > half + 1 or math.abs(u.z) > depth + 1) then
		inBounds = false
	end
end
check("survivors stay in field bounds", inBounds)

-- 6. Time limit enforced
local short = UCSimCore.new({
	seed = 9,
	timeLimit = 0.5,
	teams = {
		A = { { type = "guardian", x = -50, z = 0 } },
		B = { { type = "guardian", x = 50, z = 0 } },
	},
})
short:runToEnd()
check("time limit enforced (timeout)", short.outcome.reason == "timeout", tostring(short.outcome.reason))

-- 7. Upgrades + factions run cleanly
local upCore = makeBattle(11, "frozen", {
	factions = { A = "prism", B = "scrapworks" },
	teams = {
		A = {
			{ type = "sparkcaster", upgrade = "spark_conductor", x = -60, z = 0 },
			{ type = "guardian", upgrade = "guardian_bulwark1", x = -55, z = 6 },
		},
		B = {
			{ type = "brawler", upgrade = "brawler_iron", x = 60, z = 0 },
			{ type = "scout", upgrade = "scout_ghost", x = 55, z = -6 },
		},
	},
})
upCore:runToEnd()
check("upgraded + faction battle resolves", upCore.outcome ~= nil)

-- 8. Every arena resolves and respects obstacles
for arenaId in pairs(UCConfig.ARENAS) do
	local c = makeBattle(5, arenaId)
	local res = c:runToEnd()
	check("arena " .. arenaId .. " battle resolves", c.outcome ~= nil)
	check("arena " .. arenaId .. " does not stall (no cap)", c.outcome.reason ~= "cap", tostring(c.outcome.reason))
	local clearOfObstacles = true
	for _, u in ipairs(c.units) do
		if u.alive then
			for _, o in ipairs(c.obstacles or {}) do
				if (u.x - o.x) ^ 2 + (u.z - o.z) ^ 2 < (o.r - 0.5) ^ 2 then
					clearOfObstacles = false
				end
			end
		end
	end
	check("arena " .. arenaId .. " survivors clear of obstacles", clearOfObstacles)
end

-- 8b. Shop catalog integrity (cosmetics only)
for key, item in pairs(UCConfig.SHOP) do
	check("shop item " .. key .. " has name and blurb", item.name ~= nil and item.blurb ~= nil)
	check("shop item " .. key .. " has gamepassId", type(item.gamepassId) == "number")
	if item.palette then
		check("shop item " .. key .. " palette complete", item.palette.body ~= nil and item.palette.glyph ~= nil)
	end
end

-- 9. Mode helpers
local rng = UCRng.new(7)
local army = UCModes.randomArmy("A", 500, rng, nil)
check("randomArmy generates an army within budget", army and #army > 0, "n=" .. #(army or {}))
local formed = UCModes.formation("wall", army, "A")
check("formation tool returns placements", formed and #formed == #army)
check("formation respects field bounds", (function()
	for _, e in ipairs(formed) do
		if math.abs(e.x) > UCConfig.ARENA.HALF or math.abs(e.z) > UCConfig.ARENA.DEPTH then
			return false
		end
	end
	return true
end)())

-- 10. Battle Lab engine: variants, multi-run experiments, insights, matrix
local lab = UCLab.new()
local base = {
	name = "baseline",
	arena = "grassland",
	seed = 42,
	timeLimit = 60,
	teams = {
		A = {
			{ type = "guardian", x = -40, z = 0 },
			{ type = "longshot", x = -55, z = 5 },
		},
		B = {
			{ type = "brawler", x = 40, z = 0 },
			{ type = "scout", x = 55, z = -5 },
		},
	},
}
lab:setBaseline(base)
local variants = lab:synergyVariants(base, 200)
check("synergy variants generated", variants and #variants >= 1, "n=" .. #(variants or {}))
local aggs = lab:runExperiment({ { name = "baseline", config = base }, variants[1] }, 2)
check("runExperiment aggregates both configs", aggs and #aggs == 2)
check("aggregates computed win rates", aggs and aggs[1].runs == 2 and aggs[1].winRate ~= nil)
local single = UCSimCore.new(base):runToEnd()
local ins = lab:insights(single)
check("insights generated from real result", type(ins) == "table")
local matrix = lab:matchupMatrix(1)
check("matchup matrix runs", matrix and matrix.results and #matrix.results > 0)
local scores = UCLab.matrixScores(matrix)
check("matrix scores computed", scores and #scores > 0)

-- 11. Save/load experiment history (in-memory; DataStore pcall-safe)
lab:saveExperiment("headless test", "written by luau VM tests", aggs)
check("experiment history persists in memory", #lab:loadHistory() >= 1)

print(("\n%d checks passed, %d failed"):format(passed, #failures))
if #failures > 0 then
	os.exit(1)
end
