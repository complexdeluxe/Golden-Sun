--!strict
-- Authoritative Phase 4 Economy, Tempering, Cyberware, and D'Arby Parlor tables.
-- Mirrors Obsidian Vault `phase4_economy_tables.json` (version 1) 1:1.

export type Rarity = "Common" | "Rare" | "Epic" | "Legendary"
export type AffixId =
	"flat_physical"
	| "flat_special"
	| "flat_defense"
	| "flat_focus"
	| "flat_speed"
	| "precision_pp"
	| "control_resist_pp"
	| "def_pen_pp"
	| "crit_pp"
	| "cond_dmg_bleed"
	| "proc_bleed_or_burn"

export type PurifiedPerkId =
	"iron_ward"
	| "keen_edge"
	| "steady_sight"
	| "clear_mind"
	| "armor_piercer"
	| "measured_breath"

export type CyberwareSite = "HeadOptics" | "Neural" | "TorsoChassis" | "Limbs" | "HeartCore"
export type RaceId =
	"Human"
	| "StroheimHuman"
	| "Superhuman"
	| "Cyborg"
	| "FullBorg"
	| "Undead"
	| "Vampire"
	| "PillarMan"
	| "UltimateLifeform"
	| "Alien"
	| "Rock"

export type ParlorTierId = "standard_chip" | "high_roller_chip"
export type Affix = {
	read id: AffixId,
	read label: string,
	read weight: number,
	read unitCostPts: number,
	read minTier: number,
	read scalePerAct: number?,
	read minPct: number?,
	read maxPct: number?,
}
export type ParlorEntry = { read bucket: string, read weightPct: number, read rarity: Rarity, read isCosmetic: boolean }
type ParlorTier = {
	read id: ParlorTierId,
	read label: string,
	read singleYen: number,
	read tenSpinYen: number,
	read pityThreshold: number,
	read odds: { ParlorEntry },
}

local GlobalCaps = table.freeze({
	SourceDamageCapPct = 35,
	PrePenMitigationCapPct = 75,
	EffectiveDodgeCapPct = 50,
	ResolvePerTurnCap = 25,
	BaseGearBudgetPerSlotMultiplier = 2,
	BaseGearSlotCount = 4,
	BaseGearTotalBudgetMultiplier = 8,
	TemperMaxLevel = 10,
	TemperPctPerLevel = 2,
	TemperMaxBonusPct = 20,
	ZeroItemDestruction = true,
	ReplayXp = 0,
	ReplayMasteryMarks = 0,
	ReplayEchoes = 0,
	MaxExpeditionDropsFractionOfClear = 0.25,
})

local ActIncome = table.freeze({
	[1] = table.freeze({
		act = 1,
		tier = 1,
		flagYen = table.freeze({ F1 = 12, F2 = 18, F3 = 14, F4 = 16, F5 = 18, F6 = 20, F7 = 24 }),
		dungeonYen = table.freeze({ D1 = 30, D2 = 36, D3 = 42 }),
		castleYen = 75,
		replayYenMultiplier = 0.5,
		dismantleShards = table.freeze({ Common = 2, Rare = 4, Epic = 7, Legendary = 12 }),
		materialDrops = table.freeze({ flag = 1, dungeon = 3, castle = 5 }),
		autoBattle5Min = table.freeze({ yen = 6, shards = 1, materials = 1, xp = 0, marks = 0, echoes = 0 }),
		expedition4Hr = table.freeze({ yen = 22, shards = 3, materials = 2, xp = 0, marks = 0, echoes = 0 }),
		rarityOdds = table.freeze({ Common = 55, Rare = 35, Epic = 10, Legendary = 0 }),
	}),
	[2] = table.freeze({
		act = 2,
		tier = 2,
		flagYen = table.freeze({ F1 = 24, F2 = 28, F3 = 30, F4 = 32, F5 = 35, F6 = 38, F7 = 42 }),
		dungeonYen = table.freeze({ D1 = 55, D2 = 65, D3 = 75 }),
		castleYen = 140,
		replayYenMultiplier = 0.5,
		dismantleShards = table.freeze({ Common = 3, Rare = 6, Epic = 10, Legendary = 16 }),
		materialDrops = table.freeze({ flag = 2, dungeon = 4, castle = 7 }),
		autoBattle5Min = table.freeze({ yen = 12, shards = 2, materials = 1, xp = 0, marks = 0, echoes = 0 }),
		expedition4Hr = table.freeze({ yen = 45, shards = 5, materials = 3, xp = 0, marks = 0, echoes = 0 }),
		rarityOdds = table.freeze({ Common = 30, Rare = 45, Epic = 20, Legendary = 5 }),
	}),
	[3] = table.freeze({
		act = 3,
		tier = 3,
		flagYen = table.freeze({ F1 = 40, F2 = 45, F3 = 48, F4 = 52, F5 = 56, F6 = 60, F7 = 66 }),
		dungeonYen = table.freeze({ D1 = 85, D2 = 100, D3 = 115 }),
		castleYen = 220,
		replayYenMultiplier = 0.5,
		dismantleShards = table.freeze({ Common = 5, Rare = 9, Epic = 15, Legendary = 24 }),
		materialDrops = table.freeze({ flag = 2, dungeon = 5, castle = 9 }),
		autoBattle5Min = table.freeze({ yen = 20, shards = 3, materials = 2, xp = 0, marks = 0, echoes = 0 }),
		expedition4Hr = table.freeze({ yen = 75, shards = 8, materials = 4, xp = 0, marks = 0, echoes = 0 }),
		rarityOdds = table.freeze({ Common = 10, Rare = 40, Epic = 38, Legendary = 12 }),
	}),
	[4] = table.freeze({
		act = 4,
		tier = 4,
		flagYen = table.freeze({ F1 = 65, F2 = 72, F3 = 78, F4 = 84, F5 = 90, F6 = 96, F7 = 105 }),
		dungeonYen = table.freeze({ D1 = 135, D2 = 155, D3 = 180 }),
		castleYen = 340,
		replayYenMultiplier = 0.5,
		dismantleShards = table.freeze({ Common = 8, Rare = 14, Epic = 22, Legendary = 35 }),
		materialDrops = table.freeze({ flag = 3, dungeon = 7, castle = 12 }),
		autoBattle5Min = table.freeze({ yen = 32, shards = 5, materials = 2, xp = 0, marks = 0, echoes = 0 }),
		expedition4Hr = table.freeze({ yen = 120, shards = 12, materials = 6, xp = 0, marks = 0, echoes = 0 }),
		rarityOdds = table.freeze({ Common = 0, Rare = 25, Epic = 57, Legendary = 18 }),
	}),
	[5] = table.freeze({
		act = 5,
		tier = 5,
		flagYen = table.freeze({ F1 = 100, F2 = 110, F3 = 120, F4 = 130, F5 = 140, F6 = 150, F7 = 165 }),
		dungeonYen = table.freeze({ D1 = 210, D2 = 240, D3 = 275 }),
		castleYen = 500,
		replayYenMultiplier = 0.5,
		dismantleShards = table.freeze({ Common = 12, Rare = 20, Epic = 32, Legendary = 50 }),
		materialDrops = table.freeze({ flag = 4, dungeon = 9, castle = 16 }),
		autoBattle5Min = table.freeze({ yen = 50, shards = 8, materials = 3, xp = 0, marks = 0, echoes = 0 }),
		expedition4Hr = table.freeze({ yen = 180, shards = 18, materials = 8, xp = 0, marks = 0, echoes = 0 }),
		rarityOdds = table.freeze({ Common = 0, Rare = 10, Epic = 65, Legendary = 25 }),
	}),
})

local ConsumablePrices = table.freeze({
	["tonio-water"] = table.freeze({ price = 10, cap = 8, unlockAct = 1, directHeal = true }),
	["smoke-pellet"] = table.freeze({ price = 15, cap = 4, unlockAct = 1, directHeal = false }),
	["smelling-salts"] = table.freeze({ price = 16, cap = 4, unlockAct = 1, directHeal = false }),
	["blood-vial"] = table.freeze({ price = 18, cap = 4, unlockAct = 1, directHeal = false }),
	["coffee-gum"] = table.freeze({ price = 20, cap = 4, unlockAct = 1, directHeal = false }),
	["spiked-whetstone"] = table.freeze({ price = 22, cap = 4, unlockAct = 1, directHeal = false }),
	["uv-flash"] = table.freeze({ price = 24, cap = 3, unlockAct = 2, directHeal = false }),
	["med-kit"] = table.freeze({ price = 25, cap = 3, unlockAct = 1, directHeal = true }),
	["caprese-salad"] = table.freeze({ price = 28, cap = 3, unlockAct = 2, directHeal = true }),
	["passione-espresso"] = table.freeze({ price = 30, cap = 3, unlockAct = 3, directHeal = false }),
})

local EverydayGearPricesByTier = table.freeze({ 45, 110, 220, 380, 600 })
local HolyWaterPriceByTier = table.freeze({ 40, 80, 120, 160, 200 })

local LineBudgetMultiplier = table.freeze({ 0.6, 0.7, 0.8 })
local MaxLinesByAct = table.freeze({ 1, 2, 3, 3, 3 })
local LineCountWeightsByRarity: { [Rarity]: { [number]: number } } = {
	Common = table.freeze({ [0] = 100, [1] = 0, [2] = 0, [3] = 0 }),
	Rare = table.freeze({ [0] = 0, [1] = 65, [2] = 30, [3] = 5 }),
	Epic = table.freeze({ [0] = 0, [1] = 25, [2] = 55, [3] = 20 }),
	Legendary = table.freeze({ [0] = 0, [1] = 0, [2] = 50, [3] = 50 }),
}
table.freeze(LineCountWeightsByRarity)

local function freezeAffix(entry: Affix): Affix
	table.freeze(entry)
	return entry
end

local AffixPool: { Affix } = {
	freezeAffix({ id = "flat_physical" :: AffixId, label = "+Physical", weight = 14, minTier = 1, unitCostPts = 1.0, scalePerAct = 0.6 }),
	freezeAffix({ id = "flat_special" :: AffixId, label = "+Special", weight = 14, minTier = 1, unitCostPts = 1.0, scalePerAct = 0.6 }),
	freezeAffix({ id = "flat_defense" :: AffixId, label = "+Defense", weight = 12, minTier = 1, unitCostPts = 1.0, scalePerAct = 0.6 }),
	freezeAffix({ id = "flat_focus" :: AffixId, label = "+Focus", weight = 12, minTier = 1, unitCostPts = 1.0, scalePerAct = 0.6 }),
	freezeAffix({ id = "flat_speed" :: AffixId, label = "+Speed", weight = 10, minTier = 1, unitCostPts = 1.0, scalePerAct = 0.6 }),
	freezeAffix({ id = "precision_pp" :: AffixId, label = "+Precision pp", weight = 10, minTier = 1, unitCostPts = 0.5, scalePerAct = 1.0 }),
	freezeAffix({ id = "control_resist_pp" :: AffixId, label = "+Control Resist pp", weight = 8, minTier = 1, unitCostPts = 0.8, scalePerAct = 0.7 }),
	freezeAffix({ id = "def_pen_pp" :: AffixId, label = "+Def Pen pp", weight = 8, minTier = 1, unitCostPts = 1.0, scalePerAct = 0.6 }),
	freezeAffix({ id = "crit_pp" :: AffixId, label = "+Crit pp", weight = 4, minTier = 1, unitCostPts = 1.5, scalePerAct = 0.4 }),
	freezeAffix({ id = "cond_dmg_bleed" :: AffixId, label = "+% Dmg vs Bleeding", weight = 4, minTier = 3, unitCostPts = 0.5, minPct = 2, maxPct = 4 }),
	freezeAffix({ id = "proc_bleed_or_burn" :: AffixId, label = "% Status Attempt on Hit", weight = 4, minTier = 3, unitCostPts = 0.5, minPct = 5, maxPct = 10 }),
}
table.freeze(AffixPool)

local BlacksmithRerollCostByTier = table.freeze({
	table.freeze({ yen = 30, shards = 4 }),
	table.freeze({ yen = 65, shards = 8 }),
	table.freeze({ yen = 120, shards = 14 }),
	table.freeze({ yen = 200, shards = 22 }),
	table.freeze({ yen = 320, shards = 32 }),
})

local TemperTierMultiplier = table.freeze({ 1.0, 1.6, 2.4, 3.5, 5.0 })
local TemperLevels = table.freeze({
	table.freeze({ toLevel = 1, totalBonusPct = 2, baseYen = 20, baseShards = 2, baseMaterials = 1, successRatePct = 100, pityAddPctPerFail = 0 }),
	table.freeze({ toLevel = 2, totalBonusPct = 4, baseYen = 30, baseShards = 3, baseMaterials = 1, successRatePct = 100, pityAddPctPerFail = 0 }),
	table.freeze({ toLevel = 3, totalBonusPct = 6, baseYen = 45, baseShards = 4, baseMaterials = 2, successRatePct = 100, pityAddPctPerFail = 0 }),
	table.freeze({ toLevel = 4, totalBonusPct = 8, baseYen = 65, baseShards = 6, baseMaterials = 2, successRatePct = 100, pityAddPctPerFail = 0 }),
	table.freeze({ toLevel = 5, totalBonusPct = 10, baseYen = 90, baseShards = 8, baseMaterials = 3, successRatePct = 100, pityAddPctPerFail = 0 }),
	table.freeze({ toLevel = 6, totalBonusPct = 12, baseYen = 120, baseShards = 10, baseMaterials = 4, successRatePct = 85, pityAddPctPerFail = 25 }),
	table.freeze({ toLevel = 7, totalBonusPct = 14, baseYen = 160, baseShards = 13, baseMaterials = 5, successRatePct = 75, pityAddPctPerFail = 25 }),
	table.freeze({ toLevel = 8, totalBonusPct = 16, baseYen = 210, baseShards = 17, baseMaterials = 6, successRatePct = 65, pityAddPctPerFail = 25 }),
	table.freeze({ toLevel = 9, totalBonusPct = 18, baseYen = 270, baseShards = 22, baseMaterials = 8, successRatePct = 55, pityAddPctPerFail = 25 }),
	table.freeze({ toLevel = 10, totalBonusPct = 20, baseYen = 350, baseShards = 28, baseMaterials = 10, successRatePct = 45, pityAddPctPerFail = 25 }),
})

local PurifiedPerks = table.freeze({
	iron_ward = table.freeze({ id = "iron_ward" :: PurifiedPerkId, label = "Iron Ward", minTier = 1, slotCost = "half", stat = "defense", byTier = table.freeze({ 1, 2, 3, 4, 5 }), uniqueLoadoutLimit = nil }),
	keen_edge = table.freeze({ id = "keen_edge" :: PurifiedPerkId, label = "Keen Edge", minTier = 1, slotCost = "half", stat = "crit_pp", byTier = table.freeze({ 1, 1, 2, 3, 3 }), uniqueLoadoutLimit = nil }),
	steady_sight = table.freeze({ id = "steady_sight" :: PurifiedPerkId, label = "Steady Sight", minTier = 1, slotCost = "half", stat = "precision_pp", byTier = table.freeze({ 2, 4, 6, 8, 10 }), uniqueLoadoutLimit = nil }),
	clear_mind = table.freeze({ id = "clear_mind" :: PurifiedPerkId, label = "Clear Mind", minTier = 1, slotCost = "half", stat = "control_resist_pp", byTier = table.freeze({ 1, 3, 4, 6, 7 }), uniqueLoadoutLimit = nil }),
	armor_piercer = table.freeze({ id = "armor_piercer" :: PurifiedPerkId, label = "Armor Piercer", minTier = 1, slotCost = "half", stat = "def_pen_pp", byTier = table.freeze({ 1, 2, 3, 4, 5 }), uniqueLoadoutLimit = nil }),
	measured_breath = table.freeze({ id = "measured_breath" :: PurifiedPerkId, label = "Measured Breath", minTier = 3, slotCost = "full", stat = "starting_stamina", byTier = table.freeze({ 0, 0, 1, 1, 1 }), uniqueLoadoutLimit = 1 }),
})

local Cyberware = table.freeze({
	UnlockAct = 2,
	StrainThresholdBase = 128,
	StrainControlResistPenaltyPp = 10,
	StrainExtraAgingYears = 1,
	MaxEquippedHighTierActives = 2,
	GoldenAppleStrainFreeBonus = 30,
	GoldenAppleMinUnlockedSites = 2,
	RacialTolerance = table.freeze({
		Human = table.freeze({ base = 40, maxSites = 5, eligible = true }),
		StroheimHuman = table.freeze({ base = 60, maxSites = 5, eligible = true }),
		Superhuman = table.freeze({ base = 40, maxSites = 2, eligible = true }),
		Cyborg = table.freeze({ base = 120, maxSites = 5, eligible = true }),
		FullBorg = table.freeze({ base = 170, maxSites = 5, eligible = true }),
		Undead = table.freeze({ base = 0, maxSites = 0, eligible = false }),
		Vampire = table.freeze({ base = 0, maxSites = 0, eligible = false }),
		PillarMan = table.freeze({ base = 0, maxSites = 0, eligible = false }),
		UltimateLifeform = table.freeze({ base = 0, maxSites = 0, eligible = false }),
		Alien = table.freeze({ base = 0, maxSites = 0, eligible = false }),
		Rock = table.freeze({ base = 0, maxSites = 0, eligible = false }),
	}),
	Tiers = table.freeze({
		table.freeze({ tier = 1, tolerance = 10, yen = 80, shards = 6, grantsActive = false }),
		table.freeze({ tier = 2, tolerance = 18, yen = 160, shards = 12, grantsActive = false }),
		table.freeze({ tier = 3, tolerance = 26, yen = 280, shards = 20, grantsActive = true }),
		table.freeze({ tier = 4, tolerance = 34, yen = 440, shards = 32, grantsActive = true }),
		table.freeze({ tier = 5, tolerance = 42, yen = 650, shards = 48, grantsActive = true }),
	}),
	Sites = table.freeze({
		HeadOptics = table.freeze({ passiveStat = "precision_pp", valuesByTier = table.freeze({ 4, 6, 8, 10, 12 }), activeId = "UVBeam" }),
		Neural = table.freeze({ passiveStat = "speed", valuesByTier = table.freeze({ 2, 4, 6, 8, 10 }), activeId = "TacticalSurge" }),
		TorsoChassis = table.freeze({ passiveStat = "defense", valuesByTier = table.freeze({ 2, 4, 6, 9, 12 }), activeId = "SuppressiveVolley" }),
		Limbs = table.freeze({ passiveStat = "physical", valuesByTier = table.freeze({ 2, 4, 6, 9, 12 }), activeId = "SeismicGrip" }),
		HeartCore = table.freeze({ passiveStat = "resolve_gain_pct", valuesByTier = table.freeze({ 3, 6, 9, 12, 15 }), activeId = "EmergencyOverride" }),
	}),
})

local parlorTiers: { [ParlorTierId]: ParlorTier } = {
		standard_chip = table.freeze({
			id = "standard_chip" :: ParlorTierId,
			label = "Standard Chip",
			singleYen = 100,
			tenSpinYen = 900,
			pityThreshold = 10,
			odds = table.freeze({
				table.freeze({ bucket = "CommonCraftingCrate", weightPct = 50.0, rarity = "Common" :: Rarity, isCosmetic = false }),
				table.freeze({ bucket = "CommonCosmetic", weightPct = 30.0, rarity = "Common" :: Rarity, isCosmetic = true }),
				table.freeze({ bucket = "RareSupplyCrate", weightPct = 14.0, rarity = "Rare" :: Rarity, isCosmetic = false }),
				table.freeze({ bucket = "EpicCosmetic", weightPct = 5.0, rarity = "Epic" :: Rarity, isCosmetic = true }),
				table.freeze({ bucket = "LegendaryCosmetic", weightPct = 1.0, rarity = "Legendary" :: Rarity, isCosmetic = true }),
			}),
		}),
		high_roller_chip = table.freeze({
			id = "high_roller_chip" :: ParlorTierId,
			label = "High-Roller Chip",
			singleYen = 350,
			tenSpinYen = 3150,
			pityThreshold = 10,
			odds = table.freeze({
				table.freeze({ bucket = "RareCraftingCrate", weightPct = 42.0, rarity = "Rare" :: Rarity, isCosmetic = false }),
				table.freeze({ bucket = "RareCosmetic", weightPct = 30.0, rarity = "Rare" :: Rarity, isCosmetic = true }),
				table.freeze({ bucket = "EpicBaseGearCrate", weightPct = 18.0, rarity = "Epic" :: Rarity, isCosmetic = false }),
				table.freeze({ bucket = "EpicCosmetic", weightPct = 7.5, rarity = "Epic" :: Rarity, isCosmetic = true }),
				table.freeze({ bucket = "LegendaryCosmetic", weightPct = 2.5, rarity = "Legendary" :: Rarity, isCosmetic = true }),
			}),
		}),
}
table.freeze(parlorTiers)
local DarbyParlor = table.freeze({
	Tiers = parlorTiers,
	DuplicateCosmeticShardRefund = table.freeze({
		Common = 3,
		Rare = 8,
		Epic = 18,
		Legendary = 40,
	}),
})

return table.freeze({
	GlobalCaps = GlobalCaps,
	ActIncome = ActIncome,
	ConsumablePrices = ConsumablePrices,
	EverydayGearPricesByTier = EverydayGearPricesByTier,
	HolyWaterPriceByTier = HolyWaterPriceByTier,
	LineBudgetMultiplier = LineBudgetMultiplier,
	MaxLinesByAct = MaxLinesByAct,
	LineCountWeightsByRarity = LineCountWeightsByRarity,
	AffixPool = AffixPool,
	BlacksmithRerollCostByTier = BlacksmithRerollCostByTier,
	TemperTierMultiplier = TemperTierMultiplier,
	TemperLevels = TemperLevels,
	PurifiedPerks = PurifiedPerks,
	Cyberware = Cyberware,
	DarbyParlor = DarbyParlor,
})
