-- Path: ReplicatedStorage/BeastboundShared/Types
-- Lightweight shared type documentation (for tooling / future strict adoption).

export type ResourceId = "Driftwood" | "Stone" | "Glowseed"

export type Cost = { [string]: number }

export type Profile = {
	schemaVersion: number,
	level: number,
	xp: number,
	inventory: { [string]: number },
	counts: {
		gathered: number,
		built: number,
		contributed: number,
		discoveries: number,
	},
	discoveredLandmarks: { [string]: boolean },
	plots: { [string]: string }, -- plotId -> structureId
	quests: {
		index: number,
		progress: number,
	},
	journeyStageSeen: number,
}

return true
