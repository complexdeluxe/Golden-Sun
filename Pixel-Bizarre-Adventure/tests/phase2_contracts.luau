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
	checkResults = { "Hit", "Miss", "Pending" },
	nextCheckIndex = 3,
}
local check: Remote.SandboxQteCheckRequest = {
	battleId = primary.battleId,
	challengeId = prompt.id,
	checkIndex = 3,
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

local endTurn: Remote.SandboxSecondaryRequest = {
	battleId = primary.battleId,
	expectedRevision = 2,
	kind = "EndTurn",
	actorId = primary.actorId,
}
local fade: Combat.StatusView = {
	id = "Fade",
	label = "Fade (+20 Dodge)",
	isRemovable = false,
	turnsRemaining = 1,
}
local endTurnLegality: index<Combat.SandboxSnapshot, "endTurnLegality"> = { canUse = true, disabledReason = nil }
assert(endTurn.kind == "EndTurn" and endTurn.actorId == primary.actorId and endTurnLegality.canUse)
assert(fade.id == "Fade" and fade.turnsRemaining == 1 and not fade.isRemovable)
assert(prompt.checkResults[1] == "Hit" and prompt.checkResults[2] == "Miss" and prompt.checkResults[check.checkIndex] == "Pending")

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
for _, assetId in { Assets.TutorialStage, Assets.BlackSabbathStage, Assets.UVFlashIcon, Assets.CompanionIdle } do
	assert(string.match(assetId, "^rbxassetid://[1-9]%d*$"), "Expected a populated Roblox asset ID")
end
local heavy = Combat.HighRiskHeavy
assert(heavy.baseMultiplier == 1.70 and heavy.timingByGrade[0] == 0 and heavy.timingByGrade[3] == 1)
assert(heavy.timingByGrade[1] == 0.35 and heavy.timingByGrade[2] == 0.70)
assert(heavy.resolveOnLandedFull == 15 and heavy.resolveOnDodgedFull == 0 and heavy.resolveOnPartialOrFailed == -1)
local limits = Combat.Phase2Limits
assert(limits.PartyBeltCharges == 3 and limits.DirectHealsPerFight == 2 and limits.MedKitsPerFight == 1)
assert(limits.BonusPrimariesPerActorPerRound == 1 and limits.ResolveGainPerTurn == 25)
print("Phase 2 contract smoke passed: Build 1 compatibility, sandbox routes, QTE, and belt limits")
