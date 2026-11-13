--!strict
--[[
	DataService
	Handles player data cache in memory and persistence via DataStore.
	In Phase 2, provides session data management across all server services.
	(DataStore persistence will be fully hooked in Phase 9).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Types = require(ReplicatedStorage.Modules.Types)

local DataService = {}

local playerDataCache: { [number]: Types.PlayerData } = {}

function DataService.init()
	print("[DataService] Initialized — session cache ready.")
end

--- Retrieves player data from the in-memory cache.
function DataService.getPlayerData(userId: number): Types.PlayerData?
	return playerDataCache[userId]
end

--- Sets or updates player data in the in-memory cache.
function DataService.setPlayerData(userId: number, data: Types.PlayerData)
	playerDataCache[userId] = data
end

--- Initializes default player data for a newly joined player.
function DataService.initPlayerData(player: Player): Types.PlayerData
	local data = Types.getDefaultPlayerData()
	playerDataCache[player.UserId] = data
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

-- Phase 9 DataStore persistence stubs:
-- function DataService.loadPlayerData(userId: number): Types.PlayerData?
-- function DataService.savePlayerData(userId: number, data: Types.PlayerData): boolean
-- function DataService.saveAllPlayers()

return DataService
