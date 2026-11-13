--!strict
--[[
	ZoneConfig
	Excavation zone definitions.
	Each zone has its own fossil pool, rarity modifiers, and unlock requirements.
]]

local ZoneConfig = {}

export type ZoneInfo = {
	ZoneID: string,
	Name: string,
	RequiredLevel: number,
	UnlockCost: number,
	AvailableFossils: { string },         -- List of FossilIDs available in this zone
	RarityMultipliers: { [string]: number }, -- Rarity name → weight multiplier
	LuckMultiplier: number,
	ExcavationCooldown: number,           -- Seconds between digs
	Description: string,
}

ZoneConfig.Zones: { [string]: ZoneInfo } = {
	BEGINNER_SITE = {
		ZoneID = "BEGINNER_SITE",
		Name = "Beginner Excavation Site",
		RequiredLevel = 1,
		UnlockCost = 0,
		AvailableFossils = { "TREX_TOOTH" },
		RarityMultipliers = {
			Common    = 1.0,
			Uncommon  = 1.0,
			Rare      = 1.0,
			Epic      = 1.0,
			Legendary = 1.0,
			Mythic    = 1.0,
		},
		LuckMultiplier = 1.0,
		ExcavationCooldown = 5,
		Description = "A basic excavation site for beginners. Simple fossils await.",
	},
	-- Future zones — add entries here:
	-- DESERT_CANYON  = { ZoneID = "DESERT_CANYON",  RequiredLevel = 5,  UnlockCost = 500,  ... },
	-- FROZEN_TUNDRA  = { ZoneID = "FROZEN_TUNDRA",  RequiredLevel = 10, UnlockCost = 2000, ... },
	-- VOLCANIC_RIDGE = { ZoneID = "VOLCANIC_RIDGE", RequiredLevel = 20, UnlockCost = 8000, ... },
}

--- Returns a single zone definition by ID, or nil.
function ZoneConfig.getZone(zoneID: string): ZoneInfo?
	return ZoneConfig.Zones[zoneID]
end

--- Returns all zones the player can access at a given level.
function ZoneConfig.getAvailableZones(playerLevel: number): { ZoneInfo }
	local result: { ZoneInfo } = {}
	for _, zone in ZoneConfig.Zones do
		if zone.RequiredLevel <= playerLevel then
			table.insert(result, zone)
		end
	end
	return result
end

--- Returns a flat list of all ZoneIDs.
function ZoneConfig.getAllZoneIDs(): { string }
	local ids: { string } = {}
	for id in ZoneConfig.Zones do
		table.insert(ids, id)
	end
	return ids
end

return ZoneConfig

