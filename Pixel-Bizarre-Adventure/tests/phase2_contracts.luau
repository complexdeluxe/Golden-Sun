--!strict

local Combat = require("../src/shared/Contracts/CombatTypes")
local Remote = require("../src/shared/Contracts/RemoteContract")
local Assets = require("../src/shared/Contracts/AssetManifest")

local start: Remote.StartSandboxRequest = { level = 10, stageTag = "Night", qteMode = "AutoGood" }
local primary: Remote.SandboxPrimaryRequest = {
	battleId = "parity-test",
	expectedRevision = 1,
	actorId = "player",
	slot = "Primary",
	moveId = "HighRiskHeavy",
	targetId = "black-sabbath",
}
local prompt: Combat.QtePrompt = {
	id = "heavy-checks",
	mode = "UntimedCue",
	kind = "HighRiskThreeCheck",
	checks = {
		{ index = 1, prompt = "Read the first cue", choices = { "Left", "Center", "Right" } },
		{ index = 2, prompt = "Read the second cue", choices = { "Left", "Center", "Right" } },
		{ index = 3, prompt = "Read the third cue", choices = { "Left", "Center", "Right" } },
	},
	nextCheckIndex = 1,
}
local check: Remote.SandboxQteCheckRequest = {
	battleId = primary.battleId,
	challengeId = prompt.id,
	checkIndex = 1,
	input = "Left",
}
local redirect: Remote.SandboxSecondaryRequest = {
	battleId = primary.battleId,
	expectedRevision = 1,
	kind = "CompanionGuardRedirect",
	actorId = "player",
	intentId = "shadow-grab",
	recipientId = "companion",
}

assert(start.stageTag == "Night" and start.level == 10)
assert(#prompt.checks == 3 and check.challengeId == prompt.id and redirect.battleId == primary.battleId)
assert(Remote.FolderName == "TutorialRemotes" and Remote.Sandbox.FolderName == "BlackSabbathRemotes")
assert(Remote.Sandbox.StartSandbox.className == "RemoteFunction")
assert(Remote.Sandbox.GetSandboxSnapshot.name == "GetSandboxSnapshot")
assert(Remote.Sandbox.SubmitSandboxPrimary.name == "SubmitSandboxPrimary")
assert(Remote.Sandbox.SubmitSandboxSecondary.name == "SubmitSandboxSecondary")
assert(Remote.Sandbox.SubmitSandboxQteCheck.name == "SubmitSandboxQteCheck")
assert(Remote.Sandbox.SetSandboxQteMode.name == "SetSandboxQteMode")
assert(Remote.Sandbox.SandboxSnapshotChanged.className == "RemoteEvent")
assert(Assets.TutorialStage == "rbxassetid://0" and Assets.BlackSabbathStage == "rbxassetid://0")
assert(Assets.UVFlashIcon == "rbxassetid://0" and Assets.CompanionIdle == "rbxassetid://0")
local heavy = Combat.HighRiskHeavy
assert(heavy.baseMultiplier == 1.70 and heavy.timingByGrade[0] == 0 and heavy.timingByGrade[3] == 1)
assert(heavy.timingByGrade[1] == 0.35 and heavy.timingByGrade[2] == 0.70)
assert(heavy.resolveOnLandedFull == 15 and heavy.resolveOnDodgedFull == 0 and heavy.resolveOnPartialOrFailed == -1)
local limits = Combat.Phase2Limits
assert(limits.PartyBeltCharges == 3 and limits.DirectHealsPerFight == 2 and limits.MedKitsPerFight == 1)
assert(limits.BonusPrimariesPerActorPerRound == 1 and limits.ResolveGainPerTurn == 25)
print("Phase 2 contract smoke passed: Build 1 compatibility, sandbox routes, QTE, and belt limits")
