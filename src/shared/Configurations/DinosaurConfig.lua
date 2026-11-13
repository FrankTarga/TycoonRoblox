--!strict
--[[
	DinosaurConfig
	Centralized dinosaur definitions.
	Each dinosaur has unique income, rarity, and incubation values.
]]

local DinosaurConfig = {}

export type DinosaurInfo = {
	DinosaurID: string,
	Name: string,
	Rarity: string,          -- Must match a key in RarityConfig.Rarities
	BaseIncome: number,      -- Income per collection cycle
	IncubationTime: number,  -- Seconds to incubate from DNA
	ModelName: string,       -- Name of the 3D model in Assets
	Icon: string,            -- Asset ID for UI
	Description: string,
}

DinosaurConfig.Dinosaurs: { [string]: DinosaurInfo } = {
	TREX = {
		DinosaurID = "TREX",
		Name = "Tyrannosaurus Rex",
		Rarity = "Common",
		BaseIncome = 10,
		IncubationTime = 30,
		ModelName = "TRexModel",
		Icon = "rbxassetid://0", -- placeholder
		Description = "The king of dinosaurs. Generates steady income.",
	},
	-- Future dinosaurs — add entries here to expand content:
	-- VELOCIRAPTOR = { DinosaurID = "VELOCIRAPTOR", Rarity = "Uncommon", BaseIncome = 18, ... },
	-- TRICERATOPS  = { DinosaurID = "TRICERATOPS",  Rarity = "Rare",     BaseIncome = 30, ... },
	-- STEGOSAURUS  = { DinosaurID = "STEGOSAURUS",  Rarity = "Uncommon", BaseIncome = 15, ... },
	-- SPINOSAURUS  = { DinosaurID = "SPINOSAURUS",  Rarity = "Epic",     BaseIncome = 55, ... },
}

--- Returns a single dinosaur definition by ID, or nil.
function DinosaurConfig.getDinosaur(dinosaurID: string): DinosaurInfo?
	return DinosaurConfig.Dinosaurs[dinosaurID]
end

--- Returns all dinosaurs of a given rarity.
function DinosaurConfig.getDinosaursByRarity(rarity: string): { DinosaurInfo }
	local result: { DinosaurInfo } = {}
	for _, dino in DinosaurConfig.Dinosaurs do
		if dino.Rarity == rarity then
			table.insert(result, dino)
		end
	end
	return result
end

--- Returns a flat list of all DinosaurIDs.
function DinosaurConfig.getAllDinosaurIDs(): { string }
	local ids: { string } = {}
	for id in DinosaurConfig.Dinosaurs do
		table.insert(ids, id)
	end
	return ids
end

return DinosaurConfig

