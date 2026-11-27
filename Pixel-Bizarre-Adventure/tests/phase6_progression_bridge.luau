--!strict

local Campaign = require("../src/shared/Core/CampaignSession")
local Progression = require("../src/shared/Core/CampaignProgression")
local Bridge = require("../src/shared/Core/CampaignProgressionBridge")
local Succession = require("../src/shared/Core/SuccessionSession")
local Activity = require("../src/shared/Core/ActivitySession")
local Economy = require("../src/shared/Core/Phase4Session")
local Hub = require("../src/shared/Contracts/HubTypes")
local Map = require("../src/shared/Contracts/MapTypes")
local Save = require("../src/shared/Contracts/SaveTypes")

local rows: { [number]: { [string]: unknown } } = {}
local now, counter = 1700000000, 0
local store: Campaign.Store = {
	load = function(id) return rows[id], true end,
	update = function(id, transform)
		local updated = transform(rows[id])
		if updated then rows[id] = updated end
		return updated, true
	end,
}
local function clock(): number return now end
local function makeId(): string
	counter += 1
	return "bridge-" .. counter
end

local isSafeHub: ((number) -> boolean)? = nil
local options: Succession.Options = {
	clock = clock, makeId = makeId,
	isSafeHub = function(id: number): boolean return if isSafeHub then isSafeHub(id) else false end,
}
local lineage = Succession.new(store, options)
local activity = Activity.new(store, options)
local economy = Economy.new(store, {
	clock = clock, makeId = makeId, roll = function() return 0 end,
	prizeFor = function() return { kind = "Supplies", items = {}, resources = { yen = 0, holyWater = 0, salvageShards = 1, materials = 1 } } end,
})
local actual = Bridge.new(lineage, activity)
local failAck = false
local adapter: Progression.Bridge = {
	life = actual.life,
	apply = function(userId, event)
		local applied = actual.apply(userId, event)
		return applied and not (failAck and event.nodeId == "Castle")
	end,
}
local function makeCampaign()
	return Campaign.new(store, clock, makeId, clock, function() return 0 end, adapter)
end
local session = makeCampaign()
isSafeHub = session.isSafeHub
local function campaign(userId: number): Hub.CampaignSnapshot
	local reply = session.get(userId)
	assert(reply.ok, if reply.ok then "" else reply.message)
	return reply.snapshot
end
local function navigate(userId: number, view: Hub.CampaignSnapshot, destination: "Hub" | "ActMap"): Hub.CampaignSnapshot
	local reply = session.submit(userId, {
		kind = "Navigate", destination = destination, sessionId = view.sessionId, expectedRevision = view.revision,
	})
	assert(reply.ok, if reply.ok then "" else reply.message)
	return reply.snapshot
end
local function seed(userId: number, origin: Save.Origin, legacy: boolean)
	rows[userId] = {
		version = 1, tutorialCompleted = true, origin = origin,
		campaign = {
			version = 1, yen = 500, stock = { ["training-wraps"] = 1 }, gear = { Weapon = "training-wraps" }, belt = {},
			appearance = { skinToneId = "Tan", hairStyleId = "bald" },
			actOne = if legacy then { clears = { F1 = true, F2 = true, D1 = true }, recruited = false } else nil,
		},
	}
end
local function fight(userId: number, view: Hub.CampaignSnapshot, lose: boolean): (Hub.CampaignSnapshot, Map.NodeId, string)
	assert(view.scene.kind == "ActMap")
	local selected: Map.NodeView? = nil
	for _, node in view.scene.map.nodes do
		if node.state == "Available" then selected = node; break end
	end
	local node = assert(selected)
	local started = session.submit(userId, {
		kind = "StartNode", nodeId = node.id, playOptionId = node.playOptions[1].id,
		sessionId = view.sessionId, expectedRevision = view.revision,
	})
	assert(started.ok and started.snapshot.scene.kind == "ActEncounter")
	local battleId = started.snapshot.scene.encounter.battleId
	local initial = session.battle(userId, { kind = "Get", request = { battleId = battleId } })
	assert(initial.ok)
	local battle = initial.snapshot
	local seenSecondPhase = false
	for _ = 1, 240 do
		if battle.outcome ~= "InProgress" then break end
		local actorId = assert(battle.activeActorId)
		local targetId = actorId
		if not lose then
			for _, actor in battle.actors do if actor.team == "Enemy" then targetId = actor.id end end
		end
		local reply = session.battle(userId, { kind = "Primary", request = {
			battleId = battleId, expectedRevision = battle.revision, actorId = actorId,
			slot = "Primary", moveId = if lose then "Defend" else "BasicStrike", targetId = targetId,
		} })
		assert(reply.ok, if reply.ok then "" else reply.message)
		battle = reply.snapshot
		seenSecondPhase = seenSecondPhase or battle.waveIndex == 2
	end
	assert(battle.outcome == (if lose then "Defeat" else "Victory"),
		string.format("Act %d %s ended %s", view.scene.map.act, node.id, battle.outcome))
	if node.id == "Castle" and not lose then assert(seenSecondPhase and battle.waveCount == 2) end
	local result = campaign(userId)
	assert(result.scene.kind == "ActResults" and result.scene.result.act == view.scene.map.act)
	return result, node.id, battleId
end

local MAIN = 1
seed(MAIN, "Part1_Hamon", false)
local phase4 = economy.GetPhase4Snapshot(MAIN)
assert(phase4.ok)
local spin = economy.SubmitPhase4Action(MAIN, {
	requestId = "before-campaign", sessionId = phase4.snapshot.sessionId, expectedRevision = phase4.snapshot.revision,
	action = { kind = "Spin", count = 1, tierId = "standard_chip" },
})
assert(spin.ok)
local view = navigate(MAIN, campaign(MAIN), "ActMap")
local hamon = { 1, 2, 3, 4, 5 }
for act, part in hamon do
	for index = 1, 11 do
		assert(view.scene.kind == "ActMap" and view.scene.map.act == act and view.scene.map.part == part)
		assert(#view.scene.map.nodes <= 3)
		local result, node = fight(MAIN, view, false)
		if index == 11 then assert(node == "Castle") end
		if act == 1 and node == "D1" then
			local offer = result.companion
			assert(offer.state == "Offered")
			local recruited = session.submit(MAIN, {
				kind = "RecruitCompanion", offerId = offer.offerId,
				sessionId = result.sessionId, expectedRevision = result.revision,
			})
			assert(recruited.ok and recruited.snapshot.companion.state == "Recruited")
			result = recruited.snapshot
		end
		view = navigate(MAIN, result, if act == 5 and index == 11 then "Hub" else "ActMap")
	end
	local heritage = lineage.GetLineageSnapshot(MAIN)
	assert(heritage.ok and heritage.snapshot.age.currentAge == 18 + act * 9)
	assert(heritage.snapshot.recoveryLedger.eligibleEchoes == ({ 8, 18, 30, 50, 80 })[act])
	assert(#heritage.snapshot.heirlooms.unlockedIds == act + 1)
	local activityView = activity.GetActivitySnapshot(MAIN)
	assert(activityView.ok and activityView.snapshot.expedition.tickets == 2)
	assert(#activityView.snapshot.autoBattle.unlockedActs == act)
	if act == 1 then
		assert(heritage.snapshot.mastery[1].marks == 4)
		assert(heritage.snapshot.heirlooms.unlockedIds[2] == "zeppelis_checkered_hat")
	end
end
local after = economy.GetPhase4Snapshot(MAIN)
assert(after.ok and after.snapshot.clinic.legality.canUse and after.snapshot.balances.materials == 1 and after.snapshot.balances.yen == view.character.yen)
local ready = activity.GetActivitySnapshot(MAIN)
assert(ready.ok and ready.snapshot.autoBattle.legality.start.canUse)
local auto = activity.SubmitActivityAction(MAIN, {
	requestId = "live-unlock", sessionId = ready.snapshot.sessionId, expectedRevision = ready.snapshot.revision,
	action = { kind = "StartAutoBattle", act = 5 },
})
assert(auto.ok and auto.snapshot.autoBattle.act == 5)

-- A migrated Stand save keeps Act 1's original clears and uses Part 3,
-- then reaches the Part 1 flashback in Act 2. A Castle defeat is not a clear.
local STAND = 2
seed(STAND, "Part3_Stand", true)
local older = campaign(STAND)
assert(older.character.level == 4 and older.companion.state == "Offered")
local standView = navigate(STAND, older, "ActMap")
assert(standView.scene.kind == "ActMap" and standView.scene.map.act == 1 and standView.scene.map.part == 3)
for _ = 1, 7 do
	local result = fight(STAND, standView, false)
	standView = navigate(STAND, result, "ActMap")
end
local loss, castle, wipeId = fight(STAND, standView, true)
assert(castle == "Castle" and loss.scene.kind == "ActResults" and loss.scene.result.outcome == "Defeat")
local hurt = lineage.GetLineageSnapshot(STAND)
assert(hurt.ok and hurt.snapshot.recoveryLedger.recoveriesRemaining == 4 and hurt.snapshot.recoveryLedger.eligibleEchoes == 0)
assert(session.battle(STAND, { kind = "Get", request = { battleId = wipeId } }).ok)
hurt = lineage.GetLineageSnapshot(STAND)
assert(hurt.ok and hurt.snapshot.recoveryLedger.recoveriesRemaining == 4)
standView = navigate(STAND, loss, "ActMap")

-- The hooks may have committed while their acknowledgement to Campaign did not.
failAck = true
local won = fight(STAND, standView, false)
assert(won.scene.kind == "ActResults")
local saved = assert(Progression.decode((rows[STAND].campaign :: { [string]: unknown }).progression))
assert(saved.pending ~= nil)
now += 181
session = makeCampaign()
isSafeHub = session.isSafeHub
failAck = false
local restored = campaign(STAND)
assert(restored.scene.kind == "ActResults" and restored.scene.result.outcome == "Clear")
assert(not assert(Progression.decode((rows[STAND].campaign :: { [string]: unknown }).progression)).pending)
local durable = lineage.GetLineageSnapshot(STAND)
assert(durable.ok and durable.snapshot.recoveryLedger.recoveriesRemaining == 4 and durable.snapshot.recoveryLedger.eligibleEchoes == 8)
assert(durable.snapshot.mastery[1].marks == 3 and durable.snapshot.heirlooms.unlockedIds[2] == "jotaros_torn_cap")
standView = navigate(STAND, restored, "ActMap")
assert(standView.scene.kind == "ActMap" and standView.scene.map.act == 2 and standView.scene.map.part == 1)

print("Phase 6 progression bridge passed: five Acts, both routes, lineage and activity rewards, wipe, and restart replay")
