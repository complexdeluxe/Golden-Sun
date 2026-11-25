--!strict
-- Placeholder art for the player's chosen look (skin tone + hairstyle), shared
-- by the Creator / Hub preview and the battle screens while the modular body
-- and hair sprites are still unset in AssetManifest.
--
-- Hair shapes are { x, y, w, h } on the 96 x 96 fighter canvas, drawn facing
-- right, with the head at (41, 28) sized 14 x 13 (see FighterSprite).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AppearanceTypes = require(ReplicatedStorage.Shared.Contracts.CharacterAppearanceTypes)

type Appearance = AppearanceTypes.Appearance

local AppearanceArt = {}

AppearanceArt.HAIR_COLOR = Color3.fromHex("#2b1d14")

-- The Creator catalog's swatchHex wins when the caller has it.
local SKIN_FALLBACK: { [string]: string } = {
	Fair = "#f1c9a5",
	Tan = "#d9a066",
	Brown = "#9c6b43",
	Deep = "#5e3b25",
}

local HAIR_SHAPES: { [string]: { { number } } } = {
	bald = {},
	buzz = { { 41, 28, 14, 2 } },
	pompadour = { { 41, 26, 14, 4 }, { 49, 22, 9, 5 } },
	long = { { 40, 27, 16, 4 }, { 39, 29, 3, 14 } },
	spiky = { { 41, 27, 14, 3 }, { 42, 24, 2, 3 }, { 46, 23, 2, 4 }, { 50, 24, 2, 3 }, { 54, 25, 2, 2 } },
	cap = { { 40, 26, 16, 4 }, { 52, 29, 7, 2 } },
}
local DEFAULT_HAIR = { { 41, 28, 14, 4 } }

function AppearanceArt.skinColor(appearance: Appearance?, swatchHex: string?): Color3
	local hex = swatchHex or (appearance and SKIN_FALLBACK[appearance.skinToneId]) or SKIN_FALLBACK.Tan
	return Color3.fromHex(hex)
end

-- Unknown hairstyle IDs get a plain cap so a new catalog entry still draws.
function AppearanceArt.hairShapes(appearance: Appearance?): { { number } }
	if appearance == nil then
		return DEFAULT_HAIR
	end
	return HAIR_SHAPES[appearance.hairStyleId] or DEFAULT_HAIR
end

return AppearanceArt
