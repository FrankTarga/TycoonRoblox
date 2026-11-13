--!strict
--[[
	ProgressionService
	Authoritative server service for economy, equipment store, zone unlocks,
	plot expansions, cage purchases, and fossil selling.

	All currency transactions and progression checks are strictly validated on the server.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Shared configs & modules
local Types = require(ReplicatedStorage.Modules.Types)
local EquipmentConfig = require(ReplicatedStorage.Configurations.EquipmentConfig)
local ZoneConfig = require(ReplicatedStorage.Configurations.ZoneConfig)
local EconomyConfig = require(ReplicatedStorage.Configurations.EconomyConfig)
local FossilConfig = require(ReplicatedStorage.Configurations.FossilConfig)

local ProgressionService = {}

-- Service dependencies
local DataService = nil
local InventoryService = nil

-- Remotes
local remoteEventsFolder: Folder? = nil
local moneyUpdatedRemote: RemoteEvent? = nil
local equipmentUpdatedRemote: RemoteEvent? = nil
local zonesUpdatedRemote: RemoteEvent? = nil
local plotUpdatedRemote: RemoteEvent? = nil

-------------------------------------------------------------------------
-- INTERNAL NOTIFIERS
-------------------------------------------------------------------------

local function notifyMoney(userId: number, data: Types.PlayerData)
	local player = Players:GetPlayerByUserId(userId)
	if not player then return end
	if moneyUpdatedRemote then
		moneyUpdatedRemote:FireClient(player, data.Money)
	end
end

local function notifyEquipment(userId: number, data: Types.PlayerData)
	local player = Players:GetPlayerByUserId(userId)
	if not player then return end
	if equipmentUpdatedRemote then
		equipmentUpdatedRemote:FireClient(player, data.Equipment)
	end
end

local function notifyZones(userId: number, data: Types.PlayerData)
	local player = Players:GetPlayerByUserId(userId)
	if not player then return end
	if zonesUpdatedRemote then
		zonesUpdatedRemote:FireClient(player, data.UnlockedZones)
	end
end

local function notifyPlot(userId: number, data: Types.PlayerData)
	local player = Players:GetPlayerByUserId(userId)
	if not player then return end
	if plotUpdatedRemote then
		plotUpdatedRemote:FireClient(player, data.PlotData)
	end
end

-------------------------------------------------------------------------
-- PUBLIC API — EQUIPMENT STORE
-------------------------------------------------------------------------

--- Validates and purchases a tool/equipment.
function ProgressionService.buyEquipment(userId: number, equipmentId: string): (boolean, string?)
	if not DataService then return false, "DataService unavailable" end
	local data = DataService.getPlayerData(userId)
	if not data then return false, "Player data not found" end

	local info = EquipmentConfig.getEquipment(equipmentId)
	if not info then return false, "Equipment not found" end

	-- Check if already owned
	if table.find(data.Equipment.OwnedEquipment, equipmentId) then
		return false, "Equipment already owned"
	end

	-- Check level requirement
	if data.Level < info.RequiredLevel then
		return false, "Level requirement not met"
	end

	-- Check funds
	if data.Money < info.Cost then
		return false, "Insufficient funds"
	end

	-- Deduct money & add equipment
	data.Money -= info.Cost
	table.insert(data.Equipment.OwnedEquipment, equipmentId)

	-- Auto-equip
	if info.Type == "Shovel" then
		data.Equipment.ActiveShovel = equipmentId
	elseif info.Type == "Brush" then
		data.Equipment.ActiveBrush = equipmentId
	end

	notifyMoney(userId, data)
	notifyEquipment(userId, data)

	print(string.format("[ProgressionService] Player %d bought %s for $%d.", userId, info.Name, info.Cost))
	return true, "Equipment purchased"
end

--- Equips an already owned tool.
function ProgressionService.equipItem(userId: number, equipmentId: string): (boolean, string?)
	if not DataService then return false, "DataService unavailable" end
	local data = DataService.getPlayerData(userId)
	if not data then return false, "Player data not found" end

	local info = EquipmentConfig.getEquipment(equipmentId)
	if not info then return false, "Equipment not found" end

	if not table.find(data.Equipment.OwnedEquipment, equipmentId) then
		return false, "Equipment not owned"
	end

	if info.Type == "Shovel" then
		data.Equipment.ActiveShovel = equipmentId
	elseif info.Type == "Brush" then
		data.Equipment.ActiveBrush = equipmentId
	end

	notifyEquipment(userId, data)
	return true, "Equipped"
end

-------------------------------------------------------------------------
-- PUBLIC API — ZONE UNLOCKS
-------------------------------------------------------------------------

--- Validates and unlocks an excavation zone.
function ProgressionService.unlockZone(userId: number, zoneId: string): (boolean, string?)
	if not DataService then return false, "DataService unavailable" end
	local data = DataService.getPlayerData(userId)
	if not data then return false, "Player data not found" end

	local zoneInfo = ZoneConfig.getZone(zoneId)
	if not zoneInfo then return false, "Zone not found" end

	if table.find(data.UnlockedZones, zoneId) then
		return false, "Zone already unlocked"
	end

	if data.Level < zoneInfo.RequiredLevel then
		return false, "Level requirement not met"
	end

	if data.Money < zoneInfo.UnlockCost then
		return false, "Insufficient funds"
	end

	data.Money -= zoneInfo.UnlockCost
	table.insert(data.UnlockedZones, zoneId)

	notifyMoney(userId, data)
	notifyZones(userId, data)

	print(string.format("[ProgressionService] Player %d unlocked zone %s for $%d.", userId, zoneInfo.Name, zoneInfo.UnlockCost))
	return true, "Zone unlocked"
end

-------------------------------------------------------------------------
-- PUBLIC API — PLOT EXPANSION & CAGES
-------------------------------------------------------------------------

--- Expands the player's plot, increasing expansion level.
function ProgressionService.expandPlot(userId: number): (boolean, string?)
	if not DataService then return false, "DataService unavailable" end
	local data = DataService.getPlayerData(userId)
	if not data then return false, "Player data not found" end

	local currentLevel = data.PlotData.ExpansionLevel
	local cost = EconomyConfig.getPlotExpansionCost(currentLevel)

	if data.Money < cost then
		return false, "Insufficient funds"
	end

	data.Money -= cost
	data.PlotData.ExpansionLevel += 1

	notifyMoney(userId, data)
	notifyPlot(userId, data)

	print(string.format("[ProgressionService] Player %d expanded plot to level %d for $%d.", userId, data.PlotData.ExpansionLevel, cost))
	return true, "Plot expanded"
end

--- Purchases an additional dinosaur cage.
function ProgressionService.buyCage(userId: number): (boolean, string?)
	if not DataService then return false, "DataService unavailable" end
	local data = DataService.getPlayerData(userId)
	if not data then return false, "Player data not found" end

	local cost = EconomyConfig.CageBaseCost
	if data.Money < cost then
		return false, "Insufficient funds"
	end

	data.Money -= cost
	data.PlotData.CageCount += 1

	notifyMoney(userId, data)
	notifyPlot(userId, data)

	print(string.format("[ProgressionService] Player %d purchased a new cage (Total: %d) for $%d.", userId, data.PlotData.CageCount, cost))
	return true, "Cage purchased"
end

-------------------------------------------------------------------------
-- PUBLIC API — FOSSIL SELLING
-------------------------------------------------------------------------

--- Sells a fossil from player inventory for cash.
function ProgressionService.sellFossil(userId: number, itemUID: string): (boolean, any)
	if not DataService or not InventoryService then return false, "Services unavailable" end
	local data = DataService.getPlayerData(userId)
	if not data then return false, "Player data not found" end

	local item = InventoryService.getItem(userId, itemUID)
	if not item then
		return false, "Item not found in inventory"
	end

	if item.ItemType ~= "Fossil" then
		return false, "Only fossils can be sold"
	end

	local fossilInfo = FossilConfig.getFossil(item.ConfigID)
	local baseValue = if fossilInfo then fossilInfo.Value else 10
	local earned = math.max(1, math.floor(baseValue * EconomyConfig.FossilSellMultiplier))

	-- Remove from inventory
	local removed = InventoryService.removeItem(userId, itemUID)
	if not removed then
		return false, "Failed to remove fossil from inventory"
	end

	data.Money += earned
	data.Statistics.TotalMoneyEarned += earned

	notifyMoney(userId, data)

	print(string.format("[ProgressionService] Player %d sold %s for $%d.", userId, item.ConfigID, earned))
	return true, earned
end

-------------------------------------------------------------------------
-- INITIALIZATION
-------------------------------------------------------------------------

function ProgressionService.init()
	DataService = require(ServerScriptService.Services.DataService)
	InventoryService = require(ServerScriptService.Services.InventoryService)

	remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10) :: Folder?
	if remoteEventsFolder then
		moneyUpdatedRemote     = remoteEventsFolder:WaitForChild("MoneyUpdated", 5) :: RemoteEvent?
		equipmentUpdatedRemote = remoteEventsFolder:WaitForChild("EquipmentUpdated", 5) :: RemoteEvent?
		zonesUpdatedRemote     = remoteEventsFolder:WaitForChild("ZonesUpdated", 5) :: RemoteEvent?
		plotUpdatedRemote      = remoteEventsFolder:WaitForChild("PlotUpdated", 5) :: RemoteEvent?

		local reqBuyEquip   = remoteEventsFolder:WaitForChild("RequestBuyEquipment", 5) :: RemoteEvent?
		local reqEquip      = remoteEventsFolder:WaitForChild("RequestEquipItem", 5) :: RemoteEvent?
		local reqUnlockZone = remoteEventsFolder:WaitForChild("RequestUnlockZone", 5) :: RemoteEvent?
		local reqExpandPlot = remoteEventsFolder:WaitForChild("RequestExpandPlot", 5) :: RemoteEvent?
		local reqBuyCage    = remoteEventsFolder:WaitForChild("RequestBuyCage", 5) :: RemoteEvent?
		local reqSellFossil = remoteEventsFolder:WaitForChild("RequestSellFossil", 5) :: RemoteEvent?

		if reqBuyEquip then
			reqBuyEquip.OnServerEvent:Connect(function(player: Player, equipId: any)
				if typeof(equipId) == "string" then
					ProgressionService.buyEquipment(player.UserId, equipId)
				end
			end)
		end

		if reqEquip then
			reqEquip.OnServerEvent:Connect(function(player: Player, equipId: any)
				if typeof(equipId) == "string" then
					ProgressionService.equipItem(player.UserId, equipId)
				end
			end)
		end

		if reqUnlockZone then
			reqUnlockZone.OnServerEvent:Connect(function(player: Player, zoneId: any)
				if typeof(zoneId) == "string" then
					ProgressionService.unlockZone(player.UserId, zoneId)
				end
			end)
		end

		if reqExpandPlot then
			reqExpandPlot.OnServerEvent:Connect(function(player: Player)
				ProgressionService.expandPlot(player.UserId)
			end)
		end

		if reqBuyCage then
			reqBuyCage.OnServerEvent:Connect(function(player: Player)
				ProgressionService.buyCage(player.UserId)
			end)
		end

		if reqSellFossil then
			reqSellFossil.OnServerEvent:Connect(function(player: Player, itemUID: any)
				if typeof(itemUID) == "string" then
					ProgressionService.sellFossil(player.UserId, itemUID)
				end
			end)
		end
	end

	print("[ProgressionService] Initialized.")
end

return ProgressionService
