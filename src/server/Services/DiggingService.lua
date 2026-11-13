--!strict
--[[
	DiggingService
	Authoritative server service for excavation.
	
	Responsibilities:
	  1. Validates player excavation requests (distance, level, zone, cooldown, shovel).
	  2. Rolls random fossil rewards based on zone pools, rarity weights, and luck.
	  3. Adds discovered fossils to the player's inventory via InventoryService.
	  4. Awards XP and tracks player excavation statistics.
	  5. Manages and auto-provisions physical excavation spots in Workspace.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local CollectionService = game:GetService("CollectionService")

-- Shared modules & configs
local Types = require(ReplicatedStorage.Modules.Types)
local ItemUtils = require(ReplicatedStorage.Modules.ItemUtils)
local ZoneConfig = require(ReplicatedStorage.Configurations.ZoneConfig)
local FossilConfig = require(ReplicatedStorage.Configurations.FossilConfig)
local RarityConfig = require(ReplicatedStorage.Configurations.RarityConfig)
local EquipmentConfig = require(ReplicatedStorage.Configurations.EquipmentConfig)
local EconomyConfig = require(ReplicatedStorage.Configurations.EconomyConfig)

local DiggingService = {}

-- Server service dependencies
local DataService = nil
local InventoryService = nil

-- Remotes
local remoteEventsFolder: Folder? = nil
local requestExcavationRemote: RemoteEvent? = nil
local excavationResultRemote: RemoteEvent? = nil
local xpUpdatedRemote: RemoteEvent? = nil
local levelUpdatedRemote: RemoteEvent? = nil

-- Cooldown tracker: UserId -> os.clock() timestamp
local lastExcavationTimes: { [number]: number } = {}

-- Constants
local MAX_INTERACTION_DISTANCE = 16 -- Maximum studs between player and spot
local EXCAVATION_SPOT_TAG = "ExcavationSpot"

-------------------------------------------------------------------------
-- INTERNAL HELPERS
-------------------------------------------------------------------------

--- Determines spot position from Part or Model.
local function getSpotPosition(spot: Instance): Vector3?
	if spot:IsA("BasePart") then
		return spot.Position
	elseif spot:IsA("Model") then
		local primary = spot.PrimaryPart or spot:FindFirstChildWhichIsA("BasePart")
		return if primary then primary.Position else nil
	end
	return nil
end

--- Calculates effective excavation cooldown considering shovel speed.
local function getEffectiveCooldown(zoneInfo: ZoneConfig.ZoneInfo, shovelInfo: EquipmentConfig.EquipmentInfo): number
	local speed = math.max(0.1, shovelInfo.SpeedMultiplier)
	return math.max(1, zoneInfo.ExcavationCooldown / speed)
end

--- Server-authoritative random fossil selection based on zone pool, rarity weights, and luck.
local function rollFossil(zoneInfo: ZoneConfig.ZoneInfo, shovelInfo: EquipmentConfig.EquipmentInfo): string?
	local available = zoneInfo.AvailableFossils
	if #available == 0 then
		return nil
	end

	-- Calculate total effective luck
	local luckMultiplier = math.max(0.1, zoneInfo.LuckMultiplier + (shovelInfo.LuckBonus * 0.1))

	-- Build weighted candidate list
	local candidates: { { fossilId: string, weight: number } } = {}
	local totalWeight = 0

	for _, fossilId in available do
		local fossil = FossilConfig.getFossil(fossilId)
		if fossil then
			local rarity = RarityConfig.getRarity(fossil.Rarity)
			local baseWeight = if rarity then rarity.Weight else 10

			-- Apply zone rarity multiplier if defined
			local zoneMultiplier = if zoneInfo.RarityMultipliers and zoneInfo.RarityMultipliers[fossil.Rarity]
				then zoneInfo.RarityMultipliers[fossil.Rarity]
				else 1.0

			-- Luck bonus increases chances of rarer items
			local order = if rarity then rarity.Order else 1
			local luckBonus = if order > 1 then (luckMultiplier - 1.0) * (order * 0.25) else 0
			local effectiveWeight = math.max(0.01, (baseWeight * zoneMultiplier) * (1.0 + luckBonus))

			table.insert(candidates, {
				fossilId = fossilId,
				weight = effectiveWeight,
			})
			totalWeight += effectiveWeight
		end
	end

	if totalWeight <= 0 or #candidates == 0 then
		-- Fallback to first available fossil
		return available[1]
	end

	-- Weighted random roll
	local roll = Random.new():NextNumber(0, totalWeight)
	local accumulated = 0

	for _, candidate in candidates do
		accumulated += candidate.weight
		if roll <= accumulated then
			return candidate.fossilId
		end
	end

	return candidates[#candidates].fossilId
end

-------------------------------------------------------------------------
-- EXCAVATION REQUEST HANDLER
-------------------------------------------------------------------------

local function handleRequestExcavation(player: Player, spot: Instance)
	if not player or not spot then return end

	-- 1. Validate spot existence and location
	if typeof(spot) ~= "Instance" or not spot:IsDescendantOf(workspace) then
		if excavationResultRemote then
			excavationResultRemote:FireClient(player, {
				Success = false,
				Reason = "Invalid excavation spot.",
			})
		end
		return
	end

	local spotPos = getSpotPosition(spot)
	if not spotPos then
		if excavationResultRemote then
			excavationResultRemote:FireClient(player, {
				Success = false,
				Reason = "Excavation spot has no physical position.",
			})
		end
		return
	end

	-- 2. Validate distance from player character
	local character = player.Character
	if not character then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	local distance = (rootPart.Position - spotPos).Magnitude
	if distance > MAX_INTERACTION_DISTANCE then
		if excavationResultRemote then
			excavationResultRemote:FireClient(player, {
				Success = false,
				Reason = "Too far from excavation spot.",
			})
		end
		return
	end

	-- 3. Validate player data
	local playerData = DataService.getPlayerData(player.UserId)
	if not playerData then
		if excavationResultRemote then
			excavationResultRemote:FireClient(player, {
				Success = false,
				Reason = "Player data not loaded.",
			})
		end
		return
	end

	-- 4. Identify zone and validate player access
	local zoneId = spot:GetAttribute("ZoneID")
	if typeof(zoneId) ~= "string" or zoneId == "" then
		zoneId = "BEGINNER_SITE"
	end

	local zoneInfo = ZoneConfig.getZone(zoneId)
	if not zoneInfo then
		if excavationResultRemote then
			excavationResultRemote:FireClient(player, {
				Success = false,
				Reason = "Unknown excavation zone.",
			})
		end
		return
	end

	if not table.find(playerData.UnlockedZones, zoneId) then
		if excavationResultRemote then
			excavationResultRemote:FireClient(player, {
				Success = false,
				Reason = "Excavation zone is not unlocked.",
			})
		end
		return
	end

	if playerData.Level < zoneInfo.RequiredLevel then
		if excavationResultRemote then
			excavationResultRemote:FireClient(player, {
				Success = false,
				Reason = string.format("Level %d required for this zone.", zoneInfo.RequiredLevel),
			})
		end
		return
	end

	-- 5. Validate shovel equipment
	local shovelId = playerData.Equipment.ActiveShovel
	local shovelInfo = EquipmentConfig.getEquipment(shovelId)
	if not shovelInfo or shovelInfo.Type ~= "Shovel" then
		if excavationResultRemote then
			excavationResultRemote:FireClient(player, {
				Success = false,
				Reason = "No shovel equipped.",
			})
		end
		return
	end

	-- 6. Validate cooldown
	local effectiveCooldown = getEffectiveCooldown(zoneInfo, shovelInfo)
	local lastDig = lastExcavationTimes[player.UserId] or 0
	local elapsed = os.clock() - lastDig
	if elapsed < effectiveCooldown then
		local remaining = math.ceil(effectiveCooldown - elapsed)
		if excavationResultRemote then
			excavationResultRemote:FireClient(player, {
				Success = false,
				Reason = string.format("Cooldown active. Wait %d seconds.", remaining),
				Cooldown = remaining,
			})
		end
		return
	end

	-- Record cooldown timestamp
	lastExcavationTimes[player.UserId] = os.clock()

	-- 7. Roll fossil reward
	local chosenFossilId = rollFossil(zoneInfo, shovelInfo)
	if not chosenFossilId then
		if excavationResultRemote then
			excavationResultRemote:FireClient(player, {
				Success = false,
				Reason = "No fossils available in this zone.",
			})
		end
		return
	end

	local fossilItem = ItemUtils.createFossilItem(chosenFossilId)
	if not fossilItem then
		if excavationResultRemote then
			excavationResultRemote:FireClient(player, {
				Success = false,
				Reason = "Failed to generate fossil item.",
			})
		end
		return
	end

	-- 8. Add fossil to player inventory
	local added = InventoryService.addItem(player.UserId, fossilItem)
	if not added then
		if excavationResultRemote then
			excavationResultRemote:FireClient(player, {
				Success = false,
				Reason = "Inventory is full or unavailable.",
			})
		end
		return
	end

	-- 9. Award XP & update statistics
	playerData.XP += EconomyConfig.XPPerExcavation
	playerData.Statistics.TotalFossilsExcavated += 1

	if xpUpdatedRemote then
		xpUpdatedRemote:FireClient(player, playerData.XP)
	end

	-- Check for level up
	local nextLevel = playerData.Level + 1
	if nextLevel <= EconomyConfig.MaxLevel then
		local xpNeeded = EconomyConfig.getXPForLevel(nextLevel)
		if playerData.XP >= xpNeeded then
			playerData.Level = nextLevel
			if levelUpdatedRemote then
				levelUpdatedRemote:FireClient(player, playerData.Level)
			end
			print(string.format("[DiggingService] Player %s leveled up to Level %d!", player.Name, nextLevel))
		end
	end

	-- 10. Notify client of success
	if excavationResultRemote then
		excavationResultRemote:FireClient(player, {
			Success = true,
			FossilItem = fossilItem,
			Cooldown = effectiveCooldown,
		})
	end

	print(string.format("[DiggingService] Player %s excavated %s (%s) from %s",
		player.Name, fossilItem.ConfigID, fossilItem.Rarity, zoneInfo.Name))
end

-------------------------------------------------------------------------
-- PROXIMITY PROMPT & SPOT ATTACHMENT
-------------------------------------------------------------------------

--- Attaches an interaction ProximityPrompt to an excavation spot if not present.
function DiggingService.attachPromptToSpot(spot: Instance)
	local parentPart: BasePart? = nil
	if spot:IsA("BasePart") then
		parentPart = spot
	elseif spot:IsA("Model") then
		parentPart = spot.PrimaryPart or spot:FindFirstChildWhichIsA("BasePart")
	end

	if not parentPart then return end

	local existingPrompt = parentPart:FindFirstChildWhichIsA("ProximityPrompt")
	if not existingPrompt then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ExcavatePrompt"
		prompt.ActionText = "Excavate Fossil"
		prompt.ObjectText = "Fossil Dig Spot"
		prompt.HoldDuration = 1.0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.Parent = parentPart
	end
end

--- Auto-provisions a default excavation spot in Workspace if none exists.
function DiggingService.setupDefaultSpots()
	local digZonesFolder = workspace:FindFirstChild("DigZones")
	if not digZonesFolder then
		digZonesFolder = Instance.new("Folder")
		digZonesFolder.Name = "DigZones"
		digZonesFolder.Parent = workspace
	end

	-- Check if any spots already exist in Workspace or tagged
	local taggedSpots = CollectionService:GetTagged(EXCAVATION_SPOT_TAG)
	local folderSpots = digZonesFolder:GetChildren()

	if #taggedSpots == 0 and #folderSpots == 0 then
		-- Create a default physical excavation spot for the MVP Beginner Site
		local spot = Instance.new("Part")
		spot.Name = "BeginnerExcavationSpot"
		spot.Size = Vector3.new(6, 0.8, 6)
		spot.Position = Vector3.new(0, 0.4, 16)
		spot.Anchored = true
		spot.CanCollide = true
		spot.Material = Enum.Material.Ground
		spot.Color = Color3.fromRGB(115, 80, 45)
		spot:SetAttribute("ZoneID", "BEGINNER_SITE")
		spot.Parent = digZonesFolder

		CollectionService:AddTag(spot, EXCAVATION_SPOT_TAG)
		DiggingService.attachPromptToSpot(spot)
		print("[DiggingService] Auto-provisioned default Beginner Excavation Spot at (0, 0.4, 16).")
	else
		-- Attach prompts to existing spots
		for _, spot in taggedSpots do
			DiggingService.attachPromptToSpot(spot)
		end
		for _, spot in folderSpots do
			if spot:IsA("BasePart") or spot:IsA("Model") then
				CollectionService:AddTag(spot, EXCAVATION_SPOT_TAG)
				DiggingService.attachPromptToSpot(spot)
			end
		end
	end
end

-------------------------------------------------------------------------
-- SERVICE INITIALIZATION
-------------------------------------------------------------------------

function DiggingService.init()
	DataService = require(ServerScriptService.Services.DataService)
	InventoryService = require(ServerScriptService.Services.InventoryService)

	remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10) :: Folder?
	if remoteEventsFolder then
		requestExcavationRemote = remoteEventsFolder:WaitForChild("RequestExcavation", 5) :: RemoteEvent?
		excavationResultRemote = remoteEventsFolder:WaitForChild("ExcavationResult", 5) :: RemoteEvent?
		xpUpdatedRemote = remoteEventsFolder:WaitForChild("XPUpdated", 5) :: RemoteEvent?
		levelUpdatedRemote = remoteEventsFolder:WaitForChild("LevelUpdated", 5) :: RemoteEvent?

		if requestExcavationRemote then
			requestExcavationRemote.OnServerEvent:Connect(handleRequestExcavation)
		end
	end

	-- Listen for dynamically added excavation spots
	CollectionService:GetInstanceAddedSignal(EXCAVATION_SPOT_TAG):Connect(function(spot)
		DiggingService.attachPromptToSpot(spot)
	end)

	-- Auto-provision spots
	DiggingService.setupDefaultSpots()

	-- Clean up cooldowns when players leave
	Players.PlayerRemoving:Connect(function(player)
		lastExcavationTimes[player.UserId] = nil
	end)

	print("[DiggingService] Initialized.")
end

return DiggingService
