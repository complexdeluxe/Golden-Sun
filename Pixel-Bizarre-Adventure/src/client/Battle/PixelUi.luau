--!strict
-- Small helpers for building crisp pixel-art UI.
--
-- Every size and position here is in native pixels on the 320 x 180 battle
-- grid. The whole grid is scaled up by a whole number (2x, 3x, 4x...) so pixels
-- never blur or end up different sizes.
--
-- The battle HUD can also draw on a 640 x 360 overlay (layeredRoot + grid):
-- the stage and fighters stay on the 320 x 180 world, while text and chrome
-- get twice the resolution, 1 px borders and 14-16 px text.

local PixelUi = {}

PixelUi.NATIVE_WIDTH = 320
PixelUi.NATIVE_HEIGHT = 180
PixelUi.FONT = Font.fromEnum(Enum.Font.Arcade)
PixelUi.TEXT_SIZE = 8

-- HUD overlay: two overlay pixels per world pixel.
PixelUi.HUD_SCALE = 2
PixelUi.HUD_WIDTH = PixelUi.NATIVE_WIDTH * PixelUi.HUD_SCALE
PixelUi.HUD_HEIGHT = PixelUi.NATIVE_HEIGHT * PixelUi.HUD_SCALE
PixelUi.HUD_TEXT_SIZE = 14
PixelUi.HUD_TITLE_SIZE = 16

PixelUi.Colors = {
	Ink = Color3.fromHex("#0e101a"),
	Panel = Color3.fromHex("#1b1f33"),
	PanelLight = Color3.fromHex("#2c3354"),
	Text = Color3.fromHex("#f4efe1"),
	TextDim = Color3.fromHex("#9a9cb3"),
	Hp = Color3.fromHex("#d8434a"),
	HpBack = Color3.fromHex("#4a1d26"),
	Stamina = Color3.fromHex("#e6b83c"),
	StaminaBack = Color3.fromHex("#4a3d1c"),
	Guard = Color3.fromHex("#59a7e6"),
	Attack = Color3.fromHex("#e6b83c"),
	Heavy = Color3.fromHex("#e0463c"),
	Active = Color3.fromHex("#7fe08a"),
	Disabled = Color3.fromHex("#4b4d5e"),
	Button = Color3.fromHex("#3b4a8c"),
	ButtonHover = Color3.fromHex("#4f62b0"),
	Victory = Color3.fromHex("#f2c94c"),
	Defeat = Color3.fromHex("#c0392b"),
	Mock = Color3.fromHex("#f08c2e"),
	Sky = Color3.fromHex("#252b45"),
	SkyLow = Color3.fromHex("#343c5c"),
	Floor = Color3.fromHex("#4a3f35"),
	FloorEdge = Color3.fromHex("#5e5143"),
	Rain = Color3.fromHex("#6b7aa6"),
}

PixelUi.UNSET_ASSET = "rbxassetid://0"

function PixelUi.frame(parent: Instance?, name: string, x: number, y: number, w: number, h: number, color: Color3?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BorderSizePixel = 0
	frame.Position = UDim2.fromOffset(x, y)
	frame.Size = UDim2.fromOffset(w, h)
	if color then
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = 0
	else
		frame.BackgroundTransparency = 1
	end
	frame.Parent = parent
	return frame
end

-- A filled box with a 1 px ink outline, drawn as two frames so the outline
-- scales with the grid exactly like the rest of the art.
-- Returns the outer frame (position it, hide it) and the inner fill (recolour it).
function PixelUi.box(
	parent: Instance?,
	name: string,
	x: number,
	y: number,
	w: number,
	h: number,
	color: Color3
): (Frame, Frame)
	local outline = PixelUi.frame(parent, name, x, y, w, h, PixelUi.Colors.Ink)
	local fill = PixelUi.frame(outline, "Fill", 1, 1, w - 2, h - 2, color)
	return outline, fill
end

local function styleText(label: TextLabel | TextButton, text: string, color: Color3?, align: Enum.TextXAlignment?)
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.FontFace = PixelUi.FONT
	label.TextSize = PixelUi.TEXT_SIZE
	label.TextColor3 = color or PixelUi.Colors.Text
	label.TextXAlignment = align or Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.Text = text
end

function PixelUi.label(
	parent: Instance?,
	name: string,
	x: number,
	y: number,
	w: number,
	h: number,
	text: string,
	color: Color3?,
	align: Enum.TextXAlignment?
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Position = UDim2.fromOffset(x, y)
	label.Size = UDim2.fromOffset(w, h)
	styleText(label, text, color, align)
	label.Parent = parent
	return label
end

function PixelUi.button(parent: Instance?, name: string, x: number, y: number, w: number, h: number, text: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Position = UDim2.fromOffset(x, y)
	button.Size = UDim2.fromOffset(w, h)
	button.AutoButtonColor = false
	styleText(button, text, PixelUi.Colors.Text, Enum.TextXAlignment.Center)
	button.Parent = parent
	return button
end

-- Pixel-art image with nearest-neighbour scaling. Never use a plain ImageLabel
-- for sprites or stages; they blur.
function PixelUi.image(parent: Instance?, name: string, x: number, y: number, w: number, h: number, assetId: string): ImageLabel
	local image = Instance.new("ImageLabel")
	image.Name = name
	image.BackgroundTransparency = 1
	image.BorderSizePixel = 0
	image.Position = UDim2.fromOffset(x, y)
	image.Size = UDim2.fromOffset(w, h)
	image.Image = assetId
	image.ResampleMode = Enum.ResamplerMode.Pixelated
	image.Parent = parent
	return image
end

-- Horizontal bar with a dark track. Returns the outer frame and a setter.
function PixelUi.bar(
	parent: Instance?,
	name: string,
	x: number,
	y: number,
	w: number,
	h: number,
	fillColor: Color3,
	backColor: Color3
): (Frame, (fraction: number) -> ())
	local outer = PixelUi.frame(parent, name, x, y, w, h, PixelUi.Colors.Ink)
	local track = PixelUi.frame(outer, "Track", 1, 1, w - 2, h - 2, backColor)
	local fill = PixelUi.frame(track, "Fill", 0, 0, w - 2, h - 2, fillColor)
	local function set(fraction: number)
		local inner = w - 2
		local width = math.clamp(math.round(inner * fraction), 0, inner)
		if fraction > 0 and width == 0 then
			width = 1
		end
		fill.Size = UDim2.fromOffset(width, h - 2)
	end
	return outer, set
end

-- Builds the 320 x 180 root inside a full-screen letterbox and keeps it at the
-- largest whole-number scale that fits the screen.
function PixelUi.integerScaledRoot(screenGui: ScreenGui): Frame
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local letterbox = Instance.new("Frame")
	letterbox.Name = "Letterbox"
	letterbox.BackgroundColor3 = Color3.new(0, 0, 0)
	letterbox.BorderSizePixel = 0
	letterbox.Size = UDim2.fromScale(1, 1)
	letterbox.Parent = screenGui

	local root = Instance.new("Frame")
	root.Name = "BattleViewport"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.5)
	root.Size = UDim2.fromOffset(PixelUi.NATIVE_WIDTH, PixelUi.NATIVE_HEIGHT)
	root.BackgroundColor3 = PixelUi.Colors.Sky
	root.BorderSizePixel = 0
	root.ClipsDescendants = true
	root.Parent = letterbox

	local scale = Instance.new("UIScale")
	scale.Parent = root

	local function refit()
		local size = letterbox.AbsoluteSize
		if size.X <= 0 or size.Y <= 0 then
			return
		end
		local fit = math.min(size.X / PixelUi.NATIVE_WIDTH, size.Y / PixelUi.NATIVE_HEIGHT)
		-- Whole-number scale whenever the screen allows it. Only a screen smaller
		-- than 320 x 180 falls back to a fractional shrink.
		scale.Scale = if fit >= 1 then math.floor(fit) else fit
	end
	letterbox:GetPropertyChangedSignal("AbsoluteSize"):Connect(refit)
	refit()

	return root
end

-- The 320 x 180 world root plus a sibling 640 x 360 HUD overlay drawn over it.
-- The overlay covers exactly the same screen rectangle: its scale is always
-- half the world's, so overlay (2x, 2y) sits on world pixel (x, y).
-- Put the stage and fighter sprites on the world, and text and chrome on the HUD.
function PixelUi.layeredRoot(screenGui: ScreenGui): (Frame, Frame)
	local world = PixelUi.integerScaledRoot(screenGui)
	world.ZIndex = 1
	local worldScale = world:FindFirstChildOfClass("UIScale") :: UIScale

	local hud = Instance.new("Frame")
	hud.Name = "HudOverlay"
	hud.AnchorPoint = Vector2.new(0.5, 0.5)
	hud.Position = UDim2.fromScale(0.5, 0.5)
	hud.Size = UDim2.fromOffset(PixelUi.HUD_WIDTH, PixelUi.HUD_HEIGHT)
	hud.BackgroundTransparency = 1
	hud.BorderSizePixel = 0
	hud.ClipsDescendants = true
	hud.ZIndex = 2
	hud.Parent = world.Parent

	local hudScale = Instance.new("UIScale")
	hudScale.Parent = hud
	local function sync()
		hudScale.Scale = worldScale.Scale / PixelUi.HUD_SCALE
	end
	worldScale:GetPropertyChangedSignal("Scale"):Connect(sync)
	sync()

	return world, hud
end

-- Builders for a finer grid that takes the same layout numbers as the world
-- grid. Positions and sizes are multiplied by `scale`, borders and bar tracks
-- stay 1 px of the finer grid, and text uses `textSize`.
export type Grid = {
	scale: number,
	textSize: number,
	offset: (x: number, y: number) -> UDim2,
	frame: (parent: Instance?, name: string, x: number, y: number, w: number, h: number, color: Color3?) -> Frame,
	box: (parent: Instance?, name: string, x: number, y: number, w: number, h: number, color: Color3) -> (Frame, Frame),
	label: (
		parent: Instance?,
		name: string,
		x: number,
		y: number,
		w: number,
		h: number,
		text: string,
		color: Color3?,
		align: Enum.TextXAlignment?
	) -> TextLabel,
	button: (parent: Instance?, name: string, x: number, y: number, w: number, h: number, text: string) -> TextButton,
	image: (parent: Instance?, name: string, x: number, y: number, w: number, h: number, assetId: string) -> ImageLabel,
	bar: (
		parent: Instance?,
		name: string,
		x: number,
		y: number,
		w: number,
		h: number,
		fillColor: Color3,
		backColor: Color3
	) -> (Frame, (fraction: number) -> ()),
}

function PixelUi.grid(scale: number, textSize: number): Grid
	local s = scale
	local grid: Grid = {
		scale = scale,
		textSize = textSize,
		offset = function(x, y)
			return UDim2.fromOffset(x * s, y * s)
		end,
		frame = function(parent, name, x, y, w, h, color)
			return PixelUi.frame(parent, name, x * s, y * s, w * s, h * s, color)
		end,
		box = function(parent, name, x, y, w, h, color)
			return PixelUi.box(parent, name, x * s, y * s, w * s, h * s, color)
		end,
		label = function(parent, name, x, y, w, h, text, color, align)
			local label = PixelUi.label(parent, name, x * s, y * s, w * s, h * s, text, color, align)
			label.TextSize = textSize
			return label
		end,
		button = function(parent, name, x, y, w, h, text)
			local button = PixelUi.button(parent, name, x * s, y * s, w * s, h * s, text)
			button.TextSize = textSize
			return button
		end,
		image = function(parent, name, x, y, w, h, assetId)
			return PixelUi.image(parent, name, x * s, y * s, w * s, h * s, assetId)
		end,
		bar = function(parent, name, x, y, w, h, fillColor, backColor)
			return PixelUi.bar(parent, name, x * s, y * s, w * s, h * s, fillColor, backColor)
		end,
	}
	return grid
end

return PixelUi
