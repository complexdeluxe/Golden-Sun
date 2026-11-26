--!strict

local AssetManifest = require("./AssetManifest")
local Combat = require("./CombatTypes")

export type LifeId = string
export type HeirloomId = string
export type KitId = string

export type AgeView = {
	currentAge: number,
	-- Always 56. Longevity changes naturalDeathAge only.
	elderThreshold: number,
	naturalDeathAge: number,
	isElder: boolean,
	veteranComposureActive: boolean,
	-- Server preview in years for the upcoming event, when one is known.
	upcomingAgeDelta: number?,
}

export type RecoveryLedgerView = {
	-- Integer 0–5. At zero the life can still enter an uncleared Castle on its final attempt.
	recoveriesRemaining: number,
	maxRecoveries: number,
	isFinalAttempt: boolean,
	act5Vested: boolean,
	-- Sum of eligible Act milestones before retirement or vesting bonuses.
	eligibleEchoes: number,
	-- Server-quoted payouts including vested bonuses and eligible challenge rewards.
	retireNowEchoes: number,
	terminalFallbackEchoes: number,
	canRetireNow: boolean,
	ledgerSettled: boolean,
}

export type BloodlineBranch = "Momentum" | "LegacyLoadout" | "VitalityGrit"
export type BloodlineNodeId =
	"family_purse" | "early_conditioning" | "speedwagon_contacts" | "quartermaster_dispatch"
	| "bloodline_vault" | "resonance_attunement" | "tactical_breadth" | "dual_heirloom_satchel"
	| "bloodline_longevity" | "veteran_composure" | "chrome_resilience"

export type BloodlineNodeView = {
	nodeId: BloodlineNodeId,
	label: string,
	rank: number,
	maxRank: number,
	-- Omitted at max rank. An unaffordable next rank can still have a quoted price.
	nextCostEchoes: number?,
	description: string,
	legality: Combat.ActionLegality,
}

export type BloodlineBranchView = { branchId: BloodlineBranch, nodes: { BloodlineNodeView } }
export type BloodlineTreeView = {
	echoesBalance: number,
	branches: { BloodlineBranchView },
}

export type HeirloomDisplay = {
	id: HeirloomId,
	label: string,
	description: string,
	iconKey: AssetManifest.AssetKey?,
}

export type HeirloomView = {
	catalog: { HeirloomDisplay },
	unlockedIds: { HeirloomId },
	-- Distinct unlocked IDs, at most one by default or two with Dual Heirloom Satchel.
	carriedIds: { HeirloomId },
	-- At most one carried heirloom is active. Change attunement only at the Safe Hub.
	attunedId: HeirloomId?,
	carryLimit: number,
	legality: Combat.ActionLegality,
}

export type MasteryVariant = "Default" | "Alt"
export type MasteryView = {
	kitId: KitId,
	-- Integer 0–8.
	marks: number,
	unlockedAltTarget: boolean,
	-- Alt targeting is selectable at two marks, independently of utility.
	targetMode: MasteryVariant,
	-- Alt is selectable at five marks. Default remains available.
	utilityVariant: MasteryVariant,
	masteryTitleUnlocked: boolean,
}

export type Snapshot = {
	sessionId: string,
	revision: number,
	lifeId: LifeId,
	generation: number,
	age: AgeView,
	recoveryLedger: RecoveryLedgerView,
	bloodlineTree: BloodlineTreeView,
	heirlooms: HeirloomView,
	mastery: { MasteryView },
}

export type Action =
	{ kind: "PurchaseBloodlineNode", nodeId: BloodlineNodeId }
	| { kind: "PassTheTorch", lifeId: LifeId, confirmed: boolean }
	| { kind: "SetCarriedHeirlooms", heirloomIds: { HeirloomId } }
	-- Omit heirloomId to clear the active attunement.
	| { kind: "SetAttunedHeirloom", heirloomId: HeirloomId? }
	| { kind: "SetMasteryVariant", kitId: KitId, variant: MasteryVariant }
	| { kind: "SetMasteryTargetMode", kitId: KitId, targetMode: MasteryVariant }

export type ActionRequest = {
	sessionId: string,
	expectedRevision: number,
	-- Reuse this ID with the same action after an uncertain reply.
	requestId: string,
	action: Action,
}

export type Receipt =
	{ kind: "BloodlineNodePurchased", nodeId: BloodlineNodeId, rank: number, spentEchoes: number }
	| { kind: "PassedTheTorch", retiredLifeId: LifeId, nextLifeId: LifeId, echoesAwarded: number }
	| { kind: "CarriedHeirloomsSet", heirloomIds: { HeirloomId }, attunedId: HeirloomId? }
	| { kind: "AttunedHeirloomSet", heirloomId: HeirloomId? }
	| { kind: "MasteryVariantSet", kitId: KitId, variant: MasteryVariant }
	| { kind: "MasteryTargetModeSet", kitId: KitId, targetMode: MasteryVariant }

export type ErrorCode =
	"InvalidRequest" | "StaleRevision" | "ProfileLocked" | "SaveUnavailable" | "RequestConflict"
	-- FinalAttemptConfirmRequired is for the Castle entry guard, separate from voluntary retirement.
	| "IllegalAction" | "InsufficientEchoes" | "ConfirmationRequired" | "FinalAttemptConfirmRequired" | "AlreadySettled"

export type SnapshotResponse =
	{ ok: true, snapshot: Snapshot }
	| { ok: false, code: ErrorCode, message: string }

export type ActionResponse =
	-- Expose settlement and its idempotency receipt after they commit together.
	{ ok: true, requestId: string, receipt: Receipt, snapshot: Snapshot }
	| { ok: false, requestId: string?, code: ErrorCode, message: string, snapshot: Snapshot? }

local branchOrder: { BloodlineBranch } = { "Momentum", "LegacyLoadout", "VitalityGrit" }
local nodes: { [BloodlineBranch]: { BloodlineNodeId } } = {
	Momentum = { "family_purse", "early_conditioning", "speedwagon_contacts", "quartermaster_dispatch" },
	LegacyLoadout = { "bloodline_vault", "resonance_attunement", "tactical_breadth", "dual_heirloom_satchel" },
	VitalityGrit = { "bloodline_longevity", "veteran_composure", "chrome_resilience" },
}
for _, branchNodes in nodes do table.freeze(branchNodes) end

return table.freeze({
	ElderThreshold = 56,
	MaxRecoveries = 5,
	BaseHeirloomCarryLimit = 1,
	MaxHeirloomCarryLimit = 2,
	MasteryAltTargetMarks = 2,
	MasteryUtilityVariantMarks = 5,
	MasteryTitleMarks = 8,
	BloodlineBranchOrder = table.freeze(branchOrder),
	BloodlineNodeIds = table.freeze(nodes),
})
