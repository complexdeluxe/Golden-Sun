--!strict

local Combat = require("../Contracts/CombatTypes")
local Assets = require("../Contracts/AssetManifest")

local function actor(
	id: Combat.ActorId,
	name: string,
	team: Combat.Team,
	spriteKey: Assets.AssetKey,
	health: number,
	armor: number,
	speed: number,
	stamina: number,
	maxStamina: number
): Combat.ActorState
	return {
		id = id,
		displayName = name,
		team = team,
		spriteKey = spriteKey,
		hp = health,
		maxHp = health,
		armor = armor,
		speed = speed,
		power = 0,
		stamina = stamina,
		maxStamina = maxStamina,
		isDefending = false,
	}
end

local moves: { [Combat.MoveId]: { power: number, cost: number, label: string } } = {
	QuickStrike = { power = 7, cost = 0, label = "Quick Strike" },
	HeavyStrike = { power = 12, cost = 3, label = "Heavy Strike" },
	Defend = { power = 0, cost = 0, label = "Defend" },
}

return table.freeze({
	newPlayer = function() return actor("player", "Player", "Player", "PlayerIdle", 32, 1, 6, 3, 5) end,
	newDario = function() return actor("dario", "Dario", "Enemy", "DarioIdle", 40, 1, 4, 0, 0) end,
	newWife = function() return actor("wife", "Dario’s wife", "Enemy", "DarioWifeIdle", 20, 0, 5, 0, 0) end,
	moves = moves,
	guard = 3,
	darioStrike = 5,
	wifeStrike = 4,
	wifeHeal = 4,
	joinAt = 20,
	darioFleeAt = 6,
	wifeFleeAt = 3,
})
