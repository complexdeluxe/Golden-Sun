--!strict

local Contract = require("../src/shared/Contracts/ActivityTypes")
local Income = require("../src/shared/Data/Phase4EconomyData").ActIncome
local Activity = require("../src/shared/Core/ActivitySession")
local Campaign = require("../src/shared/Core/CampaignSession")
local Phase4 = require("../src/shared/Core/Phase4Session")
local Succession = require("../src/shared/Core/SuccessionSession")
local Lineage = require("../src/shared/Core/SuccessionProfile")
local Wallet = require("../src/shared/Core/Phase4Profile")

local USER = 42
local rows: { [number]: { [string]: unknown } } = {}
local now, idCounter = 1700000000, 0
local loseReply, retryTransform = false, false
local store: Activity.Store = {
	load = function(userId) return rows[userId], true end,
	update = function(userId, transform)
		local old = rows[userId]
		if retryTransform then
			retryTransform = false
			assert(transform(old))
		end
		local nextRow = transform(old)
		if nextRow then rows[userId] = nextRow end
		if loseReply then loseReply = false; return nil, false end
		return nextRow, true
	end,
}
local function clock(): number return now end
local function makeId(): string
	idCounter += 1
	return "fixture-" .. tostring(idCounter)
end

local tutorial = { retained = true }
rows[USER] = {
	version = 1, tutorialCompleted = true, origin = "Part1_Hamon", tutorial = tutorial,
	campaign = {
		version = 1, yen = 500, stock = {}, gear = {}, belt = {},
		appearance = { skinToneId = "Tan", hairStyleId = "bald" },
		actOne = { clears = { F1 = true, F2 = true, D1 = true }, recruited = false },
		legacyField = "keep",
	},
}
local campaign = Campaign.new(store, clock, makeId)
local options: Activity.Options = { clock = clock, makeId = makeId, isSafeHub = campaign.isSafeHub }
type Controller = typeof(Activity.new(store, options))
local activity = Activity.new(store, options)
local phase4 = Phase4.new(store, {
	clock = clock, makeId = makeId, roll = function() return 0 end,
	prizeFor = function()
		return { kind = "Supplies", items = {}, resources = { yen = 0, holyWater = 0, salvageShards = 1, materials = 1 } }
	end,
})
local succession = Succession.new(store, { clock = clock, makeId = makeId, isSafeHub = campaign.isSafeHub })

local function snapshot(reply: Contract.SnapshotResponse): Contract.Snapshot
	assert(reply.ok, if reply.ok then "" else reply.code .. ": " .. reply.message)
	return reply.snapshot
end
local function get(controller: Controller): Contract.Snapshot
	return snapshot(controller.GetActivitySnapshot(USER))
end
local function request(view: Contract.Snapshot, id: string, action: Contract.Action): Contract.ActionRequest
	return { sessionId = view.sessionId, expectedRevision = view.revision, requestId = id, action = action }
end
local function submit(controller: Controller, view: Contract.Snapshot, id: string, action: Contract.Action): Contract.ActionResponse
	return controller.SubmitActivityAction(USER, request(view, id, action))
end
local function success(reply: Contract.ActionResponse): (Contract.Snapshot, Contract.Receipt)
	assert(reply.ok, if reply.ok then "" else reply.code .. ": " .. reply.message)
	return reply.snapshot, reply.receipt
end
local function denied(reply: Contract.ActionResponse | Contract.SnapshotResponse, code: Contract.ErrorCode)
	assert(not reply.ok and reply.code == code, if reply.ok then "Unexpected success" else reply.code .. ": " .. reply.message)
end
local function balances(yen: number, shards: number, materials: number)
	local profile = assert(Wallet.decode(rows[USER]))
	assert(profile.campaign.yen == yen and profile.phase4.salvageShards == shards and profile.phase4.materials == materials,
		string.format("Unexpected balances %d / %d / %d", profile.campaign.yen, profile.phase4.salvageShards, profile.phase4.materials))
end

local fresh = snapshot(activity.GetActivitySnapshot(99))
assert(fresh.revision == 0 and fresh.expedition.tickets == 0 and rows[99].tutorialCompleted == false)
activity.close(99)

local oldCampaign = rows[USER].campaign
local view = get(activity)
assert(view.revision == 0 and view.expedition.tickets == 0 and view.expedition.maxTickets == 2)
assert(rows[USER].campaign == oldCampaign and rows[USER].phase4 == nil and rows[USER].lineage == nil)
assert(rows[USER].tutorial == tutorial and #view.autoBattle.unlockedActs == 0)
denied(submit(activity, view, "uncleared", { kind = "StartAutoBattle", act = 1 }), "ActNotCleared")
denied(submit(activity, view, "no-ticket", { kind = "DispatchExpedition", act = 1 }), "InsufficientTickets")
denied(submit(activity, view, "invalid-act", { kind = "StartAutoBattle", act = 0 }), "InvalidRequest")
local competitor = Activity.new(store, options)
denied(competitor.GetActivitySnapshot(USER), "ProfileLocked")

local atHub = campaign.get(USER)
assert(atHub.ok and atHub.snapshot.scene.kind == "Hub")
local openedEconomy = phase4.GetPhase4Snapshot(USER)
assert(openedEconomy.ok)
local lineage = succession.GetLineageSnapshot(USER)
assert(lineage.ok)
local lifeId = lineage.snapshot.lifeId
local replay = succession.recordActClear(USER, lifeId, 1, "Replay")
assert(replay.ok and not replay.changed)
denied(submit(activity, view, "replay-locked", { kind = "StartAutoBattle", act = 1 }), "ActNotCleared")
for act = 1, 5 do
	local won = succession.recordActClear(USER, lifeId, act)
	assert(won.ok and won.changed)
end

local bought = campaign.submit(USER, {
	kind = "PurchaseOffer", offerId = "tonio-water", quantity = 2,
	sessionId = atHub.snapshot.sessionId, expectedRevision = atHub.snapshot.revision,
})
assert(bought.ok and bought.snapshot.character.yen == 480)
local economy = phase4.GetPhase4Snapshot(USER)
assert(economy.ok)
local spin = phase4.SubmitPhase4Action(USER, {
	sessionId = economy.snapshot.sessionId, expectedRevision = economy.snapshot.revision, requestId = "spin-1",
	action = { kind = "Spin", tierId = "standard_chip", count = 1 },
})
assert(spin.ok)
balances(380, 1, 1)
local refreshedCampaign = campaign.get(USER)
assert(refreshedCampaign.ok)
local map = campaign.submit(USER, {
	kind = "Navigate", destination = "ActMap",
	sessionId = refreshedCampaign.snapshot.sessionId, expectedRevision = refreshedCampaign.snapshot.revision,
})
assert(map.ok and map.snapshot.scene.kind == "ActMap")
view = get(activity)
assert(#view.autoBattle.unlockedActs == 5 and not view.autoBattle.legality.start.canUse)
denied(submit(activity, view, "from-map", { kind = "StartAutoBattle", act = 2 }), "IllegalAction")
local back = campaign.submit(USER, {
	kind = "Navigate", destination = "Hub", sessionId = map.snapshot.sessionId, expectedRevision = map.snapshot.revision,
})
assert(back.ok)

-- The optional trusted clear hook de-duplicates ticket awards, including when full.
for index = 1, 3 do assert(activity.grantExpeditionTicket(USER, "clear-" .. index)) end
view = get(activity)
assert(view.expedition.tickets == 2 and view.expedition.maxTickets == 2)
local dispatchAt = now
local dispatch: Contract.Action = { kind = "DispatchExpedition", act = 3 }
local dispatchRequest = request(view, "dispatch", dispatch)
retryTransform = true
view, _ = success(activity.SubmitActivityAction(USER, dispatchRequest))
local missionId = assert(view.expedition.missionId)
assert(view.expedition.tickets == 1 and view.expedition.startedAtUtc == dispatchAt)
assert(view.expedition.completesAtUtc == dispatchAt + Contract.ExpeditionDurationSeconds and not view.expedition.claimable)
local _, dispatchReceipt = success(activity.SubmitActivityAction(USER, dispatchRequest))
assert(dispatchReceipt.kind == "ExpeditionDispatched" and dispatchReceipt.missionId == missionId)
assert(activity.grantExpeditionTicket(USER, "clear-3") and get(activity).expedition.tickets == 1)
denied(submit(activity, view, "occupied", dispatch), "ExpeditionSlotOccupied")

local lineageBeforeRetire = succession.GetLineageSnapshot(USER)
assert(lineageBeforeRetire.ok)
local retirement = succession.SubmitLineageAction(USER, {
	sessionId = lineageBeforeRetire.snapshot.sessionId, expectedRevision = lineageBeforeRetire.snapshot.revision,
	requestId = "retire", action = { kind = "PassTheTorch", lifeId = lifeId, confirmed = true },
})
assert(retirement.ok and retirement.snapshot.generation == 2)
local quartermaster = succession.SubmitLineageAction(USER, {
	sessionId = retirement.snapshot.sessionId, expectedRevision = retirement.snapshot.revision, requestId = "quartermaster",
	action = { kind = "PurchaseBloodlineNode", nodeId = "quartermaster_dispatch" },
})
assert(quartermaster.ok)
for index = 4, 6 do assert(activity.grantExpeditionTicket(USER, "clear-" .. index)) end
view = get(activity)
assert(view.expedition.tickets == 3 and view.expedition.maxTickets == 3)
assert(#view.autoBattle.unlockedActs == 5, "new generation retains manually cleared Act unlocks")

local startAt = now
view, _ = success(submit(activity, view, "start", { kind = "StartAutoBattle", act = 2 }))
local runId = assert(view.autoBattle.runId)
assert(view.autoBattle.lastClaimedAtUtc == startAt and view.autoBattle.pendingTicks == 0)
denied(submit(activity, view, "no-tick-yet", { kind = "ClaimAutoBattle", runId = runId }), "NoPendingTicks")
denied(submit(activity, view, "wrong-run", { kind = "StopAutoBattle", runId = "another-run" }), "AutoBattleRunMismatch")
now = startAt + 170
activity.renew(USER)
now = startAt + 299
assert(snapshot(activity.tick(USER)).autoBattle.pendingTicks == 0)
balances(380, 1, 1)
now = startAt + 300
local staleAfterTick = view
loseReply = true
denied(activity.tick(USER), "SaveUnavailable")
view = snapshot(activity.tick(USER))
local quote = Income[2].autoBattle5Min
assert(view.autoBattle.lastClaimedAtUtc == startAt + 300)
assert(assert(view.autoBattle.lastClaim).ticksClaimed == 1 and #assert(view.autoBattle.lastClaim).standardGear == 0)
balances(380 + quote.yen, 1 + quote.shards, 1 + quote.materials)
denied(submit(activity, staleAfterTick, "stale-stop", { kind = "StopAutoBattle", runId = runId }), "StaleRevision")
activity.close(USER)
campaign.close(USER)
phase4.close(USER)
succession.close(USER)
assert(rows[USER].activityLease == nil)
now = startAt + 930
local rejoined = competitor
view = get(rejoined)
assert(view.sessionId ~= staleAfterTick.sessionId and view.autoBattle.runId == runId)
assert(view.autoBattle.pendingTicks == 2 and view.autoBattle.startedAtUtc == startAt)
local claimRequest = request(view, "lost-claim", { kind = "ClaimAutoBattle", runId = runId })
retryTransform, loseReply = true, true
denied(rejoined.SubmitActivityAction(USER, claimRequest), "SaveUnavailable")
local claimReceipt: Contract.Receipt
view, claimReceipt = success(rejoined.SubmitActivityAction(USER, claimRequest))
assert(claimReceipt.kind == "AutoBattleClaimed" and claimReceipt.ticksClaimed == 2)
assert(view.autoBattle.lastClaimedAtUtc == startAt + 900 and view.autoBattle.pendingTicks == 0)
balances(380 + 3 * quote.yen, 1 + 3 * quote.shards, 1 + 3 * quote.materials)
denied(submit(rejoined, view, "lost-claim", { kind = "StopAutoBattle", runId = runId }), "RequestConflict")
now = startAt + 1205
view = get(rejoined)
view, _ = success(submit(rejoined, view, "stop", { kind = "StopAutoBattle", runId = runId }))
assert(view.autoBattle.runId == nil and assert(view.autoBattle.lastClaim).lastClaimedAtUtc == startAt + 1200)
denied(submit(rejoined, view, "after-stop", { kind = "ClaimAutoBattle", runId = runId }), "AutoBattleRunMismatch")
balances(380 + 4 * quote.yen, 1 + 4 * quote.shards, 1 + 4 * quote.materials)

-- A client-supplied clock cannot advance the mission.
now = dispatchAt + Contract.ExpeditionDurationSeconds - 1
local expired = rejoined
rejoined = Activity.new(store, options)
view = get(rejoined)
denied(expired.tick(USER), "ProfileLocked")
assert(view.expedition.missionId == missionId and not view.expedition.claimable)
local premature = request(view, "mission-claim", { kind = "ClaimExpedition", missionId = missionId })
local spoofed = table.clone(premature) :: { [string]: unknown }
spoofed.serverTimeUtc = now + 100000
denied(rejoined.SubmitActivityAction(USER, spoofed), "ExpeditionNotReady")
denied(submit(rejoined, view, "unknown-mission", { kind = "ClaimExpedition", missionId = "other-mission" }), "ExpeditionMissionMismatch")

now += 1
local sharedCampaign = campaign.get(USER)
local sharedPhase4 = phase4.GetPhase4Snapshot(USER)
local sharedLineage = succession.GetLineageSnapshot(USER)
assert(sharedCampaign.ok and sharedPhase4.ok and sharedLineage.ok)
view = get(rejoined)
assert(view.expedition.claimable and view.expedition.legality.claim.canUse)
local rawLineage = rows[USER].lineage
local expeditionClaim = request(view, "mission-claim", { kind = "ClaimExpedition", missionId = missionId })
local missionReceipt: Contract.Receipt
view, missionReceipt = success(rejoined.SubmitActivityAction(USER, expeditionClaim))
local expeditionQuote = Income[3].expedition4Hr
assert(missionReceipt.kind == "ExpeditionClaimed" and missionReceipt.rewards.yen == expeditionQuote.yen)
assert(view.expedition.missionId == nil and view.expedition.tickets == 3)
success(rejoined.SubmitActivityAction(USER, expeditionClaim))
denied(submit(rejoined, view, "second-mission-claim", { kind = "ClaimExpedition", missionId = missionId }), "AlreadyClaimed")
local finalYen = 380 + 4 * quote.yen + expeditionQuote.yen
local finalShards = 1 + 4 * quote.shards + expeditionQuote.shards
local finalMaterials = 1 + 4 * quote.materials + expeditionQuote.materials
balances(finalYen, finalShards, finalMaterials)
assert(rows[USER].lineage == rawLineage and rows[USER].tutorial == tutorial and rows[USER].tutorialCompleted == true)
assert(assert(Lineage.fields(rows[USER].campaign)).legacyField == "keep")

-- Activity changed the real shared wallet. Both existing controllers detect a
-- stale revision, then operate without overwriting the activity or lineage row.
local belt = {
	kind = "SetBeltSlot" :: "SetBeltSlot", index = 1, entryId = "tonio-water",
	sessionId = sharedCampaign.snapshot.sessionId, expectedRevision = sharedCampaign.snapshot.revision,
}
local staleBelt = campaign.submit(USER, belt)
assert(not staleBelt.ok and staleBelt.code == "StaleRevision")
belt.expectedRevision = assert(staleBelt.snapshot).revision
local savedActivity = rows[USER].activity
local belted = campaign.submit(USER, belt)
assert(belted.ok and belted.snapshot.character.yen == finalYen and rows[USER].activity == savedActivity)
local oldEconomyAction = phase4.SubmitPhase4Action(USER, {
	sessionId = sharedPhase4.snapshot.sessionId, expectedRevision = sharedPhase4.snapshot.revision,
	requestId = "stale-economy", action = { kind = "Spin", tierId = "standard_chip", count = 1 },
})
assert(not oldEconomyAction.ok and oldEconomyAction.code == "StaleRevision")
local visibleEconomy = phase4.GetPhase4Snapshot(USER)
assert(visibleEconomy.ok and visibleEconomy.snapshot.balances.materials == finalMaterials)
local visibleLineage = succession.GetLineageSnapshot(USER)
assert(visibleLineage.ok and visibleLineage.snapshot.age.currentAge == sharedLineage.snapshot.age.currentAge)
assert(visibleLineage.snapshot.mastery[1] == nil and rows[USER].lineage == rawLineage)
local aged = succession.advanceAge(USER, visibleLineage.snapshot.lifeId, "manual-progression", 1)
assert(aged.ok and aged.snapshot.age.currentAge == 19)
local anotherSpin = phase4.SubmitPhase4Action(USER, {
	sessionId = visibleEconomy.snapshot.sessionId, expectedRevision = visibleEconomy.snapshot.revision,
	requestId = "spin-after-expedition", action = { kind = "Spin", tierId = "standard_chip", count = 1 },
})
assert(anotherSpin.ok and rows[USER].activity == savedActivity)
balances(finalYen - 100, finalShards + 1, finalMaterials + 1)
assert(get(rejoined).expedition.tickets == 3)
rejoined.close(USER)
assert(rows[USER].activityLease == nil and rows[USER].campaignLease ~= nil and rows[USER].lineageLease ~= nil)

print("Phase 6 activity passed: durable UTC ticks, one-time expeditions, capped tickets, and all four shared sessions")
