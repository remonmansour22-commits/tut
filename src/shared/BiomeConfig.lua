-- Path: ReplicatedStorage/BeastboundShared/BiomeConfig
-- Journey stages and landmark configuration.
-- New biomes are added here as data; JourneyService does the rest.

local BiomeConfig = {}

-- worldDressing groups in Workspace/Aruun are tagged with these keys so that
-- a stage transition can simply tween the right colors.
BiomeConfig.TintableGroups = {
	"FoliageTint",
	"GroundTint",
	"AccentTint",
}

BiomeConfig.Stages = {
	{
		Id = "Mosslight",
		Name = "Mosslight Meadow",
		MomentumTarget = 130,
		Headline = "Lush, green and gentle. The Dawnward settlement rests on Aruun's back.",
		Environment = {
			ClockTime = 9.4,
			Brightness = 2.2,
			Ambient = Color3.fromRGB(120, 133, 112),
			OutdoorAmbient = Color3.fromRGB(150, 160, 140),
			FogColor = Color3.fromRGB(168, 190, 168),
			FogEnd = 900,
			EnvironmentDiffuseScale = 0.5,
		},
		Atmosphere = {
			Density = 0.35,
			Color = Color3.fromRGB(150, 175, 158),
			Decay = Color3.fromRGB(110, 130, 125),
			Glare = 0.15,
			Haze = 1.6,
		},
		Palette = {
			FoliageTint = Color3.fromRGB(120, 190, 110),
			GroundTint = Color3.fromRGB(120, 150, 96),
			AccentTint = Color3.fromRGB(120, 255, 190),
			Sky = Color3.fromRGB(140, 195, 220),
		},
	},
	{
		Id = "GoldenReaches",
		Name = "The Golden Reaches",
		MomentumTarget = 330,
		Headline = "Grass gives way to gold. Distant rock formations rise like sails.",
		Environment = {
			ClockTime = 15.5,
			Brightness = 2.4,
			Ambient = Color3.fromRGB(140, 120, 90),
			OutdoorAmbient = Color3.fromRGB(175, 155, 120),
			FogColor = Color3.fromRGB(235, 205, 150),
			FogEnd = 1100,
			EnvironmentDiffuseScale = 0.5,
		},
		Atmosphere = {
			Density = 0.4,
			Color = Color3.fromRGB(225, 190, 130),
			Decay = Color3.fromRGB(160, 120, 80),
			Glare = 0.35,
			Haze = 2.1,
		},
		Palette = {
			FoliageTint = Color3.fromRGB(200, 170, 96),
			GroundTint = Color3.fromRGB(196, 164, 108),
			AccentTint = Color3.fromRGB(255, 200, 110),
			Sky = Color3.fromRGB(225, 175, 120),
		},
	},
	{
		Id = "Glasswind",
		Name = "Glasswind Expanse",
		MomentumTarget = 620,
		Headline = "Wind-carved glass rock hums as Aruun strides across the mineral sea.",
		Environment = {
			ClockTime = 13.0,
			Brightness = 2.3,
			Ambient = Color3.fromRGB(140, 150, 165),
			OutdoorAmbient = Color3.fromRGB(175, 185, 200),
			FogColor = Color3.fromRGB(200, 215, 230),
			FogEnd = 1300,
			EnvironmentDiffuseScale = 0.5,
		},
		Atmosphere = {
			Density = 0.42,
			Color = Color3.fromRGB(195, 210, 225),
			Decay = Color3.fromRGB(120, 145, 175),
			Glare = 0.5,
			Haze = 2.4,
		},
		Palette = {
			FoliageTint = Color3.fromRGB(150, 180, 170),
			GroundTint = Color3.fromRGB(168, 178, 190),
			AccentTint = Color3.fromRGB(140, 220, 235),
			Sky = Color3.fromRGB(160, 190, 210),
		},
	},
}

-- Landmarks are placed in world space on/around the creature by WorldBuilder and
-- detected by proximity. Add entries here; no service changes needed.
BiomeConfig.Landmarks = {
	{
		Id = "WhisperingHollow",
		Name = "Whispering Hollow",
		Position = Vector3.new(-92, 42, -40),
		Radius = 12,
		Xp = 25,
		Lore = "A hollow beneath the moss where the wind hums old migration songs.",
	},
	{
		Id = "SentinelStone",
		Name = "Sentinel Stone",
		Position = Vector3.new(60, 41, 88),
		Radius = 12,
		Xp = 25,
		Lore = "A weathered watcher, carved long before the last migration route faded.",
	},
	{
		Id = "TailSpire",
		Name = "The Tail Spire",
		Position = Vector3.new(18, 60, -166),
		Radius = 12,
		Xp = 40,
		Lore = "The highest point of Aruun. From here the migration road looks endless.",
	},
	{
		Id = "HiddenGarden",
		Name = "The Hidden Garden",
		Position = Vector3.new(106, 34, 10),
		Radius = 12,
		Xp = 40,
		Lore = "Behind the waterfall, life insisted on continuing. Someone planted hope here.",
	},
	{
		Id = "LanternCrest",
		Name = "Lantern Crest",
		Position = Vector3.new(26, 46, 148),
		Radius = 12,
		Xp = 30,
		Lore = "Terraces below the great brow, where Aruun's lantern-glow is warmest.",
	},
}

return BiomeConfig
