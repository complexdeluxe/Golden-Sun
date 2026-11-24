--!strict

local CombatTypes = require("../src/shared/Contracts/CombatTypes")
local SaveTypes = require("../src/shared/Contracts/SaveTypes")
local Remotes = require("../src/shared/Contracts/RemoteContract")
local Assets = require("../src/shared/Contracts/AssetManifest")

local profile: SaveTypes.Profile = {
	version = SaveTypes.PROFILE_VERSION,
	tutorialCompleted = false,
	origin = nil,
}
local snapshot: CombatTypes.CombatSnapshot = {
	battleId = "tutorial-smoke",
	revision = 1,
	turn = 1,
	playerActorId = "player",
	activeActorId = "player",
	actors = {
		{
			id = "player", displayName = "Player", team = "Player",
			hp = 20, maxHp = 20, stamina = 2, maxStamina = 5,
			armor = 0, speed = 2, power = 1, isDefending = false,
		},
		{
			id = "dario", displayName = "Dario", team = "Enemy",
			hp = 20, maxHp = 20, stamina = 0, maxStamina = 5,
			armor = 0, speed = 1, power = 1, isDefending = false,
		},
	},
	turnOrder = { { actorId = "player", speed = 2 }, { actorId = "dario", speed = 1 } },
	enemyIntents = {
		{
			actorId = "dario", moveId = "DarioAttack", label = "Dario’s strike",
			targetId = "player", landingTurn = 1, telegraphKind = "Attack", estimatedPower = 4,
		},
	},
	actions = {
		{
			moveId = "HeavyStrike", label = "Heavy Strike", staminaCost = 3,
			targetIds = { "dario" }, legality = { canUse = false, disabledReason = "Needs 3 Stamina" },
		},
	},
	log = {},
	outcome = "InProgress",
}
local response: Remotes.TutorialResponse = { ok = true, snapshot = snapshot, profile = profile }

assert(table.isfrozen(CombatTypes) and table.isfrozen(Remotes) and table.isfrozen(Assets))
assert(response.ok == true)
assert(response.snapshot.enemyIntents[1].targetId == response.snapshot.playerActorId)
assert(response.snapshot.actions[1].legality.canUse == false)
assert(response.profile.version == 1 and response.profile.origin == nil)
assert(Remotes.FolderName == "TutorialRemotes")

local expected: { [string]: { read name: string, read className: "RemoteFunction" } } = {
	StartTutorial = Remotes.StartTutorial,
	SubmitPrimaryAction = Remotes.SubmitPrimaryAction,
	RetryTutorial = Remotes.RetryTutorial,
	ChooseOrigin = Remotes.ChooseOrigin,
}
for name, remote in expected do
	assert(remote.name == name and remote.className == "RemoteFunction")
end

local assetKeys: { Assets.AssetKey } = { "TutorialStage", "PlayerIdle", "DarioIdle", "DarioWifeIdle", "PocketWatchIcon" }
for _, key in assetKeys do
	assert(string.match(Assets[key], "^rbxassetid://%d+$") ~= nil, key)
end

print("Phase 0 smoke passed: combat and save shapes, four remote routes, five asset keys")
