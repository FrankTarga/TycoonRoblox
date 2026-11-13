--!strict
--[[
	Cage.spec
	Unit tests for Phase 7 — Dinosaurs and Cages.

	Verifies that:
	  1. Only Dinosaur items may be placed into a cage.
	  2. Fossils, DNA, and carried-nothing are rejected.
	  3. Placing a dinosaur consumes it from carrying state and inventory.
	  4. Cage assignment records the placed dinosaur (DinosaurID, ItemUID, LastCollectionTime).
	  5. Placing a dinosaur awards EconomyConfig.XPPerDinosaurPlaced (25 XP).
	  6. Placing into an already occupied cage is rejected.
	  7. Empty cages do not generate income.
	  8. Occupied cages accumulate passive income over time based on BaseIncome.
	  9. Accumulated income cannot exceed EconomyConfig.MaxAccumulatedIncome.
	  10. Collecting income adds money to PlayerData, updates statistics, and resets accumulated balance.
	  11. Collecting from an empty cage or zero-balance cage is rejected.
	  12. Retrieving a dinosaur clears the cage, deposits dinosaur back into inventory, and collects pending income.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TestFramework = require(ReplicatedStorage.Tests.TestFramework)
local Types         = require(ReplicatedStorage.Modules.Types)
local ItemUtils     = require(ReplicatedStorage.Modules.ItemUtils)
local EconomyConfig = require(ReplicatedStorage.Configurations.EconomyConfig)
local DinosaurConfig = require(ReplicatedStorage.Configurations.DinosaurConfig)
local DataService   = require(ServerScriptService.Services.DataService)
local InventoryService = require(ServerScriptService.Services.InventoryService)

local describe    = TestFramework.describe
local it          = TestFramework.it
local expect      = TestFramework.expect
local beforeEach  = TestFramework.beforeEach

-- Helper to create a Dinosaur item
local function makeDinosaur(dinoID: string): Types.ItemData?
	local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
	if not fossil then return nil end
	fossil.IsCleaned = true
	local dna = ItemUtils.createDNAItem(fossil)
	if not dna then return nil end
	return ItemUtils.createDinosaurItem(dna)
end

return function(CarryingService: any, CageService: any)

	-- =========================================================
	-- SUITE 1: Cage Placement Validation
	-- =========================================================
	describe("CageService - Placement Validation", function()
		local userId = 999020
		local cageId = "CAGE_1"

		beforeEach(function()
			DataService.removePlayerData(userId)
			DataService.initPlayerData({ UserId = userId, Name = "CagePlayer1" } :: any)
			CarryingService.clearCarriedItem(userId)
			CageService.resetPlayerCages(userId)
		end)

		it("should reject placement when player is carrying nothing", function()
			local success, reason = CageService.placeDinosaur(userId, cageId)
			expect(success).toBe(false)
			expect(reason).toBe("No item is being carried")
		end)

		it("should reject placement of a Fossil item", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				InventoryService.addItem(userId, fossil)
				CarryingService.setCarriedItem(userId, fossil.ItemUID)

				local success, reason = CageService.placeDinosaur(userId, cageId)
				expect(success).toBe(false)
				expect(reason).toBe("Only dinosaurs can be placed in cages")
			end
		end)

		it("should reject placement of a DNA item", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				fossil.IsCleaned = true
				local dna = ItemUtils.createDNAItem(fossil)
				if dna then
					InventoryService.addItem(userId, dna)
					CarryingService.setCarriedItem(userId, dna.ItemUID)

					local success, reason = CageService.placeDinosaur(userId, cageId)
					expect(success).toBe(false)
					expect(reason).toBe("Only dinosaurs can be placed in cages")
				end
			end
		end)

		it("should accept placing a dinosaur, consuming it from inventory and awarding 25 XP", function()
			local dino = makeDinosaur("TREX")
			if dino then
				InventoryService.addItem(userId, dino)
				CarryingService.setCarriedItem(userId, dino.ItemUID)

				local dataBefore = DataService.getPlayerData(userId)
				local startXP = if dataBefore then dataBefore.XP else 0

				local success, _ = CageService.placeDinosaur(userId, cageId)
				expect(success).toBe(true)

				-- Dinosaur must be consumed from inventory and carrying
				expect(InventoryService.hasItem(userId, dino.ItemUID)).toBe(false)
				expect(CarryingService.isCarrying(userId)).toBe(false)

				-- Cage assignment must record the dinosaur
				local cage = CageService.getCageData(userId, cageId)
				expect(cage).toNotBeNil()
				if cage then
					expect(cage.DinosaurID).toBe("TREX")
					expect(cage.DinosaurItemUID).toBe(dino.ItemUID)
				end

				-- XP awarded
				local dataAfter = DataService.getPlayerData(userId)
				if dataAfter then
					expect(dataAfter.XP).toBe(startXP + EconomyConfig.XPPerDinosaurPlaced)
				end
			end
		end)

		it("should reject placement if cage is already occupied", function()
			local dino1 = makeDinosaur("TREX")
			if dino1 then
				InventoryService.addItem(userId, dino1)
				CarryingService.setCarriedItem(userId, dino1.ItemUID)
				local s1, _ = CageService.placeDinosaur(userId, cageId)
				expect(s1).toBe(true)

				-- Try placing second dinosaur into the same cage
				local dino2 = makeDinosaur("TREX")
				if dino2 then
					InventoryService.addItem(userId, dino2)
					CarryingService.setCarriedItem(userId, dino2.ItemUID)

					local s2, reason = CageService.placeDinosaur(userId, cageId)
					expect(s2).toBe(false)
					expect(reason).toBe("Cage is already occupied")

					-- Second dinosaur remains safely in inventory
					expect(InventoryService.hasItem(userId, dino2.ItemUID)).toBe(true)
				end
			end
		end)
	end)

	-- =========================================================
	-- SUITE 2: Passive Income Generation & Collection
	-- =========================================================
	describe("CageService - Passive Income & Collection", function()
		local userId = 999021
		local cageId = "CAGE_1"

		beforeEach(function()
			DataService.removePlayerData(userId)
			DataService.initPlayerData({ UserId = userId, Name = "CagePlayer2" } :: any)
			CarryingService.clearCarriedItem(userId)
			CageService.resetPlayerCages(userId)
		end)

		it("should accumulate 0 income for an empty cage", function()
			local income = CageService.calculatePendingIncome(userId, cageId)
			expect(income).toBe(0)
		end)

		it("should accumulate passive income based on dinosaur BaseIncome and elapsed intervals", function()
			local dino = makeDinosaur("TREX")
			if dino then
				InventoryService.addItem(userId, dino)
				CarryingService.setCarriedItem(userId, dino.ItemUID)
				CageService.placeDinosaur(userId, cageId)

				local dinoInfo = DinosaurConfig.getDinosaur("TREX")
				local baseIncome = if dinoInfo then dinoInfo.BaseIncome else 10

				-- Simulate 2 elapsed intervals (e.g. 120 seconds if interval is 60)
				CageService.simulateElapsedTime(userId, cageId, EconomyConfig.IncomeTickInterval * 2)

				local pending = CageService.calculatePendingIncome(userId, cageId)
				expect(pending).toBe(baseIncome * 2)
			end
		end)

		it("should cap accumulated income at MaxAccumulatedIncome", function()
			local dino = makeDinosaur("TREX")
			if dino then
				InventoryService.addItem(userId, dino)
				CarryingService.setCarriedItem(userId, dino.ItemUID)
				CageService.placeDinosaur(userId, cageId)

				-- Simulate a huge amount of time (10,000 intervals)
				CageService.simulateElapsedTime(userId, cageId, EconomyConfig.IncomeTickInterval * 10000)

				local pending = CageService.calculatePendingIncome(userId, cageId)
				expect(pending).toBe(EconomyConfig.MaxAccumulatedIncome)
			end
		end)

		it("should reject collection if there is no income to collect", function()
			local success, reason = CageService.collectIncome(userId, cageId)
			expect(success).toBe(false)
			expect(reason).toBe("No income to collect")
		end)

		it("should collect income, add to PlayerData.Money, and reset accumulated balance", function()
			local dino = makeDinosaur("TREX")
			if dino then
				InventoryService.addItem(userId, dino)
				CarryingService.setCarriedItem(userId, dino.ItemUID)
				CageService.placeDinosaur(userId, cageId)

				local dinoInfo = DinosaurConfig.getDinosaur("TREX")
				local baseIncome = if dinoInfo then dinoInfo.BaseIncome else 10

				-- Simulate 3 intervals
				CageService.simulateElapsedTime(userId, cageId, EconomyConfig.IncomeTickInterval * 3)
				local expectedGain = baseIncome * 3

				local data = DataService.getPlayerData(userId)
				local startMoney = if data then data.Money else 0

				local success, collected = CageService.collectIncome(userId, cageId)
				expect(success).toBe(true)
				expect(collected).toBe(expectedGain)

				if data then
					expect(data.Money).toBe(startMoney + expectedGain)
					expect(data.Statistics.TotalMoneyEarned).toBe(expectedGain)
				end

				-- Balance should now be 0
				local pendingAfter = CageService.calculatePendingIncome(userId, cageId)
				expect(pendingAfter).toBe(0)
			end
		end)

		it("should allow retrieving a dinosaur, returning it to inventory and collecting pending income", function()
			local dino = makeDinosaur("TREX")
			if dino then
				InventoryService.addItem(userId, dino)
				CarryingService.setCarriedItem(userId, dino.ItemUID)
				CageService.placeDinosaur(userId, cageId)

				-- Simulate some income
				CageService.simulateElapsedTime(userId, cageId, EconomyConfig.IncomeTickInterval * 1)

				local data = DataService.getPlayerData(userId)
				local startMoney = if data then data.Money else 0

				local success, returnedDino = CageService.retrieveDinosaur(userId, cageId)
				expect(success).toBe(true)
				expect(returnedDino).toNotBeNil()

				if returnedDino then
					expect(returnedDino.ItemType).toBe("Dinosaur")
					expect(returnedDino.DinosaurID).toBe("TREX")
					-- Dinosaur is back in inventory
					expect(InventoryService.hasItem(userId, returnedDino.ItemUID)).toBe(true)
				end

				-- Cage is empty now
				local cage = CageService.getCageData(userId, cageId)
				if cage then
					expect(cage.DinosaurID).toBeNil()
					expect(cage.DinosaurItemUID).toBeNil()
				end

				-- Pending income was collected
				if data then
					expect(data.Money).toBeGreaterThan(startMoney)
				end
			end
		end)
	end)

end
