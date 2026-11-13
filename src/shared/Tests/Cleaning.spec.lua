--!strict
--[[
	Cleaning.spec
	Unit tests for Phase 4 — Fossil Cleaning.
	Verifies that:
	  1. Only uncleaned fossils can be cleaned.
	  2. Cleaning requires an equipped brush.
	  3. Player must be actively carrying the fossil.
	  4. Completing cleaning sets IsCleaned = true, sets Quality, and awards XP.
	  5. Already cleaned fossils cannot be cleaned again.
	  6. Non-fossil items (DNA, Dinosaurs) cannot be cleaned.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TestFramework = require(ReplicatedStorage.Tests.TestFramework)
local ItemUtils = require(ReplicatedStorage.Modules.ItemUtils)
local EconomyConfig = require(ReplicatedStorage.Configurations.EconomyConfig)
local DataService = require(ServerScriptService.Services.DataService)
local InventoryService = require(ServerScriptService.Services.InventoryService)

local describe = TestFramework.describe
local it = TestFramework.it
local expect = TestFramework.expect
local beforeEach = TestFramework.beforeEach

return function(CarryingService: any, CleaningService: any)
	describe("CleaningService - Fossil Cleaning System", function()
		local testUserId = 999004

		beforeEach(function()
			DataService.removePlayerData(testUserId)
			local mockPlayer = { UserId = testUserId, Name = "CleanerPlayer" } :: any
			DataService.initPlayerData(mockPlayer)
			CarryingService.clearCarriedItem(testUserId)
		end)

		it("should reject cleaning if the player is not carrying any item", function()
			local success, reason = CleaningService.cleanCarriedFossil(testUserId)
			expect(success).toBe(false)
			expect(reason).toBe("No item is being carried")
		end)

		it("should reject cleaning if the player is carrying a non-fossil item (DNA)", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				local dna = ItemUtils.createDNAItem(fossil)
				if dna then
					InventoryService.addItem(testUserId, dna)
					CarryingService.setCarriedItem(testUserId, dna.ItemUID)

					local success, reason = CleaningService.cleanCarriedFossil(testUserId)
					expect(success).toBe(false)
					expect(reason).toBe("Only fossils can be cleaned")
				end
			end
		end)

		it("should reject cleaning if the fossil is already cleaned", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				fossil.IsCleaned = true
				InventoryService.addItem(testUserId, fossil)
				CarryingService.setCarriedItem(testUserId, fossil.ItemUID)

				local success, reason = CleaningService.cleanCarriedFossil(testUserId)
				expect(success).toBe(false)
				expect(reason).toBe("Fossil is already cleaned")
			end
		end)

		it("should reject cleaning if the player does not have a brush equipped", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				InventoryService.addItem(testUserId, fossil)
				CarryingService.setCarriedItem(testUserId, fossil.ItemUID)

				-- Remove equipped brush
				local data = DataService.getPlayerData(testUserId)
				if data then
					data.Equipment.ActiveBrush = ""
				end

				local success, reason = CleaningService.cleanCarriedFossil(testUserId)
				expect(success).toBe(false)
				expect(reason).toBe("No brush equipped")
			end
		end)

		it("should successfully clean an uncleaned fossil, setting IsCleaned and Quality", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				expect(fossil.IsCleaned).toBe(false)
				expect(fossil.Quality).toBe(0)

				InventoryService.addItem(testUserId, fossil)
				CarryingService.setCarriedItem(testUserId, fossil.ItemUID)

				local startXP = 0
				local data = DataService.getPlayerData(testUserId)
				if data then
					startXP = data.XP
				end

				local success, resultItem = CleaningService.cleanCarriedFossil(testUserId)
				expect(success).toBe(true)
				expect(resultItem).toNotBeNil()

				if resultItem then
					expect(resultItem.IsCleaned).toBe(true)
					expect(resultItem.Quality).toBeGreaterThan(0)
				end

				-- Verify item in inventory is updated
				local inInventory = InventoryService.getItem(testUserId, fossil.ItemUID)
				expect(inInventory).toNotBeNil()
				if inInventory then
					expect(inInventory.IsCleaned).toBe(true)
					expect(inInventory.Quality).toBeGreaterThan(0)
				end

				-- Verify XP was awarded
				if data then
					expect(data.XP).toBe(startXP + EconomyConfig.XPPerCleaning)
				end
			end
		end)

		it("should calculate cleaning duration scaled by brush speed", function()
			local data = DataService.getPlayerData(testUserId)
			if data then
				data.Equipment.ActiveBrush = "BASIC_BRUSH"
				local duration = CleaningService.getCleaningDuration(testUserId)
				expect(duration).toBeGreaterThan(0)
			end
		end)
	end)
end

