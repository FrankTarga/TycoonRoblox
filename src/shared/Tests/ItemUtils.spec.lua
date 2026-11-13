--!strict
--[[
	ItemUtils.spec
	Unit tests for Item creation, identification, and machine compatibility.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TestFramework = require(ReplicatedStorage.Tests.TestFramework)
local ItemUtils = require(ReplicatedStorage.Modules.ItemUtils)

local describe = TestFramework.describe
local it = TestFramework.it
local expect = TestFramework.expect

return function()
	describe("ItemUtils - Item Creation", function()
		it("should create a valid Fossil item from FossilID", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			expect(fossil).toNotBeNil()
			if fossil then
				expect(fossil.ItemType).toBe("Fossil")
				expect(fossil.ConfigID).toBe("TREX_TOOTH")
				expect(fossil.DinosaurID).toBe("TREX")
				expect(fossil.Rarity).toBe("Common")
				expect(fossil.IsCleaned).toBe(false)
				expect(fossil.Quality).toBe(0)
				expect(typeof(fossil.ItemUID)).toBe("string")
				expect(string.len(fossil.ItemUID)).toBeGreaterThan(0)
			end
		end)

		it("should fail gracefully for unknown FossilID", function()
			local fossil = ItemUtils.createFossilItem("UNKNOWN_FOSSIL_123")
			expect(fossil).toBeNil()
		end)

		it("should create a valid DNA item from a fossil item", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			expect(fossil).toNotBeNil()
			if fossil then
				local dna = ItemUtils.createDNAItem(fossil)
				expect(dna).toNotBeNil()
				if dna then
					expect(dna.ItemType).toBe("DNA")
					expect(dna.DinosaurID).toBe("TREX")
					expect(dna.ConfigID).toBe("TREX_DNA")
					expect(dna.Rarity).toBe("Common")
					expect(typeof(dna.ItemUID)).toBe("string")
					expect(dna.ItemUID).toNotBe(fossil.ItemUID)
				end
			end
		end)

		it("should create a valid Dinosaur item from a DNA item", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				local dna = ItemUtils.createDNAItem(fossil)
				if dna then
					local dino = ItemUtils.createDinosaurItem(dna)
					expect(dino).toNotBeNil()
					if dino then
						expect(dino.ItemType).toBe("Dinosaur")
						expect(dino.DinosaurID).toBe("TREX")
						expect(dino.ConfigID).toBe("TREX")
						expect(dino.Rarity).toBe("Common")
					end
				end
			end
		end)
	end)

	describe("ItemUtils - Machine & Cage Compatibility", function()
		it("should reject uncleaned fossils in DNA Extractor", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			expect(fossil).toNotBeNil()
			if fossil then
				expect(fossil.IsCleaned).toBe(false)
				local compatible = ItemUtils.isCompatibleWithMachine(fossil, "DNA_EXTRACTOR")
				expect(compatible).toBe(false)
			end
		end)

		it("should accept cleaned fossils in DNA Extractor", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				fossil.IsCleaned = true
				local compatible = ItemUtils.isCompatibleWithMachine(fossil, "DNA_EXTRACTOR")
				expect(compatible).toBe(true)
			end
		end)

		it("should accept DNA in Incubator", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				local dna = ItemUtils.createDNAItem(fossil)
				if dna then
					local compatible = ItemUtils.isCompatibleWithMachine(dna, "INCUBATOR")
					expect(compatible).toBe(true)
				end
			end
		end)

		it("should reject fossils in Incubator", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				local compatible = ItemUtils.isCompatibleWithMachine(fossil, "INCUBATOR")
				expect(compatible).toBe(false)
			end
		end)

		it("should only allow dinosaurs to be placed in cages", function()
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				expect(ItemUtils.canPlaceInCage(fossil)).toBe(false)
				local dna = ItemUtils.createDNAItem(fossil)
				if dna then
					expect(ItemUtils.canPlaceInCage(dna)).toBe(false)
					local dino = ItemUtils.createDinosaurItem(dna)
					if dino then
						expect(ItemUtils.canPlaceInCage(dino)).toBe(true)
					end
				end
			end
		end)
	end)
end

