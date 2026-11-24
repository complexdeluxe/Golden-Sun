--!strict

local Battle = require("../src/shared/Core/BlackSabbathBattle")
local Math = require("../src/shared/Core/SandboxMath")
local Combat = require("../src/shared/Contracts/CombatTypes")
local Remote = require("../src/shared/Contracts/RemoteContract")

local now = 0
local roll = 0.5
local function fixture(mode: Combat.QteMode?, level: number?, stage: ("Night" | "Neutral")?): Battle.State
	now = 0
	roll = 0.5
	return Battle.new("test", { level = level or 10, stageTag = stage or "Night", qteMode = mode or "UntimedCue" },
		function() return roll end, function() return now end)
end

local function success(result: Remote.SandboxResponse): Combat.SandboxSnapshot
	assert(result.ok, if result.ok then "" else result.message)
	return result.snapshot
end

local function primary(state: Battle.State, move: Combat.SandboxMoveId, slot: Combat.PrimarySlot?): Remote.SandboxResponse
	local id = assert(state.active)
	return Battle.submitPrimary(state, {
		battleId = state.id, expectedRevision = state.revision, actorId = id, slot = slot or "Primary",
		moveId = move, targetId = if move == "Defend" then id else "black_sabbath",
	})
end

local function finishTurn(state: Battle.State): Combat.SandboxSnapshot
	return success(Battle.submitSecondary(state, {
		battleId = state.id, expectedRevision = state.revision, actorId = assert(state.active), kind = "EndTurn",
	}))
end

local function belt(state: Battle.State, item: Combat.BeltItemId, target: string): Remote.SandboxResponse
	return Battle.submitSecondary(state, {
		battleId = state.id, expectedRevision = state.revision, actorId = assert(state.active), kind = "UseBeltItem",
		itemId = item, targetId = target,
	})
end

local function guardRound(state: Battle.State): Combat.SandboxSnapshot
	local start = state.round
	local snapshot = Battle.snapshot(state)
	while state.round == start do
		local id = assert(state.active)
		if state.actors[id].view.primaryAvailable then success(primary(state, "Defend")) end
		snapshot = finishTurn(state)
	end
	return snapshot
end

local function check(state: Battle.State, prompt: Combat.QtePrompt, index: number, hit: boolean): Combat.SandboxSnapshot
	local input: Combat.QteSubmissionInput
	if prompt.mode == "Manual" then
		local ring = prompt.checks[index]
		now = if hit then ring.overlapAtServerTime else ring.approachStartsAtServerTime
		input = "Confirm"
	else
		local text = prompt.checks[index].prompt
		local required: Combat.QteInput = if string.find(text, "LEFT") then "Left"
			elseif string.find(text, "RIGHT") then "Right" else "Center"
		input = if hit then required elseif required == "Left" then "Right" else "Left"
	end
	local response = Battle.submitCheck(state, {
		battleId = state.id, challengeId = prompt.id, checkIndex = index,
		input = input,
	})
	return success(response)
end

assert(Math.playerHp(10, 10) == 82 and Math.playerHp(50, 50) == 242)
assert(math.abs(Math.basicRaw(50, 120) - 80.3) < 1e-8)
assert(Math.focusPrecision(14) == 0 and Math.focusPrecision(75) == 5 and Math.focusPrecision(255) == 10)
assert(Math.focusResist(149) == 14 and Math.focusResist(255) == 15)
assert(Math.statusChance(30, 15) == 25.5)
assert(Math.hitPercent(20, 15, true) == 95 and Math.hitPercent(20, 15, false) == 90)
assert(Math.flagFleePercent(4, 8) == 71 and Math.flagFleePercent(8, 100) == 25 and Math.flagFleePercent(100, 8) == 95)
local order = { player = 1, companion = 2 }
local a = { actorId = "player", speed = 10 }
local b = { actorId = "companion", speed = 10 }
assert(Math.turnComesFirst(a, b, 1, order) and Math.turnComesFirst(b, a, 2, order))
assert(Math.damage({ raw = 100, sourceBonus = 0.6, defense = 255, mitigationPp = 40, penetrationPp = 10, armor = 0, act = 1 }) == 47)
assert(Math.damage({ raw = 100, defense = 0, armor = 60, guarding = true, act = 5 }) == 52)
assert(Math.damage({ raw = 100, defense = 0, armor = 0, guarding = true, shatter = true, act = 5 }) == 100)

for grade = 0, 3 do
	local state = fixture("AutoGood")
	state.actors.player.view.resolve = 10
	local hp = state.actors.black_sabbath.view.hp
	local initial = success(primary(state, "HighRiskHeavy"))
	local prompt = assert(initial.qtePrompt)
	assert(prompt.mode == "UntimedCue" and initial.actors[1].stamina == 1)
	assert(initial.endTurnLegality.canUse == false and not belt(state, "CoffeeGum", "player").ok)
	for i = 1, 3 do
		local snapshot = check(state, prompt, i, i <= grade)
		if i < 3 then
			assert(snapshot.qtePrompt and snapshot.qtePrompt.checkResults[i] == (if i <= grade then "Hit" else "Miss"))
		end
	end
	local player = state.actors.player.view
	local raw = Math.basicRaw(10, 24) * 1.70 * Combat.HighRiskHeavy.timingByGrade[grade]
	assert(hp - state.actors.black_sabbath.view.hp == math.floor(raw * 0.9))
	assert(player.resolve == (if grade == 3 then 25 else 9) and not player.bonusPrimaryAvailable)
	assert(not primary(state, "BasicStrike", "BonusPrimary").ok and player.stamina == 1)
end

for _, grade in { 2, 3 } do
	local state = fixture()
	state.actors.black_sabbath.baseDodge = 20
	state.actors.player.view.resolve = 10
	local hp = state.actors.black_sabbath.view.hp
	local prompt = assert(success(primary(state, "HighRiskHeavy")).qtePrompt)
	roll = 0.99
	for i = 1, 3 do check(state, prompt, i, i <= grade) end
	assert(state.actors.black_sabbath.view.hp == hp and state.log[#state.log].kind == "Dodged")
	assert(state.actors.player.view.resolve == (if grade == 3 then 10 else 9))
end

do
	local state = fixture("Manual")
	local prompt = assert(success(primary(state, "HighRiskHeavy")).qtePrompt)
	assert(prompt.mode == "Manual")
	local first = prompt.checks[1]
	local second = prompt.checks[2]
	assert(math.abs(first.overlapAtServerTime - first.approachStartsAtServerTime - 1.15) < 1e-8)
	assert(math.abs(first.closesAtServerTime - first.opensAtServerTime - 0.75) < 1e-8)
	assert(math.abs(second.approachStartsAtServerTime - first.closesAtServerTime - 0.30) < 1e-8)
	local function submit(index: number, input: Combat.QteSubmissionInput): Remote.SandboxResponse
		return Battle.submitCheck(state, { battleId = state.id, challengeId = prompt.id, checkIndex = index, input = input })
	end

	assert(not submit(1, "Confirm").ok)
	now = first.opensAtServerTime
	assert(not submit(1, "Center").ok)
	assert(not submit(2, "Confirm").ok)
	local good = assert(success(submit(1, "Confirm")).qtePrompt)
	assert(good.nextCheckIndex == 2 and good.checkResults[1] == "Hit")
	assert(not submit(1, "Confirm").ok)
	assert(not submit(2, "Confirm").ok)
	now = second.approachStartsAtServerTime
	local early = assert(success(submit(2, "Confirm")).qtePrompt)
	assert(early.checkResults[2] == "Miss" and early.nextCheckIndex == 3)
	now = prompt.checks[3].closesAtServerTime
	local late = submit(3, "Confirm")
	assert(not late.ok and late.code == "ChallengeExpired")
	assert(state.actors.player.view.resolve == 0 and state.qte == nil)
end

do
	local state = fixture("UntimedCue")
	local prompt = assert(success(primary(state, "HighRiskHeavy")).qtePrompt)
	assert(prompt.mode == "UntimedCue")
	local response = Battle.submitCheck(state, { battleId = state.id, challengeId = prompt.id, checkIndex = 1, input = "Confirm" })
	assert(not response.ok and response.code == "InvalidCheck")
	assert(Battle.snapshot(state).qtePrompt and Battle.nextDeadline(state) == nil)
	assert(check(state, prompt, 1, true).qtePrompt)
end

do
	local state = fixture("Manual")
	local prompt = assert(success(primary(state, "HighRiskHeavy")).qtePrompt)
	assert(prompt.mode == "Manual")
	now = prompt.checks[1].closesAtServerTime
	assert(Battle.expireChecks(state))
	local nextPrompt = assert(Battle.snapshot(state).qtePrompt)
	assert(nextPrompt.checkResults[1] == "Miss" and nextPrompt.nextCheckIndex == 2)
	now = prompt.checks[3].closesAtServerTime
	assert(Battle.expireChecks(state) and Battle.nextDeadline(state) == nil)
	assert(state.log[#state.log].kind == "FailedQTE_0of3")
end

do
	local state = fixture("Manual")
	local prompt = assert(success(primary(state, "HighRiskHeavy")).qtePrompt)
	for i = 1, 3 do check(state, prompt, i, true) end
	assert(state.assistUsed and not state.actors.player.view.bonusPrimaryAvailable)
	finishTurn(state)
	local second = assert(success(primary(state, "HeavyStrike")).qtePrompt)
	assert(second.mode == "Manual" and #second.checks == 1 and second.kind == "Standard")
	check(state, second, 1, true)
	local assists = 0
	for _, event in state.log do if event.kind == "Assist" then assists += 1 end end
	assert(assists == 1)
end

for _, level in { 10, 50 } do
	for _, stage in { "Neutral", "Night" } do
		local state = fixture(nil, level, stage)
		guardRound(state)
		guardRound(state)
		local before = state.actors.player.view.hp
		success(primary(state, "Defend"))
		finishTurn(state)
		success(primary(state, "Defend"))
		local fade = finishTurn(state)
		local expected = if level == 50 then (if stage == "Night" then 43 else 37) else (if stage == "Night" then 17 else 14)
		assert(before - state.actors.player.view.hp == expected and not state.actors.player.stunned)
		local grabLogged = false
		for _, event in fade.log do
			if event.kind == "Damage" and event.moveId == "ShadowGrab" then
				assert(event.message == string.format("You take %d damage.", expected))
				grabLogged = true
			end
		end
		assert(grabLogged)
		assert(fade.blackSabbathStep == "FadeIntoShadow" and fade.actors[3].statuses[1].id == "Fade")
	end
end

do
	local state = fixture()
	guardRound(state)
	local intent = assert(state.intent)
	assert(intent.landingTurn == 3 and intent.targetId == "player" and intent.uvCancelable)
	local response = success(Battle.submitSecondary(state, {
		battleId = state.id, expectedRevision = state.revision, actorId = "player",
		kind = "CompanionGuardRedirect", intentId = intent.id, recipientId = "companion",
	}))
	assert(response.enemyIntents[1].targetId == "companion" and response.companion and response.companion.redirect
		and response.companion.redirect.usesRemaining == 0)
	guardRound(state)
	success(primary(state, "Defend"))
	finishTurn(state)
	success(primary(state, "Defend"))
	local before = state.actors.companion.view.hp
	finishTurn(state)
	assert(state.actors.companion.view.hp < before and not state.actors.companion.stunned)
end

do
	local state = fixture()
	guardRound(state)
	assert(not belt(state, "UVFlash", "player").ok)
	local uv = success(belt(state, "UVFlash", "black_sabbath"))
	assert(#uv.enemyIntents == 0 and not uv.exposure and uv.belt.beltChargesRemaining == 2)
	guardRound(state)
	local before = state.actors.player.view.hp
	guardRound(state)
	assert(state.actors.player.view.hp == before)
end

for _, lands in { false, true } do
	local state = fixture()
	guardRound(state)
	roll = if lands then 0.5 else 0.99
	success(primary(state, "HamonInterrupt"))
	assert((state.intent == nil) == lands and state.exposed == lands)
	if lands then
		finishTurn(state)
		local followUp = Battle.snapshot(state).exposure
		assert(followUp and followUp.exposedFollowUpActorId == "companion")
		success(primary(state, "BasicStrike"))
		assert(not state.exposed)
	end
end

do
	local state = fixture(nil, 50)
	guardRound(state)
	guardRound(state)
	success(primary(state, "BasicStrike"))
	finishTurn(state)
	success(primary(state, "Defend"))
	finishTurn(state)
	assert(state.actors.player.stunned == false and not state.actors.player.view.primaryAvailable)
	assert(Battle.snapshot(state).endTurnLegality.canUse)

	state.actors.player.view.hp = 50
	state.actors.companion.view.hp = 50
	assert(success(belt(state, "MedKit", "player")).belt.medKitUsed)
	finishTurn(state)
	assert(not belt(state, "MedKit", "companion").ok)
	success(belt(state, "MineralWater", "companion"))
	success(primary(state, "Defend"))
	finishTurn(state)
	assert(not belt(state, "CapreseSalad", "player").ok)
	state.actors.player.view.resolve = 80
	state.actors.player.view.resolveGainedThisTurn = 16
	local espresso = success(belt(state, "PassioneEspresso", "player"))
	assert(espresso.belt.beltChargesRemaining == 0 and espresso.actors[1].resolve == 89 and espresso.actors[1].resolveGainedThisTurn == 25)
end

do
	local state = fixture()
	state.actors.player.view.resolve = 90
	local response = success(belt(state, "PassioneEspresso", "player"))
	assert(response.actors[1].onFireTurnsRemaining == 2 and response.actors[1].finisherReady)
	local finish = success(primary(state, "Finisher"))
	assert(finish.actors[1].onFireTurnsRemaining == 0 and finish.actors[1].resolve == 0)
end

print("Phase 2 parity passed: math, QTE, turn slots, Guard, redirect, interrupt, Fade, UV, belt and Resolve")
