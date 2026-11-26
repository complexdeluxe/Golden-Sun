--!strict

local Inventory = require("./InventoryTypes")

-- Server-issued UUID. Use as the inventory entry ID for this gear copy.
export type ItemUuid = string
export type Tier = number -- Integer 1–5.
export type TemperLevel = number -- Integer 0–10.
export type BaseStatId = "Physical" | "Special" | "Defense" | "Focus" | "Speed"
	| "Health" | "Stamina" | "Precision" | "DefPen"
export type BaseStatLine = { statId: BaseStatId, value: number }
export type AffixId =
	"flat_physical" | "flat_special" | "flat_defense" | "flat_focus" | "flat_speed"
	| "precision_pp" | "control_resist_pp" | "def_pen_pp" | "crit_pp"
	| "cond_dmg_bleed" | "proc_bleed_or_burn"
export type RolledLine = { affixId: AffixId, value: number }
export type PurifiedPerkId =
	"iron_ward" | "keen_edge" | "steady_sight" | "clear_mind" | "armor_piercer" | "measured_breath"

export type PendingSmithOffer = {
	offerId: string,
	-- Proposed replacement lines. The item retains the old package until acceptance.
	lines: { RolledLine },
}

export type ItemInstance = {
	uuid: ItemUuid,
	familyId: Inventory.ItemId,
	slot: Inventory.GearSlot,
	tier: Tier,
	rarity: Inventory.GearRarity,
	-- Fixed, untempered stat lines. Effective stats are derived from temperLevel.
	baseStats: { BaseStatLine },
	-- Plain gear has zero lines. Rolled gear has 1–3 distinct lines within its tier budget.
	rolledLines: { RolledLine },
	temperLevel: TemperLevel,
	-- Consecutive failed attempts at the next level, reset on success.
	temperPityFailures: number,
	cursed: boolean,
	-- Present only after purification. A purified item cannot also be cursed.
	purifiedPerk: PurifiedPerkId?,
	-- Persist atomically with payment before revealing. Block reroll and trade until resolved.
	pendingSmithOffer: PendingSmithOffer?,
}

return table.freeze({})
