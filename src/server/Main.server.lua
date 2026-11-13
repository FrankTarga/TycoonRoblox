--!strict
--[[
	Main Server Script
	Bootstraps all server-side systems for Dinosaur Fossil Tycoon.

	Responsibilities:
	  1. Create RemoteEvent / RemoteFunction instances.
	  2. Initialize server services.
	  3. Handle player join / leave lifecycle.
	  4. Handle server shutdown.
]]

local Players             = game:GetService("Players")
local ReplicatedStorage   = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Shared modules
local Remotes = require(ReplicatedStorage.Remotes)
local Types   = require(ReplicatedStorage.Modules.Types)

print("[Server] Dinosaur Fossil Tycoon — initializing...")

-------------------------------------------------------------------------
-- 1. CREATE REMOTE EVENTS & FUNCTIONS
-------------------------------------------------------------------------
local remoteEventsFolder = Instance.new("Folder")
remoteEventsFolder.Name = "RemoteEvents"
remoteEventsFolder.Parent = ReplicatedStorage

for _, eventName in Remotes.Events do
	local remote = Instance.new("RemoteEvent")
	remote.Name = eventName
	remote.Parent = remoteEventsFolder
end

local remoteFunctionsFolder = Instance.new("Folder")
remoteFunctionsFolder.Name = "RemoteFunctions"
remoteFunctionsFolder.Parent = ReplicatedStorage

for _, funcName in Remotes.Functions do
	local remoteFunc = Instance.new("RemoteFunction")
	remoteFunc.Name = funcName
	remoteFunc.Parent = remoteFunctionsFolder
end

print("[Server] Remotes created.")

-------------------------------------------------------------------------
-- 2. INITIALIZE SERVICES
-------------------------------------------------------------------------
local Services = ServerScriptService.Services

local DataService      = require(Services.DataService)
local InventoryService = require(Services.InventoryService)
local PlotService      = require(Services.PlotService)
local DiggingService   = require(Services.DiggingService)

DataService.init()
InventoryService.init()
PlotService.init()
DiggingService.init()

print("[Server] Services initialized.")

-------------------------------------------------------------------------
-- 3. PLAYER LIFECYCLE
-------------------------------------------------------------------------
local function onPlayerAdded(player: Player)
	print("[Server] Player joined:", player.Name, "(", player.UserId, ")")

	-- Initialize player session data (Phase 9 will load from DataStore)
	local data = DataService.initPlayerData(player)

	-- TODO: DataService:LoadPlayerData(player.UserId)
	-- TODO: PlotService:InitializePlot(player)

	-- Send initial data to client
	local playerDataLoaded = remoteEventsFolder:FindFirstChild("PlayerDataLoaded")
	if playerDataLoaded then
		(playerDataLoaded :: RemoteEvent):FireClient(player, data)
	end

	print("[Server] Player initialized:", player.Name)
end

local function onPlayerRemoving(player: Player)
	print("[Server] Player leaving:", player.Name, "(", player.UserId, ")")

	-- TODO: DataService:SavePlayerData(player.UserId, DataService.getPlayerData(player.UserId))

	DataService.removePlayerData(player.UserId)

	print("[Server] Player data cleaned up:", player.Name)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Handle players already in game (Studio testing / late-loading script)
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

-------------------------------------------------------------------------
-- 4. REMOTE FUNCTION HANDLERS
-------------------------------------------------------------------------
local getPlayerDataRemote = remoteFunctionsFolder:FindFirstChild("GetPlayerData")
if getPlayerDataRemote then
	(getPlayerDataRemote :: RemoteFunction).OnServerInvoke = function(player: Player)
		return DataService.getPlayerData(player.UserId)
	end
end

local getInventoryRemote = remoteFunctionsFolder:FindFirstChild("GetInventory")
if getInventoryRemote then
	(getInventoryRemote :: RemoteFunction).OnServerInvoke = function(player: Player)
		return InventoryService.getInventory(player.UserId)
	end
end

-------------------------------------------------------------------------
-- 5. SERVER SHUTDOWN
-------------------------------------------------------------------------
game:BindToClose(function()
	print("[Server] Server shutting down — saving all player data...")

	for userId, data in DataService.getAllPlayerData() do
		local player = Players:GetPlayerByUserId(userId)
		local playerName = if player then player.Name else tostring(userId)
		-- TODO: DataService:SavePlayerData(userId, data)
		print("[Server] Saved data for:", playerName)
	end

	print("[Server] Shutdown complete.")
end)

print("[Server] Dinosaur Fossil Tycoon — ready!")
