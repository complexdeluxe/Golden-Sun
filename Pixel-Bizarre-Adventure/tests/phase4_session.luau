--!strict

local Contract = require("../src/shared/Contracts/Phase4EconomyTypes")
local Item = require("../src/shared/Contracts/ItemInstanceTypes")
local Profile = require("../src/shared/Core/Phase4Profile")
local Parlor = require("../src/shared/Core/Phase4Parlor")
local Session = require("../src/shared/Core/Phase4Session")
local CampaignSession = require("../src/shared/Core/CampaignSession")

local USER = 17
local GEAR = "177cffb8-7ec1-43fc-9f3f-f094e103be46"
local rows: { [number]: { [string]: unknown } } = {}
local now, ids, draws, rollValue = 100, 0, 0, 0.99
local loseReply, failWrite, retryTransform = false, false, false
local catalogFailsOnRare = false
local cachedLoad: { [string]: unknown }? = nil
local store: Session.Store = {
	load = function(userId) return cachedLoad or rows[userId], true end,
	update = function(userId, transform)
		if failWrite then return nil, false end
		local before = rows[userId]
		if retryTransform then
			retryTransform = false
			assert(transform(before))
		end
		local updated = transform(before)
		if updated then rows[userId] = updated end
		if loseReply then loseReply = false; return nil, false end
		return updated, true
	end,
}

local function prize(bucket: Contract.ParlorBucketId, act: number): Parlor.Grant?
	if bucket == "CommonCosmetic" or bucket == "RareCosmetic" or bucket == "EpicCosmetic" or bucket == "LegendaryCosmetic" then
		return { kind = "Cosmetic", cosmeticId = "parlor-" .. bucket }
	elseif bucket == "EpicBaseGearCrate" then
		return { kind = "Gear", familyId = "training-wraps", slot = "Weapon", baseStats = { { statId = "Physical", value = act * 2 } } }
	elseif bucket == "RareSupplyCrate" and catalogFailsOnRare then
		return nil
	end
	return {
		kind = "Supplies", items = { { itemId = "tonio-water", quantity = 1 } },
		resources = { yen = 0, salvageShards = 0, materials = 1, holyWater = 0 },
	}
end

local options: Session.Options = {
	clock = function() return now end,
	makeId = function() ids += 1; return "fixture-id-" .. tostring(ids) end,
	roll = function() draws += 1; return rollValue end,
	prizeFor = prize,
}
local function get(controller: typeof(Session.new(store, options)), userId: number): Contract.Snapshot
	local response = controller.GetPhase4Snapshot(userId)
	assert(response.ok, if not response.ok then response.message else "")
	return response.snapshot
end

local function rejected(response: Contract.ActionResponse, code: Contract.ErrorCode)
	assert(not response.ok and response.code == code, if response.ok then "Accepted " .. code else response.code .. ": " .. response.message)
end

local function request(view: Contract.Snapshot, id: string, action: Contract.Action): Contract.ActionRequest
	return { sessionId = view.sessionId, expectedRevision = view.revision, requestId = id, action = action }
end

local function stored(userId: number): Profile.Saved
	return assert(Profile.decode(rows[userId])).phase4
end

local function gearIn(view: Contract.Snapshot): Contract.SmithItemView
	for _, entry in view.smithItems do
		if entry.item.uuid == GEAR then return entry end
	end
	error("Fixture gear is missing")
end

-- Migration preserves the legacy campaign row and keeps all Phase 4 collections empty.
local campaign = {
	version = 1, yen = 10000, appearance = { skinToneId = "Deep", hairStyleId = "bald" },
	stock = { ["training-wraps"] = 1 }, gear = { Weapon = "training-wraps" }, belt = {},
	actOne = { clears = { F1 = true, F2 = true, D1 = true }, recruited = true },
	futureField = "preserve",
}
rows[USER] = {
	version = 1, tutorialCompleted = true, origin = "Part3_Stand", campaign = campaign,
	campaignWriteRevision = 6, unrelated = "preserve",
}
local first = Session.new(store, options)
loseReply = true
local lostOpen = first.GetPhase4Snapshot(USER)
assert(not lostOpen.ok and lostOpen.code == "SaveUnavailable")
local view = get(first, USER)
assert(view.balances.yen == 10000 and view.balances.salvageShards == 0 and #view.smithItems == 0)
assert(not view.clinic.legality.canUse and view.parlorTiers[1].pityCounter == 0)
assert(rows[USER].campaign == campaign and rows[USER].origin == "Part3_Stand" and rows[USER].unrelated == "preserve")
assert(stored(USER).act == 1 and next(stored(USER).items) == nil)
rejected(first.SubmitPhase4Action(USER, request(view, "clinic-locked", { kind = "InstallCyberware", site = "HeadOptics", tier = 1 })), "IllegalAction")
rejected(first.SubmitPhase4Action(USER, {
	sessionId = view.sessionId, expectedRevision = view.revision, requestId = "bad-count",
	action = { kind = "Spin", tierId = "standard_chip", count = 9 },
}), "InvalidRequest")
local rival = Session.new(store, options)
local locked = rival.GetPhase4Snapshot(USER)
assert(not locked.ok and locked.code == "ProfileLocked")

-- Provision gear, unlocks and non-Yen balances as trusted saved progression.
local item: Item.ItemInstance = {
	uuid = GEAR, familyId = "training-wraps", slot = "Weapon", tier = 3, rarity = "Rare",
	baseStats = { { statId = "Physical", value = 6 } }, rolledLines = { { affixId = "flat_physical", value = 1 } },
	temperLevel = 5, temperPityFailures = 0, cursed = true,
}
local fixture = stored(USER)
fixture.items[GEAR] = item
fixture.act, fixture.race = 3, "FullBorg"
fixture.salvageShards, fixture.materials, fixture.holyWater = 500, 200, 1
view = get(first, USER)
assert(gearIn(view).display.label == "Training Wraps" and gearIn(view).temper.successChancePct == 85)

-- The store retries the transform, then commits the offer but loses the reply.
local smithCall = request(view, "smith-1", { kind = "CreateOffer", itemUuid = GEAR })
retryTransform, loseReply = true, true
local beforeRolls, beforeIds = draws, ids
rejected(first.SubmitPhase4Action(USER, smithCall), "SaveUnavailable")
local pending = assert(stored(USER).items[GEAR].pendingSmithOffer)
assert(draws == beforeRolls + 2 and ids == beforeIds + 1)
assert(stored(USER).salvageShards == 486 and assert(Profile.decode(rows[USER])).campaign.yen == 9880)
local campaignAfter = rows[USER].campaign :: typeof(campaign)
assert(campaignAfter.futureField == "preserve" and campaignAfter.gear.Weapon == "training-wraps" and campaignAfter.actOne.recruited)
local recovered = first.SubmitPhase4Action(USER, smithCall)
assert(recovered.ok and recovered.receipt.kind == "OfferCreated" and recovered.receipt.offer.offerId == pending.offerId)
assert(recovered.snapshot.balances.yen == 9880 and draws == beforeRolls + 2)
recovered.receipt.offer.lines[1].value = 999
assert(pending.lines[1].value ~= 999)
rejected(first.SubmitPhase4Action(USER, request(recovered.snapshot, "smith-1", { kind = "Temper", itemUuid = GEAR })), "RequestConflict")

-- Reconnect after a lease expires, then retry the original request under the new session.
now += 181
local restarted = get(rival, USER)
assert(restarted.sessionId ~= view.sessionId and gearIn(restarted).item.pendingSmithOffer ~= nil)
assert(not gearIn(restarted).reroll.legality.canUse and not gearIn(restarted).dismantleLegality.canUse)
rejected(first.SubmitPhase4Action(USER, smithCall), "ProfileLocked")
local replay = rival.SubmitPhase4Action(USER, request(restarted, "smith-1", smithCall.action))
assert(replay.ok and replay.receipt.kind == "OfferCreated" and replay.receipt.offer.offerId == pending.offerId)
assert(replay.snapshot.balances.yen == 9880 and draws == beforeRolls + 2)
rejected(rival.SubmitPhase4Action(USER, request(restarted, "smith-block", { kind = "CreateOffer", itemUuid = GEAR })), "IllegalAction")
rejected(rival.SubmitPhase4Action(USER, request(restarted, "dismantle-block", { kind = "Dismantle", itemUuid = GEAR })), "IllegalAction")
rejected(rival.SubmitPhase4Action(USER, request(restarted, "wrong-offer", {
	kind = "ResolveOffer", itemUuid = GEAR, offerId = "other", decision = "AcceptNew",
})), "OfferMismatch")

view = restarted
local function act(id: string, action: Contract.Action): Contract.Receipt
	local response = rival.SubmitPhase4Action(USER, request(view, id, action))
	assert(response.ok, if not response.ok then response.code .. ": " .. response.message else "")
	view = response.snapshot
	return response.receipt
end

local resolved = act("accept", { kind = "ResolveOffer", itemUuid = GEAR, offerId = pending.offerId, decision = "AcceptNew" })
assert(resolved.kind == "OfferResolved" and gearIn(view).item.pendingSmithOffer == nil)
assert(gearIn(view).item.rolledLines[1].affixId == pending.lines[1].affixId)
local stale = rival.SubmitPhase4Action(USER, request(restarted, "stale-temper", { kind = "Temper", itemUuid = GEAR }))
rejected(stale, "StaleRevision")
local beforeTemper = view.balances.yen
local failed = act("temper-fail", { kind = "Temper", itemUuid = GEAR })
assert(failed.kind == "Tempered" and not failed.succeeded and failed.level == 5 and failed.pityFailures == 1)
assert(gearIn(view).item.uuid == GEAR and gearIn(view).temper.successChancePct == 100 and view.balances.yen == beforeTemper - 288)
local success = act("temper-pity", { kind = "Temper", itemUuid = GEAR })
assert(success.kind == "Tempered" and success.succeeded and success.level == 6 and success.pityFailures == 0)
local purified = act("purify", { kind = "Purify", itemUuid = GEAR, perkId = "measured_breath" })
assert(purified.kind == "Purified" and not gearIn(view).item.cursed and gearIn(view).item.purifiedPerk == "measured_breath")
assert(view.balances.holyWater == 0)
local dismantled = act("dismantle", { kind = "Dismantle", itemUuid = GEAR })
assert(dismantled.kind == "Dismantled" and dismantled.salvageShards == 9 and #view.smithItems == 0)

assert(view.clinic.sites[1].offers[5].toleranceCost == 42 and view.clinic.sites[1].offers[5].cost.yen == 650)
local implant = act("head", { kind = "InstallCyberware", site = "HeadOptics", tier = 5 })
assert(implant.kind == "CyberwareInstalled" and implant.install.routineId == "UVBeam")
act("neural", { kind = "InstallCyberware", site = "Neural", tier = 5 })
act("torso", { kind = "InstallCyberware", site = "TorsoChassis", tier = 5 })
assert(view.clinic.tolerance.usedTolerance == 126 and not view.clinic.tolerance.cyberStrainActive)
act("limbs", { kind = "InstallCyberware", site = "Limbs", tier = 1 })
assert(view.clinic.tolerance.usedTolerance == 136 and view.clinic.tolerance.cyberStrainActive)
assert(view.clinic.tolerance.controlResistPenaltyPp == 10 and view.clinic.tolerance.extraAgingYears == 1)
rejected(rival.SubmitPhase4Action(USER, request(view, "too-much", { kind = "InstallCyberware", site = "HeartCore", tier = 5 })), "IllegalAction")
rejected(rival.SubmitPhase4Action(USER, request(view, "too-many", {
	kind = "SetEquippedRoutines", routineIds = { "UVBeam", "TacticalSurge", "SuppressiveVolley" },
})), "IllegalAction")
rejected(rival.SubmitPhase4Action(USER, request(view, "duplicate-routine", {
	kind = "SetEquippedRoutines", routineIds = { "UVBeam", "UVBeam" },
})), "IllegalAction")
local equipped = act("equip", { kind = "SetEquippedRoutines", routineIds = { "UVBeam", "TacticalSurge" } })
assert(equipped.kind == "EquippedRoutinesSet" and #view.clinic.equippedRoutines == 2)
local removed = act("remove-head", { kind = "RemoveCyberware", site = "HeadOptics" })
assert(removed.kind == "CyberwareRemoved" and view.clinic.equippedRoutines[1] == "TacticalSurge")
assert(view.clinic.tolerance.usedTolerance == 94 and not view.clinic.tolerance.cyberStrainActive)

-- A single duplicate cosmetic refunds shards. An independent ten-spin batch
-- pays the discounted price and uses pity on its tenth consecutive low roll.
rollValue = 0.55
local single = act("spin-single", { kind = "Spin", tierId = "standard_chip", count = 1 })
assert(single.kind == "Spun" and single.results[1].prize.kind == "Cosmetic" and single.pityCounter == 1)
local beforeDuplicate = view.balances.salvageShards
local duplicate = act("spin-duplicate", { kind = "Spin", tierId = "standard_chip", count = 1 })
assert(duplicate.kind == "Spun")
local refund = duplicate.results[1].prize
assert(refund.kind == "DuplicateCosmetic" and refund.shardRefund == 3 and view.balances.salvageShards == beforeDuplicate + 3)
rollValue = 0
local catchup = act("spin-catchup", { kind = "Spin", tierId = "standard_chip", count = 10 })
assert(catchup.kind == "Spun" and catchup.results[8].usedPity and catchup.pityCounter == 2)
for i = 1, 8 do
	local step = act("pity-reset-" .. tostring(i), { kind = "Spin", tierId = "standard_chip", count = 1 })
	assert(step.kind == "Spun" and step.results[1].usedPity == (i == 8))
end
assert(view.parlorTiers[1].pityCounter == 0)
local beforeBatch = view
local batchCall = request(view, "spin-ten", { kind = "Spin", tierId = "standard_chip", count = 10 })
catalogFailsOnRare = true
local savedSupplies = stored(USER).supplies["tonio-water"]
rejected(rival.SubmitPhase4Action(USER, batchCall), "SaveUnavailable")
assert(stored(USER).supplies["tonio-water"] == savedSupplies and stored(USER).receipts["spin-ten"] == nil)
assert(get(rival, USER).balances.yen == beforeBatch.balances.yen)
catalogFailsOnRare = false
local batch = act("spin-ten", batchCall.action)
assert(batch.kind == "Spun" and batch.spentYen == 900 and #batch.results == 10 and batch.pityCounter == 0)
for i = 1, 9 do assert(batch.results[i].rarity == "Common" and not batch.results[i].usedPity) end
assert(batch.results[10].rarity == "Rare" and batch.results[10].usedPity)
assert(view.balances.yen == beforeBatch.balances.yen - 900 and stored(USER).supplies["tonio-water"] == savedSupplies + 10)
local beforeRetry = draws
local repeated = rival.SubmitPhase4Action(USER, batchCall)
assert(repeated.ok and repeated.receipt.kind == "Spun" and repeated.snapshot.revision == view.revision and draws == beforeRetry)

-- A separate wallet mutation fences an action using the previous campaign revision.
rows[USER].campaignWriteRevision = (rows[USER].campaignWriteRevision :: number) + 1
rejected(rival.SubmitPhase4Action(USER, request(view, "wallet-stale", { kind = "Spin", tierId = "standard_chip", count = 1 })), "StaleRevision")
view = get(rival, USER)
failWrite = true
rejected(rival.SubmitPhase4Action(USER, request(view, "store-down", { kind = "Spin", tierId = "standard_chip", count = 1 })), "SaveUnavailable")
assert(draws == beforeRetry)
failWrite = false
rollValue = 0.8
local crate = act("high-roller-base-gear", { kind = "Spin", tierId = "high_roller_chip", count = 1 })
assert(crate.kind == "Spun" and crate.results[1].bucketId == "EpicBaseGearCrate")
local gearPrize = crate.results[1].prize
assert(gearPrize.kind == "Gear")
local baseGear = stored(USER).items[gearPrize.itemUuid]
assert(baseGear.tier == 3 and baseGear.rarity == "Epic" and #baseGear.rolledLines == 0)
assert(view.parlorTiers[1].pityCounter == 0 and view.parlorTiers[2].pityCounter == 0)
rival.close(USER)
assert(stored(USER).lease == nil)
assert(get(first, USER).balances.yen == view.balances.yen)

-- Campaign -> Phase 4 -> Campaign, including honest stale requests in both
-- directions and a cached read older than the atomic store's current value.
local SHARED = 28
rows[SHARED] = {
	version = 1, tutorialCompleted = true, origin = "Part3_Stand",
	campaign = {
		version = 1, yen = 1000, appearance = campaign.appearance, stock = { ["training-wraps"] = 1 },
		gear = {}, belt = {}, actOne = campaign.actOne, futureField = campaign.futureField,
	},
	tutorialExtra = "keep tutorial metadata",
}
local campaignSession = CampaignSession.new(store, options.clock, options.makeId)
local economySession = Session.new(store, options)
local initialCampaign = campaignSession.get(SHARED)
assert(initialCampaign.ok and initialCampaign.snapshot.scene.kind == "Hub")
local economyBefore = get(economySession, SHARED)
local campaignBefore = initialCampaign.snapshot
assert(economyBefore.sessionId ~= campaignBefore.sessionId and economyBefore.balances.yen == 1000)
local bought = campaignSession.submit(SHARED, {
	kind = "PurchaseOffer", offerId = "tonio-water", quantity = 2,
	sessionId = campaignBefore.sessionId, expectedRevision = campaignBefore.revision,
})
assert(bought.ok and bought.snapshot.character.yen == 980)
rejected(economySession.SubmitPhase4Action(SHARED, request(economyBefore, "shared-spin", {
	kind = "Spin", tierId = "standard_chip", count = 1,
})), "StaleRevision")
local economyRefreshed = get(economySession, SHARED)
assert(economyRefreshed.balances.yen == 980)
local cachedCampaign = rows[SHARED]
rollValue = 0
local spent = economySession.SubmitPhase4Action(SHARED, request(economyRefreshed, "shared-spin", {
	kind = "Spin", tierId = "standard_chip", count = 1,
}))
assert(spent.ok and spent.snapshot.balances.yen == 880)
cachedLoad = cachedCampaign
local staleCampaign = campaignSession.submit(SHARED, {
	kind = "SetBeltSlot", index = 1, entryId = "tonio-water",
	sessionId = bought.snapshot.sessionId, expectedRevision = bought.snapshot.revision,
})
cachedLoad = nil
assert(not staleCampaign.ok and staleCampaign.code == "StaleRevision")
local current = assert(staleCampaign.snapshot)
assert(current.character.yen == 880 and current.sessionId == campaignBefore.sessionId)
local belted = campaignSession.submit(SHARED, {
	kind = "SetBeltSlot", index = 1, entryId = "tonio-water",
	sessionId = current.sessionId, expectedRevision = current.revision,
})
assert(belted.ok and belted.snapshot.scene.kind == "Hub" and belted.snapshot.scene.inventory.belt[1].entryId == "tonio-water")
local purchaseAgain = campaignSession.submit(SHARED, {
	kind = "PurchaseOffer", offerId = "tonio-water", quantity = 1,
	sessionId = belted.snapshot.sessionId, expectedRevision = belted.snapshot.revision,
})
assert(purchaseAgain.ok and purchaseAgain.snapshot.character.yen == 870)
local map = campaignSession.submit(SHARED, {
	kind = "Navigate", destination = "ActMap",
	sessionId = purchaseAgain.snapshot.sessionId, expectedRevision = purchaseAgain.snapshot.revision,
})
assert(map.ok and map.snapshot.scene.kind == "ActMap" and map.snapshot.scene.map.nodes[3].state == "Cleared")
local persisted = assert(Profile.decode(rows[SHARED]))
assert(persisted.campaign.stock["tonio-water"] == 3 and persisted.campaign.belt["1"] == "tonio-water")
assert(persisted.campaign.yen == 870 and persisted.campaign.actOne.recruited and persisted.campaign.appearance ~= nil)
assert(rows[SHARED].tutorialCompleted == true and rows[SHARED].origin == "Part3_Stand")
assert(rows[SHARED].tutorialExtra == "keep tutorial metadata")
assert((rows[SHARED].campaign :: { [string]: unknown }).futureField == "preserve")
assert(persisted.phase4.materials == 1 and persisted.phase4.supplies["tonio-water"] == 1)
assert(persisted.phase4.pity.standard_chip == 1 and persisted.phase4.receipts["shared-spin"].receipt.kind == "Spun")

-- Independent heartbeat renewal and cleanup leave the other lease intact.
local leaseBefore = assert(persisted.phase4.lease)
now += 95
campaignSession.renew(SHARED)
economySession.renew(SHARED)
local renewed = assert(stored(SHARED).lease)
assert(renewed.sessionId == leaseBefore.sessionId and renewed.expiresAt > leaseBefore.expiresAt)
now += 90
assert(get(economySession, SHARED).sessionId == economyBefore.sessionId)
economySession.close(SHARED)
assert(stored(SHARED).lease == nil)
local afterEconomyClose = campaignSession.get(SHARED)
assert(afterEconomyClose.ok and afterEconomyClose.snapshot.sessionId == campaignBefore.sessionId)
local reopened = get(economySession, SHARED)
campaignSession.close(SHARED)
assert(rows[SHARED].campaignLease == nil and assert(stored(SHARED).lease).sessionId == reopened.sessionId)
assert(get(economySession, SHARED).balances.yen == 870)

print("Phase 4 session passed: all nine actions, durable retries, shared Campaign wallet and leases, migration, and atomic Parlor pity")
