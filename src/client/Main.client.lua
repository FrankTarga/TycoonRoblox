--!strict
--[[
	Main Client Script
	Bootstraps all client-side systems for Dinosaur Fossil Tycoon.

	Responsibilities:
	  1. Wait for server remotes.
	  2. Receive initial player data.
	  3. Initialize client controllers.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

print("[Client] Dinosaur Fossil Tycoon — initializing...")

-------------------------------------------------------------------------
-- 1. WAIT FOR REMOTES
-------------------------------------------------------------------------
local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 30) :: Folder?
local remoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions", 30) :: Folder?

if not remoteEvents then
	warn("[Client] Timed out waiting for RemoteEvents!")
	return
end

if not remoteFunctions then
	warn("[Client] Timed out waiting for RemoteFunctions!")
	return
end

print("[Client] Remotes found.")

-------------------------------------------------------------------------
-- 2. RECEIVE INITIAL PLAYER DATA
-------------------------------------------------------------------------
local playerData = nil
local dataReceived = false

local playerDataLoaded = remoteEvents:WaitForChild("PlayerDataLoaded") :: RemoteEvent

playerDataLoaded.OnClientEvent:Connect(function(data)
	playerData = data
	dataReceived = true
	print("[Client] Received player data — Money:", data.Money, "Level:", data.Level)
end)

-- Also support requesting data if the event was missed
local getPlayerDataFunc = remoteFunctions:FindFirstChild("GetPlayerData") :: RemoteFunction?
if getPlayerDataFunc and not dataReceived then
	task.delay(3, function()
		if not dataReceived then
			print("[Client] Requesting player data via RemoteFunction...")
			local data = getPlayerDataFunc:InvokeServer()
			if data and not dataReceived then
				playerData = data
				dataReceived = true
				print("[Client] Received player data (fallback) — Money:", data.Money)
			end
		end
	end)
end

-------------------------------------------------------------------------
-- 3. LISTEN FOR DATA & ECONOMY UPDATES
-------------------------------------------------------------------------
local inventoryUpdated = remoteEvents:WaitForChild("InventoryUpdated") :: RemoteEvent
inventoryUpdated.OnClientEvent:Connect(function(newInventory)
	if playerData then
		playerData.Inventory = newInventory
	end
	-- Future: update Inventory UI
end)

local moneyUpdated = remoteEvents:WaitForChild("MoneyUpdated") :: RemoteEvent
moneyUpdated.OnClientEvent:Connect(function(newMoney: number)
	if playerData then
		playerData.Money = newMoney
	end
	-- Future: update Money UI
end)

local xpUpdated = remoteEvents:WaitForChild("XPUpdated") :: RemoteEvent
xpUpdated.OnClientEvent:Connect(function(newXP: number)
	if playerData then
		playerData.XP = newXP
	end
	-- Future: update XP UI
end)

local levelUpdated = remoteEvents:WaitForChild("LevelUpdated") :: RemoteEvent
levelUpdated.OnClientEvent:Connect(function(newLevel: number)
	if playerData then
		playerData.Level = newLevel
	end
	-- Future: update Level UI
end)

-------------------------------------------------------------------------
-- 4. INITIALIZE CONTROLLERS
-------------------------------------------------------------------------
local Controllers = script.Parent:WaitForChild("Controllers")

local CarryController = require(Controllers:WaitForChild("CarryController"))
local InventoryController = require(Controllers:WaitForChild("InventoryController"))
local ExcavationController = require(Controllers:WaitForChild("ExcavationController"))

CarryController.init()
InventoryController.init()
ExcavationController.init()

-- Controllers to be hooked in future phases:
-- local MachineController    = require(Controllers.MachineController)
-- local UIController         = require(Controllers.UIController)

print("[Client] Dinosaur Fossil Tycoon — ready!")
