-- Path: ReplicatedStorage/BeastboundShared/BuildingConfig
-- Construction catalogue. Server validates every field here before building.

local BuildingConfig = {}

BuildingConfig.ById = {
	Shelter = {
		Id = "Shelter",
		DisplayName = "Basic Shelter",
		Category = "Settlement",
		Description = "A warm driftwood home with a leaf roof. The first mark of a settlement.",
		Cost = { Driftwood = 8, Stone = 4 },
		UnlockLevel = 1,
		XpOnBuild = 30,
		BondGain = 3,
		Inventory = { Driftwood = 2, Stone = 5 }, -- small passive harvest every cycle (future use)
	},
	LookoutTower = {
		Id = "LookoutTower",
		DisplayName = "Lookout Tower",
		Category = "Special",
		Description = "Climb high and watch the migration road. Reveals far-away landmarks.",
		Cost = { Driftwood = 12, Stone = 10 },
		UnlockLevel = 3,
		XpOnBuild = 45,
		BondGain = 3,
	},
	ResonanceBeacon = {
		Id = "ResonanceBeacon",
		DisplayName = "Resonance Beacon",
		Category = "Creature",
		Description = "A glowseed lens that sings to Aruun. Strengthens the bond with the creature.",
		Cost = { Stone = 8, Glowseed = 10 },
		UnlockLevel = 2,
		XpOnBuild = 50,
		BondGain = 8,
	},
}

BuildingConfig.Order = { "Shelter", "LookoutTower", "ResonanceBeacon" }

return BuildingConfig
