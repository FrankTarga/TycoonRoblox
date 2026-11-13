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
	DESERT_CANYON = {
		ZoneID = "DESERT_CANYON",
		Name = "Desert Canyon",
		RequiredLevel = 2,
		UnlockCost = 300,
		AvailableFossils = { "TREX_TOOTH" },
		RarityMultipliers = {
			Common    = 0.8,
			Uncommon  = 1.4,
			Rare      = 1.5,
			Epic      = 1.2,
			Legendary = 1.0,
			Mythic    = 1.0,
		},
		LuckMultiplier = 1.25,
		ExcavationCooldown = 4,
		Description = "An arid desert canyon where wind reveals ancient fossil deposits.",
	},
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

