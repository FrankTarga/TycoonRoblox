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
		Icon = "rbxassetid://0", -- placeholder
		ModelName = "TRexToothModel",
		Description = "A massive fossilized tooth from a Tyrannosaurus Rex.",
	},
	-- Future fossils — add entries here to expand content:
	-- TREX_CLAW    = { FossilID = "TREX_CLAW",    DinosaurID = "TREX", ... },
	-- RAPTOR_CLAW  = { FossilID = "RAPTOR_CLAW",  DinosaurID = "VELOCIRAPTOR", ... },
	-- TRIKE_HORN   = { FossilID = "TRIKE_HORN",   DinosaurID = "TRICERATOPS", ... },
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

