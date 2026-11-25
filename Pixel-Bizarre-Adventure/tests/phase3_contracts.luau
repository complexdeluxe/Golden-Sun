--!strict

local Appearance = require("../src/shared/Contracts/CharacterAppearanceTypes")
local Combat = require("../src/shared/Contracts/CombatTypes")
local Hub = require("../src/shared/Contracts/HubTypes")
local Inventory = require("../src/shared/Contracts/InventoryTypes")
local Map = require("../src/shared/Contracts/MapTypes")
local Remote = require("../src/shared/Contracts/RemoteContract")
local Save = require("../src/shared/Contracts/SaveTypes")

local brownBald: Appearance.Appearance = { skinToneId = "Brown", hairStyleId = "bald" }
local create: Remote.CampaignActionRequest = {
	kind = "CommitAppearance", sessionId = "profile-session", expectedRevision = 1,
	appearance = brownBald,
}
assert(create.kind == "CommitAppearance")
local creator: Hub.Scene = {
	kind = "Creator",
	catalog = {
		defaultAppearance = create.appearance,
		skinTones = {
			{ id = "Fair", label = "Fair", swatchHex = "#F6D6AC" },
			{ id = "Tan", label = "Tan", swatchHex = "#D7A075" },
			{ id = "Brown", label = "Brown", swatchHex = "#9C694B" },
			{ id = "Deep", label = "Deep", swatchHex = "#5F3D2E" },
		},
		hairStyles = { { id = "bald", label = "Bald", legality = { canUse = true } } },
	},
}
assert(creator.kind == "Creator" and creator.catalog.defaultAppearance.hairStyleId == "bald")
assert(#Appearance.SkinTones == 4 and #Inventory.GearSlots == 4)

local water: Inventory.ItemDisplay = {
	itemId = "tonio-water", label = "Mineral Water", description = "Restores HP.", iconKey = "MineralWaterIcon",
}
local stock: Inventory.StackEntry = {
	kind = "Stack", entryId = "water-stock", item = water,
	quantity = 2, beltItemId = "MineralWater", beltLegality = { canUse = true },
}
local hub: Hub.Scene = {
	kind = "Hub",
	hub = {
		setOutLegality = { canUse = true },
		shopOffers = {
			{ id = "water-restock", item = water, kind = "BeltSupply", unitPriceYen = 10, maxQuantity = 2, legality = { canUse = true } },
		},
	},
	inventory = {
		entries = { stock },
		gear = { { slot = "Weapon", legality = { canUse = true } } },
		belt = { { index = 1, entryId = stock.entryId, legality = { canUse = true } } },
	},
}
local hubResponse: Remote.CampaignResponse = {
	ok = true,
	snapshot = {
		sessionId = create.sessionId, revision = 4,
		character = { appearance = create.appearance, tutorialCompleted = true, origin = "Part1_Hamon", level = 2, yen = 40 },
		scene = hub, companion = { state = "Locked" },
	},
}
local function beltStock(response: Remote.CampaignResponse): (number?, Combat.BeltItemId?)
	if not response.ok or response.snapshot.scene.kind ~= "Hub" then return nil, nil end
	local inventory = response.snapshot.scene.inventory
	for _, entry in inventory.entries do
		if entry.kind == "Stack" and entry.entryId == inventory.belt[1].entryId then
			return entry.quantity, entry.beltItemId
		end
	end
	return nil, nil
end
local quantity, beltItemId = beltStock(hubResponse)
assert(quantity == 2 and beltItemId == "MineralWater" and stock.item.itemId == "tonio-water")
assert(hubResponse.ok)
assert(hubResponse.snapshot.character.level == 2 and hubResponse.snapshot.character.yen == 40)

local replay: Map.PlayOption = {
	id = "F1:T1:replay", label = "Replay · Tier 1", mode = "Replay", tier = 1, levelsOnClear = 0,
	legality = { canUse = true },
}
local firstClear: Map.PlayOption = {
	id = "F2:T1:first", label = "Set out", mode = "FirstClear", tier = 1, levelsOnClear = 1,
	legality = { canUse = true },
}
local map: Hub.Scene = {
	kind = "ActMap",
	map = {
		act = 1, part = 1,
		nodes = {
			{ id = "F1", label = "Flag 1", prerequisites = {}, state = "Cleared", stageTag = "Neutral", playOptions = { replay } },
			{ id = "F2", label = "Flag 2", prerequisites = { "F1" }, state = "Available", stageTag = "Night", playOptions = { firstClear } },
			{ id = "D1", label = "Dungeon 1", prerequisites = { "F2" }, state = "Locked", stageTag = "Neutral", playOptions = {} },
		},
	},
}
local setOut: Remote.CampaignActionRequest = {
	kind = "StartNode", sessionId = create.sessionId, expectedRevision = 5, nodeId = "F2", playOptionId = firstClear.id,
}
assert(setOut.kind == "StartNode")
assert(map.kind == "ActMap" and map.map.nodes[2].id == setOut.nodeId and map.map.nodes[3].state == "Locked")
assert(Map.NodeOrder[1] == "F1" and Map.NodeOrder[2] == "F2" and Map.NodeOrder[3] == "D1")
assert(replay.levelsOnClear == 0 and firstClear.levelsOnClear == 1)

local result: Hub.Scene = {
	kind = "ActResults",
	result = { encounterId = "act1-d1-clear", nodeId = "D1", mode = "FirstClear", outcome = "Clear", rewards = { yen = 12, levels = 1, items = {} } },
}
local offer: Map.CompanionView = {
	state = "Offered" :: "Offered", offerId = "story-recruit", companionId = "speedwagon", label = "Speedwagon",
	description = "A streetwise ally from Ogre Street.", spriteKey = "CompanionIdle", legality = { canUse = true },
}
assert(offer.state == "Offered")
local recruit: Remote.CampaignActionRequest = {
	kind = "RecruitCompanion", sessionId = create.sessionId, expectedRevision = 8, offerId = offer.offerId,
}
assert(recruit.kind == "RecruitCompanion")
assert(result.kind == "ActResults" and result.result.nodeId == "D1" and offer.offerId == recruit.offerId)
local resultSnapshot: Hub.CampaignSnapshot = {
	sessionId = create.sessionId, revision = 9,
	character = { appearance = create.appearance, tutorialCompleted = true, origin = "Part1_Hamon", level = 3, yen = 52 },
	scene = result,
	companion = {
		state = "Recruited" :: "Recruited", companionId = offer.companionId, label = offer.label,
		description = offer.description, spriteKey = offer.spriteKey,
	},
}
assert(resultSnapshot.character.level == 3 and resultSnapshot.character.yen == 52)
assert(resultSnapshot.companion.state == "Recruited")
assert(resultSnapshot.companion.spriteKey == "CompanionIdle" and resultSnapshot.companion.description == offer.description)
local stale: Remote.CampaignResponse = {
	ok = false, code = "StaleRevision", message = "Campaign state changed.", snapshot = hubResponse.snapshot,
}
assert(stale.snapshot and stale.snapshot.sessionId == create.sessionId)

assert(Save.PROFILE_VERSION == 1 and Remote.FolderName == "TutorialRemotes")
assert(Remote.Sandbox.FolderName == "BlackSabbathRemotes")
assert(Remote.Campaign.FolderName == "CampaignRemotes")
assert(Remote.Campaign.GetCampaignSnapshot.name == "GetCampaignSnapshot" and Remote.Campaign.GetCampaignSnapshot.className == "RemoteFunction")
assert(Remote.Campaign.SubmitCampaignAction.name == "SubmitCampaignAction" and Remote.Campaign.SubmitCampaignAction.className == "RemoteFunction")
assert(Remote.Campaign.CampaignSnapshotChanged.name == "CampaignSnapshotChanged" and Remote.Campaign.CampaignSnapshotChanged.className == "RemoteEvent")

local encounter: Map.ActiveEncounter = {
	encounterId = "act1-d1-clear", battleId = "act1-battle-23",
	nodeId = "D1", mode = "FirstClear", stageTag = "Sunlit",
}
local actBattle: Map.ActBattleSnapshot = {
	battleId = encounter.battleId, encounterId = encounter.encounterId,
	revision = 4, turn = 2, playerActorId = "player", activeActorId = "player",
	actors = {}, turnOrder = {}, enemyIntents = {}, primaryOptions = {}, log = {},
	endTurnLegality = { canUse = false, disabledReason = "Primary available" },
	retreatLegality = { canUse = true },
	belt = { beltChargesRemaining = 2, directHealsRemaining = 1, medKitUsed = false, items = {} },
	qteMode = "Manual", stageTag = encounter.stageTag, waveIndex = 2, waveCount = 3,
	outcome = "InProgress",
}
local resume: Remote.GetActBattleSnapshotRequest = { battleId = encounter.battleId }
local retreat: Remote.ActBattleSecondaryRequest = {
	kind = "Retreat", actorId = actBattle.playerActorId,
	battleId = actBattle.battleId, expectedRevision = actBattle.revision,
}
assert(resume.battleId == actBattle.battleId and retreat.expectedRevision == actBattle.revision)
assert(actBattle.waveIndex < actBattle.waveCount and actBattle.outcome == "InProgress")
actBattle.revision += 1
actBattle.waveIndex = actBattle.waveCount
actBattle.outcome = "Victory"
local settled: Remote.ActBattleResponse = {
	ok = true, snapshot = actBattle, campaignSnapshot = resultSnapshot,
}
assert(settled.ok and settled.snapshot.outcome == "Victory")
assert(settled.campaignSnapshot and settled.campaignSnapshot.scene.kind == "ActResults"
	and settled.campaignSnapshot.scene.result.encounterId == settled.snapshot.encounterId)
assert(Remote.ActBattle.FolderName == "ActBattleRemotes" and Remote.ActBattle.FolderName ~= Remote.Sandbox.FolderName)
assert(Remote.ActBattle.GetActBattleSnapshot.className == "RemoteFunction")
assert(Remote.ActBattle.SubmitActBattlePrimary.className == "RemoteFunction")
assert(Remote.ActBattle.SubmitActBattleSecondary.className == "RemoteFunction")
assert(Remote.ActBattle.SubmitActBattleQteCheck.className == "RemoteFunction")
assert(Remote.ActBattle.SetActBattleQteMode.className == "RemoteFunction")
assert(Remote.ActBattle.ActBattleSnapshotChanged.className == "RemoteEvent")

print("Phase 3 contract smoke passed: creator, hub, loadout, map replay, recruitment, and Act combat")
