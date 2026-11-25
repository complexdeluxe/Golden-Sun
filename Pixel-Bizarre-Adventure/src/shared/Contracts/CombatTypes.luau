--!strict

local AssetManifest = require("./AssetManifest")

export type ActorId = string
export type Team = "Player" | "Enemy"
export type MoveId = "QuickStrike" | "HeavyStrike" | "Defend"

export type ActorState = {
	id: ActorId,
	displayName: string,
	hp: number,
	maxHp: number,
	stamina: number,
	maxStamina: number,
	armor: number,
	speed: number,
	power: number,
	isDefending: boolean,
	team: Team,
	-- Which manifest sprite the client draws for this actor. Nil means use a local placeholder.
	spriteKey: AssetManifest.AssetKey?,
}

export type EnemyIntent = {
	actorId: ActorId,
	moveId: string,
	label: string,
	targetId: ActorId,
	landingTurn: number,
	telegraphKind: "Attack" | "Heavy" | "Guard",
	estimatedPower: number,
}

-- Match the snapshot revision that the player saw when choosing the move.
export type ActionRequest = {
	battleId: string,
	expectedRevision: number,
	moveId: MoveId,
	targetId: ActorId?,
}

export type ActionLegality =
	{ canUse: true, disabledReason: nil? }
	| { canUse: false, disabledReason: string }

export type ActionOption = {
	moveId: MoveId,
	label: string,
	staminaCost: number,
	targetIds: { ActorId },
	legality: ActionLegality,
}

export type TurnOrderEntry = {
	actorId: ActorId,
	speed: number,
}

export type CombatLogEvent = {
	turn: number,
	kind: "Action" | "Damage" | "Guard" | "Join" | "Defeated" | "Flee" | "Outcome",
	actorId: ActorId?,
	targetId: ActorId?,
	moveId: string?,
	amount: number?,
	message: string,
}

export type CombatOutcome = "InProgress" | "Victory" | "Defeat"

export type CombatSnapshot = {
	battleId: string,
	revision: number,
	turn: number,
	playerActorId: ActorId,
	activeActorId: ActorId?,
	actors: { ActorState },
	turnOrder: { TurnOrderEntry },
	enemyIntents: { EnemyIntent },
	actions: { ActionOption },
	log: { CombatLogEvent },
	outcome: CombatOutcome,
}

-- Phase 2 sandbox payloads use a separate shape so the Build 1 tutorial keeps its protocol.
export type ScalingTag = "Physical" | "Special" | "Hybrid" | "AutoBest"
export type QteMode = "Manual" | "AutoGood" | "UntimedCue"
-- Check indexes are integers 1–3. The server validates bounds and order.
export type QteCheckIndex = number
-- A grade is the number of successful checks, from 0 through 3.
export type QteGrade = number
export type QteInput = "Left" | "Center" | "Right"
export type QteSubmissionInput = QteInput | "Confirm"
export type TacticMode = "Aggressive" | "Defensive" | "Support"
export type PrimarySlot = "Primary" | "BonusPrimary"
export type SandboxMoveId = "BasicStrike" | "HeavyStrike" | "HighRiskHeavy" | "Defend" | "HamonInterrupt" | "Finisher"
export type BeltItemId =
	"MineralWater" | "CapreseSalad" | "MedKit" | "CoffeeGum" | "BloodVial"
	| "UVFlash" | "SmellingSalts" | "SmokePellet" | "PassioneEspresso" | "SpikedWhetstone"
export type StatusId = "Bleed" | "Burn" | "Slow" | "FogWound" | "AgeDown" | "CoinBomb" | "Stun" | "Exposed" | "Fade"

export type StatusView = {
	id: StatusId,
	label: string,
	isRemovable: boolean,
	-- Fade includes its remaining duration and is not removable.
	turnsRemaining: number?,
}

export type SandboxActorState = ActorState & {
	primaryAvailable: boolean,
	secondaryAvailable: boolean,
	bonusPrimaryAvailable: boolean,
	resolve: number,
	resolveGainedThisTurn: number,
	onFireTurnsRemaining: number,
	finisherReady: boolean,
	dodgePercent: number,
	precisionPercent: number,
	statuses: { StatusView },
}

export type SandboxIntent = EnemyIntent & {
	id: string,
	targeting: "Single" | "Party",
	stage: "Scheduled" | "Windup" | "Landing",
	offensiveInterruptible: boolean,
	uvCancelable: boolean,
}

export type TargetOdds = {
	targetId: ActorId,
	legality: ActionLegality,
	effectiveDodgePercent: number,
	hitIfExecutedPercent: number,
	interruptIfExecutedPercent: number?,
}

export type PrimaryOption = {
	moveId: SandboxMoveId,
	label: string,
	scalingTag: ScalingTag,
	staminaCost: number,
	slot: PrimarySlot,
	legality: ActionLegality,
	targets: { TargetOdds },
	qte: "None" | "Standard" | "HighRiskThreeCheck",
	effectiveQteMode: QteMode?,
}

export type BeltPreview = {
	targetId: ActorId,
	legality: ActionLegality,
	summary: string,
	hpGain: number?,
	staminaGain: number?,
	resolveGain: number?,
	dodgeGainPp: number?,
	removes: { StatusId }?,
	cancelsIntentId: string?,
}

export type BeltItemView = {
	itemId: BeltItemId,
	label: string,
	stock: number,
	legality: ActionLegality,
	targets: { BeltPreview },
}

export type PartyBelt = {
	beltChargesRemaining: number,
	directHealsRemaining: number,
	medKitUsed: boolean,
	items: { BeltItemView },
}

export type RedirectTarget = {
	recipientId: ActorId,
	recipientIsDefending: boolean,
	legality: ActionLegality,
}

export type RedirectView = {
	intentId: string,
	originalTargetId: ActorId,
	usesRemaining: number,
	legality: ActionLegality,
	targets: { RedirectTarget },
}

export type CompanionView = {
	actorId: ActorId,
	tacticMode: TacticMode,
	tacticLegality: ActionLegality,
	assistAvailableThisRound: boolean,
	redirect: RedirectView?,
}

export type ExposureView = {
	targetId: ActorId,
	mitigationPenaltyPp: number,
	-- Omitted if the next eligible party Primary does not yet have a known owner.
	exposedFollowUpActorId: ActorId?,
}

export type ManualQteCheck = {
	index: QteCheckIndex,
	approachStartsAtServerTime: number,
	overlapAtServerTime: number,
	opensAtServerTime: number,
	closesAtServerTime: number,
}

export type UntimedQteCheck = {
	index: QteCheckIndex,
	prompt: string,
	choices: { QteInput },
}

export type QteCheckResult = "Pending" | "Hit" | "Miss"

-- The server returns one result per check in the same order as the checks array.
export type QtePrompt =
	{
		id: string,
		mode: "Manual",
		kind: "Standard" | "HighRiskThreeCheck",
		checks: { ManualQteCheck },
		checkResults: { QteCheckResult },
		nextCheckIndex: QteCheckIndex?,
	}
	| {
		id: string,
		mode: "UntimedCue",
		kind: "HighRiskThreeCheck",
		checks: { UntimedQteCheck },
		checkResults: { QteCheckResult },
		nextCheckIndex: QteCheckIndex?,
	}

export type SandboxLogEvent = {
	turn: number,
	kind: "Action" | "Damage" | "Guard" | "Defeated" | "Outcome" | "Dodged" | "FailedQTE_0of3"
		| "Interrupt" | "UVCancel" | "Redirect" | "Assist" | "ItemUsed" | "Resolve" | "Status",
	actorId: ActorId?,
	targetId: ActorId?,
	moveId: string?,
	intentId: string?,
	amount: number?,
	qteGrade: QteGrade?,
	resolveDelta: number?,
	message: string,
}

export type BattleHudSnapshot = {
	battleId: string,
	revision: number,
	turn: number,
	playerActorId: ActorId,
	activeActorId: ActorId?,
	actors: { SandboxActorState },
	turnOrder: { TurnOrderEntry },
	enemyIntents: { SandboxIntent },
	-- Options belong to activeActorId.
	primaryOptions: { PrimaryOption },
	endTurnLegality: ActionLegality,
	belt: PartyBelt,
	companion: CompanionView?,
	exposure: ExposureView?,
	qteMode: QteMode,
	qtePrompt: QtePrompt?,
	log: { SandboxLogEvent },
}

export type SandboxSnapshot = BattleHudSnapshot & {
	stageTag: "Night" | "Neutral",
	blackSabbathStep: "LighterStrike" | "ShadowGrabWindup" | "ShadowGrabLanding" | "FadeIntoShadow",
	outcome: CombatOutcome,
}

local highRiskHeavy = table.freeze({
	baseMultiplier = 1.70,
	timingByGrade = table.freeze({ [0] = 0, [1] = 0.35, [2] = 0.70, [3] = 1.00 }),
	resolveOnLandedFull = 15,
	resolveOnDodgedFull = 0,
	resolveOnPartialOrFailed = -1,
})

return table.freeze({
	HighRiskHeavy = highRiskHeavy,
	Phase2Limits = table.freeze({
		BonusPrimariesPerActorPerRound = 1,
		MaxResolve = 100,
		ResolveGainPerTurn = 25,
		OnFireTurns = 2,
		LowHpResolve = 20,
		PartyBeltCharges = 3,
		DirectHealsPerFight = 2,
		MedKitsPerFight = 1,
		CompanionRedirectsPerFight = 1,
		ManualAssistStrength = 0.25,
		ExposedMitigationPp = 15,
		FadeDodgePp = 20,
		ShadowGrabMultiplier = 1.65,
	}),
})
