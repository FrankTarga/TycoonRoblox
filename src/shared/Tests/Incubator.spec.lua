--!strict
--[[
	Incubator.spec
	Unit tests for Phase 6 — Dinosaur Incubator.

	Verifies that:
	  1.  Only DNA items may be inserted into the Incubator.
	  2.  Fossils, Dinosaurs, and carried-nothing are rejected.
	  3.  The machine must be Idle to accept a new DNA strand.
	  4.  Inserting DNA consumes it from carrying state and inventory.
	  5.  After insertion the machine transitions to Processing.
	  6.  After processing completes (via forceCompleteProcessing) the dinosaur is
	      automatically added to inventory (AutoCollectOutput = true).
	  7.  The machine resets to Idle after auto-collection.
	  8.  XP (EconomyConfig.XPPerIncubation = 20) is awarded after incubation.
	  9.  DinosaurID and Rarity of the resulting dinosaur match the input DNA.
	  10. A second insertion while Processing is rejected.
	  11. forceCompleteProcessing on an Idle machine is a no-op (safe to call).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TestFramework = require(ReplicatedStorage.Tests.TestFramework)
local Types         = require(ReplicatedStorage.Modules.Types)
local ItemUtils     = require(ReplicatedStorage.Modules.ItemUtils)
local EconomyConfig = require(ReplicatedStorage.Configurations.EconomyConfig)
local DataService      = require(ServerScriptService.Services.DataService)
local InventoryService = require(ServerScriptService.Services.InventoryService)

local describe    = TestFramework.describe
local it          = TestFramework.it
local expect      = TestFramework.expect
local beforeEach  = TestFramework.beforeEach

-- Helper: creates a cleaned fossil, then a DNA item from it
local function makeDNA(dinoID: string): Types.ItemData?
	local fossil = ItemUtils.createFossilItem(dinoID == "TREX" and "TREX_TOOTH" or "TREX_TOOTH")
	if not fossil then return nil end
	fossil.IsCleaned = true
	return ItemUtils.createDNAItem(fossil)
end

return function(CarryingService: any, IncubatorService: any)

	-- =========================================================
	-- SUITE 1: Input Validation
	-- =========================================================
	describe("IncubatorService - Input Validation", function()
		local userId = 999010

		beforeEach(function()
			DataService.removePlayerData(userId)
			DataService.initPlayerData({ UserId = userId, Name = "IncubatorTestPlayer" } :: any)
			CarryingService.clearCarriedItem(userId)
			IncubatorService.resetMachine(userId)
		end)

		it("should reject insertion when player is not carrying anything", function()
			local success, reason = IncubatorService.insertItem(userId)
			expect(success).toBe(false)
			expect(reason).toBe("No item is being carried")
		end)

		it("should reject uncleaned fossil (wrong item type)", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				InventoryService.addItem(userId, fossil)
				CarryingService.setCarriedItem(userId, fossil.ItemUID)

				local success, reason = IncubatorService.insertItem(userId)
				expect(success).toBe(false)
				expect(reason).toBe("Incubator only accepts DNA items")
			end
		end)

		it("should reject cleaned fossil (wrong item type)", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				fossil.IsCleaned = true
				InventoryService.addItem(userId, fossil)
				CarryingService.setCarriedItem(userId, fossil.ItemUID)

				local success, reason = IncubatorService.insertItem(userId)
				expect(success).toBe(false)
				expect(reason).toBe("Incubator only accepts DNA items")
			end
		end)

		it("should reject dinosaur items (wrong item type)", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				local dna = ItemUtils.createDNAItem(fossil)
				if dna then
					local dino = ItemUtils.createDinosaurItem(dna)
					if dino then
						InventoryService.addItem(userId, dino)
						CarryingService.setCarriedItem(userId, dino.ItemUID)

						local success, reason = IncubatorService.insertItem(userId)
						expect(success).toBe(false)
						expect(reason).toBe("Incubator only accepts DNA items")
					end
				end
			end
		end)

		it("should reject insertion when machine is already Processing", function()
			local dna = makeDNA("TREX")
			if dna then
				InventoryService.addItem(userId, dna)
				CarryingService.setCarriedItem(userId, dna.ItemUID)

				local success1, _ = IncubatorService.insertItem(userId)
				expect(success1).toBe(true)

				-- Machine is now Processing — try to insert a second DNA
				local dna2 = makeDNA("TREX")
				if dna2 then
					InventoryService.addItem(userId, dna2)
					CarryingService.setCarriedItem(userId, dna2.ItemUID)

					local success2, reason = IncubatorService.insertItem(userId)
					expect(success2).toBe(false)
					expect(reason).toBe("Machine is not Idle")
				end
			end
		end)
	end)

	-- =========================================================
	-- SUITE 2: Processing & Auto-Collection
	-- =========================================================
	describe("IncubatorService - Processing & Auto-Collection", function()
		local userId = 999011

		beforeEach(function()
			DataService.removePlayerData(userId)
			DataService.initPlayerData({ UserId = userId, Name = "IncubatorTestPlayer2" } :: any)
			CarryingService.clearCarriedItem(userId)
			IncubatorService.resetMachine(userId)
		end)

		it("should consume DNA from inventory and carrying state on insertion", function()
			local dna = makeDNA("TREX")
			if dna then
				InventoryService.addItem(userId, dna)
				CarryingService.setCarriedItem(userId, dna.ItemUID)

				local success, _ = IncubatorService.insertItem(userId)
				expect(success).toBe(true)

				-- DNA must be GONE from inventory
				expect(InventoryService.hasItem(userId, dna.ItemUID)).toBe(false)
				-- Player must no longer be carrying it
				expect(CarryingService.isCarrying(userId)).toBe(false)
			end
		end)

		it("should transition machine to Processing state after insertion", function()
			local dna = makeDNA("TREX")
			if dna then
				InventoryService.addItem(userId, dna)
				CarryingService.setCarriedItem(userId, dna.ItemUID)

				IncubatorService.insertItem(userId)

				local state = IncubatorService.getMachineState(userId)
				expect(state).toNotBeNil()
				if state then
					expect(state.State).toBe("Processing")
					expect(state.InputDinosaurID).toBe("TREX")
				end
			end
		end)

		it("should auto-add dinosaur to inventory and reset machine when processing completes", function()
			local dna = makeDNA("TREX")
			if dna then
				InventoryService.addItem(userId, dna)
				CarryingService.setCarriedItem(userId, dna.ItemUID)

				IncubatorService.insertItem(userId)
				-- Force-complete bypasses the real timer
				IncubatorService.forceCompleteProcessing(userId)

				-- Machine should be Idle again (auto-collect happened internally)
				local state = IncubatorService.getMachineState(userId)
				expect(state.State).toBe("Idle")

				-- Exactly 1 item in inventory: the dinosaur
				local inv = InventoryService.getInventory(userId)
				expect(#inv).toBe(1)
				if #inv >= 1 then
					local dino = inv[1]
					expect(dino.ItemType).toBe("Dinosaur")
					expect(dino.DinosaurID).toBe("TREX")
				end
			end
		end)

		it("should award XPPerIncubation XP after incubation completes", function()
			local dna = makeDNA("TREX")
			if dna then
				InventoryService.addItem(userId, dna)
				CarryingService.setCarriedItem(userId, dna.ItemUID)

				local dataBefore = DataService.getPlayerData(userId)
				local startXP = if dataBefore then dataBefore.XP else 0

				IncubatorService.insertItem(userId)
				IncubatorService.forceCompleteProcessing(userId)

				local dataAfter = DataService.getPlayerData(userId)
				if dataAfter then
					expect(dataAfter.XP).toBe(startXP + EconomyConfig.XPPerIncubation)
				end
			end
		end)

		it("should produce a dinosaur matching the DNA's DinosaurID and Rarity", function()
			local dna = makeDNA("TREX")
			if dna then
				InventoryService.addItem(userId, dna)
				CarryingService.setCarriedItem(userId, dna.ItemUID)

				IncubatorService.insertItem(userId)
				IncubatorService.forceCompleteProcessing(userId)

				local inv = InventoryService.getInventory(userId)
				if #inv >= 1 then
					local dino = inv[1]
					expect(dino.DinosaurID).toBe(dna.DinosaurID)
					expect(dino.Rarity).toBe(dna.Rarity)
				end
			end
		end)

		it("should be safe to call forceCompleteProcessing when machine is Idle (no-op)", function()
			-- Machine starts Idle — this must not error or corrupt state
			IncubatorService.forceCompleteProcessing(userId)

			local state = IncubatorService.getMachineState(userId)
			expect(state.State).toBe("Idle")

			-- Inventory must remain empty
			local inv = InventoryService.getInventory(userId)
			expect(#inv).toBe(0)
		end)

		it("should allow a second incubation after the first completes", function()
			local dna1 = makeDNA("TREX")
			if dna1 then
				InventoryService.addItem(userId, dna1)
				CarryingService.setCarriedItem(userId, dna1.ItemUID)

				local s1, _ = IncubatorService.insertItem(userId)
				expect(s1).toBe(true)
				IncubatorService.forceCompleteProcessing(userId)

				-- Machine should be Idle — insert a second DNA
				local dna2 = makeDNA("TREX")
				if dna2 then
					InventoryService.addItem(userId, dna2)
					CarryingService.setCarriedItem(userId, dna2.ItemUID)

					local s2, _ = IncubatorService.insertItem(userId)
					expect(s2).toBe(true)

					local state = IncubatorService.getMachineState(userId)
					expect(state.State).toBe("Processing")
				end
			end
		end)
	end)

end

