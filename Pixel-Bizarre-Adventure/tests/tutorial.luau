--!strict

local Combat = require("../src/shared/Contracts/CombatTypes")
local Engine = require("../src/shared/Core/CombatEngine")
local Progress = require("../src/shared/Core/TutorialProgress")
local Session = require("../src/shared/Core/TutorialSession")
local Save = require("../src/shared/Contracts/SaveTypes")

local function action(battle: Engine.Battle, move: Combat.MoveId, target: string?): Engine.Battle
	local updated, reason = Engine.apply(battle, {
		battleId = battle.id,
		expectedRevision = battle.revision,
		moveId = move,
		targetId = target,
	})
	assert(updated, reason)
	return updated
end

local function check(name: string, run: () -> ())
	run()
	print("PASS " .. name)
end

check("opening intent, speed and Quick Strike", function()
	local battle = Engine.new("opening")
	local view = Engine.snapshot(battle)
	assert(view.activeActorId == "player" and view.turnOrder[1].actorId == "player")
	assert(view.enemyIntents[1].targetId == "player" and view.enemyIntents[1].landingTurn == 1)
	assert(view.enemyIntents[1].estimatedPower == 5 and view.actors[2].spriteKey == "DarioIdle")
	view.actors[1].hp = 1
	local updated = action(battle, "QuickStrike", "dario")
	assert(updated.dario.hp == 34 and updated.player.hp == 28 and updated.player.stamina == 4)
	assert(battle.dario.hp == 40 and battle.player.hp == 32 and #battle.log == 0)
end)

check("Heavy Strike cost, damage, legality and rejected input", function()
	local battle = Engine.new("heavy")
	local updated = action(battle, "HeavyStrike", "dario")
	assert(updated.dario.hp == 29 and updated.player.stamina == 1)
	battle.player.stamina = 2
	local locked = Engine.snapshot(battle).actions[2]
	assert(locked.staminaCost == 3 and locked.legality.canUse == false)
	local denied = Engine.apply(battle, { battleId = battle.id, expectedRevision = 1, moveId = "HeavyStrike", targetId = "dario" })
	assert(denied == nil and battle.revision == 1 and battle.player.stamina == 2)
	assert(Engine.apply(battle, { battleId = battle.id, expectedRevision = 1, moveId = "QuickStrike", targetId = "player" }) == nil)
end)

check("Defend reduces four damage to one and clears next turn", function()
	local battle = action(Engine.new("guard"), "Defend", nil)
	assert(battle.player.hp == 31 and not battle.player.isDefending)
	assert(battle.log[1].kind == "Guard" and battle.log[2].amount == 1)
	assert(battle.revision == 3 and battle.round == 2)
end)

check("reinforcement joins once and uses its displayed Support once", function()
	local battle = Engine.new("reinforcement")
	battle.dario.hp = 26
	battle = action(battle, "QuickStrike", "dario")
	local wife = battle.wife
	assert(wife and battle.dario.hp == 20 and battle.round == 2)
	local view = Engine.snapshot(battle)
	assert(view.turnOrder[2].actorId == "wife")
	assert(view.enemyIntents[1].moveId == "WifeSupport" and view.enemyIntents[1].targetId == "dario")
	battle = action(battle, "Defend", nil)
	assert(battle.dario.hp == 24 and battle.wifeHealUsed)
	assert(Engine.snapshot(battle).enemyIntents[1].moveId == "WifeCounterattack")
	local joins = 0
	for _, event in battle.log do
		if event.kind == "Join" then joins += 1 end
	end
	assert(joins == 1)
end)

check("either retreat ends the tutorial and early retreat skips reinforcement", function()
	local battle = Engine.new("early-victory")
	battle.dario.hp = 21
	battle.player.power = 6
	battle = action(battle, "HeavyStrike", "dario")
	assert(battle.outcome == "Victory" and not battle.wife and #Engine.snapshot(battle).enemyIntents == 0)
	assert(battle.log[2].kind == "Flee" and battle.log[2].actorId == "dario")
	local second = Engine.new("other-victory")
	second.dario.hp = 21
	second = action(second, "QuickStrike", "dario")
	local wife = second.wife
	assert(wife)
	wife.hp = 10
	second = action(second, "QuickStrike", "wife")
	assert(second.outcome == "Victory" and second.dario.hp == 15)
end)

type Mock = {
	profiles: { [number]: Save.Profile },
	writes: number,
	failWrites: boolean,
}
local function sandbox(): (Session.Controller, Mock)
	local saved: Mock = { profiles = {}, writes = 0, failWrites = false }
	local store: Session.Store = {
		load = function(id) return Progress.decode(saved.profiles[id]) end,
		update = function(id, transform)
			if saved.failWrites then return nil, nil end
			local current = Progress.decode(saved.profiles[id])
			assert(current)
			local changed, reason = transform(current)
			if changed then
				saved.profiles[id] = table.clone(changed)
				saved.writes += 1
			end
			return changed, reason
		end,
	}
	local count = 0
	return Session.new(store, function() count += 1; return "battle-" .. count end), saved
end

check("defeat, free retry and stale or cross-player requests", function()
	local controller, saved = sandbox()
	local other = controller.start(101)
	assert(other.ok == true)
	local fresh = controller.start(102)
	assert(fresh.ok == true)
	local current = fresh.snapshot
	local invalid = controller.submit(102, { battleId = current.battleId, expectedRevision = current.revision, moveId = "QuickStrike", targetId = "wife" })
	assert(invalid.ok == false and invalid.code == "IllegalAction")
	for _ = 1, 32 do
		local result = controller.submit(102, { battleId = current.battleId, expectedRevision = current.revision, moveId = "Defend" })
		assert(result.ok == true)
		current = result.snapshot
	end
	assert(current.outcome == "Defeat" and saved.writes == 0)
	assert(current.log[#current.log - 1].kind == "Defeated")
	local retried = controller.retry(102, { battleId = current.battleId, expectedRevision = current.revision })
	assert(retried.ok == true and retried.snapshot.battleId ~= current.battleId)
	assert(retried.snapshot.actors[1].hp == 32 and retried.snapshot.actors[1].stamina == 3)
	local foreign = controller.retry(101, { battleId = current.battleId, expectedRevision = current.revision })
	assert(foreign.ok == false and foreign.code == "BattleNotFound")
	local stale = controller.submit(102, { battleId = retried.snapshot.battleId, expectedRevision = 9, moveId = "Defend" })
	assert(stale.ok == false and stale.code == "StaleRevision" and stale.snapshot)
end)

check("victory and origin save once, retry safely and survive session reload", function()
	local controller, saved = sandbox()
	local premature = controller.choose(201, { origin = "Part1_Hamon" })
	assert(premature.ok == false and premature.code == "TutorialIncomplete")
	local opened = controller.start(201)
	assert(opened.ok == true)
	local current = opened.snapshot
	for _, move in ({ "HeavyStrike", "QuickStrike", "QuickStrike" } :: { Combat.MoveId }) do
		local result = controller.submit(201, { battleId = current.battleId, expectedRevision = current.revision, moveId = move, targetId = "dario" })
		assert(result.ok == true)
		current = result.snapshot
	end
	local winning: Combat.ActionRequest = { battleId = current.battleId, expectedRevision = current.revision, moveId = "HeavyStrike", targetId = "dario" }
	saved.failWrites = true
	local failed = controller.submit(201, winning)
	assert(failed.ok == false and failed.code == "SaveUnavailable" and failed.snapshot)
	assert(failed.snapshot.revision == current.revision)
	saved.failWrites = false
	local won = controller.submit(201, winning)
	assert(won.ok == true and won.profile.tutorialCompleted and saved.writes == 1)
	assert(controller.submit(201, winning).ok == false and saved.writes == 1)
	local chosen = controller.choose(201, { origin = "Part3_Stand" })
	assert(chosen.ok == true and saved.writes == 2)
	assert(controller.choose(201, { origin = "Part3_Stand" }).ok == true and saved.writes == 2)
	assert(controller.choose(201, { origin = "Part1_Hamon" }).ok == false)
	controller.remove(201)
	local reopened = controller.start(201)
	assert(reopened.ok == true and reopened.snapshot.outcome == "Victory" and reopened.profile.origin == "Part3_Stand")
	assert(Progress.decode({ version = 99, tutorialCompleted = false }) == nil)
end)
