--!strict

local Appearance = require("../src/shared/Contracts/CharacterAppearanceTypes")
local Assets = require("../src/shared/Contracts/AssetManifest")
local Combat = require("../src/shared/Contracts/CombatTypes")
local Hub = require("../src/shared/Contracts/HubTypes")
local Map = require("../src/shared/Contracts/MapTypes")
local Remote = require("../src/shared/Contracts/RemoteContract")
local Session = require("../src/shared/Core/CampaignSession")

local rows: { [number]: { [string]: unknown } } = {}
local now = 100
local id = 0
local failWrite = false
local loseResponse = false
local roll = 0.5
local store: Session.Store = {
	load = function(userId) return rows[userId], true end,
	update = function(userId, transform)
		if failWrite then return nil, false end
		local updated = transform(rows[userId])
		if updated then rows[userId] = updated end
		if loseResponse then
			loseResponse = false
			return nil, false
		end
		return updated, true
	end,
}

local function session()
	return Session.new(store, function() return now end, function()
		id += 1
		return "session-" .. tostring(id)
	end, nil, function() return roll end)
end

local function accepted(result: Remote.CampaignResponse): Hub.CampaignSnapshot
	assert(result.ok, if result.ok then "" else result.message)
	return result.snapshot
end

local function denied(result: Remote.CampaignResponse, code: Remote.CampaignErrorCode)
	assert(not result.ok and result.code == code, "Expected " .. code)
end

local first = session()
local rival = session()
local creator = accepted(first.get(1))
assert(creator.scene.kind == "Creator")
local hairColors = assert(creator.scene.catalog.hairColors)
assert(#hairColors == 8 and hairColors[1].hex == "#242633")
for _, skin in creator.scene.catalog.skinTones do
	assert(skin.bodySpriteKey and Assets[skin.bodySpriteKey])
end
for _, hair in creator.scene.catalog.hairStyles do
	if hair.id == "bald" then
		assert(hair.overlaySpriteKey == nil)
	else
		assert(hair.overlaySpriteKey and Assets[hair.overlaySpriteKey])
	end
	assert(hair.accentSpriteKey == (if hair.id == "cap" then "HairCapTrim" else nil))
end
denied(rival.get(1), "ProfileLocked")
local invalidLook: Appearance.Appearance = { skinToneId = "Deep", hairStyleId = "bald", hairColorHex = "#112233" }
denied(first.submit(1, {
	kind = "CommitAppearance", sessionId = creator.sessionId, expectedRevision = creator.revision,
	appearance = invalidLook,
}), "IllegalAction")
local deepBald: Appearance.Appearance = { skinToneId = "Deep", hairStyleId = "bald" }
local look: Remote.CampaignActionRequest = {
	kind = "CommitAppearance", appearance = deepBald,
	sessionId = creator.sessionId, expectedRevision = creator.revision,
}
local tutorial = accepted(first.submit(1, look))
assert(tutorial.scene.kind == "Tutorial" and tutorial.character.appearance and tutorial.character.appearance.skinToneId == "Deep")
assert(tutorial.character.appearance.hairColorHex == "#242633")
local baldSprites = assert(tutorial.character.appearanceSprites)
assert(baldSprites.bodySpriteKey == "PlayerBodyDeep")
assert(baldSprites.overlaySpriteKey == nil and baldSprites.accentSpriteKey == nil)
denied(first.submit(1, look), "StaleRevision")

-- Simulate the existing tutorial routes writing the root profile.
rows[1].tutorialCompleted = true
assert(accepted(first.get(1)).scene.kind == "OriginSelect")
rows[1].origin = "Part1_Hamon"
local hub = accepted(first.get(1))
assert(hub.scene.kind == "Hub" and hub.character.origin == "Part1_Hamon")
assert(hub.scene.hub.shopOffers[1].item.iconKey == "BrimmedCapIcon")
assert(hub.scene.inventory.entries[1].item.iconKey == "TrainingWrapsIcon")

local purchase: Remote.CampaignActionRequest = {
	kind = "PurchaseOffer", offerId = "tonio-water", quantity = 2,
	sessionId = hub.sessionId, expectedRevision = hub.revision,
}
failWrite = true
denied(first.submit(1, purchase), "SaveUnavailable")
assert(accepted(first.get(1)).character.yen == hub.character.yen)
failWrite = false
loseResponse = true
denied(first.submit(1, purchase), "SaveUnavailable")
denied(first.submit(1, purchase), "StaleRevision")
local stocked = accepted(first.get(1))
assert(stocked.character.yen == hub.character.yen - 20)
assert(stocked.scene.kind == "Hub")
local waterCount = 0
for _, entry in stocked.scene.inventory.entries do
	if entry.kind == "Stack" and entry.beltItemId == "MineralWater" then waterCount = entry.quantity end
end
assert(waterCount == 4)

local geared = accepted(first.submit(1, {
	kind = "SetGearSlot", sessionId = stocked.sessionId, expectedRevision = stocked.revision,
	slot = "Weapon", entryId = "training-wraps",
}))
local belted = accepted(first.submit(1, {
	kind = "SetBeltSlot", sessionId = geared.sessionId, expectedRevision = geared.revision,
	index = 1, entryId = "tonio-water",
}))
denied(first.submit(1, {
	kind = "SetBeltSlot", sessionId = belted.sessionId, expectedRevision = belted.revision,
	index = 2, entryId = "tonio-water",
}), "IllegalAction")

local map = accepted(first.submit(1, {
	kind = "Navigate", sessionId = belted.sessionId, expectedRevision = belted.revision, destination = "ActMap",
}))
assert(map.scene.kind == "ActMap" and map.scene.map.nodes[2].state == "Locked")
assert(map.scene.map.act == 1 and map.scene.map.part == 1)
local hamonNodes = map.scene.map.nodes
assert(hamonNodes[1].stageAssetKey == "OgreStreetStage" and hamonNodes[1].stageTag == "Neutral")
assert(hamonNodes[2].stageAssetKey == "NightAlleyStage" and hamonNodes[2].stageTag == "Night")
assert(hamonNodes[3].stageAssetKey == "OgreHideoutStage")
denied(first.submit(1, {
	kind = "StartNode", sessionId = map.sessionId, expectedRevision = map.revision, nodeId = "F2", playOptionId = "F2:first",
}), "NodeLocked")
denied(first.submit(1, {
	kind = "SetBeltSlot", sessionId = map.sessionId, expectedRevision = map.revision, index = 1, entryId = nil,
}), "IllegalAction")

now += 100
first.renew(1)
now += 90
denied(rival.get(1), "ProfileLocked")
first.close(1)
local restored = accepted(rival.get(1))
assert(restored.sessionId ~= creator.sessionId and restored.scene.kind == "Hub")
assert(restored.character.appearance and restored.character.appearance.skinToneId == "Deep")
assert(restored.character.origin == "Part1_Hamon" and restored.character.yen == stocked.character.yen)
assert(restored.scene.inventory.gear[1].entryId == "training-wraps")
assert(restored.scene.inventory.belt[1].entryId == "tonio-water")

rows[2] = { version = 1, tutorialCompleted = true, origin = "Part3_Stand" }
local migrating = accepted(first.get(2))
assert(migrating.scene.kind == "Creator" and migrating.character.origin == "Part3_Stand")
local tanCap: Appearance.Appearance = { skinToneId = "Tan", hairStyleId = "cap", hairColorHex = "#f2c94c" }
local migrated = accepted(first.submit(2, {
	kind = "CommitAppearance", appearance = tanCap,
	sessionId = migrating.sessionId, expectedRevision = migrating.revision,
}))
assert(migrated.scene.kind == "Hub" and migrated.character.origin == "Part3_Stand")
local capView = assert(migrated.character.appearance)
local capSprites = assert(migrated.character.appearanceSprites)
assert(capView.hairColorHex == "#F2C94C" and capSprites.bodySpriteKey == "PlayerBodyTan")
assert(capSprites.overlaySpriteKey == "HairCap" and capSprites.accentSpriteKey == "HairCapTrim" and Assets.HairCapTrim)
local savedCap = ((rows[2].campaign :: { appearance: unknown }).appearance :: { [string]: unknown })
assert(savedCap.hairColorHex == "#F2C94C" and savedCap.accentSpriteKey == nil)
local standMap = accepted(first.submit(2, {
	kind = "Navigate", sessionId = migrated.sessionId, expectedRevision = migrated.revision, destination = "ActMap",
}))
assert(standMap.scene.kind == "ActMap" and standMap.scene.map.act == 1 and standMap.scene.map.part == 3)
local standNodes = standMap.scene.map.nodes
assert(standNodes[1].id == "F1" and standNodes[1].stageAssetKey == "TokyoJailStage")
assert(standNodes[2].prerequisites[1] == "F1" and standNodes[2].stageAssetKey == "TokyoSchoolyardStage")
assert(standNodes[3].prerequisites[1] == "F2" and standNodes[3].stageAssetKey == "TigerBalmGardenStage")
assert(standNodes[1].playOptions[1].legality.canUse)

now += 181
local recovered = accepted(rival.get(2))
assert(recovered.scene.kind == "Hub")
local recoveredLook = assert(recovered.character.appearance)
local recoveredSprites = assert(recovered.character.appearanceSprites)
assert(recoveredLook.hairColorHex == "#F2C94C" and recoveredSprites.accentSpriteKey == "HairCapTrim")
local changed = first.submit(2, {
	kind = "PurchaseOffer", offerId = "tonio-water", quantity = 1,
	sessionId = migrated.sessionId, expectedRevision = migrated.revision,
})
denied(changed, "ProfileLocked")
assert(accepted(rival.get(2)).character.yen == migrated.character.yen)

rows[3] = {
	version = 1, tutorialCompleted = true, origin = "Part1_Hamon",
	campaign = {
		version = 1, yen = 60, stock = {}, gear = {}, belt = {},
		appearance = { skinToneId = "Fair", hairStyleId = "spiky" },
	},
}
local legacy = accepted(first.get(3))
assert(legacy.scene.kind == "Hub")
local legacyLook = assert(legacy.character.appearance)
local legacySprites = assert(legacy.character.appearanceSprites)
assert(legacyLook.hairColorHex == "#242633" and legacySprites.bodySpriteKey == "PlayerBodyFair")
assert(legacySprites.overlaySpriteKey == "HairSpiky" and legacySprites.accentSpriteKey == nil)

local function startF1(controller: typeof(first), userId: number, current: Hub.CampaignSnapshot, option: string): Remote.CampaignResponse
	return controller.submit(userId, {
		kind = "StartNode", sessionId = current.sessionId, expectedRevision = current.revision, nodeId = "F1", playOptionId = option,
	})
end

local function navigate(controller: typeof(first), userId: number, current: Hub.CampaignSnapshot, destination: "ActMap" | "Hub"): Hub.CampaignSnapshot
	return accepted(controller.submit(userId, {
		kind = "Navigate", sessionId = current.sessionId, expectedRevision = current.revision, destination = destination,
	}))
end

local function battleAccepted(reply: Remote.ActBattleResponse)
	assert(reply.ok, if reply.ok then "" else reply.message)
	return reply.snapshot, reply.campaignSnapshot
end

local function attack(controller: typeof(first), userId: number, current: Map.ActBattleSnapshot, move: "BasicStrike" | "HeavyStrike" | "Defend")
	return battleAccepted(controller.battle(userId, { kind = "Primary", request = {
		battleId = current.battleId, expectedRevision = current.revision, actorId = current.playerActorId,
		slot = "Primary", moveId = move, targetId = if move == "Defend" then nil else current.actors[2].id,
	} }))
end

local function finishWithBasics(controller: typeof(first), userId: number, current: Map.ActBattleSnapshot)
	local result: Hub.CampaignSnapshot? = nil
	for _ = 1, 6 do
		current, result = attack(controller, userId, current, "BasicStrike")
		if current.outcome ~= "InProgress" then break end
	end
	assert(current.outcome == "Victory")
	return current, result
end

rival.close(1)
local f1Map = navigate(rival, 1, accepted(rival.get(1)), "ActMap")
loseResponse = true
denied(startF1(rival, 1, f1Map, "F1:first"), "SaveUnavailable")
local encounter = accepted(rival.get(1))
assert(encounter.scene.kind == "ActEncounter")
local idF1 = encounter.scene.encounter.battleId
local unauthorized = first.battle(3, { kind = "Get", request = { battleId = idF1 } })
assert(not unauthorized.ok and unauthorized.code == "BattleNotFound")
local fight = battleAccepted(rival.battle(1, { kind = "Get", request = { battleId = idF1 } }))
assert(fight.stageAssetKey == "OgreStreetStage" and fight.waveIndex == 1 and fight.waveCount == 1)
assert(fight.actors[2].displayName == "Ogre Street Brawler" and fight.companion == nil)
assert(#fight.belt.items == 1 and fight.belt.items[1].itemId == "MineralWater" and fight.belt.items[1].stock == 4)

fight = attack(rival, 1, fight, "HeavyStrike")
assert(fight.qtePrompt and fight.qtePrompt.mode == "Manual" and fight.qtePrompt.checkResults[1] == "Pending")
local deadlineId, closesAt = rival.nextCheck(1)
assert(deadlineId == idF1 and closesAt)
now = closesAt + 0.01
fight = battleAccepted(assert(rival.expireChecks(1, idF1)))
assert(fight.turn == 2 and fight.qtePrompt == nil and fight.enemyIntents[1].stage == "Windup")
local water: Remote.SandboxSecondaryRequest = {
	battleId = idF1, expectedRevision = fight.revision, kind = "UseBeltItem",
	actorId = fight.playerActorId, targetId = fight.playerActorId, itemId = "MineralWater" :: Combat.BeltItemId,
}
fight = battleAccepted(rival.battle(1, { kind = "Secondary", request = water }))
assert(fight.belt.items[1].stock == 3 and fight.belt.beltChargesRemaining == 2)

failWrite = true
local terminal, awaitingResults = finishWithBasics(rival, 1, fight)
assert(awaitingResults == nil and terminal.activeActorId == nil)
assert(accepted(rival.get(1)).scene.kind == "ActEncounter")
failWrite = false
now += 3
loseResponse = true
assert(accepted(rival.get(1)).scene.kind == "ActEncounter")
local savedVictory = accepted(rival.get(1))
assert(savedVictory.scene.kind == "ActResults" and savedVictory.scene.result.outcome == "Clear")
assert(savedVictory.scene.result.rewards.levels == 1 and savedVictory.character.level == 2)
assert(savedVictory.character.yen == f1Map.character.yen + 12)
local repeated, receipt = battleAccepted(rival.battle(1, { kind = "Primary", request = {
	battleId = idF1, expectedRevision = 1, actorId = fight.playerActorId, slot = "Primary", moveId = "BasicStrike", targetId = fight.actors[2].id,
} }))
assert(repeated.revision == terminal.revision and receipt and receipt.revision == savedVictory.revision)
assert(accepted(rival.get(1)).character.yen == savedVictory.character.yen)
rival.close(1)

local rejoined = accepted(first.get(1))
assert(rejoined.scene.kind == "ActResults" and rejoined.scene.result.encounterId == savedVictory.scene.result.encounterId)
local postFightHub = navigate(first, 1, rejoined, "Hub")
assert(postFightHub.scene.kind == "Hub")
for _, entry in postFightHub.scene.inventory.entries do
	if entry.kind == "Stack" and entry.beltItemId == "MineralWater" then assert(entry.quantity == 3) end
end
local replayMap = navigate(first, 1, postFightHub, "ActMap")
assert(replayMap.scene.kind == "ActMap" and replayMap.scene.map.nodes[1].state == "Cleared")
assert(replayMap.scene.map.nodes[1].playOptions[1].levelsOnClear == 0)
local replayEncounter = accepted(startF1(first, 1, replayMap, "F1:replay"))
assert(replayEncounter.scene.kind == "ActEncounter")
local replayBattle = battleAccepted(first.battle(1, { kind = "Get", request = { battleId = replayEncounter.scene.encounter.battleId } }))
local _, replayReceipt = finishWithBasics(first, 1, replayBattle)
assert(replayReceipt and replayReceipt.scene.kind == "ActResults" and replayReceipt.scene.result.rewards.levels == 0)
assert(replayReceipt.character.level == 2 and replayReceipt.character.yen == savedVictory.character.yen + 6)

local tokyoMap = navigate(rival, 2, accepted(rival.get(2)), "ActMap")
local tokyo = accepted(startF1(rival, 2, tokyoMap, "F1:first"))
assert(tokyo.scene.kind == "ActEncounter")
local tokyoBattle = battleAccepted(rival.battle(2, { kind = "Get", request = { battleId = tokyo.scene.encounter.battleId } }))
assert(tokyoBattle.stageAssetKey == "TokyoJailStage" and tokyoBattle.actors[2].displayName == "Stand-Awakened Jail Thug")
local function retreat(current: typeof(tokyoBattle))
	return battleAccepted(rival.battle(2, { kind = "Secondary", request = {
		kind = "Retreat", battleId = current.battleId, expectedRevision = current.revision, actorId = current.playerActorId,
	} }))
end
roll = 0.99
tokyoBattle = retreat(tokyoBattle)
assert(tokyoBattle.outcome == "InProgress" and not tokyoBattle.retreatLegality.canUse)
tokyoBattle = attack(rival, 2, tokyoBattle, "Defend")
roll = 0.5
local escape, escapeReceipt = retreat(tokyoBattle)
assert(escape.outcome == "Retreated" and escapeReceipt and escapeReceipt.scene.kind == "ActResults")
assert(escapeReceipt.scene.result.outcome == "Retreat" and escapeReceipt.scene.result.rewards.yen == 0)
local nextTokyo = navigate(rival, 2, escapeReceipt, "ActMap")
assert(accepted(startF1(rival, 2, nextTokyo, "F1:first")).scene.kind == "ActEncounter")
rival.close(2)
local interrupted = accepted(first.get(2))
assert(interrupted.scene.kind == "ActMap" and interrupted.scene.map.nodes[1].state == "Available")
local restarted = accepted(startF1(first, 2, interrupted, "F1:first"))
assert(restarted.scene.kind == "ActEncounter")
local doomed = battleAccepted(first.battle(2, { kind = "Get", request = { battleId = restarted.scene.encounter.battleId } }))
local loss: Hub.CampaignSnapshot? = nil
for _ = 1, 30 do
	doomed, loss = attack(first, 2, doomed, "Defend")
	if doomed.outcome ~= "InProgress" then break end
end
assert(doomed.outcome == "Defeat" and loss and loss.scene.kind == "ActResults")
assert(loss.scene.result.outcome == "Defeat" and loss.scene.result.rewards.yen == 0 and loss.character.level == 1)

print("Campaign server passed: migration, loadout, F1 for both Origins, ring timeout, defeat, retreat, save retry, and replay")
