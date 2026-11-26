--!strict

local Combat = require("./CombatTypes")
local Inventory = require("./InventoryTypes")

export type Act = number -- Integer 1–5. This is the Act tier in either origin route.
export type AutoBattleRunId = string
export type ExpeditionMissionId = string
export type UtcSeconds = number -- Whole Unix seconds from the server clock.

-- Both activities exclude XP, Mastery Marks, and Echoes from previews and grants.
export type CraftingBundle = {
	yen: number,
	salvageShards: number,
	materials: number,
}

export type AutoBattleRewardPreview = CraftingBundle & {
	-- Per-tick ceiling. Boss Sets, Boss Discs, and Golden Apples are excluded.
	maxStandardGearDrops: number,
}

export type StandardGearGrant = {
	entryId: Inventory.EntryId,
	item: Inventory.ItemDisplay,
	slot: Inventory.GearSlot,
	tier: number,
	rarity: "Common" | "Rare" | "Epic" | "Legendary",
}

export type AutoBattleClaim = {
	runId: AutoBattleRunId,
	act: Act,
	ticksClaimed: number,
	-- The last paid tick boundary, independent of the wall-clock time of the claim.
	lastClaimedAtUtc: UtcSeconds,
	rewards: CraftingBundle,
	standardGear: { StandardGearGrant },
}

export type AutoBattleActView = {
	act: Act,
	rewardPreview: AutoBattleRewardPreview,
}

export type AutoBattleView = {
	-- The server only lists Acts this player has manually cleared. Start outside an Act.
	unlockedActs: { AutoBattleActView },
	tickSeconds: number,
	-- An active run and its paid-through timestamp are restored on rejoin. Each
	-- completed tick is eligible for server auto-claim and persistence every 300s.
	runId: AutoBattleRunId?,
	act: Act?,
	startedAtUtc: UtcSeconds?,
	lastClaimedAtUtc: UtcSeconds?,
	pendingTicks: number,
	lastClaim: AutoBattleClaim?,
	legality: {
		start: Combat.ActionLegality,
		claim: Combat.ActionLegality,
		stop: Combat.ActionLegality,
	},
}

export type ExpeditionView = {
	tickets: number,
	-- Two by default. Quartermaster Dispatch raises the cap to three.
	maxTickets: number,
	durationSeconds: number,
	-- One mission slot. A completed mission occupies it until its one-time claim.
	missionId: ExpeditionMissionId?,
	act: Act?,
	startedAtUtc: UtcSeconds?,
	completesAtUtc: UtcSeconds?,
	claimable: boolean,
	-- One bundle worth at most 25% of a same-Act clear, with zero Age,
	-- progression, gear, boss loot, or Disc pity.
	rewardPreview: CraftingBundle?,
	legality: {
		dispatch: Combat.ActionLegality,
		claim: Combat.ActionLegality,
	},
}

export type Snapshot = {
	sessionId: string,
	revision: number,
	serverTimeUtc: UtcSeconds,
	autoBattle: AutoBattleView,
	expedition: ExpeditionView,
}

export type Action =
	{ kind: "StartAutoBattle", act: Act }
	| { kind: "ClaimAutoBattle", runId: AutoBattleRunId }
	| { kind: "StopAutoBattle", runId: AutoBattleRunId }
	| { kind: "DispatchExpedition", act: Act }
	| { kind: "ClaimExpedition", missionId: ExpeditionMissionId }

export type ActionRequest = {
	sessionId: string,
	expectedRevision: number,
	-- Retrying the same action with this ID returns its committed receipt.
	-- Reusing it for a different action returns RequestConflict.
	requestId: string,
	action: Action,
}

export type Receipt =
	{ kind: "AutoBattleStarted", runId: AutoBattleRunId, act: Act, startedAtUtc: UtcSeconds }
	| ({ kind: "AutoBattleClaimed" } & AutoBattleClaim)
	| { kind: "AutoBattleStopped", runId: AutoBattleRunId, stoppedAtUtc: UtcSeconds }
	| {
		kind: "ExpeditionDispatched",
		missionId: ExpeditionMissionId,
		act: Act,
		startedAtUtc: UtcSeconds,
		completesAtUtc: UtcSeconds,
		ticketsSpent: number,
	}
	| { kind: "ExpeditionClaimed", missionId: ExpeditionMissionId, act: Act, rewards: CraftingBundle }

export type ErrorCode =
	"InvalidRequest" | "StaleRevision" | "RequestConflict" | "ProfileLocked" | "SaveUnavailable" | "IllegalAction"
	| "ActNotCleared" | "AutoBattleAlreadyRunning" | "AutoBattleRunMismatch" | "NoPendingTicks"
	| "InsufficientTickets" | "ExpeditionSlotOccupied" | "ExpeditionMissionMismatch" | "ExpeditionNotReady" | "AlreadyClaimed"

export type SnapshotResponse =
	{ ok: true, snapshot: Snapshot }
	| { ok: false, code: ErrorCode, message: string }

export type ActionResponse =
	{ ok: true, requestId: string, receipt: Receipt, snapshot: Snapshot }
	| { ok: false, requestId: string?, code: ErrorCode, message: string, snapshot: Snapshot? }

return table.freeze({
	AutoBattleTickSeconds = 300,
	ExpeditionDurationSeconds = 14400,
	BaseExpeditionMaxTickets = 2,
	QuartermasterExpeditionMaxTickets = 3,
	MaxExpeditionValueFraction = 0.25,
})
