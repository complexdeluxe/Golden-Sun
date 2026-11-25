--!strict

local Appearance = require("../Contracts/CharacterAppearanceTypes")
local Combat = require("../Contracts/CombatTypes")
local Inventory = require("../Contracts/InventoryTypes")

export type Offer = { price: number, cap: number }
export type Item = {
	display: Inventory.ItemDisplay,
	beltItemId: Combat.BeltItemId?,
	gearSlot: Inventory.GearSlot?,
	baseStatLines: { string }?,
	offer: Offer?,
}

local catalog: Appearance.Catalog = {
	defaultAppearance = { skinToneId = "Tan", hairStyleId = "buzz" },
	skinTones = {
		{ id = "Fair", label = "Fair", swatchHex = "#F1C9A5" },
		{ id = "Tan", label = "Tan", swatchHex = "#D9A066" },
		{ id = "Brown", label = "Brown", swatchHex = "#9C6B43" },
		{ id = "Deep", label = "Deep", swatchHex = "#5E3B25" },
	},
	hairStyles = {
		{ id = "buzz", label = "Buzz Cut", legality = { canUse = true } },
		{ id = "pompadour", label = "Pompadour", legality = { canUse = true } },
		{ id = "long", label = "Long", legality = { canUse = true } },
		{ id = "spiky", label = "Spiky", legality = { canUse = true } },
		{ id = "cap", label = "Cap", legality = { canUse = true } },
		{ id = "bald", label = "Bald", legality = { canUse = true } },
	},
}

-- Starter prices and stock are for the Act 1 server playtest.
local items: { [string]: Item } = {
	["training-wraps"] = {
		display = { itemId = "training-wraps", label = "Training Wraps", description = "Simple cloth wraps for close combat." },
		gearSlot = "Weapon", baseStatLines = { "+2 Physical" },
	},
	["brimmed-cap"] = {
		display = { itemId = "brimmed-cap", label = "Brimmed Cap", description = "An ordinary cap with a sturdy brim." },
		gearSlot = "Head", baseStatLines = { "+2 Focus" }, offer = { price = 45, cap = 1 },
	},
	["tonio-water"] = {
		display = { itemId = "tonio-water", label = "Mineral Water", description = "Restores 25% of max HP to the user.", iconKey = "MineralWaterIcon" },
		beltItemId = "MineralWater", offer = { price = 10, cap = 8 },
	},
	["med-kit"] = {
		display = { itemId = "med-kit", label = "Speedwagon Med-Kit", description = "Restores 40% of max HP to one ally.", iconKey = "MedKitIcon" },
		beltItemId = "MedKit", offer = { price = 25, cap = 3 },
	},
}

return table.freeze({
	Catalog = catalog,
	Items = items,
	ItemOrder = table.freeze({ "training-wraps", "brimmed-cap", "tonio-water", "med-kit" }),
	BeltSlots = 3,
	StartingYen = 60,
})
