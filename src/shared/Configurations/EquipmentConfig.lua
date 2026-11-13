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
		Icon = "rbxassetid://0", -- placeholder
		Description = "A simple shovel for basic excavation.",
	},
	-- IRON_SHOVEL   = { EquipmentID = "IRON_SHOVEL",   Type = "Shovel", Tier = 2, ... },
	-- GOLDEN_SHOVEL = { EquipmentID = "GOLDEN_SHOVEL", Type = "Shovel", Tier = 3, ... },

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
		Icon = "rbxassetid://0", -- placeholder
		Description = "A simple brush for cleaning fossils.",
	},
	-- FINE_BRUSH    = { EquipmentID = "FINE_BRUSH",    Type = "Brush", Tier = 2, ... },
	-- DIAMOND_BRUSH = { EquipmentID = "DIAMOND_BRUSH", Type = "Brush", Tier = 3, ... },
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

