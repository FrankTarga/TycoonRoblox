--!strict
--[[
	Inventory.spec
	Unit tests for Inventory operations, data isolation, and query helpers.
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

return function()
	describe("InventoryService - Authoritative Operations", function()
		local testUserId = 999001

		beforeEach(function()
			-- Reset player data before each test
			DataService.removePlayerData(testUserId)
			local mockPlayer = { UserId = testUserId, Name = "TestPlayer" } :: any
			DataService.initPlayerData(mockPlayer)
		end)

		it("should start with an empty inventory", function()
			local inventory = InventoryService.getInventory(testUserId)
			expect(#inventory).toBe(0)
		end)

		it("should add an item successfully and make it retrievable", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			expect(fossil).toNotBeNil()
			if fossil then
				local added = InventoryService.addItem(testUserId, fossil)
				expect(added).toBe(true)

				local inventory = InventoryService.getInventory(testUserId)
				expect(#inventory).toBe(1)
				expect(inventory[1].ItemUID).toBe(fossil.ItemUID)

				local retrieved = InventoryService.getItem(testUserId, fossil.ItemUID)
				expect(retrieved).toNotBeNil()
				if retrieved then
					expect(retrieved.ConfigID).toBe("TREX_TOOTH")
				end

				expect(InventoryService.hasItem(testUserId, fossil.ItemUID)).toBe(true)
			end
		end)

		it("should assign distinct UIDs to multiple items of the same fossil", function()
			local f1 = ItemUtils.createFossilItem("TREX_TOOTH")
			local f2 = ItemUtils.createFossilItem("TREX_TOOTH")
			expect(f1).toNotBeNil()
			expect(f2).toNotBeNil()

			if f1 and f2 then
				expect(f1.ItemUID).toNotBe(f2.ItemUID)

				InventoryService.addItem(testUserId, f1)
				InventoryService.addItem(testUserId, f2)

				local inventory = InventoryService.getInventory(testUserId)
				expect(#inventory).toBe(2)
			end
		end)

		it("should remove an item by UID without affecting others", function()
			local f1 = ItemUtils.createFossilItem("TREX_TOOTH")
			local f2 = ItemUtils.createFossilItem("TREX_TOOTH")

			if f1 and f2 then
				InventoryService.addItem(testUserId, f1)
				InventoryService.addItem(testUserId, f2)

				local removed = InventoryService.removeItem(testUserId, f1.ItemUID)
				expect(removed).toNotBeNil()
				if removed then
					expect(removed.ItemUID).toBe(f1.ItemUID)
				end

				expect(InventoryService.hasItem(testUserId, f1.ItemUID)).toBe(false)
				expect(InventoryService.hasItem(testUserId, f2.ItemUID)).toBe(true)

				local inventory = InventoryService.getInventory(testUserId)
				expect(#inventory).toBe(1)
				expect(inventory[1].ItemUID).toBe(f2.ItemUID)
			end
		end)

		it("should filter inventory correctly by item type", function()
			local f1 = ItemUtils.createFossilItem("TREX_TOOTH")
			if f1 then
				InventoryService.addItem(testUserId, f1)
				local dna = ItemUtils.createDNAItem(f1)
				if dna then
					InventoryService.addItem(testUserId, dna)

					local inventory = InventoryService.getInventory(testUserId)
					local fossils = ItemUtils.filterByType(inventory, "Fossil")
					local dnas = ItemUtils.filterByType(inventory, "DNA")
					local dinos = ItemUtils.filterByType(inventory, "Dinosaur")

					expect(#fossils).toBe(1)
					expect(#dnas).toBe(1)
					expect(#dinos).toBe(0)
				end
			end
		end)

		it("should return false/nil when querying non-existent items", function()
			expect(InventoryService.hasItem(testUserId, "NON_EXISTENT_UID")).toBe(false)
			expect(InventoryService.getItem(testUserId, "NON_EXISTENT_UID")).toBeNil()
			expect(InventoryService.removeItem(testUserId, "NON_EXISTENT_UID")).toBeNil()
		end)
	end)
end
