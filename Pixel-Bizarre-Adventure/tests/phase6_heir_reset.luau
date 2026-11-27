--!strict

local Activity = require("../src/shared/Core/ActivitySession")
local Bridge = require("../src/shared/Core/CampaignProgressionBridge")
local Campaign = require("../src/shared/Core/CampaignSession")
local Economy = require("../src/shared/Core/Phase4Session")
local HeirReset = require("../src/shared/Core/CampaignHeirReset")
local Profile = require("../src/shared/Core/Phase4Profile")
local Succession = require("../src/shared/Core/SuccessionSession")
local Lineage = require("../src/shared/Core/SuccessionProfile")
local Hub = require("../src/shared/Contracts/HubTypes")
local Map = require("../src/shared/Contracts/MapTypes")
local Starter = require("../src/shared/Data/CampaignStarter")
local Bloodline = require("../src/shared/Data/BloodlineTreeData")

local rows: { [number]: Lineage.Row } = {}
local now, ids = 1000, 0
local loseReply, repeatTransform = false, false
local dropHeirReplyFor: number? = nil
local store: Campaign.Store = {
	load = function(id) return rows[id], true end,
	update = function(id, transform)
		local previous = rows[id]
		if repeatTransform then
			repeatTransform = false
			assert(transform(previous))
		end
		local changed = transform(previous)
		if changed then
			rows[id] = changed
			if dropHeirReplyFor == id then
				local _, old = Lineage.decodeRow(previous)
				local _, new = Lineage.decodeRow(changed)
				if old and new and new.life.generation > old.life.generation then
					dropHeirReplyFor = nil
					return nil, false
				end
			end
		end
		if loseReply then loseReply = false; return nil, false end
		return changed, true
	end,
}
local function clock(): number return now end
local function makeId(): string
	ids += 1
	return "heir-reset-" .. ids
end

local atHub: ((number) -> boolean)? = nil
local options: Succession.Options = {
	clock = clock, makeId = makeId, applyHeirReset = HeirReset.apply,
	isSafeHub = function(id: number): boolean return if atHub then atHub(id) else false end,
}
local lineage = Succession.new(store, options)
local activity = Activity.new(store, options)
local economy = Economy.new(store, {
	clock = clock, makeId = makeId, roll = function() return 0 end,
	prizeFor = function()
		return { kind = "Supplies", items = {}, resources = { yen = 0, holyWater = 0, salvageShards = 1, materials = 1 } }
	end,
})
local campaign = Campaign.new(store, clock, makeId, clock, function() return 0 end, Bridge.new(lineage, activity))
atHub = campaign.isSafeHub

local function get(user: number): Hub.CampaignSnapshot
	local reply = campaign.get(user)
	assert(reply.ok, if reply.ok then "" else reply.message)
	return reply.snapshot
end
local function navigate(user: number, view: Hub.CampaignSnapshot, destination: "ActMap" | "Hub"): Hub.CampaignSnapshot
	local reply = campaign.submit(user, {
		kind = "Navigate", destination = destination, sessionId = view.sessionId, expectedRevision = view.revision,
	})
	assert(reply.ok, if reply.ok then "" else reply.message)
	return reply.snapshot
end
local function openLineage(user: number)
	local reply = lineage.GetLineageSnapshot(user)
	assert(reply.ok, if reply.ok then "" else reply.message)
	return reply.snapshot
end
local function available(view: Hub.CampaignSnapshot): Map.NodeView
	assert(view.scene.kind == "ActMap")
	for _, node in view.scene.map.nodes do if node.state == "Available" then return node end end
	error("No available story node")
end
local function start(user: number, view: Hub.CampaignSnapshot, confirm: boolean): string
	local node = available(view)
	local reply = campaign.submit(user, {
		kind = "StartNode", nodeId = node.id,
		playOptionId = node.playOptions[1].id .. (if confirm then ":confirm" else ""),
		sessionId = view.sessionId, expectedRevision = view.revision,
	})
	assert(reply.ok and reply.snapshot.scene.kind == "ActEncounter", if reply.ok then "Expected a fight" else reply.message)
	return reply.snapshot.scene.encounter.battleId
end
local function finish(user: number, battleId: string, lose: boolean): Hub.CampaignSnapshot
	local reply = campaign.battle(user, { kind = "Get", request = { battleId = battleId } })
	assert(reply.ok)
	local battle = reply.snapshot
	for _ = 1, 240 do
		if battle.outcome ~= "InProgress" then break end
		local actor = assert(battle.activeActorId)
		local target = actor
		if not lose then
			for _, enemy in battle.actors do if enemy.team == "Enemy" then target = enemy.id end end
		end
		local nextTurn = campaign.battle(user, { kind = "Primary", request = {
			battleId = battleId, expectedRevision = battle.revision, actorId = actor, slot = "Primary",
			moveId = if lose then "Defend" else "BasicStrike", targetId = target,
		} })
		assert(nextTurn.ok, if nextTurn.ok then "" else nextTurn.message)
		battle = nextTurn.snapshot
	end
	assert(battle.outcome == (if lose then "Defeat" else "Victory"))
	return get(user)
end

local vault = { items = { ["vault-watch"] = { uuid = "vault-watch", familyId = "heirloom" } } }
local function seed(user: number)
	rows[user] = {
		version = 1, tutorialCompleted = true, origin = "Part1_Hamon", bloodlineVault = vault,
		campaign = {
			version = 1, yen = 500, stock = { ["training-wraps"] = 1, ["tonio-water"] = 6 }, belt = { ["1"] = "tonio-water" },
			gear = { Weapon = "training-wraps" }, appearance = { skinToneId = "Tan", hairStyleId = "bald" },
		},
	}
	local opened = economy.GetPhase4Snapshot(user)
	assert(opened.ok)
	local record = assert(Profile.decode(rows[user]))
	local phase4 = table.clone(record.phase4)
	phase4.cosmetics = { ["permanent-swatch"] = true }
	phase4.salvageShards = 71
	phase4.goldenApple = true
	phase4.items["kept-gear"] = {
		uuid = "kept-gear", familyId = "training-wraps", slot = "Weapon", tier = 1, rarity = "Common",
		baseStats = {}, rolledLines = {}, temperLevel = 0, temperPityFailures = 0, cursed = false,
	}
	phase4.equippedGear["kept-gear"] = true
	phase4.installs.HeadOptics = { site = "HeadOptics", tier = 3, routineId = "UVBeam" }
	phase4.equippedRoutines[1] = "UVBeam"
	rows[user] = Profile.encode(record, phase4, record.campaign.yen)
end
local function checkHeir(user: number, yen: number, shards: number): Hub.CampaignSnapshot
	local view = get(user)
	assert(view.scene.kind == "Hub" and view.character.level == 1 and view.character.yen == yen)
	assert(view.character.origin == "Part1_Hamon" and view.character.tutorialCompleted and view.character.appearance ~= nil)
	assert(view.companion.state == "Locked")
	local record = assert(Profile.decode(rows[user]))
	assert(record.phase4.act == 1 and record.phase4.salvageShards == shards)
	assert(record.phase4.cosmetics["permanent-swatch"] and rows[user].bloodlineVault == vault)
	assert(record.phase4.items["kept-gear"] and next(record.phase4.equippedGear) == nil)
	assert(next(record.phase4.installs) == nil and #record.phase4.equippedRoutines == 0)
	assert(next(record.campaign.gear) == nil and next(record.campaign.belt) == nil and next(record.campaign.actOne.clears) == nil)
	assert(record.campaign.stock["training-wraps"] == 1 and record.campaign.stock["tonio-water"] == 2)
	assert(record.campaign.actOne.pending == nil and record.campaign.actOne.result == nil and not record.phase4.goldenApple)
	local activities = activity.GetActivitySnapshot(user)
	assert(activities.ok and activities.snapshot.expedition.tickets == 2)
	return view
end

local VOLUNTARY = 1
seed(VOLUNTARY)
local first = openLineage(VOLUNTARY)
local view = navigate(VOLUNTARY, get(VOLUNTARY), "ActMap")
for act = 1, 3 do
	for index = 1, 11 do
		assert(view.scene.kind == "ActMap" and view.scene.map.act == act)
		local node = available(view)
		local result = finish(VOLUNTARY, start(VOLUNTARY, view, false), false)
		if act == 1 and node.id == "D1" then
			local offer = result.companion
			assert(offer.state == "Offered")
			local recruit = campaign.submit(VOLUNTARY, {
				kind = "RecruitCompanion", offerId = offer.offerId,
				sessionId = result.sessionId, expectedRevision = result.revision,
			})
			assert(recruit.ok)
			result = recruit.snapshot
		end
		view = navigate(VOLUNTARY, result, if act == 3 and index == 11 then "Hub" else "ActMap")
	end
end
local retire = openLineage(VOLUNTARY)
assert(retire.generation == 1 and retire.lifeId == first.lifeId and retire.recoveryLedger.retireNowEchoes == 30)
assert(retire.mastery[1].marks == 8 and #retire.heirlooms.unlockedIds == 4)
local request = {
	sessionId = retire.sessionId, expectedRevision = retire.revision, requestId = "torch-one",
	action = { kind = "PassTheTorch" :: "PassTheTorch", lifeId = retire.lifeId, confirmed = true },
}
local beforeEconomy = economy.GetPhase4Snapshot(VOLUNTARY)
assert(beforeEconomy.ok)
repeatTransform, loseReply = true, true
local lost = lineage.SubmitLineageAction(VOLUNTARY, request)
assert(not lost.ok and lost.code == "SaveUnavailable")
view = checkHeir(VOLUNTARY, Starter.StartingYen, 0)
local stale = economy.SubmitPhase4Action(VOLUNTARY, {
	sessionId = beforeEconomy.snapshot.sessionId, expectedRevision = beforeEconomy.snapshot.revision,
	requestId = "old-wallet", action = { kind = "Spin", tierId = "standard_chip", count = 1 },
})
assert(not stale.ok and stale.code == "StaleRevision")
local heir = openLineage(VOLUNTARY)
assert(heir.generation == 2 and heir.age.currentAge == 18 and heir.recoveryLedger.recoveriesRemaining == 5)
assert(heir.bloodlineTree.echoesBalance == 30 and heir.mastery[1].marks == 8 and #heir.heirlooms.unlockedIds == 4)

local purse = {
	sessionId = heir.sessionId, expectedRevision = heir.revision, requestId = "buy-purse",
	action = { kind = "PurchaseBloodlineNode" :: "PurchaseBloodlineNode", nodeId = "family_purse" :: "family_purse" },
}
local purchase = lineage.SubmitLineageAction(VOLUNTARY, purse)
assert(purchase.ok and purchase.receipt.kind == "BloodlineNodePurchased" and purchase.receipt.rank == 1)
assert(purchase.snapshot.bloodlineTree.echoesBalance == 10)
local quote = Bloodline.FamilyPurseBonuses[1]
view = checkHeir(VOLUNTARY, Starter.StartingYen + 50, 5)
local saved = rows[VOLUNTARY]
local reprise = lineage.SubmitLineageAction(VOLUNTARY, request)
assert(reprise.ok and reprise.receipt.kind == "PassedTheTorch" and reprise.receipt.nextLifeId == heir.lifeId)
assert(lineage.SubmitLineageAction(VOLUNTARY, purse).ok and rows[VOLUNTARY] == saved)
assert(quote.yen == 50 and quote.salvageShards == 5)

view = navigate(VOLUNTARY, view, "ActMap")
assert(view.scene.kind == "ActMap" and view.scene.map.act == 1 and available(view).id == "F1")
start(VOLUNTARY, view, false)
assert(assert(Profile.decode(rows[VOLUNTARY])).campaign.progression.starterPurseRank == nil)

local TERMINAL = 2
seed(TERMINAL)
local before = openLineage(TERMINAL)
view = navigate(TERMINAL, get(TERMINAL), "ActMap")
for _ = 1, 10 do view = navigate(TERMINAL, finish(TERMINAL, start(TERMINAL, view, false), false), "ActMap") end
for attempt = 1, 5 do
	assert(available(view).id == "Castle")
	local result = finish(TERMINAL, start(TERMINAL, view, false), true)
	assert(openLineage(TERMINAL).recoveryLedger.recoveriesRemaining == 5 - attempt)
	view = navigate(TERMINAL, result, "ActMap")
end
local blocked = campaign.submit(TERMINAL, {
	kind = "StartNode", nodeId = "Castle", playOptionId = "Castle:first",
	sessionId = view.sessionId, expectedRevision = view.revision,
})
assert(not blocked.ok and blocked.code == "IllegalAction")
local terminalId = start(TERMINAL, view, true)
dropHeirReplyFor = TERMINAL
local terminalHub = finish(TERMINAL, terminalId, true)
assert(dropHeirReplyFor == nil)
assert(terminalHub.scene.kind == "Hub" and terminalHub.character.level == 1)
checkHeir(TERMINAL, Starter.StartingYen, 0)
local repeatedWipe = lineage.recordCastleWipe(TERMINAL, {
	lifeId = before.lifeId, eventId = terminalId, act = 1, encounterKind = "Castle", fullPartyWipe = true, mode = "FirstClear",
})
assert(repeatedWipe.ok and not repeatedWipe.changed and repeatedWipe.snapshot.generation == 2)
assert(repeatedWipe.settlement and repeatedWipe.settlement.cause == "CastleWipe")
assert(repeatedWipe.snapshot.recoveryLedger.recoveriesRemaining == 5 and repeatedWipe.snapshot.lifeId ~= before.lifeId)

print("Phase 6 heir reset passed: Acts 1–3, lost replies, Family Purse, permanent state, and terminal Castle")
