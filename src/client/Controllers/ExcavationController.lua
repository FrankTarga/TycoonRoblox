--!strict
--[[
	ExcavationController
	Client-side controller for excavation interactions.
	
	Responsibilities:
	  1. Detects physical player interaction with excavation spots via ProximityPrompt.
	  2. Sends authoritative excavation requests to DiggingService.
	  3. Provides visual/audio/text feedback for excavation results and cooldowns.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Types = require(ReplicatedStorage.Modules.Types)
local ItemUtils = require(ReplicatedStorage.Modules.ItemUtils)

local ExcavationController = {}

local player = Players.LocalPlayer
local requestExcavationRemote: RemoteEvent? = nil
local excavationResultRemote: RemoteEvent? = nil

local isRequestPending = false
local clientCooldownEnd = 0

-------------------------------------------------------------------------
-- FEEDBACK HELPER
-------------------------------------------------------------------------

local function showExcavationFeedback(success: boolean, message: string, color: Color3?)
	local prefix = if success then "[Excavation SUCCESS]" else "[Excavation INFO]"
	local outputColor = color or (if success then Color3.fromRGB(80, 220, 100) else Color3.fromRGB(255, 120, 100))

	print(string.format("%s %s", prefix, message))

	-- Display in TextChatService if supported, or standard output
	-- Future phases will hook this directly to MachineUI / HUD
end

-------------------------------------------------------------------------
-- EXCAVATION INTERACTION
-------------------------------------------------------------------------

local function onPromptTriggered(prompt: ProximityPrompt, triggeredPlayer: Player)
	if triggeredPlayer ~= player then return end
	if prompt.Name ~= "ExcavatePrompt" then return end

	local spot = prompt.Parent
	if not spot then return end

	-- Check client-side cooldown to avoid spamming server
	local now = os.clock()
	if now < clientCooldownEnd then
		local remaining = math.ceil(clientCooldownEnd - now)
		showExcavationFeedback(false, string.format("Please wait %d seconds before excavating again.", remaining))
		return
	end

	if isRequestPending then
		return
	end

	isRequestPending = true

	if requestExcavationRemote then
		requestExcavationRemote:FireServer(spot)
	else
		warn("[ExcavationController] RequestExcavation remote not available.")
		isRequestPending = false
	end
end

-------------------------------------------------------------------------
-- SERVER RESULT HANDLER
-------------------------------------------------------------------------

type ExcavationResultPayload = {
	Success: boolean,
	FossilItem: Types.ItemData?,
	Reason: string?,
	Cooldown: number?,
}

local function onExcavationResult(result: ExcavationResultPayload)
	isRequestPending = false

	if result.Success and result.FossilItem then
		local fossilName = ItemUtils.getDisplayName(result.FossilItem)
		local rarity = result.FossilItem.Rarity
		local rarityColor = ItemUtils.getRarityColor(result.FossilItem)

		if result.Cooldown then
			clientCooldownEnd = os.clock() + result.Cooldown
		end

		showExcavationFeedback(
			true,
			string.format("Discovered %s (%s)! Added to inventory.", fossilName, rarity),
			rarityColor
		)
	else
		local reason = result.Reason or "Excavation failed."
		if result.Cooldown then
			clientCooldownEnd = os.clock() + result.Cooldown
		end

		showExcavationFeedback(false, reason)
	end
end

-------------------------------------------------------------------------
-- INITIALIZATION
-------------------------------------------------------------------------

function ExcavationController.init()
	local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10) :: Folder?
	if not remoteEvents then
		warn("[ExcavationController] RemoteEvents folder not found!")
		return
	end

	requestExcavationRemote = remoteEvents:WaitForChild("RequestExcavation", 5) :: RemoteEvent?
	excavationResultRemote = remoteEvents:WaitForChild("ExcavationResult", 5) :: RemoteEvent?

	if excavationResultRemote then
		excavationResultRemote.OnClientEvent:Connect(onExcavationResult)
	end

	-- Listen globally to ProximityPrompt triggers
	ProximityPromptService.PromptTriggered:Connect(onPromptTriggered)

	print("[ExcavationController] Initialized.")
end

return ExcavationController
