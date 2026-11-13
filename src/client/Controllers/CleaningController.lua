--!strict
--[[
	CleaningController
	Client-side controller for interacting with fossil cleaning stations.

	Responsibilities:
	  1. Listens to ProximityPrompt triggers on Cleaning Stations.
	  2. Performs quick client-side validation against CarryController to provide instant feedback.
	  3. Fires RequestCleanFossil to the server for authoritative cleaning processing.
	  4. Displays cleaning progress, quality reveals, and XP reward notifications.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Types = require(ReplicatedStorage.Modules.Types)
local ItemUtils = require(ReplicatedStorage.Modules.ItemUtils)

local CleaningController = {}

local player = Players.LocalPlayer
local CarryController = nil

local requestCleanFossilRemote: RemoteEvent? = nil
local cleaningProgressRemote: RemoteEvent? = nil

local isCleaningPending = false

-------------------------------------------------------------------------
-- FEEDBACK HELPER
-------------------------------------------------------------------------

local function showCleaningFeedback(success: boolean, message: string)
	local prefix = if success then "[Cleaning SUCCESS]" else "[Cleaning INFO]"
	print(string.format("%s %s", prefix, message))
end

-------------------------------------------------------------------------
-- PROMPT INTERACTION
-------------------------------------------------------------------------

local function onPromptTriggered(prompt: ProximityPrompt, triggeredPlayer: Player)
	if triggeredPlayer ~= player then return end
	if prompt.Name ~= "CleanPrompt" then return end

	local station = prompt.Parent
	if not station then return end

	if not CarryController then return end

	-- Client pre-validation for responsive UX
	local carriedItem = CarryController.getCarriedItem()
	if not carriedItem then
		showCleaningFeedback(false, "You must be holding a fossil in your hands to clean it.")
		return
	end

	if carriedItem.ItemType ~= "Fossil" then
		showCleaningFeedback(false, "Only raw fossils can be cleaned at this station.")
		return
	end

	if carriedItem.IsCleaned then
		showCleaningFeedback(false, "This fossil has already been cleaned and prepped for DNA extraction.")
		return
	end

	if isCleaningPending then return end
	isCleaningPending = true

	if requestCleanFossilRemote then
		requestCleanFossilRemote:FireServer(station)
	else
		isCleaningPending = false
		warn("[CleaningController] RequestCleanFossil remote not found.")
	end
end

-------------------------------------------------------------------------
-- SERVER PROGRESS / RESULT HANDLER
-------------------------------------------------------------------------

type CleaningProgressPayload = {
	Status: string,
	Progress: number,
	Item: Types.ItemData?,
	Reason: string?,
}

local function onCleaningProgress(payload: CleaningProgressPayload)
	isCleaningPending = false

	if payload.Status == "Completed" and payload.Item then
		local displayName = ItemUtils.getDisplayName(payload.Item)
		showCleaningFeedback(
			true,
			string.format("Fossil cleaned successfully! %s — Quality: %d%% (+5 XP). Ready for DNA Extractor!",
				displayName, payload.Item.Quality)
		)
	elseif payload.Status == "Failed" then
		showCleaningFeedback(false, payload.Reason or "Cleaning failed.")
	end
end

-------------------------------------------------------------------------
-- INITIALIZATION
-------------------------------------------------------------------------

function CleaningController.init()
	local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10) :: Folder?
	CarryController = require(script.Parent:WaitForChild("CarryController"))

	if remoteEvents then
		requestCleanFossilRemote = remoteEvents:WaitForChild("RequestCleanFossil", 5) :: RemoteEvent?
		cleaningProgressRemote = remoteEvents:WaitForChild("CleaningProgress", 5) :: RemoteEvent?

		if cleaningProgressRemote then
			cleaningProgressRemote.OnClientEvent:Connect(onCleaningProgress)
		end
	end

	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)

	print("[CleaningController] Initialized.")
end

return CleaningController
