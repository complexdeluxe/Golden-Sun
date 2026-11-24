--!strict

local Combat = require("../Contracts/CombatTypes")
local Tutorial = require("../Data/TutorialEncounter")

type ActorState = Combat.ActorState
type EnemyIntent = Combat.EnemyIntent
type ActionOption = Combat.ActionOption
type CombatLogEvent = Combat.CombatLogEvent

export type Battle = {
	id: string,
	revision: number,
	round: number,
	player: ActorState,
	dario: ActorState,
	wife: ActorState?,
	wifeQueued: boolean,
	wifeHealUsed: boolean,
	outcome: Combat.CombatOutcome,
	log: { CombatLogEvent },
}

local moves: { Combat.MoveId } = { "QuickStrike", "HeavyStrike", "Defend" }

local function addLog(
	battle: Battle,
	kind: index<CombatLogEvent, "kind">,
	message: string,
	actor: ActorState?,
	target: ActorState?,
	moveId: string?,
	amount: number?
)
	table.insert(battle.log, {
		turn = battle.round,
		kind = kind,
		message = message,
		actorId = if actor then actor.id else nil,
		targetId = if target then target.id else nil,
		moveId = moveId,
		amount = amount,
	})
end

local function orderedActors(battle: Battle): { ActorState }
	local actors: { ActorState } = { battle.player, battle.dario }
	if battle.wife then
		table.insert(actors, battle.wife)
	end
	local positions = { player = 1, dario = 2, wife = 3 } :: { [string]: number }
	table.sort(actors, function(left: ActorState, right: ActorState)
		if left.speed == right.speed then
			return positions[left.id] < positions[right.id]
		end
		return left.speed > right.speed
	end)
	return actors
end

local function intents(battle: Battle): { EnemyIntent }
	local result: { EnemyIntent } = {}
	if battle.outcome ~= "InProgress" then
		return result
	end
	for _, actor in orderedActors(battle) do
		if actor.team == "Player" or actor.hp <= 0 then
			continue
		end
		local support = actor.id == "wife" and not battle.wifeHealUsed and battle.dario.hp < battle.dario.maxHp
		local isDario = actor.id == "dario"
		table.insert(result, {
			actorId = actor.id,
			moveId = if support then "WifeSupport" elseif isDario then "DarioStrike" else "WifeCounterattack",
			label = if support then "Support" elseif isDario then "Dario’s Strike" else "Counterattack",
			targetId = if support then battle.dario.id else battle.player.id,
			landingTurn = battle.round,
			telegraphKind = "Attack" :: "Attack",
			estimatedPower = if support then Tutorial.wifeHeal elseif isDario then Tutorial.darioStrike else Tutorial.wifeStrike,
		})
	end
	return result
end

local function options(battle: Battle): { ActionOption }
	local result: { ActionOption } = {}
	if battle.outcome ~= "InProgress" then
		return result
	end
	local enemies = { battle.dario.id }
	if battle.wife and battle.wife.hp > 0 then
		table.insert(enemies, battle.wife.id)
	end
	for _, id in moves do
		local move = Tutorial.moves[id]
		local legality: Combat.ActionLegality
		if battle.player.stamina < move.cost then
			legality = { canUse = false :: false, disabledReason = "Needs " .. move.cost .. " Stamina" }
		else
			legality = { canUse = true :: true, disabledReason = nil }
		end
		table.insert(result, {
			moveId = id,
			label = move.label,
			staminaCost = move.cost,
			targetIds = if id == "Defend" then { battle.player.id } else table.clone(enemies),
			legality = legality,
		})
	end
	return result
end

local function snapshot(battle: Battle): Combat.CombatSnapshot
	local actors: { ActorState } = {}
	local queue: { Combat.TurnOrderEntry } = {}
	for _, actor in orderedActors(battle) do
		table.insert(actors, table.clone(actor))
		if battle.outcome == "InProgress" and actor.hp > 0 then
			table.insert(queue, { actorId = actor.id, speed = actor.speed })
		end
	end
	local log: { CombatLogEvent } = {}
	for _, event in battle.log do
		table.insert(log, table.clone(event))
	end
	return {
		battleId = battle.id,
		revision = battle.revision,
		turn = battle.round,
		playerActorId = battle.player.id,
		activeActorId = if battle.outcome == "InProgress" then battle.player.id else nil,
		actors = actors,
		turnOrder = queue,
		enemyIntents = intents(battle),
		actions = options(battle),
		log = log,
		outcome = battle.outcome,
	}
end

local function new(battleId: string): Battle
	return {
		id = battleId,
		revision = 1,
		round = 1,
		player = Tutorial.newPlayer(),
		dario = Tutorial.newDario(),
		wife = nil,
		wifeQueued = false,
		wifeHealUsed = false,
		outcome = "InProgress",
		log = {},
	}
end

local function strike(battle: Battle, actor: ActorState, target: ActorState, moveId: string, power: number)
	local guard = if target.isDefending then Tutorial.guard else 0
	local damage = math.min(target.hp, math.max(1, power + actor.power - target.armor - guard))
	target.hp -= damage
	addLog(battle, "Damage", actor.displayName .. " hits " .. target.displayName .. " for " .. damage .. ".", actor, target, moveId, damage)
	if target.hp == 0 then
		addLog(battle, "Defeated", target.displayName .. " is defeated.", target)
	end
end

local function closeBattle(battle: Battle, outcome: Combat.CombatOutcome)
	battle.outcome = outcome
	addLog(battle, "Outcome", if outcome == "Victory" then "The attackers retreat." else "You were defeated.")
end

local function apply(previous: Battle, request: Combat.ActionRequest): (Battle?, string?)
	if previous.outcome ~= "InProgress" then
		return nil, "The tutorial battle has ended."
	end
	local move = Tutorial.moves[request.moveId]
	if previous.player.stamina < move.cost then
		return nil, "Needs " .. move.cost .. " Stamina"
	end

	local targetId = request.targetId
	if request.moveId == "Defend" then
		if targetId ~= nil and targetId ~= previous.player.id then
			return nil, "Defend targets the player."
		end
	elseif targetId ~= previous.dario.id and (not previous.wife or previous.wife.id ~= targetId) then
		return nil, "Select a living enemy."
	end

	-- Validate and stage each turn without changing the current battle.
	local battle = table.clone(previous)
	battle.player = table.clone(previous.player)
	battle.dario = table.clone(previous.dario)
	battle.wife = if previous.wife then table.clone(previous.wife) else nil
	battle.log = table.clone(previous.log)
	battle.revision += 1
	local scheduled = intents(previous)
	local player = battle.player
	player.stamina -= move.cost
	if request.moveId == "Defend" then
		player.isDefending = true
		addLog(battle, "Guard", "You prepare to guard.", player, player, request.moveId)
	else
		local target = if battle.dario.id == targetId then battle.dario else battle.wife
		assert(target ~= nil)
		strike(battle, player, target, request.moveId, move.power)
		local fleeAt = if target.id == battle.dario.id then Tutorial.darioFleeAt else Tutorial.wifeFleeAt
		if target.hp <= fleeAt then
			if target.hp > 0 then
				addLog(battle, "Flee", target.displayName .. " retreats.", target)
			end
			closeBattle(battle, "Victory")
			return battle, nil
		end
	end

	if not battle.wife and battle.dario.hp <= Tutorial.joinAt then
		battle.wifeQueued = true
	end

	for _, intent in scheduled do
		local actor = if intent.actorId == battle.dario.id then battle.dario else battle.wife
		assert(actor ~= nil)
		battle.revision += 1
		if intent.moveId == "WifeSupport" then
			local healed = math.min(Tutorial.wifeHeal, battle.dario.maxHp - battle.dario.hp)
			battle.dario.hp += healed
			battle.wifeHealUsed = true
			addLog(battle, "Action", actor.displayName .. " restores " .. healed .. " HP.", actor, battle.dario, intent.moveId, healed)
		else
			strike(battle, actor, player, intent.moveId, intent.estimatedPower)
		end
		if player.hp == 0 then
			closeBattle(battle, "Defeat")
			return battle, nil
		end
	end

	battle.round += 1
	player.stamina = math.min(player.maxStamina, player.stamina + 1)
	player.isDefending = false
	if battle.wifeQueued and not battle.wife then
		battle.wife = Tutorial.newWife()
		battle.wifeQueued = false
		addLog(battle, "Join", "Dario’s wife enters the fight.", battle.wife)
	end
	return battle, nil
end

return table.freeze({ new = new, apply = apply, snapshot = snapshot })
