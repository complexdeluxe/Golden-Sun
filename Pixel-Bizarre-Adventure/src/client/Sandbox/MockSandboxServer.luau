--!strict
-- Client-only stand-in for the Phase 2 Black Sabbath sandbox server.
--
-- It answers the BlackSabbathRemotes calls with contract-shaped SandboxSnapshots
-- so Combat HUD v2 can be built and played in Studio before Codex's server
-- lands. Every number here is a placeholder, not the audited combat math. The
-- real rules live in src/shared/Core and src/server, and this mock is never used
-- once the BlackSabbathRemotes folder exists.
--
-- What it fakes, roughly:
--   You (Hamon) and a companion against Black Sabbath at Night.
--   Black Sabbath loops Lighter Strike -> Shadow Grab windup -> Shadow Grab
--   landing -> Fade Into Shadow. Hamon Interrupt or UV Flash can cancel the
--   windup. A 3-check High-Risk Heavy, Resolve / On Fire / Finisher, the shared
--   3-charge belt, companion tactics, assist and the one Guard Redirect all work.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatTypes = require(ReplicatedStorage.Shared.Contracts.CombatTypes)
local RemoteContract = require(ReplicatedStorage.Shared.Contracts.RemoteContract)

type Actor = CombatTypes.SandboxActorState
type Snapshot = CombatTypes.SandboxSnapshot
type Intent = CombatTypes.SandboxIntent
type Legality = CombatTypes.ActionLegality
type PrimaryOption = CombatTypes.PrimaryOption
type QteMode = CombatTypes.QteMode
type QteInput = CombatTypes.QteInput
type QteCheckResult = CombatTypes.QteCheckResult
type BeltItemId = CombatTypes.BeltItemId
type StatusId = CombatTypes.StatusId
type StatusView = CombatTypes.StatusView
type SandboxMoveId = CombatTypes.SandboxMoveId
type TacticMode = CombatTypes.TacticMode
type LogEvent = CombatTypes.SandboxLogEvent
type Response = RemoteContract.SandboxResponse
type ErrorCode = RemoteContract.SandboxErrorCode

local Limits = CombatTypes.Phase2Limits
local HighRisk = CombatTypes.HighRiskHeavy

local PLAYER_ID = "player"
local COMPANION_ID = "companion"
local SABBATH_ID = "blackSabbath"
local PARTY = { PLAYER_ID, COMPANION_ID }
local STEPS: { "LighterStrike" | "ShadowGrabWindup" | "ShadowGrabLanding" | "FadeIntoShadow" } =
	{ "LighterStrike", "ShadowGrabWindup", "ShadowGrabLanding", "FadeIntoShadow" }
local CHOICES: { QteInput } = { "Left", "Center", "Right" }

local ENEMY_DELAY = 0.9
-- Manual ring schedule, matching the server's provisional timing.
local RING_LEAD = 0.15
local RING_APPROACH = 1.15
local RING_WINDOW = 0.75
local RING_RESET = 0.30
local STAMINA_REGEN = 2
local DEFEND_TAKEN = 0.6
local BASE_DODGE = 8
local SMOKE_DODGE = 15

type MoveInfo = {
	label: string,
	scalingTag: CombatTypes.ScalingTag,
	cost: number,
	multiplier: number,
	qte: "None" | "Standard" | "HighRiskThreeCheck",
	resolveGain: number,
}

local MOVES: { [SandboxMoveId]: MoveInfo } = {
	BasicStrike = { label = "Basic Strike", scalingTag = "Physical", cost = 0, multiplier = 1, qte = "None", resolveGain = 12 },
	HeavyStrike = { label = "Heavy Strike", scalingTag = "Physical", cost = 3, multiplier = 1.5, qte = "Standard", resolveGain = 10 },
	HighRiskHeavy = { label = "High-Risk Heavy", scalingTag = "Hybrid", cost = 4, multiplier = HighRisk.baseMultiplier, qte = "HighRiskThreeCheck", resolveGain = 0 },
	Defend = { label = "Defend", scalingTag = "Physical", cost = 0, multiplier = 0, qte = "None", resolveGain = 5 },
	HamonInterrupt = { label = "Hamon Interrupt", scalingTag = "Special", cost = 2, multiplier = 0.8, qte = "None", resolveGain = 10 },
	Finisher = { label = "Finisher", scalingTag = "AutoBest", cost = 0, multiplier = 2.5, qte = "None", resolveGain = 0 },
}

local PLAYER_MOVES: { SandboxMoveId } = { "BasicStrike", "HeavyStrike", "HighRiskHeavy", "Defend", "HamonInterrupt", "Finisher" }
local COMPANION_MOVES: { SandboxMoveId } = { "BasicStrike", "HeavyStrike", "Defend", "Finisher" }

type ItemInfo = {
	label: string,
	stock: number,
	hp: number?,
	stamina: number?,
	resolve: number?,
	dodge: number?,
	removes: { StatusId }?,
	directHeal: boolean?,
	medKit: boolean?,
	uv: boolean?,
}

local ITEM_ORDER: { BeltItemId } =
	{ "MineralWater", "CapreseSalad", "MedKit", "CoffeeGum", "UVFlash", "SmokePellet", "PassioneEspresso", "SmellingSalts" }

local ITEMS: { [BeltItemId]: ItemInfo } = {
	MineralWater = { label = "Mineral Water", stock = 2, hp = 8, directHeal = true },
	CapreseSalad = { label = "Caprese Salad", stock = 1, hp = 14, directHeal = true },
	MedKit = { label = "Med-Kit", stock = 1, hp = 20, removes = { "Bleed", "Burn" }, medKit = true },
	CoffeeGum = { label = "Coffee Gum", stock = 1, stamina = 3 },
	UVFlash = { label = "UV Flash", stock = 1, uv = true },
	SmokePellet = { label = "Smoke Pellet", stock = 1, dodge = SMOKE_DODGE },
	PassioneEspresso = { label = "Passione Espresso", stock = 1, resolve = 15, stamina = 1 },
	SmellingSalts = { label = "Smelling Salts", stock = 1, removes = { "Stun" } },
}

type Pending = {
	actorId: string,
	moveId: SandboxMoveId,
	targetId: string,
	answers: { QteInput },
	starts: { number },
	opens: { number },
	closes: { number },
	manual: boolean,
}

type Battle = {
	id: string,
	revision: number,
	turn: number,
	level: number,
	stageTag: "Night" | "Neutral",
	qteMode: QteMode,
	actors: { Actor },
	activeIndex: number,
	step: number,
	grabCancelled: boolean,
	grabTargetId: string,
	retarget: string?,
	beltCharges: number,
	directHeals: number,
	medKitUsed: boolean,
	stock: { [BeltItemId]: number },
	tactic: TacticMode,
	redirectUses: number,
	assistUsedRound: boolean,
	exposure: CombatTypes.ExposureView?,
	prompt: CombatTypes.QtePrompt?,
	pending: Pending?,
	regularPrimaryDone: boolean,
	bonusUsedRound: { [string]: boolean },
	lowHpUsed: { [string]: boolean },
	smoke: { [string]: boolean },
	log: { LogEvent },
	outcome: CombatTypes.CombatOutcome,
	rng: Random,
	challengeCount: number,
}

local MockSandboxServer = {}

local current: Battle? = nil
local battleCount = 0
local listeners: { (Snapshot) -> () } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function legal(canUse: boolean, reason: string): Legality
	if canUse then
		return { canUse = true }
	end
	return { canUse = false, disabledReason = reason }
end

local function find(battle: Battle, id: string?): Actor?
	for _, actor in battle.actors do
		if actor.id == id then
			return actor
		end
	end
	return nil
end

local function get(battle: Battle, id: string): Actor
	local actor = find(battle, id)
	assert(actor, `unknown actor {id}`)
	return actor
end

local function alive(actor: Actor?): boolean
	return actor ~= nil and actor.hp > 0
end

local function shortName(battle: Battle, id: string): string
	if id == PLAYER_ID then
		return "You"
	end
	local actor = find(battle, id)
	return if actor then actor.displayName else id
end

-- "You use" / "Companion uses": the player's short name is "You".
local function verb(id: string, plural: string, singular: string): string
	return if id == PLAYER_ID then plural else singular
end

local function hasStatus(actor: Actor, id: StatusId): boolean
	for _, status in actor.statuses do
		if status.id == id then
			return true
		end
	end
	return false
end

local function removeStatus(actor: Actor, id: StatusId): boolean
	for index, status in actor.statuses do
		if status.id == id then
			table.remove(actor.statuses, index)
			return true
		end
	end
	return false
end

local STATUS_LABELS: { [StatusId]: string } = {
	Bleed = "Bleed",
	Burn = "Burn",
	Slow = "Slow",
	FogWound = "Fog Wound",
	AgeDown = "Age-Down",
	CoinBomb = "Coin Bomb",
	Stun = "Stun",
	Exposed = "Exposed (-15 Mit)",
	Fade = "Fade (+20 Dodge)",
}
local REMOVABLE: { [StatusId]: boolean } =
	{ Bleed = true, Burn = true, Slow = true, FogWound = true, AgeDown = true, CoinBomb = true }

local function addStatus(actor: Actor, id: StatusId, turns: number?)
	removeStatus(actor, id)
	table.insert(actor.statuses, {
		id = id,
		label = STATUS_LABELS[id],
		isRemovable = REMOVABLE[id] == true,
		turnsRemaining = turns,
	})
end

local function log(battle: Battle, event: LogEvent)
	table.insert(battle.log, event)
end

local function say(battle: Battle, kind: any, message: string, extra: { [string]: any }?)
	local event: { [string]: any } = { turn = battle.turn, kind = kind, message = message }
	if extra then
		for key, value in extra do
			event[key] = value
		end
	end
	log(battle, event :: any)
end

local function newActor(
	id: string,
	name: string,
	team: CombatTypes.Team,
	hp: number,
	maxStamina: number,
	speed: number,
	power: number,
	spriteKey: any
): Actor
	return {
		id = id,
		displayName = name,
		hp = hp,
		maxHp = hp,
		stamina = maxStamina - 2,
		maxStamina = maxStamina,
		armor = 0,
		speed = speed,
		power = power,
		isDefending = false,
		team = team,
		spriteKey = spriteKey,
		primaryAvailable = false,
		secondaryAvailable = false,
		bonusPrimaryAvailable = false,
		resolve = 0,
		resolveGainedThisTurn = 0,
		onFireTurnsRemaining = 0,
		finisherReady = false,
		dodgePercent = BASE_DODGE,
		precisionPercent = 90,
		statuses = {},
	}
end

local function stepName(battle: Battle)
	return STEPS[battle.step]
end

local function activeId(battle: Battle): string?
	if battle.outcome ~= "InProgress" then
		return nil
	end
	local order = { PLAYER_ID, COMPANION_ID, SABBATH_ID }
	return order[battle.activeIndex]
end

local function effectiveDodge(battle: Battle, actor: Actor): number
	local dodge = actor.dodgePercent
	if hasStatus(actor, "Fade") then
		dodge += Limits.FadeDodgePp
	end
	if battle.smoke[actor.id] then
		dodge += SMOKE_DODGE
	end
	return math.clamp(dodge, 0, 95)
end

local function currentIntent(battle: Battle): Intent?
	if battle.outcome ~= "InProgress" then
		return nil
	end
	local sabbath = get(battle, SABBATH_ID)
	if not alive(sabbath) then
		return nil
	end
	local step = stepName(battle)
	if step == "LighterStrike" then
		return {
			id = `bs-{battle.turn}-lighter`,
			actorId = SABBATH_ID,
			moveId = "LighterStrike",
			label = "Lighter Strike",
			targetId = battle.retarget or PLAYER_ID,
			landingTurn = battle.turn,
			telegraphKind = "Attack",
			estimatedPower = sabbath.power,
			targeting = "Single",
			stage = "Scheduled",
			offensiveInterruptible = false,
			uvCancelable = false,
		}
	elseif step == "ShadowGrabWindup" or step == "ShadowGrabLanding" then
		if battle.grabCancelled then
			return nil
		end
		local windup = step == "ShadowGrabWindup"
		return {
			id = `bs-grab-{if windup then battle.turn else battle.turn - 1}`,
			actorId = SABBATH_ID,
			moveId = "ShadowGrab",
			label = "Shadow Grab",
			targetId = battle.retarget or battle.grabTargetId,
			landingTurn = if windup then battle.turn + 1 else battle.turn,
			telegraphKind = "Heavy",
			estimatedPower = math.round(sabbath.power * Limits.ShadowGrabMultiplier),
			targeting = "Single",
			stage = if windup then "Windup" else "Landing",
			offensiveInterruptible = windup,
			uvCancelable = windup and battle.stageTag == "Night",
		}
	else
		return {
			id = `bs-{battle.turn}-fade`,
			actorId = SABBATH_ID,
			moveId = "FadeIntoShadow",
			label = "Fade Into Shadow",
			targetId = SABBATH_ID,
			landingTurn = battle.turn,
			telegraphKind = "Guard",
			estimatedPower = 0,
			targeting = "Single",
			stage = "Scheduled",
			offensiveInterruptible = false,
			uvCancelable = false,
		}
	end
end

-- Resolve ------------------------------------------------------------------

local function gainResolve(battle: Battle, actor: Actor, amount: number, reason: string)
	if amount == 0 or actor.team ~= "Player" or battle.outcome ~= "InProgress" then
		return
	end
	if amount > 0 then
		if actor.onFireTurnsRemaining > 0 then
			return -- Gains pause while On Fire.
		end
		amount = math.min(amount, Limits.ResolveGainPerTurn - actor.resolveGainedThisTurn)
		if amount <= 0 then
			return
		end
		actor.resolveGainedThisTurn += amount
	end
	local before = actor.resolve
	actor.resolve = math.clamp(actor.resolve + amount, 0, Limits.MaxResolve)
	local delta = actor.resolve - before
	if delta == 0 then
		return
	end
	say(battle, "Resolve", `{shortName(battle, actor.id)} Resolve {if delta > 0 then "+" else ""}{delta} ({reason}).`, {
		actorId = actor.id,
		resolveDelta = delta,
	})
	if actor.resolve >= Limits.MaxResolve and actor.onFireTurnsRemaining == 0 then
		actor.onFireTurnsRemaining = Limits.OnFireTurns
		actor.finisherReady = true
		say(battle, "Resolve", `{shortName(battle, actor.id)}: ON FIRE! Finisher ready.`, { actorId = actor.id })
	end
end

local function checkLowHp(battle: Battle, actor: Actor)
	if actor.team == "Player" and alive(actor) and not battle.lowHpUsed[actor.id] and actor.hp <= actor.maxHp * 0.3 then
		battle.lowHpUsed[actor.id] = true
		-- The low-HP boost ignores the per-turn cap.
		if actor.onFireTurnsRemaining == 0 then
			actor.resolveGainedThisTurn = math.max(0, actor.resolveGainedThisTurn - Limits.LowHpResolve)
			gainResolve(battle, actor, Limits.LowHpResolve, "low HP")
		end
	end
end

-- Damage -------------------------------------------------------------------

local function updateOutcome(battle: Battle)
	if battle.outcome ~= "InProgress" then
		return
	end
	if not alive(find(battle, SABBATH_ID)) then
		battle.outcome = "Victory"
		say(battle, "Outcome", "Black Sabbath dissolves into the dark. Victory!")
	elseif not alive(find(battle, PLAYER_ID)) and not alive(find(battle, COMPANION_ID)) then
		battle.outcome = "Defeat"
		say(battle, "Outcome", "Your party falls in the shadows.")
	end
end

local function dealDamage(battle: Battle, attacker: Actor, target: Actor, raw: number, moveId: string): number
	local amount = raw
	if attacker.onFireTurnsRemaining > 0 then
		amount *= 1.15
	end
	if hasStatus(target, "Exposed") then
		amount *= 1 + Limits.ExposedMitigationPp / 100
	end
	if target.isDefending then
		amount *= DEFEND_TAKEN
	end
	local final = math.max(1, math.round(amount))
	target.hp = math.max(0, target.hp - final)
	say(battle, "Damage", `{shortName(battle, attacker.id)} {verb(attacker.id, "hit", "hits")} {shortName(battle, target.id)} for {final}.`, {
		actorId = attacker.id,
		targetId = target.id,
		moveId = moveId,
		amount = final,
	})
	if not alive(target) then
		say(battle, "Defeated", `{shortName(battle, target.id)}: down!`, { targetId = target.id })
	end
	if target.team == "Player" then
		gainResolve(battle, target, 5, "took a hit")
		checkLowHp(battle, target)
	end
	updateOutcome(battle)
	return final
end

-- Exposure lasts through the party's next Primary.
local function consumeExposure(battle: Battle)
	local exposure = battle.exposure
	if exposure then
		battle.exposure = nil
		local target = find(battle, exposure.targetId)
		if target then
			removeStatus(target, "Exposed")
		end
	end
end

local function nextPartyActorAfter(battle: Battle, id: string): string?
	local start = table.find(PARTY, id) or 0
	for offset = 1, #PARTY do
		local candidate = PARTY[(start + offset - 1) % #PARTY + 1]
		if alive(find(battle, candidate)) then
			return candidate
		end
	end
	return nil
end

-- Turn flow ----------------------------------------------------------------

local advance: (battle: Battle) -> ()
local runEnemyTurn: (battle: Battle) -> ()
local broadcast: (battle: Battle) -> ()

local function startActorTurn(battle: Battle)
	local id = activeId(battle)
	if not id then
		return
	end
	local actor = get(battle, id)
	if not alive(actor) then
		advance(battle)
		return
	end
	battle.regularPrimaryDone = false
	actor.isDefending = false
	actor.resolveGainedThisTurn = 0
	actor.stamina = math.min(actor.maxStamina, actor.stamina + STAMINA_REGEN)

	-- Burn ticks at the start of the turn.
	for _, status in table.clone(actor.statuses) do
		if status.id == "Burn" then
			actor.hp = math.max(1, actor.hp - 2)
			say(battle, "Status", `Burn deals 2 to {shortName(battle, id)}.`, { targetId = id, amount = 2 })
		end
	end

	if actor.team == "Enemy" then
		actor.primaryAvailable = false
		actor.secondaryAvailable = false
		actor.bonusPrimaryAvailable = false
		task.delay(ENEMY_DELAY, function()
			if current == battle and battle.outcome == "InProgress" and activeId(battle) == SABBATH_ID then
				runEnemyTurn(battle)
			end
		end)
		return
	end

	actor.primaryAvailable = true
	actor.secondaryAvailable = true
	actor.bonusPrimaryAvailable = false
	if hasStatus(actor, "Stun") then
		actor.primaryAvailable = false
		say(battle, "Status", `{shortName(battle, id)}: Stunned, no Primary this turn.`, { targetId = id })
	end
	battle.smoke[id] = nil
end

local function tickActorStatuses(battle: Battle, actor: Actor)
	for index = #actor.statuses, 1, -1 do
		local status = actor.statuses[index]
		local turns = status.turnsRemaining
		if turns ~= nil and status.id ~= "Fade" then
			if turns <= 1 then
				table.remove(actor.statuses, index)
			else
				status.turnsRemaining = turns - 1
			end
		end
	end
	if actor.onFireTurnsRemaining > 0 then
		actor.onFireTurnsRemaining -= 1
		if actor.onFireTurnsRemaining == 0 then
			actor.resolve = 0
			actor.finisherReady = false
			say(battle, "Resolve", `{shortName(battle, actor.id)}: the Fire burns out.`, { actorId = actor.id })
		end
	end
end

function advance(battle: Battle)
	if battle.outcome ~= "InProgress" then
		return
	end
	local id = activeId(battle)
	if id then
		local actor = get(battle, id)
		actor.primaryAvailable = false
		actor.secondaryAvailable = false
		actor.bonusPrimaryAvailable = false
		if actor.team == "Player" then
			tickActorStatuses(battle, actor)
			if id == COMPANION_ID and battle.tactic == "Defensive" and alive(actor) then
				actor.isDefending = true
			elseif id == COMPANION_ID and battle.tactic == "Support" and alive(actor) then
				local player = get(battle, PLAYER_ID)
				if alive(player) and player.hp < player.maxHp then
					player.hp = math.min(player.maxHp, player.hp + 2)
					say(battle, "Assist", "Companion patches you up for 2 HP (Support).", { actorId = COMPANION_ID })
				end
			end
		end
	end
	battle.activeIndex += 1
	if battle.activeIndex > 3 then
		-- New round.
		battle.activeIndex = 1
		battle.turn += 1
		battle.step = battle.step % #STEPS + 1
		if stepName(battle) == "LighterStrike" then
			battle.grabCancelled = false
		end
		-- A Guard Redirect made during the windup carries into the landing.
		if stepName(battle) ~= "ShadowGrabLanding" then
			battle.retarget = nil
		end
		if stepName(battle) == "ShadowGrabWindup" then
			-- Black Sabbath grabs whoever has the least HP.
			local target = PLAYER_ID
			local companion = find(battle, COMPANION_ID)
			local player = get(battle, PLAYER_ID)
			if companion and alive(companion) and (companion.hp < player.hp or not alive(player)) then
				target = COMPANION_ID
			end
			battle.grabTargetId = target
		end
		battle.assistUsedRound = false
		table.clear(battle.bonusUsedRound)
	end
	startActorTurn(battle)
end

function runEnemyTurn(battle: Battle)
	local sabbath = get(battle, SABBATH_ID)
	local step = stepName(battle)
	-- Fade wears off when Black Sabbath acts again.
	if removeStatus(sabbath, "Fade") then
		say(battle, "Status", "Black Sabbath steps out of the shadows. Fade ends.", { targetId = SABBATH_ID })
	end
	local intent = currentIntent(battle)
	if step == "LighterStrike" and intent then
		local target = get(battle, intent.targetId)
		if not alive(target) then
			target = get(battle, nextPartyActorAfter(battle, intent.targetId) or PLAYER_ID)
		end
		say(battle, "Action", "Black Sabbath swings a burning lighter!", { actorId = SABBATH_ID, moveId = "LighterStrike" })
		if battle.rng:NextInteger(1, 100) <= effectiveDodge(battle, target) then
			say(battle, "Dodged", `{shortName(battle, target.id)} dodged the Lighter Strike!`, { targetId = target.id, actorId = SABBATH_ID })
		else
			dealDamage(battle, sabbath, target, sabbath.power, "LighterStrike")
			if alive(target) then
				addStatus(target, "Burn", 2)
				say(battle, "Status", `{shortName(battle, target.id)}: Burning!`, { targetId = target.id })
			end
		end
	elseif step == "ShadowGrabWindup" then
		if intent then
			say(battle, "Action", `Black Sabbath sinks into the shadows, reaching for {shortName(battle, intent.targetId)}...`, {
				actorId = SABBATH_ID,
				intentId = intent.id,
			})
		else
			say(battle, "Action", "Black Sabbath reels, its grab broken.", { actorId = SABBATH_ID })
		end
	elseif step == "ShadowGrabLanding" then
		if intent then
			local target = get(battle, intent.targetId)
			say(battle, "Action", "SHADOW GRAB!", { actorId = SABBATH_ID, moveId = "ShadowGrab", intentId = intent.id })
			if alive(target) then
				dealDamage(battle, sabbath, target, sabbath.power * Limits.ShadowGrabMultiplier, "ShadowGrab")
				if alive(target) and not target.isDefending then
					addStatus(target, "Stun", 1)
					say(battle, "Status", `{shortName(battle, target.id)}: Stunned!`, { targetId = target.id })
				end
			end
		else
			say(battle, "Action", "Black Sabbath gathers itself in the dark.", { actorId = SABBATH_ID })
		end
	else
		addStatus(sabbath, "Fade", 1)
		say(battle, "Status", "Black Sabbath fades into shadow: +20 Dodge.", { targetId = SABBATH_ID })
	end
	battle.revision += 1
	advance(battle)
	broadcast(battle)
end

-- Options ------------------------------------------------------------------

local function partyActive(battle: Battle): Actor?
	local id = activeId(battle)
	local actor = if id then find(battle, id) else nil
	if actor and actor.team == "Player" then
		return actor
	end
	return nil
end

local function primaryReason(battle: Battle, actor: Actor?): string?
	if battle.outcome ~= "InProgress" then
		return "The fight is over."
	end
	if battle.prompt then
		return "Finish the QTE first."
	end
	if not actor then
		return "Black Sabbath is acting."
	end
	if hasStatus(actor, "Stun") and not battle.regularPrimaryDone then
		return "Stunned: no Primary this turn."
	end
	if not actor.primaryAvailable and not actor.bonusPrimaryAvailable then
		return "Primary already used this turn."
	end
	return nil
end

local function primaryOptions(battle: Battle): { PrimaryOption }
	local actor = partyActive(battle)
	local moves = if actor and actor.id == COMPANION_ID then COMPANION_MOVES else PLAYER_MOVES
	local sabbath = get(battle, SABBATH_ID)
	local intent = currentIntent(battle)
	local baseReason = primaryReason(battle, actor)
	local slot: CombatTypes.PrimarySlot = if actor and not actor.primaryAvailable and actor.bonusPrimaryAvailable
		then "BonusPrimary"
		else "Primary"
	local list: { PrimaryOption } = {}
	for _, moveId in moves do
		local info = MOVES[moveId]
		local reason = baseReason
		if not reason and actor then
			if actor.stamina < info.cost then
				reason = `Needs {info.cost} Stamina.`
			elseif moveId == "Finisher" and not actor.finisherReady then
				reason = "Fill Resolve to 100 first."
			elseif moveId == "HamonInterrupt" and not (intent and intent.offensiveInterruptible) then
				reason = "Only during a Shadow Grab windup."
			elseif moveId == "Defend" and slot == "BonusPrimary" then
				reason = "Bonus Primary must attack."
			end
		end
		local dodge = effectiveDodge(battle, sabbath)
		local targets: { CombatTypes.TargetOdds } = {}
		if moveId ~= "Defend" then
			table.insert(targets, {
				targetId = SABBATH_ID,
				legality = legal(reason == nil and alive(sabbath), reason or "No target."),
				effectiveDodgePercent = dodge,
				hitIfExecutedPercent = 100 - dodge,
				interruptIfExecutedPercent = if moveId == "HamonInterrupt" then math.max(0, 85 - dodge) else nil,
			})
		end
		local option: PrimaryOption = {
			moveId = moveId,
			label = info.label,
			scalingTag = info.scalingTag,
			staminaCost = info.cost,
			slot = slot,
			legality = legal(reason == nil, reason or ""),
			targets = targets,
			qte = info.qte,
			effectiveQteMode = if info.qte == "HighRiskThreeCheck"
				then (if battle.qteMode == "Manual" then "Manual" else "UntimedCue")
				elseif info.qte == "Standard" then (if battle.qteMode == "Manual" then "Manual" else "AutoGood")
				else nil,
		}
		table.insert(list, option)
	end
	return list
end

local function secondaryReason(battle: Battle, actor: Actor?): string?
	if battle.outcome ~= "InProgress" then
		return "The fight is over."
	end
	if battle.prompt then
		return "Finish the QTE first."
	end
	if not actor then
		return "Black Sabbath is acting."
	end
	if not actor.secondaryAvailable then
		return "Secondary already used this turn."
	end
	return nil
end

local function itemPreview(battle: Battle, itemId: BeltItemId, target: Actor, baseReason: string?): CombatTypes.BeltPreview
	local info = ITEMS[itemId]
	local reason = baseReason
	local intent = currentIntent(battle)
	local preview: CombatTypes.BeltPreview = {
		targetId = target.id,
		legality = { canUse = true },
		summary = "",
	}
	local parts: { string } = {}
	if info.uv then
		local eligible = intent ~= nil and intent.uvCancelable
		if not reason and not eligible then
			reason = "No Shadow windup to cancel."
		end
		if eligible and intent then
			preview.cancelsIntentId = intent.id
		end
		table.insert(parts, if eligible and intent then `Cancels {intent.label}` else "Cancels a Shadow windup")
	else
		if not alive(target) and not reason then
			reason = "Target is down."
		end
		if info.hp then
			local gain = math.min(info.hp, target.maxHp - target.hp)
			preview.hpGain = gain
			table.insert(parts, `+{gain} HP`)
			if not reason and info.directHeal and battle.directHeals <= 0 then
				reason = "No direct heals left this fight."
			elseif not reason and info.medKit and battle.medKitUsed then
				reason = "Med-Kit already used this fight."
			elseif not reason and gain <= 0 and not info.removes then
				reason = "Already at full HP."
			end
		end
		if info.stamina then
			local gain = math.min(info.stamina, target.maxStamina - target.stamina)
			preview.staminaGain = gain
			table.insert(parts, `+{gain} STA`)
			if not reason and gain <= 0 and not info.resolve then
				reason = "Stamina is already full."
			end
		end
		if info.resolve then
			local room = if target.onFireTurnsRemaining > 0
				then 0
				else math.min(Limits.ResolveGainPerTurn - target.resolveGainedThisTurn, Limits.MaxResolve - target.resolve)
			local gain = math.max(0, math.min(info.resolve, room))
			preview.resolveGain = gain
			table.insert(parts, `+{gain} Resolve`)
		end
		if info.dodge then
			preview.dodgeGainPp = info.dodge
			table.insert(parts, `+{info.dodge} Dodge`)
		end
		if info.removes then
			preview.removes = info.removes
			local present = {}
			for _, id in info.removes do
				if hasStatus(target, id) then
					table.insert(present, STATUS_LABELS[id])
				end
			end
			if #present > 0 then
				table.insert(parts, `removes {table.concat(present, ", ")}`)
			elseif not info.hp and not reason then
				reason = `Nothing to cure on {shortName(battle, target.id)}.`
			end
		end
	end
	preview.summary = table.concat(parts, ", ")
	preview.legality = legal(reason == nil, reason or "")
	return preview
end

local function beltView(battle: Battle): CombatTypes.PartyBelt
	local actor = partyActive(battle)
	local base = secondaryReason(battle, actor)
	if not base and battle.beltCharges <= 0 then
		base = "No belt charges left."
	end
	local items: { CombatTypes.BeltItemView } = {}
	for _, itemId in ITEM_ORDER do
		local info = ITEMS[itemId]
		local stock = battle.stock[itemId] or 0
		local reason = base
		if not reason and stock <= 0 then
			reason = "None left."
		end
		local previews: { CombatTypes.BeltPreview } = {}
		if info.uv then
			table.insert(previews, itemPreview(battle, itemId, get(battle, SABBATH_ID), reason))
		else
			for _, id in PARTY do
				local target = find(battle, id)
				if target then
					table.insert(previews, itemPreview(battle, itemId, target, reason))
				end
			end
		end
		local anyLegal = false
		for _, preview in previews do
			if preview.legality.canUse then
				anyLegal = true
			end
		end
		if not reason and not anyLegal and previews[1] then
			reason = previews[1].legality.disabledReason
		end
		table.insert(items, {
			itemId = itemId,
			label = info.label,
			stock = stock,
			legality = legal(reason == nil, reason or ""),
			targets = previews,
		})
	end
	return {
		beltChargesRemaining = battle.beltCharges,
		directHealsRemaining = battle.directHeals,
		medKitUsed = battle.medKitUsed,
		items = items,
	}
end

local function companionView(battle: Battle): CombatTypes.CompanionView?
	local companion = find(battle, COMPANION_ID)
	if not companion then
		return nil
	end
	local actor = partyActive(battle)
	local base = secondaryReason(battle, actor)
	if not base and not alive(companion) then
		base = "Your companion is down."
	end
	local view: CombatTypes.CompanionView = {
		actorId = COMPANION_ID,
		tacticMode = battle.tactic,
		tacticLegality = legal(base == nil, base or ""),
		assistAvailableThisRound = alive(companion) and not battle.assistUsedRound,
	}
	local intent = currentIntent(battle)
	if intent and intent.telegraphKind ~= "Guard" and intent.targeting == "Single" and intent.targetId ~= SABBATH_ID then
		local reason = base
		if not reason and battle.redirectUses <= 0 then
			reason = "Guard Redirect already used this fight."
		end
		local targets: { CombatTypes.RedirectTarget } = {}
		for _, id in PARTY do
			local recipient = find(battle, id)
			if recipient and id ~= intent.targetId then
				local recipientReason = reason
				if not recipientReason and not alive(recipient) then
					recipientReason = "They're down."
				end
				table.insert(targets, {
					recipientId = id,
					recipientIsDefending = recipient.isDefending,
					legality = legal(recipientReason == nil, recipientReason or ""),
				})
			end
		end
		view.redirect = {
			intentId = intent.id,
			originalTargetId = intent.targetId,
			usesRemaining = battle.redirectUses,
			legality = legal(reason == nil, reason or ""),
			targets = targets,
		}
	end
	return view
end

local function copyActor(actor: Actor): Actor
	local copy = table.clone(actor)
	local statuses: { StatusView } = {}
	for _, status in actor.statuses do
		table.insert(statuses, table.clone(status))
	end
	copy.statuses = statuses
	return copy
end

local function copyPrompt(prompt: CombatTypes.QtePrompt): CombatTypes.QtePrompt
	local copy = table.clone(prompt :: any)
	copy.checkResults = table.clone(prompt.checkResults)
	return copy :: CombatTypes.QtePrompt
end

local function snapshotOf(battle: Battle): Snapshot
	local actors: { Actor } = {}
	local order: { CombatTypes.TurnOrderEntry } = {}
	for _, actor in battle.actors do
		table.insert(actors, copyActor(actor))
		if alive(actor) then
			table.insert(order, { actorId = actor.id, speed = actor.speed })
		end
	end
	local intent = currentIntent(battle)
	local actor = partyActive(battle)
	local endReason: string? = nil
	if battle.outcome ~= "InProgress" then
		endReason = "The fight is over."
	elseif battle.prompt then
		endReason = "Finish the QTE first."
	elseif not actor then
		endReason = "Black Sabbath is acting."
	else
		-- End Turn is only a skip for a fighter with no usable Primary (for
		-- example Stunned). Otherwise the Primary itself ends the turn.
		for _, option in primaryOptions(battle) do
			if option.legality.canUse then
				endReason = "Taking a Primary ends your turn."
			end
		end
	end
	local log: { LogEvent } = {}
	for _, event in battle.log do
		table.insert(log, table.clone(event))
	end
	local prompt = battle.prompt
	return {
		battleId = battle.id,
		revision = battle.revision,
		turn = battle.turn,
		playerActorId = PLAYER_ID,
		activeActorId = activeId(battle),
		actors = actors,
		turnOrder = order,
		enemyIntents = if intent then { intent } else {},
		primaryOptions = primaryOptions(battle),
		endTurnLegality = legal(endReason == nil, endReason or ""),
		belt = beltView(battle),
		companion = companionView(battle),
		exposure = if battle.exposure then table.clone(battle.exposure) else nil,
		qteMode = battle.qteMode,
		qtePrompt = if prompt then copyPrompt(prompt) else nil,
		stageTag = battle.stageTag,
		blackSabbathStep = stepName(battle),
		log = log,
		outcome = battle.outcome,
	}
end

function broadcast(battle: Battle)
	if current ~= battle then
		return
	end
	local snapshot = snapshotOf(battle)
	for _, listener in listeners do
		task.spawn(listener, snapshot)
	end
end

local function ok(battle: Battle): Response
	return { ok = true, snapshot = snapshotOf(battle) }
end

local function reject(code: ErrorCode, message: string): Response
	local battle = current
	return { ok = false, code = code, message = message, snapshot = if battle then snapshotOf(battle) else nil }
end

local function checkBattle(request: any, needsRevision: boolean): (Battle?, Response?)
	local battle = current
	if type(request) ~= "table" then
		return nil, reject("InvalidRequest", "Bad request.")
	end
	if not battle or request.battleId ~= battle.id then
		return nil, reject("BattleNotFound", "That battle isn't running anymore.")
	end
	if needsRevision and request.expectedRevision ~= battle.revision then
		return nil, reject("StaleRevision", "The battle changed. Showing the latest state.")
	end
	return battle, nil
end

-- After the regular Primary or a Secondary, end the turn automatically once
-- there is nothing left to do.
local function maybeAutoAdvance(battle: Battle)
	local actor = partyActive(battle)
	if actor and battle.outcome == "InProgress" and not battle.prompt then
		if not actor.primaryAvailable and not actor.secondaryAvailable and not actor.bonusPrimaryAvailable then
			advance(battle)
		end
	end
end

-- Attacks ------------------------------------------------------------------

local function finishPrimary(battle: Battle, actor: Actor, slot: CombatTypes.PrimarySlot)
	if slot == "Primary" then
		battle.regularPrimaryDone = true
	end
	actor.bonusPrimaryAvailable = actor.bonusPrimaryAvailable and slot ~= "BonusPrimary"
	-- A Primary ends the turn (after any Bonus Primary it earned).
	if battle.outcome == "InProgress" and partyActive(battle) == actor and not actor.bonusPrimaryAvailable then
		advance(battle)
	end
end

local function strike(battle: Battle, actor: Actor, moveId: SandboxMoveId, target: Actor, multiplier: number): boolean
	if battle.rng:NextInteger(1, 100) <= effectiveDodge(battle, target) then
		say(battle, "Dodged", `{shortName(battle, target.id)} dodged {MOVES[moveId].label}!`, {
			actorId = actor.id,
			targetId = target.id,
			moveId = moveId,
		})
		return false
	end
	local followUp = battle.exposure and battle.exposure.exposedFollowUpActorId == actor.id
	if actor.id == COMPANION_ID and battle.tactic == "Aggressive" then
		multiplier *= 1.1
	end
	dealDamage(battle, actor, target, actor.power * multiplier, moveId)
	if followUp then
		say(battle, "Status", `{shortName(battle, actor.id)} {verb(actor.id, "land", "lands")} the boosted follow-up on the Exposed target!`, {
			actorId = actor.id,
			targetId = target.id,
		})
	end
	return true
end

local function resolveQte(battle: Battle)
	local pending = battle.pending
	local prompt = battle.prompt
	if not pending or not prompt then
		return
	end
	battle.pending = nil
	battle.prompt = nil
	local actor = get(battle, pending.actorId)
	local target = get(battle, pending.targetId)
	local grade = 0
	for _, result in prompt.checkResults do
		if result == "Hit" then
			grade += 1
		end
	end
	local slot: CombatTypes.PrimarySlot = if battle.regularPrimaryDone then "BonusPrimary" else "Primary"

	if pending.moveId == "HighRiskHeavy" then
		if grade == 0 then
			say(battle, "FailedQTE_0of3", "0/3 - missed timing! The High-Risk Heavy whiffs.", {
				actorId = actor.id,
				targetId = target.id,
				moveId = pending.moveId,
				qteGrade = 0,
			})
			gainResolve(battle, actor, HighRisk.resolveOnPartialOrFailed, "missed timing")
		else
			local band = HighRisk.timingByGrade[grade] or 0
			say(battle, "Action", `High-Risk Heavy: {grade}/3 checks.`, { actorId = actor.id, moveId = pending.moveId, qteGrade = grade })
			local landed = strike(battle, actor, pending.moveId, target, HighRisk.baseMultiplier * band)
			if grade == 3 and landed then
				gainResolve(battle, actor, HighRisk.resolveOnLandedFull, "perfect High-Risk Heavy")
				if not battle.bonusUsedRound[actor.id] and slot == "Primary" then
					actor.bonusPrimaryAvailable = true
					battle.bonusUsedRound[actor.id] = true
					say(battle, "Action", `{shortName(battle, actor.id)}: Bonus Primary earned!`, { actorId = actor.id })
				end
				local companion = find(battle, COMPANION_ID)
				if pending.manual and alive(companion) and not battle.assistUsedRound and alive(target) and companion then
					battle.assistUsedRound = true
					local amount = math.max(1, math.round(actor.power * HighRisk.baseMultiplier * Limits.ManualAssistStrength))
					target.hp = math.max(0, target.hp - amount)
					say(battle, "Assist", `Companion assist (25%)! +{amount} damage.`, {
						actorId = COMPANION_ID,
						targetId = target.id,
						amount = amount,
					})
					updateOutcome(battle)
				end
			elseif grade == 3 then
				-- Dodged 3/3 grants zero attack Resolve.
			else
				gainResolve(battle, actor, HighRisk.resolveOnPartialOrFailed, "partial timing")
			end
		end
	else
		-- Standard single-check Heavy: a hit is full power, a miss is half.
		local multiplier = MOVES[pending.moveId].multiplier * (if grade >= 1 then 1 else 0.5)
		if strike(battle, actor, pending.moveId, target, multiplier) then
			gainResolve(battle, actor, MOVES[pending.moveId].resolveGain, "hit")
		end
	end
	if battle.exposure and battle.exposure.exposedFollowUpActorId == actor.id then
		consumeExposure(battle)
	end
	battle.revision += 1
	finishPrimary(battle, actor, slot)
end

local function startQte(battle: Battle, actor: Actor, moveId: SandboxMoveId, target: Actor)
	local info = MOVES[moveId]
	-- Untimed cues only exist for the tagged High-Risk Heavy; a Standard check
	-- only runs in Manual mode.
	local mode: QteMode = if battle.qteMode == "Manual" then "Manual" else "UntimedCue"
	local count = if info.qte == "HighRiskThreeCheck" then 3 else 1
	battle.challengeCount += 1
	local id = `qte-{battle.id}-{battle.challengeCount}`
	local answers: { QteInput } = {}
	local starts: { number } = {}
	local overlaps: { number } = {}
	local opens: { number } = {}
	local closes: { number } = {}
	local results: { QteCheckResult } = {}
	local start = now() + RING_LEAD
	for index = 1, count do
		answers[index] = CHOICES[battle.rng:NextInteger(1, #CHOICES)]
		starts[index] = start
		overlaps[index] = start + RING_APPROACH
		opens[index] = overlaps[index] - RING_WINDOW / 2
		closes[index] = overlaps[index] + RING_WINDOW / 2
		results[index] = "Pending"
		start = closes[index] + RING_RESET
	end
	battle.pending = {
		actorId = actor.id,
		moveId = moveId,
		targetId = target.id,
		answers = answers,
		starts = starts,
		opens = opens,
		closes = closes,
		manual = mode == "Manual",
	}
	local kind: "Standard" | "HighRiskThreeCheck" = if count == 3 then "HighRiskThreeCheck" else "Standard"
	if mode == "Manual" then
		local checks: { CombatTypes.ManualQteCheck } = {}
		for index = 1, count do
			table.insert(checks, {
				index = index,
				approachStartsAtServerTime = starts[index],
				overlapAtServerTime = overlaps[index],
				opensAtServerTime = opens[index],
				closesAtServerTime = closes[index],
			})
		end
		battle.prompt = { id = id, mode = "Manual", kind = kind, checks = checks, checkResults = results, nextCheckIndex = 1 }
		-- Expire each window the player lets pass.
		for index = 1, count do
			task.delay(closes[index] - now() + 0.05, function()
				local prompt = battle.prompt
				if current == battle and prompt and prompt.id == id and prompt.checkResults[index] == "Pending" then
					prompt.checkResults[index] = "Miss"
					prompt.nextCheckIndex = if index < count then index + 1 else nil
					if index >= count then
						resolveQte(battle)
					else
						battle.revision += 1
					end
					broadcast(battle)
				end
			end)
		end
	else
		-- Untimed cue (and Auto-Good for this tagged attack): read the cue, no clock.
		local checks: { CombatTypes.UntimedQteCheck } = {}
		for index = 1, count do
			table.insert(checks, {
				index = index,
				prompt = `Cue: {string.upper(answers[index])}`,
				choices = CHOICES,
			})
		end
		battle.prompt = {
			id = id,
			mode = "UntimedCue",
			kind = "HighRiskThreeCheck",
			checks = checks,
			checkResults = results,
			nextCheckIndex = 1,
		}
	end
end

-- Public API: mirrors the BlackSabbathRemotes -------------------------------

function MockSandboxServer.onChanged(listener: (Snapshot) -> ())
	table.insert(listeners, listener)
end

function MockSandboxServer.StartSandbox(request: RemoteContract.StartSandboxRequest): Response
	battleCount += 1
	local level = if request.level == 50 then 50 else 10
	local scale = if level == 50 then 3 else 1
	local battle: Battle = {
		id = `sandbox-mock-{battleCount}`,
		revision = 1,
		turn = 1,
		level = level,
		stageTag = if request.stageTag == "Neutral" then "Neutral" else "Night",
		qteMode = request.qteMode or "Manual",
		actors = {
			newActor(PLAYER_ID, "You", "Player", 48 * scale, 6, 12, 7 * scale, "PlayerIdle"),
			newActor(COMPANION_ID, "Companion", "Player", 36 * scale, 5, 10, 5 * scale, "CompanionIdle"),
			newActor(SABBATH_ID, "Black Sabbath", "Enemy", 110 * scale, 6, 8, 8 * scale, "BlackSabbathIdle"),
		},
		activeIndex = 1,
		step = 1,
		grabCancelled = false,
		grabTargetId = PLAYER_ID,
		retarget = nil,
		beltCharges = Limits.PartyBeltCharges,
		directHeals = Limits.DirectHealsPerFight,
		medKitUsed = false,
		stock = {},
		tactic = "Aggressive",
		redirectUses = Limits.CompanionRedirectsPerFight,
		assistUsedRound = false,
		exposure = nil,
		prompt = nil,
		pending = nil,
		regularPrimaryDone = false,
		bonusUsedRound = {},
		lowHpUsed = {},
		smoke = {},
		log = {},
		outcome = "InProgress",
		rng = Random.new(1234 + battleCount),
		challengeCount = 0,
	}
	get(battle, SABBATH_ID).dodgePercent = 12
	for itemId, info in ITEMS do
		battle.stock[itemId] = info.stock
	end
	current = battle
	say(battle, "Action", "Night falls. Black Sabbath rises from the shadow of the arrow!")
	startActorTurn(battle)
	return ok(battle)
end

function MockSandboxServer.GetSandboxSnapshot(request: RemoteContract.SandboxBattleRef): Response
	local battle, failure = checkBattle(request, false)
	if not battle then
		return failure :: Response
	end
	return ok(battle)
end

function MockSandboxServer.SetSandboxQteMode(request: RemoteContract.SandboxQteModeRequest): Response
	local battle, failure = checkBattle(request, true)
	if not battle then
		return failure :: Response
	end
	if battle.prompt then
		return reject("QtePending", "Finish the QTE first.")
	end
	if request.qteMode ~= "Manual" and request.qteMode ~= "AutoGood" and request.qteMode ~= "UntimedCue" then
		return reject("InvalidRequest", "Unknown QTE mode.")
	end
	battle.qteMode = request.qteMode
	battle.revision += 1
	return ok(battle)
end

function MockSandboxServer.SubmitSandboxPrimary(request: RemoteContract.SandboxPrimaryRequest): Response
	local battle, failure = checkBattle(request, true)
	if not battle then
		return failure :: Response
	end
	if battle.prompt then
		return reject("QtePending", "Finish the QTE first.")
	end
	local actor = partyActive(battle)
	if not actor or actor.id ~= request.actorId then
		return reject("IllegalAction", "It isn't that fighter's turn.")
	end
	local chosen: PrimaryOption? = nil
	for _, option in primaryOptions(battle) do
		if option.moveId == request.moveId then
			chosen = option
		end
	end
	if not chosen then
		return reject("IllegalAction", "That move isn't available.")
	end
	if not chosen.legality.canUse then
		return reject("IllegalAction", chosen.legality.disabledReason or "Can't use that now.")
	end
	if chosen.slot ~= request.slot then
		return reject("IllegalAction", "That slot isn't available.")
	end
	local info = MOVES[chosen.moveId]
	local slot = chosen.slot
	actor.stamina -= info.cost
	if slot == "Primary" then
		actor.primaryAvailable = false
	else
		actor.bonusPrimaryAvailable = false
	end
	local sabbath = get(battle, SABBATH_ID)
	say(battle, "Action", `{shortName(battle, actor.id)} {verb(actor.id, "use", "uses")} {info.label}{if slot == "BonusPrimary" then " (Bonus)" else ""}.`, {
		actorId = actor.id,
		moveId = chosen.moveId,
	})

	if chosen.moveId == "Defend" then
		actor.isDefending = true
		say(battle, "Guard", `{shortName(battle, actor.id)} {verb(actor.id, "brace", "braces")} to Guard.`, { actorId = actor.id })
		gainResolve(battle, actor, info.resolveGain, "guard")
	elseif info.qte == "HighRiskThreeCheck" or (info.qte == "Standard" and battle.qteMode == "Manual") then
		startQte(battle, actor, chosen.moveId, sabbath)
		battle.revision += 1
		return ok(battle)
	elseif chosen.moveId == "HamonInterrupt" then
		local intent = currentIntent(battle)
		local chance = chosen.targets[1] and chosen.targets[1].interruptIfExecutedPercent or 0
		if intent and battle.rng:NextInteger(1, 100) <= chance then
			battle.grabCancelled = true
			say(battle, "Interrupt", "Hamon Overdrive breaks the Shadow Grab!", {
				actorId = actor.id,
				targetId = SABBATH_ID,
				intentId = intent.id,
			})
			dealDamage(battle, actor, sabbath, actor.power * info.multiplier, chosen.moveId)
			gainResolve(battle, actor, info.resolveGain, "interrupt")
			if alive(sabbath) then
				addStatus(sabbath, "Exposed")
				local followUp = nextPartyActorAfter(battle, actor.id)
				battle.exposure = {
					targetId = SABBATH_ID,
					mitigationPenaltyPp = Limits.ExposedMitigationPp,
					exposedFollowUpActorId = if followUp ~= actor.id then followUp else nil,
				}
				say(battle, "Status", "Black Sabbath is Exposed (-15 Mitigation).", { targetId = SABBATH_ID })
			end
		else
			say(battle, "Dodged", "Black Sabbath slips the Hamon Interrupt!", { actorId = actor.id, targetId = SABBATH_ID })
		end
	elseif chosen.moveId == "Finisher" then
		strike(battle, actor, chosen.moveId, sabbath, info.multiplier)
		actor.onFireTurnsRemaining = 0
		actor.finisherReady = false
		actor.resolve = 0
		say(battle, "Resolve", `{shortName(battle, actor.id)} {verb(actor.id, "spend your", "spends their")} Fire on the Finisher.`, { actorId = actor.id })
	else
		if strike(battle, actor, chosen.moveId, sabbath, info.multiplier) then
			gainResolve(battle, actor, info.resolveGain, "hit")
		end
		if battle.exposure and battle.exposure.exposedFollowUpActorId == actor.id then
			consumeExposure(battle)
		end
	end
	battle.revision += 1
	finishPrimary(battle, actor, slot)
	return ok(battle)
end

function MockSandboxServer.SubmitSandboxSecondary(request: RemoteContract.SandboxSecondaryRequest): Response
	local battle, failure = checkBattle(request, true)
	if not battle then
		return failure :: Response
	end
	if battle.prompt then
		return reject("QtePending", "Finish the QTE first.")
	end
	local actor = partyActive(battle)
	if not actor or actor.id ~= request.actorId then
		return reject("IllegalAction", "It isn't that fighter's turn.")
	end
	local raw = request :: any

	if raw.kind == "EndTurn" then
		local snapshot = snapshotOf(battle)
		if not snapshot.endTurnLegality.canUse then
			return reject("IllegalAction", snapshot.endTurnLegality.disabledReason or "Can't end the turn yet.")
		end
		say(battle, "Action", `{shortName(battle, actor.id)} {verb(actor.id, "end your", "ends their")} turn.`, { actorId = actor.id })
		advance(battle)
		battle.revision += 1
		return ok(battle)
	end

	local reason = secondaryReason(battle, actor)
	if reason then
		return reject("IllegalAction", reason)
	end

	if raw.kind == "UseBeltItem" then
		local itemId = raw.itemId :: BeltItemId
		local view: CombatTypes.BeltItemView? = nil
		for _, item in beltView(battle).items do
			if item.itemId == itemId then
				view = item
			end
		end
		if not view then
			return reject("IllegalAction", "That item isn't on your belt.")
		end
		local preview: CombatTypes.BeltPreview? = nil
		for _, candidate in view.targets do
			if candidate.targetId == raw.targetId then
				preview = candidate
			end
		end
		if not preview then
			return reject("IllegalAction", "Can't use that item on that target.")
		end
		if not preview.legality.canUse then
			return reject("IllegalAction", preview.legality.disabledReason or "Can't use that now.")
		end
		local info = ITEMS[itemId]
		local target = get(battle, preview.targetId)
		battle.stock[itemId] -= 1
		battle.beltCharges -= 1
		actor.secondaryAvailable = false
		if info.directHeal then
			battle.directHeals -= 1
		end
		if info.medKit then
			battle.medKitUsed = true
		end
		say(battle, "ItemUsed", `{shortName(battle, actor.id)} {verb(actor.id, "use", "uses")} {info.label} on {if target.id == actor.id and actor.id == PLAYER_ID then "yourself" else shortName(battle, target.id)}: {preview.summary}.`, {
			actorId = actor.id,
			targetId = target.id,
		})
		if info.uv then
			local intent = currentIntent(battle)
			battle.grabCancelled = true
			say(battle, "UVCancel", "The UV Flash burns away the shadow. Shadow Grab cancelled!", {
				actorId = actor.id,
				targetId = SABBATH_ID,
				intentId = if intent then intent.id else nil,
			})
		end
		target.hp += preview.hpGain or 0
		target.stamina += preview.staminaGain or 0
		if preview.resolveGain and preview.resolveGain > 0 then
			gainResolve(battle, target, preview.resolveGain, info.label)
		end
		if info.dodge then
			battle.smoke[target.id] = true
		end
		for _, id in preview.removes or {} do
			removeStatus(target, id)
		end
	elseif raw.kind == "SetCompanionTactic" then
		local view = companionView(battle)
		if not view or not view.tacticLegality.canUse then
			return reject("IllegalAction", if view then view.tacticLegality.disabledReason or "" else "No companion.")
		end
		local mode = raw.tacticMode :: TacticMode
		if mode ~= "Aggressive" and mode ~= "Defensive" and mode ~= "Support" then
			return reject("InvalidRequest", "Unknown tactic.")
		end
		if mode == battle.tactic then
			return reject("IllegalAction", "Already using that tactic.")
		end
		battle.tactic = mode
		actor.secondaryAvailable = false
		say(battle, "Action", `Companion switches to {mode}.`, { actorId = COMPANION_ID })
	elseif raw.kind == "CompanionGuardRedirect" then
		local view = companionView(battle)
		local redirect = view and view.redirect
		if not redirect or redirect.intentId ~= raw.intentId then
			return reject("IllegalAction", "Nothing to redirect right now.")
		end
		if not redirect.legality.canUse then
			return reject("IllegalAction", redirect.legality.disabledReason or "Can't redirect now.")
		end
		local recipient: CombatTypes.RedirectTarget? = nil
		for _, candidate in redirect.targets do
			if candidate.recipientId == raw.recipientId then
				recipient = candidate
			end
		end
		if not recipient or not recipient.legality.canUse then
			return reject("IllegalAction", if recipient then recipient.legality.disabledReason or "" else "Can't redirect to them.")
		end
		battle.redirectUses -= 1
		actor.secondaryAvailable = false
		battle.retarget = recipient.recipientId
		say(battle, "Redirect", `Guard Redirect! The attack now targets {shortName(battle, recipient.recipientId)}.`, {
			actorId = COMPANION_ID,
			targetId = recipient.recipientId,
			intentId = redirect.intentId,
		})
	else
		return reject("InvalidRequest", "Unknown Secondary.")
	end
	battle.revision += 1
	maybeAutoAdvance(battle)
	return ok(battle)
end

function MockSandboxServer.SubmitSandboxQteCheck(request: RemoteContract.SandboxQteCheckRequest): Response
	local battle, failure = checkBattle(request, false)
	if not battle then
		return failure :: Response
	end
	local prompt = battle.prompt
	local pending = battle.pending
	if not prompt or not pending or prompt.id ~= request.challengeId then
		return reject("ChallengeExpired", "That QTE already ended.")
	end
	local index = request.checkIndex
	if index ~= prompt.nextCheckIndex or prompt.checkResults[index] ~= "Pending" then
		return reject("InvalidCheck", "Wrong check.")
	end
	local correct
	if pending.manual then
		local t = now()
		if request.input ~= "Confirm" then
			return reject("InvalidCheck", "Use Confirm for this timing check.")
		end
		if t < pending.starts[index] then
			return reject("InvalidCheck", "Wait for the next ring.")
		end
		-- Late presses are already expired by the timer; early ones miss.
		correct = t >= pending.opens[index] and t < pending.closes[index]
	else
		if request.input == "Confirm" then
			return reject("InvalidCheck", "Choose a direction for the cue.")
		end
		correct = request.input == pending.answers[index]
	end
	prompt.checkResults[index] = if correct then "Hit" else "Miss"
	if index >= #prompt.checkResults then
		prompt.nextCheckIndex = nil
		resolveQte(battle)
	else
		prompt.nextCheckIndex = index + 1
		battle.revision += 1
	end
	return ok(battle)
end

return MockSandboxServer
