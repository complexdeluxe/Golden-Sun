--!strict
-- Headless deterministic test suite for Phase 4 Economy, Tempering,
-- Purification, Cyberware Tolerance, and D'Arby's Hub Parlor.

local Data = require("../src/shared/Data/Phase4EconomyData")
local Economy = require("../src/shared/Core/Phase4Economy")

local function fixedRoll(seq: { number }): () -> number
	local i = 0
	return function()
		i += 1
		return seq[((i - 1) % #seq) + 1]
	end
end

local uuidCount = 0
local function nextUuid(): string
	uuidCount += 1
	return "item-uuid-" .. tostring(uuidCount)
end

-- 1. Live Act 1 income parity + Replay 50% Yen / 0 XP rule
local f1First = Economy.computeNodeRewards(1, "Flag", "F1", "FirstClear")
assert(f1First.ok and f1First.yen == 12 and f1First.xpLevels == 1)
local d1First = Economy.computeNodeRewards(1, "Dungeon", "D1", "FirstClear")
assert(d1First.ok and d1First.yen == 30 and d1First.xpLevels == 1 and d1First.masteryMarks == 1)
local d1Replay = Economy.computeNodeRewards(1, "Dungeon", "D1", "Replay")
assert(d1Replay.ok and d1Replay.yen == 15 and d1Replay.xpLevels == 0 and d1Replay.masteryMarks == 0 and d1Replay.echoes == 0)

-- 2. Rolled affix diminishing pool & anti-scum pendingSmithOffer lock
local t5Leg = Economy.generateGearDrop(5, "Legendary", "Accessory", "iron-signet", false, fixedRoll({ 0.99, 0.1, 0.3, 0.6 }), nextUuid)
assert(t5Leg.baseStatPts == 10 and #t5Leg.rolledLines == 3)
local t1Leg = Economy.generateGearDrop(1, "Legendary", "Accessory", "iron-signet", false, fixedRoll({ 0.99 }), nextUuid)
assert(#t1Leg.rolledLines == 1)
local offer1 = Economy.createSmithRerollOffer(t5Leg, 400, 40, fixedRoll({ 0.2, 0.5, 0.8 }))
assert(offer1.ok and offer1.yen == 80 and offer1.shards == 8 and offer1.item.pendingSmithOffer ~= nil)
-- Second reroll blocked until pendingSmithOffer is resolved (anti-reload exploit)
local offer2Blocked = Economy.createSmithRerollOffer(offer1.item, 1000, 100, fixedRoll({ 0.1 }))
assert(not offer2Blocked.ok)
local accepted = Economy.resolveSmithOffer(offer1.item, "AcceptNew")
assert(accepted.ok and accepted.item.pendingSmithOffer == nil and #accepted.item.rolledLines == 3)

-- Exercise the weighted pool and value bounds for drops and smith offers at every tier.
local affixes: { [Data.AffixId]: Data.Affix } = {}
for _, entry in Data.AffixPool do affixes[entry.id] = entry end
local function assertBudget(tier: number, lines: { Economy.RolledLine })
	if #lines == 0 then return end
	local totalBudget = Data.LineBudgetMultiplier[#lines] * tier
	local perLineBudget = totalBudget / #lines
	local totalCost = 0
	local seen: { [Data.AffixId]: boolean } = {}
	for _, line in lines do
		local affix = affixes[line.affixId]
		assert(affix.minTier <= tier and not seen[line.affixId])
		assert(line.value >= (affix.minPct or 1) and line.value <= (affix.maxPct or math.huge))
		local cost = line.value * affix.unitCostPts
		assert(cost <= perLineBudget + 1e-9)
		totalCost += cost
		seen[line.affixId] = true
		if tier == 1 then assert(line.affixId == "precision_pp" and line.value == 1) end
	end
	assert(totalCost <= totalBudget + 1e-9)
end

local rarities: { Data.Rarity } = { "Common", "Rare", "Epic", "Legendary" }
for tier = 1, 5 do
	for _, rarity in rarities do
		for sample = 0, 99 do
			local roll = fixedRoll({ (sample + 0.5) / 100 })
			local item = Economy.generateGearDrop(tier, rarity, "Weapon", "training-wraps", false, roll, nextUuid)
			assert(#item.rolledLines <= Data.MaxLinesByAct[tier])
			assertBudget(tier, item.rolledLines)
			if rarity ~= "Common" then
				assert(#item.rolledLines > 0)
				local reroll = Economy.createSmithRerollOffer(item, 1000, 100, roll)
				local lines = assert(reroll.item.pendingSmithOffer)
				assert(reroll.ok and #lines == #item.rolledLines)
				assertBudget(tier, lines)
			end
		end
	end
end

local t2Legendary = Economy.generateGearDrop(2, "Legendary", "Weapon", "training-wraps", false, fixedRoll({ 0.99 }), nextUuid)
assert(#t2Legendary.rolledLines == 1)
local t3Conditional = Economy.generateGearDrop(3, "Rare", "Weapon", "training-wraps", false, fixedRoll({ 0, 0.99, 0.99 }), nextUuid)
assert(t3Conditional.rolledLines[1].affixId == "cond_dmg_bleed" and t3Conditional.rolledLines[1].value == 3)
local t5Proc = Economy.generateGearDrop(5, "Rare", "Weapon", "training-wraps", false, fixedRoll({ 0, 0.99, 0.99 }), nextUuid)
assert(t5Proc.rolledLines[1].affixId == "proc_bleed_or_burn" and t5Proc.rolledLines[1].value == 6)

-- 3. Bounded +1 -> +10 Tempering (zero destruction + pity)
local temperItem = Economy.generateGearDrop(1, "Rare", "Weapon", "training-wraps", false, fixedRoll({ 0.1 }), nextUuid)
assert(Economy.effectiveBaseStatPts(temperItem) == 2)
for lvl = 1, 5 do
	local res = Economy.temperGear(temperItem, 1000, 100, 100, fixedRoll({ 0.99 }))
	assert(res.ok and res.succeeded and res.item.temperLevel == lvl)
	temperItem = res.item
end
-- Level +6 has 85% base chance; 0.95 fails safely without breaking or downgrading, adding +25% pity -> next try 100%+
local fail6 = Economy.temperGear(temperItem, 1000, 100, 100, fixedRoll({ 0.95 }))
assert(fail6.ok and not fail6.succeeded and fail6.item.temperLevel == 5 and fail6.item.temperPityFailures == 1)
local pass6 = Economy.temperGear(fail6.item, 1000, 100, 100, fixedRoll({ 0.99 }))
assert(pass6.ok and pass6.succeeded and pass6.item.temperLevel == 6 and pass6.item.temperPityFailures == 0)

-- T5 +10 effective base = 10 * 1.20 = 12
local t5Temper = table.clone(t5Leg)
t5Temper.temperLevel = 10
assert(Economy.effectiveBaseStatPts(t5Temper) == 12)

-- 4. Holy Water Purification (Measured Breath T3+ unique gate & T1 rejection)
local cursedT1 = Economy.generateGearDrop(1, "Rare", "Weapon", "anubis-katana", true, fixedRoll({ 0.1 }), nextUuid)
local badT1Breath = Economy.purifyCursedGear(cursedT1, "measured_breath", 500, 2, false)
assert(not badT1Breath.ok)
local goodT1Ward = Economy.purifyCursedGear(cursedT1, "iron_ward", 500, 2, false)
assert(goodT1Ward.ok and not goodT1Ward.item.cursed and goodT1Ward.item.purifiedPerk == "iron_ward" and goodT1Ward.yen == 460 and goodT1Ward.holyWaterCount == 1)

-- 5. Cyberware Tolerance & Full 'Borg Strain boundary (127 unstrained vs 128 strained)
local humanOk = Economy.evaluateCyberwareLoadout("Human", false, {
	{ site = "HeadOptics", tier = 3 }, -- 26
	{ site = "Neural", tier = 1 },     -- 10 (total 36 <= 40)
}, false, 0)
assert(humanOk.ok and humanOk.usedTolerance == 36 and not humanOk.cyberStrainActive)
local vampGoldenApple = Economy.evaluateCyberwareLoadout("Vampire", false, {
	{ site = "HeadOptics", tier = 2 }, -- 18
	{ site = "Neural", tier = 1 },     -- 10 (28 <= 30 strain-free)
}, true, 10) -- Bloodline bonus tolerance ignored on 0-tolerance race!
assert(vampGoldenApple.ok and vampGoldenApple.maxTolerance == 30 and not vampGoldenApple.cyberStrainActive)

local borgStrained = Economy.evaluateCyberwareLoadout("Cyborg", true, {
	{ site = "HeadOptics", tier = 5 },   -- 42
	{ site = "Neural", tier = 5 },       -- 42
	{ site = "TorsoChassis", tier = 5 }, -- 42
	{ site = "Limbs", tier = 1 },        -- 10 -> 136 >= 128
}, false, 0)
assert(borgStrained.ok and borgStrained.cyberStrainActive and borgStrained.controlResistPenaltyPp == 10 and borgStrained.activeRoutineCount == 2)
local fullBorg = Economy.evaluateCyberwareLoadout("FullBorg", false, {
	{ site = "HeadOptics", tier = 5 },
	{ site = "Neural", tier = 5 },
	{ site = "TorsoChassis", tier = 5 },
	{ site = "Limbs", tier = 1 },
}, false, 0)
assert(fullBorg.ok and fullBorg.usedTolerance == 136 and fullBorg.cyberStrainActive)

-- 6. D'Arby Parlor odds sum to 100.0 & spin-10 pity guarantees Rare+
for _, tier in Data.DarbyParlor.Tiers do
	local sumPct = 0
	for _, entry in tier.odds do
		sumPct += entry.weightPct
	end
	assert(math.abs(sumPct - 100.0) < 0.001)
end
local pitySpin = Economy.spinDarbyParlor("standard_chip", 500, 9, true, fixedRoll({ 0.0 }))
assert(pitySpin.ok and pitySpin.rarity ~= "Common" and pitySpin.nextPityCounter == 0 and pitySpin.yen == 400)

-- 7. Negative/NaN validation & Cap clamping
local negNode = Economy.computeNodeRewards(1, "Flag", "F1", "FirstClear")
assert(negNode.ok)
local badSmith = Economy.createSmithRerollOffer(t5Leg, -50, 100, fixedRoll({ 0.1 }))
assert(not badSmith.ok)
local capped = Economy.clampCombatCaps(52, 91, 80, 10)
assert(capped.sourceDmgPct == 35 and capped.prePenMitPct == 75 and capped.effectiveDodgePct == 50)

print("Phase 4 Economy headless suite passed: income, rolls, anti-scum smith, +10 temper, purification, cyberware strain, D'Arby parlor, and audit caps.")
