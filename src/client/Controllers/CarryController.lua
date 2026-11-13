--!strict
--[[
	CarryController
	Client-side controller for tracking and managing the physically carried item.

	Responsibilities:
	  1. Receives authoritative carry state updates from CarryingService via CarryStateChanged.
	  2. Sends carry/drop requests to the server via RequestCarryItem.
	  3. Exposes signals and query methods for UI and physical interaction controllers.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Modules.Types)
local ItemUtils = require(ReplicatedStorage.Modules.ItemUtils)

local CarryController = {}

local player = Players.LocalPlayer
local requestCarryItemRemote: RemoteEvent? = nil
local carryStateChangedRemote: RemoteEvent? = nil

local currentCarriedUID: string? = nil
local currentCarriedItem: Types.ItemData? = nil

-- Custom BindableEvent for local subscribers
local carriedItemChangedEvent = Instance.new("BindableEvent")
CarryController.CarriedItemChanged = carriedItemChangedEvent.Event

-------------------------------------------------------------------------
-- PUBLIC QUERIES
-------------------------------------------------------------------------

--- Returns whether the local player is currently carrying an item.
function CarryController.isCarrying(): boolean
	return currentCarriedUID ~= nil
end

--- Returns the ItemUID of the currently carried item.
function CarryController.getCarriedUID(): string?
	return currentCarriedUID
end

--- Returns the full ItemData of the currently carried item.
function CarryController.getCarriedItem(): Types.ItemData?
	return currentCarriedItem
end

-------------------------------------------------------------------------
-- ACTIONS
-------------------------------------------------------------------------

--- Requests the server to equip and carry the specified inventory item.
function CarryController.carryItem(itemUID: string)
	if not requestCarryItemRemote then return end
	requestCarryItemRemote:FireServer(itemUID)
end

--- Requests the server to unequip and drop the currently carried item back to inventory.
function CarryController.dropItem()
	if not requestCarryItemRemote then return end
	requestCarryItemRemote:FireServer(nil)
end

-------------------------------------------------------------------------
-- INITIALIZATION
-------------------------------------------------------------------------

function CarryController.init()
	local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10) :: Folder?
	if not remoteEvents then
		warn("[CarryController] RemoteEvents folder not found!")
		return
	end

	requestCarryItemRemote = remoteEvents:WaitForChild("RequestCarryItem", 5) :: RemoteEvent?
	carryStateChangedRemote = remoteEvents:WaitForChild("CarryStateChanged", 5) :: RemoteEvent?

	if carryStateChangedRemote then
		carryStateChangedRemote.OnClientEvent:Connect(function(payload: { ItemUID: string?, ItemData: Types.ItemData? })
			currentCarriedUID = payload.ItemUID
			currentCarriedItem = payload.ItemData

			if currentCarriedItem then
				print(string.format("[CarryController] Now carrying: %s (%s)",
					ItemUtils.getDisplayName(currentCarriedItem), currentCarriedItem.Rarity))
			else
				print("[CarryController] Item unequipped / dropped.")
			end

			carriedItemChangedEvent:Fire(currentCarriedItem)
		end)
	end

	print("[CarryController] Initialized.")
end

return CarryController
