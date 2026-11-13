--!strict
--[[
	CageController
	Client-side controller for dinosaur cages and passive income collection.

	Handles:
	  1. CagePlacementPrompt: Validates carried dinosaur and fires RequestPlaceDinosaur.
	  2. CageCollectPrompt: Fires RequestCollectIncome.
	  3. Listens to CageUpdated and MoneyUpdated events to provide player feedback.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local CageController = {}

local player = Players.LocalPlayer
local CarryController = nil

local requestPlaceDinosaurRemote: RemoteEvent? = nil
local requestCollectIncomeRemote: RemoteEvent? = nil
local cageUpdatedRemote: RemoteEvent? = nil
local moneyUpdatedRemote: RemoteEvent? = nil

local pendingRequest = false

local function showCageFeedback(success: boolean, msg: string)
	local prefix = if success then "[Cage OK]" else "[Cage INFO]"
	print(string.format("%s %s", prefix, msg))
end

local function onPromptTriggered(prompt: ProximityPrompt, triggeredPlayer: Player)
	if triggeredPlayer ~= player then return end
	if pendingRequest then return end

	local cage = prompt.Parent
	if not cage then return end

	local cageId = cage:GetAttribute("CageID") or "CAGE_1"

	-- -----------------------------------------------------------
	-- Place Dinosaur
	-- -----------------------------------------------------------
	if prompt.Name == "CagePlacementPrompt" then
		if not CarryController then return end

		local carried = CarryController.getCarriedItem()
		if not carried then
			showCageFeedback(false, "Pick up a dinosaur from your inventory first.")
			return
		end

		if carried.ItemType ~= "Dinosaur" then
			showCageFeedback(false, "Only dinosaurs can be placed inside cages.")
			return
		end

		pendingRequest = true
		if requestPlaceDinosaurRemote then
			requestPlaceDinosaurRemote:FireServer(cage, cageId)
		end
		task.delay(1.5, function() pendingRequest = false end)

	-- -----------------------------------------------------------
	-- Collect Income
	-- -----------------------------------------------------------
	elseif prompt.Name == "CageCollectPrompt" then
		pendingRequest = true
		if requestCollectIncomeRemote then
			requestCollectIncomeRemote:FireServer(cage, cageId)
		end
		task.delay(1.5, function() pendingRequest = false end)
	end
end

local function onCageUpdated(payload: any)
	if typeof(payload) ~= "table" then return end
	if payload.DinosaurID then
		showCageFeedback(true, string.format("Cage %s now houses %s!", tostring(payload.CageID), tostring(payload.DinosaurID)))
	else
		showCageFeedback(true, string.format("Cage %s is now empty.", tostring(payload.CageID)))
	end
end

local function onMoneyUpdated(newMoney: any)
	if typeof(newMoney) == "number" then
		print(string.format("[Economy] Current Balance: $%d", newMoney))
	end
end

function CageController.init()
	local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10) :: Folder?
	CarryController = require(script.Parent:WaitForChild("CarryController"))

	if remoteEvents then
		requestPlaceDinosaurRemote = remoteEvents:WaitForChild("RequestPlaceDinosaur", 5) :: RemoteEvent?
		requestCollectIncomeRemote = remoteEvents:WaitForChild("RequestCollectIncome", 5) :: RemoteEvent?
		cageUpdatedRemote          = remoteEvents:WaitForChild("CageUpdated", 5) :: RemoteEvent?
		moneyUpdatedRemote         = remoteEvents:WaitForChild("MoneyUpdated", 5) :: RemoteEvent?

		if cageUpdatedRemote then
			cageUpdatedRemote.OnClientEvent:Connect(onCageUpdated)
		end
		if moneyUpdatedRemote then
			moneyUpdatedRemote.OnClientEvent:Connect(onMoneyUpdated)
		end
	end

	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)

	print("[CageController] Initialized.")
end

return CageController

