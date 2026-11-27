--!strict
-- Draws one fighter on a 96 x 96 canvas with the feet on row 88.
--
-- If AssetManifest has a real image for the fighter, that image is shown with
-- pixelated scaling. While the manifest still holds the "rbxassetid://0"
-- placeholder, a simple ink-outlined silhouette (about 60 px tall) is drawn so
-- the battle reads correctly before the final sprites are uploaded.
--
-- The player's Creator look can also arrive as modular layers
-- (CampaignSnapshot.character.appearanceSprites). Once the body layer has a
-- real image, three 96 x 96 images are stacked: body (untinted), hair overlay
-- (tinted with the saved hair colour) and the optional accent (untinted, e.g.
-- HairCapTrim). A missing or unset hair/accent layer is skipped; an unset body
-- falls back to the single sprite or the silhouette above.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetManifest = require(ReplicatedStorage.Shared.Contracts.AssetManifest)
local AppearanceTypes = require(ReplicatedStorage.Shared.Contracts.CharacterAppearanceTypes)
local PixelUi = require(script.Parent.PixelUi)
local AppearanceArt = require(script.Parent.AppearanceArt)

export type Palette = { skin: Color3, top: Color3, legs: Color3, hair: Color3 }

local CANVAS = 96
local FEET_ROW = 88
-- Older saves and clients have no saved colour: Jet Black.
local DEFAULT_HAIR_HEX = "#242633"

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

-- The manifest image for `key`, or nil while it is missing or still unset.
local function assetFor(key: AssetManifest.AssetKey?): string?
	if key == nil then
		return nil
	end
	local id = (AssetManifest :: any)[key]
	if type(id) == "string" and id ~= PixelUi.UNSET_ASSET then
		return id
	end
	return nil
end

-- One full-canvas pixelated layer. Mirrors without resampling by flipping the image rect.
local function layer(canvas: Frame, name: string, assetId: string, facingLeft: boolean, zIndex: number): ImageLabel
	local image = PixelUi.image(canvas, name, 0, 0, CANVAS, CANVAS, assetId)
	image.ZIndex = zIndex
	if facingLeft then
		image.ImageRectOffset = Vector2.new(CANVAS, 0)
		image.ImageRectSize = Vector2.new(-CANVAS, CANVAS)
	end
	return image
end

local function hairColor(hex: string?): Color3
	if hex then
		local ok, color = pcall(Color3.fromHex, hex)
		if ok then
			return color
		end
	end
	return Color3.fromHex(DEFAULT_HAIR_HEX)
end

local function silhouette(canvas: Frame, palette: Palette, facingLeft: boolean, hair: { { number } }?)
	-- Parts are listed back to front as { x, y, w, h, color } with the feet on row 88.
	local top = FEET_ROW - 60
	local parts: { { any } } = {
		{ 38, top + 12, 20, 26, palette.top }, -- torso
		{ 39, top + 38, 8, 22, palette.legs }, -- left leg
		{ 49, top + 38, 8, 22, palette.legs }, -- right leg
		{ 34, top + 14, 5, 18, palette.top }, -- back arm
		{ 57, top + 14, 5, 18, palette.top }, -- front arm
		{ 41, top, 14, 13, palette.skin }, -- head
	}
	if hair == nil then
		table.insert(parts, { 41, top, 14, 4, palette.hair })
	end
	for index, part in parts do
		local x = part[1] :: number
		local w = part[3] :: number
		if facingLeft then
			x = CANVAS - x - w
		end
		PixelUi.box(canvas, `Part{index}`, x, part[2] :: number, w, part[4] :: number, part[5] :: Color3)
	end
	-- The player's chosen hairstyle, as plain pixels over the head.
	for index, shape in hair or {} do
		local x = shape[1]
		if facingLeft then
			x = CANVAS - x - shape[3]
		end
		PixelUi.frame(canvas, `Hair{index}`, x, shape[2], shape[3], shape[4], palette.hair)
	end
	-- Eye, so the facing direction is readable.
	local eyeX = if facingLeft then CANVAS - 52 - 2 else 52
	PixelUi.frame(canvas, "Eye", eyeX, top + 6, 2, 2, PixelUi.Colors.Ink)
end

-- Builds the canvas. The caller positions it so row 88 sits on the floor.
-- `appearance` (the player's Creator look) recolours the placeholder skin and
-- draws the chosen hairstyle; its hairColorHex tints the hair layer.
-- `sprites` (the snapshot's appearanceSprites) draws the modular layers once
-- the body layer has a real image, ahead of `spriteKey`.
function FighterSprite.create(
	parent: Instance,
	spriteKey: AssetManifest.AssetKey?,
	facingLeft: boolean,
	appearance: AppearanceTypes.Appearance?,
	sprites: AppearanceTypes.AppearanceSprites?
): Frame
	local canvas = PixelUi.frame(parent, "Sprite", 0, 0, CANVAS, CANVAS)
	local bodyId = if sprites then assetFor(sprites.bodySpriteKey) else nil
	local assetId = assetFor(spriteKey)
	if sprites and bodyId then
		layer(canvas, "Body", bodyId, facingLeft, 1)
		local hairId = assetFor(sprites.overlaySpriteKey)
		if hairId then
			local hair = layer(canvas, "Hair", hairId, facingLeft, 2)
			hair.ImageColor3 = hairColor(if appearance then appearance.hairColorHex else nil)
		end
		local accentId = assetFor(sprites.accentSpriteKey)
		if accentId then
			layer(canvas, "Accent", accentId, facingLeft, 3)
		end
	elseif assetId then
		layer(canvas, "Image", assetId, facingLeft, 1)
	else
		local palette = if spriteKey then PALETTES[spriteKey] or FALLBACK else FALLBACK
		if appearance then
			palette = {
				skin = AppearanceArt.skinColor(appearance, nil),
				top = palette.top,
				legs = palette.legs,
				hair = AppearanceArt.HAIR_COLOR,
			}
			silhouette(canvas, palette, facingLeft, AppearanceArt.hairShapes(appearance))
		else
			silhouette(canvas, palette, facingLeft, nil)
		end
	end
	return canvas
end

FighterSprite.CANVAS = CANVAS
FighterSprite.FEET_ROW = FEET_ROW

return FighterSprite
