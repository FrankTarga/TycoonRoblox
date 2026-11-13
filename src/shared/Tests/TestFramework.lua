--!strict
--[[
	TestFramework
	Zero-dependency, lightweight Unit Testing framework for Luau / Roblox.
	Provides Jest/TestEZ-like assertions and test execution.
]]

local TestFramework = {}

export type TestResult = {
	Name: string,
	Passed: boolean,
	ErrorMessage: string?,
	Duration: number,
}

export type SuiteResult = {
	Name: string,
	Passed: boolean,
	Tests: { TestResult },
	TotalCount: number,
	PassCount: number,
	FailCount: number,
	Duration: number,
}

-------------------------------------------------------------------------
-- ASSERTION MATCHER
-------------------------------------------------------------------------
local function createExpectation(actual: any)
	local expectation = {}

	function expectation.toBe(expected: any)
		if actual ~= expected then
			error(string.format("Expected %s (type %s), got %s (type %s)",
				tostring(expected), typeof(expected), tostring(actual), typeof(actual)), 2)
		end
	end

	function expectation.toNotBe(expected: any)
		if actual == expected then
			error(string.format("Expected value not to be %s", tostring(expected)), 2)
		end
	end

	function expectation.toBeNil()
		if actual ~= nil then
			error(string.format("Expected nil, got %s (type %s)", tostring(actual), typeof(actual)), 2)
		end
	end

	function expectation.toNotBeNil()
		if actual == nil then
			error("Expected non-nil value, got nil", 2)
		end
	end

	function expectation.toBeTruthy()
		if not actual then
			error(string.format("Expected truthy value, got %s", tostring(actual)), 2)
		end
	end

	function expectation.toBeFalsy()
		if actual then
			error(string.format("Expected falsy value, got %s", tostring(actual)), 2)
		end
	end

	function expectation.toEqual(expected: any)
		if typeof(actual) == "table" and typeof(expected) == "table" then
			for k, v in expected do
				if actual[k] ~= v then
					error(string.format("Table mismatch at key '%s': expected %s, got %s",
						tostring(k), tostring(v), tostring(actual[k])), 2)
				end
			end
		elseif actual ~= expected then
			error(string.format("Expected %s, got %s", tostring(expected), tostring(actual)), 2)
		end
	end

	function expectation.toHaveLength(expectedLen: number)
		local len = if typeof(actual) == "table" then #actual else string.len(tostring(actual))
		if len ~= expectedLen then
			error(string.format("Expected length %d, got %d", expectedLen, len), 2)
		end
	end

	function expectation.toBeGreaterThan(expected: number)
		if typeof(actual) ~= "number" or actual <= expected then
			error(string.format("Expected %s to be greater than %s", tostring(actual), tostring(expected)), 2)
		end
	end

	return expectation
end

TestFramework.expect = createExpectation

-------------------------------------------------------------------------
-- SUITE BUILDER
-------------------------------------------------------------------------
type TestCase = {
	name: string,
	fn: () -> (),
}

type Suite = {
	name: string,
	tests: { TestCase },
	beforeEach: (() -> ())?,
	afterEach: (() -> ())?,
}

local currentSuite: Suite? = nil
local registeredSuites: { Suite } = {}

function TestFramework.describe(suiteName: string, suiteDefinition: () -> ())
	local suite: Suite = {
		name = suiteName,
		tests = {},
		beforeEach = nil,
		afterEach = nil,
	}
	local prevSuite = currentSuite
	currentSuite = suite

	suiteDefinition()

	table.insert(registeredSuites, suite)
	currentSuite = prevSuite
end

function TestFramework.it(testName: string, testFn: () -> ())
	if not currentSuite then
		error("it() must be called inside a describe() block", 2)
	end
	table.insert(currentSuite.tests, {
		name = testName,
		fn = testFn,
	})
end

TestFramework.test = TestFramework.it

function TestFramework.beforeEach(fn: () -> ())
	if currentSuite then
		currentSuite.beforeEach = fn
	end
end

function TestFramework.afterEach(fn: () -> ())
	if currentSuite then
		currentSuite.afterEach = fn
	end
end

-------------------------------------------------------------------------
-- RUNNER
-------------------------------------------------------------------------
function TestFramework.runAll(): { SuiteResult }
	local suiteResults: { SuiteResult } = {}

	for _, suite in registeredSuites do
		local suiteStart = os.clock()
		local testResults: { TestResult } = {}
		local passCount = 0
		local failCount = 0

		for _, tc in suite.tests do
			if suite.beforeEach then
				pcall(suite.beforeEach)
			end

			local testStart = os.clock()
			local success, err = pcall(tc.fn)
			local duration = os.clock() - testStart

			if suite.afterEach then
				pcall(suite.afterEach)
			end

			if success then
				passCount += 1
				table.insert(testResults, {
					Name = tc.name,
					Passed = true,
					Duration = duration,
				})
			else
				failCount += 1
				table.insert(testResults, {
					Name = tc.name,
					Passed = false,
					ErrorMessage = tostring(err),
					Duration = duration,
				})
			end
		end

		table.insert(suiteResults, {
			Name = suite.name,
			Passed = failCount == 0,
			Tests = testResults,
			TotalCount = #suite.tests,
			PassCount = passCount,
			FailCount = failCount,
			Duration = os.clock() - suiteStart,
		})
	end

	return suiteResults
end

--- Clears all registered suites (useful between runs)
function TestFramework.clear()
	table.clear(registeredSuites)
	currentSuite = nil
end

return TestFramework
