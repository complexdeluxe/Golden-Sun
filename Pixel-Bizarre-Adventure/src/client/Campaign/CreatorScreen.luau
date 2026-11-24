--!strict
-- Character Creator: pick one of four skin tones and a hairstyle, then commit.
-- The look is set once for this character. Options come from the server
-- catalog, including whether each hairstyle can be picked.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AppearanceTypes = require(ReplicatedStorage.Shared.Contracts.CharacterAppearanceTypes)
local HubTypes = require(ReplicatedStorage.Shared.Contracts.HubTypes)
local PixelUi = require(script.Parent.Parent.Battle.PixelUi)
local CampaignUi = require(script.Parent.CampaignUi)
local Screen = require(script.Parent.Screen)

type Snapshot = HubTypes.CampaignSnapshot
type Catalog = AppearanceTypes.Catalog
type Appearance = AppearanceTypes.Appearance

local Colors = PixelUi.Colors
local Gold = CampaignUi.Colors

local HAIR_ROWS = 4
local HAIR_COLUMNS = 2

local CreatorScreen = {}

function CreatorScreen.new(root: Frame, actions: Screen.Actions): Screen.Screen
	local frame = PixelUi.frame(root, "Creator", 0, 0, 320, 180, Gold.Backdrop)

	PixelUi.label(frame, "Title", 14, 4, 140, 10, "CREATE YOUR FIGHTER", Gold.Gold)
	PixelUi.label(frame, "Sub", 14, 15, 292, 8, "Your look is set once for this character.", Colors.TextDim)

	-- Left: preview on a small stage.
	local stageOutline = PixelUi.box(frame, "Stage", 14, 30, 110, 112, Gold.PurpleDark)
	PixelUi.frame(stageOutline, "Floor", 1, 96, 108, 15, Colors.Floor)
	local preview = CampaignUi.preview(stageOutline, "Preview", 7, 8)
	local lookLabel = PixelUi.label(frame, "Look", 14, 144, 110, 9, "", Colors.Text, Enum.TextXAlignment.Center)

	-- Right: skin swatches, then hairstyles.
	PixelUi.label(frame, "SkinTitle", 136, 30, 170, 9, "SKIN TONE", Gold.Gold)
	local swatches: { { outline: Frame, fill: Frame, button: TextButton, label: TextLabel } } = {}
	for i = 1, 4 do
		local x = 136 + (i - 1) * 44
		local outline, fill = PixelUi.box(frame, `Skin{i}`, x, 40, 40, 16, Colors.Panel)
		local chip = PixelUi.frame(fill, "Chip", 2, 2, 10, 10, Colors.Panel)
		local label = PixelUi.label(fill, "Label", 13, 0, 25, 14, "", Colors.Text)
		local button = PixelUi.button(fill, "Press", 0, 0, 38, 14, "")
		swatches[i] = { outline = outline, fill = chip, button = button, label = label }
	end

	PixelUi.label(frame, "HairTitle", 136, 62, 170, 9, "HAIRSTYLE", Gold.Gold)
	local hairButtons: { CampaignUi.Button } = {}
	for i = 1, HAIR_ROWS * HAIR_COLUMNS do
		local column = (i - 1) % HAIR_COLUMNS
		local row = (i - 1) // HAIR_COLUMNS
		hairButtons[i] = CampaignUi.button(frame, `Hair{i}`, 136 + column * 88, 72 + row * 15, 84, 13, "")
	end
	local hint = PixelUi.label(frame, "Hint", 136, 134, 172, 9, "", Colors.TextDim)
	local confirm = CampaignUi.button(frame, "Confirm", 196, 150, 112, 18, "CONFIRM LOOK")

	local catalog: Catalog? = nil
	local selected: Appearance? = nil
	local busy = false
	local hintText = ""

	local function swatchHex(cat: Catalog, id: string): string?
		for _, tone in cat.skinTones do
			if tone.id == id then
				return tone.swatchHex
			end
		end
		return nil
	end

	local function hairLabel(cat: Catalog, id: string): string
		for _, style in cat.hairStyles do
			if style.id == id then
				return style.label
			end
		end
		return id
	end

	local function hairLegal(cat: Catalog, id: string): boolean
		for _, style in cat.hairStyles do
			if style.id == id then
				return style.legality.canUse
			end
		end
		return false
	end

	local function refresh()
		local cat = catalog
		local look = selected
		if not cat or not look then
			return
		end
		preview.set(look, swatchHex(cat, look.skinToneId))
		lookLabel.Text = `{string.upper(look.skinToneId)} / {string.upper(hairLabel(cat, look.hairStyleId))}`
		for i, swatch in swatches do
			local tone = cat.skinTones[i]
			swatch.outline.Visible = tone ~= nil
			if tone then
				swatch.fill.BackgroundColor3 = Color3.fromHex(tone.swatchHex)
				swatch.label.Text = string.upper(tone.label)
				swatch.outline.BackgroundColor3 = if tone.id == look.skinToneId then Gold.Gold else Colors.Ink
			end
		end
		for i, button in hairButtons do
			local style = cat.hairStyles[i]
			button.outline.Visible = style ~= nil
			if style then
				button.setText(string.upper(style.label))
				button.setState(if not style.legality.canUse then "Disabled" elseif style.id == look.hairStyleId then "Selected" else "Normal")
			end
		end
		local ready = not busy and hairLegal(cat, look.hairStyleId)
		confirm.setState(if ready then "Primary" else "Disabled")
		confirm.setText(if busy then "SAVING..." else "CONFIRM LOOK")
		hint.Text = hintText
	end

	for i, swatch in swatches do
		swatch.button.Activated:Connect(function()
			local cat, look = catalog, selected
			if busy or not cat or not look or not cat.skinTones[i] then
				return
			end
			selected = { skinToneId = cat.skinTones[i].id, hairStyleId = look.hairStyleId }
			hintText = ""
			refresh()
		end)
	end
	for i, button in hairButtons do
		button.button.Activated:Connect(function()
			local cat, look = catalog, selected
			local style = if cat then cat.hairStyles[i] else nil
			if busy or not look or not style then
				return
			end
			if not style.legality.canUse then
				hintText = CampaignUi.reason(style.legality)
			else
				selected = { skinToneId = look.skinToneId, hairStyleId = style.id }
				hintText = ""
			end
			refresh()
		end)
	end
	confirm.button.Activated:Connect(function()
		local look = selected
		if busy or not look then
			return
		end
		actions.submit({ kind = "CommitAppearance", appearance = { skinToneId = look.skinToneId, hairStyleId = look.hairStyleId } })
	end)

	local self = {} :: Screen.Screen

	function self.render(_self: Screen.Screen, snapshot: Snapshot)
		local scene = snapshot.scene
		if scene.kind ~= "Creator" then
			return
		end
		catalog = scene.catalog
		if selected == nil then
			local default = scene.catalog.defaultAppearance
			selected = { skinToneId = default.skinToneId, hairStyleId = default.hairStyleId }
		end
		refresh()
	end

	function self.setBusy(_self: Screen.Screen, value: boolean)
		busy = value
		refresh()
	end

	function self.destroy(_self: Screen.Screen)
		frame:Destroy()
	end

	return self
end

return CreatorScreen
