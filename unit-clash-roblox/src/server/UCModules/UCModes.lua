-- UNIT CLASH - mode definitions and army/formation generators.
-- Campaign missions, daily challenge seeding, survival waves, random armies,
-- formation layouts. Pure data in / pure data out.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UCConfig = require(ReplicatedStorage:WaitForChild("UCShared"):WaitForChild("UCConfig"))
local UCRng = require(script.Parent:WaitForChild("UCRng"))

local UCModes = {}

local function side(team)
	return team == "A" and -1 or 1
end

function UCModes.randomArmy(team, budget, rng, restrict)
	local out = {}
	local remaining = budget
	local ids = UCConfig.ORDER
	local guard = 0
	while remaining >= 45 and guard < 200 do
		guard = guard + 1
		local id = ids[rng:int(1, #ids)]
		local def = UCConfig.get(id)
		local blocked = restrict and restrict.categories and restrict.categories[def.category] or false
		if not blocked and def.cost <= remaining then
			table.insert(out, {
				type = id,
				x = side(team) * rng:range(20, 88),
				z = rng:range(-22, 22),
			})
			remaining = remaining - def.cost
		end
	end
	return out
end

-- Rearranges a team's placed units into a named formation.
function UCModes.formation(kind, entries, team)
	local out = {}
	local s = side(team)
	local n = #entries
	if n == 0 then
		return out
	end
	if kind == "line" then
		for i, e in ipairs(entries) do
			table.insert(out, { type = e.type, upgrade = e.upgrade, x = s * 60, z = -24 + (i - 1) * (48 / math.max(1, n - 1)) })
		end
	elseif kind == "wall" then
		for i, e in ipairs(entries) do
			local row = math.floor((i - 1) / 8)
			local col = (i - 1) % 8
			table.insert(out, { type = e.type, upgrade = e.upgrade, x = s * (70 - row * 10), z = -21 + col * 6 })
		end
	elseif kind == "wedge" then
		for i, e in ipairs(entries) do
			local row = math.floor((i - 1) / 4)
			local col = (i - 1) % 4
			table.insert(out, { type = e.type, upgrade = e.upgrade, x = s * (40 + row * 12), z = -12 + col * 8 + row * 4 })
		end
	elseif kind == "spread" then
		local rng = UCRng.new(7)
		for _, e in ipairs(entries) do
			table.insert(out, { type = e.type, upgrade = e.upgrade, x = s * rng:range(15, 88), z = rng:range(-26, 26) })
		end
	else
		for _, e in ipairs(entries) do
			table.insert(out, { type = e.type, upgrade = e.upgrade, x = e.x, z = e.z })
		end
	end
	return out
end

UCConfig.MISSIONS = {
	{
		name = "First Steps", blurb = "Beat a small raiding party. Learn placement.",
		arena = "grassland", budgetA = 300, budgetB = 0,
		enemy = { { type = "scout", x = 70, z = -8 }, { type = "scout", x = 70, z = 8 }, { type = "brawler", x = 80, z = 0 } },
	},
	{
		name = "Hold the Line", blurb = "Ranged and Support only, against an armored wall.",
		arena = "grassland", budgetA = 400, budgetB = 0, restrict = { categories = { Frontline = true, Heavy = true, Agile = true, Commander = true, Experimental = true, Specialist = true } },
		enemy = { { type = "juggernaut", x = 70, z = -6 }, { type = "juggernaut", x = 70, z = 6 }, { type = "guardian", x = 85, z = 0 }, { type = "guardian", x = 85, z = -12 }, { type = "guardian", x = 85, z = 12 }, { type = "medic", x = 92, z = 0 } },
	},
	{
		name = "The Underdog", blurb = "250 budget against double your value.",
		arena = "desert", budgetA = 250, budgetB = 0,
		enemy = { { type = "brawler", x = 60, z = -10 }, { type = "brawler", x = 60, z = 10 }, { type = "sparkcaster", x = 75, z = -6 }, { type = "sparkcaster", x = 75, z = 6 }, { type = "medic", x = 88, z = 0 }, { type = "guardian", x = 50, z = 0 }, { type = "longshot", x = 90, z = -14 }, { type = "longshot", x = 90, z = 14 } },
	},
	{
		name = "Titan Slayer", blurb = "Bring down the Colossus without a wall of your own.",
		arena = "industrial", budgetA = 350, budgetB = 0,
		enemy = { { type = "colossus", x = 65, z = 0 }, { type = "medic", x = 85, z = 0 }, { type = "guardian", x = 75, z = -8 }, { type = "guardian", x = 75, z = 8 } },
	},
	{
		name = "Equal Ground", blurb = "Mirror match. Formation and upgrades decide it.",
		arena = "frozen", budgetA = 500, budgetB = 0, mirror = true,
		enemy = { { type = "brawler", x = 60, z = -8 }, { type = "brawler", x = 60, z = 8 }, { type = "guardian", x = 72, z = -4 }, { type = "guardian", x = 72, z = 4 }, { type = "sparkcaster", x = 84, z = 0 }, { type = "medic", x = 92, z = 0 } },
	},
}

function UCModes.dailySeed()
	local t = os.date("*t")
	return UCRng.hashSeed(string.format("UC-DAILY-%04d-%02d-%02d", t.year, t.month, t.day))
end

function UCModes.daily()
	local seed = UCModes.dailySeed()
	local rng = UCRng.new(seed)
	local arenaIds = { "grassland", "desert", "industrial", "frozen", "rooftop", "training" }
	local arena = arenaIds[rng:int(1, #arenaIds)]
	local enemyBudget = 380 + (seed % 140)
	local enemy = UCModes.randomArmy("B", enemyBudget, rng)
	return {
		name = "Challenge of the Day",
		blurb = string.format("Seeded challenge - %d enemy value. Same for everyone today.", enemyBudget),
		arena = arena, budgetA = 400, seed = seed, enemy = enemy,
	}
end

return UCModes
