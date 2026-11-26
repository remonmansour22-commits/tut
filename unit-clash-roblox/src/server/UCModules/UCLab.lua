-- UNIT CLASH - Battle Lab. Headless multi-run experiments, auto-variants,
-- synergy scan, formation variants, evidence-only insights, experiment history.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UCConfig = require(ReplicatedStorage:WaitForChild("UCShared"):WaitForChild("UCConfig"))
local UCRng = require(script.Parent:WaitForChild("UCRng"))
local UCSimCore = require(script.Parent:WaitForChild("UCSimCore"))

local UCLab = {}
UCLab.__index = UCLab

local TICK = 1 / 30
local HISTORY_KEY = "UC_LAB_HISTORY"
local MAX_HISTORY = 25

function UCLab.new()
	local self = setmetatable({}, UCLab)
	self.baseline = nil
	self.history = {}
	self.loadStore = nil
	pcall(function()
		self.loadStore = game:GetService("DataStoreService"):GetDataStore(HISTORY_KEY)
	end)
	return self
end

function UCLab:setBaseline(config)
	self.baseline = config
	return { ok = true, units = #config.teams.A }
end

local function variantOf(base, teamAUnits, name)
	return {
		name = name,
		config = {
			arena = base.arena, seed = base.seed, timeLimit = base.timeLimit,
			factions = base.factions and table.clone(base.factions) or nil,
			budgets = base.budgets,
			teams = { A = teamAUnits, B = table.clone(base.teams.B) },
		},
	}
end

function UCLab:synergyVariants(base, addedBudget)
	local variants = {}
	local cx, cz, n = 0, 0, 0
	for _, u in ipairs(base.teams.A) do
		cx, cz, n = cx + u.x, cz + u.z, n + 1
	end
	if n == 0 then
		cx, cz = -60, 0
	else
		cx, cz = cx / n, cz / n
	end
	local seen = {}
	for _, unitId in ipairs(UCConfig.ORDER) do
		local def = UCConfig.get(unitId)
		local copies = math.clamp(math.floor(addedBudget / def.cost), 1, 6)
		local name = string.format("+%d %s (+%d)", copies, def.name, def.cost * copies)
		if not seen[name] then
			seen[name] = true
			local units = table.clone(base.teams.A)
			local rng2 = UCRng.new(UCRng.hashSeed(unitId))
			for _ = 1, copies do
				table.insert(units, {
					type = unitId,
					x = math.clamp(cx + rng2:range(-10, 10), -95, -20),
					z = math.clamp(cz + rng2:range(-12, 12), -26, 26),
				})
			end
			table.insert(variants, variantOf(base, units, name))
		end
	end
	return variants
end

function UCLab:formationVariants(base)
	local UCModes = require(script.Parent:WaitForChild("UCModes"))
	local variants = {}
	local kinds = {
		{ id = "line", label = "Defensive Line" },
		{ id = "wall", label = "Wall" },
		{ id = "spread", label = "Scattered" },
	}
	for _, k in ipairs(kinds) do
		local rearranged = UCModes.formation(k.id, base.teams.A, "A")
		if #rearranged > 0 then
			table.insert(variants, variantOf(base, rearranged, k.label))
		end
	end
	return variants
end

-- Lazy runner: call :chunk(budgetSeconds) repeatedly until it returns true.
function UCLab.runner(config, seed)
	local core = UCSimCore.new(config)
	core.rng = UCRng.new(seed)
	local done = false
	return {
		core = core,
		chunk = function(_, maxSeconds)
			if done then
				return true
			end
			local deadline = os.clock() + (maxSeconds or 0.03)
			while not core.outcome and os.clock() < deadline do
				for _ = 1, 15 do
					if core.outcome then
						break
					end
					core:step(TICK)
				end
			end
			if core.outcome then
				done = true
			end
			return done
		end,
	}
end

-- Full experiment: N seeded runs per config, yielded between 30 ms chunks.
function UCLab:runExperiment(configs, runs, onProgress)
	local total = #configs * runs
	local finished = 0
	local aggregated = {}
	for _, item in ipairs(configs) do
		local agg = { name = item.name, runs = 0, winsA = 0, winsB = 0, draws = 0,
			duration = 0, survA = 0, survB = 0, dmgA = 0, dmgB = 0, healA = 0, healB = 0 }
		for i = 1, runs do
			local seed = UCRng.deterministicSeed(item.config.seed or 1000, i)
			local r = UCLab.runner(item.config, seed)
			while not r:chunk(0.03) do
				task.wait()
			end
			local res = r.core:results()
			agg.runs = agg.runs + 1
			if res.winner == "A" then
				agg.winsA = agg.winsA + 1
			elseif res.winner == "B" then
				agg.winsB = agg.winsB + 1
			else
				agg.draws = agg.draws + 1
			end
			agg.duration = agg.duration + res.duration
			agg.survA = agg.survA + res.A.survivors
			agg.survB = agg.survB + res.B.survivors
			agg.dmgA = agg.dmgA + res.A.damage
			agg.dmgB = agg.dmgB + res.B.damage
			agg.healA = agg.healA + res.A.healing
			agg.healB = agg.healB + res.B.healing
			finished = finished + 1
			if onProgress and finished % 2 == 0 then
				onProgress(finished, total)
			end
		end
		local n = math.max(1, agg.runs)
		agg.avgDuration = math.floor(agg.duration / n)
		agg.avgSurvA = math.floor(agg.survA / n * 10) / 10
		agg.avgSurvB = math.floor(agg.survB / n * 10) / 10
		agg.avgDmgA = math.floor(agg.dmgA / n)
		agg.avgDmgB = math.floor(agg.dmgB / n)
		agg.avgHealA = math.floor(agg.healA / n)
		agg.avgHealB = math.floor(agg.healB / n)
		agg.winRate = math.floor(agg.winsA / n * 100)
		table.insert(aggregated, agg)
	end
	return aggregated
end

-- Evidence-only insights, generated strictly from the result table.
function UCLab:insights(res)
	local out = {}
	if res.winner ~= "draw" then
		local win = res.winner
		local lose = win == "A" and "B" or "A"
		local w, l = res[win], res[lose]
		table.insert(out, string.format("%s won by %s after %ds.",
			UCConfig.TEAMS[win].name, res.reason == "timeout" and "remaining value" or "annihilation", res.duration))
		if w.healing > l.healing * 1.5 and w.healing > 150 then
			table.insert(out, string.format("Healing decided this: %d vs %d. Burst-focus counters to sustain would test well.", w.healing, l.healing))
		end
		if l.damage > w.damage then
			table.insert(out, string.format("%s dealt MORE total damage (%d vs %d) and still lost - its damage was traded unevenly.",
				UCConfig.TEAMS[lose].name, l.damage, w.damage))
		end
		if w.abilities <= 1 then
			table.insert(out, "The winner barely used abilities - raw stats carried it.")
		end
	else
		table.insert(out, string.format("Draw after %ds - even remaining value at the limit.", res.duration))
	end
	return out
end

-- ---------- matchup matrix ----------
-- Headless 1v1 round-robin: every unit vs every unit, seeded and reproducible.
-- Yields between runs (call from task.spawn); onProgress(done, total, runs).
function UCLab:matchupMatrix(runsPerPair, onProgress)
	local runs = math.clamp(runsPerPair or 4, 1, 10)
	local ids = UCConfig.ORDER
	local pairsList = {}
	for i = 1, #ids do
		for j = i + 1, #ids do
			table.insert(pairsList, { ids[i], ids[j] })
		end
	end
	local results = {}
	for pi, pair in ipairs(pairsList) do
		local a, b = pair[1], pair[2]
		local winsA, winsB, draws = 0, 0, 0
		for i = 1, runs do
			local laneZ = ((i - 1) % 3 - 1) * 14
			local config = {
				arena = "training", timeLimit = 40, seed = 1000,
				teams = {
					A = { { type = a, x = -55, z = laneZ } },
					B = { { type = b, x = 55, z = laneZ } },
				},
			}
			local seed = UCRng.hashSeed(a .. "|" .. b) + i * 7919
			local r = UCLab.runner(config, seed)
			while not r:chunk(0.03) do
				task.wait()
			end
			local w = r.core.outcome and r.core.outcome.winner
			if w == "A" then
				winsA = winsA + 1
			elseif w == "B" then
				winsB = winsB + 1
			else
				draws = draws + 1
			end
		end
		table.insert(results, { a = a, b = b, winsA = winsA, winsB = winsB, draws = draws })
		if onProgress then
			onProgress(pi, #pairsList, runs)
		end
	end
	return { runs = runs, results = results }
end

-- Overall 1v1 ranking from a finished matrix (0..100 avg win rate).
function UCLab.matrixScores(matrix)
	local tally, duels = {}, {}
	for _, e in ipairs(matrix.results) do
		local n = e.winsA + e.winsB + e.draws
		if n > 0 then
			tally[e.a] = (tally[e.a] or 0) + (e.winsA + e.draws * 0.5) / n
			tally[e.b] = (tally[e.b] or 0) + (e.winsB + e.draws * 0.5) / n
			duels[e.a] = (duels[e.a] or 0) + 1
			duels[e.b] = (duels[e.b] or 0) + 1
		end
	end
	local scores = {}
	for id, sum in pairs(tally) do
		table.insert(scores, { id = id, name = UCConfig.get(id).name, score = math.floor(sum / duels[id] * 100) })
	end
	table.sort(scores, function(x, y) return x.score > y.score end)
	return scores
end

-- ---------- history ----------

function UCLab:saveExperiment(name, note, aggregated)
	local entry = {
		name = name, note = note or "", at = os.time(),
		results = aggregated,
		kind = (#aggregated > 1) and "comparison" or "single",
	}
	table.insert(self.history, 1, entry)
	while #self.history > MAX_HISTORY do
		table.remove(self.history)
	end
	if self.loadStore then
		pcall(function()
			self.loadStore:SetAsync(HISTORY_KEY, self.history)
		end)
	end
	return entry
end

function UCLab:loadHistory()
	if #self.history == 0 and self.loadStore then
		pcall(function()
			local saved = self.loadStore:GetAsync(HISTORY_KEY)
			if saved then
				self.history = saved
			end
		end)
	end
	return self.history
end

return UCLab
