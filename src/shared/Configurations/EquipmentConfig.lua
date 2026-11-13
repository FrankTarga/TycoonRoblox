--!strict
--[[
	EquipmentConfig
	Tools and equipment definitions (shovels, brushes).
	Includes tier, speed multipliers, luck bonuses, and unlock requirements.
]]

local EquipmentConfig = {}

export type EquipmentInfo = {
	EquipmentID: string,
	Name: string,
	Type: string,            -- "Shovel" | "Brush"
	Tier: number,
	SpeedMultiplier: number, -- Multiplier on excavation/cleaning speed
	LuckBonus: number,       -- Additive luck bonus
	Cost: number,
	RequiredLevel: number,
	Icon: string,
	Description: string,
}

EquipmentConfig.Equipment: { [string]: EquipmentInfo } = {
	---------- Shovels ----------
	BASIC_SHOVEL = {
		EquipmentID = "BASIC_SHOVEL",
		Name = "Basic Shovel",
		Type = "Shovel",
		Tier = 1,
		SpeedMultiplier = 1.0,
		LuckBonus = 0,
		Cost = 0,
		RequiredLevel = 1,
		Icon = "rbxassetid://0",
		Description = "A simple shovel for basic excavation.",
	},
	IRON_SHOVEL = {
		EquipmentID = "IRON_SHOVEL",
		Name = "Iron Shovel",
		Type = "Shovel",
		Tier = 2,
		SpeedMultiplier = 1.4,
		LuckBonus = 5,
		Cost = 250,
		RequiredLevel = 2,
		Icon = "rbxassetid://0",
		Description = "A sturdy iron shovel that digs faster with higher luck.",
	},
	GOLDEN_SHOVEL = {
		EquipmentID = "GOLDEN_SHOVEL",
		Name = "Golden Shovel",
		Type = "Shovel",
		Tier = 3,
		SpeedMultiplier = 1.8,
		LuckBonus = 15,
		Cost = 1000,
		RequiredLevel = 5,
		Icon = "rbxassetid://0",
		Description = "A lavish golden shovel with exceptional speed and luck.",
	},

	---------- Brushes ----------
	BASIC_BRUSH = {
		EquipmentID = "BASIC_BRUSH",
		Name = "Basic Brush",
		Type = "Brush",
		Tier = 1,
		SpeedMultiplier = 1.0,
		LuckBonus = 0,
		Cost = 0,
		RequiredLevel = 1,
		Icon = "rbxassetid://0",
		Description = "A simple brush for cleaning fossils.",
	},
	FINE_BRUSH = {
		EquipmentID = "FINE_BRUSH",
		Name = "Fine Brush",
		Type = "Brush",
		Tier = 2,
		SpeedMultiplier = 1.3,
		LuckBonus = 5,
		Cost = 200,
		RequiredLevel = 2,
		Icon = "rbxassetid://0",
		Description = "A delicate fine brush that cleans faster and improves fossil quality.",
	},
	DIAMOND_BRUSH = {
		EquipmentID = "DIAMOND_BRUSH",
		Name = "Diamond Brush",
		Type = "Brush",
		Tier = 3,
		SpeedMultiplier = 1.7,
		LuckBonus = 15,
		Cost = 800,
		RequiredLevel = 5,
		Icon = "rbxassetid://0",
		Description = "A masterwork brush with diamond-coated bristles for pristine fossil restoration.",
	},
}

--- Returns a single equipment definition by ID, or nil.
function EquipmentConfig.getEquipment(equipmentID: string): EquipmentInfo?
	return EquipmentConfig.Equipment[equipmentID]
end

--- Returns all equipment of a given type, sorted by tier (ascending).
function EquipmentConfig.getEquipmentByType(equipType: string): { EquipmentInfo }
	local result: { EquipmentInfo } = {}
	for _, equip in EquipmentConfig.Equipment do
		if equip.Type == equipType then
			table.insert(result, equip)
		end
	end
	table.sort(result, function(a, b)
		return a.Tier < b.Tier
	end)
	return result
end

--- Returns all equipment available at a given level, sorted by tier.
function EquipmentConfig.getAvailableEquipment(playerLevel: number): { EquipmentInfo }
	local result: { EquipmentInfo } = {}
	for _, equip in EquipmentConfig.Equipment do
		if equip.RequiredLevel <= playerLevel then
			table.insert(result, equip)
		end
	end
	table.sort(result, function(a, b)
		return a.Tier < b.Tier
	end)
	return result
end

return EquipmentConfig

