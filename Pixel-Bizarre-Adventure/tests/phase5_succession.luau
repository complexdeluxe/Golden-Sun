--!strict

local Assets = require("../src/shared/Contracts/AssetManifest")
local Contract = require("../src/shared/Contracts/SuccessionTypes")
local Campaign = require("../src/shared/Core/CampaignSession")
local Phase4 = require("../src/shared/Core/Phase4Session")
local Profile = require("../src/shared/Core/SuccessionProfile")
local Session = require("../src/shared/Core/SuccessionSession")
local Data = require("../src/shared/Data/BloodlineTreeData")

local rows: { [number]: Profile.Row } = {}
local hub: { [number]: boolean } = {}
local now, ids = 100, 0
local loseReply, retryTransform = false, false
local store: Session.Store = {
	load = function(id) return rows[id], true end,
	update = function(id, transform)
		local old = rows[id]
		if retryTransform then
			retryTransform = false
			assert(transform(old))
		end
		local new = transform(old)
		if new then rows[id] = new end
		if loseReply then loseReply = false; return nil, false end
		return new, true
	end,
}
local function makeId(): string
	ids += 1
	return "lineage-fixture-" .. tostring(ids)
end
local options: Session.Options = {
	clock = function() return now end,
	makeId = makeId,
	isSafeHub = function(userId) return hub[userId] ~= false end,
}
type Controller = typeof(Session.new(store, options))
local first = Session.new(store, options)

local function get(s: Controller, user: number): Contract.Snapshot
	local reply = s.GetLineageSnapshot(user)
	assert(reply.ok, if reply.ok then "" else reply.code .. ": " .. reply.message)
	return reply.snapshot
end
local function hook(reply: Session.HookResponse, changed: boolean?): Contract.Snapshot
	assert(reply.ok, if reply.ok then "" else reply.code .. ": " .. reply.message)
	if changed ~= nil then assert(reply.changed == changed) end
	return reply.snapshot
end
local function denied(reply: Contract.ActionResponse | Session.HookResponse, code: Contract.ErrorCode)
	assert(not reply.ok and reply.code == code, if reply.ok then "Accepted " .. code else reply.code .. ": " .. reply.message)
end
local function request(view: Contract.Snapshot, id: string, action: Contract.Action): Contract.ActionRequest
	return { sessionId = view.sessionId, expectedRevision = view.revision, requestId = id, action = action }
end
local function action(s: Controller, user: number, view: Contract.Snapshot, id: string, mutation: Contract.Action): (Contract.Snapshot, Contract.Receipt)
	local reply = s.SubmitLineageAction(user, request(view, id, mutation))
	assert(reply.ok, if reply.ok then "" else reply.code .. ": " .. reply.message)
	return reply.snapshot, reply.receipt
end
local function saved(user: number): Profile.Saved
	local _, state = Profile.decodeRow(rows[user])
	return assert(state)
end
local function clear(s: Controller, user: number, lifeId: string, act: number, years: number): Contract.Snapshot
	hook(s.recordActClear(user, lifeId, act), true)
	return hook(s.advanceAge(user, lifeId, "age-act-" .. act, years), true)
end
local function wipe(s: Controller, user: number, lifeId: string, id: string, act: number): Session.HookResponse
	return s.recordCastleWipe(user, {
		lifeId = lifeId, eventId = id, act = act, encounterKind = "Castle", mode = "FirstClear", fullPartyWipe = true,
	})
end

local expectedCosts: { [Contract.BloodlineNodeId]: { number } } = {
	family_purse = {20, 35, 55}, early_conditioning = {25, 45, 75}, speedwagon_contacts = {40, 75},
	quartermaster_dispatch = {60}, bloodline_vault = {20, 40, 70}, resonance_attunement = {35, 70},
	tactical_breadth = {85}, dual_heirloom_satchel = {90}, bloodline_longevity = {20, 45, 80},
	veteran_composure = {65}, chrome_resilience = {35, 70},
}
local nodeCount, rankCount, total = 0, 0, 0
for _, branch in Data.BranchOrder do
	for _, id in Data.BranchNodes[branch] do
		nodeCount += 1
		local ranks = Data.Nodes[id].costs
		assert(table.isfrozen(ranks) and #ranks == #expectedCosts[id])
		for i, cost in ranks do
			assert(cost == expectedCosts[id][i])
			total += cost
			rankCount += 1
		end
	end
end
assert(nodeCount == 11 and rankCount == 22 and total == 1155)
local icons = {
	"PocketWatchIcon", "ZeppelisCheckeredHatIcon", "CaesarsHeadbandIcon",
	"JotarosTornCapIcon", "JosukesPeacePinIcon", "BrunosZipperBroochIcon",
}
assert(#Data.Heirlooms == #icons)
for i, heirloom in Data.Heirlooms do
	assert(heirloom.iconKey == icons[i] and Assets[assert(heirloom.iconKey)] and table.isfrozen(heirloom))
end
local challengeCount, challengeTotal = 0, 0
for _, value in Data.EndgameChallengeEchoes do challengeCount += 1; challengeTotal += value end
assert(challengeCount == 5 and challengeTotal == 20)

-- Timeline A. Migration preserves older roots, then Act 3 retirement banks 30.
local A = 11
local oldCampaign = { version = 1, yen = 71, stock = {}, gear = {}, belt = {} }
local oldPhase4 = { version = 1, unrelated = true }
rows[A] = { version = 1, tutorialCompleted = true, origin = "Part3_Stand", campaign = oldCampaign, phase4 = oldPhase4 }
local a = get(first, A)
local lifeA = a.lifeId
assert(a.generation == 1 and a.age.currentAge == 18 and a.recoveryLedger.recoveriesRemaining == 5)
assert(a.heirlooms.unlockedIds[1] == "pocket_watch" and a.heirlooms.carriedIds[1] == "pocket_watch")
assert(a.heirlooms.attunedId == "pocket_watch" and a.heirlooms.carryLimit == 1)
assert(rows[A].campaign == oldCampaign and rows[A].phase4 == oldPhase4 and rows[A].origin == "Part3_Stand")
denied(first.SubmitLineageAction(A, request(a, "too-early", { kind = "PassTheTorch", lifeId = lifeA, confirmed = true })), "IllegalAction")
denied(first.recordActClear(A, lifeA, 3), "IllegalAction")
denied(first.recordEndgameChallenge(A, lifeA, "two_boss_castle_gauntlet", true), "IllegalAction")
local emptyMilestones = saved(A).life.awardedMilestones
a = clear(first, A, lifeA, 1, 9)
assert(a.age.currentAge == 27 and a.recoveryLedger.eligibleEchoes == 8 and next(emptyMilestones) == nil)
local revisionA = a.revision
assert(hook(first.recordActClear(A, lifeA, 1), false).revision == revisionA)
assert(hook(first.recordActClear(A, lifeA, 2, "Replay"), false).revision == revisionA)
assert(hook(first.advanceAge(A, lifeA, "age-act-1", 9), false).age.currentAge == 27)
a = clear(first, A, lifeA, 2, 9)
assert(a.age.currentAge == 36 and a.recoveryLedger.eligibleEchoes == 18)
a = clear(first, A, lifeA, 3, 9)
assert(a.age.currentAge == 45 and a.recoveryLedger.retireNowEchoes == 30 and a.recoveryLedger.recoveriesRemaining == 5)
hub[A] = false
local outside = get(first, A)
assert(not outside.recoveryLedger.canRetireNow)
denied(first.SubmitLineageAction(A, request(outside, "outside", { kind = "PassTheTorch", lifeId = lifeA, confirmed = true })), "IllegalAction")
hub[A] = true
denied(first.SubmitLineageAction(A, request(a, "confirm", { kind = "PassTheTorch", lifeId = lifeA, confirmed = false })), "ConfirmationRequired")
local torch = request(a, "torch-a", { kind = "PassTheTorch", lifeId = lifeA, confirmed = true })
local idsBefore = ids
retryTransform, loseReply = true, true
denied(first.SubmitLineageAction(A, torch), "SaveUnavailable")
assert(ids == idsBefore + 1 and saved(A).echoes == 30 and saved(A).life.generation == 2)
local heirA = saved(A).life.id
assert(saved(A).closedLives[lifeA].ledgerSettled and saved(A).closedLives[lifeA].awardedMilestones["act:3"])
local replay = first.SubmitLineageAction(A, torch)
assert(replay.ok and replay.receipt.kind == "PassedTheTorch" and replay.receipt.echoesAwarded == 30)
assert(replay.receipt.nextLifeId == heirA and replay.snapshot.age.currentAge == 18 and replay.snapshot.recoveryLedger.recoveriesRemaining == 5)
denied(first.SubmitLineageAction(A, request(replay.snapshot, "torch-a", { kind = "PurchaseBloodlineNode", nodeId = "family_purse" })), "RequestConflict")
denied(first.SubmitLineageAction(A, request(replay.snapshot, "other-torch", torch.action)), "AlreadySettled")
denied(first.recordActClear(A, lifeA, 4), "AlreadySettled")
local afterPurchase, purchased = action(first, A, replay.snapshot, "family-a", { kind = "PurchaseBloodlineNode", nodeId = "family_purse" })
assert(purchased.kind == "BloodlineNodePurchased" and purchased.spentEchoes == 20 and purchased.rank == 1)
assert(afterPurchase.bloodlineTree.echoesBalance == 10 and rows[A].campaign == oldCampaign and rows[A].phase4 == oldPhase4)
first.close(A)
local reconnect = Session.new(store, options)
local aRejoined = get(reconnect, A)
local persistedReply = reconnect.SubmitLineageAction(A, request(aRejoined, "torch-a", torch.action))
assert(persistedReply.ok and persistedReply.receipt.kind == "PassedTheTorch" and persistedReply.receipt.echoesAwarded == 30)
assert(persistedReply.snapshot.bloodlineTree.echoesBalance == 10 and persistedReply.snapshot.lifeId == heirA)

-- Timeline B. Three qualifying wipes, Elder at 56, Act 5 at 63, and 112 Echoes.
local B = 22
local b = get(first, B)
local lifeB = b.lifeId
clear(first, B, lifeB, 1, 9)
clear(first, B, lifeB, 2, 9)
assert(hook(wipe(first, B, lifeB, "castle-3", 3), true).recoveryLedger.recoveriesRemaining == 4)
clear(first, B, lifeB, 3, 9)
b = clear(first, B, lifeB, 4, 9)
assert(b.age.currentAge == 54 and not b.age.isElder and b.recoveryLedger.retireNowEchoes == 55 and b.recoveryLedger.terminalFallbackEchoes == 50)
b = hook(first.advanceAge(B, lifeB, "act5-flags", 2), true)
assert(b.age.currentAge == 56 and b.age.elderThreshold == 56 and b.age.isElder and not b.age.veteranComposureActive)
hook(wipe(first, B, lifeB, "castle-5a", 5), true)
b = hook(wipe(first, B, lifeB, "castle-5b", 5), true)
assert(b.recoveryLedger.recoveriesRemaining == 2)
b = clear(first, B, lifeB, 5, 7)
assert(b.age.currentAge == 63 and b.recoveryLedger.act5Vested and b.recoveryLedger.retireNowEchoes == 100)
assert(hook(wipe(first, B, lifeB, "castle-5-post-clear", 5), false).recoveryLedger.recoveriesRemaining == 2)
for _, id in { "two_boss_castle_gauntlet", "marked_modifier_clear", "endgame_challenge_3" } do
	b = hook(first.recordEndgameChallenge(B, lifeB, id, true), true)
end
assert(hook(first.recordEndgameChallenge(B, lifeB, "endgame_challenge_3", true), false).revision == b.revision)
assert(hook(first.recordEndgameChallenge(B, lifeB, "endgame_challenge_4", false), false).revision == b.revision)
assert(b.recoveryLedger.retireNowEchoes == 112 and b.recoveryLedger.terminalFallbackEchoes == 112)
b = action(first, B, b, "torch-b", { kind = "PassTheTorch", lifeId = lifeB, confirmed = true })
assert(b.bloodlineTree.echoesBalance == 112)
local purchases: { Contract.BloodlineNodeId } = { "family_purse", "early_conditioning", "bloodline_longevity", "resonance_attunement" }
for _, nodeId in purchases do b = action(first, B, b, nodeId, { kind = "PurchaseBloodlineNode", nodeId = nodeId }) end
assert(b.bloodlineTree.echoesBalance == 12 and b.age.naturalDeathAge == 80 and b.age.elderThreshold == 56)
assert(saved(B).closedLives[lifeB].act5Vested)

-- Five recoveries absorb five uncleared Castle wipes. Only the sixth settles.
local C = 33
local c = get(first, C)
local lifeC = c.lifeId
clear(first, C, lifeC, 1, 9)
local nonCastleKinds: { "Tutorial" | "Flag" | "Dungeon" } = { "Tutorial", "Flag", "Dungeon" }
for _, kind in nonCastleKinds do
	assert(hook(first.recordCastleWipe(C, {
		lifeId = lifeC, eventId = kind, act = 2, encounterKind = kind, mode = "FirstClear", fullPartyWipe = true,
	}), false).recoveryLedger.recoveriesRemaining == 5)
end
for attempt = 1, 5 do
	c = hook(wipe(first, C, lifeC, "qualifying-" .. attempt, 2), true)
	assert(c.recoveryLedger.recoveriesRemaining == 5 - attempt and c.bloodlineTree.echoesBalance == 0)
	assert(c.recoveryLedger.isFinalAttempt == (attempt == 5) and not c.recoveryLedger.ledgerSettled)
end
assert(hook(wipe(first, C, lifeC, "qualifying-5", 2), false).recoveryLedger.isFinalAttempt)
loseReply = true
denied(wipe(first, C, lifeC, "terminal", 2), "SaveUnavailable")
local terminal = wipe(first, C, lifeC, "terminal", 2)
assert(terminal.ok and not terminal.changed and terminal.snapshot.recoveryLedger.ledgerSettled)
assert(terminal.settlement and terminal.settlement.cause == "CastleWipe" and terminal.settlement.echoesAwarded == 8)
assert(terminal.snapshot.bloodlineTree.echoesBalance == 8)
denied(wipe(first, C, lifeC, "later-wipe", 2), "AlreadySettled")
denied(first.advanceAge(C, lifeC, "later-age", 18), "AlreadySettled")
c = hook(first.beginNextLife(C, lifeC), true)
assert(c.generation == 2 and c.recoveryLedger.recoveriesRemaining == 5 and c.bloodlineTree.echoesBalance == 8)
denied(first.beginNextLife(C, lifeC), "AlreadySettled")

-- Post-clear Castle defeats cannot remove vesting. Old age keeps the same
-- vested Echo award and pays distinct endgame challenges at face value.
local D = 44
local d = get(first, D)
local lifeD = d.lifeId
for act = 1, 5 do d = clear(first, D, lifeD, act, 9) end
for _, id in { "two_boss_castle_gauntlet", "marked_modifier_clear", "endgame_challenge_3" } do
	d = hook(first.recordEndgameChallenge(D, lifeD, id, true), true)
end
assert(hook(first.recordCastleWipe(D, {
	lifeId = lifeD, eventId = "replay-death", act = 5, encounterKind = "Castle", mode = "Replay", fullPartyWipe = true,
}), false).recoveryLedger.act5Vested)
local oldAge = first.advanceAge(D, lifeD, "natural-death", 12)
assert(oldAge.ok and oldAge.settlement and oldAge.settlement.cause == "OldAge" and oldAge.settlement.echoesAwarded == 112)
assert(oldAge.snapshot.age.currentAge == 75 and oldAge.snapshot.recoveryLedger.act5Vested)
assert(hook(first.advanceAge(D, lifeD, "natural-death", 12), false).bloodlineTree.echoesBalance == 112)
d = hook(first.beginNextLife(D, lifeD), true)
local heirD = d.lifeId
d = hook(first.unlockHeirloom(D, heirD, "jotaros_torn_cap"), true)
assert(hook(first.unlockHeirloom(D, heirD, "jotaros_torn_cap"), false).revision == d.revision)
denied(first.unlockHeirloom(D, heirD, "unknown"), "InvalidRequest")
local two: Contract.Action = { kind = "SetCarriedHeirlooms", heirloomIds = { "pocket_watch", "jotaros_torn_cap" } }
denied(first.SubmitLineageAction(D, request(d, "too-many", two)), "IllegalAction")
d = action(first, D, d, "satchel", { kind = "PurchaseBloodlineNode", nodeId = "dual_heirloom_satchel" })
assert(d.heirlooms.carryLimit == 2 and d.bloodlineTree.echoesBalance == 22)
denied(first.SubmitLineageAction(D, request(d, "duplicate-carry", { kind = "SetCarriedHeirlooms", heirloomIds = { "pocket_watch", "pocket_watch" } })), "IllegalAction")
denied(first.SubmitLineageAction(D, request(d, "locked-carry", { kind = "SetCarriedHeirlooms", heirloomIds = { "caesars_headband" } })), "IllegalAction")
denied(first.SubmitLineageAction(D, request(d, "uncarried", { kind = "SetAttunedHeirloom", heirloomId = "jotaros_torn_cap" })), "IllegalAction")
hub[D] = false
denied(first.SubmitLineageAction(D, request(d, "away-carry", two)), "IllegalAction")
denied(first.SubmitLineageAction(D, request(d, "away-attune", { kind = "SetAttunedHeirloom", heirloomId = "pocket_watch" })), "IllegalAction")
hub[D] = true
d = action(first, D, d, "carry-two", two)
d = action(first, D, d, "attune-cap", { kind = "SetAttunedHeirloom", heirloomId = "jotaros_torn_cap" })
assert(#d.heirlooms.carriedIds == 2 and d.heirlooms.attunedId == "jotaros_torn_cap")
d = action(first, D, d, "remove-cap", { kind = "SetCarriedHeirlooms", heirloomIds = { "pocket_watch" } })
assert(d.heirlooms.attunedId == nil)

-- Mastery options are independent. Replays, automations, duplicates and marks
-- over the cap cannot award extra progress.
local kitId = "fixture-kit"
local function mark(id: number, mode: ("FirstClear" | "Replay" | "AutoBattle" | "Expedition")?): Session.HookResponse
	return first.awardMasteryMark(D, { lifeId = heirD, eventId = "mark-" .. id, kitId = kitId, mode = mode or "FirstClear" })
end
hook(mark(0, "Replay"), false)
hook(mark(0, "AutoBattle"), false)
hook(mark(0, "Expedition"), false)
d = hook(mark(1), true)
assert(hook(mark(1), false).mastery[1].marks == 1)
denied(first.SubmitLineageAction(D, request(d, "target-too-early", { kind = "SetMasteryTargetMode", kitId = kitId, targetMode = "Alt" })), "IllegalAction")
d = hook(mark(2), true)
d = action(first, D, d, "alt-target", { kind = "SetMasteryTargetMode", kitId = kitId, targetMode = "Alt" })
assert(d.mastery[1].unlockedAltTarget and d.mastery[1].targetMode == "Alt" and d.mastery[1].utilityVariant == "Default")
denied(first.SubmitLineageAction(D, request(d, "utility-too-early", { kind = "SetMasteryVariant", kitId = kitId, variant = "Alt" })), "IllegalAction")
for i = 3, 5 do d = hook(mark(i), true) end
d = action(first, D, d, "alt-utility", { kind = "SetMasteryVariant", kitId = kitId, variant = "Alt" })
d = action(first, D, d, "default-target", { kind = "SetMasteryTargetMode", kitId = kitId, targetMode = "Default" })
assert(d.mastery[1].targetMode == "Default" and d.mastery[1].utilityVariant == "Alt")
for i = 6, 8 do d = hook(mark(i), true) end
assert(d.mastery[1].masteryTitleUnlocked and hook(mark(9), false).mastery[1].marks == 8)

-- Interleave all three real sessions on one row. A lineage write does not
-- move either wallet revision or change the persisted Campaign/Phase 4 objects.
local SHARED = 55
rows[SHARED] = {
	version = 1, tutorialCompleted = true, origin = "Part1_Hamon",
	campaign = { version = 1, yen = 500, stock = {}, gear = {}, belt = {}, appearance = { skinToneId = "Tan", hairStyleId = "bald" } },
}
local campaign = Campaign.new(store, options.clock, makeId)
local sharedLineage = Session.new(store, {
	clock = options.clock, makeId = makeId, isSafeHub = campaign.isSafeHub,
})
local economy = Phase4.new(store, {
	clock = options.clock, makeId = makeId, roll = function() return 0 end,
	prizeFor = function()
		return { kind = "Supplies", items = {}, resources = { yen = 0, holyWater = 0, salvageShards = 1, materials = 1 } }
	end,
})
local campaignStart = campaign.get(SHARED)
assert(campaignStart.ok and campaignStart.snapshot.scene.kind == "Hub")
local initialEconomy = economy.GetPhase4Snapshot(SHARED)
assert(initialEconomy.ok)
local shared = get(sharedLineage, SHARED)
assert(shared.heirlooms.legality.canUse and campaign.isSafeHub(SHARED))
local sharedLife = shared.lifeId
local bought = campaign.submit(SHARED, {
	kind = "PurchaseOffer", offerId = "tonio-water", quantity = 2,
	sessionId = campaignStart.snapshot.sessionId, expectedRevision = campaignStart.snapshot.revision,
})
assert(bought.ok and bought.snapshot.character.yen == 480)
local readyEconomy = economy.GetPhase4Snapshot(SHARED)
assert(readyEconomy.ok and readyEconomy.snapshot.balances.yen == 480)
local rawCampaign, rawEconomy = rows[SHARED].campaign, rows[SHARED].phase4
shared = clear(sharedLineage, SHARED, sharedLife, 1, 9)
assert(rows[SHARED].campaign == rawCampaign and rows[SHARED].phase4 == rawEconomy)
local spin = economy.SubmitPhase4Action(SHARED, {
	sessionId = readyEconomy.snapshot.sessionId, expectedRevision = readyEconomy.snapshot.revision,
	requestId = "shared-spin", action = { kind = "Spin", tierId = "standard_chip", count = 1 },
})
assert(spin.ok and spin.snapshot.balances.yen == 380)
local staleCampaign = campaign.submit(SHARED, {
	kind = "SetBeltSlot", index = 1, entryId = "tonio-water",
	sessionId = bought.snapshot.sessionId, expectedRevision = bought.snapshot.revision,
})
assert(not staleCampaign.ok and staleCampaign.code == "StaleRevision")
local freshCampaign = assert(staleCampaign.snapshot)
local belted = campaign.submit(SHARED, {
	kind = "SetBeltSlot", index = 1, entryId = "tonio-water",
	sessionId = freshCampaign.sessionId, expectedRevision = freshCampaign.revision,
})
assert(belted.ok and belted.snapshot.scene.kind == "Hub" and belted.snapshot.scene.inventory.belt[1].entryId == "tonio-water")
assert(belted.snapshot.character.yen == 380 and get(sharedLineage, SHARED).revision == shared.revision)
assert(rows[SHARED].tutorialCompleted == true and rows[SHARED].origin == "Part1_Hamon")
local latestEconomy = economy.GetPhase4Snapshot(SHARED)
assert(latestEconomy.ok and latestEconomy.snapshot.balances.salvageShards == 1)
local map = campaign.submit(SHARED, {
	kind = "Navigate", destination = "ActMap",
	sessionId = belted.snapshot.sessionId, expectedRevision = belted.snapshot.revision,
})
assert(map.ok and map.snapshot.scene.kind == "ActMap" and not campaign.isSafeHub(SHARED))
local mapLineage = get(sharedLineage, SHARED)
assert(not mapLineage.heirlooms.legality.canUse)
local clearAttunement: Contract.Action = { kind = "SetAttunedHeirloom" }
denied(sharedLineage.SubmitLineageAction(SHARED, request(mapLineage, "map-attunement", clearAttunement)), "IllegalAction")
local hubReturn = campaign.submit(SHARED, {
	kind = "Navigate", destination = "Hub",
	sessionId = map.snapshot.sessionId, expectedRevision = map.snapshot.revision,
})
assert(hubReturn.ok and campaign.isSafeHub(SHARED))
shared = action(sharedLineage, SHARED, get(sharedLineage, SHARED), "hub-attunement", clearAttunement)
assert(shared.heirlooms.attunedId == nil)
now += 95
sharedLineage.renew(SHARED)
campaign.renew(SHARED)
economy.renew(SHARED)
now += 90
assert(get(sharedLineage, SHARED).sessionId == shared.sessionId)
sharedLineage.close(SHARED)
assert(rows[SHARED].lineageLease == nil and campaign.get(SHARED).ok and economy.GetPhase4Snapshot(SHARED).ok)

print("Phase 5 succession passed: both timelines, single settlement, durable retries, heirlooms, mastery, and shared Store")
