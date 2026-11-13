--!strict
--[[
	CageService
	Authoritative server service for dinosaur cages and passive income generation.

	Responsibilities:
	  1. Validates dinosaur placement into cages (ownership, item type, cage occupancy).
	  2. Consumes dinosaur from carrying and inventory on placement.
	  3. Calculates passive income based on dinosaur BaseIncome and elapsed time intervals.
	  4. Caps accumulated income at EconomyConfig.MaxAccumulatedIncome.
	  5. Handles authoritative income collection and PlayerData updates.
	  6. Supports dinosaur retrieval back to player inventory.
	  7. Auto-provisions starter cage in Workspace.Cages.StarterCage.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

-- Shared modules & configs
local Types = require(ReplicatedStorage.Modules.Types)
local ItemUtils = require(ReplicatedStorage.Modules.ItemUtils)
local DinosaurConfig = require(ReplicatedStorage.Configurations.DinosaurConfig)
local EconomyConfig = require(ReplicatedStorage.Configurations.EconomyConfig)

local CageService = {}

-- Service dependencies
local DataService = nil
local InventoryService = nil
local CarryingService = nil

-- Remotes
local remoteEventsFolder: Folder? = nil
local requestPlaceDinosaurRemote: RemoteEvent? = nil
local requestCollectIncomeRemote: RemoteEvent? = nil
local cageUpdatedRemote: RemoteEvent? = nil
local moneyUpdatedRemote: RemoteEvent? = nil
local xpUpdatedRemote: RemoteEvent? = nil
local levelUpdatedRemote: RemoteEvent? = nil

-- Constants
local DEFAULT_CAGE_ID = "CAGE_1"
local MAX_INTERACTION_DISTANCE = 16
local CAGE_TAG = "DinosaurCage"

-- In-memory cache of stored dinosaur items in cages (for accurate retrieval)
-- UserId -> { [CageID]: Types.ItemData }
local storedDinosaurItems: { [number]: { [string]: Types.ItemData } } = {}

-- In-memory spawned visual models for dinosaurs inside cages
-- UserId -> { [CageID]: Model }
local cageVisualModels: { [number]: { [string]: Model } } = {}

-------------------------------------------------------------------------
-- INTERNAL HELPERS
-------------------------------------------------------------------------

local function getOrCreateCageData(userId: number, cageId: string): Types.CageData?
	local data = DataService.getPlayerData(userId)
	if not data then return nil end

	if not data.CageAssignments then
		data.CageAssignments = {}
	end

	if not data.CageAssignments[cageId] then
		data.CageAssignments[cageId] = {
			CageID = cageId,
			DinosaurItemUID = nil,
			DinosaurID = nil,
			AccumulatedIncome = 0,
			LastCollectionTime = os.time(),
		}
	end

	return data.CageAssignments[cageId]
end

local function fireXPUpdate(userId: number, data: Types.PlayerData, amount: number)
	data.XP += amount

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
			print(string.format("[CageService] Player %d reached Level %d!", userId, nextLevel))
		end
	end
end

local function fireMoneyUpdate(userId: number, data: Types.PlayerData)
	local player = Players:GetPlayerByUserId(userId)
	if not player then return end

	if moneyUpdatedRemote then
		moneyUpdatedRemote:FireClient(player, data.Money)
	end
end

local function fireCageUpdate(userId: number, cage: Types.CageData, pendingIncome: number)
	local player = Players:GetPlayerByUserId(userId)
	if not player then return end

	if cageUpdatedRemote then
		cageUpdatedRemote:FireClient(player, {
			CageID = cage.CageID,
			DinosaurID = cage.DinosaurID,
			DinosaurItemUID = cage.DinosaurItemUID,
			PendingIncome = pendingIncome,
			LastCollectionTime = cage.LastCollectionTime,
		})
	end
end

local function getCagePosition(cage: Instance): Vector3?
	if cage:IsA("BasePart") then
		return cage.Position
	elseif cage:IsA("Model") then
		local primary = cage.PrimaryPart or cage:FindFirstChildWhichIsA("BasePart")
		return if primary then primary.Position else nil
	end
	return nil
end

local function destroyCageVisual(userId: number, cageId: string)
	if cageVisualModels[userId] and cageVisualModels[userId][cageId] then
		cageVisualModels[userId][cageId]:Destroy()
		cageVisualModels[userId][cageId] = nil
	end
end

local function spawnCageVisual(userId: number, cageId: string, dino: Types.ItemData, cageInstance: Instance?)
	destroyCageVisual(userId, cageId)
	if not cageInstance then return end

	local parentPart: BasePart? = nil
	if cageInstance:IsA("BasePart") then
		parentPart = cageInstance
	elseif cageInstance:IsA("Model") then
		parentPart = cageInstance.PrimaryPart or cageInstance:FindFirstChildWhichIsA("BasePart")
	end
	if not parentPart then return end

	local model = Instance.new("Model")
	model.Name = "CageDinosaurVisual_" .. dino.DinosaurID

	local part = Instance.new("Part")
	part.Name = "DinoBody"
	part.Size = Vector3.new(3, 3, 4)
	part.Position = parentPart.Position + Vector3.new(0, 1.5, 0)
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.SmoothPlastic
	part.Color = ItemUtils.getRarityColor(dino)
	part.Parent = model
	model.PrimaryPart = part

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DinoTag"
	billboard.Size = UDim2.new(0, 140, 0, 40)
	billboard.StudsOffset = Vector3.new(0, 2.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 0.5
	label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextSize = 13
	label.Font = Enum.Font.GothamBold
	label.Text = string.format("%s\n[%s]", ItemUtils.getDisplayName(dino), dino.Rarity)
	label.Parent = billboard
	billboard.Parent = part

	model.Parent = cageInstance

	if not cageVisualModels[userId] then
		cageVisualModels[userId] = {}
	end
	cageVisualModels[userId][cageId] = model
end

-------------------------------------------------------------------------
-- PUBLIC API — QUERIES & STATE
-------------------------------------------------------------------------

--- Returns cage data for a given player and cage ID.
function CageService.getCageData(userId: number, cageId: string): Types.CageData?
	return getOrCreateCageData(userId, cageId)
end

--- Resets all cage data and visuals for a player.
function CageService.resetPlayerCages(userId: number)
	local data = DataService.getPlayerData(userId)
	if data then
		data.CageAssignments = {}
	end
	if storedDinosaurItems[userId] then
		storedDinosaurItems[userId] = {}
	end
	if cageVisualModels[userId] then
		for _, m in cageVisualModels[userId] do
			m:Destroy()
		end
		cageVisualModels[userId] = {}
	end
end

--- Calculates current pending income for a given cage.
function CageService.calculatePendingIncome(userId: number, cageId: string): number
	local cage = getOrCreateCageData(userId, cageId)
	if not cage or not cage.DinosaurID then
		return 0
	end

	local dinoInfo = DinosaurConfig.getDinosaur(cage.DinosaurID)
	local baseIncome = if dinoInfo then dinoInfo.BaseIncome else 10

	local now = os.time()
	local elapsed = math.max(0, now - cage.LastCollectionTime)
	local intervals = math.floor(elapsed / EconomyConfig.IncomeTickInterval)

	local calculated = cage.AccumulatedIncome + (intervals * baseIncome)
	return math.clamp(calculated, 0, EconomyConfig.MaxAccumulatedIncome)
end

--- TEST HOOK: Simulates elapsed time by shifting LastCollectionTime backward.
function CageService.simulateElapsedTime(userId: number, cageId: string, seconds: number)
	local cage = getOrCreateCageData(userId, cageId)
	if cage then
		cage.LastCollectionTime -= seconds
	end
end

-------------------------------------------------------------------------
-- PUBLIC API — GAMEPLAY ACTIONS
-------------------------------------------------------------------------

--- Validates and places the player's carried dinosaur into the specified cage.
function CageService.placeDinosaur(userId: number, cageId: string, cageInstance: Instance?): (boolean, string?)
	if not CarryingService or not InventoryService or not DataService then
		return false, "Services unavailable"
	end

	-- 1. Validate carried item
	local carried = CarryingService.getCarriedItem(userId)
	if not carried then
		return false, "No item is being carried"
	end

	-- 2. Validate item type
	if not ItemUtils.canPlaceInCage(carried) then
		return false, "Only dinosaurs can be placed in cages"
	end

	-- 3. Validate cage data
	local cage = getOrCreateCageData(userId, cageId)
	if not cage then
		return false, "Cage not found or not owned"
	end

	-- 4. Check if cage is already occupied
	if cage.DinosaurID ~= nil then
		return false, "Cage is already occupied"
	end

	-- 5. Distance check if cage instance is provided
	if cageInstance then
		if not cageInstance:IsDescendantOf(workspace) then
			return false, "Invalid cage instance"
		end
		local cagePos = getCagePosition(cageInstance)
		if cagePos then
			local player = Players:GetPlayerByUserId(userId)
			if player and player.Character then
				local root = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and (root.Position - cagePos).Magnitude > MAX_INTERACTION_DISTANCE then
					return false, "Too far from cage"
				end
			end
		end
	end

	-- 6. Consume dinosaur from carrying and inventory
	local consumed = CarryingService.consumeCarriedItem(userId)
	if not consumed then
		return false, "Failed to consume carried dinosaur"
	end

	-- 7. Assign dinosaur to cage
	cage.DinosaurID = consumed.DinosaurID
	cage.DinosaurItemUID = consumed.ItemUID
	cage.AccumulatedIncome = 0
	cage.LastCollectionTime = os.time()

	-- Store full item data for accurate retrieval
	if not storedDinosaurItems[userId] then
		storedDinosaurItems[userId] = {}
	end
	storedDinosaurItems[userId][cageId] = consumed

	-- 8. Award XP
	local data = DataService.getPlayerData(userId)
	if data then
		fireXPUpdate(userId, data, EconomyConfig.XPPerDinosaurPlaced)
	end

	-- 9. Spawn physical visual
	spawnCageVisual(userId, cageId, consumed, cageInstance)

	-- 10. Notify client
	fireCageUpdate(userId, cage, 0)

	print(string.format("[CageService] Player %d placed %s into cage %s.", userId, consumed.DinosaurID, cageId))
	return true, "Dinosaur placed"
end

--- Collects passive income from an occupied cage.
function CageService.collectIncome(userId: number, cageId: string, cageInstance: Instance?): (boolean, any)
	local cage = getOrCreateCageData(userId, cageId)
	if not cage or not cage.DinosaurID then
		return false, "No income to collect"
	end

	-- Distance check if instance provided
	if cageInstance then
		local cagePos = getCagePosition(cageInstance)
		if cagePos then
			local player = Players:GetPlayerByUserId(userId)
			if player and player.Character then
				local root = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root and (root.Position - cagePos).Magnitude > MAX_INTERACTION_DISTANCE then
					return false, "Too far from cage"
				end
			end
		end
	end

	local pending = CageService.calculatePendingIncome(userId, cageId)
	if pending <= 0 then
		return false, "No income to collect"
	end

	local data = DataService.getPlayerData(userId)
	if not data then
		return false, "Player data not loaded"
	end

	-- Authoritatively add money and update stats
	data.Money += pending
	data.Statistics.TotalMoneyEarned += pending

	-- Reset accumulated income and update collection time
	cage.AccumulatedIncome = 0
	cage.LastCollectionTime = os.time()

	fireMoneyUpdate(userId, data)
	fireCageUpdate(userId, cage, 0)

	print(string.format("[CageService] Player %d collected $%d from cage %s.", userId, pending, cageId))
	return true, pending
end

--- Retrieves a dinosaur from a cage, returning it to player inventory.
function CageService.retrieveDinosaur(userId: number, cageId: string, cageInstance: Instance?): (boolean, any)
	local cage = getOrCreateCageData(userId, cageId)
	if not cage or not cage.DinosaurID then
		return false, "No dinosaur in cage"
	end

	-- 1. Collect any pending income first
	local pending = CageService.calculatePendingIncome(userId, cageId)
	if pending > 0 then
		local data = DataService.getPlayerData(userId)
		if data then
			data.Money += pending
			data.Statistics.TotalMoneyEarned += pending
			fireMoneyUpdate(userId, data)
		end
	end

	-- 2. Retrieve or reconstruct the dinosaur item
	local dinoItem: Types.ItemData? = nil
	if storedDinosaurItems[userId] and storedDinosaurItems[userId][cageId] then
		dinoItem = storedDinosaurItems[userId][cageId]
		storedDinosaurItems[userId][cageId] = nil
	else
		-- Fallback reconstruction from DinosaurID
		dinoItem = {
			ItemUID = cage.DinosaurItemUID or ItemUtils.generateUID(),
			ItemType = "Dinosaur",
			ConfigID = cage.DinosaurID,
			DinosaurID = cage.DinosaurID,
			Rarity = "Common",
			Quality = 80,
			IsCleaned = false,
			ObtainedAt = os.time(),
		}
	end

	-- 3. Return to inventory
	if dinoItem then
		InventoryService.addItem(userId, dinoItem)
	end

	-- 4. Clear cage assignment
	cage.DinosaurID = nil
	cage.DinosaurItemUID = nil
	cage.AccumulatedIncome = 0
	cage.LastCollectionTime = os.time()

	-- 5. Remove visual representation
	destroyCageVisual(userId, cageId)

	fireCageUpdate(userId, cage, 0)

	print(string.format("[CageService] Player %d retrieved dinosaur from cage %s.", userId, cageId))
	return true, dinoItem
end

-------------------------------------------------------------------------
-- WORLD PROVISION & PROMPTS
-------------------------------------------------------------------------

local function attachPromptsToCage(cage: Instance)
	local basePart: BasePart? = nil
	if cage:IsA("BasePart") then
		basePart = cage
	elseif cage:IsA("Model") then
		basePart = cage.PrimaryPart or cage:FindFirstChildWhichIsA("BasePart")
	end
	if not basePart then return end

	if not basePart:FindFirstChild("CagePlacementPrompt") then
		local placePrompt = Instance.new("ProximityPrompt")
		placePrompt.Name = "CagePlacementPrompt"
		placePrompt.ActionText = "Place Dinosaur"
		placePrompt.ObjectText = "Dinosaur Cage"
		placePrompt.HoldDuration = 0.5
		placePrompt.MaxActivationDistance = 12
		placePrompt.RequiresLineOfSight = false
		placePrompt.Parent = basePart

		local collectPrompt = Instance.new("ProximityPrompt")
		collectPrompt.Name = "CageCollectPrompt"
		collectPrompt.ActionText = "Collect Income"
		collectPrompt.ObjectText = "Dinosaur Cage"
		collectPrompt.HoldDuration = 0
		collectPrompt.MaxActivationDistance = 12
		collectPrompt.RequiresLineOfSight = false
		collectPrompt.Parent = basePart

		local retrievePrompt = Instance.new("ProximityPrompt")
		retrievePrompt.Name = "CageRetrievePrompt"
		retrievePrompt.ActionText = "Retrieve Dinosaur"
		retrievePrompt.ObjectText = "Dinosaur Cage"
		retrievePrompt.HoldDuration = 1.0
		retrievePrompt.MaxActivationDistance = 12
		retrievePrompt.RequiresLineOfSight = false
		retrievePrompt.Parent = basePart
	end
end

local function setupDefaultCages()
	local cagesFolder = workspace:FindFirstChild("Cages")
	if not cagesFolder then
		cagesFolder = Instance.new("Folder")
		cagesFolder.Name = "Cages"
		cagesFolder.Parent = workspace
	end

	local tagged = CollectionService:GetTagged(CAGE_TAG)
	local existing = cagesFolder:FindFirstChild("StarterCage")

	if #tagged == 0 and not existing then
		-- Create a starter cage
		local cage = Instance.new("Part")
		cage.Name = "StarterCage"
		cage.Size = Vector3.new(14, 6, 14)
		cage.Position = Vector3.new(0, 3, 25)
		cage.Anchored = true
		cage.CanCollide = true
		cage.Material = Enum.Material.Metal
		cage.Color = Color3.fromRGB(110, 110, 110)
		cage:SetAttribute("CageID", DEFAULT_CAGE_ID)
		cage.Parent = cagesFolder

		CollectionService:AddTag(cage, CAGE_TAG)
		attachPromptsToCage(cage)
		print("[CageService] Auto-provisioned StarterCage at (0, 3, 25).")
	else
		for _, c in tagged do attachPromptsToCage(c) end
		if existing then attachPromptsToCage(existing) end
	end
end

-------------------------------------------------------------------------
-- INITIALIZATION
-------------------------------------------------------------------------

function CageService.init()
	DataService = require(ServerScriptService.Services.DataService)
	InventoryService = require(ServerScriptService.Services.InventoryService)
	CarryingService = require(ServerScriptService.Services.CarryingService)

	remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10) :: Folder?
	if remoteEventsFolder then
		requestPlaceDinosaurRemote = remoteEventsFolder:WaitForChild("RequestPlaceDinosaur", 5) :: RemoteEvent?
		requestCollectIncomeRemote = remoteEventsFolder:WaitForChild("RequestCollectIncome", 5) :: RemoteEvent?
		cageUpdatedRemote          = remoteEventsFolder:WaitForChild("CageUpdated", 5) :: RemoteEvent?
		moneyUpdatedRemote         = remoteEventsFolder:WaitForChild("MoneyUpdated", 5) :: RemoteEvent?
		xpUpdatedRemote            = remoteEventsFolder:WaitForChild("XPUpdated", 5) :: RemoteEvent?
		levelUpdatedRemote         = remoteEventsFolder:WaitForChild("LevelUpdated", 5) :: RemoteEvent?

		if requestPlaceDinosaurRemote then
			requestPlaceDinosaurRemote.OnServerEvent:Connect(function(player: Player, cageInst: any, cageIdArg: any)
				local cid = if typeof(cageIdArg) == "string" then cageIdArg else DEFAULT_CAGE_ID
				local inst = if typeof(cageInst) == "Instance" then cageInst else nil
				CageService.placeDinosaur(player.UserId, cid, inst)
			end)
		end

		if requestCollectIncomeRemote then
			requestCollectIncomeRemote.OnServerEvent:Connect(function(player: Player, cageInst: any, cageIdArg: any)
				local cid = if typeof(cageIdArg) == "string" then cageIdArg else DEFAULT_CAGE_ID
				local inst = if typeof(cageInst) == "Instance" then cageInst else nil
				CageService.collectIncome(player.UserId, cid, inst)
			end)
		end
	end

	CollectionService:GetInstanceAddedSignal(CAGE_TAG):Connect(function(c)
		attachPromptsToCage(c)
	end)

	setupDefaultCages()

	Players.PlayerRemoving:Connect(function(player)
		CageService.resetPlayerCages(player.UserId)
	end)

	print("[CageService] Initialized.")
end

return CageService

