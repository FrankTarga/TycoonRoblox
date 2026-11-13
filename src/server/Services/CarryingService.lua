--!strict
--[[
	CarryingService
	Authoritative server service for carrying and placing items in the 3D world.

	Key Rules:
	  1. The inventory system is independent from the physical carrying system.
	  2. Selecting an item attaches its 3D model to the character's hand.
	  3. Items remain safely in the player's inventory while being carried.
	  4. Items are ONLY removed from inventory upon successful placement into a machine or cage.
	  5. The server strictly validates item ownership, distance, and placement compatibility.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

-- Shared modules & configs
local Types = require(ReplicatedStorage.Modules.Types)
local ItemUtils = require(ReplicatedStorage.Modules.ItemUtils)

local CarryingService = {}

-- Server service dependencies
local DataService = nil
local InventoryService = nil

-- Remotes
local remoteEventsFolder: Folder? = nil
local requestCarryItemRemote: RemoteEvent? = nil
local carryStateChangedRemote: RemoteEvent? = nil

-- Active carrying state: UserId -> ItemUID
local activeCarriedItems: { [number]: string } = {}

-- Active physical visual models: UserId -> Model
local activeVisualModels: { [number]: Model } = {}

-------------------------------------------------------------------------
-- VISUAL ATTACHMENT HELPERS
-------------------------------------------------------------------------

--- Finds the right hand or right arm of a character (R15 or R6).
local function getAttachmentHand(character: Model): BasePart?
	return (character:FindFirstChild("RightHand")
		or character:FindFirstChild("Right Arm")
		or character:FindFirstChild("RightUpperArm")) :: BasePart?
end

--- Removes and destroys any existing carried model for a player.
local function destroyVisualModel(userId: number)
	local model = activeVisualModels[userId]
	if model then
		model:Destroy()
		activeVisualModels[userId] = nil
	end
end

--- Creates or attaches the physical visual model for the carried item.
-- If custom 3D models are not yet placed in ReplicatedStorage.Assets,
-- it creates a clean, lightweight placeholder part adorned with a billboard UI.
local function spawnVisualModel(player: Player, item: Types.ItemData): Model?
	local character = player.Character
	if not character then return nil end

	local hand = getAttachmentHand(character)
	if not hand then return nil end

	destroyVisualModel(player.UserId)

	-- Check for existing asset in ReplicatedStorage.Assets.Items
	local assetsFolder = ReplicatedStorage:FindFirstChild("Assets") :: Folder?
	local itemsFolder = if assetsFolder then assetsFolder:FindFirstChild("Items") :: Folder? else nil
	local customAsset = if itemsFolder then itemsFolder:FindFirstChild(item.ConfigID) :: Model? else nil

	local carriedModel: Model

	if customAsset and customAsset:IsA("Model") then
		carriedModel = customAsset:Clone()
	else
		-- Create a clean placeholder model
		carriedModel = Instance.new("Model")
		carriedModel.Name = "CarriedItemVisual"

		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(0.8, 0.8, 0.8)
		handle.CanCollide = false
		handle.Massless = true
		handle.CastShadow = false
		handle.Material = Enum.Material.SmoothPlastic
		handle.Color = ItemUtils.getRarityColor(item)
		handle.Parent = carriedModel
		carriedModel.PrimaryPart = handle

		-- Billboard displaying item name and rarity
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "ItemInfo"
		billboard.Size = UDim2.new(0, 140, 0, 36)
		billboard.StudsOffset = Vector3.new(0, 1.2, 0)
		billboard.AlwaysOnTop = true
		billboard.MaxDistance = 30
		billboard.Adornee = handle

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 0.5
		label.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
		label.TextColor3 = ItemUtils.getRarityColor(item)
		label.TextSize = 13
		label.Font = Enum.Font.GothamBold
		label.Text = string.format("%s\n[%s]", ItemUtils.getDisplayName(item), item.Rarity)
		label.Parent = billboard
		billboard.Parent = handle
	end

	local handlePart = carriedModel.PrimaryPart or carriedModel:FindFirstChildWhichIsA("BasePart")
	if handlePart then
		handlePart.CanCollide = false
		handlePart.Massless = true
		handlePart.CFrame = hand.CFrame * CFrame.new(0, -0.2, -0.6)

		local weld = Instance.new("WeldConstraint")
		weld.Name = "CarriedItemWeld"
		weld.Part0 = hand
		weld.Part1 = handlePart
		weld.Parent = handlePart
	end

	carriedModel.Parent = character
	activeVisualModels[player.UserId] = carriedModel

	return carriedModel
end

-------------------------------------------------------------------------
-- CORE CARRYING OPERATIONS
-------------------------------------------------------------------------

--- Checks whether a player is currently carrying an item.
function CarryingService.isCarrying(userId: number): boolean
	return activeCarriedItems[userId] ~= nil
end

--- Retrieves the ItemUID of the item currently being carried by a player.
function CarryingService.getCarriedUID(userId: number): string?
	return activeCarriedItems[userId]
end

--- Retrieves the full ItemData of the item currently being carried by a player.
function CarryingService.getCarriedItem(userId: number): Types.ItemData?
	local uid = activeCarriedItems[userId]
	if not uid or not InventoryService then return nil end
	return InventoryService.getItem(userId, uid)
end

--- Authoritatively clears / unequips the carried item without removing it from inventory.
function CarryingService.clearCarriedItem(userId: number): boolean
	destroyVisualModel(userId)
	activeCarriedItems[userId] = nil

	local player = Players:GetPlayerByUserId(userId)
	if player and carryStateChangedRemote then
		carryStateChangedRemote:FireClient(player, {
			ItemUID = nil,
			ItemData = nil,
		})
	end

	return true
end

--- Authoritatively sets the carried item for a player after validating ownership.
-- Passing nil or an empty string unequips the current item.
function CarryingService.setCarriedItem(userId: number, itemUID: string?): (boolean, string?)
	if itemUID == nil or itemUID == "" then
		CarryingService.clearCarriedItem(userId)
		return true, "Item unequipped"
	end

	if not InventoryService then
		return false, "InventoryService not available"
	end

	-- 1. Validate that the player actually owns this item
	local item = InventoryService.getItem(userId, itemUID)
	if not item then
		warn(string.format("[CarryingService] Player %d attempted to carry unowned item: %s", userId, tostring(itemUID)))
		return false, "You do not own this item"
	end

	-- 2. Update carried state
	activeCarriedItems[userId] = itemUID

	-- 3. Spawn visual 3D model if player has an active character
	local player = Players:GetPlayerByUserId(userId)
	if player then
		spawnVisualModel(player, item)

		if carryStateChangedRemote then
			carryStateChangedRemote:FireClient(player, {
				ItemUID = itemUID,
				ItemData = item,
			})
		end
	end

	return true, "Item equipped"
end

--- Consumes the currently carried item.
-- Used when placing an item into a machine or cage.
-- This removes the item from inventory, destroys the physical model, and resets carried state.
function CarryingService.consumeCarriedItem(userId: number): Types.ItemData?
	local itemUID = activeCarriedItems[userId]
	if not itemUID or not InventoryService then
		return nil
	end

	-- Remove from inventory
	local removedItem = InventoryService.removeItem(userId, itemUID)

	-- Destroy visual model and clear carrying state
	destroyVisualModel(userId)
	activeCarriedItems[userId] = nil

	local player = Players:GetPlayerByUserId(userId)
	if player and carryStateChangedRemote then
		carryStateChangedRemote:FireClient(player, {
			ItemUID = nil,
			ItemData = nil,
		})
	end

	return removedItem
end

-------------------------------------------------------------------------
-- PLACEMENT VALIDATION
-------------------------------------------------------------------------

--- Validates whether the carried item can be placed into the specified machine.
function CarryingService.validateMachinePlacement(userId: number, machineID: string): (boolean, string?)
	local item = CarryingService.getCarriedItem(userId)
	if not item then
		return false, "No item being carried"
	end

	if not ItemUtils.isCompatibleWithMachine(item, machineID) then
		if item.ItemType == "Fossil" and not item.IsCleaned then
			return false, "Fossil must be cleaned before DNA extraction"
		end
		return false, "Item is not compatible with this machine"
	end

	return true, "Compatible"
end

--- Validates whether the carried item can be placed into a cage.
function CarryingService.validateCagePlacement(userId: number): (boolean, string?)
	local item = CarryingService.getCarriedItem(userId)
	if not item then
		return false, "No item being carried"
	end

	if not ItemUtils.canPlaceInCage(item) then
		return false, "Only living dinosaurs can be placed in cages"
	end

	return true, "Compatible"
end

-------------------------------------------------------------------------
-- INITIALIZATION & NETWORKING
-------------------------------------------------------------------------

function CarryingService.init()
	DataService = require(ServerScriptService.Services.DataService)
	InventoryService = require(ServerScriptService.Services.InventoryService)

	remoteEventsFolder = ReplicatedStorage:WaitForChild("RemoteEvents", 10) :: Folder?
	if remoteEventsFolder then
		requestCarryItemRemote = remoteEventsFolder:WaitForChild("RequestCarryItem", 5) :: RemoteEvent?
		carryStateChangedRemote = remoteEventsFolder:WaitForChild("CarryStateChanged", 5) :: RemoteEvent?

		if requestCarryItemRemote then
			requestCarryItemRemote.OnServerEvent:Connect(function(player: Player, itemUID: any)
				if typeof(itemUID) ~= "string" and itemUID ~= nil then
					return
				end
				CarryingService.setCarriedItem(player.UserId, itemUID)
			end)
		end
	end

	-- Clean up on player leaving or character respawning
	Players.PlayerRemoving:Connect(function(player)
		destroyVisualModel(player.UserId)
		activeCarriedItems[player.UserId] = nil
	end)

	Players.PlayerAdded:Connect(function(player)
		player.CharacterRemoving:Connect(function()
			destroyVisualModel(player.UserId)
		end)
		player.CharacterAdded:Connect(function()
			-- If player was carrying an item when respawning, reattach visual model
			local itemUID = activeCarriedItems[player.UserId]
			if itemUID and InventoryService then
				local item = InventoryService.getItem(player.UserId, itemUID)
				if item then
					task.defer(function()
						spawnVisualModel(player, item)
					end)
				else
					activeCarriedItems[player.UserId] = nil
				end
			end
		end)
	end)

	print("[CarryingService] Initialized.")
end

return CarryingService
