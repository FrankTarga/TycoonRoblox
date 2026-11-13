--!strict
--[[
	EconomyConfig
	Central balance values for the economy system.
	Money, XP, leveling, costs, and multipliers.
]]

local EconomyConfig = {}

---------- Starting Values ----------
EconomyConfig.StartingMoney = 100
EconomyConfig.StartingLevel = 1
EconomyConfig.StartingXP    = 0

---------- Passive Income ----------
EconomyConfig.IncomeTickInterval   = 60    -- Seconds between income accumulation ticks
EconomyConfig.MaxAccumulatedIncome = 10000 -- Max income a cage can accumulate before collection

---------- XP Rewards ----------
EconomyConfig.XPPerExcavation     = 10
EconomyConfig.XPPerCleaning       = 5
EconomyConfig.XPPerExtraction     = 15
EconomyConfig.XPPerIncubation     = 20
EconomyConfig.XPPerDinosaurPlaced = 25

---------- Leveling ----------
EconomyConfig.BaseXPToLevel    = 100
EconomyConfig.XPScalingFactor  = 1.5   -- XP required = Base × Factor^(Level−1)
EconomyConfig.MaxLevel         = 100

---------- Costs ----------
EconomyConfig.PlotExpansionBaseCost   = 500
EconomyConfig.PlotExpansionScaling    = 2.0
EconomyConfig.CageBaseCost            = 200

---------- Sell ----------
EconomyConfig.FossilSellMultiplier = 0.5  -- Fraction of base Value when selling

--- Returns the total XP required to reach the given level.
function EconomyConfig.getXPForLevel(level: number): number
	if level <= 1 then return 0 end
	return math.floor(
		EconomyConfig.BaseXPToLevel * (EconomyConfig.XPScalingFactor ^ (level - 1))
	)
end

--- Returns the cost of expanding the plot to the next expansion level.
function EconomyConfig.getPlotExpansionCost(currentExpansionLevel: number): number
	return math.floor(
		EconomyConfig.PlotExpansionBaseCost * (EconomyConfig.PlotExpansionScaling ^ (currentExpansionLevel - 1))
	)
end

return EconomyConfig

