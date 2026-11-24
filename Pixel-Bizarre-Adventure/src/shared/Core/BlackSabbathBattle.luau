--!strict

local Combat = require("../Contracts/CombatTypes")
local Remote = require("../Contracts/RemoteContract")
local Math = require("./SandboxMath")
local Encounter = require("../Data/BlackSabbathEncounter")

local Limits = Combat.Phase2Limits
local Heavy = Combat.HighRiskHeavy
local PLAYER = "player"
local COMPANION = "companion"
local SABBATH = "black_sabbath"
local ALLOWED: Combat.ActionLegality = { canUse = true }
local RING_LEAD_SECONDS = 0.15
local RING_APPROACH_SECONDS = 1.15
local RING_HIT_WINDOW_SECONDS = 0.75
local RING_RESET_SECONDS = 0.30

type Actor = {
	view: Combat.SandboxActorState,
	physical: number,
	special: number,
	defense: number,
	focus: number,
	baseDodge: number,
	smoke: boolean,
	whetstone: boolean,
	stunned: boolean,
	lowHpTriggered: boolean,
	fireStartedAfterPrimary: boolean,
}

type Challenge = {
	id: string,
	move: Encounter.Move,
	actorId: string,
	targetId: string,
	results: { Combat.QteCheckResult },
	nextIndex: number,
	grade: number,
} & (
	{ mode: "Manual", kind: "Standard" | "HighRiskThreeCheck", rings: { Combat.ManualQteCheck } }
	| { mode: "UntimedCue", kind: "HighRiskThreeCheck", cues: { Combat.QteInput } }
)

export type State = {
	id: string,
	level: number,
	act: number,
	stage: "Night" | "Neutral",
	mode: Combat.QteMode,
	revision: number,
	round: number,
	actors: { [string]: Actor },
	roster: { string },
	tieOrder: { [string]: number },
	queue: { Combat.TurnOrderEntry },
	queueIndex: number,
	active: string?,
	outcome: Combat.CombatOutcome,
	log: { Combat.SandboxLogEvent },
	intent: Combat.SandboxIntent?,
	exposed: boolean,
	qte: Challenge?,
	random: () -> number,
	clock: () -> number,
	charges: number,
	heals: number,
	medKit: boolean,
	stock: { [Combat.BeltItemId]: number },
	tactic: Combat.TacticMode,
	redirects: number,
	assistUsed: boolean,
}

local Battle = {}

local function blocked(reason: string): Combat.ActionLegality
	return { canUse = false, disabledReason = reason }
end

local function when(noIssue: boolean, reason: string): Combat.ActionLegality
	return if noIssue then ALLOWED else blocked(reason)
end

local function raise(state: State, event: Combat.SandboxLogEvent)

	table.insert(state.log, event)
end

local function note(state: State, kind: "Action" | "Guard" | "Defeated" | "Outcome" | "Assist" | "Resolve" | "Status", message: string, id: string?)
	raise(state, { turn = state.round, kind = kind, message = message, actorId = id })
end

local function chance(state: State, percent: number): boolean
	return percent >= 100 or (percent > 0 and state.random() * 100 < percent)
end

local function step(state: State): "LighterStrike" | "ShadowGrabWindup" | "ShadowGrabLanding" | "FadeIntoShadow"
	local beat = (state.round - 1) % 4
	if beat == 0 then return "LighterStrike" end
	if beat == 1 then return "ShadowGrabWindup" end
	if beat == 2 then return "ShadowGrabLanding" end
	return "FadeIntoShadow"
end

local function dodge(actor: Actor): number
	return math.min(50, actor.baseDodge + (if actor.smoke then 20 else 0))
end

local function addResolve(state: State, actor: Actor, gain: number): number
	local view = actor.view
	if view.onFireTurnsRemaining > 0 then return 0 end
	local delta = if gain < 0 then -math.min(view.resolve, -gain)
		else math.min(gain, Limits.ResolveGainPerTurn - view.resolveGainedThisTurn, Limits.MaxResolve - view.resolve)
	view.resolve += delta
	view.resolveGainedThisTurn += math.max(0, delta)
	if view.resolve == Limits.MaxResolve then
		view.onFireTurnsRemaining = Limits.OnFireTurns
		view.finisherReady = true
		actor.fireStartedAfterPrimary = state.active ~= view.id or not view.primaryAvailable
		note(state, "Resolve", view.displayName .. " is On Fire!", view.id)
	end
	return delta
end

local function stopFire(actor: Actor)
	actor.view.onFireTurnsRemaining = 0
	actor.view.finisherReady = false
	actor.view.resolve = 0
	actor.fireStartedAfterPrimary = false
end

local function applyDamage(state: State, source: Actor, target: Actor, damage: number, moveId: string, grade: number?)
	local view = target.view
	local before = view.hp
	view.hp = math.max(0, view.hp - damage)
	raise(state, {
		turn = state.round, kind = "Damage", actorId = source.view.id, targetId = view.id,
		moveId = moveId, amount = before - view.hp, qteGrade = grade,
		message = string.format("%s takes %d damage.", view.displayName, before - view.hp),
	})
	if view.hp == 0 then
		note(state, "Defeated", view.displayName .. " falls.", view.id)
		if view.id == SABBATH then
			state.outcome = "Victory"
		elseif state.actors[PLAYER].view.hp == 0 and state.actors[COMPANION].view.hp == 0 then
			state.outcome = "Defeat"
		end
		if state.outcome ~= "InProgress" then
			state.active = nil
			state.intent = nil
			note(state, "Outcome", if state.outcome == "Victory" then "Black Sabbath is defeated." else "The party falls.")
		end
	elseif view.team == "Player" and not target.lowHpTriggered and before > view.maxHp * 0.25 and view.hp <= view.maxHp * 0.25 then
		target.lowHpTriggered = true
		addResolve(state, target, Limits.LowHpResolve)
	end
end

local function canInterrupt(state: State, target: Actor): boolean
	local intent = state.intent
	return intent ~= nil and intent.targetId ~= "" and intent.stage == "Windup" and target.view.id == SABBATH
end

local function cancelGrab(state: State, sourceId: string, offensive: boolean)
	local intent = assert(state.intent)
	state.intent = nil
	state.exposed = offensive
	raise(state, {
		turn = state.round, kind = if offensive then "Interrupt" else "UVCancel", actorId = sourceId,
		targetId = SABBATH, intentId = intent.id,
		message = if offensive then "Shadow Grab breaks. Black Sabbath is Exposed (-15 Mitigation)." else "UV Flash cancels Shadow Grab.",
	})
end

local function resolvePrimary(state: State, actor: Actor, target: Actor, move: Encounter.Move, challenge: Challenge?)
	local grade = if challenge then challenge.grade else nil
	local highRisk = move.qte == "HighRiskThreeCheck"
	local exposurePp = if state.exposed then Limits.ExposedMitigationPp else 0
	state.exposed = false

	local resolveDelta = 0
	if highRisk and grade ~= 3 then
		resolveDelta = addResolve(state, actor, Heavy.resolveOnPartialOrFailed)
	end
	if highRisk and grade == 0 then
		raise(state, {
			turn = state.round, kind = "FailedQTE_0of3", message = "0/3. Missed timing.",
			actorId = actor.view.id, targetId = target.view.id, moveId = move.id, qteGrade = 0, resolveDelta = resolveDelta,
		})
		return
	end

	if not chance(state, Math.hitPercent(dodge(target), actor.view.precisionPercent, highRisk or move.id == "BasicStrike")) then
		raise(state, {
			turn = state.round, kind = "Dodged", message = target.view.displayName .. " dodges.",
			actorId = actor.view.id, targetId = target.view.id, moveId = move.id, qteGrade = grade, resolveDelta = resolveDelta,
		})
		if move.id == "Finisher" then stopFire(actor) end
		return
	end

	local manualPerfect = challenge ~= nil and challenge.mode == "Manual" and grade == #challenge.results
	local interrupted = canInterrupt(state, target) and (move.id == "HamonInterrupt" or (highRisk and grade == 3))
	local timing = if highRisk then Heavy.timingByGrade[grade or 0]
		elseif grade == nil then 1 elseif grade == 1 then 1.10 else 0.90
	local onFire = actor.view.onFireTurnsRemaining > 0
	local shatter = highRisk and grade == 3
	if shatter then target.view.isDefending = false end

	local raw = Math.basicRaw(state.level, Math.scalingStat(move.tag, actor.physical, actor.special)) * move.multiplier
	local critical = chance(state, if onFire then 25 else 10)
	local damage = Math.damage({
		raw = raw, timing = timing, critical = critical, onFire = onFire, defense = target.defense, armor = target.view.armor,
		penetrationPp = if actor.whetstone then 15 else 0, exposurePp = exposurePp,
		guarding = target.view.isDefending, act = state.act,
	})
	actor.whetstone = false
	applyDamage(state, actor, target, damage, move.id, grade)

	if highRisk then
		if grade == 3 then resolveDelta = addResolve(state, actor, Heavy.resolveOnLandedFull) end
	elseif move.id == "Finisher" then
		stopFire(actor)
	else
		resolveDelta = addResolve(state, actor, if move.id == "BasicStrike" then 8 else 10)
	end
	if resolveDelta ~= 0 then
		raise(state, {
			turn = state.round, kind = "Resolve", actorId = actor.view.id, moveId = move.id, qteGrade = grade,
			resolveDelta = resolveDelta, message = string.format("Resolve %+d.", resolveDelta),
		})
	end
	if state.outcome ~= "InProgress" then return end
	if interrupted then cancelGrab(state, actor.view.id, true) end

	local partner = state.actors[if actor.view.id == PLAYER then COMPANION else PLAYER]
	if manualPerfect and not state.assistUsed and partner.view.hp > 0 and not partner.stunned then
		state.assistUsed = true
		note(state, "Assist", partner.view.displayName .. " follows up at 25% strength.", partner.view.id)
		local assistRaw = Math.basicRaw(state.level, math.max(partner.physical, partner.special))
		applyDamage(state, partner, target, Math.damage({
			raw = assistRaw * Limits.ManualAssistStrength, defense = target.defense, armor = target.view.armor,
			guarding = target.view.isDefending, act = state.act,
		}), "Assist", nil)
	end
end

local function setIntent(state: State, targetId: string, grab: boolean)
	local landing = if grab then state.round + 1 else state.round
	state.intent = {
		id = state.id .. ":" .. tostring(landing), actorId = SABBATH, moveId = if grab then "ShadowGrab" else "LighterStrike",
		label = if grab then "Shadow Grab" else "Lighter Strike", targetId = targetId, landingTurn = landing,
		telegraphKind = if grab then "Heavy" else "Attack", estimatedPower = (8 + 0.72 * state.level) * (if grab then Limits.ShadowGrabMultiplier else 1),
		targeting = "Single", stage = if grab then "Windup" else "Scheduled", offensiveInterruptible = grab, uvCancelable = grab,
	}
end

local function enemyTurn(state: State)
	local intent = state.intent
	if not intent or intent.landingTurn ~= state.round then return end
	local enemy = state.actors[SABBATH]
	local target = state.actors[intent.targetId]
	local grab = intent.moveId == "ShadowGrab"
	state.intent = nil
	if target.view.hp == 0 then
		note(state, "Action", intent.label .. " loses its target.", SABBATH)
		return
	end
	if not chance(state, 100 - dodge(target)) then
		raise(state, {
			turn = state.round, kind = "Dodged", actorId = SABBATH, targetId = target.view.id,
			moveId = intent.moveId, message = target.view.displayName .. " dodges " .. intent.label .. ".",
		})
		return
	end
	applyDamage(state, enemy, target, Math.damage({
		raw = intent.estimatedPower, defense = target.defense, armor = target.view.armor,
		guarding = target.view.isDefending, act = state.act, stageMatch = state.stage == "Night",
	}), intent.moveId, nil)
	if grab and target.view.hp > 0 and not target.view.isDefending and chance(state, Math.statusChance(100, Math.focusResist(target.focus))) then
		target.stunned = true
		note(state, "Status", target.view.displayName .. " is Stunned.", target.view.id)
	end
end

local function startRound(state: State)
	state.queue = {}
	state.queueIndex = 0
	state.assistUsed = false
	state.actors[SABBATH].baseDodge = if step(state) == "FadeIntoShadow" then Limits.FadeDodgePp else 0
	local target = if state.actors[PLAYER].view.hp > 0 then PLAYER else COMPANION
	local beat = step(state)
	if beat == "LighterStrike" then
		setIntent(state, target, false)
	elseif beat == "ShadowGrabWindup" then
		setIntent(state, target, true)
		note(state, "Action", "Black Sabbath winds up Shadow Grab.", SABBATH)
	elseif beat == "ShadowGrabLanding" and state.intent then
		state.intent.stage = "Landing"
		state.intent.uvCancelable = false
		state.intent.offensiveInterruptible = false
	elseif beat == "FadeIntoShadow" then
		note(state, "Status", "Black Sabbath fades (+20 Dodge).", SABBATH)
	end

	for _, id in state.roster do
		local view = state.actors[id].view
		if view.hp > 0 then
			table.insert(state.queue, { actorId = id, speed = Math.effectiveSpeed(view.speed, view.onFireTurnsRemaining > 0) })
		end
	end
	table.sort(state.queue, function(a, b) return Math.turnComesFirst(a, b, state.round, state.tieOrder) end)
end

local function nextTurn(state: State)
	state.active = nil
	while state.outcome == "InProgress" do
		state.queueIndex += 1
		local entry = state.queue[state.queueIndex]
		if not entry then
			state.round += 1
			startRound(state)
			continue
		end
		local actor = state.actors[entry.actorId]
		local view = actor.view
		if view.hp == 0 then continue end
		if view.team == "Enemy" then
			enemyTurn(state)
			continue
		end

		state.active = view.id
		view.isDefending = false
		view.resolveGainedThisTurn = 0
		view.primaryAvailable = not actor.stunned
		view.secondaryAvailable = true
		view.bonusPrimaryAvailable = false
		actor.smoke = false
		actor.whetstone = false
		actor.fireStartedAfterPrimary = false
		if state.round > 1 then view.stamina = math.min(view.maxStamina, view.stamina + 1) end
		if actor.stunned then note(state, "Status", view.displayName .. " loses the Primary to Stun.", view.id) end
		actor.stunned = false
		return
	end
end

local function endTurn(state: State, actor: Actor)
	local view = actor.view
	view.primaryAvailable = false
	view.secondaryAvailable = false
	view.bonusPrimaryAvailable = false
	actor.whetstone = false
	if view.onFireTurnsRemaining > 0 and not actor.fireStartedAfterPrimary then
		view.onFireTurnsRemaining -= 1
		if view.onFireTurnsRemaining == 0 then stopFire(actor) end
	end
	nextTurn(state)
end

local function canAct(state: State, actor: Actor?): Combat.ActionLegality
	if state.qte then return blocked("Finish the active QTE.") end
	return when(state.outcome == "InProgress" and actor ~= nil and state.active == actor.view.id, "Wait for this fighter's turn.")
end

local function secondaryLegality(state: State, actor: Actor?): Combat.ActionLegality
	local legality = canAct(state, actor)
	if not legality.canUse then return legality end
	return when(assert(actor).view.secondaryAvailable, "Secondary already spent.")
end

local function endTurnLegality(state: State, actor: Actor?): Combat.ActionLegality
	local legality = canAct(state, actor)
	if not legality.canUse then return legality end
	return when(not assert(actor).view.primaryAvailable, "Resolve your Primary first.")
end

local function primaryLegality(state: State, actor: Actor, move: Encounter.Move, slot: Combat.PrimarySlot): Combat.ActionLegality
	local legality = canAct(state, actor)
	if not legality.canUse then return legality end
	local view = actor.view
	if slot == "BonusPrimary" then
		if view.primaryAvailable or not view.bonusPrimaryAvailable then return blocked("No Bonus Primary available.") end
	elseif not view.primaryAvailable then return blocked("Primary is unavailable.") end
	if view.stamina < move.cost then return blocked("Not enough Stamina.") end
	if move.id == "Finisher" and not view.finisherReady then return blocked("Finisher requires On Fire.") end
	if move.id == "HamonInterrupt" and not canInterrupt(state, state.actors[SABBATH]) then return blocked("No interruptible windup.") end
	return ALLOWED
end

local function targetOdds(state: State, actor: Actor, move: Encounter.Move, target: Actor): Combat.TargetOdds
	local view = target.view
	local defensive = move.id == "Defend"
	local valid = view.hp > 0 and (if defensive then view.id == actor.view.id else view.team == "Enemy")
	local precision = actor.view.precisionPercent
	local targetDodge = dodge(target)
	local hit = if defensive then 100 else Math.hitPercent(targetDodge, precision, move.id == "HighRiskHeavy" or move.id == "BasicStrike")
	return {
		targetId = view.id, legality = when(valid, "Pick a living target for this move."),
		effectiveDodgePercent = if defensive then 0 else Math.dodgePercent(targetDodge, precision),
		hitIfExecutedPercent = hit,
		interruptIfExecutedPercent = if canInterrupt(state, target) and (move.id == "HamonInterrupt" or move.id == "HighRiskHeavy") then hit else nil,
	}
end

local function qteMode(state: State, move: Encounter.Move): Combat.QteMode?
	if move.qte == "None" then return nil end
	if state.mode == "Manual" then return "Manual" end
	return if move.qte == "HighRiskThreeCheck" then "UntimedCue" else "AutoGood"
end

local function viewOptions(state: State, actor: Actor?): { Combat.PrimaryOption }
	local options: { Combat.PrimaryOption } = {}
	if actor then
		local slot: Combat.PrimarySlot = if not actor.view.primaryAvailable and actor.view.bonusPrimaryAvailable then "BonusPrimary" else "Primary"
		for _, move in Encounter.Moves do
			local target = if move.id == "Defend" then actor else state.actors[SABBATH]
			table.insert(options, {
				moveId = move.id, label = move.label, scalingTag = move.tag, staminaCost = move.cost, slot = slot,
				legality = primaryLegality(state, actor, move, slot), targets = { targetOdds(state, actor, move, target) },
				qte = move.qte, effectiveQteMode = qteMode(state, move),
			})
		end
	end
	return options
end

local function beltPreview(state: State, actor: Actor?, target: Actor, item: Encounter.Item): Combat.BeltPreview
	local view = target.view
	local preview: Combat.BeltPreview = { targetId = view.id, summary = item.label, legality = secondaryLegality(state, actor) }
	local function unavailable(reason: string)
		if preview.legality.canUse then preview.legality = blocked(reason) end
	end

	if state.charges == 0 then unavailable("No belt charges remain.") end
	if state.stock[item.id] == 0 then unavailable("No stock remains.") end
	if view.hp == 0 then unavailable("Target is defeated.") end

	local removable: { Combat.StatusId } = {}
	for _, status in view.statuses do
		if status.isRemovable and (item.id ~= "CapreseSalad" or #removable == 0) then
			table.insert(removable, status.id)
		end
	end
	if item.healFraction then
		if state.heals == 0 then unavailable("Party heal limit reached.") end
		if item.id == "MedKit" and state.medKit then unavailable("The Med-Kit limit was reached.") end
		if item.id == "MineralWater" and (actor == nil or actor.view.id ~= view.id) then unavailable("Mineral Water targets the acting fighter.") end
		local gain = math.min(view.maxHp - view.hp, math.floor(view.maxHp * item.healFraction))
		preview.hpGain = gain
		preview.summary = string.format("+%d HP", gain)
		if item.id == "CapreseSalad" and #removable > 0 then
			preview.removes = removable
			preview.summary ..= " and cleanse 1 status"
		elseif gain == 0 then unavailable("Target is already at full HP.") end
	elseif item.id == "CoffeeGum" then
		local gain = math.min(2, view.maxStamina - view.stamina)
		preview.staminaGain = gain
		preview.summary = string.format("+%d Stamina", gain)
		if gain == 0 then unavailable("Target is already at full Stamina.") end
	elseif item.id == "PassioneEspresso" then
		local gain = if view.onFireTurnsRemaining > 0 then 0
			else math.min(15, Limits.ResolveGainPerTurn - view.resolveGainedThisTurn, Limits.MaxResolve - view.resolve)
		preview.resolveGain = gain
		preview.summary = string.format("+%d Resolve%s", gain, if view.resolve + gain == Limits.MaxResolve and gain > 0 then ", On Fire" else "")
		if gain == 0 then unavailable("Target cannot gain Resolve right now.") end
	elseif item.id == "SmokePellet" then
		local gain = math.min(20, 50 - dodge(target))
		if target.smoke then gain = 0 end
		preview.dodgeGainPp = gain
		preview.summary = string.format("+%d Dodge", gain)
		if preview.dodgeGainPp == 0 then unavailable("Dodge is already boosted.") end
	elseif item.id == "UVFlash" then
		local intent = state.intent
		preview.summary = "Guaranteed Shadow Cancel Only"
		if intent and intent.uvCancelable then preview.cancelsIntentId = intent.id else unavailable("No eligible Shadow Grab windup.") end
	elseif item.id == "SmellingSalts" then
		preview.removes = removable
		preview.summary = string.format("Cleanse %d statuses", #removable)
		if #removable == 0 then unavailable("No removable statuses.") end
	elseif item.id == "SpikedWhetstone" then
		preview.summary = "+15 Defense Penetration on the next landed Primary this turn"
		if actor == nil or actor ~= target or not (view.primaryAvailable or view.bonusPrimaryAvailable) then
			unavailable("Requires the acting fighter's remaining Primary.")
		end
	end
	return preview
end

local function itemTargets(state: State, item: Encounter.Item, actor: Actor?): { Combat.BeltPreview }
	local targets: { Combat.BeltPreview } = {}
	if item.id == "UVFlash" then
		table.insert(targets, beltPreview(state, actor, state.actors[SABBATH], item))
	else
		for _, id in { PLAYER, COMPANION } do
			table.insert(targets, beltPreview(state, actor, state.actors[id], item))
		end
	end
	return targets
end

local function beltView(state: State, actor: Actor?): Combat.PartyBelt
	local items: { Combat.BeltItemView } = {}
	for _, item in Encounter.Items do
		local targets = itemTargets(state, item, actor)
		local legality = targets[1].legality
		for _, target in targets do
			if target.legality.canUse then legality = ALLOWED end
		end
		table.insert(items, { itemId = item.id, label = item.label, stock = state.stock[item.id], targets = targets, legality = legality })
	end
	return { beltChargesRemaining = state.charges, directHealsRemaining = state.heals, medKitUsed = state.medKit, items = items }
end

local function redirectView(state: State, actor: Actor?): Combat.RedirectView?
	local intent = state.intent
	if not intent or intent.moveId ~= "ShadowGrab" then return nil end
	local legality = secondaryLegality(state, actor)
	local companion = state.actors[COMPANION].view
	if legality.canUse then
		legality = when(state.redirects > 0 and companion.hp > 0, "Companion redirect is unavailable.")
	end
	local targets: { Combat.RedirectTarget } = {}
	for _, id in { PLAYER, COMPANION } do
		local recipient = state.actors[id].view
		table.insert(targets, {
			recipientId = id, recipientIsDefending = recipient.isDefending,
			legality = if not legality.canUse then legality else when(id ~= intent.targetId and recipient.hp > 0, "Choose a different living recipient."),
		})
	end
	return { intentId = intent.id, originalTargetId = intent.targetId, usesRemaining = state.redirects, legality = legality, targets = targets }
end

local function promptView(challenge: Challenge?): Combat.QtePrompt?
	if not challenge then return nil end
	if challenge.mode == "Manual" then
		local manualChecks: { Combat.ManualQteCheck } = {}
		for index, ring in challenge.rings do
			manualChecks[index] = table.clone(ring)
		end
		return { id = challenge.id, mode = "Manual", kind = challenge.kind, checks = manualChecks, checkResults = table.clone(challenge.results), nextCheckIndex = challenge.nextIndex }
	end
	local checks: { Combat.UntimedQteCheck } = {}
	for index, cue in challenge.cues do
		checks[index] = { index = index, prompt = "Press " .. string.upper(cue), choices = table.clone(Encounter.Choices) }
	end
	return { id = challenge.id, mode = "UntimedCue", kind = "HighRiskThreeCheck", checks = checks, checkResults = table.clone(challenge.results), nextCheckIndex = challenge.nextIndex }
end

function Battle.snapshot(state: State): Combat.SandboxSnapshot
	local actors: { Combat.SandboxActorState } = {}
	for _, id in state.roster do
		local actor = state.actors[id]
		local view = table.clone(actor.view)
		view.statuses = table.clone(view.statuses)
		view.dodgePercent = dodge(actor)
		if actor.stunned then table.insert(view.statuses, { id = "Stun" :: "Stun", label = "Stun", isRemovable = false, turnsRemaining = 1 }) end
		if id == SABBATH and actor.baseDodge > 0 then
			table.insert(view.statuses, { id = "Fade" :: "Fade", label = "Fade", isRemovable = false, turnsRemaining = 1 })
		end
		if id == SABBATH and state.exposed then table.insert(view.statuses, { id = "Exposed" :: "Exposed", label = "Exposed", isRemovable = false }) end
		table.insert(actors, view)
	end

	local active = if state.active then state.actors[state.active] else nil
	local companion = state.actors[COMPANION].view
	local beat = step(state)
	local exposureOwner: string? = nil
	if active and (active.view.primaryAvailable or active.view.bonusPrimaryAvailable or state.qte ~= nil) then
		exposureOwner = active.view.id
	elseif state.exposed then
		for i = state.queueIndex + 1, #state.queue do
			local actor = state.actors[state.queue[i].actorId]
			if actor.view.team == "Player" and actor.view.hp > 0 and not actor.stunned then
				exposureOwner = actor.view.id
				break
			end
		end
	end
	return {
		battleId = state.id, revision = state.revision, turn = state.round, playerActorId = PLAYER,
		activeActorId = state.active, actors = actors, turnOrder = table.clone(state.queue),
		enemyIntents = if state.intent then { table.clone(state.intent) } else {}, primaryOptions = viewOptions(state, active),
		endTurnLegality = endTurnLegality(state, active), belt = beltView(state, active),
		companion = {
			actorId = COMPANION, tacticMode = state.tactic,
			tacticLegality = if companion.hp > 0 then secondaryLegality(state, active) else blocked("Companion is defeated."),
			assistAvailableThisRound = companion.hp > 0 and not state.assistUsed, redirect = redirectView(state, active),
		},
		exposure = if state.exposed then { targetId = SABBATH, mitigationPenaltyPp = Limits.ExposedMitigationPp, exposedFollowUpActorId = exposureOwner } else nil,
		qteMode = state.mode, qtePrompt = promptView(state.qte), stageTag = state.stage,
		blackSabbathStep = beat, log = table.clone(state.log), outcome = state.outcome,
	}
end


local function newActor(id: string, name: string, level: number, act: number): Actor
	local enemy = id == SABBATH
	local companion = id == COMPANION
	local hp = if enemy then math.floor((44 + 6 * level) * 1.65) else Math.playerHp(level, if companion then 0 else level)
	local focus = if companion then 30 else 0
	local offense = 2 * level + 4 * act
	local stat = if companion then math.floor(offense * 0.55) else offense
	local staminaStat = if companion then 20 else 40
	local sprite: "BlackSabbathIdle" | "CompanionIdle" | "PlayerIdle" = if enemy then "BlackSabbathIdle" elseif companion then "CompanionIdle" else "PlayerIdle"
	return {
		view = {
			id = id, displayName = name, hp = hp, maxHp = hp, team = if enemy then "Enemy" else "Player",
			stamina = if enemy then 0 else 3 + math.floor(staminaStat / 40),
			maxStamina = if enemy then 0 else 5 + math.floor(staminaStat / 20),
			armor = 0, speed = if enemy then 8 elseif companion then 10 else 12, power = stat,
			isDefending = false, spriteKey = sprite, primaryAvailable = false, secondaryAvailable = false,
			bonusPrimaryAvailable = false, resolve = 0, resolveGainedThisTurn = 0, onFireTurnsRemaining = 0,
			finisherReady = false, dodgePercent = 0, precisionPercent = Math.focusPrecision(focus), statuses = {},
		},
		physical = stat, special = stat, defense = if enemy then 50 + 10 * (act - 1) elseif act == 1 then 14 else 50,
		focus = focus, baseDodge = 0, smoke = false, whetstone = false, stunned = false,
		fireStartedAfterPrimary = false, lowHpTriggered = false,
	}
end

function Battle.new(id: string, request: Remote.StartSandboxRequest, random: () -> number, clock: () -> number): State
	local level = request.level
	local act = math.ceil(level / 10)
	local stock: { [Combat.BeltItemId]: number } = {}
	for _, item in Encounter.Items do stock[item.id] = item.stock end
	local state: State = {
		id = id, level = level, act = act, stage = request.stageTag, mode = request.qteMode, revision = 1, round = 1,
		actors = {
			[PLAYER] = newActor(PLAYER, "You", level, act), [COMPANION] = newActor(COMPANION, "Companion", level, act),
			[SABBATH] = newActor(SABBATH, "Black Sabbath", level, act),
		},
		roster = { PLAYER, COMPANION, SABBATH }, tieOrder = { [PLAYER] = 1, [COMPANION] = 2, [SABBATH] = 3 },
		queue = {}, queueIndex = 0, outcome = "InProgress", log = {}, exposed = false,
		random = random, clock = clock, charges = Limits.PartyBeltCharges, heals = Limits.DirectHealsPerFight,
		medKit = false, stock = stock, tactic = "Aggressive", redirects = Limits.CompanionRedirectsPerFight, assistUsed = false,
	}
	if state.stage == "Night" then note(state, "Action", "Night falls. Black Sabbath rises from the shadows.", SABBATH) end
	startRound(state)
	nextTurn(state)
	return state
end

local function reject(state: State, code: Remote.SandboxErrorCode, message: string): Remote.SandboxResponse
	return { ok = false, code = code, message = message, snapshot = Battle.snapshot(state) }
end

local function commit(state: State): Remote.SandboxResponse
	state.revision += 1
	return { ok = true, snapshot = Battle.snapshot(state) }
end

local function checkRevision(state: State, request: Remote.SandboxBattleRevision): Remote.SandboxResponse?
	if state.id ~= request.battleId then return reject(state, "BattleNotFound", "This sandbox battle has ended.") end
	if state.revision ~= request.expectedRevision then return reject(state, "StaleRevision", "Sandbox state changed. Choose again.") end
	return nil
end

local function beginChallenge(state: State, mode: "Manual" | "UntimedCue", move: Encounter.Move, actor: Actor, target: Actor)
	local kind: "Standard" | "HighRiskThreeCheck" = if move.qte == "HighRiskThreeCheck" then "HighRiskThreeCheck" else "Standard"
	local count = if kind == "HighRiskThreeCheck" then 3 else 1
	local id = state.id .. ":qte:" .. tostring(state.revision)
	local results = table.create(count, "Pending" :: Combat.QteCheckResult)
	if mode == "Manual" then
		local rings: { Combat.ManualQteCheck } = {}
		local halfWindow = (RING_HIT_WINDOW_SECONDS + math.clamp(actor.focus, 0, 150) / 500) / 2
		local startsAt = state.clock() + RING_LEAD_SECONDS
		for index = 1, count do
			local overlapAt = startsAt + RING_APPROACH_SECONDS
			local closesAt = overlapAt + halfWindow
			rings[index] = {
				index = index,
				approachStartsAtServerTime = startsAt,
				overlapAtServerTime = overlapAt,
				opensAtServerTime = overlapAt - halfWindow,
				closesAtServerTime = closesAt,
			}
			startsAt = closesAt + RING_RESET_SECONDS
		end
		state.qte = {
			id = id, mode = "Manual" :: "Manual", kind = kind, move = move, actorId = actor.view.id, targetId = target.view.id,
			rings = rings, results = results, nextIndex = 1, grade = 0,
		}
		return
	end

	local cues: { Combat.QteInput } = {}
	for index = 1, count do
		cues[index] = Encounter.Choices[math.floor(state.random() * #Encounter.Choices) + 1]
	end
	state.qte = {
		id = id, mode = "UntimedCue" :: "UntimedCue", kind = "HighRiskThreeCheck" :: "HighRiskThreeCheck",
		move = move, actorId = actor.view.id, targetId = target.view.id,
		cues = cues, results = results, nextIndex = 1, grade = 0,
	}
end

function Battle.submitPrimary(state: State, request: Remote.SandboxPrimaryRequest): Remote.SandboxResponse
	local stale = checkRevision(state, request)
	if stale then return stale end
	local actor = state.actors[request.actorId]
	if not actor then return reject(state, "IllegalAction", "Unknown fighter.") end
	for _, move in Encounter.Moves do
		if move.id ~= request.moveId then continue end
		local legality = primaryLegality(state, actor, move, request.slot)
		if not legality.canUse then return reject(state, if state.qte then "QtePending" else "IllegalAction", legality.disabledReason) end
		local targetId = request.targetId or (if move.id == "Defend" then actor.view.id else "")
		local target = state.actors[targetId]
		if not target or not targetOdds(state, actor, move, target).legality.canUse then
			return reject(state, "IllegalAction", "Choose a legal target.")
		end

		local view = actor.view
		view.stamina -= move.cost
		if request.slot == "Primary" then view.primaryAvailable = false else view.bonusPrimaryAvailable = false end
		raise(state, {
			turn = state.round, kind = "Action", actorId = view.id, targetId = targetId, moveId = move.id,
			message = view.displayName .. (if view.id == PLAYER then " use " else " uses ") .. move.label .. ".",
		})
		if move.id == "Defend" then
			view.isDefending = true
			view.stamina = math.min(view.maxStamina, view.stamina + 1)
			note(state, "Guard", if view.id == PLAYER then "You guard." else view.displayName .. " guards.", view.id)
		else
			local mode = qteMode(state, move)
			if mode == "Manual" or mode == "UntimedCue" then
				beginChallenge(state, mode, move, actor, target)
			else
				resolvePrimary(state, actor, target, move, nil)
			end
		end
		return commit(state)
	end
	return reject(state, "InvalidRequest", "Unknown Primary.")
end

local function useItem(state: State, actor: Actor, target: Actor, item: Encounter.Item, preview: Combat.BeltPreview)
	local view = target.view
	view.hp += preview.hpGain or 0
	view.stamina += preview.staminaGain or 0
	if preview.resolveGain then addResolve(state, target, preview.resolveGain) end
	if preview.dodgeGainPp then target.smoke = true end
	if preview.removes then
		for index = #view.statuses, 1, -1 do
			if table.find(preview.removes, view.statuses[index].id) then table.remove(view.statuses, index) end
		end
	end
	if preview.cancelsIntentId then cancelGrab(state, actor.view.id, false) end
	if item.id == "SpikedWhetstone" then target.whetstone = true end
	if item.healFraction then state.heals -= 1 end
	if item.id == "MedKit" then state.medKit = true end
	state.stock[item.id] -= 1
	state.charges -= 1
	raise(state, {
		turn = state.round, kind = "ItemUsed", actorId = actor.view.id, targetId = view.id, moveId = item.id,
		message = (if actor.view.id == PLAYER then "You use " else actor.view.displayName .. " uses ") .. item.label .. ".",
	})
end

function Battle.submitSecondary(state: State, request: Remote.SandboxSecondaryRequest): Remote.SandboxResponse
	local stale = checkRevision(state, request)
	if stale then return stale end
	local actor = state.actors[request.actorId]
	if not actor then return reject(state, "IllegalAction", "Unknown fighter.") end
	local function illegal(reason: string): Remote.SandboxResponse
		return reject(state, if state.qte then "QtePending" else "IllegalAction", reason)
	end
	if request.kind == "EndTurn" then
		local legality = endTurnLegality(state, actor)
		if not legality.canUse then return illegal(legality.disabledReason) end
		endTurn(state, actor)
		return commit(state)
	end

	local legality = secondaryLegality(state, actor)
	if not legality.canUse then return illegal(legality.disabledReason) end

	if request.kind == "UseBeltItem" then
		for _, item in Encounter.Items do
			if item.id ~= request.itemId then continue end
			for _, preview in itemTargets(state, item, actor) do
				if preview.targetId ~= request.targetId then continue end
				if not preview.legality.canUse then return illegal(preview.legality.disabledReason) end
				useItem(state, actor, state.actors[request.targetId], item, preview)
				actor.view.secondaryAvailable = false
				return commit(state)
			end
			return illegal("Choose a legal belt target.")
		end
		return illegal("This belt item is unavailable in the sandbox.")
	end
	if request.kind == "SetCompanionTactic" then
		if state.actors[COMPANION].view.hp == 0 then return illegal("Companion is defeated.") end
		if state.tactic == request.tacticMode then return illegal("This tactic is already selected.") end
		state.tactic = request.tacticMode
		note(state, "Action", "Companion tactic: " .. request.tacticMode .. ".", COMPANION)
	else
		local redirect = redirectView(state, actor)
		local intentId = request.intentId
		if not redirect or redirect.intentId ~= intentId then return illegal("No matching Shadow Grab.") end
		local recipient = state.actors[request.recipientId]
		if not recipient or not redirect.legality.canUse or not (recipient.view.team == "Player"
			and recipient.view.hp > 0 and recipient.view.id ~= redirect.originalTargetId) then
			return illegal("Choose a legal redirect recipient.")
		end
		assert(state.intent).targetId = request.recipientId
		state.redirects -= 1
		raise(state, {
			turn = state.round, kind = "Redirect", actorId = actor.view.id, targetId = recipient.view.id,
			intentId = intentId, message = "Shadow Grab redirects to " .. recipient.view.displayName .. ".",
		})
	end
	actor.view.secondaryAvailable = false
	return commit(state)
end

function Battle.setQteMode(state: State, request: Remote.SandboxQteModeRequest): Remote.SandboxResponse
	local stale = checkRevision(state, request)
	if stale then return stale end
	if state.qte then return reject(state, "QtePending", "Finish the active QTE first.") end
	state.mode = request.qteMode
	return commit(state)
end

local function checkResult(state: State, challenge: Challenge, hit: boolean)
	challenge.results[challenge.nextIndex] = if hit then "Hit" else "Miss"
	if hit then challenge.grade += 1 end
	challenge.nextIndex += 1
	if challenge.nextIndex > #challenge.results then
		state.qte = nil
		resolvePrimary(state, state.actors[challenge.actorId], state.actors[challenge.targetId], challenge.move, challenge)
	end
end

function Battle.nextDeadline(state: State): number?
	local challenge = state.qte
	return if challenge and challenge.mode == "Manual" then challenge.rings[challenge.nextIndex].closesAtServerTime else nil
end

local function expireChecksAt(state: State, now: number): boolean
	local challenge = state.qte
	if not challenge or challenge.mode ~= "Manual" then return false end
	local changed = false
	while state.qte == challenge and now >= challenge.rings[challenge.nextIndex].closesAtServerTime do
		checkResult(state, challenge, false)
		changed = true
	end
	if changed then state.revision += 1 end
	return changed
end

function Battle.expireChecks(state: State): boolean
	return expireChecksAt(state, state.clock())
end

function Battle.submitCheck(state: State, request: Remote.SandboxQteCheckRequest): Remote.SandboxResponse
	local receivedAt = state.clock()
	expireChecksAt(state, receivedAt)
	local challenge = state.qte
	if state.id ~= request.battleId or not challenge or challenge.id ~= request.challengeId then
		return reject(state, "ChallengeExpired", "That QTE is no longer active.")
	end
	local index = request.checkIndex
	if index ~= challenge.nextIndex then return reject(state, "InvalidCheck", "Answer the current check in order.") end
	if challenge.mode == "Manual" then
		local ring = challenge.rings[index]
		if request.input ~= "Confirm" then return reject(state, "InvalidCheck", "Use Confirm for this timing check.") end
		if receivedAt < ring.approachStartsAtServerTime then return reject(state, "InvalidCheck", "Wait for the next ring.") end
		checkResult(state, challenge, receivedAt >= ring.opensAtServerTime)
	else
		if request.input == "Confirm" then return reject(state, "InvalidCheck", "Choose a direction for the cue.") end
		checkResult(state, challenge, request.input == challenge.cues[index])
	end
	return commit(state)
end

return table.freeze(Battle)
