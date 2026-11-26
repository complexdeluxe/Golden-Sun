--!strict

local Activity = require("../src/shared/Contracts/ActivityTypes")
local Combat = require("../src/shared/Contracts/CombatTypes")
local Remote = require("../src/shared/Contracts/RemoteContract")
local Economy = require("../src/shared/Data/Phase4EconomyData")

local allowed: Combat.ActionLegality = { canUse = true }
local locked: Combat.ActionLegality = { canUse = false, disabledReason = "Manually clear an Act first." }
local occupied: Combat.ActionLegality = { canUse = false, disabledReason = "An activity is already running." }

local startedAtUtc = 1700000000
local act = 1
local lastClaimedAtUtc = startedAtUtc + Activity.AutoBattleTickSeconds
local completesAtUtc = startedAtUtc + Activity.ExpeditionDurationSeconds
local autoBattlePreview = Economy.ActIncome[act].autoBattle5Min
local expeditionPreview = Economy.ActIncome[act].expedition4Hr
local craftingBundle: Activity.CraftingBundle = {
	yen = expeditionPreview.yen, salvageShards = expeditionPreview.shards, materials = expeditionPreview.materials,
}
local tickClaim: Activity.AutoBattleClaim = {
	runId = "auto-1", act = act, ticksClaimed = 1, lastClaimedAtUtc = lastClaimedAtUtc,
	rewards = { yen = autoBattlePreview.yen, salvageShards = autoBattlePreview.shards, materials = autoBattlePreview.materials },
	standardGear = {
		{
			entryId = "gear-1", item = { itemId = "worn-gloves", label = "Worn Gloves", description = "Ordinary wearable gear." },
			tier = 1, slot = "Weapon", rarity = "Common",
		},
	},
}

local idle: Activity.Snapshot = {
	sessionId = "activity-session", revision = 1, serverTimeUtc = startedAtUtc,
	autoBattle = {
		unlockedActs = {}, tickSeconds = Activity.AutoBattleTickSeconds, pendingTicks = 0,
		legality = { start = locked, claim = locked, stop = locked },
	},
	expedition = {
		tickets = 2, maxTickets = Activity.BaseExpeditionMaxTickets, durationSeconds = Activity.ExpeditionDurationSeconds,
		claimable = false, legality = { dispatch = allowed, claim = locked },
	},
}

local active: Activity.Snapshot = {
	sessionId = idle.sessionId, revision = 4, serverTimeUtc = completesAtUtc,
	autoBattle = {
		unlockedActs = {
			{
				act = act,
				rewardPreview = {
					yen = autoBattlePreview.yen, salvageShards = autoBattlePreview.shards,
					materials = autoBattlePreview.materials, maxStandardGearDrops = 1,
				},
			},
		},
		tickSeconds = Activity.AutoBattleTickSeconds,
		runId = tickClaim.runId, act = act, startedAtUtc = startedAtUtc,
		lastClaimedAtUtc = lastClaimedAtUtc, pendingTicks = 47, lastClaim = tickClaim,
		legality = { start = occupied, claim = allowed, stop = allowed },
	},
	expedition = {
		tickets = 2, maxTickets = Activity.QuartermasterExpeditionMaxTickets,
		durationSeconds = Activity.ExpeditionDurationSeconds,
		missionId = "mission-1", act = act, startedAtUtc = startedAtUtc, completesAtUtc = completesAtUtc,
		claimable = true, rewardPreview = craftingBundle, legality = { dispatch = occupied, claim = allowed },
	},
}

local function getSnapshot(_: Remote.GetActivitySnapshotRequest): Remote.ActivitySnapshotResponse
	return { ok = true, snapshot = active }
end

local restored = getSnapshot({})
assert(restored.ok)
local autoBattle = restored.snapshot.autoBattle
local expedition = restored.snapshot.expedition
assert(table.isfrozen(Activity) and table.isfrozen(Remote.Activity))
assert(idle.autoBattle.runId == nil and #idle.autoBattle.unlockedActs == 0 and not idle.autoBattle.legality.start.canUse)
assert(idle.expedition.missionId == nil and idle.expedition.maxTickets == 2)
assert(autoBattle.tickSeconds == 300 and autoBattle.unlockedActs[1].act == autoBattle.act)
assert(autoBattle.runId == tickClaim.runId and autoBattle.lastClaim == tickClaim)
assert(autoBattle.lastClaimedAtUtc == startedAtUtc + 300)
assert(autoBattle.pendingTicks == math.floor((active.serverTimeUtc - lastClaimedAtUtc) / 300))
assert(expedition.durationSeconds == 14400 and expedition.completesAtUtc == startedAtUtc + 14400)
assert(expedition.claimable and expedition.legality.claim.canUse and expedition.maxTickets == 3)
assert(Activity.MaxExpeditionValueFraction == 0.25)
assert(Activity.MaxExpeditionValueFraction == Economy.GlobalCaps.MaxExpeditionDropsFractionOfClear)

local cases: { { action: Activity.Action, receipt: Activity.Receipt } } = {
	{
		action = { kind = "StartAutoBattle", act = act },
		receipt = { kind = "AutoBattleStarted", runId = tickClaim.runId, act = act, startedAtUtc = startedAtUtc },
	},
	{
		action = { kind = "ClaimAutoBattle", runId = tickClaim.runId },
		receipt = {
			kind = "AutoBattleClaimed", runId = tickClaim.runId, act = act, ticksClaimed = tickClaim.ticksClaimed,
			lastClaimedAtUtc = lastClaimedAtUtc, rewards = tickClaim.rewards, standardGear = tickClaim.standardGear,
		},
	},
	{
		action = { kind = "StopAutoBattle", runId = tickClaim.runId },
		receipt = { kind = "AutoBattleStopped", runId = tickClaim.runId, stoppedAtUtc = completesAtUtc },
	},
	{
		action = { kind = "DispatchExpedition", act = act },
		receipt = {
			kind = "ExpeditionDispatched", missionId = "mission-1", act = act, ticketsSpent = 1,
			startedAtUtc = startedAtUtc, completesAtUtc = completesAtUtc,
		},
	},
	{
		action = { kind = "ClaimExpedition", missionId = "mission-1" },
		receipt = { kind = "ExpeditionClaimed", missionId = "mission-1", act = act, rewards = craftingBundle },
	},
}
for _, case in cases do
	local request: Remote.ActivityActionRequest = {
		sessionId = active.sessionId, expectedRevision = active.revision,
		requestId = "activity-fixture-" .. case.action.kind, action = case.action,
	}
	local reply: Remote.ActivityActionResponse = {
		ok = true, requestId = request.requestId, receipt = case.receipt, snapshot = active,
	}
	assert(reply.ok and reply.requestId == request.requestId and reply.receipt.kind == case.receipt.kind)
end

local conflict: Remote.ActivityActionResponse = {
	ok = false, code = "RequestConflict", message = "This request ID is already bound to another action.", snapshot = active,
}
local notReady: Remote.ActivityActionResponse = {
	ok = false, code = "ExpeditionNotReady", message = "Mission is still running.",
}
assert(not conflict.ok and conflict.snapshot == active and not notReady.ok)
assert(Remote.Activity.FolderName == "ActivityRemotes")
assert(Remote.Activity.GetActivitySnapshot.name == "GetActivitySnapshot")
assert(Remote.Activity.GetActivitySnapshot.className == "RemoteFunction")
assert(Remote.Activity.SubmitActivityAction.name == "SubmitActivityAction")
assert(Remote.Activity.SubmitActivityAction.className == "RemoteFunction")

print("Phase 6 contracts passed: activity views, reward shapes, five actions and receipts, and activity remotes")
