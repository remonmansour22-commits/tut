-- Path: ReplicatedStorage/BeastboundShared/AudioConfig
-- Placeholder sound assets (bundled with the engine, always valid).
-- Replace any SoundId with real uploaded asset ids in polish later.

local AudioConfig = {
	UiClick = { SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.4, Pitch = 1.4 },
	UiOpen = { SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5, Pitch = 1.0 },
	Gather = { SoundId = "rbxasset://sounds/snap.mp3", Volume = 0.7, Pitch = 1.0 },
	Build = { SoundId = "rbxasset://sounds/snap.mp3", Volume = 0.8, Pitch = 0.7 },
	Discover = { SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.7, Pitch = 0.8 },
	CreatureCall = { SoundId = "rbxasset://sounds/impact_water.mp3", Volume = 1.0, Pitch = 0.5 },
	CreaturePurr = { SoundId = "rbxasset://sounds/impact_water.mp3", Volume = 0.7, Pitch = 0.8 },
	ProjectComplete = { SoundId = "rbxasset://sounds/impact_water.mp3", Volume = 1.0, Pitch = 0.65 },
}

return AudioConfig
