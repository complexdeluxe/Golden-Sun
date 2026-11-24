--!strict

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
	kind: "Action" | "Damage" | "Guard" | "Join" | "Flee" | "Outcome",
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

return table.freeze({})
