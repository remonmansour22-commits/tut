-- Path: ReplicatedStorage/BeastboundShared/QuestConfig
-- Sequential onboarding objectives. Add quests here; QuestService walks the list.

local QuestConfig = {}

QuestConfig.Quests = {
	{
		Id = "KindleGlow",
		Title = "Gather 5 Glowseeds",
		Tag = "gather:Glowseed",
		Target = 5,
		RewardXp = 20,
		Hint = "Glowseed clusters grow on the middle terraces of Aruun's back.",
	},
	{
		Id = "Heartlight",
		Title = "Feed the Heartroot 5 Glowseeds",
		Tag = "contribute",
		Target = 5,
		RewardXp = 30,
		Hint = "Contribute Glowseeds at the Heartroot in the central plaza.",
	},
	{
		Id = "FirstRoof",
		Title = "Build a Basic Shelter",
		Tag = "build",
		Target = 1,
		RewardXp = 40,
		Hint = "Claim a plot ring and open the Build menu.",
	},
	{
		Id = "Wayfinder",
		Title = "Discover a Landmark",
		Tag = "discover",
		Target = 1,
		RewardXp = 40,
		Hint = "Explore the edges of Aruun: hollows, spires and gardens hide there.",
	},
	{
		Id = "OnwardStage",
		Title = "Follow the Migration to Stage 2",
		Tag = "journey",
		Target = 2,
		RewardXp = 60,
		Hint = "Community projects and discoveries push the migration onward.",
	},
	{
		Id = "BondKeeper",
		Title = "Reach Bond Level 2 with Aruun",
		Tag = "bond",
		Target = 2,
		RewardXp = 50,
		Hint = "Beacons, buildings and Heartroot light deepen the bond.",
	},
}

QuestConfig.IdleTitle = "Explore freely. Restore the terraces. The First Garden lies far ahead."

return QuestConfig
