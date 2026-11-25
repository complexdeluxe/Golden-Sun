--!strict

local CombatTypes = require("./CombatTypes")
local SaveTypes = require("./SaveTypes")
local Appearance = require("./CharacterAppearanceTypes")
local Hub = require("./HubTypes")
local Inventory = require("./InventoryTypes")
local Map = require("./MapTypes")

export type StartTutorialRequest = {}
export type SubmitPrimaryActionRequest = CombatTypes.ActionRequest
export type RetryTutorialRequest = {
	battleId: string,
	expectedRevision: number,
}
export type ChooseOriginRequest = {
	origin: SaveTypes.Origin,
}

export type ErrorCode =
	"InvalidRequest"
	| "NotReady"
	| "BattleNotFound"
	| "StaleRevision"
	| "IllegalAction"
	| "RetryUnavailable"
	| "TutorialIncomplete"
	| "OriginAlreadyChosen"
	| "SaveUnavailable"

export type Rejected = {
	ok: false,
	code: ErrorCode,
	message: string,
	-- Present if the server can return a current battle for resync.
	snapshot: CombatTypes.CombatSnapshot?,
}

export type TutorialResponse =
	{ ok: true, snapshot: CombatTypes.CombatSnapshot, profile: SaveTypes.Profile }
	| Rejected

export type ChooseOriginResponse =
	{ ok: true, profile: SaveTypes.Profile }
	| Rejected

local function remoteFunction(name: string): { read name: string, read className: "RemoteFunction" }
	return table.freeze({ name = name, className = "RemoteFunction" :: "RemoteFunction" })
end

export type StartSandboxRequest = {
	-- The server supports fixtures at levels 10 and 50.
	level: number,
	stageTag: "Night" | "Neutral",
	qteMode: CombatTypes.QteMode,
}

export type SandboxBattleRef = { battleId: string }
export type SandboxBattleRevision = { battleId: string, expectedRevision: number }

export type SandboxPrimaryRequest = SandboxBattleRevision & {
	actorId: CombatTypes.ActorId,
	slot: CombatTypes.PrimarySlot,
	moveId: CombatTypes.SandboxMoveId,
	targetId: CombatTypes.ActorId?,
}

export type SandboxSecondaryRequest = SandboxBattleRevision & (
	{ kind: "UseBeltItem", actorId: CombatTypes.ActorId, itemId: CombatTypes.BeltItemId, targetId: CombatTypes.ActorId }
	| { kind: "SetCompanionTactic", actorId: CombatTypes.ActorId, tacticMode: CombatTypes.TacticMode }
	| { kind: "CompanionGuardRedirect", actorId: CombatTypes.ActorId, intentId: string, recipientId: CombatTypes.ActorId }
	| { kind: "EndTurn", actorId: CombatTypes.ActorId }
)

export type SandboxQteModeRequest = SandboxBattleRevision & { qteMode: CombatTypes.QteMode }

-- Manual checks accept Confirm. Untimed cues accept a directional input.
-- One input per check. Server time and the active challenge determine validity.
export type SandboxQteCheckRequest = SandboxBattleRef & {
	challengeId: string,
	checkIndex: CombatTypes.QteCheckIndex,
	input: CombatTypes.QteSubmissionInput,
}

export type SandboxErrorCode = ErrorCode | "ChallengeExpired" | "InvalidCheck" | "QtePending"

export type SandboxResponse =
	{ ok: true, snapshot: CombatTypes.SandboxSnapshot }
	| { ok: false, code: SandboxErrorCode, message: string, snapshot: CombatTypes.SandboxSnapshot? }

export type SandboxSnapshotChanged = CombatTypes.SandboxSnapshot

export type GetCampaignSnapshotRequest = {}

export type CampaignActionRequest = {
	read sessionId: string,
	read expectedRevision: number,
} & (
	{ read kind: "CommitAppearance", read appearance: Appearance.Appearance }
	| { read kind: "Navigate", read destination: "Hub" | "ActMap" }
	| { read kind: "PurchaseOffer", read offerId: Hub.ShopOfferId, read quantity: number }
	| { read kind: "SetGearSlot", read slot: Inventory.GearSlot, read entryId: Inventory.EntryId? }
	| { read kind: "SetBeltSlot", read index: number, read entryId: Inventory.EntryId? }
	| { read kind: "StartNode", read nodeId: Map.NodeId, read playOptionId: Map.PlayOptionId }
	| { read kind: "RecruitCompanion", read offerId: string }
)

export type CampaignErrorCode = "InvalidRequest" | "NotReady" | "SaveUnavailable" | "ProfileLocked"
	| "StaleRevision" | "IllegalAction" | "InsufficientYen" | "OutOfStock" | "NodeLocked"

export type CampaignResponse =
	{ ok: true, snapshot: Hub.CampaignSnapshot }
	| { ok: false, code: CampaignErrorCode, message: string, snapshot: Hub.CampaignSnapshot? }

export type CampaignSnapshotChanged = Hub.CampaignSnapshot

-- StartNode creates the battle. These routes act on its server-issued battle ID.
export type GetActBattleSnapshotRequest = SandboxBattleRef
export type ActBattlePrimaryRequest = SandboxPrimaryRequest
export type ActBattleSecondaryRequest = SandboxSecondaryRequest
	| (SandboxBattleRevision & { kind: "Retreat", actorId: CombatTypes.ActorId })
export type ActBattleQteCheckRequest = SandboxQteCheckRequest
export type ActBattleQteModeRequest = SandboxQteModeRequest

export type ActBattleResponse =
	{ ok: true, snapshot: Map.ActBattleSnapshot, campaignSnapshot: Hub.CampaignSnapshot? }
	| {
		ok: false,
		code: SandboxErrorCode | "ProfileLocked",
		message: string,
		snapshot: Map.ActBattleSnapshot?,
		campaignSnapshot: Hub.CampaignSnapshot?,
	}

export type ActBattleSnapshotChanged = Map.ActBattleSnapshot

local function remoteEvent(name: string): { read name: string, read className: "RemoteEvent" }
	return table.freeze({ name = name, className = "RemoteEvent" :: "RemoteEvent" })
end

return table.freeze({
	FolderName = "TutorialRemotes",
	StartTutorial = remoteFunction("StartTutorial"),
	SubmitPrimaryAction = remoteFunction("SubmitPrimaryAction"),
	RetryTutorial = remoteFunction("RetryTutorial"),
	ChooseOrigin = remoteFunction("ChooseOrigin"),
	Sandbox = table.freeze({
		FolderName = "BlackSabbathRemotes",
		StartSandbox = remoteFunction("StartSandbox"),
		GetSandboxSnapshot = remoteFunction("GetSandboxSnapshot"),
		SubmitSandboxPrimary = remoteFunction("SubmitSandboxPrimary"),
		SubmitSandboxSecondary = remoteFunction("SubmitSandboxSecondary"),
		SubmitSandboxQteCheck = remoteFunction("SubmitSandboxQteCheck"),
		SetSandboxQteMode = remoteFunction("SetSandboxQteMode"),
		SandboxSnapshotChanged = remoteEvent("SandboxSnapshotChanged"),
	}),
	Campaign = table.freeze({
		FolderName = "CampaignRemotes",
		GetCampaignSnapshot = remoteFunction("GetCampaignSnapshot"),
		SubmitCampaignAction = remoteFunction("SubmitCampaignAction"),
		CampaignSnapshotChanged = remoteEvent("CampaignSnapshotChanged"),
	}),
	ActBattle = table.freeze({
		FolderName = "ActBattleRemotes",
		GetActBattleSnapshot = remoteFunction("GetActBattleSnapshot"),
		SubmitActBattlePrimary = remoteFunction("SubmitActBattlePrimary"),
		SubmitActBattleSecondary = remoteFunction("SubmitActBattleSecondary"),
		SubmitActBattleQteCheck = remoteFunction("SubmitActBattleQteCheck"),
		SetActBattleQteMode = remoteFunction("SetActBattleQteMode"),
		ActBattleSnapshotChanged = remoteEvent("ActBattleSnapshotChanged"),
	}),
})
