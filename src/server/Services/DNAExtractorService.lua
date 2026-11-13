--!strict
--[[
	DNAExtractorService
	Authoritative server service for the DNA Extractor machine.

	State Machine (per player):
	  Idle → (insertItem) → Processing → (timer completes) → OutputReady → (collectDNA) → Idle

	Key Rules (from PROJECT_CONTEXT.txt §8):
	  1. Only cleaned fossils are accepted.
	  2. The fossil is consumed from carrying state and inventory on insertion.
	  3. The fossil appears visually INSIDE the machine (future 3D phase).
	  4. DNA appears physically at the machine output on completion.
	  5. DNA does NOT automatically enter the inventory — player must manually collect it.
	  6. Machine must be Idle before accepting a new fossil.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

-- Shared modules & configs
local Types = require(ReplicatedStorage.Modules.Types)
local ItemUtils = require(ReplicatedStorage.Modules.ItemUtils)
local MachineConfig = require(ReplicatedStorage.Configurations.MachineConfig)
local EconomyConfig = require(ReplicatedStorage.Configurations.EconomyConfig)

local DNAExtractorService = {}

-- Service dependencies (injected in init)
local DataService = nil
local InventoryService = nil
local CarryingService = nil

-- Remotes
local remoteEventsFolder: Folder? = nil
local requestUseMachineRemote: RemoteEvent? = nil
local requestCollectOutputRemote: RemoteEvent? = nil
local machineStateUpdatedRemote: RemoteEvent? = nil
local xpUpdatedRemote: RemoteEvent? = nil
local levelUpdatedRemote: RemoteEvent? = nil

-- Constants
local MACHINE_ID = "DNA_EXTRACTOR"
local MAX_INTERACTION_DISTANCE = 16
local MACHINE_TAG = "DNAExtractor"

export type ExtractorState = {
	State: string,            -- Idle | Processing | OutputReady
	InputItemUID: string?,
	InputDinosaurID: string?,
	InputRarity: string?,
	InputQuality: number?,
	StartTime: number?,
	PendingDNAItem: Types.ItemData?, -- Available for collection when OutputReady
}

-- Per-player machine states: UserId → ExtractorState
local machineStates: { [number]: ExtractorState } = {}

-- Active processing tasks: UserId → thread
local processingTasks: { [number]: thread } = {}

-------------------------------------------------------------------------
-- INTERNAL HELPERS
-------------------------------------------------------------------------

local function getDefaultState(): ExtractorState
	return {
		State = MachineConfig.States.Idle,
		InputItemUID = nil,
		InputDinosaurID = nil,
		InputRarity = nil,
		InputQuality = nil,
		StartTime = nil,
		PendingDNAItem = nil,
	}
end

local function getState(userId: number): ExtractorState
	if not machineStates[userId] then
		machineStates[userId] = getDefaultState()
	end
	return machineStates[userId]
end

local function fireStateUpdate(userId: number)
	if not machineStateUpdatedRemote then return end
	local player = Players:GetPlayerByUserId(userId)
	if not player then return end

	local state = getState(userId)
	machineStateUpdatedRemote:FireClient(player, {
		MachineID = MACHINE_ID,
		State = state.State,
		InputDinosaurID = state.InputDinosaurID,
		InputRarity = state.InputRarity,
		StartTime = state.StartTime,
		ProcessingTime = MachineConfig.Machines[MACHINE_ID].BaseProcessingTime,
		HasOutput = state.PendingDNAItem ~= nil,
	})
end

local function fireXPUpdate(userId: number, data: Types.PlayerData)
	data.XP += EconomyConfig.XPPerExtraction
	data.Statistics.TotalDNAExtracted += 1

	local player = Players:GetPlayerByUserId(userId)
	if not player then return end

	if xpUpdatedRemote then
		xpUpdatedRemote:FireClient(player, data.XP)
	end

	local nextLevel = data.Level + 1
	if nextLevel <= EconomyConfig.MaxLevel then
		local xpNeeded = EconomyConfig.getXPForLevel(nextLevel)
		if data.XP >= xpNeeded then
			data.Level = nextLevel
			if levelUpdatedRemote then
				levelUpdatedRemote:FireClient(player, data.Level)
			end
			print(string.format("[DNAExtractorService] Player %d leveled up to Level %d!", userId, nextLevel))
		end
	end
end

local function getStationPosition(machine: Instance): Vector3?
	if machine:IsA("BasePart") then
		return machine.Position
	elseif machine:IsA("Model") then
		local primary = machine.PrimaryPart or machine:FindFirstChildWhichIsA("BasePart")
		return if primary then primary.Position else nil
	end
	return nil
end

-------------------------------------------------------------------------
-- PUBLIC API — MACHINE STATE
-------------------------------------------------------------------------

--- Returns the current ExtractorState for a player (read-only snapshot).
function DNAExtractorService.getMachineState(userId: number): ExtractorState
	return getState(userId)
end

--- Resets a player's machine to Idle — used in tests and on player leave.
function DNAExtractorService.resetMachine(userId: number)
	-- Cancel any in-flight processing task
	if processingTasks[userId] then
		task.cancel(processingTasks[userId])
		processingTasks[userId] = nil
	end
	machineStates[userId] = getDefaultState()
end

--- TEST HOOK: Forces the machine directly into OutputReady, bypassing the timer.
-- Only called in unit tests or by the test runner; never called by gameplay code.
function DNAExtractorService.forceCompleteProcessing(userId: number)
	local state = getState(userId)
	if state.State ~= MachineConfig.States.Processing then return end

	-- Cancel running task
	if processingTasks[userId] then
		task.cancel(processingTasks[userId])
		processingTasks[userId] = nil
	end

	-- Build the DNA item that would have been produced
	local dnaItem = ItemUtils.createDNAItem({
		ItemUID = state.InputItemUID or "FORCE_TEST",
		ItemType = "Fossil",
		ConfigID = "TREX_TOOTH",
		DinosaurID = state.InputDinosaurID or "TREX",
		Rarity = state.InputRarity or "Common",
		Quality = state.InputQuality or 80,
		IsCleaned = true,
		ObtainedAt = os.time(),
	})

	state.State = MachineConfig.States.OutputReady
	state.PendingDNAItem = dnaItem
	state.StartTime = nil

	fireStateUpdate(userId)
end

-------------------------------------------------------------------------
-- PUBLIC API — GAMEPLAY OPERATIONS
-------------------------------------------------------------------------

--- Validates and inserts the player's currently carried fossil into the DNA Extractor.
function DNAExtractorService.insertItem(userId: number, machine: Instance?): (boolean, string?)
	if not CarryingService or not InventoryService or not DataService then
		return false, "Services unavailable"
	end

	-- 1. Validate that the player is carrying an item
	local item = CarryingService.getCarriedItem(userId)
	if not item then
		return false, "No item is being carried"
	end

	-- 2. Validate item compatibility with DNA Extractor
	if not ItemUtils.isCompatibleWithMachine(item, MACHINE_ID) then
		if item.ItemType == "Fossil" and not item.IsCleaned then
			return false, "Fossil must be cleaned before DNA extraction"
		end
		return false, "DNA Extractor only accepts cleaned fossils"
	end

	-- 3. Validate machine is Idle
	local state = getState(userId)
	if state.State ~= MachineConfig.States.Idle then
		return false, "Machine is not Idle"
	end

	-- 4. Validate physical distance if a machine instance is provided
	if machine then
		if not machine:IsDescendantOf(workspace) then
			return false, "Invalid machine instance"
		end

		local machinePos = getStationPosition(machine)
		if machinePos then
			local player = Players:GetPlayerByUserId(userId)
			if player and player.Character then
				local root = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and (root.Position - machinePos).Magnitude > MAX_INTERACTION_DISTANCE then
					return false, "Too far from DNA Extractor"
				end
			end
		end
	end

	-- 5. Consume the fossil from inventory and carrying state
	local consumed = CarryingService.consumeCarriedItem(userId)
	if not consumed then
		return false, "Failed to consume carried item"
	end

	-- 6. Transition to Processing
	local machineInfo = MachineConfig.getMachine(MACHINE_ID)
	local processingTime = if machineInfo then machineInfo.BaseProcessingTime else 15

	state.State = MachineConfig.States.Processing
	state.InputItemUID = consumed.ItemUID
	state.InputDinosaurID = consumed.DinosaurID
	state.InputRarity = consumed.Rarity
	state.InputQuality = consumed.Quality
	state.StartTime = os.time()
	state.PendingDNAItem = nil

	fireStateUpdate(userId)

	print(string.format("[DNAExtractorService] Player %d started extraction — %s (%s), %.0fs",
		userId, consumed.DinosaurID, consumed.Rarity, processingTime))

	-- 7. Schedule completion after processing time
	processingTasks[userId] = task.delay(processingTime, function()
		processingTasks[userId] = nil

		-- Build the pending DNA item
		local dnaItem = ItemUtils.createDNAItem(consumed)
		if not dnaItem then
			warn("[DNAExtractorService] Failed to create DNA item for player", userId)
			machineStates[userId] = getDefaultState()
			fireStateUpdate(userId)
			return
		end

		local currentState = getState(userId)
		if currentState.State ~= MachineConfig.States.Processing then
			-- Machine was reset while processing (player left, etc.) — abort
			return
		end

		currentState.State = MachineConfig.States.OutputReady
		currentState.PendingDNAItem = dnaItem
		currentState.StartTime = nil

		fireStateUpdate(userId)

		print(string.format("[DNAExtractorService] Player %d extraction complete — DNA ready for collection!", userId))
	end)

	return true, "Processing started"
end

--- Authoritatively collects the pending DNA output from the DNA Extractor.
-- The player must manually walk up and collect — DNA is NEVER auto-added to inventory.
function DNAExtractorService.collectDNA(userId: number, machine: Instance?): (boolean, any)
	local state = getState(userId)

	if state.State ~= MachineConfig.States.OutputReady or not state.PendingDNAItem then
		return false, "No DNA available to collect"
	end

	-- Validate physical distance if machine instance provided
	if machine then
		if not machine:IsDescendantOf(workspace) then
			return false, "Invalid machine instance"
		end

		local machinePos = getStationPosition(machine)
		if machinePos then
			local player = Players:GetPlayerByUserId(userId)
			if player and player.Character then
				local root = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and (root.Position - machinePos).Magnitude > MAX_INTERACTION_DISTANCE then
					return false, "Too far from DNA Extractor"
				end
			end
		end
	end

	-- Extract the pending DNA
	local dnaItem = state.PendingDNAItem :: Types.ItemData

	-- Add to player inventory
	local added = InventoryService.addItem(userId, dnaItem)
	if not added then
		return false, "Could not add DNA to inventory"
	end

	-- Award XP
	local data = DataService.getPlayerData(userId)
	if data then
		fireXPUpdate(userId, data)
	end

	-- Reset machine to Idle
	machineStates[userId] = getDefaultState()
	fireStateUpdate(userId)

	print(string.format("[DNAExtractorService] Player %d collected %s DNA (UID: %s)",
		userId, dnaItem.DinosaurID, dnaItem.ItemUID))

	return true, dnaItem
end

-------------------------------------------------------------------------
-- WORLD — AUTO-PROVISION & PROMPTS
-------------------------------------------------------------------------

local function attachPromptsToMachine(machine: Instance)
	local basePart: BasePart? = nil
	if machine:IsA("BasePart") then
		basePart = machine
	elseif machine:IsA("Model") then
		basePart = machine.PrimaryPart or machine:FindFirstChildWhichIsA("BasePart")
	end
	if not basePart then return end

	-- Insert prompt if none exists
	if not basePart:FindFirstChildWhichIsA("ProximityPrompt") then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ExtractorInsertPrompt"
		prompt.ActionText = "Insert Fossil"
		prompt.ObjectText = "DNA Extractor"
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = basePart

		-- Second prompt for collecting DNA (always visible; service validates state)
		local collectPrompt = Instance.new("ProximityPrompt")
		collectPrompt.Name = "ExtractorCollectPrompt"
		collectPrompt.ActionText = "Collect DNA"
		collectPrompt.ObjectText = "DNA Extractor"
		collectPrompt.HoldDuration = 0
		collectPrompt.MaxActivationDistance = 10
		collectPrompt.RequiresLineOfSight = false
		collectPrompt.Parent = basePart
	end
end

local function setupDefaultMachine()
	local machinesFolder = workspace:FindFirstChild("Machines")
	if not machinesFolder then
		machinesFolder = Instance.new("Folder")
		machinesFolder.Name = "Machines"
		machinesFolder.Parent = workspace
	end

	local tagged = CollectionService:GetTagged(MACHINE_TAG)
	local existing = machinesFolder:FindFirstChild("DNAExtractorMachine")

	if #tagged == 0 and not existing then
		-- Auto-provision a placeholder machine
		local machine = Instance.new("Part")
		machine.Name = "DNAExtractorMachine"
		machine.Size = Vector3.new(5, 4, 4)
		machine.Position = Vector3.new(28, 2, 0)
		machine.Anchored = true
		machine.CanCollide = true
		machine.Material = Enum.Material.Metal
		machine.Color = Color3.fromRGB(0, 120, 180)
		machine:SetAttribute("MachineID", MACHINE_ID)
		machine.Parent = machinesFolder

		CollectionService:AddTag(machine, MACHINE_TAG)
		attachPromptsToMachine(machine)
		print("[DNAExtractorService] Auto-provisioned placeholder DNA Extractor at (28, 2, 0).")
	else
		for _, m in tagged do attachPromptsToMachine(m) end
		if existing then attachPromptsToMachine(existing) end
	end
end

-------------------------------------------------------------------------
-- INITIALIZATION
-------------------------------------------------------------------------

function DNAExtractorService.init()
	DataService = require(ServerScriptService.Services.DataService)
	InventoryService = require(ServerScriptService.Services.InventoryService)
	CarryingService = require(ServerScriptService.Services.CarryingService)

	remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10) :: Folder?
	if remoteEventsFolder then
		requestUseMachineRemote    = remoteEventsFolder:WaitForChild("RequestUseMachine", 5) :: RemoteEvent?
		requestCollectOutputRemote = remoteEventsFolder:WaitForChild("RequestCollectOutput", 5) :: RemoteEvent?
		machineStateUpdatedRemote  = remoteEventsFolder:WaitForChild("MachineStateUpdated", 5) :: RemoteEvent?
		xpUpdatedRemote            = remoteEventsFolder:WaitForChild("XPUpdated", 5) :: RemoteEvent?
		levelUpdatedRemote         = remoteEventsFolder:WaitForChild("LevelUpdated", 5) :: RemoteEvent?

		if requestUseMachineRemote then
			requestUseMachineRemote.OnServerEvent:Connect(function(player: Player, machineInst: any, machineIDArg: any)
				if typeof(machineIDArg) ~= "string" or machineIDArg ~= MACHINE_ID then return end
				local inst = if typeof(machineInst) == "Instance" then machineInst else nil
				local success, result = DNAExtractorService.insertItem(player.UserId, inst)
				if not success and machineStateUpdatedRemote then
					machineStateUpdatedRemote:FireClient(player, {
						MachineID = MACHINE_ID,
						Error = tostring(result),
					})
				end
			end)
		end

		if requestCollectOutputRemote then
			requestCollectOutputRemote.OnServerEvent:Connect(function(player: Player, machineInst: any, machineIDArg: any)
				if typeof(machineIDArg) ~= "string" or machineIDArg ~= MACHINE_ID then return end
				local inst = if typeof(machineInst) == "Instance" then machineInst else nil
				local success, result = DNAExtractorService.collectDNA(player.UserId, inst)
				if not success and machineStateUpdatedRemote then
					machineStateUpdatedRemote:FireClient(player, {
						MachineID = MACHINE_ID,
						Error = tostring(result),
					})
				end
			end)
		end
	end

	-- New tagged machines get prompts automatically
	CollectionService:GetInstanceAddedSignal(MACHINE_TAG):Connect(function(m)
		attachPromptsToMachine(m)
	end)

	setupDefaultMachine()

	-- Clean up on player leave
	Players.PlayerRemoving:Connect(function(player)
		DNAExtractorService.resetMachine(player.UserId)
	end)

	print("[DNAExtractorService] Initialized.")
end

return DNAExtractorService

