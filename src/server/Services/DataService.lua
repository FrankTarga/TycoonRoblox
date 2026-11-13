--!strict
--[[
	DataService
	Handles player data caching in memory and persistent storage via DataStoreService.

	Key Features:
	  1. In-memory session cache for fast, synchronous data access across all services.
	  2. Safe DataStoreService integration with pcall error handling and retry logic.
	  3. Automatic schema validation and migration for backward compatibility.
	  4. Support for mock DataStores during automated testing.
	  5. Periodic auto-save loop (every 300s) and graceful save on shutdown/disconnect.
]]

local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(ReplicatedStorage.Modules.Types)

local DataService = {}

-- Constants
local DATA_STORE_NAME = "DinoTycoon_PlayerData_v1"
local KEY_PREFIX = "Player_"
local AUTO_SAVE_INTERVAL = 300 -- 5 minutes
local MAX_RETRIES = 3

-- In-memory session cache: UserId -> PlayerData
local playerDataCache: { [number]: Types.PlayerData } = {}

-- DataStore reference (real or mock)
local dataStore: any = nil

-------------------------------------------------------------------------
-- MOCK & DATASTORE INITIALIZATION
-------------------------------------------------------------------------

local function getStore(): any
	if dataStore then return dataStore end

	-- Safely attempt to connect to Roblox DataStoreService
	local success, result = pcall(function()
		return DataStoreService:GetDataStore(DATA_STORE_NAME)
	end)

	if success and result then
		dataStore = result
	else
		warn("[DataService] Could not access real DataStore (offline mode / API disabled).")
	end

	return dataStore
end

--- Allows unit tests to inject a mock DataStore object.
function DataService.setMockDataStore(mock: any)
	dataStore = mock
end

-------------------------------------------------------------------------
-- SCHEMA VALIDATION & MIGRATION
-------------------------------------------------------------------------

--- Validates raw data loaded from DataStore and ensures all required fields exist.
function DataService.validateAndMigrate(raw: any): Types.PlayerData
	local default = Types.getDefaultPlayerData()

	if typeof(raw) ~= "table" then
		return default
	end

	-- Core attributes
	raw.Money = if typeof(raw.Money) == "number" then raw.Money else default.Money
	raw.Level = if typeof(raw.Level) == "number" then raw.Level else default.Level
	raw.XP    = if typeof(raw.XP) == "number" then raw.XP else default.XP

	-- Inventory
	if typeof(raw.Inventory) ~= "table" then
		raw.Inventory = default.Inventory
	end

	-- Equipment
	if typeof(raw.Equipment) ~= "table" then
		raw.Equipment = default.Equipment
	else
		raw.Equipment.ActiveShovel = raw.Equipment.ActiveShovel or default.Equipment.ActiveShovel
		raw.Equipment.ActiveBrush  = raw.Equipment.ActiveBrush or default.Equipment.ActiveBrush
		raw.Equipment.OwnedEquipment = raw.Equipment.OwnedEquipment or default.Equipment.OwnedEquipment
	end

	-- Unlocked Zones
	if typeof(raw.UnlockedZones) ~= "table" then
		raw.UnlockedZones = default.UnlockedZones
	end

	-- Plot Data
	if typeof(raw.PlotData) ~= "table" then
		raw.PlotData = default.PlotData
	else
		raw.PlotData.ExpansionLevel = raw.PlotData.ExpansionLevel or default.PlotData.ExpansionLevel
		raw.PlotData.CageCount = raw.PlotData.CageCount or default.PlotData.CageCount
	end

	-- Cage Assignments
	if typeof(raw.CageAssignments) ~= "table" then
		raw.CageAssignments = default.CageAssignments
	end

	-- Machine States
	if typeof(raw.MachineStates) ~= "table" then
		raw.MachineStates = default.MachineStates
	end

	-- Statistics
	if typeof(raw.Statistics) ~= "table" then
		raw.Statistics = default.Statistics
	else
		raw.Statistics.TotalFossilsExcavated = raw.Statistics.TotalFossilsExcavated or 0
		raw.Statistics.TotalDNAExtracted = raw.Statistics.TotalDNAExtracted or 0
		raw.Statistics.TotalDinosaursIncubated = raw.Statistics.TotalDinosaursIncubated or 0
		raw.Statistics.TotalMoneyEarned = raw.Statistics.TotalMoneyEarned or 0
	end

	return raw :: Types.PlayerData
end

-------------------------------------------------------------------------
-- CACHE & LIFECYCLE
-------------------------------------------------------------------------

--- Retrieves player data from the in-memory cache.
function DataService.getPlayerData(userId: number): Types.PlayerData?
	return playerDataCache[userId]
end

--- Sets or updates player data in the in-memory cache.
function DataService.setPlayerData(userId: number, data: Types.PlayerData)
	playerDataCache[userId] = data
end

--- Initializes default player data for a newly joined player.
function DataService.initPlayerData(player: any): Types.PlayerData
	local uid = if typeof(player) == "Instance" then player.UserId else (player.UserId or 0)
	local data = Types.getDefaultPlayerData()
	playerDataCache[uid] = data
	return data
end

--- Removes player data from the in-memory cache on leave.
function DataService.removePlayerData(userId: number)
	playerDataCache[userId] = nil
end

--- Returns the entire session cache (read-only reference).
function DataService.getAllPlayerData(): { [number]: Types.PlayerData }
	return playerDataCache
end

-------------------------------------------------------------------------
-- PERSISTENCE — SAVE & LOAD
-------------------------------------------------------------------------

--- Loads player data from DataStore (or fallback) and caches it.
function DataService.loadPlayerData(userId: number): Types.PlayerData
	local store = getStore()
	local key = KEY_PREFIX .. tostring(userId)

	if store then
		local success, result = pcall(function()
			return store:GetAsync(key)
		end)

		if success and result ~= nil then
			local validated = DataService.validateAndMigrate(result)
			playerDataCache[userId] = validated
			print(string.format("[DataService] Successfully loaded data for player %d.", userId))
			return validated
		elseif not success then
			warn(string.format("[DataService] Failed to load data for player %d: %s", userId, tostring(result)))
		end
	end

	-- If new player or DataStore failed, initialize default
	local default = Types.getDefaultPlayerData()
	playerDataCache[userId] = default
	print(string.format("[DataService] Initialized default data for player %d.", userId))
	return default
end

--- Saves player data from cache into DataStore with retry logic.
function DataService.savePlayerData(userId: number): boolean
	local data = playerDataCache[userId]
	if not data then return false end

	local store = getStore()
	if not store then return false end

	local key = KEY_PREFIX .. tostring(userId)
	local attempts = 0
	local success = false
	local err: any = nil

	while attempts < MAX_RETRIES and not success do
		attempts += 1
		success, err = pcall(function()
			store:SetAsync(key, data)
		end)
		if not success and attempts < MAX_RETRIES then
			task.wait(1)
		end
	end

	if success then
		print(string.format("[DataService] Successfully saved data for player %d.", userId))
		return true
	else
		warn(string.format("[DataService] Failed to save data for player %d after %d attempts: %s",
			userId, attempts, tostring(err)))
		return false
	end
end

--- Saves data for all currently active players in cache.
function DataService.saveAllPlayers()
	print("[DataService] Saving data for all connected players...")
	for userId, _ in playerDataCache do
		DataService.savePlayerData(userId)
	end
end

-------------------------------------------------------------------------
-- INITIALIZATION & AUTO-SAVE
-------------------------------------------------------------------------

function DataService.init()
	-- Start periodic auto-save loop only in real gameplay (not unit tests)
	if RunService:IsServer() and not RunService:IsStudio() then
		task.spawn(function()
			while true do
				task.wait(AUTO_SAVE_INTERVAL)
				DataService.saveAllPlayers()
			end
		end)
	end

	print("[DataService] Initialized with DataStore persistence.")
end

return DataService
