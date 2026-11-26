--!strict

local Battle = require("../src/shared/Core/BlackSabbathBattle")
local Math = require("../src/shared/Core/SandboxMath")
local Economy = require("../src/shared/Core/Phase4Economy")
local Gear = require("../src/shared/Data/Phase4EconomyData")
local Campaign = require("../src/shared/Data/CampaignPartsData")
local Build = require("../src/shared/Data/BuildCatalogData")
local Bloodline = require("../src/shared/Data/BloodlineTreeData")
local Combat = require("../src/shared/Contracts/CombatTypes")
local Succession = require("../src/shared/Contracts/SuccessionTypes")

type Archetype = {
	name: string, race: Build.RaceId, technique: Build.TechniqueId, scaling: Combat.ScalingTag,
	sourcePct: number, stamina: number,
}
local boxer: Archetype = {
	name = "Unbound Boxing", race = "Human", technique = "Boxing", scaling = "Physical",
	sourcePct = 20, stamina = 6,
}
local archetypes: { Archetype } = {
	{ name = "Hamon User", race = "Human", technique = "Hamon", scaling = "Special", sourcePct = 10, stamina = 5 },
	boxer,
	{ name = "Pure Stand", race = "Human", technique = "StandMastery", scaling = "Special", sourcePct = 10, stamina = 5 },
	{ name = "Cyborg / Full 'Borg", race = "Cyborg", technique = "FullBorg", scaling = "Physical", sourcePct = 0, stamina = 5 },
	{ name = "Vampire / Pillar Man", race = "Vampire", technique = "Boxing", scaling = "Physical", sourcePct = 15, stamina = 5 },
}
for _, archetype in archetypes do
	assert(Build.Compatibility[archetype.race][archetype.technique], archetype.name .. " must be launch-compatible")
end

type Loadout = {
	weapon: number, focus: number, defense: number, health: number, physical: number, special: number,
	precision: number, penetration: number, bleedDamage: number, crit: number,
}
type Slot = "Weapon" | "Head" | "Body" | "Accessory"
local slots: { Slot } = { "Weapon", "Head", "Body", "Accessory" }
local function loadout(tier: number, maxTemper: boolean): Loadout
	local gear: Loadout = {
		weapon = 0, focus = 0, defense = 0, health = 0, physical = 0, special = 0,
		precision = 0, penetration = 0, bleedDamage = 0, crit = 0,
	}
	for _, slot in slots do
		local item = Economy.generateGearDrop(tier, "Legendary", slot, "parity", false, function()
			return 0.98
		end, function() return "parity-" .. slot end)
		if maxTemper then
			local yen, shards, materials = 100000, 100000, 100000
			for _ = 1, 10 do
				local nextTemper = Economy.temperGear(item, yen, shards, materials, function() return 0 end)
				assert(nextTemper.ok and nextTemper.succeeded)
				item, yen, shards, materials = nextTemper.item, nextTemper.yen, nextTemper.shards, nextTemper.materials
			end
			assert(item.tier == 5 and item.temperLevel == 10 and #item.rolledLines == 3, "stress gear must be T5 +10 with three lines")
		end
		local points = Economy.effectiveBaseStatPts(item)
		if slot == "Weapon" then gear.weapon += points
		elseif slot == "Head" then gear.focus += points
		elseif slot == "Body" then gear.defense += points
		else gear.health += points end
		for _, line in item.rolledLines do
			if line.affixId == "flat_physical" then gear.physical += line.value
			elseif line.affixId == "flat_special" then gear.special += line.value
			elseif line.affixId == "flat_defense" then gear.defense += line.value
			elseif line.affixId == "flat_focus" then gear.focus += line.value
			elseif line.affixId == "precision_pp" then gear.precision += line.value
			elseif line.affixId == "def_pen_pp" then gear.penetration += line.value
			elseif line.affixId == "crit_pp" then gear.crit += line.value
			elseif line.affixId == "cond_dmg_bleed" then gear.bleedDamage += line.value end
		end
	end
	return gear
end

local function checkCaps(source: number, mitigation: number, dodge: number, precision: number)
	local caps = Economy.clampCombatCaps(source, mitigation, dodge, precision)
	assert(caps.sourceDmgPct >= 0 and caps.sourceDmgPct <= 35, "source damage cap")
	assert(caps.prePenMitPct >= 0 and caps.prePenMitPct <= 75, "pre-penetration mitigation cap")
	assert(caps.effectiveDodgePct >= 0 and caps.effectiveDodgePct <= 50, "effective Dodge cap")
	return caps
end

local limits = Combat.Phase2Limits
assert(limits.ResolveGainPerTurn == 25 and Gear.GlobalCaps.ResolvePerTurnCap == 25)
local function grantResolve(current: number, gained: number, raw: number): number
	-- Model the sandbox's per-turn and meter budgets for the Phase 5 fixture.
	local granted = math.min(raw, limits.ResolveGainPerTurn - gained, limits.MaxResolve - current)
	assert(granted >= 0 and gained + granted <= 25, "per-turn Resolve cap")
	return granted
end

local function castleFor(storyPart: number): Campaign.Castle
	local nodes = Campaign.Parts[storyPart].nodes
	local castle = nodes[#nodes]
	assert(castle.kind == "Castle")
	return castle
end

local stressGear = loadout(5, true)
local maxGrade = Build.StandGrades["A+"]
-- Exercise the shipped sandbox's Resolve grant too. A landed basic would
-- normally grant eight, but only three points remain in the current turn.
local sandbox = Battle.new("parity-resolve", { level = 10, qteMode = "AutoGood", stageTag = "Neutral" },
	function() return 0.5 end, function() return 0 end)
local player = sandbox.actors.player.view
player.resolve, player.resolveGainedThisTurn = 22, 22
local strike = Battle.submitPrimary(sandbox, {
	battleId = sandbox.id, expectedRevision = sandbox.revision, actorId = "player", slot = "Primary",
	moveId = "BasicStrike", targetId = "black_sabbath",
})
assert(strike.ok and player.resolve == 25 and player.resolveGainedThisTurn == 25, "sandbox must clamp the actual Resolve grant")

local origins: { "Part1_Hamon" | "Part3_Stand" } = { "Part1_Hamon", "Part3_Stand" }
local counts = 0
for act = 1, 5 do
	for _, origin in origins do
		local route = Campaign.OriginRoutes[origin]
		local set = Campaign.BossSets[castleFor(route[act].storyPart).bossSetId]
		local setPoints = 2 * set.onePieceAmountByAct[5]
		local effect = set.fullSet
		local setResolve = if effect.kind == "UltimateLifeform" or effect.kind == "CrimsonEmperor" then effect.resolve else 0
		for _, archetype in archetypes do
			local standPower = if archetype.technique == "StandMastery" then maxGrade.powerPct else 0
			local standGuard = if archetype.technique == "StandMastery" then maxGrade.durabilityGuardPp else 0
			local standPrecision = if archetype.technique == "StandMastery" then maxGrade.precisionPp else 0
			local standResolve = if archetype.technique == "StandMastery" then maxGrade.potentialResolvePerNaturalTurn else 0
			local setDefense = if set.onePieceStat == "Defense" then setPoints else 0
			local setPrecision = if set.onePieceStat == "PrecisionPp" then setPoints else 0
			if effect.kind == "QuietLife" then setPrecision += effect.precisionPp end

			-- Inject excess from the same combat buckets after applying the real gear and catalog modifiers.
			local source = archetype.sourcePct + stressGear.bleedDamage + standPower + 40
			local defense = 250 + stressGear.defense + setDefense
			local mitigationPp = standGuard + 35
			local mitigation = math.min(51, defense * 0.2) + mitigationPp
			local precision = Math.focusPrecision(stressGear.focus) + stressGear.precision + standPrecision + setPrecision
			local caps = checkCaps(source, mitigation, 100, precision)
			assert(source > 35 and mitigation > 75 and 100 - precision > 50, "stress case must exceed all three cap inputs")
			assert(caps.sourceDmgPct == 35 and caps.prePenMitPct == 75 and caps.effectiveDodgePct == 50)

			local raw = Math.basicRaw(10 * act, 50 + stressGear.weapon)
			local hit: Math.DamageInput = { raw = raw, sourceBonus = source / 100, defense = defense, mitigationPp = mitigationPp,
				penetrationPp = 15 + stressGear.penetration, guarding = true, armor = 0, act = act }
			local saturated = Math.damage(hit)
			hit.sourceBonus = 0.35
			assert(Math.damage(hit) == saturated, "SandboxMath must cap source damage before Guard")
			hit.mitigationPp = 75 - math.min(51, defense * 0.2)
			assert(Math.damage(hit) == saturated, "SandboxMath must cap mitigation before penetration")
			assert(Math.dodgePercent(100, 0) == 50)

			local opening = grantResolve(0, 0, 10 + standResolve + setResolve)
			local lowHp = grantResolve(opening, opening, limits.LowHpResolve)
			assert(opening + limits.LowHpResolve > 25 and opening + lowHp == 25)
			assert(grantResolve(25, 25, 10) == 0, "a further trigger cannot raise Resolve in the same turn")
			counts += 1
		end
	end
end
assert(counts == 50)
print(string.format("Combat caps: %d overloaded T5 +10 combinations held (35/75/50/25)", counts))

type Age = { years: number, veteranRank: number, race: Build.RaceId }
type Result = {
	turns: number, hp: number, maxHp: number, maxStamina: number, guards: number, telegraphs: number,
}
local function challenge(
	act: number, storyPart: number, archetype: Archetype, gear: Loadout, age: Age, combatRace: Build.RaceId
): Result
	local castle = castleFor(storyPart)
	local level = 10 * act
	local stat = 18 + level + gear.weapon
	local cyborgActive = archetype.technique == "FullBorg" and act >= Gear.Cyberware.UnlockAct
	local implants = Gear.Cyberware.Sites
	if cyborgActive then
		local installed: { Economy.CyberwareInstall } = {
			{ site = "HeadOptics", tier = act }, { site = "TorsoChassis", tier = act },
			{ site = "Limbs", tier = act }, { site = "HeartCore", tier = act },
		}
		assert(Economy.evaluateCyberwareLoadout("Cyborg", true, installed, false, 0).ok)
	end
	local implantPhysical = if cyborgActive then implants.Limbs.valuesByTier[act] else 0
	local implantDefense = if cyborgActive then implants.TorsoChassis.valuesByTier[act] else 0
	local implantPrecision = if cyborgActive then implants.HeadOptics.valuesByTier[act] else 0
	local heartBonus = if cyborgActive then implants.HeartCore.valuesByTier[act] else 0
	local isStand = archetype.technique == "StandMastery"
	local grades = Build.StandsById[if act == 5 then "star_platinum" else "silver_chariot"].grades
	local standPower = if isStand then Build.StandGrades[grades.Power].powerPct else 0
	local standGuard = if isStand then Build.StandGrades[grades.Durability].durabilityGuardPp else 0
	local standPrecision = if isStand then Build.StandGrades[grades.Precision].precisionPp else 0
	local standResolve = if isStand then Build.StandGrades[grades.Potential].potentialResolvePerNaturalTurn else 0
	local elder = age.years >= Succession.ElderThreshold and not Build.Races[age.race].ageless
	local resilient = elder and age.veteranRank > 0
	local hpFactor = if resilient then 0.95 elseif elder then 0.90 else 1
	local maxHp = math.floor(Math.playerHp(level, 15 + act * 6 + gear.health) * hpFactor)
	local maxStamina = archetype.stamina - (if elder and not resilient then 1 else 0)
	local stamina, hp, resolve = maxStamina, maxHp, 0
	local telegraphs, guards, phaseTurns, fireTurns = 0, 0, 0, 0
	local blood = 30
	local undead = combatRace == "Vampire" or combatRace == "PillarMan"
	local raceMitigation = if combatRace == "PillarMan" then 5 else 0
	local raw = Math.basicRaw(level, Math.scalingStat(archetype.scaling, stat + gear.physical + implantPhysical, stat + gear.special))
	local defense = stat + gear.defense + implantDefense
	local precision = Math.focusPrecision(gear.focus) + gear.precision + implantPrecision + standPrecision

	-- One equal budget, opponent, companion, and policy per Act. Fixture HP, armor, and
	-- boss cadence are fixed inputs alongside the launch catalog's phases and move multipliers.
	local bossMaxHp = 260 + 84 * act
	local bossHp = bossMaxHp
	local bossDefense = 24 + 7 * act
	local bossDodge = 3 + act
	local companion = Math.damage({ raw = Math.basicRaw(level, stat * 0.8), defense = bossDefense, armor = act, act = act })
	local phaseIndex = 1
	local pending: Campaign.BossMove? = nil
	local remainingWindup = 0
	local moveIndex = 0

	for turn = 1, 40 do
		if phaseIndex == 1 and bossHp * 100 <= bossMaxHp * castle.phases[2].startsAtHpPct then
			phaseIndex, phaseTurns, moveIndex = 2, 0, 0
		end
		local phase = castle.phases[phaseIndex]
		phaseTurns += 1
		local queued = pending
		local guarding = queued ~= nil and remainingWindup == 1
		local gained = 0
		stamina = math.min(maxStamina, stamina + 1)
		if not guarding then
			-- Reserve two Stamina before committing to a three-Stamina Heavy.
			local heavy = stamina >= 5
			if heavy then
				stamina -= 3
			end
			local bossGuards = not queued and phaseTurns % 5 == 0
			local bleed = gear.bleedDamage > 0 and turn % 4 == 0
			local source = archetype.sourcePct + standPower + (if bleed then gear.bleedDamage else 0)
			local caps = checkCaps(source, bossDefense * 0.2, bossDodge, precision)
			local lands = (17 + turn * 37) % 100 >= caps.effectiveDodgePct
			if lands then
				local hit = Math.damage({
					raw = raw * (if heavy then 1.45 else 1), sourceBonus = caps.sourceDmgPct / 100,
					defense = bossDefense, penetrationPp = gear.penetration, armor = act, act = act,
					onFire = fireTurns > 0, guarding = bossGuards, critical = (turn * 31) % 100 < gear.crit,
				})
				bossHp -= hit
				if fireTurns == 0 then
					gained = grantResolve(resolve, gained, math.floor((if heavy then 10 else 8) * (1 + heartBonus / 100)) + standResolve)
					resolve += gained
				end
				if undead then blood += 3 end
			end
		end
		bossHp -= companion
		if bossHp <= 0 then
			return { turns = turn, hp = hp, maxHp = maxHp, maxStamina = maxStamina,
				guards = guards, telegraphs = telegraphs }
		end

		local incoming = 10 + act * 2
		local mitigation = raceMitigation + (if guarding then standGuard else 0)
		checkCaps(0, math.min(51, defense * 0.2) + mitigation, 0, 0)
		local penetration = if queued and queued.name == "Space Ripper Stingy Eyes" then 15 else 0
		local function receive(multiplier: number)
			hp -= Math.damage({ raw = incoming * multiplier, defense = defense, mitigationPp = mitigation,
				penetrationPp = penetration, guarding = guarding, armor = act, act = act })
		end

		if queued then
			remainingWindup -= 1
			if remainingWindup == 0 then
				telegraphs += 1
				if guarding then guards += 1 end
				receive(queued.multiplier or 1)
				if queued.bonusPrimaryMultiplier then receive(queued.bonusPrimaryMultiplier) end
				pending = nil
			end
		elseif phaseTurns % 3 == 1 then
			local move = phase.moves[moveIndex % #phase.moves + 1]
			moveIndex += 1
			if move.telegraphTurns then
				pending = move
				remainingWindup = move.telegraphTurns
			else
				receive(move.multiplier or 1)
			end
		else
			receive(1)
		end
		assert(hp > 0, string.format("%s lost Act %d / Part %d on turn %d", archetype.name, act, storyPart, turn))
		if hp < maxHp * 0.65 and undead and blood > 25 then
			blood -= 15
			hp += math.floor(maxHp * 0.10)
		end
		if fireTurns > 0 then
			fireTurns -= 1
		elseif resolve == limits.MaxResolve then
			resolve, fireTurns = 0, limits.OnFireTurns
		end
	end
	error("Castle fixture exceeded its 40-turn limit")
end

local youngest: Age = { years = 18, veteranRank = 0, race = "Human" }
local maxDeviation = 0
for act = 1, 5 do
	local gear = loadout(act, false)
	for _, origin in origins do
		local entry = Campaign.OriginRoutes[origin][act]
		assert(entry.actTier == act)
		local turns: { number } = {}
		for _, archetype in archetypes do
			local age = table.clone(youngest)
			-- The Clinic is closed in Act 1; the bloodline path graduates from Vampire to Pillar Man.
			age.race = if archetype.race == "Cyborg" and act < Gear.Cyberware.UnlockAct then "Human"
				elseif archetype.race == "Vampire" and act == 5 then "PillarMan" else archetype.race
			local result = challenge(act, entry.storyPart, archetype, gear, age, age.race)
			table.insert(turns, result.turns)
		end
		local sorted = table.clone(turns)
		table.sort(sorted)
		local median = sorted[3]
		for index, turnCount in turns do
			local deviation = math.abs(turnCount - median) / median
			maxDeviation = math.max(maxDeviation, deviation)
			assert(deviation <= 0.15, string.format("%s Act %d (%s): %d turns vs median %d",
				archetypes[index].name, act, origin, turnCount, median))
		end
		print(string.format("Act %d %s (Part %d): %d/%d/%d/%d/%d turns, median %d",
			act, origin, entry.storyPart, turns[1], turns[2], turns[3], turns[4], turns[5], median))
	end
end
print(string.format("Largest median deviation: %.2f%%", maxDeviation * 100))

local veteran = Bloodline.Nodes.veteran_composure
assert(#veteran.costs == 1 and Succession.ElderThreshold == 56)
local finaleGear = loadout(5, false)
local elder = challenge(5, 5, boxer, finaleGear, { years = 59, veteranRank = 0, race = "Human" }, "Human")
local composed = challenge(5, 5, boxer, finaleGear, { years = 59, veteranRank = #veteran.costs, race = "Human" }, "Human")
-- Hold the Human Boxer combat package constant to isolate the Ageless age modifier.
local ageless = challenge(5, 5, boxer, finaleGear, { years = 59, veteranRank = 0, race = "PillarMan" }, "Human")
assert(elder.maxHp == math.floor(ageless.maxHp * 0.90) and elder.maxStamina == ageless.maxStamina - 1)
assert(composed.maxHp == math.floor(ageless.maxHp * 0.95) and composed.maxStamina == ageless.maxStamina)
for _, result in { elder, composed, ageless } do
	assert(result.hp > 0 and result.telegraphs > 0 and result.guards == result.telegraphs, "Finale must clear and guard every resolved telegraph")
end
assert(composed.hp > elder.hp and ageless.hp > elder.hp, "both builds must improve Finale survival")
assert(composed.turns <= elder.turns and ageless.turns <= elder.turns, "survival gains must not cost turns")
print(string.format("Age-59 Finale (turns, HP left): Elder %d/%d, Veteran %d/%d, Ageless %d/%d. Elder guarded %d/%d telegraphs.",
	elder.turns, elder.hp, composed.turns, composed.hp, ageless.turns, ageless.hp, elder.guards, elder.telegraphs))
print("phase5_parity: PASS")
