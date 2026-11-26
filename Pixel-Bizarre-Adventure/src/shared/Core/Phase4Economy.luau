--!strict
-- Pure deterministic Phase 4 economy, Blacksmith, Tempering, Purification,
-- Cyberware, and D'Arby Parlor calculator. Zero Roblox Instance dependencies.

local Data = require("../Data/Phase4EconomyData")

export type NodeKind = "Flag" | "Dungeon" | "Castle"
export type RunMode = "FirstClear" | "Replay"
export type RolledLine = {
	affixId: Data.AffixId,
	value: number,
}
export type GearInstance = {
	uuid: string,
	familyId: string,
	slot: "Weapon" | "Head" | "Body" | "Accessory",
	tier: number,
	rarity: Data.Rarity,
	baseStatPts: number,
	temperLevel: number,
	temperPityFailures: number,
	cursed: boolean,
	purifiedPerk: Data.PurifiedPerkId?,
	rolledLines: { RolledLine },
	pendingSmithOffer: { RolledLine }?,
}
export type CyberwareInstall = {
	site: Data.CyberwareSite,
	tier: number,
}

local Phase4Economy = {}

local function isFiniteInt(value: unknown, minVal: number, maxVal: number): boolean
	return type(value) == "number" and value == value and value >= minVal and value <= maxVal and value % 1 == 0
end

local function clampRoll(roll: () -> number): number
	local r = roll()
	if r ~= r or r < 0 then
		return 0
	end
	if r >= 1 then
		return 0.9999999
	end
	return r
end

local function roundHalfUp(value: number): number
	return math.floor(value + 0.5)
end

-- 1. Act 1-5 Node Rewards (Replay = 50% Yen, 0 XP, 0 Marks, 0 Echoes)
function Phase4Economy.computeNodeRewards(act: number, nodeKind: NodeKind, nodeId: string, mode: RunMode): {
	ok: boolean,
	yen: number,
	materials: number,
	xpLevels: number,
	masteryMarks: number,
	echoes: number,
	error: string?,
}
	if not isFiniteInt(act, 1, 5) then
		return { ok = false, yen = 0, materials = 0, xpLevels = 0, masteryMarks = 0, echoes = 0, error = "Invalid act." }
	end
	local row = Data.ActIncome[act]
	local baseYen: number? = nil
	local mats = 0
	if nodeKind == "Flag" then
		baseYen = (row.flagYen :: { [string]: number })[nodeId]
		mats = row.materialDrops.flag
	elseif nodeKind == "Dungeon" then
		baseYen = (row.dungeonYen :: { [string]: number })[nodeId]
		mats = row.materialDrops.dungeon
	elseif nodeKind == "Castle" then
		baseYen = row.castleYen
		mats = row.materialDrops.castle
	end
	if baseYen == nil then
		return { ok = false, yen = 0, materials = 0, xpLevels = 0, masteryMarks = 0, echoes = 0, error = "Unknown nodeId." }
	end
	local isFirst = mode == "FirstClear"
	local yen = if isFirst then baseYen else math.floor(baseYen * row.replayYenMultiplier)
	return {
		ok = true,
		yen = yen,
		materials = mats,
		xpLevels = if isFirst and nodeKind ~= "Castle" then 1 else Data.GlobalCaps.ReplayXp,
		masteryMarks = if isFirst and nodeKind ~= "Flag" then 1 else Data.GlobalCaps.ReplayMasteryMarks,
		echoes = if isFirst and nodeKind == "Castle" then 1 else Data.GlobalCaps.ReplayEchoes,
	}
end

-- 2. Rolled Line Generation (+0.6 / +0.7 / +0.8 x Act diminishing pool)
local function rollDistinctLines(tier: number, lineCount: number, roll: () -> number): { RolledLine }?
	if lineCount == 0 then
		return {}
	end
	local multiplier = Data.LineBudgetMultiplier[lineCount]
	if not multiplier or lineCount > Data.MaxLinesByAct[tier] then return nil end
	local perLineBudget = multiplier * tier / lineCount
	local available: { Data.Affix } = {}
	for _, entry in Data.AffixPool do
		local minimumCost = entry.unitCostPts * (entry.minPct or 1)
		if entry.minTier <= tier and minimumCost <= perLineBudget + 1e-9 then
			table.insert(available, entry)
		end
	end
	if #available < lineCount then return nil end
	local lines: { RolledLine } = {}
	for _ = 1, lineCount do
		local weightSum = 0
		for _, entry in available do
			weightSum += entry.weight
		end
		local pick = clampRoll(roll) * weightSum
		local acc = 0
		local chosenIdx = #available
		for idx, entry in available do
			acc += entry.weight
			if pick < acc then
				chosenIdx = idx
				break
			end
		end
		local entry = table.remove(available, chosenIdx)
		assert(entry ~= nil)
		local val = math.floor(perLineBudget / entry.unitCostPts + 1e-9)
		local minPct = entry.minPct
		if minPct then
			local maxPct = math.min(assert(entry.maxPct), val)
			val = minPct + math.floor(clampRoll(roll) * (maxPct - minPct + 1))
		end
		table.insert(lines, { affixId = entry.id, value = val })
	end
	return lines
end

function Phase4Economy.generateGearDrop(
	act: number,
	rarity: Data.Rarity,
	slot: "Weapon" | "Head" | "Body" | "Accessory",
	familyId: string,
	cursed: boolean,
	roll: () -> number,
	makeUuid: () -> string
): GearInstance
	assert(isFiniteInt(act, 1, 5), "act must be 1..5")
	local weights = Data.LineCountWeightsByRarity[rarity]
	local maxLines = Data.MaxLinesByAct[act]
	local validWeights: { { count: number, w: number } } = {}
	local sumW = 0
	for count = 0, 3 do
		local w = weights[count] or 0
		if w > 0 then
			table.insert(validWeights, { count = count, w = w })
			sumW += w
		end
	end
	local lineCount = 0
	if sumW > 0 then
		local pick = clampRoll(roll) * sumW
		local acc = 0
		for _, pair in validWeights do
			acc += pair.w
			if pick < acc then
				lineCount = math.min(maxLines, pair.count)
				break
			end
		end
	end
	local rolledLines = rollDistinctLines(act, lineCount, roll)
	-- A drop can roll more lines than this tier can afford as distinct affixes.
	while rolledLines == nil do
		lineCount -= 1
		rolledLines = rollDistinctLines(act, lineCount, roll)
	end
	return {
		uuid = makeUuid(),
		familyId = familyId,
		slot = slot,
		tier = act,
		rarity = rarity,
		baseStatPts = Data.GlobalCaps.BaseGearBudgetPerSlotMultiplier * act,
		temperLevel = 0,
		temperPityFailures = 0,
		cursed = cursed,
		purifiedPerk = nil,
		rolledLines = assert(rolledLines),
		pendingSmithOffer = nil,
	}
end

-- 3. Blacksmith Anti-Scum Reroll (Persists pendingSmithOffer before reveal)
function Phase4Economy.createSmithRerollOffer(
	item: GearInstance,
	yen: number,
	shards: number,
	roll: () -> number
): { ok: boolean, item: GearInstance, yen: number, shards: number, error: string? }
	if item.pendingSmithOffer ~= nil then
		return { ok = false, item = item, yen = yen, shards = shards, error = "Resolve pending smith offer first." }
	end
	local lineCount = #item.rolledLines
	if lineCount == 0 then
		return { ok = false, item = item, yen = yen, shards = shards, error = "Plain gear has no rolled lines." }
	end
	if not isFiniteInt(yen, 0, 2 ^ 50) or not isFiniteInt(shards, 0, 2 ^ 50) then
		return { ok = false, item = item, yen = yen, shards = shards, error = "Invalid currency amount." }
	end
	local cost = Data.BlacksmithRerollCostByTier[item.tier]
	if not cost then
		return { ok = false, item = item, yen = yen, shards = shards, error = "Invalid item tier." }
	end
	if yen < cost.yen or shards < cost.shards then
		return { ok = false, item = item, yen = yen, shards = shards, error = "Insufficient Yen or Shards." }
	end
	local lines = rollDistinctLines(item.tier, lineCount, roll)
	if not lines then
		return { ok = false, item = item, yen = yen, shards = shards, error = "Too few eligible affixes for this line count." }
	end
	local updated = table.clone(item)
	updated.pendingSmithOffer = lines
	return {
		ok = true,
		item = updated,
		yen = yen - cost.yen,
		shards = shards - cost.shards,
	}
end

function Phase4Economy.resolveSmithOffer(
	item: GearInstance,
	decision: "AcceptNew" | "KeepOld"
): { ok: boolean, item: GearInstance, error: string? }
	local offer = item.pendingSmithOffer
	if not offer then
		return { ok = false, item = item, error = "No pending smith offer." }
	end
	local updated = table.clone(item)
	if decision == "AcceptNew" then
		updated.rolledLines = offer
	end
	updated.pendingSmithOffer = nil
	return { ok = true, item = updated }
end

-- 4. Bounded +1 -> +10 Tempering (Zero Destruction / Downgrade)
function Phase4Economy.temperCost(tier: number, toLevel: number): (number, number, number)
	local mult = Data.TemperTierMultiplier[tier]
	local lvl = Data.TemperLevels[toLevel]
	return roundHalfUp(lvl.baseYen * mult), roundHalfUp(lvl.baseShards * mult), roundHalfUp(lvl.baseMaterials * mult)
end

function Phase4Economy.effectiveBaseStatPts(item: GearInstance): number
	local pct = math.min(Data.GlobalCaps.TemperMaxBonusPct, item.temperLevel * Data.GlobalCaps.TemperPctPerLevel)
	return roundHalfUp(item.baseStatPts * (1 + pct / 100))
end

function Phase4Economy.temperGear(
	item: GearInstance,
	yen: number,
	shards: number,
	materials: number,
	roll: () -> number
): { ok: boolean, succeeded: boolean, item: GearInstance, yen: number, shards: number, materials: number, error: string? }
	if item.temperLevel >= Data.GlobalCaps.TemperMaxLevel then
		return { ok = false, succeeded = false, item = item, yen = yen, shards = shards, materials = materials, error = "Already +10." }
	end
	if not isFiniteInt(yen, 0, 2 ^ 50) or not isFiniteInt(shards, 0, 2 ^ 50) or not isFiniteInt(materials, 0, 2 ^ 50) then
		return { ok = false, succeeded = false, item = item, yen = yen, shards = shards, materials = materials, error = "Invalid resource balance." }
	end
	local nextLevel = item.temperLevel + 1
	local levelInfo = Data.TemperLevels[nextLevel]
	local yenCost, shardCost, matCost = Phase4Economy.temperCost(item.tier, nextLevel)
	if yen < yenCost or shards < shardCost or materials < matCost then
		return { ok = false, succeeded = false, item = item, yen = yen, shards = shards, materials = materials, error = "Insufficient resources." }
	end
	local effectiveChance = math.min(100, levelInfo.successRatePct + item.temperPityFailures * levelInfo.pityAddPctPerFail)
	local succeeded = (clampRoll(roll) * 100) < effectiveChance
	local updated = table.clone(item)
	if succeeded then
		updated.temperLevel = nextLevel
		updated.temperPityFailures = 0
	else
		-- Zero destruction / zero downgrade: only pity increments.
		updated.temperPityFailures = item.temperPityFailures + 1
	end
	return {
		ok = true,
		succeeded = succeeded,
		item = updated,
		yen = yen - yenCost,
		shards = shards - shardCost,
		materials = materials - matCost,
	}
end

-- 5. Holy Water Purification (Removes BOTH Cursed +6 Crit and -5% HP Recoil)
function Phase4Economy.purifyCursedGear(
	item: GearInstance,
	perkId: Data.PurifiedPerkId,
	yen: number,
	holyWaterCount: number,
	alreadyHasUniqueMeasuredBreath: boolean
): { ok: boolean, item: GearInstance, yen: number, holyWaterCount: number, error: string? }
	if not item.cursed then
		return { ok = false, item = item, yen = yen, holyWaterCount = holyWaterCount, error = "Item is not Cursed." }
	end
	if not isFiniteInt(yen, 0, 2 ^ 50) or not isFiniteInt(holyWaterCount, 0, 2 ^ 50) then
		return { ok = false, item = item, yen = yen, holyWaterCount = holyWaterCount, error = "Invalid resource balance." }
	end
	local perk = (Data.PurifiedPerks :: { [string]: any })[perkId]
	if not perk then
		return { ok = false, item = item, yen = yen, holyWaterCount = holyWaterCount, error = "Unknown purified perk." }
	end
	if item.tier < perk.minTier then
		return { ok = false, item = item, yen = yen, holyWaterCount = holyWaterCount, error = "Perk requires higher tier." }
	end
	if perk.uniqueLoadoutLimit and alreadyHasUniqueMeasuredBreath then
		return { ok = false, item = item, yen = yen, holyWaterCount = holyWaterCount, error = "Measured Breath limit reached." }
	end
	local yenCost = Data.HolyWaterPriceByTier[item.tier]
	if holyWaterCount < 1 or yen < yenCost then
		return { ok = false, item = item, yen = yen, holyWaterCount = holyWaterCount, error = "Need 1 Holy Water and sufficient Yen." }
	end
	local updated = table.clone(item)
	updated.cursed = false
	updated.purifiedPerk = perkId
	return {
		ok = true,
		item = updated,
		yen = yen - yenCost,
		holyWaterCount = holyWaterCount - 1,
	}
end

-- 6. Cyberware Clinic Tolerance & Cyber-Strain Evaluator
function Phase4Economy.evaluateCyberwareLoadout(
	race: Data.RaceId,
	isFullBorg: boolean,
	installs: { CyberwareInstall },
	hasGoldenApple: boolean,
	bloodlineBonusTolerance: number
): {
	ok: boolean,
	maxTolerance: number,
	usedTolerance: number,
	cyberStrainActive: boolean,
	controlResistPenaltyPp: number,
	extraAgingYears: number,
	activeRoutineCount: number,
	error: string?,
}
	local rInfo = (Data.Cyberware.RacialTolerance :: { [string]: any })[race]
	if not rInfo then
		return { ok = false, maxTolerance = 0, usedTolerance = 0, cyberStrainActive = false, controlResistPenaltyPp = 0, extraAgingYears = 0, activeRoutineCount = 0, error = "Unknown race." }
	end
	local fullBorg = race == "FullBorg" or (race == "Cyborg" and isFullBorg)
	local baseTol = if fullBorg then Data.Cyberware.RacialTolerance.FullBorg.base else rInfo.base
	-- Audit rule: Bloodline bonus tolerance applies ONLY to implant-eligible races.
	local extraBloodline = if rInfo.eligible then math.max(0, bloodlineBonusTolerance) else 0
	local appleTol = if hasGoldenApple then Data.Cyberware.GoldenAppleStrainFreeBonus else 0
	local maxTol = baseTol + extraBloodline + appleTol
	local maxSites = if rInfo.eligible then rInfo.maxSites elseif hasGoldenApple then Data.Cyberware.GoldenAppleMinUnlockedSites else 0

	if #installs > maxSites then
		return { ok = false, maxTolerance = maxTol, usedTolerance = 0, cyberStrainActive = false, controlResistPenaltyPp = 0, extraAgingYears = 0, activeRoutineCount = 0, error = "Site limit exceeded." }
	end

	local seenSites: { [string]: boolean } = {}
	local used = 0
	local actives = 0
	for _, imp in installs do
		if seenSites[imp.site] then
			return { ok = false, maxTolerance = maxTol, usedTolerance = 0, cyberStrainActive = false, controlResistPenaltyPp = 0, extraAgingYears = 0, activeRoutineCount = 0, error = "Duplicate body site." }
		end
		seenSites[imp.site] = true
		local tInfo = Data.Cyberware.Tiers[imp.tier]
		if not tInfo then
			return { ok = false, maxTolerance = maxTol, usedTolerance = 0, cyberStrainActive = false, controlResistPenaltyPp = 0, extraAgingYears = 0, activeRoutineCount = 0, error = "Invalid cyberware tier." }
		end
		used += tInfo.tolerance
		if tInfo.grantsActive then
			actives += 1
		end
	end
	if used > maxTol then
		return { ok = false, maxTolerance = maxTol, usedTolerance = used, cyberStrainActive = false, controlResistPenaltyPp = 0, extraAgingYears = 0, activeRoutineCount = actives, error = "Exceeds Cyberware Tolerance." }
	end

	-- Golden Apple's +30 is explicitly Strain-Free.
	local strainedLoad = math.max(0, used - appleTol)
	local strainThreshold = Data.Cyberware.StrainThresholdBase + (if fullBorg then math.floor(extraBloodline * 0.8 + 0.0001) else 0)
	local strained = fullBorg and strainedLoad >= strainThreshold
	return {
		ok = true,
		maxTolerance = maxTol,
		usedTolerance = used,
		cyberStrainActive = strained,
		controlResistPenaltyPp = if strained then Data.Cyberware.StrainControlResistPenaltyPp else 0,
		extraAgingYears = if strained then Data.Cyberware.StrainExtraAgingYears else 0,
		activeRoutineCount = math.min(actives, Data.Cyberware.MaxEquippedHighTierActives),
	}
end

-- 7. D'Arby's Hub Parlor Spin (Pity on 10th spin, duplicate cosmetic shard refund)
function Phase4Economy.spinDarbyParlor(
	tierId: Data.ParlorTierId,
	yen: number,
	pityCounter: number,
	alreadyOwnedCosmetic: boolean,
	roll: () -> number
): {
	ok: boolean,
	yen: number,
	nextPityCounter: number,
	bucket: string?,
	rarity: Data.Rarity?,
	shardRefund: number,
	error: string?,
}
	local tier = Data.DarbyParlor.Tiers[tierId]
	if not tier then
		return { ok = false, yen = yen, nextPityCounter = pityCounter, shardRefund = 0, error = "Unknown Parlor tier." }
	end
	if not isFiniteInt(yen, 0, 2 ^ 50) or not isFiniteInt(pityCounter, 0, 100) then
		return { ok = false, yen = yen, nextPityCounter = pityCounter, shardRefund = 0, error = "Invalid balance or pity." }
	end
	if yen < tier.singleYen then
		return { ok = false, yen = yen, nextPityCounter = pityCounter, shardRefund = 0, error = "Insufficient Yen." }
	end

	local forceRarePlus = (pityCounter + 1) >= tier.pityThreshold
	local eligible: { Data.ParlorEntry } = {}
	local totalW = 0
	for _, entry in tier.odds do
		if not forceRarePlus or entry.rarity ~= "Common" then
			table.insert(eligible, entry)
			totalW += entry.weightPct
		end
	end
	local pick = clampRoll(roll) * totalW
	local acc = 0
	local chosen = eligible[#eligible]
	for _, entry in eligible do
		acc += entry.weightPct
		if pick < acc then
			chosen = entry
			break
		end
	end
	local refund = if chosen.isCosmetic and alreadyOwnedCosmetic
		then (Data.DarbyParlor.DuplicateCosmeticShardRefund :: { [string]: number })[chosen.rarity]
		else 0
	local nextPity = if chosen.rarity == "Common" then pityCounter + 1 else 0
	return {
		ok = true,
		yen = yen - tier.singleYen,
		nextPityCounter = nextPity,
		bucket = chosen.bucket,
		rarity = chosen.rarity,
		shardRefund = refund,
	}
end

-- 8. Global Combat Cap Clamper (Audit Proof: 35% Dmg, 75% Mit, 50% Effective Dodge)
function Phase4Economy.clampCombatCaps(
	rawSourceDmgPct: number,
	rawPrePenMitPct: number,
	targetDodgePct: number,
	attackerPrecisionPct: number
): { sourceDmgPct: number, prePenMitPct: number, effectiveDodgePct: number }
	return {
		sourceDmgPct = math.clamp(rawSourceDmgPct, 0, Data.GlobalCaps.SourceDamageCapPct),
		prePenMitPct = math.clamp(rawPrePenMitPct, 0, Data.GlobalCaps.PrePenMitigationCapPct),
		effectiveDodgePct = math.clamp(math.max(0, targetDodgePct - attackerPrecisionPct), 0, Data.GlobalCaps.EffectiveDodgeCapPct),
	}
end

return table.freeze(Phase4Economy)
