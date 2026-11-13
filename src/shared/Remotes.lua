--!strict
--[[
	Remotes
	Centralized remote event and function name definitions.
	The server creates these instances at startup; both sides reference them by name.
]]

local Remotes = {}

--- RemoteEvent names (fire-and-forget / one-way notifications)
Remotes.Events = {
	-- Excavation
	RequestExcavation = "RequestExcavation",  -- Client → Server
	ExcavationResult  = "ExcavationResult",   -- Server → Client

	-- Inventory
	InventoryUpdated = "InventoryUpdated",    -- Server → Client

	-- Carrying & Placement
	RequestCarryItem  = "RequestCarryItem",   -- Client → Server
	RequestPlaceItem  = "RequestPlaceItem",   -- Client → Server
	CarryStateChanged = "CarryStateChanged",  -- Server → Client

	-- Cleaning
	RequestCleanFossil = "RequestCleanFossil", -- Client → Server
	CleaningProgress   = "CleaningProgress",   -- Server → Client

	-- Machines (DNA Extractor & Incubator)
	RequestUseMachine    = "RequestUseMachine",    -- Client → Server
	RequestCollectOutput = "RequestCollectOutput",  -- Client → Server
	MachineStateUpdated  = "MachineStateUpdated",   -- Server → Client

	-- Cages
	RequestPlaceDinosaur = "RequestPlaceDinosaur", -- Client → Server
	CageUpdated          = "CageUpdated",          -- Server → Client

	-- Economy
	RequestCollectIncome = "RequestCollectIncome",  -- Client → Server
	MoneyUpdated         = "MoneyUpdated",          -- Server → Client
	XPUpdated            = "XPUpdated",             -- Server → Client
	LevelUpdated         = "LevelUpdated",          -- Server → Client

	-- Player Data
	PlayerDataLoaded = "PlayerDataLoaded",          -- Server → Client (initial sync)
}

--- RemoteFunction names (request-response)
Remotes.Functions = {
	GetPlayerData  = "GetPlayerData",
	GetInventory   = "GetInventory",
	GetMachineState = "GetMachineState",
}

return Remotes

