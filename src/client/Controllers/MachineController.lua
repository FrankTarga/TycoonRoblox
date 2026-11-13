--!strict
--[[
	MachineController
	Client-side controller for all physical machine interactions.
	Handles DNA Extractor (Phase 5) and Incubator (Phase 6).

	For DNA Extractor:
	  - "ExtractorInsertPrompt" → fires RequestUseMachine (machineInst, "DNA_EXTRACTOR")
	  - "ExtractorCollectPrompt" → fires RequestCollectOutput (machineInst, "DNA_EXTRACTOR")
	  - Listens to MachineStateUpdated for feedback and UI updates.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Types = require(ReplicatedStorage.Modules.Types)
local ItemUtils = require(ReplicatedStorage.Modules.ItemUtils)

local MachineController = {}

local player = Players.LocalPlayer
local CarryController = nil

local requestUseMachineRemote: RemoteEvent? = nil
local requestCollectOutputRemote: RemoteEvent? = nil
local machineStateUpdatedRemote: RemoteEvent? = nil

-- Simple client-side state to prevent spamming
local pendingMachineRequest = false

-------------------------------------------------------------------------
-- FEEDBACK HELPER
-------------------------------------------------------------------------

local function showMachineFeedback(machineID: string, success: boolean, msg: string)
	local tag = if success then "[Machine OK]" else "[Machine INFO]"
	print(string.format("%s [%s] %s", tag, machineID, msg))
end

-------------------------------------------------------------------------
-- PROXIMITY PROMPT DISPATCHER
-------------------------------------------------------------------------

local function onPromptTriggered(prompt: ProximityPrompt, triggeredPlayer: Player)
	if triggeredPlayer ~= player then return end
	if pendingMachineRequest then return end

	local machine = prompt.Parent
	if not machine then return end

	-- -----------------------------------------------------------
	-- DNA EXTRACTOR — Insert Fossil
	-- -----------------------------------------------------------
	if prompt.Name == "ExtractorInsertPrompt" then
		if not CarryController then return end

		local carried = CarryController.getCarriedItem()
		if not carried then
			showMachineFeedback("DNA_EXTRACTOR", false, "Pick up a cleaned fossil first.")
			return
		end
		if carried.ItemType ~= "Fossil" then
			showMachineFeedback("DNA_EXTRACTOR", false, "DNA Extractor only accepts fossils.")
			return
		end
		if not carried.IsCleaned then
			showMachineFeedback("DNA_EXTRACTOR", false,
				"This fossil hasn't been cleaned yet. Take it to the Cleaning Station first.")
			return
		end

		pendingMachineRequest = true
		if requestUseMachineRemote then
			requestUseMachineRemote:FireServer(machine, "DNA_EXTRACTOR")
		end
		task.delay(1.5, function() pendingMachineRequest = false end)

	-- -----------------------------------------------------------
	-- DNA EXTRACTOR — Collect DNA
	-- -----------------------------------------------------------
	elseif prompt.Name == "ExtractorCollectPrompt" then
		pendingMachineRequest = true
		if requestCollectOutputRemote then
			requestCollectOutputRemote:FireServer(machine, "DNA_EXTRACTOR")
		end
		task.delay(1.5, function() pendingMachineRequest = false end)
	end
end

-------------------------------------------------------------------------
-- SERVER STATE UPDATE HANDLER
-------------------------------------------------------------------------

type MachineStatePayload = {
	MachineID: string,
	State: string?,
	InputDinosaurID: string?,
	InputRarity: string?,
	StartTime: number?,
	ProcessingTime: number?,
	HasOutput: boolean?,
	Error: string?,
}

local function onMachineStateUpdated(payload: MachineStatePayload)
	if payload.Error then
		showMachineFeedback(payload.MachineID, false, payload.Error)
		pendingMachineRequest = false
		return
	end

	if payload.MachineID == "DNA_EXTRACTOR" then
		if payload.State == "Processing" then
			local dinoName = payload.InputDinosaurID or "Dinosaur"
			showMachineFeedback("DNA_EXTRACTOR", true,
				string.format("Extracting %s DNA... (%.0fs)", dinoName, payload.ProcessingTime or 15))

		elseif payload.State == "OutputReady" then
			showMachineFeedback("DNA_EXTRACTOR", true,
				"DNA Extraction complete! Walk up and collect your DNA sample.")

		elseif payload.State == "Idle" then
			if payload.HasOutput == nil then
				showMachineFeedback("DNA_EXTRACTOR", true, "DNA collected and added to inventory!")
			else
				showMachineFeedback("DNA_EXTRACTOR", true, "DNA Extractor is ready.")
			end
		end
	end
end

-------------------------------------------------------------------------
-- INITIALIZATION
-------------------------------------------------------------------------

function MachineController.init()
	local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10) :: Folder?
	CarryController = require(script.Parent:WaitForChild("CarryController"))

	if remoteEvents then
		requestUseMachineRemote    = remoteEvents:WaitForChild("RequestUseMachine", 5) :: RemoteEvent?
		requestCollectOutputRemote = remoteEvents:WaitForChild("RequestCollectOutput", 5) :: RemoteEvent?
		machineStateUpdatedRemote  = remoteEvents:WaitForChild("MachineStateUpdated", 5) :: RemoteEvent?

		if machineStateUpdatedRemote then
			machineStateUpdatedRemote.OnClientEvent:Connect(onMachineStateUpdated)
		end
	end

	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)

	print("[MachineController] Initialized.")
end

return MachineController
