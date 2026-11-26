-- UNIT CLASH - shared configuration: roster, upgrades, factions, arenas,
-- progression thresholds, budgets. Sim, AI, UI, Lab and visuals all read this.

local UCConfig = {}

UCConfig.NAME = "UNIT CLASH"
UCConfig.TICK_RATE = 20
UCConfig.BATTLE_TIME_LIMIT = 180
UCConfig.BUDGET = { A = 500, B = 500 }
UCConfig.UNIT_LIMIT = 40

UCConfig.ARENA = { HALF = 100, DEPTH = 30, BASE_Y = 0, UNIT_Y = 3 }

UCConfig.TEAMS = {
	A = { name = "AZURE", color = Color3.fromRGB(60, 140, 255) },
	B = { name = "CRIMSON", color = Color3.fromRGB(255, 80, 80) },
}

-- Sound IDs are intentionally empty: paste your own rbxassetid numbers in
-- Studio. Empty entries are skipped, the game stays silent by default.
UCConfig.SFX = {
	hit = "", death = "", shoot = "", heal = "", ability = "", victory = "",
}

UCConfig.UNITS = {
	scout = {
		name = "Scout", category = "Agile", cost = 45, hp = 55, speed = 26, radius = 1,
		range = 6, damage = 8, cooldown = 0.5, brain = "skirmisher", unlockLevel = 1,
		color = Color3.fromRGB(120, 220, 120),
		desc = "Fast hit-and-run harasser.",
	},
	brawler = {
		name = "Brawler", category = "Frontline", cost = 90, hp = 140, speed = 16, radius = 1.3,
		range = 6, damage = 16, cooldown = 0.9, brain = "brawler", unlockLevel = 1,
		color = Color3.fromRGB(230, 160, 60),
		desc = "Close-range bruiser. Charges the nearest enemy.",
	},
	guardian = {
		name = "Guardian", category = "Frontline", cost = 80, hp = 170, speed = 12, radius = 1.4,
		range = 5, damage = 8, cooldown = 1.1, brain = "guardian", armor = 0.15, unlockLevel = 1,
		aura = { kind = "protect", radius = 18, reduction = 0.25 },
		color = Color3.fromRGB(90, 170, 220),
		desc = "Wall. Nearby allies take 25% less damage.",
	},
	medic = {
		name = "Medic", category = "Support", cost = 100, hp = 80, speed = 14, radius = 1.1,
		range = 24, damage = 0, cooldown = 2, brain = "healer", unlockLevel = 1,
		ability = { name = "Heal Beam", cooldown = 2, kind = "heal", amount = 26 },
		color = Color3.fromRGB(120, 240, 180),
		desc = "Heals the most wounded nearby ally.",
	},
	juggernaut = {
		name = "Juggernaut", category = "Heavy", cost = 150, hp = 340, speed = 9, radius = 1.8,
		range = 7, damage = 24, cooldown = 1.4, brain = "brawler", armor = 0.15, unlockLevel = 2,
		color = Color3.fromRGB(150, 150, 160),
		desc = "Slow armored wall of muscle.",
	},
	sparkcaster = {
		name = "Spark Caster", category = "Ranged", cost = 110, hp = 90, speed = 13, radius = 1.1,
		range = 26, damage = 13, cooldown = 1.4, brain = "ranged", unlockLevel = 1,
		projectile = { speed = 80, color = Color3.fromRGB(120, 200, 255) },
		ability = { name = "Chain Spark", cooldown = 5, kind = "bounce", jumps = 2, falloff = 0.6 },
		color = Color3.fromRGB(120, 200, 255),
		desc = "Bolts that chain to nearby enemies.",
	},
	longshot = {
		name = "Longshot", category = "Ranged", cost = 120, hp = 60, speed = 12, radius = 1.1,
		range = 48, damage = 30, cooldown = 2.6, brain = "ranged", unlockLevel = 1,
		projectile = { speed = 90, color = Color3.fromRGB(255, 240, 120) },
		color = Color3.fromRGB(255, 240, 120),
		desc = "Extreme-range sniper, fragile up close.",
	},
	engineer = {
		name = "Engineer", category = "Specialist", cost = 115, hp = 85, speed = 13, radius = 1.1,
		range = 10, damage = 6, cooldown = 1.5, brain = "engineer", unlockLevel = 1,
		ability = { name = "Deploy Turret", cooldown = 12, kind = "deploy_turret", hp = 60, damage = 8, range = 24, cooldown2 = 0.8, lifetime = 20 },
		projectile = { speed = 50, color = Color3.fromRGB(200, 200, 120) },
		color = Color3.fromRGB(200, 170, 90),
		desc = "Deploys an auto-turret for 20 seconds.",
	},
	disruptor = {
		name = "Disruptor", category = "Specialist", cost = 105, hp = 90, speed = 16, radius = 1.1,
		range = 20, damage = 10, cooldown = 1.2, brain = "disruptor", unlockLevel = 1,
		projectile = { speed = 60, color = Color3.fromRGB(200, 120, 255) },
		ability = { name = "Static Field", cooldown = 9, kind = "slow_aoe", radius = 20, factor = 0.5, duration = 3 },
		color = Color3.fromRGB(200, 120, 255),
		desc = "Pulses a field that slows enemies.",
	},
	commander = {
		name = "Commander", category = "Commander", cost = 130, hp = 120, speed = 12, radius = 1.3,
		range = 8, damage = 10, cooldown = 1.0, brain = "commander", unlockLevel = 1,
		aura = { kind = "might", radius = 30, bonus = 0.2 },
		color = Color3.fromRGB(255, 210, 90),
		desc = "Allies within 30 studs deal 20% more damage.",
	},
	trickster = {
		name = "Trickster", category = "Agile", cost = 95, hp = 70, speed = 22, radius = 1.0,
		range = 6, damage = 9, cooldown = 0.7, brain = "trickster", unlockLevel = 1,
		ability = { name = "Blink Step", cooldown = 6, kind = "dash", distance = 30 },
		color = Color3.fromRGB(240, 130, 200),
		desc = "Blinks behind enemies when pressured.",
	},
	artificer = {
		name = "Artificer", category = "Support", cost = 110, hp = 80, speed = 12, radius = 1.1,
		range = 22, damage = 0, cooldown = 4, brain = "artificer", unlockLevel = 1,
		ability = { name = "Mend Pad", cooldown = 10, kind = "deploy_pad", heal = 10, radius = 14, lifetime = 16 },
		color = Color3.fromRGB(170, 220, 140),
		desc = "Places a pad that heals allies on it.",
	},
	colossus = {
		name = "Colossus", category = "Experimental", cost = 340, hp = 800, speed = 6, radius = 3,
		range = 12, damage = 36, cooldown = 2, brain = "titan", armor = 0.25, unlockLevel = 2,
		ability = { name = "Seismic Slam", cooldown = 8, kind = "slam_aoe", radius = 20, damage = 22, knockback = 24 },
		color = Color3.fromRGB(110, 100, 130),
		desc = "Siege engine with a damaging ground slam.",
	},
	phoenix = {
		name = "Phoenix", category = "Experimental", cost = 160, hp = 115, speed = 18, radius = 1.2,
		range = 28, damage = 13, cooldown = 1.1, brain = "caster", unlockLevel = 2,
		projectile = { speed = 55, color = Color3.fromRGB(255, 150, 60) },
		rebirth = { hpFrac = 0.35, novaDamage = 20, novaRadius = 20 },
		color = Color3.fromRGB(255, 150, 60),
		desc = "Dies once, returns in flame with a nova.",
	},
	reaper = {
		name = "Reaper", category = "Specialist", cost = 150, hp = 165, speed = 21, radius = 1.2,
		range = 5, damage = 16, cooldown = 0.7, brain = "skirmisher", armor = 0.05,
		lifesteal = 0.6, unlockLevel = 3,
		color = Color3.fromRGB(90, 60, 110),
		desc = "Drain-tank, heals 60% of damage dealt.",
	},
}

UCConfig.ORDER = { "scout", "brawler", "guardian", "medic", "sparkcaster", "longshot",
	"engineer", "disruptor", "commander", "trickster", "artificer", "juggernaut",
	"colossus", "phoenix", "reaper" }

-- 30 upgrades, two per unit. apply(d) mutates the unit's def copy at spawn;
-- flag entries (no apply) are behavior hooks checked via unit:hasUpgrade.
UCConfig.UPGRADES = {
	scout_ghost = { unit = "scout", name = "Ghost Step", desc = "+15% speed", apply = function(d) d.speed = d.speed * 1.15 end },
	scout_trail = { unit = "scout", name = "Trail Runner", desc = "Longer reach, faster strikes", apply = function(d) d.range = d.range + 4; d.cooldown = d.cooldown * 0.85 end },
	brawler_iron = { unit = "brawler", name = "Iron Fists", desc = "+20% damage", apply = function(d) d.damage = d.damage * 1.2 end },
	brawler_hulk = { unit = "brawler", name = "Hulk Out", desc = "+25% HP, -10% speed", apply = function(d) d.hp = d.hp * 1.25; d.speed = d.speed * 0.9 end },
	guardian_bulwark1 = { unit = "guardian", name = "Bulwark", desc = "+0.10 armor", apply = function(d) d.armor = (d.armor or 0) + 0.10 end },
	guardian_bulwark2 = { unit = "guardian", name = "Great Wall", desc = "+25% HP, -10% speed", apply = function(d) d.hp = d.hp * 1.25; d.speed = d.speed * 0.9 end },
	medic_triage = { unit = "medic", name = "Field Triage", desc = "Heals 25% faster", apply = function(d) d.ability.cooldown = d.ability.cooldown * 0.75 end },
	medic_combat = { unit = "medic", name = "Combat Medic", desc = "+30% HP, +0.05 armor", apply = function(d) d.hp = d.hp * 1.3; d.armor = (d.armor or 0) + 0.05 end },
	juggernaut_plating = { unit = "juggernaut", name = "Reactive Plating", desc = "+0.08 armor", apply = function(d) d.armor = (d.armor or 0) + 0.08 end },
	juggernaut_engine = { unit = "juggernaut", name = "Overdrive Engine", desc = "+20% speed", apply = function(d) d.speed = d.speed * 1.2 end },
	spark_conductor = { unit = "sparkcaster", name = "Conductor", desc = "Chain hits one more enemy", apply = function(d) d.ability.jumps = d.ability.jumps + 1 end },
	spark_overclock = { unit = "sparkcaster", name = "Overclock", desc = "+20% damage, slightly slower", apply = function(d) d.damage = d.damage * 1.2; d.cooldown = d.cooldown * 1.1 end },
	longshot_deadeye = { unit = "longshot", name = "Deadeye", desc = "+25% damage", apply = function(d) d.damage = d.damage * 1.25 end },
	longshot_quickscope = { unit = "longshot", name = "Quickscope", desc = "Fires 20% faster", apply = function(d) d.cooldown = d.cooldown * 0.8 end },
	engineer_turretup = { unit = "engineer", name = "Gun Turret", desc = "Turret deals +40%", apply = function(d) d.ability.damage = d.ability.damage * 1.4 end },
	engineer_rapid = { unit = "engineer", name = "Rapid Deploy", desc = "Turret ready 30% sooner", apply = function(d) d.ability.cooldown = d.ability.cooldown * 0.7 end },
	disruptor_wide = { unit = "disruptor", name = "Wide Field", desc = "+40% field radius", apply = function(d) d.ability.radius = d.ability.radius * 1.4 end },
	disruptor_paralysis = { unit = "disruptor", name = "Paralysis", desc = "Slow lasts 1.5s longer", apply = function(d) d.ability.duration = d.ability.duration + 1.5 end },
	commander_banner = { unit = "commander", name = "War Banner", desc = "Aura bonus +10%", apply = function(d) d.aura.bonus = d.aura.bonus + 0.10 end },
	commander_ironwill = { unit = "commander", name = "Iron Will", desc = "+30% HP", apply = function(d) d.hp = d.hp * 1.3 end },
	trickster_phase = { unit = "trickster", name = "Phase Dance", desc = "Blink reaches 50% farther", apply = function(d) d.ability.distance = d.ability.distance * 1.5 end },
	trickster_mirror = { unit = "trickster", name = "Mirror Feint", desc = "+15% speed, +10% HP", apply = function(d) d.speed = d.speed * 1.15; d.hp = d.hp * 1.1 end },
	artificer_sanctuary = { unit = "artificer", name = "Sanctuary", desc = "Pads heal 50% more", apply = function(d) d.ability.heal = d.ability.heal * 1.5 end },
	artificer_twin = { unit = "artificer", name = "Twin Pads", desc = "+30% pad radius", apply = function(d) d.ability.radius = d.ability.radius * 1.3 end },
	colossus_quake = { unit = "colossus", name = "Quake", desc = "+40% slam radius", apply = function(d) d.ability.radius = d.ability.radius * 1.4 end },
	colossus_engine = { unit = "colossus", name = "Siege Engine", desc = "+25% speed", apply = function(d) d.speed = d.speed * 1.25 end },
	phoenix_ember = { unit = "phoenix", name = "Ember Burst", desc = "+40% nova radius", apply = function(d) d.rebirth.novaRadius = d.rebirth.novaRadius * 1.4 end },
	phoenix_solar = { unit = "phoenix", name = "Solar Core", desc = "Rebirths with more HP", apply = function(d) d.rebirth.hpFrac = d.rebirth.hpFrac + 0.15 end },
	reaper_bloodmoon = { unit = "reaper", name = "Bloodmoon", desc = "+20% damage", apply = function(d) d.damage = d.damage * 1.2 end },
	reaper_deathwing = { unit = "reaper", name = "Deathwing", desc = "Executes wounded enemies", flag = "execute" },
}

UCConfig.FACTIONS = {
	scrapworks = {
		name = "Scrapworks", blurb = "Inventors. +10% damage from improvised weapons.",
		apply = function(d) d.damage = d.damage * 1.10 end,
	},
	vanguard = {
		name = "Vanguard", blurb = "Discipline. +0.05 armor, tighter formations.",
		apply = function(d) d.armor = (d.armor or 0) + 0.05 end,
	},
	wildgrove = {
		name = "Wildgrove", blurb = "Nature. Allies regenerate 1 HP/s.",
		apply = function(d) end, flag = "regen",
	},
	prism = {
		name = "Prism Division", blurb = "Energy. Abilities recharge 15% faster.",
		apply = function(d) if d.ability then d.ability.cooldown = d.ability.cooldown * 0.85 end end,
	},
}

UCConfig.ARENAS = {
	grassland = { name = "Grassland", ground = Color3.fromRGB(90, 140, 70), material = Enum.Material.Grass, modifiers = {},
		obstacles = { { x = 6, z = -14, r = 7 }, { x = -6, z = 14, r = 7 } } },
	desert = { name = "Desert", ground = Color3.fromRGB(215, 185, 120), material = Enum.Material.Sand, modifiers = { wind = true },
		obstacles = { { x = -18, z = 0, r = 8 }, { x = 18, z = 0, r = 8 }, { x = 0, z = 0, r = 5 } } },
	industrial = { name = "Industrial", ground = Color3.fromRGB(70, 75, 85), material = Enum.Material.DiamondPlate, modifiers = { heavyknock = true },
		obstacles = { { x = 0, z = -10, r = 9 }, { x = 0, z = 10, r = 9 } } },
	frozen = { name = "Frozen", ground = Color3.fromRGB(170, 215, 235), material = Enum.Material.Ice, modifiers = { slippery = true },
		obstacles = { { x = 0, z = 0, r = 10 } } },
	rooftop = { name = "Rooftop", ground = Color3.fromRGB(60, 60, 70), material = Enum.Material.Concrete, modifiers = { lowgravity = true },
		obstacles = { { x = -20, z = -12, r = 6 }, { x = -20, z = 12, r = 6 }, { x = 20, z = 0, r = 8 } } },
	training = { name = "Training Grounds", ground = Color3.fromRGB(120, 120, 130), material = Enum.Material.Concrete, modifiers = {},
		obstacles = {} },
}

-- Shop: cosmetics only. gamepassId 0 = not configured yet; set real IDs from Creator Hub.
UCConfig.SHOP = {
	gold = {
		name = "Golden Legion", blurb = "Your units render in polished gold.",
		gamepassId = 0,
		palette = { body = Color3.fromRGB(212, 175, 55), glyph = Color3.fromRGB(255, 240, 180) },
	},
	void = {
		name = "Void Corps", blurb = "Your units render in shadow-violet.",
		gamepassId = 0,
		palette = { body = Color3.fromRGB(30, 26, 48), glyph = Color3.fromRGB(185, 150, 255) },
	},
	supporter = {
		name = "Supporter Star", blurb = "Gold star beside your name. Pure style.",
		gamepassId = 0,
	},
}

UCConfig.LEVEL_XP = 100

function UCConfig.levelFor(xp)
	return 1 + math.floor((xp or 0) / UCConfig.LEVEL_XP)
end

function UCConfig.get(unitId)
	return UCConfig.UNITS[unitId]
end

function UCConfig.upgradesFor(unitId)
	local out = {}
	for id, up in pairs(UCConfig.UPGRADES) do
		if up.unit == unitId then
			table.insert(out, { id = id, name = up.name, desc = up.desc })
		end
	end
	table.sort(out, function(a, b) return a.id < b.id end)
	return out
end

return UCConfig
