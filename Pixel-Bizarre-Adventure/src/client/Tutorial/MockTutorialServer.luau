--!strict
-- Client-only stand-in for the Phase 1 tutorial server.
--
-- It answers the four RemoteContract calls with contract-shaped snapshots so the
-- battle screen can be built and tested before Codex's BattleService lands.
-- The numbers here are placeholders, not the real combat rules. The real rules
-- live in src/shared/Core and src/server, and this mock is never used once the
-- TutorialRemotes folder exists.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatTypes = require(ReplicatedStorage.Shared.Contracts.CombatTypes)
local SaveTypes = require(ReplicatedStorage.Shared.Contracts.SaveTypes)
local RemoteContract = require(ReplicatedStorage.Shared.Contracts.RemoteContract)
local AssetManifest = require(ReplicatedStorage.Shared.Contracts.AssetManifest)

type ActorState = CombatTypes.ActorState
type EnemyIntent = CombatTypes.EnemyIntent
type ActionOption = CombatTypes.ActionOption
type CombatLogEvent = CombatTypes.CombatLogEvent
type CombatSnapshot = CombatTypes.CombatSnapshot
type MoveId = CombatTypes.MoveId
type Profile = SaveTypes.Profile
type TutorialResponse = RemoteContract.TutorialResponse
type ChooseOriginResponse = RemoteContract.ChooseOriginResponse
type ErrorCode = RemoteContract.ErrorCode

type EnemyPlan = { moveId: string, label: string, kind: "Attack" | "Heavy" | "Guard", power: number }

type Battle = {
	id: string,
	revision: number,
	turn: number,
	actors: { ActorState },
	log: { CombatLogEvent },
	outcome: CombatTypes.CombatOutcome,
	wifeJoined: boolean,
	nextPlan: { [string]: number },
}

local PLAYER_ID = "player"
local DARIO_ID = "dario"
local WIFE_ID = "wife"
local WIFE_JOIN_TURN = 3

local QUICK_COST = 0
local HEAVY_COST = 3
local DEFEND_MULTIPLIER = 0.65

local PLANS: { [string]: { EnemyPlan } } = {
	[DARIO_ID] = {
		{ moveId = "DarioSwing", label = "Drunken Swing", kind = "Attack", power = 4 },
		{ moveId = "DarioSwing", label = "Drunken Swing", kind = "Attack", power = 4 },
		{ moveId = "DarioBottle", label = "Bottle Smash", kind = "Heavy", power = 12 },
	},
	[WIFE_ID] = {
		{ moveId = "WifeShove", label = "Desperate Shove", kind = "Attack", power = 2 },
	},
}

local MockTutorialServer = {}

local profile: Profile = {
	version = SaveTypes.PROFILE_VERSION,
	tutorialCompleted = false,
	origin = nil,
}
local current: Battle? = nil
local battleCount = 0

local function copyProfile(): Profile
	return { version = profile.version, tutorialCompleted = profile.tutorialCompleted, origin = profile.origin }
end

local function findActor(battle: Battle, id: string): ActorState?
	for _, actor in battle.actors do
		if actor.id == id then
			return actor
		end
	end
	return nil
end

local function isAlive(actor: ActorState): boolean
	return actor.hp > 0
end

local function newActor(
	id: string,
	name: string,
	team: CombatTypes.Team,
	hp: number,
	stamina: number,
	speed: number,
	power: number,
	spriteKey: AssetManifest.AssetKey
): ActorState
	return {
		id = id,
		displayName = name,
		hp = hp,
		maxHp = hp,
		stamina = stamina,
		maxStamina = 5,
		armor = 0,
		speed = speed,
		power = power,
		isDefending = false,
		team = team,
		spriteKey = spriteKey,
	}
end

local function newBattle(): Battle
	battleCount += 1
	local battle: Battle = {
		id = `tutorial-mock-{battleCount}`,
		revision = 1,
		turn = 1,
		actors = {
			newActor(PLAYER_ID, "You", "Player", 40, 2, 3, 6, "PlayerIdle"),
			newActor(DARIO_ID, "Dario Brando", "Enemy", 28, 0, 2, 1, "DarioIdle"),
		},
		log = {},
		outcome = "InProgress",
		wifeJoined = false,
		nextPlan = { [DARIO_ID] = 1, [WIFE_ID] = 1 },
	}
	table.insert(battle.log, {
		turn = 1,
		kind = "Join",
		actorId = DARIO_ID,
		message = "The carriage overturns in the rain. Dario Brando staggers toward you!",
	})
	return battle
end

local function planFor(battle: Battle, actorId: string): EnemyPlan
	local plans = PLANS[actorId]
	return plans[battle.nextPlan[actorId]]
end

local function livingEnemies(battle: Battle): { ActorState }
	local list = {}
	for _, actor in battle.actors do
		if actor.team == "Enemy" and isAlive(actor) then
			table.insert(list, actor)
		end
	end
	return list
end

local function turnOrder(battle: Battle): { CombatTypes.TurnOrderEntry }
	local living = {}
	for _, actor in battle.actors do
		if isAlive(actor) then
			table.insert(living, actor)
		end
	end
	table.sort(living, function(a, b)
		if a.speed ~= b.speed then
			return a.speed > b.speed
		end
		return a.team == "Player" and b.team ~= "Player"
	end)
	local order = {}
	for _, actor in living do
		table.insert(order, { actorId = actor.id, speed = actor.speed })
	end
	return order
end

local function intents(battle: Battle): { EnemyIntent }
	local list = {}
	if battle.outcome ~= "InProgress" then
		return list
	end
	for _, enemy in livingEnemies(battle) do
		local plan = planFor(battle, enemy.id)
		table.insert(list, {
			actorId = enemy.id,
			moveId = plan.moveId,
			label = plan.label,
			targetId = PLAYER_ID,
			landingTurn = battle.turn,
			telegraphKind = plan.kind,
			estimatedPower = plan.power,
		})
	end
	return list
end

local function legality(canUse: boolean, reason: string): CombatTypes.ActionLegality
	if canUse then
		return { canUse = true }
	end
	return { canUse = false, disabledReason = reason }
end

local function actions(battle: Battle): { ActionOption }
	local player = findActor(battle, PLAYER_ID)
	assert(player, "mock battle has no player")
	local targets = {}
	for _, enemy in livingEnemies(battle) do
		table.insert(targets, enemy.id)
	end
	local over = battle.outcome ~= "InProgress"
	local overReason = if battle.outcome == "Victory" then "The fight is won" else "You were defeated"

	local heavyOk = not over and player.stamina >= HEAVY_COST
	local heavyReason = if over then overReason else `Needs {HEAVY_COST} Stamina (you have {player.stamina})`

	return {
		{
			moveId = "QuickStrike",
			label = "Quick Strike",
			staminaCost = QUICK_COST,
			targetIds = targets,
			legality = legality(not over, overReason),
		},
		{
			moveId = "HeavyStrike",
			label = "Heavy Strike",
			staminaCost = HEAVY_COST,
			targetIds = targets,
			legality = legality(heavyOk, heavyReason),
		},
		{
			moveId = "Defend",
			label = "Defend",
			staminaCost = 0,
			targetIds = {},
			legality = legality(not over, overReason),
		},
	}
end

local function snapshot(battle: Battle): CombatSnapshot
	local actorsCopy = {}
	for _, actor in battle.actors do
		table.insert(actorsCopy, table.clone(actor))
	end
	local logCopy = {}
	for _, event in battle.log do
		table.insert(logCopy, table.clone(event))
	end
	return {
		battleId = battle.id,
		revision = battle.revision,
		turn = battle.turn,
		playerActorId = PLAYER_ID,
		activeActorId = if battle.outcome == "InProgress" then PLAYER_ID else nil,
		actors = actorsCopy,
		turnOrder = turnOrder(battle),
		enemyIntents = intents(battle),
		actions = actions(battle),
		log = logCopy,
		outcome = battle.outcome,
	}
end

local function ok(battle: Battle): TutorialResponse
	return { ok = true, snapshot = snapshot(battle), profile = copyProfile() }
end

local function reject(code: ErrorCode, message: string, battle: Battle?): TutorialResponse
	return {
		ok = false,
		code = code,
		message = message,
		snapshot = if battle then snapshot(battle) else nil,
	}
end

local function log(battle: Battle, event: CombatLogEvent)
	table.insert(battle.log, event)
end

local function dealDamage(battle: Battle, attacker: ActorState, target: ActorState, raw: number, moveId: string)
	local amount = raw
	if target.isDefending then
		amount = math.max(1, math.floor(raw * DEFEND_MULTIPLIER))
	end
	target.hp = math.max(0, target.hp - amount)
	log(battle, {
		turn = battle.turn,
		kind = "Damage",
		actorId = attacker.id,
		targetId = target.id,
		moveId = moveId,
		amount = amount,
		message = if attacker.id == PLAYER_ID
			then `You hit {target.displayName} for {amount}.`
			else `{attacker.displayName} hits you for {amount}.`,
	})
	if target.hp == 0 then
		log(battle, {
			turn = battle.turn,
			kind = "Defeated",
			actorId = target.id,
			message = if target.id == PLAYER_ID then "You go down!" else `{target.displayName} goes down!`,
		})
	end
end

local function checkOutcome(battle: Battle)
	if battle.outcome ~= "InProgress" then
		return
	end
	local player = findActor(battle, PLAYER_ID)
	assert(player, "mock battle has no player")
	if player.hp == 0 then
		battle.outcome = "Defeat"
		log(battle, { turn = battle.turn, kind = "Outcome", message = "You were defeated. Try again!" })
	elseif #livingEnemies(battle) == 0 and battle.wifeJoined then
		battle.outcome = "Victory"
		profile.tutorialCompleted = true
		log(battle, { turn = battle.turn, kind = "Outcome", message = "Victory! The road is clear." })
	end
end

local function enemyPhase(battle: Battle)
	local player = findActor(battle, PLAYER_ID)
	assert(player, "mock battle has no player")
	for _, enemy in livingEnemies(battle) do
		if battle.outcome ~= "InProgress" then
			return
		end
		local plan = planFor(battle, enemy.id)
		log(battle, {
			turn = battle.turn,
			kind = "Action",
			actorId = enemy.id,
			targetId = PLAYER_ID,
			moveId = plan.moveId,
			message = `{enemy.displayName} uses {plan.label}!`,
		})
		dealDamage(battle, enemy, player, plan.power, plan.moveId)
		battle.nextPlan[enemy.id] = battle.nextPlan[enemy.id] % #PLANS[enemy.id] + 1
		checkOutcome(battle)
	end
end

local function advanceTurn(battle: Battle)
	if battle.outcome ~= "InProgress" then
		return
	end
	battle.turn += 1
	local player = findActor(battle, PLAYER_ID)
	assert(player, "mock battle has no player")
	player.isDefending = false
	player.stamina = math.min(player.maxStamina, player.stamina + 1)
	if not battle.wifeJoined and battle.turn >= WIFE_JOIN_TURN then
		battle.wifeJoined = true
		table.insert(battle.actors, newActor(WIFE_ID, "Dario's Wife", "Enemy", 12, 0, 1, 1, "DarioWifeIdle"))
		log(battle, {
			turn = battle.turn,
			kind = "Join",
			actorId = WIFE_ID,
			message = "Dario's wife joins the fight!",
		})
	end
end

function MockTutorialServer.StartTutorial(_request: RemoteContract.StartTutorialRequest): TutorialResponse
	local battle = current
	if battle and battle.outcome == "InProgress" then
		return ok(battle)
	end
	local fresh = newBattle()
	current = fresh
	return ok(fresh)
end

function MockTutorialServer.SubmitPrimaryAction(request: RemoteContract.SubmitPrimaryActionRequest): TutorialResponse
	local battle = current
	if not battle or battle.id ~= request.battleId then
		return reject("BattleNotFound", "That battle is no longer running.", battle)
	end
	if request.expectedRevision ~= battle.revision then
		return reject("StaleRevision", "The battle moved on. Showing the latest state.", battle)
	end
	if battle.outcome ~= "InProgress" then
		return reject("IllegalAction", "The fight is already over.", battle)
	end

	local player = findActor(battle, PLAYER_ID)
	assert(player, "mock battle has no player")
	local option: ActionOption? = nil
	for _, candidate in actions(battle) do
		if candidate.moveId == request.moveId then
			option = candidate
		end
	end
	if not option or not option.legality.canUse then
		return reject("IllegalAction", "You can't use that move right now.", battle)
	end

	local target: ActorState? = nil
	if #option.targetIds > 0 then
		local targetId = request.targetId or option.targetIds[1]
		if not table.find(option.targetIds, targetId) then
			return reject("IllegalAction", "That target can't be hit.", battle)
		end
		target = findActor(battle, targetId)
	end

	player.stamina -= option.staminaCost
	log(battle, {
		turn = battle.turn,
		kind = "Action",
		actorId = PLAYER_ID,
		targetId = if target then target.id else nil,
		moveId = request.moveId,
		message = `You use {option.label}!`,
	})
	if request.moveId == "Defend" then
		player.isDefending = true
		player.stamina = math.min(player.maxStamina, player.stamina + 1)
		log(battle, { turn = battle.turn, kind = "Guard", actorId = PLAYER_ID, message = "You brace yourself." })
	elseif target then
		local raw = if request.moveId == "HeavyStrike" then player.power * 2 else player.power
		dealDamage(battle, player, target, raw, request.moveId)
	end

	checkOutcome(battle)
	enemyPhase(battle)
	advanceTurn(battle)
	checkOutcome(battle)
	battle.revision += 1
	return ok(battle)
end

function MockTutorialServer.RetryTutorial(request: RemoteContract.RetryTutorialRequest): TutorialResponse
	local battle = current
	if not battle or battle.id ~= request.battleId then
		return reject("BattleNotFound", "That battle is no longer running.", battle)
	end
	if battle.outcome ~= "Defeat" then
		return reject("RetryUnavailable", "Retry is only available after a defeat.", battle)
	end
	local fresh = newBattle()
	current = fresh
	return ok(fresh)
end

function MockTutorialServer.ChooseOrigin(request: RemoteContract.ChooseOriginRequest): ChooseOriginResponse
	if not profile.tutorialCompleted then
		return { ok = false, code = "TutorialIncomplete", message = "Finish the tutorial first." }
	end
	if profile.origin ~= nil then
		return { ok = false, code = "OriginAlreadyChosen", message = "Your origin is already set." }
	end
	if request.origin ~= "Part1_Hamon" and request.origin ~= "Part3_Stand" then
		return { ok = false, code = "InvalidRequest", message = "Unknown origin." }
	end
	profile.origin = request.origin
	return { ok = true, profile = copyProfile() }
end

return MockTutorialServer
