--!strict
--[[
	InventoryController
	Client-side controller for inventory access, filtering, and item selection.

	Responsibilities:
	  1. Maintains the client's local inventory cache updated via InventoryUpdated.
	  2. Provides filtered queries for Fossils, DNA, and Dinosaurs.
	  3. Facilitates selecting an item to carry via CarryController.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Modules.Types)
local ItemUtils = require(ReplicatedStorage.Modules.ItemUtils)

local InventoryController = {}

local CarryController = nil
local localInventory: { Types.ItemData } = {}

-- Custom BindableEvent for local subscribers (e.g. Inventory UI)
local inventoryChangedEvent = Instance.new("BindableEvent")
InventoryController.InventoryChanged = inventoryChangedEvent.Event

-------------------------------------------------------------------------
-- PUBLIC QUERIES
-------------------------------------------------------------------------

--- Returns a copy of the current local inventory.
function InventoryController.getInventory(): { Types.ItemData }
	return table.clone(localInventory)
end

--- Returns a single item from local inventory by ItemUID.
function InventoryController.getItem(itemUID: string): Types.ItemData?
	local item = ItemUtils.findItemByUID(localInventory, itemUID)
	return item
end

--- Returns all Fossil items currently in inventory.
function InventoryController.getFossils(): { Types.ItemData }
	return ItemUtils.filterByType(localInventory, "Fossil")
end

--- Returns all DNA items currently in inventory.
function InventoryController.getDNA(): { Types.ItemData }
	return ItemUtils.filterByType(localInventory, "DNA")
end

--- Returns all Dinosaur items currently in inventory.
function InventoryController.getDinosaurs(): { Types.ItemData }
	return ItemUtils.filterByType(localInventory, "Dinosaur")
end

-------------------------------------------------------------------------
-- SELECTION / CARRY TOGGLE
-------------------------------------------------------------------------

--- Toggles carrying an item.
-- If the item is already being carried, unequips it.
-- Otherwise, requests CarryController to carry it.
function InventoryController.selectItem(itemUID: string)
	if not CarryController then return end

	if CarryController.getCarriedUID() == itemUID then
		CarryController.dropItem()
	else
		CarryController.carryItem(itemUID)
	end
end

-------------------------------------------------------------------------
-- INITIALIZATION
-------------------------------------------------------------------------

function InventoryController.init()
	local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10) :: Folder?
	local remoteFunctions = ReplicatedStorage:WaitForChild("RemoteFunctions", 10) :: Folder?

	CarryController = require(script.Parent:WaitForChild("CarryController"))

	-- Listen for real-time inventory updates from server
	if remoteEvents then
		local inventoryUpdated = remoteEvents:WaitForChild("InventoryUpdated", 5) :: RemoteEvent?
		if inventoryUpdated then
			inventoryUpdated.OnClientEvent:Connect(function(newInventory: { Types.ItemData })
				localInventory = newInventory or {}
				print(string.format("[InventoryController] Inventory updated (%d items).", #localInventory))
				inventoryChangedEvent:Fire(localInventory)
			end)
		end
	end

	-- Initial fallback fetch via RemoteFunction if not yet populated
	task.defer(function()
		if #localInventory == 0 and remoteFunctions then
			local getInventoryFunc = remoteFunctions:FindFirstChild("GetInventory") :: RemoteFunction?
			if getInventoryFunc then
				local fetched = getInventoryFunc:InvokeServer()
				if fetched and typeof(fetched) == "table" and #localInventory == 0 then
					localInventory = fetched
					inventoryChangedEvent:Fire(localInventory)
				end
			end
		end
	end)

	print("[InventoryController] Initialized.")
end

return InventoryController

