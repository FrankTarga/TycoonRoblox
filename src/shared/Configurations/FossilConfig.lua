--!strict
--[[
	FossilConfig
	Centralized fossil definitions.
	Each fossil maps to a DinosaurID — a single fossil part is enough
	to identify a dinosaur and generate its corresponding DNA.
]]

local FossilConfig = {}

export type FossilInfo = {
	FossilID: string,
	Name: string,
	Rarity: string,       -- Must match a key in RarityConfig.Rarities
	DinosaurID: string,    -- Which dinosaur this fossil produces DNA for
	Value: number,         -- Base sell value
	Icon: string,          -- Asset ID for UI
	ModelName: string,     -- Name of the 3D model in Assets
	Description: string,
}

FossilConfig.Fossils: { [string]: FossilInfo } = {
	TREX_TOOTH = {
		FossilID = "TREX_TOOTH",
		Name = "T-Rex Tooth",
		Rarity = "Common",
		DinosaurID = "TREX",
		Value = 5,
		Icon = "rbxassetid://0",
		ModelName = "TRexToothModel",
		Description = "A massive fossilized tooth from a Tyrannosaurus Rex.",
	},
	RAPTOR_CLAW = {
		FossilID = "RAPTOR_CLAW",
		Name = "Velociraptor Claw",
		Rarity = "Uncommon",
		DinosaurID = "VELOCIRAPTOR",
		Value = 15,
		Icon = "rbxassetid://0",
		ModelName = "RaptorClawModel",
		Description = "A sickle-shaped predatory claw from a nimble Velociraptor.",
	},
	TRICERATOPS_HORN = {
		FossilID = "TRICERATOPS_HORN",
		Name = "Triceratops Horn",
		Rarity = "Rare",
		DinosaurID = "TRICERATOPS",
		Value = 35,
		Icon = "rbxassetid://0",
		ModelName = "TriceratopsHornModel",
		Description = "A formidable brow horn preserved from a giant Triceratops.",
	},
	SPINOSAURUS_SPINE = {
		FossilID = "SPINOSAURUS_SPINE",
		Name = "Spinosaurus Neural Spine",
		Rarity = "Epic",
		DinosaurID = "SPINOSAURUS",
		Value = 80,
		Icon = "rbxassetid://0",
		ModelName = "SpinosaurusSpineModel",
		Description = "An immense vertebral sail spine from an amphibious super-predator.",
	},
}

--- Returns a single fossil definition by ID, or nil.
function FossilConfig.getFossil(fossilID: string): FossilInfo?
	return FossilConfig.Fossils[fossilID]
end

--- Returns all fossils that produce DNA for the given dinosaur.
function FossilConfig.getFossilsByDinosaur(dinosaurID: string): { FossilInfo }
	local result: { FossilInfo } = {}
	for _, fossil in FossilConfig.Fossils do
		if fossil.DinosaurID == dinosaurID then
			table.insert(result, fossil)
		end
	end
	return result
end

--- Returns all fossils of a given rarity.
function FossilConfig.getFossilsByRarity(rarity: string): { FossilInfo }
	local result: { FossilInfo } = {}
	for _, fossil in FossilConfig.Fossils do
		if fossil.Rarity == rarity then
			table.insert(result, fossil)
		end
	end
	return result
end

--- Returns a flat list of all FossilIDs.
function FossilConfig.getAllFossilIDs(): { string }
	local ids: { string } = {}
	for id in FossilConfig.Fossils do
		table.insert(ids, id)
	end
	return ids
end

return FossilConfig

