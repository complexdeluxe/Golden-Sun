--!strict
-- Draws one fighter on a 96 x 96 canvas with the feet on row 88.
--
-- If AssetManifest has a real image for the fighter, that image is shown with
-- pixelated scaling. While the manifest still holds the "rbxassetid://0"
-- placeholder, a simple ink-outlined silhouette (about 60 px tall) is drawn so
-- the battle reads correctly before the final sprites are uploaded.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetManifest = require(ReplicatedStorage.Shared.Contracts.AssetManifest)
local PixelUi = require(script.Parent.PixelUi)

export type Palette = { skin: Color3, top: Color3, legs: Color3, hair: Color3 }

local CANVAS = 96
local FEET_ROW = 88

local PALETTES: { [string]: Palette } = {
	PlayerIdle = {
		skin = Color3.fromHex("#d9a066"), -- Tan ramp placeholder
		top = Color3.fromHex("#3d6fb0"),
		legs = Color3.fromHex("#2a2f4a"),
		hair = Color3.fromHex("#2b1d14"),
	},
	DarioIdle = {
		skin = Color3.fromHex("#e0b48a"),
		top = Color3.fromHex("#6b4a2b"),
		legs = Color3.fromHex("#3a2c22"),
		hair = Color3.fromHex("#5a5048"),
	},
	DarioWifeIdle = {
		skin = Color3.fromHex("#e8c09a"),
		top = Color3.fromHex("#7a3d6b"),
		legs = Color3.fromHex("#5b2d50"),
		hair = Color3.fromHex("#8a5a2b"),
	},
	CompanionIdle = {
		skin = Color3.fromHex("#c98b5a"),
		top = Color3.fromHex("#3f8a5c"),
		legs = Color3.fromHex("#2d3b33"),
		hair = Color3.fromHex("#d9c35a"),
	},
	BlackSabbathIdle = {
		skin = Color3.fromHex("#2a2438"),
		top = Color3.fromHex("#14111f"),
		legs = Color3.fromHex("#14111f"),
		hair = Color3.fromHex("#7a4fd6"),
	},
}

local FALLBACK: Palette = {
	skin = Color3.fromHex("#c8a07a"),
	top = Color3.fromHex("#6d6f80"),
	legs = Color3.fromHex("#3c3e4f"),
	hair = Color3.fromHex("#2b2b2b"),
}

local FighterSprite = {}

local function silhouette(canvas: Frame, palette: Palette, facingLeft: boolean)
	-- Parts are listed back to front as { x, y, w, h, color } with the feet on row 88.
	local top = FEET_ROW - 60
	local parts: { { any } } = {
		{ 38, top + 12, 20, 26, palette.top }, -- torso
		{ 39, top + 38, 8, 22, palette.legs }, -- left leg
		{ 49, top + 38, 8, 22, palette.legs }, -- right leg
		{ 34, top + 14, 5, 18, palette.top }, -- back arm
		{ 57, top + 14, 5, 18, palette.top }, -- front arm
		{ 41, top, 14, 13, palette.skin }, -- head
		{ 41, top, 14, 4, palette.hair }, -- hair
	}
	for index, part in parts do
		local x = part[1] :: number
		local w = part[3] :: number
		if facingLeft then
			x = CANVAS - x - w
		end
		PixelUi.box(canvas, `Part{index}`, x, part[2] :: number, w, part[4] :: number, part[5] :: Color3)
	end
	-- Eye, so the facing direction is readable.
	local eyeX = if facingLeft then CANVAS - 52 - 2 else 52
	PixelUi.frame(canvas, "Eye", eyeX, top + 6, 2, 2, PixelUi.Colors.Ink)
end

-- Builds the canvas. The caller positions it so row 88 sits on the floor.
function FighterSprite.create(parent: Instance, spriteKey: AssetManifest.AssetKey?, facingLeft: boolean): Frame
	local canvas = PixelUi.frame(parent, "Sprite", 0, 0, CANVAS, CANVAS)
	local assetId = if spriteKey then AssetManifest[spriteKey] else nil
	if assetId and assetId ~= PixelUi.UNSET_ASSET then
		local image = PixelUi.image(canvas, "Image", 0, 0, CANVAS, CANVAS, assetId)
		if facingLeft then
			-- Mirror without resampling by flipping the image rect.
			image.ImageRectOffset = Vector2.new(CANVAS, 0)
			image.ImageRectSize = Vector2.new(-CANVAS, CANVAS)
		end
	else
		local palette = if spriteKey then PALETTES[spriteKey] or FALLBACK else FALLBACK
		silhouette(canvas, palette, facingLeft)
	end
	return canvas
end

FighterSprite.CANVAS = CANVAS
FighterSprite.FEET_ROW = FEET_ROW

return FighterSprite
