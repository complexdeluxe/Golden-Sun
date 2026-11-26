--!strict

local Assets = require("../src/shared/Contracts/AssetManifest")
local Save = require("../src/shared/Contracts/SaveTypes")
local Openers = require("../src/shared/Data/ActOneEncounters")
local Starter = require("../src/shared/Data/CampaignStarter")
local Campaign = require("../src/shared/Data/CampaignPartsData")
local Build = require("../src/shared/Data/BuildCatalogData")
local Economy = require("../src/shared/Data/Phase4EconomyData")

local function checkAsset(key: Assets.AssetKey?)
	if key then assert(Assets[key] ~= nil, "Missing AssetManifest key: " .. key) end
end

local order: { Campaign.NodeId } = { "F1", "F2", "D1", "F3", "F4", "D2", "F5", "F6", "F7", "D3", "Castle" }
local storyTitles = { "Phantom Blood", "Battle Tendency", "Stardust Crusaders", "Diamond Is Unbreakable", "Golden Wind" }
local weightedEncounters = 0
assert(#Campaign.Parts == 5 and table.isfrozen(Campaign.Parts))
for storyPart, part in Campaign.Parts do
	assert(part.storyPart == storyPart and part.title == storyTitles[storyPart])
	assert(#part.nodes == #order and table.isfrozen(part) and table.isfrozen(part.nodes))
	local flags, dungeons, castles, approaches = 0, 0, 0, 0
	local approachIds: { [string]: boolean } = {}
	for index, node in part.nodes do
		assert(node.id == order[index] and node.opponent ~= "" and node.location ~= "" and node.hook ~= "")
		assert(table.isfrozen(node))
		checkAsset(node.stageAssetKey)
		if node.kind == "Flag" then
			flags += 1
		elseif node.kind == "Dungeon" then
			dungeons += 1
			assert(#node.approaches == 2 and table.isfrozen(node.approaches))
			local defaultFound = node.defaultApproachId == nil
			for _, wave in node.approaches do
				assert(wave.opponent ~= "" and wave.hook ~= "" and not approachIds[wave.id] and table.isfrozen(wave))
				approachIds[wave.id] = true
				defaultFound = defaultFound or wave.id == node.defaultApproachId
				approaches += 1
			end
			assert(defaultFound)
		else
			castles += 1
			assert(Campaign.BossSets[node.bossSetId].storyPart == storyPart)
			assert(#node.phases == 2 and table.isfrozen(node.phases))
			assert(node.phases[1].startsAtHpPct == 100 and node.phases[2].startsAtHpPct == Campaign.CastleTransition.startsAtHpPct)
			for phaseIndex, phase in node.phases do
				assert(#phase.moves > 0 and table.isfrozen(phase) and table.isfrozen(phase.moves))
				for _, move in phase.moves do
					assert(move.name ~= "" and table.isfrozen(move))
					if phaseIndex == 2 then assert(move.telegraphTurns == 1) end
					if move.bonusPrimaryMultiplier then assert(storyPart == 3 and move.bonusPrimaryMultiplier == 1.75) end
				end
			end
		end
	end
	assert(flags == 7 and dungeons == 3 and castles == 1 and approaches == 6)
	weightedEncounters += #part.nodes + approaches
end
assert(weightedEncounters == 85 and Campaign.CastleTransition.maxTransitions == 1)
assert(Campaign.CastleTransition.queueAfterCrossingAttack)

local expectedHamon = { 1, 2, 3, 4, 5 }
local expectedStand = { 3, 1, 2, 4, 5 }
local origins: { Save.Origin } = { "Part1_Hamon", "Part3_Stand" }
for _, origin in origins do
	local route = Campaign.OriginRoutes[origin]
	local expected = if origin == "Part1_Hamon" then expectedHamon else expectedStand
	local seen: { [number]: boolean } = {}
	assert(#route == 5 and table.isfrozen(route))
	for act, entry in route do
		assert(entry.actTier == act and entry.storyPart == expected[act] and not seen[entry.storyPart])
		assert(entry.isFlashback == (origin == "Part3_Stand" and (entry.storyPart == 1 or entry.storyPart == 2)))
		seen[entry.storyPart] = true
	end
	local opener = Campaign.Parts[route[1].storyPart]
	local f1, f2, d1 = opener.nodes[1], opener.nodes[2], opener.nodes[3]
	assert(f1.kind == "Flag" and f2.kind == "Flag" and d1.kind == "Dungeon")
	local waves = Openers.Routes[origin].waves
	local stages = Starter.ActOneRoutes[origin].stages
	assert(f1.opponent == waves.F1[1].label and f1.opponentId == waves.F1[1].id)
	assert(f2.opponent == waves.F2[1].label and f2.opponentId == waves.F2[1].id)
	local foundDefault = false
	for _, approach in d1.approaches do
		if approach.id == d1.defaultApproachId then
			assert(approach.id == waves.D1[1].id and approach.opponent == waves.D1[1].label)
			foundDefault = true
		end
	end
	assert(foundDefault)
	assert(d1.defaultApproachId == waves.D1[1].id and d1.opponentId == waves.D1[2].id and d1.opponent == waves.D1[2].label)
	assert(d1.recruitId == Openers.Routes[origin].recruit.companionId)
	assert(f1.stageAssetKey == stages.F1.assetKey and f1.location == stages.F1.label)
	assert(f2.stageAssetKey == stages.F2.assetKey and f2.location == stages.F2.label)
	assert(d1.stageAssetKey == stages.D1.assetKey and d1.location == stages.D1.label)
	assert(f1.stageTag == stages.F1.tag and f2.stageTag == stages.F2.tag and d1.stageTag == stages.D1.tag)
end

local expectedSets = { "Ice Demon", "Ultimate Lifeform", "Crusader's World", "Quiet Life", "Crimson Emperor" }
local countSets = 0
for id, set in Campaign.BossSets do
	countSets += 1
	assert(set.id == id and set.label == expectedSets[set.storyPart])
	assert(#set.pieces == 2 and set.pieces[1].slot == "Head" and set.pieces[2].slot == "Body")
	for _, piece in set.pieces do checkAsset(piece.iconKey); assert(table.isfrozen(piece)) end
	assert(table.isfrozen(set) and table.isfrozen(set.fullSet) and table.isfrozen(set.onePieceAmountByAct))
	assert(#set.onePieceAmountByAct == 5 and #set.authoredOnePieceAmountByAct == 5)
	for act, amount in set.onePieceAmountByAct do
		assert(amount > 0 and amount * set.pointsPerUnit <= act + 1e-9)
		assert(amount <= set.authoredOnePieceAmountByAct[act])
	end
	local effect = set.fullSet
	if effect.kind == "IceDemon" then
		assert(effect.trigger == "FirstLandedNaturalPrimary" and effect.slowSpeedPct == -20 and effect.slowTurns == 2)
		assert(effect.maxSlowProcsPerFight == 1 and effect.maxBloodHealsPerNaturalTurn == 1)
		assert(effect.bloodHealDiscount == 3 and effect.minBloodHealCost == 7 and effect.healGateAboveBlood == 25)
		assert(#effect.eligibleBloodRaces == 4 and table.isfrozen(effect.eligibleBloodRaces))
	elseif effect.kind == "UltimateLifeform" then
		assert(effect.resolve == 10 and effect.resolve <= Economy.GlobalCaps.ResolvePerTurnCap and effect.defPenPp == 10)
		assert(effect.maxProcsPerRound == 1 and effect.requiresUnboundHamonOrPillarMan and effect.nextPrimaryOnly)
		assert(effect.expiresEndOfNextTurn and not effect.stacks)
	elseif effect.kind == "CrusadersWorld" then
		assert(effect.stamina == 1 and effect.positiveCostStandDiscount == 1 and effect.maxProcsPerOnFire == 1)
	elseif effect.kind == "QuietLife" then
		assert(effect.trigger == "StateChangingSecondary" and effect.critPp == 6 and effect.precisionPp == 6 and effect.sameTurnOnly)
	else
		assert(effect.bleedTurns == 2 and effect.bleedHpPct == 4 and effect.bossTickCap == 25)
		assert(effect.resolve == 5 and effect.resolve <= Economy.GlobalCaps.ResolvePerTurnCap and effect.maxProcsPerAction == 1)
		assert(effect.sharedBleedPerTarget and effect.ticksAtTargetTurnEnd and not effect.canProcFromBleed)
	end
end
assert(countSets == 5 and Campaign.BossSetDropProtection.firstPieceClear == 1 and Campaign.BossSetDropProtection.missingPieceClear == 2)
local crimson = Campaign.BossSets.crimson_emperor
for act, amount in { 1, 1, 2, 3, 3 } do assert(crimson.authoredOnePieceAmountByAct[act] == amount) end
assert(math.abs(crimson.onePieceAmountByAct[1] - 2 / 3) < 1e-9 and math.abs(crimson.onePieceAmountByAct[4] - 8 / 3) < 1e-9)

assert(#Build.RaceOrder == 9 and #Build.TechniqueOrder == 5 and table.isfrozen(Build.Compatibility))
for _, id in Build.RaceOrder do
	local race, row = Build.Races[id], Build.Compatibility[id]
	assert(table.isfrozen(race) and table.isfrozen(row) and row.Boxing and row.PassioneHitman)
	for _, technique in Build.TechniqueOrder do assert(type(row[technique]) == "boolean" and Build.Techniques[technique] ~= "") end
	assert(row.FullBorg == (id == "Cyborg"))
	assert(row.StandMastery == race.standCompatible and race.standCompatible == (id ~= "Alien"))
	assert(row.Hamon == (id ~= "Undead" and id ~= "Vampire" and id ~= "PillarMan"))
end
local seenEvolutions: { [string]: boolean } = {}
for _, entry in Build.Evolutions do
	assert(not seenEvolutions[entry.id] and not entry.autoTrigger and entry.requiresConfirmation and entry.trigger == "HubEvolutionEncounter")
	seenEvolutions[entry.id] = true
	assert(table.isfrozen(entry) and table.isfrozen(entry.criteria))
	if entry.kind == "Race" then assert(entry.criteria.fromRace ~= nil)
	elseif entry.kind == "Technique" then assert(entry.criteria.fromTechnique ~= nil)
	else assert(entry.criteria.fromStand and Build.StandsById[entry.criteria.fromStand] and Build.StandsById[entry.resultId]) end
	if entry.id == "human_to_superhuman" then
		assert(entry.criteria.fromRace == "Human" and entry.criteria.minHumanStyleMarks == 5 and entry.criteria.maxImplants == 2)
	elseif entry.id == "human_to_cyborg" then
		assert(entry.criteria.fromRace == "Human" and entry.criteria.clinicUnlocked and entry.criteria.minActTier == 2)
		assert(entry.criteria.minImplantedSites == 2 and entry.criteria.minUsedTolerance == 30)
	end
end
assert(seenEvolutions.human_to_superhuman and seenEvolutions.human_to_cyborg)

local gradeOrder: { Build.StandGrade } = { "E", "D", "C", "B", "A", "A+", "∞" }
local power, axis, potential = { 0, 1, 2, 4, 6, 8, 8 }, { 0, 1, 2, 3, 4, 5, 5 }, { 0, 0, 1, 1, 2, 2, 2 }
assert(Build.StandGradeScope == "StandActionsOnly")
for i, id in gradeOrder do
	local grade = Build.StandGrades[id]
	assert(table.isfrozen(grade) and grade.powerPct == power[i] and grade.speedTieBreak == axis[i])
	assert(grade.precisionPp == axis[i] and grade.durabilityGuardPp == axis[i] and grade.potentialResolvePerNaturalTurn == potential[i])
	assert(grade.maxAuthoredBehaviorsPerAxis == (if id == "∞" then 1 else 0))
end
local expectedArrow = {
	"silver_chariot", "hierophant_green", "magicians_red", "hermit_purple", "the_fool", "anubis",
	"crazy_diamond", "the_hand", "heavens_door", "red_hot_chili_pepper", "echoes",
	"gold_experience", "sticky_fingers", "six_pistols", "aerosmith", "purple_haze", "spice_girl",
}
local expectedDiscs = { "star_platinum", "the_world", "cream", "justice", "horus", "killer_queen", "enigma", "king_crimson", "metallica" }
assert(#Build.Stands == 45 and table.isfrozen(Build.Stands) and table.isfrozen(Build.StandsById))
local seenStands: { [string]: boolean } = {}
local partCounts = { [3] = 0, [4] = 0, [5] = 0 }
for _, stand in Build.Stands do
	assert(not seenStands[stand.id] and Build.StandsById[stand.id] == stand and partCounts[stand.storyPart] ~= nil)
	seenStands[stand.id] = true
	partCounts[stand.storyPart] += 1
	assert(stand.arrowCore == (table.find(expectedArrow, stand.id) ~= nil))
	assert(stand.bossDisc == (table.find(expectedDiscs, stand.id) ~= nil))
	assert(table.isfrozen(stand) and table.isfrozen(stand.grades))
	for _, mark in { stand.grades.Power, stand.grades.Speed, stand.grades.Precision, stand.grades.Durability, stand.grades.Potential } do
		assert(Build.StandGrades[mark] ~= nil)
	end
	checkAsset(stand.sheetKey)
end
assert(partCounts[3] == 16 and partCounts[4] == 11 and partCounts[5] == 18)
for _, id in expectedArrow do assert(seenStands[id]) end
for _, id in expectedDiscs do assert(seenStands[id]) end
assert(Build.StandsById.star_platinum.grades.Power == "A+" and Build.StandsById.gold_experience_requiem.grades.Power == "∞")

print("Phase 5 catalogs passed: 5 Parts, 85 encounter entries, both routes, 5 Boss Sets, opt-in evolutions, and 45 Stand records")
