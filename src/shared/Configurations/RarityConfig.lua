--!strict
--[[
	RarityConfig
	Centralized rarity level definitions.
	Used by excavation, fossil, and dinosaur systems.
]]

local RarityConfig = {}

export type RarityInfo = {
	Name: string,
	Order: number,
	Color: Color3,
	Weight: number,           -- Base drop weight (higher = more common)
	ValueMultiplier: number,  -- Multiplier applied to item sell value
	IncomeMultiplier: number, -- Multiplier applied to dinosaur income
}

RarityConfig.Rarities: { [string]: RarityInfo } = {
	Common = {
		Name = "Common",
		Order = 1,
		Color = Color3.fromRGB(180, 180, 180),
		Weight = 50,
		ValueMultiplier = 1.0,
		IncomeMultiplier = 1.0,
	},
	Uncommon = {
		Name = "Uncommon",
		Order = 2,
		Color = Color3.fromRGB(30, 200, 30),
		Weight = 25,
		ValueMultiplier = 1.5,
		IncomeMultiplier = 1.5,
	},
	Rare = {
		Name = "Rare",
		Order = 3,
		Color = Color3.fromRGB(30, 100, 255),
		Weight = 12,
		ValueMultiplier = 2.5,
		IncomeMultiplier = 2.5,
	},
	Epic = {
		Name = "Epic",
		Order = 4,
		Color = Color3.fromRGB(160, 30, 255),
		Weight = 5,
		ValueMultiplier = 5.0,
		IncomeMultiplier = 5.0,
	},
	Legendary = {
		Name = "Legendary",
		Order = 5,
		Color = Color3.fromRGB(255, 180, 0),
		Weight = 2,
		ValueMultiplier = 10.0,
		IncomeMultiplier = 10.0,
	},
	Mythic = {
		Name = "Mythic",
		Order = 6,
		Color = Color3.fromRGB(255, 50, 50),
		Weight = 0.5,
		ValueMultiplier = 25.0,
		IncomeMultiplier = 25.0,
	},
}

--- Returns rarities sorted by Order (ascending).
function RarityConfig.getSortedRarities(): { RarityInfo }
	local sorted: { RarityInfo } = {}
	for _, info in RarityConfig.Rarities do
		table.insert(sorted, info)
	end
	table.sort(sorted, function(a, b)
		return a.Order < b.Order
	end)
	return sorted
end

--- Returns the RarityInfo for a given rarity name, or nil.
function RarityConfig.getRarity(name: string): RarityInfo?
	return RarityConfig.Rarities[name]
end

return RarityConfig

