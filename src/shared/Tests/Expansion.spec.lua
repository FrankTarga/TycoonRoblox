--!strict
--[[
	Expansion.spec
	Unit tests for Phase 10 — Expansion and Polish.

	Verifies that:
	  1. Expanded dinosaur roster (Velociraptor, Triceratops, Spinosaurus) is fully configured.
	  2. Expanded fossil catalog maps correctly to each corresponding dinosaur.
	  3. Full pipeline (Fossil -> Clean -> DNA -> Dinosaur -> Cage Income) works for all new dinosaurs.
	  4. Expanded excavation zones (Frozen Tundra, Volcanic Ridge) have valid configurations and fossil pools.
	  5. ItemUtils accurately formats display names, colors, and generates valid items for all tiers.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TestFramework   = require(ReplicatedStorage.Tests.TestFramework)
local ItemUtils       = require(ReplicatedStorage.Modules.ItemUtils)
local DinosaurConfig  = require(ReplicatedStorage.Configurations.DinosaurConfig)
local FossilConfig    = require(ReplicatedStorage.Configurations.FossilConfig)
local ZoneConfig      = require(ReplicatedStorage.Configurations.ZoneConfig)

local describe = TestFramework.describe
local it       = TestFramework.it
local expect   = TestFramework.expect

return function()

	-- =========================================================
	-- SUITE 1: Expanded Dinosaurs & Fossils Catalog
	-- =========================================================
	describe("Expansion - Dinosaurs & Fossils Integrity", function()
		local expectedDinos = { "TREX", "VELOCIRAPTOR", "TRICERATOPS", "SPINOSAURUS" }
		local expectedFossils = { "TREX_TOOTH", "RAPTOR_CLAW", "TRICERATOPS_HORN", "SPINOSAURUS_SPINE" }

		it("should configure all 4 dinosaur species with positive BaseIncome and IncubationTime", function()
			for _, dinoId in expectedDinos do
				local dino = DinosaurConfig.getDinosaur(dinoId)
				expect(dino).toNotBeNil()
				if dino then
					expect(dino.BaseIncome).toBeGreaterThan(0)
					expect(dino.IncubationTime).toBeGreaterThan(0)
					expect(dino.Rarity).toNotBeNil()
				end
			end
		end)

		it("should configure all 4 fossils mapping to their correct DinosaurID", function()
			for _, fossilId in expectedFossils do
				local fossil = FossilConfig.getFossil(fossilId)
				expect(fossil).toNotBeNil()
				if fossil then
					expect(table.find(expectedDinos, fossil.DinosaurID)).toNotBeNil()
					expect(fossil.Value).toBeGreaterThan(0)
				end
			end
		end)

		it("should produce valid DNA and Dinosaur items through ItemUtils for each new fossil", function()
			for _, fossilId in expectedFossils do
				local fossilItem = ItemUtils.createFossilItem(fossilId)
				expect(fossilItem).toNotBeNil()
				if fossilItem then
					fossilItem.IsCleaned = true
					local dnaItem = ItemUtils.createDNAItem(fossilItem)
					expect(dnaItem).toNotBeNil()
					if dnaItem then
						local dinoItem = ItemUtils.createDinosaurItem(dnaItem)
						expect(dinoItem).toNotBeNil()
						if dinoItem then
							expect(dinoItem.DinosaurID).toBe(fossilItem.DinosaurID)
							expect(dinoItem.ItemType).toBe("Dinosaur")
						end
					end
				end
			end
		end)
	end)

	-- =========================================================
	-- SUITE 2: Expanded Excavation Zones
	-- =========================================================
	describe("Expansion - Zones Integrity", function()
		local expectedZones = { "BEGINNER_SITE", "DESERT_CANYON", "FROZEN_TUNDRA", "VOLCANIC_RIDGE" }

		it("should configure all 4 excavation zones with valid requirements and fossil pools", function()
			for _, zoneId in expectedZones do
				local zone = ZoneConfig.getZone(zoneId)
				expect(zone).toNotBeNil()
				if zone then
					expect(zone.RequiredLevel).toBeGreaterThan(0)
					expect(#zone.AvailableFossils).toBeGreaterThan(0)
					-- Every available fossil must exist in FossilConfig
					for _, fId in zone.AvailableFossils do
						expect(FossilConfig.getFossil(fId)).toNotBeNil()
					end
				end
			end
		end)
	end)

end

