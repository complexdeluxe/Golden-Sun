--!strict
-- ArcadeMenu: the selection screen. Pure view: it renders game cards from
-- registry metadata and reports Play clicks. The launcher (Codex runtime)
-- owns switching and drives the menu through setState().
-- Mouse/keyboard first; cards and buttons are sized for touch and the list
-- scrolls, so it works in phone portrait.
-- Owner: Claude.

local ArcadeMenu = {}
ArcadeMenu.__index = ArcadeMenu

export type GameInfo = {
	id: string,
	displayName: string,
	description: string,
	controls: { string },
	devices: { string }?,
}

export type State = "menu" | "loading" | "playing" | "stopping" | "error"

export type Callbacks = {
	onPlay: (id: string) -> (),
}

export type Menu = typeof(setmetatable(
	{} :: {
		root: Frame,
		_list: ScrollingFrame,
		_overlay: Frame,
		_overlayText: TextLabel,
		_overlayBack: TextButton,
		_playButtons: { TextButton },
		_state: State,
		_conns: { RBXScriptConnection },
		_destroyed: boolean,
		_callbacks: Callbacks,
	},
	ArcadeMenu
))

local CARD_COLORS = {
	Color3.fromRGB(70, 60, 140),
	Color3.fromRGB(30, 110, 140),
	Color3.fromRGB(150, 90, 30),
	Color3.fromRGB(60, 130, 70),
}

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function initials(name: string): string
	local out = ""
	for word in string.gmatch(name, "%a+") do
		out ..= string.upper(string.sub(word, 1, 1))
		if #out >= 2 then
			break
		end
	end
	return out
end

local function makeCard(self: any, list: ScrollingFrame, info: GameInfo, index: number)
	local card = Instance.new("Frame")
	card.Name = "Card_" .. info.id
	card.BackgroundColor3 = Color3.fromRGB(30, 30, 44)
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.LayoutOrder = index
	corner(card, 12)
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 12)
	pad.PaddingBottom = UDim.new(0, 12)
	pad.PaddingLeft = UDim.new(0, 12)
	pad.PaddingRight = UDim.new(0, 12)
	pad.Parent = card

	-- Placeholder thumbnail (no art pipeline in scope).
	local thumb = Instance.new("TextLabel")
	thumb.Name = "Thumbnail"
	thumb.Size = UDim2.fromOffset(72, 72)
	thumb.BackgroundColor3 = CARD_COLORS[(index - 1) % #CARD_COLORS + 1]
	thumb.Text = initials(info.displayName)
	thumb.Font = Enum.Font.GothamBlack
	thumb.TextSize = 28
	thumb.TextColor3 = Color3.new(1, 1, 1)
	corner(thumb, 10)
	thumb.Parent = card

	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.new(0, 84, 0, 0)
	body.Size = UDim2.new(1, -84, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.Parent = card
	local bl = Instance.new("UIListLayout")
	bl.Padding = UDim.new(0, 4)
	bl.SortOrder = Enum.SortOrder.LayoutOrder
	bl.Parent = body

	local function text(t: string, size: number, font: Enum.Font, color: Color3, order: number)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Text = t
		l.Font = font
		l.TextSize = size
		l.TextColor3 = color
		l.TextWrapped = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.Size = UDim2.new(1, 0, 0, size + 2)
		l.AutomaticSize = Enum.AutomaticSize.Y
		l.LayoutOrder = order
		l.Parent = body
		return l
	end
	text(info.displayName, 22, Enum.Font.GothamBold, Color3.fromRGB(255, 215, 0), 1)
	text(info.description, 15, Enum.Font.Gotham, Color3.new(1, 1, 1), 2)
	text("Controls: " .. table.concat(info.controls, " · "), 13, Enum.Font.Gotham, Color3.fromRGB(190, 190, 205), 3)
	if info.devices and #info.devices > 0 then
		text("Devices: " .. table.concat(info.devices, ", "), 12, Enum.Font.GothamMedium, Color3.fromRGB(150, 200, 255), 4)
	end

	local play = Instance.new("TextButton")
	play.Name = "Play"
	play.Text = "Play"
	play.Font = Enum.Font.GothamBold
	play.TextSize = 20
	play.TextColor3 = Color3.new(1, 1, 1)
	play.BackgroundColor3 = Color3.fromRGB(46, 139, 87)
	play.Size = UDim2.new(0, 140, 0, 44) -- touch-sized
	play.LayoutOrder = 5
	corner(play, 8)
	play.Parent = body

	table.insert(self._playButtons, play)
	table.insert(self._conns, play.Activated:Connect(function()
		-- Debounce: only a menu in the idle state accepts a launch.
		if self._destroyed or self._state ~= "menu" then
			return
		end
		self:setState("loading", "Loading " .. info.displayName .. "...")
		local ok, err = pcall(self._callbacks.onPlay, info.id)
		if not ok then
			self:setState("error", "Could not start " .. info.displayName .. ": " .. tostring(err))
		end
	end))

	card.Parent = list
end

function ArcadeMenu.new(parent: GuiObject, games: { GameInfo }, callbacks: Callbacks): Menu
	local root = Instance.new("Frame")
	root.Name = "ArcadeMenu"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(14, 14, 22)
	root.BorderSizePixel = 0
	root.ZIndex = 1

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Text = "Golden Sun Arcade"
	title.Font = Enum.Font.GothamBlack
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 215, 0)
	title.AnchorPoint = Vector2.new(0.5, 0)
	title.Position = UDim2.new(0.5, 0, 0, 16)
	title.Size = UDim2.new(0.9, 0, 0, 44)
	title.Parent = root
	local tmax = Instance.new("UITextSizeConstraint")
	tmax.MaxTextSize = 40
	tmax.Parent = title

	local subtitle = Instance.new("TextLabel")
	subtitle.BackgroundTransparency = 1
	subtitle.Text = "Choose a game"
	subtitle.Font = Enum.Font.Gotham
	subtitle.TextSize = 16
	subtitle.TextColor3 = Color3.fromRGB(200, 200, 210)
	subtitle.AnchorPoint = Vector2.new(0.5, 0)
	subtitle.Position = UDim2.new(0.5, 0, 0, 62)
	subtitle.Size = UDim2.new(0.9, 0, 0, 20)
	subtitle.Parent = root

	local list = Instance.new("ScrollingFrame")
	list.Name = "Games"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.AnchorPoint = Vector2.new(0.5, 0)
	list.Position = UDim2.new(0.5, 0, 0, 92)
	list.Size = UDim2.new(1, -24, 1, -104)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 6
	list.Parent = root
	local lmax = Instance.new("UISizeConstraint")
	lmax.MaxSize = Vector2.new(640, math.huge)
	lmax.Parent = list
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = list

	local overlay = Instance.new("Frame")
	overlay.Name = "StatusOverlay"
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.3
	overlay.Active = true -- block card clicks while busy
	overlay.Visible = false
	overlay.ZIndex = 30
	overlay.Parent = root

	local overlayText = Instance.new("TextLabel")
	overlayText.BackgroundTransparency = 1
	overlayText.Font = Enum.Font.GothamBold
	overlayText.TextSize = 20
	overlayText.TextWrapped = true
	overlayText.TextColor3 = Color3.new(1, 1, 1)
	overlayText.AnchorPoint = Vector2.new(0.5, 0.5)
	overlayText.Position = UDim2.fromScale(0.5, 0.45)
	overlayText.Size = UDim2.new(0.85, 0, 0, 120)
	overlayText.ZIndex = 31
	overlayText.Parent = overlay

	local back = Instance.new("TextButton")
	back.Name = "BackToMenu"
	back.Text = "Back to menu"
	back.Font = Enum.Font.GothamBold
	back.TextSize = 18
	back.TextColor3 = Color3.new(1, 1, 1)
	back.BackgroundColor3 = Color3.fromRGB(60, 60, 90)
	back.AnchorPoint = Vector2.new(0.5, 0)
	back.Position = UDim2.fromScale(0.5, 0.62)
	back.Size = UDim2.fromOffset(180, 44)
	back.ZIndex = 31
	back.Visible = false
	corner(back, 8)
	back.Parent = overlay

	local self = setmetatable({
		root = root,
		_list = list,
		_overlay = overlay,
		_overlayText = overlayText,
		_overlayBack = back,
		_playButtons = {},
		_state = "menu" :: State,
		_conns = {},
		_destroyed = false,
		_callbacks = callbacks,
	}, ArcadeMenu)

	for i, info in games do
		makeCard(self, list, info, i)
	end

	table.insert(self._conns, back.Activated:Connect(function()
		if self._state == "error" then
			self:setState("menu")
		end
	end))

	root.Parent = parent
	return self
end

function ArcadeMenu.getState(self: Menu): State
	return self._state
end

-- menu: cards visible and clickable
-- loading / stopping: overlay with message, input blocked
-- playing: menu hidden (game owns the screen)
-- error: overlay with message and a Back to menu button
function ArcadeMenu.setState(self: Menu, state: State, message: string?)
	if self._destroyed then
		return
	end
	self._state = state
	self.root.Visible = state ~= "playing"
	local busy = state == "loading" or state == "stopping" or state == "error"
	self._overlay.Visible = busy
	self._overlayBack.Visible = state == "error"
	self._overlayText.TextColor3 = if state == "error" then Color3.fromRGB(255, 140, 140) else Color3.new(1, 1, 1)
	self._overlayText.Text = message or (if state == "loading" then "Loading..." elseif state == "stopping" then "Returning to menu..." else "")
	for _, b in self._playButtons do
		b.Active = state == "menu"
		b.AutoButtonColor = state == "menu"
	end
end

-- Idempotent.
function ArcadeMenu.destroy(self: Menu)
	if self._destroyed then
		return
	end
	self._destroyed = true
	for _, c in self._conns do
		c:Disconnect()
	end
	table.clear(self._conns)
	self.root:Destroy()
end

return ArcadeMenu
