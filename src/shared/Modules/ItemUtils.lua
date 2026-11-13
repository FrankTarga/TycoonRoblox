--!strict
--[[
	ItemUtils
	Shared utility functions for creating and validating items.
	Used by both server services and client controllers.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types         = require(ReplicatedStorage.Modules.Types)
local FossilConfig  = require(ReplicatedStorage.Configurations.FossilConfig)
local DinosaurConfig = require(ReplicatedStorage.Configurations.DinosaurConfig)
local MachineConfig = require(ReplicatedStorage.Configurations.MachineConfig)
local RarityConfig  = require(ReplicatedStorage.Configurations.RarityConfig)

local ItemUtils = {}

--- Generates a unique item identifier.
function ItemUtils.generateUID(): string
	return HttpService:GenerateGUID(false)
end

----------------------------------------------------------------------
-- Item creation
----------------------------------------------------------------------

--- Creates a new Fossil item from a FossilID.
function ItemUtils.createFossilItem(fossilID: string): Types.ItemData?
	local fossilInfo = FossilConfig.getFossil(fossilID)
	if not fossilInfo then
		warn("[ItemUtils] Unknown FossilID:", fossilID)
		return nil
	end

	return {
		ItemUID    = ItemUtils.generateUID(),
		ItemType   = "Fossil",
		ConfigID   = fossilID,
		DinosaurID = fossilInfo.DinosaurID,
		Rarity     = fossilInfo.Rarity,
		Quality    = 0,
		IsCleaned  = false,
		ObtainedAt = os.time(),
	}
end

--- Creates a DNA item from a cleaned fossil item.
function ItemUtils.createDNAItem(fossilItem: Types.ItemData): Types.ItemData?
	if fossilItem.ItemType ~= "Fossil" then
		warn("[ItemUtils] Cannot create DNA from non-fossil item")
		return nil
	end

	return {
		ItemUID    = ItemUtils.generateUID(),
		ItemType   = "DNA",
		ConfigID   = fossilItem.DinosaurID .. "_DNA",
		DinosaurID = fossilItem.DinosaurID,
		Rarity     = fossilItem.Rarity,
		Quality    = fossilItem.Quality,
		IsCleaned  = false,
		ObtainedAt = os.time(),
	}
end

--- Creates a Dinosaur item from a DNA item.
function ItemUtils.createDinosaurItem(dnaItem: Types.ItemData): Types.ItemData?
	if dnaItem.ItemType ~= "DNA" then
		warn("[ItemUtils] Cannot create dinosaur from non-DNA item")
		return nil
	end

	local dinoInfo = DinosaurConfig.getDinosaur(dnaItem.DinosaurID)
	if not dinoInfo then
		warn("[ItemUtils] Unknown DinosaurID:", dnaItem.DinosaurID)
		return nil
	end

	return {
		ItemUID    = ItemUtils.generateUID(),
		ItemType   = "Dinosaur",
		ConfigID   = dnaItem.DinosaurID,
		DinosaurID = dnaItem.DinosaurID,
		Rarity     = dnaItem.Rarity,
		Quality    = dnaItem.Quality,
		IsCleaned  = false,
		ObtainedAt = os.time(),
	}
end

----------------------------------------------------------------------
-- Compatibility checks
----------------------------------------------------------------------

--- Checks if an item is compatible with a given machine.
function ItemUtils.isCompatibleWithMachine(item: Types.ItemData, machineID: string): boolean
	local machineInfo = MachineConfig.getMachine(machineID)
	if not machineInfo then return false end

	-- Check item type matches what the machine accepts
	if item.ItemType ~= machineInfo.AcceptedItemType then
		return false
	end

	-- Check cleaning requirement
	if machineInfo.RequiresCleanedInput and not item.IsCleaned then
		return false
	end

	return true
end

--- Checks if a dinosaur item can be placed in a cage.
function ItemUtils.canPlaceInCage(item: Types.ItemData): boolean
	return item.ItemType == "Dinosaur"
end

----------------------------------------------------------------------
-- Display helpers
----------------------------------------------------------------------

--- Returns the human-readable display name for any item.
function ItemUtils.getDisplayName(item: Types.ItemData): string
	if item.ItemType == "Fossil" then
		local info = FossilConfig.getFossil(item.ConfigID)
		return if info then info.Name else "Unknown Fossil"

	elseif item.ItemType == "DNA" then
		local dinoInfo = DinosaurConfig.getDinosaur(item.DinosaurID)
		return if dinoInfo then (dinoInfo.Name .. " DNA") else "Unknown DNA"

	elseif item.ItemType == "Dinosaur" then
		local dinoInfo = DinosaurConfig.getDinosaur(item.ConfigID)
		return if dinoInfo then dinoInfo.Name else "Unknown Dinosaur"
	end

	return "Unknown Item"
end

--- Returns the rarity color for an item.
function ItemUtils.getRarityColor(item: Types.ItemData): Color3
	local rarityInfo = RarityConfig.getRarity(item.Rarity)
	return if rarityInfo then rarityInfo.Color else Color3.fromRGB(180, 180, 180)
end

----------------------------------------------------------------------
-- Inventory helpers
----------------------------------------------------------------------

--- Finds an item in an inventory list by its UID. Returns item and index.
function ItemUtils.findItemByUID(inventory: { Types.ItemData }, itemUID: string): (Types.ItemData?, number?)
	for i, item in inventory do
		if item.ItemUID == itemUID then
			return item, i
		end
	end
	return nil, nil
end

--- Filters inventory by item type.
function ItemUtils.filterByType(inventory: { Types.ItemData }, itemType: string): { Types.ItemData }
	local result: { Types.ItemData } = {}
	for _, item in inventory do
		if item.ItemType == itemType then
			table.insert(result, item)
		end
	end
	return result
end

return ItemUtils

