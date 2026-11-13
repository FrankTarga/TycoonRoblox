--!strict
--[[
	Types
	Shared type definitions used across client and server.
	Defines the data shapes for items, player data, cages, machines, and statistics.
]]

local Types = {}

----------------------------------------------------------------------
-- Item instance (a single item in a player's inventory)
----------------------------------------------------------------------
export type ItemData = {
	ItemUID: string,       -- Unique instance identifier (GUID)
	ItemType: string,      -- "Fossil" | "DNA" | "Dinosaur"
	ConfigID: string,      -- References FossilConfig, DinosaurConfig key, etc.
	DinosaurID: string,    -- Which dinosaur this item relates to
	Rarity: string,        -- Rarity level name
	Quality: number,       -- 0–100, improved by cleaning
	IsCleaned: boolean,    -- Whether the fossil has been cleaned
	ObtainedAt: number,    -- os.time() timestamp
}

----------------------------------------------------------------------
-- Cage assignment
----------------------------------------------------------------------
export type CageData = {
	CageID: string,
	DinosaurItemUID: string?,  -- nil if cage is empty
	DinosaurID: string?,       -- nil if cage is empty
	AccumulatedIncome: number,
	LastCollectionTime: number, -- os.time() timestamp
}

----------------------------------------------------------------------
-- Machine state (for persistence and recovery)
----------------------------------------------------------------------
export type MachineStateData = {
	MachineID: string,
	State: string,              -- "Idle" | "Processing" | "OutputReady" | "Completed"
	InputItemUID: string?,      -- UID of item placed in machine
	InputConfigID: string?,     -- ConfigID of the input item
	StartTime: number?,         -- os.time() when processing started
	OutputConfigID: string?,    -- ConfigID of what will be produced
	OutputDinosaurID: string?,  -- DinosaurID of the output
}

----------------------------------------------------------------------
-- Plot data
----------------------------------------------------------------------
export type PlotData = {
	ExpansionLevel: number,
	CageCount: number,
}

----------------------------------------------------------------------
-- Player statistics
----------------------------------------------------------------------
export type PlayerStatistics = {
	TotalFossilsExcavated: number,
	TotalDNAExtracted: number,
	TotalDinosaursIncubated: number,
	TotalMoneyEarned: number,
}

----------------------------------------------------------------------
-- Full player data (persisted to DataStore)
----------------------------------------------------------------------
export type PlayerData = {
	Money: number,
	Level: number,
	XP: number,
	Inventory: { ItemData },
	Equipment: {
		ActiveShovel: string,       -- EquipmentID
		ActiveBrush: string,        -- EquipmentID
		OwnedEquipment: { string }, -- List of EquipmentIDs
	},
	UnlockedZones: { string },      -- List of ZoneIDs
	PlotData: PlotData,
	CageAssignments: { [string]: CageData }, -- CageID → CageData
	MachineStates: { [string]: MachineStateData }, -- MachineID → state
	Statistics: PlayerStatistics,
}

----------------------------------------------------------------------
-- Default player data factory
----------------------------------------------------------------------
function Types.getDefaultPlayerData(): PlayerData
	return {
		Money = 100,
		Level = 1,
		XP = 0,
		Inventory = {},
		Equipment = {
			ActiveShovel = "BASIC_SHOVEL",
			ActiveBrush = "BASIC_BRUSH",
			OwnedEquipment = { "BASIC_SHOVEL", "BASIC_BRUSH" },
		},
		UnlockedZones = { "BEGINNER_SITE" },
		PlotData = {
			ExpansionLevel = 1,
			CageCount = 1,
		},
		CageAssignments = {},
		MachineStates = {},
		Statistics = {
			TotalFossilsExcavated = 0,
			TotalDNAExtracted = 0,
			TotalDinosaursIncubated = 0,
			TotalMoneyEarned = 0,
		},
	}
end

return Types

