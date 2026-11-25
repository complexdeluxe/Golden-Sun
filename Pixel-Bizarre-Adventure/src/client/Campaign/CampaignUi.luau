--!strict
-- Shared pieces for the Phase 3 campaign screens (Creator, Hub, Act Map,
-- Results): buttons that follow server legality, 32 x 32 item tiles with a
-- placeholder, and the player preview built from appearance IDs.
--
-- Everything is in native pixels on the 320 x 180 grid.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetManifest = require(ReplicatedStorage.Shared.Contracts.AssetManifest)
local CombatTypes = require(ReplicatedStorage.Shared.Contracts.CombatTypes)
local AppearanceTypes = require(ReplicatedStorage.Shared.Contracts.CharacterAppearanceTypes)
local PixelUi = require(script.Parent.Parent.Battle.PixelUi)
local AppearanceArt = require(script.Parent.Parent.Battle.AppearanceArt)

type Legality = CombatTypes.ActionLegality
type Appearance = AppearanceTypes.Appearance

local Colors = PixelUi.Colors

local CampaignUi = {}

CampaignUi.Colors = {
	Gold = Color3.fromHex("#f2c94c"),
	GoldDark = Color3.fromHex("#8a6a1c"),
	Purple = Color3.fromHex("#8f5bd9"),
	PurpleDark = Color3.fromHex("#2a1f45"),
	Backdrop = Color3.fromHex("#15182a"),
	Tile = Color3.fromHex("#232842"),
	TileEmpty = Color3.fromHex("#1a1e33"),
	Cleared = Color3.fromHex("#59c27a"),
	Locked = Color3.fromHex("#3a3d52"),
	Yen = Color3.fromHex("#f2c94c"),
}


export type Button = {
	outline: Frame,
	fill: Frame,
	button: TextButton,
	setText: (text: string) -> (),
	setState: (state: "Normal" | "Selected" | "Disabled" | "Primary") -> (),
}

-- An outlined button. Its colour shows whether it can be used.
function CampaignUi.button(parent: Instance, name: string, x: number, y: number, w: number, h: number, text: string): Button
	local outline, fill = PixelUi.box(parent, name, x, y, w, h, Colors.Button)
	local button = PixelUi.button(fill, "Press", 0, 0, w - 2, h - 2, text)
	local function setState(state: "Normal" | "Selected" | "Disabled" | "Primary")
		if state == "Disabled" then
			fill.BackgroundColor3 = Colors.Disabled
			button.TextColor3 = Colors.TextDim
			outline.BackgroundColor3 = Colors.Ink
		elseif state == "Selected" then
			fill.BackgroundColor3 = Colors.ButtonHover
			button.TextColor3 = CampaignUi.Colors.Gold
			outline.BackgroundColor3 = CampaignUi.Colors.Gold
		elseif state == "Primary" then
			fill.BackgroundColor3 = CampaignUi.Colors.GoldDark
			button.TextColor3 = Colors.Text
			outline.BackgroundColor3 = CampaignUi.Colors.Gold
		else
			fill.BackgroundColor3 = Colors.Button
			button.TextColor3 = Colors.Text
			outline.BackgroundColor3 = Colors.Ink
		end
	end
	return {
		outline = outline,
		fill = fill,
		button = button,
		setText = function(value: string)
			button.Text = value
		end,
		setState = setState,
	}
end

function CampaignUi.reason(legality: Legality): string
	if legality.canUse then
		return ""
	end
	return legality.disabledReason or "Not available."
end

-- Three-letter code for a placeholder tile, for example "Mineral Water" -> "MIN".
function CampaignUi.code(label: string): string
	local words = string.split(string.upper(label), " ")
	if #words >= 2 then
		return string.sub(words[1], 1, 2) .. string.sub(words[2], 1, 1)
	end
	return string.sub(words[1] or "?", 1, 3)
end

local function assetFor(key: AssetManifest.AssetKey?): string?
	if not key then
		return nil
	end
	local id = (AssetManifest :: any)[key]
	if type(id) ~= "string" or id == PixelUi.UNSET_ASSET then
		return nil
	end
	return id
end
CampaignUi.assetFor = assetFor

export type Tile = {
	outline: Frame,
	fill: Frame,
	button: TextButton,
	set: (iconKey: AssetManifest.AssetKey?, label: string?, badge: string?) -> (),
	setHighlight: (color: Color3?) -> (),
}

-- An item tile at native size (32 x 32 in grids, 16 x 16 in shop rows). An unset
-- icon shows a placeholder with a short code. An empty tile shows `emptyText`.
function CampaignUi.tile(parent: Instance, name: string, x: number, y: number, size: number, emptyText: string): Tile
	local outline, fill = PixelUi.box(parent, name, x, y, size + 2, size + 2, CampaignUi.Colors.TileEmpty)
	local image = PixelUi.image(fill, "Icon", 0, 0, size, size, "")
	image.Visible = false
	local code = PixelUi.label(fill, "Code", 0, 0, size, size, emptyText, Colors.TextDim, Enum.TextXAlignment.Center)
	local badge = PixelUi.label(fill, "Badge", 0, size - 8, size - 1, 8, "", Colors.Text, Enum.TextXAlignment.Right)
	badge.ZIndex = 2
	local button = PixelUi.button(fill, "Press", 0, 0, size, size, "")
	button.ZIndex = 3
	local function set(iconKey: AssetManifest.AssetKey?, label: string?, badgeText: string?)
		local id = assetFor(iconKey)
		if label == nil then
			fill.BackgroundColor3 = CampaignUi.Colors.TileEmpty
			image.Visible = false
			code.Visible = true
			code.Text = emptyText
			code.TextColor3 = Colors.TextDim
		elseif id then
			fill.BackgroundColor3 = CampaignUi.Colors.Tile
			image.Image = id
			image.Visible = true
			code.Visible = false
		else
			fill.BackgroundColor3 = CampaignUi.Colors.Tile
			image.Visible = false
			code.Visible = true
			code.Text = CampaignUi.code(label)
			code.TextColor3 = Colors.Text
		end
		badge.Text = badgeText or ""
	end
	return {
		outline = outline,
		fill = fill,
		button = button,
		set = set,
		setHighlight = function(color: Color3?)
			outline.BackgroundColor3 = color or Colors.Ink
		end,
	}
end

export type Preview = {
	root: Frame,
	set: (appearance: Appearance?, swatchHex: string?) -> (),
}

-- The player on a 96 x 96 canvas, built from the selected skin and hair IDs.
-- Uses the body/hair sprites when the manifest has them, otherwise a silhouette.
function CampaignUi.preview(parent: Instance, name: string, x: number, y: number): Preview
	local root = PixelUi.frame(parent, name, x, y, 96, 96)
	local body = PixelUi.frame(root, "Body", 0, 0, 96, 96)
	local function set(appearance: Appearance?, swatchHex: string?)
		body:ClearAllChildren()
		local skin = AppearanceArt.skinColor(appearance, swatchHex)
		local top = Color3.fromHex("#3d6fb0")
		local legs = Color3.fromHex("#2a2f4a")
		local parts: { { any } } = {
			{ 38, 40, 20, 26, top },
			{ 39, 66, 8, 22, legs },
			{ 49, 66, 8, 22, legs },
			{ 34, 42, 5, 18, top },
			{ 57, 42, 5, 18, skin },
			{ 41, 28, 14, 13, skin },
		}
		for index, part in parts do
			PixelUi.box(body, `Part{index}`, part[1], part[2], part[3], part[4], part[5])
		end
		PixelUi.frame(body, "Eye", 52, 34, 2, 2, Colors.Ink)
		for index, shape in AppearanceArt.hairShapes(appearance) do
			PixelUi.frame(body, `Hair{index}`, shape[1], shape[2], shape[3], shape[4], AppearanceArt.HAIR_COLOR)
		end
	end
	set(nil, nil)
	return { root = root, set = set }
end

-- Top bar used by the Hub, Act Map and Results: title, level, Yen.
export type TopBar = {
	root: Frame,
	set: (title: string, level: number, yen: number, extra: string?) -> (),
}

function CampaignUi.topBar(parent: Instance): TopBar
	local root = PixelUi.frame(parent, "TopBar", 0, 0, 320, 14, CampaignUi.Colors.PurpleDark)
	PixelUi.frame(root, "Edge", 0, 13, 320, 1, CampaignUi.Colors.Purple)
	local title = PixelUi.label(root, "Title", 4, 2, 150, 10, "", CampaignUi.Colors.Gold)
	-- Party line, for example "+ SPEEDWAGON". The MOCK SERVER badge sits at 160..222.
	local extra = PixelUi.label(root, "Extra", 4, 2, 150, 10, "", Colors.TextDim, Enum.TextXAlignment.Right)
	local level = PixelUi.label(root, "Level", 226, 2, 36, 10, "", Colors.Active, Enum.TextXAlignment.Right)
	local yen = PixelUi.label(root, "Yen", 264, 2, 52, 10, "", CampaignUi.Colors.Yen, Enum.TextXAlignment.Right)
	return {
		root = root,
		set = function(titleText: string, levelValue: number, yenValue: number, extraText: string?)
			title.Text = titleText
			level.Text = `LV {levelValue}`
			yen.Text = `{yenValue} YEN`
			extra.Text = extraText or ""
		end,
	}
end

return CampaignUi
