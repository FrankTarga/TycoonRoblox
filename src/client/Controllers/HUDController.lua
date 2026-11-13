--!strict
--[[
	HUDController
	Client-side head-up display (HUD) for Dinosaur Fossil Tycoon.

	Displays in real-time:
	  1. Currency balance ($).
	  2. Player Level and XP progress bar.
	  3. Equipped shovel and brush names.
	  4. Floating on-screen notification messages for actions, discoveries, and leveling up.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local EconomyConfig = require(ReplicatedStorage.Configurations.EconomyConfig)
local EquipmentConfig = require(ReplicatedStorage.Configurations.EquipmentConfig)

local HUDController = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local screenGui: ScreenGui? = nil
local moneyLabel: TextLabel? = nil
local levelLabel: TextLabel? = nil
local xpFill: Frame? = nil
local toolLabel: TextLabel? = nil
local notificationContainer: Frame? = nil

local currentMoney = 100
local currentLevel = 1
local currentXP = 0
local activeShovel = "BASIC_SHOVEL"
local activeBrush = "BASIC_BRUSH"

-------------------------------------------------------------------------
-- UI BUILDER (Procedural Roblox GUI)
-------------------------------------------------------------------------

local function buildHUD()
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "TycoonHUD"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	-- Main stats panel (top-left)
	local statsFrame = Instance.new("Frame")
	statsFrame.Name = "StatsFrame"
	statsFrame.Size = UDim2.new(0, 240, 0, 110)
	statsFrame.Position = UDim2.new(0, 16, 0, 16)
	statsFrame.BackgroundColor3 = Color3.fromRGB(25, 28, 35)
	statsFrame.BackgroundTransparency = 0.15
	statsFrame.BorderSizePixel = 0
	statsFrame.Parent = screenGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = statsFrame

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(50, 60, 80)
	stroke.Thickness = 1.5
	stroke.Parent = statsFrame

	-- Money display
	moneyLabel = Instance.new("TextLabel")
	moneyLabel.Name = "MoneyLabel"
	moneyLabel.Size = UDim2.new(1, -20, 0, 30)
	moneyLabel.Position = UDim2.new(0, 10, 0, 8)
	moneyLabel.BackgroundTransparency = 1
	moneyLabel.TextColor3 = Color3.fromRGB(85, 230, 110)
	moneyLabel.TextSize = 20
	moneyLabel.Font = Enum.Font.GothamBold
	moneyLabel.TextXAlignment = Enum.TextXAlignment.Left
	moneyLabel.Text = "$100"
	moneyLabel.Parent = statsFrame

	-- Level display
	levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "LevelLabel"
	levelLabel.Size = UDim2.new(1, -20, 0, 20)
	levelLabel.Position = UDim2.new(0, 10, 0, 38)
	levelLabel.BackgroundTransparency = 1
	levelLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
	levelLabel.TextSize = 13
	levelLabel.Font = Enum.Font.GothamMedium
	levelLabel.TextXAlignment = Enum.TextXAlignment.Left
	levelLabel.Text = "Level 1"
	levelLabel.Parent = statsFrame

	-- XP bar background
	local xpBg = Instance.new("Frame")
	xpBg.Name = "XPBarBg"
	xpBg.Size = UDim2.new(1, -20, 0, 8)
	xpBg.Position = UDim2.new(0, 10, 0, 62)
	xpBg.BackgroundColor3 = Color3.fromRGB(40, 45, 55)
	xpBg.BorderSizePixel = 0
	xpBg.Parent = statsFrame

	local xpCorner = Instance.new("UICorner")
	xpCorner.CornerRadius = UDim.new(1, 0)
	xpCorner.Parent = xpBg

	-- XP bar fill
	xpFill = Instance.new("Frame")
	xpFill.Name = "XPFill"
	xpFill.Size = UDim2.new(0, 0, 1, 0)
	xpFill.BackgroundColor3 = Color3.fromRGB(70, 170, 255)
	xpFill.BorderSizePixel = 0
	xpFill.Parent = xpBg

	local xpFillCorner = Instance.new("UICorner")
	xpFillCorner.CornerRadius = UDim.new(1, 0)
	xpFillCorner.Parent = xpFill

	-- Tools display
	toolLabel = Instance.new("TextLabel")
	toolLabel.Name = "ToolLabel"
	toolLabel.Size = UDim2.new(1, -20, 0, 20)
	toolLabel.Position = UDim2.new(0, 10, 0, 78)
	toolLabel.BackgroundTransparency = 1
	toolLabel.TextColor3 = Color3.fromRGB(160, 175, 195)
	toolLabel.TextSize = 11
	toolLabel.Font = Enum.Font.Gotham
	toolLabel.TextXAlignment = Enum.TextXAlignment.Left
	toolLabel.Text = "Shovel: Basic | Brush: Basic"
	toolLabel.Parent = statsFrame

	-- Notification container (top-center)
	notificationContainer = Instance.new("Frame")
	notificationContainer.Name = "Notifications"
	notificationContainer.Size = UDim2.new(0, 320, 0, 120)
	notificationContainer.Position = UDim2.new(0.5, -160, 0, 20)
	notificationContainer.BackgroundTransparency = 1
	notificationContainer.Parent = screenGui
end

-------------------------------------------------------------------------
-- UPDATE HELPERS
-------------------------------------------------------------------------

local function updateHUD()
	if moneyLabel then
		moneyLabel.Text = string.format("$%d", currentMoney)
	end

	local nextLevel = currentLevel + 1
	local neededXP = EconomyConfig.getXPForLevel(nextLevel)
	local prevLevelXP = EconomyConfig.getXPForLevel(currentLevel)
	local progress = 0

	if neededXP > prevLevelXP then
		progress = math.clamp((currentXP - prevLevelXP) / (neededXP - prevLevelXP), 0, 1)
	end

	if levelLabel then
		levelLabel.Text = string.format("Level %d (%d / %d XP)", currentLevel, currentXP, neededXP)
	end

	if xpFill then
		xpFill.Size = UDim2.new(progress, 0, 1, 0)
	end

	if toolLabel then
		local shovelInfo = EquipmentConfig.getEquipment(activeShovel)
		local brushInfo = EquipmentConfig.getEquipment(activeBrush)
		local sName = if shovelInfo then shovelInfo.Name else activeShovel
		local bName = if brushInfo then brushInfo.Name else activeBrush
		toolLabel.Text = string.format("%s | %s", sName, bName)
	end
end

--- Displays an on-screen toast notification.
function HUDController.notify(text: string, color: Color3?)
	if not notificationContainer then return end

	local toast = Instance.new("TextLabel")
	toast.Size = UDim2.new(1, 0, 0, 28)
	toast.BackgroundColor3 = Color3.fromRGB(20, 24, 30)
	toast.BackgroundTransparency = 0.2
	toast.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	toast.TextSize = 13
	toast.Font = Enum.Font.GothamBold
	toast.Text = text
	toast.Parent = notificationContainer

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = toast

	task.delay(3.0, function()
		local fade = TweenService:Create(toast, TweenInfo.new(0.5), {
			TextTransparency = 1,
			BackgroundTransparency = 1,
		})
		fade:Play()
		fade.Completed:Connect(function()
			toast:Destroy()
		end)
	end)
end

-------------------------------------------------------------------------
-- INITIALIZATION
-------------------------------------------------------------------------

function HUDController.init()
	local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10) :: Folder?

	buildHUD()
	updateHUD()

	if remoteEvents then
		local moneyRemote = remoteEvents:WaitForChild("MoneyUpdated", 5) :: RemoteEvent?
		local xpRemote    = remoteEvents:WaitForChild("XPUpdated", 5) :: RemoteEvent?
		local levelRemote = remoteEvents:WaitForChild("LevelUpdated", 5) :: RemoteEvent?
		local equipRemote = remoteEvents:WaitForChild("EquipmentUpdated", 5) :: RemoteEvent?
		local initRemote  = remoteEvents:WaitForChild("PlayerDataLoaded", 5) :: RemoteEvent?

		if initRemote then
			initRemote.OnClientEvent:Connect(function(data: any)
				if typeof(data) == "table" then
					currentMoney = data.Money or currentMoney
					currentLevel = data.Level or currentLevel
					currentXP = data.XP or currentXP
					if data.Equipment then
						activeShovel = data.Equipment.ActiveShovel or activeShovel
						activeBrush = data.Equipment.ActiveBrush or activeBrush
					end
					updateHUD()
				end
			end)
		end

		if moneyRemote then
			moneyRemote.OnClientEvent:Connect(function(newMoney: number)
				if typeof(newMoney) == "number" then
					local diff = newMoney - currentMoney
					currentMoney = newMoney
					updateHUD()
					if diff > 0 then
						HUDController.notify(string.format("+$%d Earned!", diff), Color3.fromRGB(90, 230, 110))
					end
				end
			end)
		end

		if xpRemote then
			xpRemote.OnClientEvent:Connect(function(newXP: number)
				if typeof(newXP) == "number" then
					currentXP = newXP
					updateHUD()
				end
			end)
		end

		if levelRemote then
			levelRemote.OnClientEvent:Connect(function(newLevel: number)
				if typeof(newLevel) == "number" then
					currentLevel = newLevel
					updateHUD()
					HUDController.notify(string.format("🎉 LEVEL UP! You reached Level %d!", newLevel), Color3.fromRGB(255, 215, 0))
				end
			end)
		end

		if equipRemote then
			equipRemote.OnClientEvent:Connect(function(equipData: any)
				if typeof(equipData) == "table" then
					activeShovel = equipData.ActiveShovel or activeShovel
					activeBrush = equipData.ActiveBrush or activeBrush
					updateHUD()
				end
			end)
		end
	end

	print("[HUDController] Initialized.")
end

return HUDController
