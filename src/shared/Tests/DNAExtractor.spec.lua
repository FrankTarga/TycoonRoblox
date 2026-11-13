--!strict
--[[
	DNAExtractor.spec
	Unit tests for Phase 5 — DNA Extractor.

	Verifies that:
	  1. Only cleaned fossils may be inserted into the DNA Extractor.
	  2. Uncleaned fossils, DNA, and dinosaurs are rejected.
	  3. The machine must be Idle to accept input.
	  4. Inserting a fossil consumes it from carrying state and inventory.
	  5. Processing completes and transitions to OutputReady state.
	  6. DNA can only be collected once the machine is in OutputReady state.
	  7. Collecting DNA adds it to inventory and resets the machine to Idle.
	  8. A second insertion while Processing is rejected.
	  9. XP is awarded after successful DNA extraction.
	  10. Machine state is recorded correctly per player.
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

return function(CarryingService: any, DNAExtractorService: any)
	describe("DNAExtractorService - Input Validation", function()
		local userId = 999005

		beforeEach(function()
			DataService.removePlayerData(userId)
			DataService.initPlayerData({ UserId = userId, Name = "ExtractorPlayer" } :: any)
			CarryingService.clearCarriedItem(userId)
			DNAExtractorService.resetMachine(userId)
		end)

		it("should reject insertion when player is not carrying anything", function()
			local success, reason = DNAExtractorService.insertItem(userId)
			expect(success).toBe(false)
			expect(reason).toBe("No item is being carried")
		end)

		it("should reject uncleaned fossils", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				-- IsCleaned stays false by default
				InventoryService.addItem(userId, fossil)
				CarryingService.setCarriedItem(userId, fossil.ItemUID)

				local success, reason = DNAExtractorService.insertItem(userId)
				expect(success).toBe(false)
				expect(reason).toBe("Fossil must be cleaned before DNA extraction")
			end
		end)

		it("should reject DNA items (wrong item type)", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				local dna = ItemUtils.createDNAItem(fossil)
				if dna then
					InventoryService.addItem(userId, dna)
					CarryingService.setCarriedItem(userId, dna.ItemUID)

					local success, reason = DNAExtractorService.insertItem(userId)
					expect(success).toBe(false)
					expect(reason).toBe("DNA Extractor only accepts cleaned fossils")
				end
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

						local success, reason = DNAExtractorService.insertItem(userId)
						expect(success).toBe(false)
						expect(reason).toBe("DNA Extractor only accepts cleaned fossils")
					end
				end
			end
		end)

		it("should reject insertion when machine is already Processing", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				fossil.IsCleaned = true
				InventoryService.addItem(userId, fossil)
				CarryingService.setCarriedItem(userId, fossil.ItemUID)

				-- First insertion should succeed
				local success1, _ = DNAExtractorService.insertItem(userId)
				expect(success1).toBe(true)

				-- Machine is now Processing — place another cleaned fossil
				local fossil2 = ItemUtils.createFossilItem("TREX_TOOTH")
				if fossil2 then
					fossil2.IsCleaned = true
					InventoryService.addItem(userId, fossil2)
					CarryingService.setCarriedItem(userId, fossil2.ItemUID)

					local success2, reason = DNAExtractorService.insertItem(userId)
					expect(success2).toBe(false)
					expect(reason).toBe("Machine is not Idle")
				end
			end
		end)
	end)

	describe("DNAExtractorService - Processing & Output", function()
		local userId = 999006

		beforeEach(function()
			DataService.removePlayerData(userId)
			DataService.initPlayerData({ UserId = userId, Name = "ExtractorPlayer2" } :: any)
			CarryingService.clearCarriedItem(userId)
			DNAExtractorService.resetMachine(userId)
		end)

		it("should consume the fossil from inventory and carrying state on insertion", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				fossil.IsCleaned = true
				InventoryService.addItem(userId, fossil)
				CarryingService.setCarriedItem(userId, fossil.ItemUID)

				local success, _ = DNAExtractorService.insertItem(userId)
				expect(success).toBe(true)

				-- Item must be GONE from inventory
				expect(InventoryService.hasItem(userId, fossil.ItemUID)).toBe(false)
				-- Player must no longer be carrying it
				expect(CarryingService.isCarrying(userId)).toBe(false)
			end
		end)

		it("should transition machine to Processing state after insertion", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				fossil.IsCleaned = true
				InventoryService.addItem(userId, fossil)
				CarryingService.setCarriedItem(userId, fossil.ItemUID)

				DNAExtractorService.insertItem(userId)

				local state = DNAExtractorService.getMachineState(userId)
				expect(state).toNotBeNil()
				if state then
					expect(state.State).toBe("Processing")
					expect(state.InputDinosaurID).toBe("TREX")
				end
			end
		end)

		it("should transition machine to OutputReady after processing completes", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				fossil.IsCleaned = true
				InventoryService.addItem(userId, fossil)
				CarryingService.setCarriedItem(userId, fossil.ItemUID)

				DNAExtractorService.insertItem(userId)
				-- Force-complete processing for testing
				DNAExtractorService.forceCompleteProcessing(userId)

				local state = DNAExtractorService.getMachineState(userId)
				expect(state).toNotBeNil()
				if state then
					expect(state.State).toBe("OutputReady")
				end
			end
		end)

		it("should reject DNA collection if machine is not in OutputReady state", function()
			local success, reason = DNAExtractorService.collectDNA(userId)
			expect(success).toBe(false)
			expect(reason).toBe("No DNA available to collect")
		end)

		it("should add DNA to inventory and reset machine when player collects output", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				fossil.IsCleaned = true
				InventoryService.addItem(userId, fossil)
				CarryingService.setCarriedItem(userId, fossil.ItemUID)

				DNAExtractorService.insertItem(userId)
				DNAExtractorService.forceCompleteProcessing(userId)

				local startXP = 0
				local data = DataService.getPlayerData(userId)
				if data then startXP = data.XP end

				local success, dnaItem = DNAExtractorService.collectDNA(userId)
				expect(success).toBe(true)
				expect(dnaItem).toNotBeNil()

				if dnaItem then
					expect(dnaItem.ItemType).toBe("DNA")
					expect(dnaItem.DinosaurID).toBe("TREX")
					-- DNA must be in inventory now
					expect(InventoryService.hasItem(userId, dnaItem.ItemUID)).toBe(true)
				end

				-- Machine must be reset to Idle
				local state = DNAExtractorService.getMachineState(userId)
				expect(state.State).toBe("Idle")

				-- XP awarded
				if data then
					expect(data.XP).toBe(startXP + EconomyConfig.XPPerExtraction)
				end
			end
		end)

		it("should not allow collecting DNA twice from the same extraction", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				fossil.IsCleaned = true
				InventoryService.addItem(userId, fossil)
				CarryingService.setCarriedItem(userId, fossil.ItemUID)

				DNAExtractorService.insertItem(userId)
				DNAExtractorService.forceCompleteProcessing(userId)

				local success1, _ = DNAExtractorService.collectDNA(userId)
				expect(success1).toBe(true)

				-- Machine is Idle again — second collection should fail
				local success2, reason = DNAExtractorService.collectDNA(userId)
				expect(success2).toBe(false)
				expect(reason).toBe("No DNA available to collect")
			end
		end)
	end)
end
