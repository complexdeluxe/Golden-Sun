--!strict

local CombatTypes = require("./CombatTypes")
local SaveTypes = require("./SaveTypes")

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

return table.freeze({
	FolderName = "TutorialRemotes",
	StartTutorial = remoteFunction("StartTutorial"),
	SubmitPrimaryAction = remoteFunction("SubmitPrimaryAction"),
	RetryTutorial = remoteFunction("RetryTutorial"),
	ChooseOrigin = remoteFunction("ChooseOrigin"),
})
