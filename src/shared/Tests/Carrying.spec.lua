--!strict
--[[
	Carrying.spec
	Unit tests for the physical Carrying and Placement validation system.
	Verifies that:
	  1. Carrying requires item ownership.
	  2. The item remains in inventory while carried.
	  3. Items are only removed when successfully consumed upon placement.
	  4. Unauthorized carrying or placement is strictly rejected.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TestFramework = require(ReplicatedStorage.Tests.TestFramework)
local ItemUtils = require(ReplicatedStorage.Modules.ItemUtils)
local DataService = require(ServerScriptService.Services.DataService)
local InventoryService = require(ServerScriptService.Services.InventoryService)

local describe = TestFramework.describe
local it = TestFramework.it
local expect = TestFramework.expect
local beforeEach = TestFramework.beforeEach

return function(CarryingService: any)
	describe("CarryingService - Authoritative Carrying & Placement", function()
		local testUserId = 999002
		local otherUserId = 999003

		beforeEach(function()
			-- Reset players
			DataService.removePlayerData(testUserId)
			DataService.removePlayerData(otherUserId)

			local mockPlayer = { UserId = testUserId, Name = "CarryingPlayer" } :: any
			local otherPlayer = { UserId = otherUserId, Name = "OtherPlayer" } :: any

			DataService.initPlayerData(mockPlayer)
			DataService.initPlayerData(otherPlayer)

			CarryingService.clearCarriedItem(testUserId)
			CarryingService.clearCarriedItem(otherUserId)
		end)

		it("should reject carrying an item the player does not own", function()
			local fakeUID = "UNOWNED_ITEM_999"
			local success, reason = CarryingService.setCarriedItem(testUserId, fakeUID)
			expect(success).toBe(false)
			expect(CarryingService.isCarrying(testUserId)).toBe(false)
			expect(CarryingService.getCarriedItem(testUserId)).toBeNil()
		end)

		it("should reject carrying an item owned by another player", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				InventoryService.addItem(otherUserId, fossil)

				-- testUserId attempts to carry otherUserId's fossil
				local success, reason = CarryingService.setCarriedItem(testUserId, fossil.ItemUID)
				expect(success).toBe(false)
				expect(CarryingService.isCarrying(testUserId)).toBe(false)
			end
		end)

		it("should allow carrying an item the player owns", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				InventoryService.addItem(testUserId, fossil)

				local success, reason = CarryingService.setCarriedItem(testUserId, fossil.ItemUID)
				expect(success).toBe(true)
				expect(CarryingService.isCarrying(testUserId)).toBe(true)

				local carried = CarryingService.getCarriedItem(testUserId)
				expect(carried).toNotBeNil()
				if carried then
					expect(carried.ItemUID).toBe(fossil.ItemUID)
					expect(carried.ConfigID).toBe("TREX_TOOTH")
				end
			end
		end)

		it("must keep the item in the inventory while it is being carried", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				InventoryService.addItem(testUserId, fossil)
				CarryingService.setCarriedItem(testUserId, fossil.ItemUID)

				-- Critical gameplay rule: item remains in inventory until placed
				expect(InventoryService.hasItem(testUserId, fossil.ItemUID)).toBe(true)
				local inv = InventoryService.getInventory(testUserId)
				expect(#inv).toBe(1)
			end
		end)

		it("should uncarry (drop) an item without removing it from inventory", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				InventoryService.addItem(testUserId, fossil)
				CarryingService.setCarriedItem(testUserId, fossil.ItemUID)

				-- Drop / uncarry
				local success = CarryingService.clearCarriedItem(testUserId)
				expect(success).toBe(true)
				expect(CarryingService.isCarrying(testUserId)).toBe(false)
				expect(CarryingService.getCarriedItem(testUserId)).toBeNil()

				-- Still in inventory!
				expect(InventoryService.hasItem(testUserId, fossil.ItemUID)).toBe(true)
			end
		end)

		it("should consume the carried item on successful placement", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				InventoryService.addItem(testUserId, fossil)
				CarryingService.setCarriedItem(testUserId, fossil.ItemUID)

				-- Simulate machine/cage consumption
				local consumedItem = CarryingService.consumeCarriedItem(testUserId)
				expect(consumedItem).toNotBeNil()
				if consumedItem then
					expect(consumedItem.ItemUID).toBe(fossil.ItemUID)
				end

				-- Now it MUST be removed from inventory and from carried state
				expect(CarryingService.isCarrying(testUserId)).toBe(false)
				expect(InventoryService.hasItem(testUserId, fossil.ItemUID)).toBe(false)
				local inv = InventoryService.getInventory(testUserId)
				expect(#inv).toBe(0)
			end
		end)

		it("should validate placement compatibility with machines", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				-- Uncleaned fossil in DNA_EXTRACTOR should fail compatibility
				InventoryService.addItem(testUserId, fossil)
				CarryingService.setCarriedItem(testUserId, fossil.ItemUID)

				local valid, reason = CarryingService.validateMachinePlacement(testUserId, "DNA_EXTRACTOR")
				expect(valid).toBe(false)

				-- Clean the fossil
				fossil.IsCleaned = true
				local validAfterClean, _ = CarryingService.validateMachinePlacement(testUserId, "DNA_EXTRACTOR")
				expect(validAfterClean).toBe(true)
			end
		end)
	end)
end
