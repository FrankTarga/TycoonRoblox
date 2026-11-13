--!strict
--[[
	TestRunner (Server)
	Executes automated unit test specifications in Roblox Studio.
	Runs during development / Play Solo when RunTests is true (or automatically in Studio).
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local function runAllSuites()
	print("\n=======================================================")
	print("       DINOSAUR FOSSIL TYCOON — TEST SUITE RUNNER")
	print("=======================================================")

	local TestsFolder = ReplicatedStorage:WaitForChild("Tests", 10) :: Folder?
	if not TestsFolder then
		warn("[TestRunner] Tests folder not found in ReplicatedStorage!")
		return
	end

	local TestFramework = require(TestsFolder:WaitForChild("TestFramework"))
	local CarryingService = require(ServerScriptService.Services.CarryingService)
	local CleaningService = require(ServerScriptService.Services.CleaningService)
	local DNAExtractorService = require(ServerScriptService.Services.DNAExtractorService)
	local IncubatorService = require(ServerScriptService.Services.IncubatorService)

	-- Register spec files
	local itemUtilsSpec     = require(TestsFolder:WaitForChild("ItemUtils.spec"))
	local inventorySpec     = require(TestsFolder:WaitForChild("Inventory.spec"))
	local carryingSpec      = require(TestsFolder:WaitForChild("Carrying.spec"))
	local cleaningSpec      = require(TestsFolder:WaitForChild("Cleaning.spec"))
	local dnaExtractorSpec  = require(TestsFolder:WaitForChild("DNAExtractor.spec"))
	local incubatorSpec     = require(TestsFolder:WaitForChild("Incubator.spec"))

	TestFramework.clear()

	itemUtilsSpec()
	inventorySpec()
	carryingSpec(CarryingService)
	cleaningSpec(CarryingService, CleaningService)
	dnaExtractorSpec(CarryingService, DNAExtractorService)
	incubatorSpec(CarryingService, IncubatorService)

	local results = TestFramework.runAll()

	local totalTests = 0
	local totalPassed = 0
	local totalFailed = 0

	for _, suite in results do
		local suiteTag = if suite.Passed then "[PASS]" else "[FAIL]"
		print(string.format("%s %s (%.3fs)", suiteTag, suite.Name, suite.Duration))

		for _, test in suite.Tests do
			totalTests += 1
			if test.Passed then
				totalPassed += 1
				print(string.format("   ✔ %s (%.4fs)", test.Name, test.Duration))
			else
				totalFailed += 1
				warn(string.format("   ✖ %s (%.4fs)\n     Error: %s", test.Name, test.Duration, test.ErrorMessage or "Unknown error"))
			end
		end
	end

	print("=======================================================")
	if totalFailed == 0 then
		print(string.format("SUMMARY: %d passed, %d failed (Total: %d) — 100%% SUCCESS", totalPassed, totalFailed, totalTests))
		workspace:SetAttribute("TestResults", "PASSED")
	else
		warn(string.format("SUMMARY: %d passed, %d failed (Total: %d) — FAILURES DETECTED", totalPassed, totalFailed, totalTests))
		workspace:SetAttribute("TestResults", "FAILED")
	end
	print("=======================================================\n")
end

-- Run in Studio automatically or if workspace has attribute RunTests = true
if RunService:IsStudio() then
	task.delay(1.0, function()
		runAllSuites()
	end)
end

