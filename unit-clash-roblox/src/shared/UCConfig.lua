-- UNIT CLASH - shared configuration: unit roster, budgets, arena, teams.
-- Every unit is config-driven: the sim, AI, UI and visuals all read from here.

local UCConfig = {}

UCConfig.NAME = "UNIT CLASH"
UCConfig.TICK_RATE = 20
UCConfig.BATTLE_TIME_LIMIT = 180
UCConfig.BUDGET = { A = 500, B = 500 }
UCConfig.UNIT_LIMIT = 40

UCConfig.ARENA = {
	HALF = 100,
	DEPTH = 30,
	BASE_Y = 0,
	UNIT_Y = 3,
}

UCConfig.TEAMS = {
	A = { name = "AZURE", color = Color3.fromRGB(60, 140, 255) },
	B = { name = "CRIMSON", color = Color3.fromRGB(255, 80, 80) },
}

-- speed = studs/sec, range/damage in studs/hp, cooldowns in seconds.
-- ability = optional { name, cooldown, kind, ... }; kind drives the sim hook.
UCConfig.UNITS = {
	scout = {
		name = "Scout", category = "Agile", cost = 45, hp = 55, speed = 26, radius = 1,
		range = 6, damage = 8, cooldown = 0.5, brain = "skirmisher",
		color = Color3.fromRGB(120, 220, 120),
		desc = "Fast hit-and-run harasser. Fights, disengages, strikes again.",
	},
	brawler = {
		name = "Brawler", category = "Frontline", cost = 90, hp = 140, speed = 16, radius = 1.3,
		range = 6, damage = 16, cooldown = 0.9, brain = "brawler",
		color = Color3.fromRGB(230, 160, 60),
		desc = "Straightforward close-range bruiser. Charges the nearest enemy.",
	},
	guardian = {
		name = "Guardian", category = "Frontline", cost = 80, hp = 170, speed = 12, radius = 1.4,
		range = 5, damage = 8, cooldown = 1.1, brain = "guardian", armor = 0.15,
		aura = { kind = "protect", radius = 18, reduction = 0.25 },
		color = Color3.fromRGB(90, 170, 220),
		desc = "Defensive wall. Nearby allies take 25% less damage.",
	},
	medic = {
		name = "Medic", category = "Support", cost = 100, hp = 80, speed = 14, radius = 1.1,
		range = 24, damage = 0, cooldown = 2, brain = "healer",
		ability = { name = "Heal Beam", cooldown = 2, kind = "heal", amount = 26 },
		color = Color3.fromRGB(120, 240, 180),
		desc = "Heals the most wounded nearby ally. Flees when enemies close in.",
	},
	juggernaut = {
		name = "Juggernaut", category = "Heavy", cost = 150, hp = 340, speed = 9, radius = 1.8,
		range = 7, damage = 24, cooldown = 1.4, brain = "brawler", armor = 0.15,
		color = Color3.fromRGB(150, 150, 160),
		desc = "Slow armored wall of muscle. Absorbs fire and keeps walking.",
	},
	sparkcaster = {
		name = "Spark Caster", category = "Ranged", cost = 110, hp = 75, speed = 13, radius = 1.1,
		range = 26, damage = 13, cooldown = 1.4, brain = "ranged",
		projectile = { speed = 55, color = Color3.fromRGB(120, 200, 255) },
		ability = { name = "Chain Spark", cooldown = 5, kind = "bounce", jumps = 2, falloff = 0.6 },
		color = Color3.fromRGB(120, 200, 255),
		desc = "Lobs energy bolts that chain to nearby enemies.",
	},
	longshot = {
		name = "Longshot", category = "Ranged", cost = 120, hp = 60, speed = 12, radius = 1.1,
		range = 48, damage = 30, cooldown = 2.6, brain = "ranged", armor = 0,
		projectile = { speed = 90, color = Color3.fromRGB(255, 240, 120) },
		color = Color3.fromRGB(255, 240, 120),
		desc = "Extreme-range sniper. Powerful answer to armored walls, fragile up close.",
	},
	engineer = {
		name = "Engineer", category = "Specialist", cost = 115, hp = 85, speed = 13, radius = 1.1,
		range = 10, damage = 6, cooldown = 1.5, brain = "engineer",
		ability = { name = "Deploy Turret", cooldown = 12, kind = "deploy_turret", hp = 60, damage = 8, range = 24, cooldown2 = 0.8, lifetime = 20 },
		projectile = { speed = 50, color = Color3.fromRGB(200, 200, 120) },
		color = Color3.fromRGB(200, 170, 90),
		desc = "Deploys an auto-turret that fights for 20 seconds.",
	},
	disruptor = {
		name = "Disruptor", category = "Specialist", cost = 105, hp = 90, speed = 16, radius = 1.1,
		range = 20, damage = 10, cooldown = 1.2, brain = "disruptor",
		projectile = { speed = 60, color = Color3.fromRGB(200, 120, 255) },
		ability = { name = "Static Field", cooldown = 9, kind = "slow_aoe", radius = 20, factor = 0.5, duration = 3 },
		color = Color3.fromRGB(200, 120, 255),
		desc = "Pulses a field that slows every enemy caught in it.",
	},
	commander = {
		name = "Commander", category = "Commander", cost = 130, hp = 120, speed = 12, radius = 1.3,
		range = 8, damage = 10, cooldown = 1.0, brain = "commander",
		aura = { kind = "might", radius = 30, bonus = 0.2 },
		color = Color3.fromRGB(255, 210, 90),
		desc = "Aura: allies within 30 studs deal 20% more damage.",
	},
	trickster = {
		name = "Trickster", category = "Agile", cost = 95, hp = 70, speed = 22, radius = 1.0,
		range = 6, damage = 9, cooldown = 0.7, brain = "trickster",
		ability = { name = "Blink Step", cooldown = 6, kind = "dash", distance = 30 },
		color = Color3.fromRGB(240, 130, 200),
		desc = "Erratic duelist that blinks behind enemies when pressured.",
	},
	artificer = {
		name = "Artificer", category = "Support", cost = 110, hp = 80, speed = 12, radius = 1.1,
		range = 22, damage = 0, cooldown = 4, brain = "artificer",
		ability = { name = "Mend Pad", cooldown = 10, kind = "deploy_pad", heal = 10, radius = 14, lifetime = 16 },
		color = Color3.fromRGB(170, 220, 140),
		desc = "Places a pad that steadily heals allies standing on it.",
	},
	colossus = {
		name = "Colossus", category = "Experimental", cost = 320, hp = 900, speed = 6, radius = 3,
		range = 12, damage = 40, cooldown = 2, brain = "titan", armor = 0.25,
		ability = { name = "Seismic Slam", cooldown = 8, kind = "slam_aoe", radius = 20, damage = 25, knockback = 24 },
		color = Color3.fromRGB(110, 100, 130),
		desc = "Costly siege engine. Slams the ground, damaging and launching groups.",
	},
	phoenix = {
		name = "Phoenix", category = "Experimental", cost = 160, hp = 115, speed = 18, radius = 1.2,
		range = 28, damage = 13, cooldown = 1.1, brain = "caster",
		projectile = { speed = 55, color = Color3.fromRGB(255, 150, 60) },
		rebirth = { hpFrac = 0.35, novaDamage = 20, novaRadius = 20 },
		color = Color3.fromRGB(255, 150, 60),
		desc = "Dies once, returns in flame. Rebirth unleashes a damaging nova.",
	},
	reaper = {
		name = "Reaper", category = "Specialist", cost = 150, hp = 165, speed = 21, radius = 1.2,
		range = 5, damage = 16, cooldown = 0.7, brain = "skirmisher", armor = 0.05,
		lifesteal = 0.6,
		color = Color3.fromRGB(90, 60, 110),
		desc = "Drain-tank. Heals for 60% of the damage it deals.",
	},
}

UCConfig.ORDER = { "scout", "brawler", "guardian", "medic", "juggernaut", "sparkcaster",
	"longshot", "engineer", "disruptor", "commander", "trickster", "artificer",
	"colossus", "phoenix", "reaper" }

function UCConfig.get(unitId)
	return UCConfig.UNITS[unitId]
end

return UCConfig
