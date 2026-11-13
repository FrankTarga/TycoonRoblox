--!strict
--[[
	MachineConfig
	Definitions for plot machines (DNA Extractor, Incubator).
	Controls accepted item types, processing times, and output behavior.
]]

local MachineConfig = {}

export type MachineInfo = {
	MachineID: string,
	Name: string,
	AcceptedItemType: string,     -- "Fossil" | "DNA"
	OutputItemType: string,       -- "DNA" | "Dinosaur"
	BaseProcessingTime: number,   -- Seconds
	RequiresCleanedInput: boolean,
	AutoCollectOutput: boolean,   -- false = player must manually collect
	Description: string,
}

MachineConfig.Machines: { [string]: MachineInfo } = {
	DNA_EXTRACTOR = {
		MachineID = "DNA_EXTRACTOR",
		Name = "DNA Extractor",
		AcceptedItemType = "Fossil",
		OutputItemType = "DNA",
		BaseProcessingTime = 15,
		RequiresCleanedInput = true,  -- Fossil must be cleaned first
		AutoCollectOutput = false,    -- Player must manually collect DNA
		Description = "Extracts dinosaur DNA from cleaned fossils.",
	},
	INCUBATOR = {
		MachineID = "INCUBATOR",
		Name = "Dinosaur Incubator",
		AcceptedItemType = "DNA",
		OutputItemType = "Dinosaur",
		BaseProcessingTime = 30,
		RequiresCleanedInput = false,
		AutoCollectOutput = true,     -- Dinosaur goes to inventory automatically
		Description = "Incubates dinosaur DNA into a living dinosaur.",
	},
}

-- Machine state constants
MachineConfig.States = {
	Idle        = "Idle",
	Processing  = "Processing",
	OutputReady = "OutputReady",  -- Used by DNA Extractor (manual collection)
	Completed   = "Completed",   -- Used by Incubator (auto-collect)
}

--- Returns a single machine definition by ID, or nil.
function MachineConfig.getMachine(machineID: string): MachineInfo?
	return MachineConfig.Machines[machineID]
end

return MachineConfig

