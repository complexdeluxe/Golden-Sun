--!strict

local Combat = require("../Contracts/CombatTypes")

export type Move = {
	id: Combat.SandboxMoveId,
	label: string,
	tag: Combat.ScalingTag,
	cost: number,
	multiplier: number,
	qte: "None" | "Standard" | "HighRiskThreeCheck",
}

export type Item = { id: Combat.BeltItemId, label: string, stock: number, healFraction: number? }

local moves: { Move } = {
	{ id = "BasicStrike", label = "Basic Strike", tag = "AutoBest", cost = 0, multiplier = 1, qte = "None" },
	{ id = "HeavyStrike", label = "Heavy Strike", tag = "Physical", cost = 3, multiplier = 1.50, qte = "Standard" },
	{ id = "HighRiskHeavy", label = "High-Risk Heavy", tag = "Hybrid", cost = 3, multiplier = Combat.HighRiskHeavy.baseMultiplier, qte = "HighRiskThreeCheck" },
	{ id = "Defend", label = "Defend", tag = "Physical", cost = 0, multiplier = 0, qte = "None" },
	{ id = "HamonInterrupt", label = "Hamon Interrupt", tag = "Special", cost = 2, multiplier = 0.75, qte = "None" },
	{ id = "Finisher", label = "Finisher", tag = "AutoBest", cost = 0, multiplier = 2, qte = "None" },
}

local items: { Item } = {
	{ id = "MineralWater", label = "Mineral Water", stock = 2, healFraction = 0.25 },
	{ id = "CapreseSalad", label = "Caprese Salad", stock = 1, healFraction = 0.35 },
	{ id = "MedKit", label = "Speedwagon Med-Kit", stock = 1, healFraction = 0.40 },
	{ id = "CoffeeGum", label = "Coffee Gum", stock = 1 },
	{ id = "UVFlash", label = "UV Flash Capsule", stock = 1 },
	{ id = "SmokePellet", label = "Smoke Pellet", stock = 1 },
	{ id = "PassioneEspresso", label = "Passione Espresso", stock = 1 },
	{ id = "SmellingSalts", label = "Smelling Salts", stock = 1 },
	{ id = "SpikedWhetstone", label = "Spiked Whetstone", stock = 1 },
}

return table.freeze({
	Moves = moves,
	Items = items,
	Choices = table.freeze({ "Left", "Center", "Right" } :: { Combat.QteInput }),
})
