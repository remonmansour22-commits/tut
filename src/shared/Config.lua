--!strict
-- Path: ReplicatedStorage/BeastboundShared/Config
-- Global tuning constants. Change values here, not inside systems.

local Config = {
	-- Data / persistence
	DataStoreName = "Beastbound_PlayerData_v1",
	AutosaveIntervalSeconds = 60,
	MaxSaveRetries = 3,

	-- Progression
	LevelXpThresholds = { 0, 60, 140, 260, 420, 640, 920, 1270, 1700, 2220, 2850 }, -- index = level 1..11
	XpRewards = {
		Gather = 3,
		Contribute = 6,
		Build = 30,
		Discover = 25,
		ProjectCompleteBonus = 60,
	},

	-- Gathering
	NodeRespawnSeconds = 14,
	MaxGatherDistance = 14, -- sanity check beyond ProximityPrompt distance
	RareDoubleChance = 0.12,

	-- Building
	BuildRateLimitSeconds = 2,
	MaxRotationSteps = 4, -- rotation validated server-side

	-- Journey (community "migration momentum")
	JourneyMomentumPerMinute = 1.5,
	JourneyMomentumPerDiscover = 12,
	JourneyMomentumPerBuild = 8,
	JourneyMomentumPerProject = 120,

	-- Creature bond
	BondPerContribution = 2,
	BondPerBuild = 3,
	BondPerDiscover = 4,
	BondMaxLevel = 8,

	-- Community project
	HeartrootGlowseedsNeeded = 40,
	ContributeChunk = 5, -- per interaction, clamped to what the player holds

	WorldSeedSafe = true, -- reserved for future procedural variation
}

return Config
