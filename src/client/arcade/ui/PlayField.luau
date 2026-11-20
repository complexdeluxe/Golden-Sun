--!strict
-- PlayField: an aspect-locked square that maps the original 400x400 cmu_graphics
-- canvas onto Roblox GUI scale coordinates. 2D only.
-- Owner: Claude (selection UI / game ports).

local PlayField = {}

local LOGICAL = 400

PlayField.LOGICAL = LOGICAL

-- Creates the square play area inside `parent`, letterboxed to preserve aspect ratio.
function PlayField.new(parent: GuiObject, background: Color3?): Frame
	local frame = Instance.new("Frame")
	frame.Name = "PlayField"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = background or Color3.new(0, 0, 0)
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = frame
	frame.Parent = parent
	return frame
end

-- Positions a GuiObject using logical left/top/width/height.
function PlayField.place(obj: GuiObject, left: number, top: number, w: number, h: number)
	obj.Position = UDim2.fromScale(left / LOGICAL, top / LOGICAL)
	obj.Size = UDim2.fromScale(w / LOGICAL, h / LOGICAL)
end

-- cmu opacity (0..100) -> Roblox transparency (1..0).
function PlayField.alpha(opacity: number): number
	return 1 - math.clamp(opacity, 0, 100) / 100
end

export type RectProps = {
	left: number,
	top: number,
	w: number,
	h: number,
	color: Color3?,
	opacity: number?,
	z: number?,
	border: Color3?,
	borderWidth: number?,
	round: boolean?,
	name: string?,
}

function PlayField.rect(parent: GuiObject, p: RectProps): Frame
	local f = Instance.new("Frame")
	f.Name = p.name or "Rect"
	f.BorderSizePixel = 0
	f.BackgroundColor3 = p.color or Color3.new(0, 0, 0)
	f.BackgroundTransparency = PlayField.alpha(p.opacity or 100)
	f.ZIndex = p.z or 1
	PlayField.place(f, p.left, p.top, p.w, p.h)
	if p.border then
		local s = Instance.new("UIStroke")
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Color = p.border
		s.Thickness = p.borderWidth or 2
		s.Parent = f
	end
	if p.round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = f
	end
	f.Parent = parent
	return f
end

export type LabelProps = {
	text: string,
	cx: number,
	cy: number,
	size: number,
	color: Color3?,
	font: Enum.Font?,
	z: number?,
	opacity: number?,
	width: number?,
	name: string?,
}

-- Centered text label. `size` is the original cmu font size in logical pixels.
function PlayField.label(parent: GuiObject, p: LabelProps): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = p.name or "Label"
	l.BackgroundTransparency = 1
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Text = p.text
	l.TextColor3 = p.color or Color3.new(0, 0, 0)
	l.Font = p.font or Enum.Font.GothamBold
	l.TextScaled = true
	l.TextTransparency = PlayField.alpha(p.opacity or 100)
	l.ZIndex = p.z or 5
	local w = p.width or 400
	l.Position = UDim2.fromScale(p.cx / LOGICAL, p.cy / LOGICAL)
	l.Size = UDim2.fromScale(w / LOGICAL, (p.size * 1.15) / LOGICAL)
	l.Parent = parent
	return l
end

-- Re-centres a label after a logical size change.
function PlayField.setLabel(l: TextLabel, cx: number, cy: number, size: number, width: number?)
	l.Position = UDim2.fromScale(cx / LOGICAL, cy / LOGICAL)
	l.Size = UDim2.fromScale((width or 400) / LOGICAL, (size * 1.15) / LOGICAL)
end

-- Converts a screen position to logical playfield coordinates.
function PlayField.toLogical(frame: GuiObject, screen: Vector2): (number, number)
	local abs = frame.AbsolutePosition
	local size = frame.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then
		return -1, -1
	end
	return (screen.X - abs.X) / size.X * LOGICAL, (screen.Y - abs.Y) / size.Y * LOGICAL
end

-- Named cmu_graphics colours used by the ported games.
PlayField.colors = {
	black = Color3.fromRGB(0, 0, 0),
	white = Color3.fromRGB(255, 255, 255),
	royalBlue = Color3.fromRGB(65, 105, 225),
	lightCoral = Color3.fromRGB(240, 128, 128),
	paleGreen = Color3.fromRGB(152, 251, 152),
	darkCyan = Color3.fromRGB(0, 139, 139),
	slateBlue = Color3.fromRGB(106, 90, 205),
	deepPink = Color3.fromRGB(255, 20, 147),
	mediumPurple = Color3.fromRGB(147, 112, 219),
	darkRed = Color3.fromRGB(139, 0, 0),
	cornsilk = Color3.fromRGB(255, 248, 220),
	darkGreen = Color3.fromRGB(0, 100, 0),
	cadetBlue = Color3.fromRGB(95, 158, 160),
	crimson = Color3.fromRGB(220, 20, 60),
	khaki = Color3.fromRGB(240, 230, 140),
	violet = Color3.fromRGB(238, 130, 238),
	tomato = Color3.fromRGB(255, 99, 71),
	peru = Color3.fromRGB(205, 133, 63),
	lightSkyBlue = Color3.fromRGB(135, 206, 250),
	bisque = Color3.fromRGB(255, 228, 196),
	oldLace = Color3.fromRGB(253, 245, 230),
	maroon = Color3.fromRGB(128, 0, 0),
	skyBlue = Color3.fromRGB(135, 206, 235),
	dodgerBlue = Color3.fromRGB(30, 144, 255),
	salmon = Color3.fromRGB(250, 128, 114),
	fireBrick = Color3.fromRGB(178, 34, 34),
	dimGray = Color3.fromRGB(105, 105, 105),
	gainsboro = Color3.fromRGB(220, 220, 220),
	limeGreen = Color3.fromRGB(50, 205, 50),
	chartreuse = Color3.fromRGB(127, 255, 0),
	azure = Color3.fromRGB(240, 255, 255),
	aquamarine = Color3.fromRGB(127, 255, 212),
	cyan = Color3.fromRGB(0, 255, 255),
	darkGoldenrod = Color3.fromRGB(184, 134, 11),
	gold = Color3.fromRGB(255, 215, 0),
	lightCyan = Color3.fromRGB(224, 255, 255),
	orange = Color3.fromRGB(255, 165, 0),
	yellow = Color3.fromRGB(255, 255, 0),
	forestGreen = Color3.fromRGB(34, 139, 34),
	silver = Color3.fromRGB(192, 192, 192),
	lightGray = Color3.fromRGB(211, 211, 211),
	darkOliveGreen = Color3.fromRGB(85, 107, 47),
	oliveDrab = Color3.fromRGB(107, 142, 35),
	seaGreen = Color3.fromRGB(46, 139, 87),
	blue = Color3.fromRGB(0, 0, 255),
	sienna = Color3.fromRGB(160, 82, 45),
	green = Color3.fromRGB(0, 128, 0),
	springGreen = Color3.fromRGB(0, 255, 127),
	darkOrange = Color3.fromRGB(255, 140, 0),
	red = Color3.fromRGB(255, 0, 0),
}

return PlayField
