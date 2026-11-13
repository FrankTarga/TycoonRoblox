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
		Icon = "rbxassetid://0",
		Description = "The king of dinosaurs. Generates steady income.",
	},
	VELOCIRAPTOR = {
		DinosaurID = "VELOCIRAPTOR",
		Name = "Velociraptor",
		Rarity = "Uncommon",
		BaseIncome = 18,
		IncubationTime = 40,
		ModelName = "VelociraptorModel",
		Icon = "rbxassetid://0",
		Description = "A swift and cunning hunter with sharp claws.",
	},
	TRICERATOPS = {
		DinosaurID = "TRICERATOPS",
		Name = "Triceratops",
		Rarity = "Rare",
		BaseIncome = 30,
		IncubationTime = 50,
		ModelName = "TriceratopsModel",
		Icon = "rbxassetid://0",
		Description = "A mighty three-horned herbivore with strong crowd appeal.",
	},
	SPINOSAURUS = {
		DinosaurID = "SPINOSAURUS",
		Name = "Spinosaurus",
		Rarity = "Epic",
		BaseIncome = 55,
		IncubationTime = 75,
		ModelName = "SpinosaurusModel",
		Icon = "rbxassetid://0",
		Description = "An apex predatory leviathan with an imposing sail.",
	},
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

