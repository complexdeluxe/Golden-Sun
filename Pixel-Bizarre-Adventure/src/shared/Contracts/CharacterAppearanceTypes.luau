--!strict

local AssetManifest = require("./AssetManifest")
local Combat = require("./CombatTypes")

export type SkinToneId = "Fair" | "Tan" | "Brown" | "Deep"
export type HairStyleId = string

-- Store catalog IDs so publishing a replacement sprite does not change the save.
export type Appearance = {
	skinToneId: SkinToneId,
	hairStyleId: HairStyleId,
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
	legality: Combat.ActionLegality,
}

export type Catalog = {
	defaultAppearance: Appearance,
	skinTones: { SkinToneOption },
	hairStyles: { HairStyleOption },
}

local skinTones: { SkinToneId } = { "Fair", "Tan", "Brown", "Deep" }

return table.freeze({ SkinTones = table.freeze(skinTones) })
