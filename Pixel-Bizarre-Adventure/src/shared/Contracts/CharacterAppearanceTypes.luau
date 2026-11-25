--!strict

local AssetManifest = require("./AssetManifest")
local Combat = require("./CombatTypes")

export type SkinToneId = "Fair" | "Tan" | "Brown" | "Deep"
export type HairStyleId = string

-- Save the selected IDs and color. Older clients and saves may omit the color.
export type Appearance = {
	skinToneId: SkinToneId,
	hairStyleId: HairStyleId,
	hairColorHex: string?,
}

-- Campaign snapshots resolve these layers from the selected IDs on every scene.
export type AppearanceSprites = {
	read bodySpriteKey: AssetManifest.AssetKey?,
	read overlaySpriteKey: AssetManifest.AssetKey?,
	read accentSpriteKey: AssetManifest.AssetKey?,
}

export type SkinToneOption = {
	id: SkinToneId,
	label: string,
	swatchHex: string,
	bodySpriteKey: AssetManifest.AssetKey?,
}

export type HairStyleOption = {
	id: HairStyleId,
	label: string,
	overlaySpriteKey: AssetManifest.AssetKey?,
	accentSpriteKey: AssetManifest.AssetKey?,
	legality: Combat.ActionLegality,
}

export type HairColorOption = { id: string, label: string, hex: string }

export type Catalog = {
	defaultAppearance: Appearance,
	skinTones: { SkinToneOption },
	hairStyles: { HairStyleOption },
	-- The live catalog supplies the swatches. Older offline mocks may omit them.
	hairColors: { HairColorOption }?,
}

local skinTones: { SkinToneId } = { "Fair", "Tan", "Brown", "Deep" }

return table.freeze({ SkinTones = table.freeze(skinTones) })
