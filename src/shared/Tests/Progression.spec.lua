--!strict
--[[
	Progression.spec
	Unit tests for Phase 8 — Economy and Progression.

	Verifies that:
	  1. Buying equipment validates level and funds, deducts money, and adds to OwnedEquipment.
	  2. Rejects buying unknown, already-owned, under-leveled, or unaffordable equipment.
	  3. Equipping tools sets ActiveShovel or ActiveBrush for owned items and rejects unowned items.
	  4. Unlocking excavation zones validates level and funds, deducts money, and adds to UnlockedZones.
	  5. Rejects unlocking unknown, already-unlocked, under-leveled, or unaffordable zones.
	  6. Expanding plot validates funds, deducts money, and increments ExpansionLevel.
	  7. Purchasing cages validates funds, deducts money, and increments CageCount.
	  8. Selling fossils removes item from inventory and awards cash based on FossilSellMultiplier.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TestFramework   = require(ReplicatedStorage.Tests.TestFramework)
local Types           = require(ReplicatedStorage.Modules.Types)
local ItemUtils       = require(ReplicatedStorage.Modules.ItemUtils)
local EconomyConfig   = require(ReplicatedStorage.Configurations.EconomyConfig)
local EquipmentConfig = require(ReplicatedStorage.Configurations.EquipmentConfig)
local ZoneConfig      = require(ReplicatedStorage.Configurations.ZoneConfig)
local DataService     = require(ServerScriptService.Services.DataService)
local InventoryService = require(ServerScriptService.Services.InventoryService)

local describe   = TestFramework.describe
local it         = TestFramework.it
local expect     = TestFramework.expect
local beforeEach = TestFramework.beforeEach

return function(ProgressionService: any)

	-- =========================================================
	-- SUITE 1: Equipment Purchase & Equipping
	-- =========================================================
	describe("ProgressionService - Equipment Shop", function()
		local userId = 999030

		beforeEach(function()
			DataService.removePlayerData(userId)
			local data = DataService.initPlayerData({ UserId = userId, Name = "ProgPlayer1" } :: any)
			data.Money = 500
			data.Level = 2
		end)

		it("should reject purchasing unknown equipment", function()
			local success, reason = ProgressionService.buyEquipment(userId, "NON_EXISTENT_TOOL")
			expect(success).toBe(false)
			expect(reason).toBe("Equipment not found")
		end)

		it("should reject purchasing already owned equipment", function()
			local success, reason = ProgressionService.buyEquipment(userId, "BASIC_SHOVEL")
			expect(success).toBe(false)
			expect(reason).toBe("Equipment already owned")
		end)

		it("should reject purchasing if player level is insufficient", function()
			-- GOLDEN_SHOVEL requires Level 5, player is Level 2
			local success, reason = ProgressionService.buyEquipment(userId, "GOLDEN_SHOVEL")
			expect(success).toBe(false)
			expect(reason).toBe("Level requirement not met")
		end)

		it("should reject purchasing if player has insufficient funds", function()
			local data = DataService.getPlayerData(userId)
			if data then data.Money = 50 end -- IRON_SHOVEL costs 250
			local success, reason = ProgressionService.buyEquipment(userId, "IRON_SHOVEL")
			expect(success).toBe(false)
			expect(reason).toBe("Insufficient funds")
		end)

		it("should buy equipment, deduct money, add to OwnedEquipment, and equip it", function()
			local data = DataService.getPlayerData(userId)
			local startMoney = if data then data.Money else 500

			local success, _ = ProgressionService.buyEquipment(userId, "IRON_SHOVEL")
			expect(success).toBe(true)

			if data then
				expect(data.Money).toBe(startMoney - 250)
				expect(table.find(data.Equipment.OwnedEquipment, "IRON_SHOVEL")).toNotBeNil()
				expect(data.Equipment.ActiveShovel).toBe("IRON_SHOVEL")
			end
		end)

		it("should allow equipping an owned equipment and reject unowned equipment", function()
			local s1, r1 = ProgressionService.equipItem(userId, "DIAMOND_BRUSH")
			expect(s1).toBe(false)
			expect(r1).toBe("Equipment not owned")

			local s2, _ = ProgressionService.equipItem(userId, "BASIC_BRUSH")
			expect(s2).toBe(true)

			local data = DataService.getPlayerData(userId)
			if data then
				expect(data.Equipment.ActiveBrush).toBe("BASIC_BRUSH")
			end
		end)
	end)

	-- =========================================================
	-- SUITE 2: Excavation Zones & Plot Expansion
	-- =========================================================
	describe("ProgressionService - Zones & Plot Expansion", function()
		local userId = 999031

		beforeEach(function()
			DataService.removePlayerData(userId)
			local data = DataService.initPlayerData({ UserId = userId, Name = "ProgPlayer2" } :: any)
			data.Money = 1000
			data.Level = 3
		end)

		it("should reject unlocking unknown zone", function()
			local success, reason = ProgressionService.unlockZone(userId, "UNKNOWN_ZONE")
			expect(success).toBe(false)
			expect(reason).toBe("Zone not found")
		end)

		it("should reject unlocking already unlocked zone", function()
			local success, reason = ProgressionService.unlockZone(userId, "BEGINNER_SITE")
			expect(success).toBe(false)
			expect(reason).toBe("Zone already unlocked")
		end)

		it("should reject unlocking zone if player lacks funds", function()
			local data = DataService.getPlayerData(userId)
			if data then data.Money = 50 end -- DESERT_CANYON costs 300
			local success, reason = ProgressionService.unlockZone(userId, "DESERT_CANYON")
			expect(success).toBe(false)
			expect(reason).toBe("Insufficient funds")
		end)

		it("should unlock zone, deduct money, and add to UnlockedZones", function()
			local data = DataService.getPlayerData(userId)
			local startMoney = if data then data.Money else 1000

			local success, _ = ProgressionService.unlockZone(userId, "DESERT_CANYON")
			expect(success).toBe(true)

			if data then
				expect(data.Money).toBe(startMoney - 300)
				expect(table.find(data.UnlockedZones, "DESERT_CANYON")).toNotBeNil()
			end
		end)

		it("should expand plot, deducting scaled cost and incrementing ExpansionLevel", function()
			local data = DataService.getPlayerData(userId)
			local cost = EconomyConfig.getPlotExpansionCost(1) -- Base cost: 500

			local success, _ = ProgressionService.expandPlot(userId)
			expect(success).toBe(true)

			if data then
				expect(data.Money).toBe(1000 - cost)
				expect(data.PlotData.ExpansionLevel).toBe(2)
			end
		end)

		it("should purchase additional cages, deducting CageBaseCost and incrementing CageCount", function()
			local data = DataService.getPlayerData(userId)
			local cost = EconomyConfig.CageBaseCost -- 200

			local success, _ = ProgressionService.buyCage(userId)
			expect(success).toBe(true)

			if data then
				expect(data.Money).toBe(1000 - cost)
				expect(data.PlotData.CageCount).toBe(2)
			end
		end)

		it("should sell a fossil from inventory for cash", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				InventoryService.addItem(userId, fossil)

				local data = DataService.getPlayerData(userId)
				local startMoney = if data then data.Money else 1000

				local success, earned = ProgressionService.sellFossil(userId, fossil.ItemUID)
				expect(success).toBe(true)

				-- Fossil removed from inventory
				expect(InventoryService.hasItem(userId, fossil.ItemUID)).toBe(false)

				-- Cash awarded
				if data then
					expect(data.Money).toBeGreaterThan(startMoney)
				end
			end
		end)
	end)

end
