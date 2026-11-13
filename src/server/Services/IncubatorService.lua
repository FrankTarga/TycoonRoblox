--!strict
--[[
	IncubatorService
	Authoritative server service for the Dinosaur Incubator machine.

	State Machine (per player):
	  Idle → (insertItem) → Processing → (timer completes / forceComplete) → Auto-collect to Inventory → Idle

	Key Rules (from PROJECT_CONTEXT.txt §8 & §28):
	  1. Only DNA items are accepted.
	  2. The DNA item is consumed from carrying state and inventory on insertion.
	  3. AutoCollectOutput = true: When incubation finishes, the dinosaur is automatically
	     added directly to the player's inventory (no manual collection step required).
	  4. The machine resets to Idle immediately after auto-collecting.
	  5. Machine must be Idle before accepting a new DNA item.
	  6. Awards EconomyConfig.XPPerIncubation (20 XP) upon successful incubation.
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

local IncubatorService = {}

-- Service dependencies (injected in init)
local DataService = nil
local InventoryService = nil
local CarryingService = nil

-- Remotes
local remoteEventsFolder: Folder? = nil
local requestUseMachineRemote: RemoteEvent? = nil
local machineStateUpdatedRemote: RemoteEvent? = nil
local xpUpdatedRemote: RemoteEvent? = nil
local levelUpdatedRemote: RemoteEvent? = nil

-- Constants
local MACHINE_ID = "INCUBATOR"
local MAX_INTERACTION_DISTANCE = 16
local MACHINE_TAG = "Incubator"

export type IncubatorState = {
	State: string,            -- Idle | Processing
	InputItemUID: string?,
	InputDinosaurID: string?,
	InputRarity: string?,
	InputQuality: number?,
	StartTime: number?,
}

-- Per-player machine states: UserId → IncubatorState
local machineStates: { [number]: IncubatorState } = {}

-- Active processing tasks: UserId → thread
local processingTasks: { [number]: thread } = {}

-------------------------------------------------------------------------
-- INTERNAL HELPERS
-------------------------------------------------------------------------

local function getDefaultState(): IncubatorState
	return {
		State = MachineConfig.States.Idle,
		InputItemUID = nil,
		InputDinosaurID = nil,
		InputRarity = nil,
		InputQuality = nil,
		StartTime = nil,
	}
end

local function getState(userId: number): IncubatorState
	if not machineStates[userId] then
		machineStates[userId] = getDefaultState()
	end
	return machineStates[userId]
end

local function fireStateUpdate(userId: number, completedDino: Types.ItemData?)
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
		HasOutput = false,
		CompletedDinosaurID = if completedDino then completedDino.DinosaurID else nil,
		CompletedDinosaurName = if completedDino then ItemUtils.getDisplayName(completedDino) else nil,
	})
end

local function fireXPUpdate(userId: number, data: Types.PlayerData)
	data.XP += EconomyConfig.XPPerIncubation
	data.Statistics.TotalDinosaursIncubated += 1

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
			print(string.format("[IncubatorService] Player %d leveled up to Level %d!", userId, nextLevel))
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

--- Returns the current IncubatorState for a player.
function IncubatorService.getMachineState(userId: number): IncubatorState
	return getState(userId)
end

--- Resets a player's machine to Idle — used in tests and on player leave.
function IncubatorService.resetMachine(userId: number)
	if processingTasks[userId] then
		task.cancel(processingTasks[userId])
		processingTasks[userId] = nil
	end
	machineStates[userId] = getDefaultState()
end

--- Completes processing: creates the dinosaur, adds it to inventory, awards XP, and resets to Idle.
function IncubatorService.completeProcessing(userId: number): (boolean, any)
	local state = getState(userId)
	if state.State ~= MachineConfig.States.Processing then
		return false, "Machine is not processing"
	end

	-- Cancel any scheduled task
	if processingTasks[userId] then
		task.cancel(processingTasks[userId])
		processingTasks[userId] = nil
	end

	-- Build DNA representation to generate dinosaur
	local dnaProxy: Types.ItemData = {
		ItemUID = state.InputItemUID or ItemUtils.generateUID(),
		ItemType = "DNA",
		ConfigID = (state.InputDinosaurID or "TREX") .. "_DNA",
		DinosaurID = state.InputDinosaurID or "TREX",
		Rarity = state.InputRarity or "Common",
		Quality = state.InputQuality or 80,
		IsCleaned = false,
		ObtainedAt = os.time(),
	}

	local dinoItem = ItemUtils.createDinosaurItem(dnaProxy)
	if not dinoItem then
		warn("[IncubatorService] Failed to create Dinosaur item for player", userId)
		machineStates[userId] = getDefaultState()
		fireStateUpdate(userId)
		return false, "Failed to create dinosaur item"
	end

	-- Auto-collect to inventory
	local added = InventoryService.addItem(userId, dinoItem)
	if not added then
		warn("[IncubatorService] Failed to add incubated dinosaur to inventory for player", userId)
		return false, "Failed to add dinosaur to inventory"
	end

	-- Award XP & update stats
	local data = DataService.getPlayerData(userId)
	if data then
		fireXPUpdate(userId, data)
	end

	-- Reset machine to Idle
	machineStates[userId] = getDefaultState()
	fireStateUpdate(userId, dinoItem)

	print(string.format("[IncubatorService] Player %d successfully incubated %s (%s, UID: %s)",
		userId, dinoItem.DinosaurID, dinoItem.Rarity, dinoItem.ItemUID))

	return true, dinoItem
end

--- TEST HOOK: Forces incubation to complete immediately, bypassing the timer.
-- Safe no-op if the machine is not currently Processing.
function IncubatorService.forceCompleteProcessing(userId: number)
	local state = getState(userId)
	if state.State ~= MachineConfig.States.Processing then
		return
	end
	IncubatorService.completeProcessing(userId)
end

-------------------------------------------------------------------------
-- PUBLIC API — GAMEPLAY OPERATIONS
-------------------------------------------------------------------------

--- Validates and inserts the player's currently carried DNA into the Dinosaur Incubator.
function IncubatorService.insertItem(userId: number, machine: Instance?): (boolean, string?)
	if not CarryingService or not InventoryService or not DataService then
		return false, "Services unavailable"
	end

	-- 1. Validate that the player is carrying an item
	local item = CarryingService.getCarriedItem(userId)
	if not item then
		return false, "No item is being carried"
	end

	-- 2. Validate item compatibility with Dinosaur Incubator
	if not ItemUtils.isCompatibleWithMachine(item, MACHINE_ID) then
		return false, "Incubator only accepts DNA items"
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
					return false, "Too far from Dinosaur Incubator"
				end
			end
		end
	end

	-- 5. Consume the DNA from inventory and carrying state
	local consumed = CarryingService.consumeCarriedItem(userId)
	if not consumed then
		return false, "Failed to consume carried item"
	end

	-- 6. Transition to Processing
	local machineInfo = MachineConfig.getMachine(MACHINE_ID)
	local processingTime = if machineInfo then machineInfo.BaseProcessingTime else 30

	state.State = MachineConfig.States.Processing
	state.InputItemUID = consumed.ItemUID
	state.InputDinosaurID = consumed.DinosaurID
	state.InputRarity = consumed.Rarity
	state.InputQuality = consumed.Quality
	state.StartTime = os.time()

	fireStateUpdate(userId)

	print(string.format("[IncubatorService] Player %d started incubation — %s (%s), %.0fs",
		userId, consumed.DinosaurID, consumed.Rarity, processingTime))

	-- 7. Schedule auto-completion after incubation time
	processingTasks[userId] = task.delay(processingTime, function()
		IncubatorService.completeProcessing(userId)
	end)

	return true, "Processing started"
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
		prompt.Name = "IncubatorInsertPrompt"
		prompt.ActionText = "Insert DNA"
		prompt.ObjectText = "Dinosaur Incubator"
		prompt.HoldDuration = 0.5
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = basePart
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
	local existing = machinesFolder:FindFirstChild("IncubatorMachine")

	if #tagged == 0 and not existing then
		-- Auto-provision a placeholder machine
		local machine = Instance.new("Part")
		machine.Name = "IncubatorMachine"
		machine.Size = Vector3.new(6, 5, 5)
		machine.Position = Vector3.new(44, 2, 0)
		machine.Anchored = true
		machine.CanCollide = true
		machine.Material = Enum.Material.Glass
		machine.Color = Color3.fromRGB(0, 180, 120)
		machine:SetAttribute("MachineID", MACHINE_ID)
		machine.Parent = machinesFolder

		CollectionService:AddTag(machine, MACHINE_TAG)
		attachPromptsToMachine(machine)
		print("[IncubatorService] Auto-provisioned placeholder Incubator at (44, 2, 0).")
	else
		for _, m in tagged do attachPromptsToMachine(m) end
		if existing then attachPromptsToMachine(existing) end
	end
end

-------------------------------------------------------------------------
-- INITIALIZATION
-------------------------------------------------------------------------

function IncubatorService.init()
	DataService = require(ServerScriptService.Services.DataService)
	InventoryService = require(ServerScriptService.Services.InventoryService)
	CarryingService = require(ServerScriptService.Services.CarryingService)

	remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10) :: Folder?
	if remoteEventsFolder then
		requestUseMachineRemote   = remoteEventsFolder:WaitForChild("RequestUseMachine", 5) :: RemoteEvent?
		machineStateUpdatedRemote = remoteEventsFolder:WaitForChild("MachineStateUpdated", 5) :: RemoteEvent?
		xpUpdatedRemote           = remoteEventsFolder:WaitForChild("XPUpdated", 5) :: RemoteEvent?
		levelUpdatedRemote        = remoteEventsFolder:WaitForChild("LevelUpdated", 5) :: RemoteEvent?

		if requestUseMachineRemote then
			requestUseMachineRemote.OnServerEvent:Connect(function(player: Player, machineInst: any, machineIDArg: any)
				if typeof(machineIDArg) ~= "string" or machineIDArg ~= MACHINE_ID then return end
				local inst = if typeof(machineInst) == "Instance" then machineInst else nil
				local success, result = IncubatorService.insertItem(player.UserId, inst)
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
		IncubatorService.resetMachine(player.UserId)
	end)

	print("[IncubatorService] Initialized.")
end

return IncubatorService
