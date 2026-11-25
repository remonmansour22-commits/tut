-- Path: ReplicatedStorage/BeastboundShared/ResourceConfig
-- Resource definitions used by gathering, inventory and building cost checks.

local ResourceConfig = {}

ResourceConfig.Order = { "Driftwood", "Stone", "Glowseed" }

ResourceConfig.ById = {
	Driftwood = {
		Id = "Driftwood",
		DisplayName = "Driftwood",
		IconColor = Color3.fromRGB(196, 141, 84),
		Material = Enum.Material.WoodPlanks,
		DropMin = 1,
		DropMax = 2,
		Description = "Weathered wood gathered across the back of Aruun. Good for shelter frames.",
	},
	Stone = {
		Id = "Stone",
		DisplayName = "Stone",
		IconColor = Color3.fromRGB(150, 152, 158),
		Material = Enum.Material.Slate,
		DropMin = 1,
		DropMax = 2,
		Description = "Broken terrace rock. Used for foundations and infrastructure.",
	},
	Glowseed = {
		Id = "Glowseed",
		DisplayName = "Glowseed",
		IconColor = Color3.fromRGB(120, 255, 190),
		Material = Enum.Material.Neon,
		DropMin = 1,
		DropMax = 1,
		Description = "A warm, living seed. Feeds the Heartroot and restoration projects.",
	},
}

return ResourceConfig
