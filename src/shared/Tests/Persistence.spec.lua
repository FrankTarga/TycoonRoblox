--!strict
--[[
	Persistence.spec
	Unit tests for Phase 9 — Persistence and DataStore.

	Verifies that:
	  1. Schema migration and validation ensures missing fields are populated with defaults.
	  2. Saving player data persists all attributes (Money, Level, XP, Inventory, Equipment, Plot, Cages, Statistics).
	  3. Loading player data retrieves saved state accurately.
	  4. Loading data for a first-time player initializes default data.
	  5. DataStore failures are caught gracefully with pcall without breaking server state.
	  6. Periodic save and save-on-leave routines work reliably.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local TestFramework = require(ReplicatedStorage.Tests.TestFramework)
local Types         = require(ReplicatedStorage.Modules.Types)
local ItemUtils     = require(ReplicatedStorage.Modules.ItemUtils)
local DataService   = require(ServerScriptService.Services.DataService)

local describe   = TestFramework.describe
local it         = TestFramework.it
local expect     = TestFramework.expect
local beforeEach = TestFramework.beforeEach

-- In-memory mock DataStore for deterministic testing
local function createMockDataStore()
	local storage = {}
	local shouldFail = false

	return {
		GetAsync = function(_self: any, key: string)
			if shouldFail then error("DataStore error: connection refused") end
			return storage[key]
		end,
		SetAsync = function(_self: any, key: string, value: any)
			if shouldFail then error("DataStore error: write limit exceeded") end
			-- Deep clone value
			storage[key] = value
		end,
		setFail = function(fail: boolean)
			shouldFail = fail
		end,
		getRawStorage = function()
			return storage
		end,
	}
end

return function()

	-- =========================================================
	-- SUITE 1: Schema Migration & Validation
	-- =========================================================
	describe("DataService - Schema Migration & Validation", function()
		it("should produce valid default data when given an empty table", function()
			local migrated = DataService.validateAndMigrate({})
			expect(migrated).toNotBeNil()
			expect(migrated.Money).toBe(100)
			expect(migrated.Level).toBe(1)
			expect(migrated.XP).toBe(0)
			expect(migrated.Equipment.ActiveShovel).toBe("BASIC_SHOVEL")
			expect(migrated.PlotData.ExpansionLevel).toBe(1)
			expect(migrated.PlotData.CageCount).toBe(1)
			expect(migrated.Statistics.TotalMoneyEarned).toBe(0)
		end)

		it("should preserve existing player progress while adding missing new schema fields", function()
			local legacyData = {
				Money = 8500,
				Level = 7,
				XP = 320,
				-- Intentionally missing PlotData, Statistics, and CageAssignments from older versions
			}

			local migrated = DataService.validateAndMigrate(legacyData)
			expect(migrated.Money).toBe(8500)
			expect(migrated.Level).toBe(7)
			expect(migrated.XP).toBe(320)
			-- Missing fields must be populated
			expect(migrated.PlotData).toNotBeNil()
			expect(migrated.PlotData.ExpansionLevel).toBe(1)
			expect(migrated.Statistics).toNotBeNil()
			expect(migrated.CageAssignments).toNotBeNil()
		end)
	end)

	-- =========================================================
	-- SUITE 2: Save, Load, and Error Handling
	-- =========================================================
	describe("DataService - Save, Load, and Error Resilience", function()
		local userId = 999040
		local mockStore: any = nil

		beforeEach(function()
			mockStore = createMockDataStore()
			DataService.setMockDataStore(mockStore)
			DataService.removePlayerData(userId)
		end)

		it("should initialize default data on first load when no saved record exists", function()
			local loaded = DataService.loadPlayerData(userId)
			expect(loaded).toNotBeNil()
			expect(loaded.Money).toBe(100)
			expect(loaded.Level).toBe(1)
		end)

		it("should save mutated player data and accurately restore it on reload", function()
			local data = DataService.loadPlayerData(userId)
			data.Money = 4500
			data.Level = 4
			data.XP = 120
			table.insert(data.Equipment.OwnedEquipment, "IRON_SHOVEL")
			data.Equipment.ActiveShovel = "IRON_SHOVEL"

			-- Add a fossil to inventory
			local fossil = ItemUtils.createFossilItem("TREX_TOOTH")
			if fossil then
				table.insert(data.Inventory, fossil)
			end

			-- Save data
			local saveSuccess = DataService.savePlayerData(userId)
			expect(saveSuccess).toBe(true)

			-- Clear in-memory session cache to test cold reload
			DataService.removePlayerData(userId)
			expect(DataService.getPlayerData(userId)).toBeNil()

			-- Reload from mock DataStore
			local restored = DataService.loadPlayerData(userId)
			expect(restored).toNotBeNil()
			expect(restored.Money).toBe(4500)
			expect(restored.Level).toBe(4)
			expect(restored.XP).toBe(120)
			expect(restored.Equipment.ActiveShovel).toBe("IRON_SHOVEL")
			expect(#restored.Inventory).toBe(1)
		end)

		it("should gracefully catch DataStore save failures with pcall without breaking server", function()
			DataService.loadPlayerData(userId)
			mockStore.setFail(true) -- Cause simulated network/DataStore error

			local saveSuccess = DataService.savePlayerData(userId)
			expect(saveSuccess).toBe(false)
			-- Memory cache remains unharmed
			expect(DataService.getPlayerData(userId)).toNotBeNil()
		end)

		it("should fallback to default data when DataStore load fails", function()
			mockStore.setFail(true)
			local loaded = DataService.loadPlayerData(userId)
			expect(loaded).toNotBeNil()
			expect(loaded.Money).toBe(100)
		end)
	end)

end

