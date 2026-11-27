--!strict

local Appearance = require("../Contracts/CharacterAppearanceTypes")
local Assets = require("../Contracts/AssetManifest")
local Combat = require("../Contracts/CombatTypes")
local Inventory = require("../Contracts/InventoryTypes")
local Map = require("../Contracts/MapTypes")
local Save = require("../Contracts/SaveTypes")

export type Offer = { price: number, cap: number }
export type Item = {
	display: Inventory.ItemDisplay,
	beltItemId: Combat.BeltItemId?,
	gearSlot: Inventory.GearSlot?,
	baseStatLines: { string }?,
	offer: Offer?,
}

local DEFAULT_HAIR_COLOR = "#242633"
local hairColors: { Appearance.HairColorOption } = {
	{ id = "jet-black", label = "Jet Black", hex = DEFAULT_HAIR_COLOR },
	{ id = "espresso", label = "Espresso", hex = "#5C3B28" },
	{ id = "dio-gold", label = "Dio Gold", hex = "#F2C94C" },
	{ id = "josuke-indigo", label = "Indigo", hex = "#4B5799" },
	{ id = "kakyoin-red", label = "Crimson", hex = "#D94A5A" },
	{ id = "polnareff-silver", label = "Silver", hex = "#DCE2F0" },
	{ id = "jolyne-green", label = "Emerald", hex = "#52C488" },
	{ id = "giorno-magenta", label = "Magenta", hex = "#D968A8" },
}

local catalog: Appearance.Catalog = {
	defaultAppearance = { skinToneId = "Tan", hairStyleId = "buzz", hairColorHex = DEFAULT_HAIR_COLOR },
	hairColors = hairColors,
	skinTones = {
		{ id = "Fair", label = "Fair", swatchHex = "#F1C9A5", bodySpriteKey = "PlayerBodyFair" },
		{ id = "Tan", label = "Tan", swatchHex = "#D9A066", bodySpriteKey = "PlayerBodyTan" },
		{ id = "Brown", label = "Brown", swatchHex = "#9C6B43", bodySpriteKey = "PlayerBodyBrown" },
		{ id = "Deep", label = "Deep", swatchHex = "#5E3B25", bodySpriteKey = "PlayerBodyDeep" },
	},
	hairStyles = {
		{ id = "buzz", label = "Buzz Cut", overlaySpriteKey = "HairBuzz", legality = { canUse = true } },
		{ id = "pompadour", label = "Pompadour", overlaySpriteKey = "HairPompadour", legality = { canUse = true } },
		{ id = "long", label = "Long", overlaySpriteKey = "HairLong", legality = { canUse = true } },
		{ id = "spiky", label = "Spiky", overlaySpriteKey = "HairSpiky", legality = { canUse = true } },
		{ id = "cap", label = "Cap", overlaySpriteKey = "HairCap", accentSpriteKey = "HairCapTrim", legality = { canUse = true } },
		{ id = "bald", label = "Bald", legality = { canUse = true } },
	},
}

-- Starter prices and stock are for the Act 1 server playtest.
local items: { [string]: Item } = {
	["training-wraps"] = {
		display = { itemId = "training-wraps", label = "Training Wraps", description = "Simple cloth wraps for close combat.", iconKey = "TrainingWrapsIcon" },
		gearSlot = "Weapon", baseStatLines = { "+2 Physical" },
	},
	["brimmed-cap"] = {
		display = { itemId = "brimmed-cap", label = "Brimmed Cap", description = "An ordinary cap with a sturdy brim.", iconKey = "BrimmedCapIcon" },
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

type Stage = { label: string, tag: Map.StageTag, assetKey: Assets.AssetKey }
type ActOneRoute = { part: number, stages: { [Map.ActOneNodeId]: Stage } }

local actOneRoutes: { [Save.Origin]: ActOneRoute } = {
	Part1_Hamon = {
		part = 1,
		stages = {
			F1 = { label = "Ogre Street", tag = "Neutral", assetKey = "OgreStreetStage" },
			F2 = { label = "Night Alley", tag = "Night", assetKey = "NightAlleyStage" },
			D1 = { label = "Ogre Street Hideout", tag = "Neutral", assetKey = "OgreHideoutStage" },
		},
	},
	Part3_Stand = {
		part = 3,
		stages = {
			F1 = { label = "Tokyo Jail", tag = "Neutral", assetKey = "TokyoJailStage" },
			F2 = { label = "Tokyo Schoolyard", tag = "Neutral", assetKey = "TokyoSchoolyardStage" },
			D1 = { label = "Tiger Balm Garden", tag = "Neutral", assetKey = "TigerBalmGardenStage" },
		},
	},
}

return table.freeze({
	ActOneRoutes = actOneRoutes,
	Catalog = catalog,
	DefaultHairColor = DEFAULT_HAIR_COLOR,
	HairColors = hairColors,
	Items = items,
	ItemOrder = table.freeze({ "training-wraps", "brimmed-cap", "tonio-water", "med-kit" }),
	BeltSlots = 3,
	StartingYen = 60,
})
