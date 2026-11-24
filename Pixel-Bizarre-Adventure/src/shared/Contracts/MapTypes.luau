--!strict

local AssetManifest = require("./AssetManifest")
local Combat = require("./CombatTypes")
local Inventory = require("./InventoryTypes")

export type NodeId = "F1" | "F2" | "D1"
export type NodeState = "Locked" | "Available" | "Cleared"
export type RunMode = "FirstClear" | "Replay"
export type StageTag = "Neutral" | "Night" | "WaterRain" | "Sunlit"
export type PlayOptionId = string
export type EncounterId = string
export type CompanionId = string

export type PlayOption = {
	id: PlayOptionId,
	label: string,
	mode: RunMode,
	tier: number,
	levelsOnClear: number,
	-- The server can expose a discovered variant as its own option on replay.
	variantLabel: string?,
	legality: Combat.ActionLegality,
}

export type NodeView = {
	id: NodeId,
	label: string,
	prerequisites: { NodeId },
	state: NodeState,
	stageTag: StageTag,
	stageAssetKey: AssetManifest.AssetKey?,
	playOptions: { PlayOption },
}

export type ActMapView = {
	act: number,
	part: number,
	level: number,
	nodes: { NodeView },
}

export type ActiveEncounter = {
	encounterId: EncounterId,
	battleId: string,
	nodeId: NodeId,
	mode: RunMode,
	stageTag: StageTag,
}

export type ItemReward = {
	item: Inventory.ItemDisplay,
	quantity: number,
}

export type EncounterResult = {
	encounterId: EncounterId,
	nodeId: NodeId,
	mode: RunMode,
	outcome: "Clear" | "Defeat" | "Retreat",
	rewards: { yen: number, levels: number, items: { ItemReward } },
}

export type CompanionView =
	{ state: "Locked" }
	| { state: "Offered", offerId: string, companionId: CompanionId, label: string, legality: Combat.ActionLegality }
	| { state: "Recruited", companionId: CompanionId, label: string }

local nodeOrder: { NodeId } = { "F1", "F2", "D1" }

return table.freeze({ NodeOrder = table.freeze(nodeOrder) })
