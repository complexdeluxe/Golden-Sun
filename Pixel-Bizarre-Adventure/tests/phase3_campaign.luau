--!strict

local Appearance = require("../src/shared/Contracts/CharacterAppearanceTypes")
local Assets = require("../src/shared/Contracts/AssetManifest")
local Hub = require("../src/shared/Contracts/HubTypes")
local Remote = require("../src/shared/Contracts/RemoteContract")
local Session = require("../src/shared/Core/CampaignSession")

local rows: { [number]: { [string]: unknown } } = {}
local now = 100
local id = 0
local failWrite = false
local loseResponse = false
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
	end)
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
	kind = "StartNode", sessionId = map.sessionId, expectedRevision = map.revision, nodeId = "F1", playOptionId = "F1:first",
}), "NotReady")
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
assert(standNodes[1].playOptions[1].legality.canUse == false)

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

print("Campaign server passed: profile routing, migration, asset bindings, both Act 1 maps, shop, loadout, and session locking")
