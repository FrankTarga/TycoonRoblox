--!strict
--[[
	CleaningService
	Authoritative server service for cleaning excavated fossils using brushes.

	Responsibilities:
	  1. Validates player cleaning requests (distance, station, fossil, uncleaned, brush equipped).
	  2. Processes fossil cleaning: sets IsCleaned = true, assigns Quality rating, awards XP.
	  3. Syncs updated fossil state across InventoryService and CarryingService.
	  4. Auto-provisions and manages physical Cleaning Stations in Workspace.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

-- Shared modules & configs
local Types = require(ReplicatedStorage.Modules.Types)
local ItemUtils = require(ReplicatedStorage.Modules.ItemUtils)
local EquipmentConfig = require(ReplicatedStorage.Configurations.EquipmentConfig)
local EconomyConfig = require(ReplicatedStorage.Configurations.EconomyConfig)

local CleaningService = {}

-- Server service dependencies
local DataService = nil
local InventoryService = nil
local CarryingService = nil

-- Remotes
local remoteEventsFolder: Folder? = nil
local requestCleanFossilRemote: RemoteEvent? = nil
local cleaningProgressRemote: RemoteEvent? = nil
local xpUpdatedRemote: RemoteEvent? = nil
local levelUpdatedRemote: RemoteEvent? = nil

-- Constants
local MAX_INTERACTION_DISTANCE = 16
local CLEANING_STATION_TAG = "CleaningStation"
local BASE_CLEANING_DURATION = 2.0 -- seconds

-------------------------------------------------------------------------
-- INTERNAL HELPERS
-------------------------------------------------------------------------

local function getStationPosition(station: Instance): Vector3?
	if station:IsA("BasePart") then
		return station.Position
	elseif station:IsA("Model") then
		local primary = station.PrimaryPart or station:FindFirstChildWhichIsA("BasePart")
		return if primary then primary.Position else nil
	end
	return nil
end

-------------------------------------------------------------------------
-- VALIDATION & DURATION
-------------------------------------------------------------------------

--- Calculates the cleaning duration scaled by the player's equipped brush speed.
function CleaningService.getCleaningDuration(userId: number): number
	if not DataService then return BASE_CLEANING_DURATION end
	local data = DataService.getPlayerData(userId)
	if not data then return BASE_CLEANING_DURATION end

	local brushId = data.Equipment.ActiveBrush
	local brushInfo = EquipmentConfig.getEquipment(brushId)
	local speedMultiplier = if brushInfo and brushInfo.SpeedMultiplier then brushInfo.SpeedMultiplier else 1.0

	return math.max(0.5, BASE_CLEANING_DURATION / math.max(0.1, speedMultiplier))
end

--- Validates whether the player can clean their currently held item.
function CleaningService.validateCleaning(userId: number, station: Instance?): (boolean, string?, Types.ItemData?)
	if not CarryingService or not DataService then
		return false, "Services unavailable", nil
	end

	-- 1. Check if carrying an item
	local item = CarryingService.getCarriedItem(userId)
	if not item then
		return false, "No item is being carried", nil
	end

	-- 2. Check that the item is a Fossil
	if item.ItemType ~= "Fossil" then
		return false, "Only fossils can be cleaned", nil
	end

	-- 3. Check that the fossil is not already cleaned
	if item.IsCleaned then
		return false, "Fossil is already cleaned", nil
	end

	-- 4. Check that player has a brush equipped
	local data = DataService.getPlayerData(userId)
	if not data then
		return false, "Player data not loaded", nil
	end

	local brushId = data.Equipment.ActiveBrush
	if not brushId or brushId == "" then
		return false, "No brush equipped", nil
	end

	local brushInfo = EquipmentConfig.getEquipment(brushId)
	if not brushInfo or brushInfo.Type ~= "Brush" then
		return false, "Equipped tool is not a brush", nil
	end

	-- 5. If a physical station is provided, validate distance
	if station then
		if not station:IsDescendantOf(workspace) then
			return false, "Invalid cleaning station", nil
		end

		local stationPos = getStationPosition(station)
		if not stationPos then
			return false, "Cleaning station has no physical position", nil
		end

		local player = Players:GetPlayerByUserId(userId)
		if player and player.Character then
			local root = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				local distance = (root.Position - stationPos).Magnitude
				if distance > MAX_INTERACTION_DISTANCE then
					return false, "Too far from cleaning station", nil
				end
			end
		end
	end

	return true, "Valid", item
end

-------------------------------------------------------------------------
-- CLEANING EXECUTION
-------------------------------------------------------------------------

--- Authoritatively cleans the fossil the player is currently carrying.
function CleaningService.cleanCarriedFossil(userId: number, station: Instance?): (boolean, any)
	local valid, reason, item = CleaningService.validateCleaning(userId, station)
	if not valid or not item then
		return false, reason
	end

	local data = DataService.getPlayerData(userId)
	if not data then
		return false, "Player data not loaded"
	end

	-- Calculate Quality (70-95 base + brush bonus)
	local brushInfo = EquipmentConfig.getEquipment(data.Equipment.ActiveBrush)
	local brushTier = if brushInfo then brushInfo.Tier else 1
	local qualityRoll = math.clamp(70 + (brushTier * 5) + math.random(0, 15), 1, 100)

	-- Apply cleaning state to the item
	item.IsCleaned = true
	item.Quality = qualityRoll

	-- Award XP & update player statistics
	data.XP += EconomyConfig.XPPerCleaning

	local player = Players:GetPlayerByUserId(userId)
	if player then
		if xpUpdatedRemote then
			xpUpdatedRemote:FireClient(player, data.XP)
		end

		-- Level up check
		local nextLevel = data.Level + 1
		if nextLevel <= EconomyConfig.MaxLevel then
			local xpNeeded = EconomyConfig.getXPForLevel(nextLevel)
			if data.XP >= xpNeeded then
				data.Level = nextLevel
				if levelUpdatedRemote then
					levelUpdatedRemote:FireClient(player, data.Level)
				end
				print(string.format("[CleaningService] Player %s leveled up to Level %d!", player.Name, nextLevel))
			end
		end

		-- Refresh inventory on client
		if remoteEventsFolder then
			local inventoryUpdated = remoteEventsFolder:FindFirstChild("InventoryUpdated") :: RemoteEvent?
			if inventoryUpdated then
				inventoryUpdated:FireClient(player, data.Inventory)
			end
		end

		-- Refresh visual carrying label/billboard
		CarryingService.setCarriedItem(userId, item.ItemUID)

		-- Notify client of successful cleaning completion
		if cleaningProgressRemote then
			cleaningProgressRemote:FireClient(player, {
				Status = "Completed",
				Progress = 100,
				Item = item,
			})
		end

		print(string.format("[CleaningService] Player %s cleaned %s (Quality: %d%%)",
			player.Name, ItemUtils.getDisplayName(item), qualityRoll))
	end

	return true, item
end

-------------------------------------------------------------------------
-- PROMPT & STATION ATTACHMENT
-------------------------------------------------------------------------

--- Attaches an interaction ProximityPrompt to a cleaning station.
function CleaningService.attachPromptToStation(station: Instance)
	local parentPart: BasePart? = nil
	if station:IsA("BasePart") then
		parentPart = station
	elseif station:IsA("Model") then
		parentPart = station.PrimaryPart or station:FindFirstChildWhichIsA("BasePart")
	end

	if not parentPart then return end

	local existing = parentPart:FindFirstChildWhichIsA("ProximityPrompt")
	if not existing then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "CleanPrompt"
		prompt.ActionText = "Clean Fossil with Brush"
		prompt.ObjectText = "Fossil Cleaning Station"
		prompt.HoldDuration = BASE_CLEANING_DURATION
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = parentPart
	end
end

--- Auto-provisions a default cleaning station in Workspace if none exists.
function CleaningService.setupDefaultStations()
	local stationsFolder = workspace:FindFirstChild("CleaningStations")
	if not stationsFolder then
		stationsFolder = Instance.new("Folder")
		stationsFolder.Name = "CleaningStations"
		stationsFolder.Parent = workspace
	end

	local tagged = CollectionService:GetTagged(CLEANING_STATION_TAG)
	local children = stationsFolder:GetChildren()

	if #tagged == 0 and #children == 0 then
		local station = Instance.new("Part")
		station.Name = "BeginnerCleaningStation"
		station.Size = Vector3.new(5, 2, 4)
		station.Position = Vector3.new(12, 1, 0)
		station.Anchored = true
		station.CanCollide = true
		station.Material = Enum.Material.WoodPlanks
		station.Color = Color3.fromRGB(130, 95, 60)
		station.Parent = stationsFolder

		CollectionService:AddTag(station, CLEANING_STATION_TAG)
		CleaningService.attachPromptToStation(station)
		print("[CleaningService] Auto-provisioned default Beginner Cleaning Station at (12, 1, 0).")
	else
		for _, st in tagged do
			CleaningService.attachPromptToStation(st)
		end
		for _, st in children do
			if st:IsA("BasePart") or st:IsA("Model") then
				CollectionService:AddTag(st, CLEANING_STATION_TAG)
				CleaningService.attachPromptToStation(st)
			end
		end
	end
end

-------------------------------------------------------------------------
-- SERVICE INITIALIZATION
-------------------------------------------------------------------------

function CleaningService.init()
	DataService = require(ServerScriptService.Services.DataService)
	InventoryService = require(ServerScriptService.Services.InventoryService)
	CarryingService = require(ServerScriptService.Services.CarryingService)

	remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10) :: Folder?
	if remoteEventsFolder then
		requestCleanFossilRemote = remoteEventsFolder:WaitForChild("RequestCleanFossil", 5) :: RemoteEvent?
		cleaningProgressRemote = remoteEventsFolder:WaitForChild("CleaningProgress", 5) :: RemoteEvent?
		xpUpdatedRemote = remoteEventsFolder:WaitForChild("XPUpdated", 5) :: RemoteEvent?
		levelUpdatedRemote = remoteEventsFolder:WaitForChild("LevelUpdated", 5) :: RemoteEvent?

		if requestCleanFossilRemote then
			requestCleanFossilRemote.OnServerEvent:Connect(function(player: Player, station: any)
				local stationInst = if typeof(station) == "Instance" then station else nil
				local success, result = CleaningService.cleanCarriedFossil(player.UserId, stationInst)
				if not success and cleaningProgressRemote then
					cleaningProgressRemote:FireClient(player, {
						Status = "Failed",
						Progress = 0,
						Reason = tostring(result),
					})
				end
			end)
		end
	end

	CollectionService:GetInstanceAddedSignal(CLEANING_STATION_TAG):Connect(function(station)
		CleaningService.attachPromptToStation(station)
	end)

	CleaningService.setupDefaultStations()

	print("[CleaningService] Initialized.")
end

return CleaningService
