--!strict
--[[
	InventoryService
	Server-side inventory management.
	Provides authoritative operations to add, remove, and query player items.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Types = require(ReplicatedStorage.Modules.Types)
local ItemUtils = require(ReplicatedStorage.Modules.ItemUtils)

local InventoryService = {}

local DataService = nil
local remoteEventsFolder: Folder? = nil

function InventoryService.init()
	DataService = require(ServerScriptService.Services.DataService)
	remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10) :: Folder?
	print("[InventoryService] Initialized.")
end

--- Adds an item to a player's inventory and syncs to client.
function InventoryService.addItem(userId: number, item: Types.ItemData): boolean
	if not DataService then return false end
	local data = DataService.getPlayerData(userId)
	if not data then
		warn("[InventoryService] Cannot add item: player data not found for userId", userId)
		return false
	end

	table.insert(data.Inventory, item)

	-- Fire inventory update to the client
	local player = Players:GetPlayerByUserId(userId)
	if player and remoteEventsFolder then
		local inventoryUpdated = remoteEventsFolder:FindFirstChild("InventoryUpdated") :: RemoteEvent?
		if inventoryUpdated then
			inventoryUpdated:FireClient(player, data.Inventory)
		end
	end

	return true
end

--- Removes an item from a player's inventory by its ItemUID.
function InventoryService.removeItem(userId: number, itemUID: string): Types.ItemData?
	if not DataService then return nil end
	local data = DataService.getPlayerData(userId)
	if not data then return nil end

	local _, index = ItemUtils.findItemByUID(data.Inventory, itemUID)
	if not index then return nil end

	local removedItem = table.remove(data.Inventory, index)

	local player = Players:GetPlayerByUserId(userId)
	if player and remoteEventsFolder then
		local inventoryUpdated = remoteEventsFolder:FindFirstChild("InventoryUpdated") :: RemoteEvent?
		if inventoryUpdated then
			inventoryUpdated:FireClient(player, data.Inventory)
		end
	end

	return removedItem
end

--- Retrieves an item from a player's inventory by ItemUID.
function InventoryService.getItem(userId: number, itemUID: string): Types.ItemData?
	if not DataService then return nil end
	local data = DataService.getPlayerData(userId)
	if not data then return nil end

	local item = ItemUtils.findItemByUID(data.Inventory, itemUID)
	return item
end

--- Returns a player's full inventory.
function InventoryService.getInventory(userId: number): { Types.ItemData }
	if not DataService then return {} end
	local data = DataService.getPlayerData(userId)
	return if data then data.Inventory else {}
end

--- Checks if a player owns an item with the given ItemUID.
function InventoryService.hasItem(userId: number, itemUID: string): boolean
	return InventoryService.getItem(userId, itemUID) ~= nil
end

return InventoryService
