--!strict

local AssetManifest = require("./AssetManifest")
local Combat = require("./CombatTypes")

export type ItemId = string
-- Unique within the player's inventory. Phase 4 defines persisted gear UUIDs.
export type EntryId = string
export type GearSlot = "Weapon" | "Head" | "Body" | "Accessory"
export type GearRarity = "Common" | "Rare" | "Epic" | "Legendary" | "BossSet"

export type ItemDisplay = {
	itemId: ItemId,
	label: string,
	description: string,
	iconKey: AssetManifest.AssetKey?,
}

export type GearEntry = {
	kind: "Gear",
	entryId: EntryId,
	item: ItemDisplay,
	slot: GearSlot,
	tier: number,
	rarity: GearRarity,
	baseStatLines: { string },
	equipLegality: Combat.ActionLegality,
}

export type StackEntry = {
	kind: "Stack",
	entryId: EntryId,
	item: ItemDisplay,
	quantity: number,
	-- A non-belt item can appear in inventory with a disabled belt legality.
	beltLegality: Combat.ActionLegality,
}

export type InventoryEntry = GearEntry | StackEntry

export type GearSlotView = {
	slot: GearSlot,
	entryId: EntryId?,
	legality: Combat.ActionLegality,
}

export type BeltSlotView = {
	-- One-based index in the loadout. Combat belt charges are encounter state.
	index: number,
	entryId: EntryId?,
	legality: Combat.ActionLegality,
}

export type InventoryView = {
	entries: { InventoryEntry },
	gear: { GearSlotView },
	belt: { BeltSlotView },
}

local gearSlots: { GearSlot } = { "Weapon", "Head", "Body", "Accessory" }

return table.freeze({ GearSlots = table.freeze(gearSlots) })
