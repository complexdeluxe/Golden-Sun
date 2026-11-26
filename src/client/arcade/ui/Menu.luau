--!strict
-- Menu: the arcade selection screen (docs/arcade-contract.md v1).
--   Menu.mount(parent: Frame, entries, onPlay: (id: string) -> ()): () -> ()
-- Renders one card per Registry entry and reports Play clicks. Returns an
-- idempotent unmount function. The launcher (Codex runtime) owns transitions,
-- loading/error presentation and the in-game Back action.
-- Mouse/keyboard first; buttons are touch-sized and the list scrolls, so it
-- works in phone portrait.
-- Owner: Claude. No side effects at require time.

local Menu = {}

export type Entry = {
	id: string,
	displayName: string,
	description: string,
	controls: string,
	supportedDevices: { string },
	adapterName: string,
}

local CARD_COLORS = {
	Color3.fromRGB(70, 60, 140),
	Color3.fromRGB(30, 110, 140),
	Color3.fromRGB(150, 90, 30),
	Color3.fromRGB(60, 130, 70),
}

-- Ignore further Play clicks for this long after one is accepted, so a
-- double-click cannot request two launches before the launcher hides the menu.
local PLAY_DEBOUNCE = 0.75

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
	return if out == "" then "?" else out
end

function Menu.mount(parent: Frame, entries: { Entry }, onPlay: (id: string) -> ()): () -> ()
	local conns: { RBXScriptConnection } = {}
	local mounted = true
	local lastPlay = -math.huge

	local root = Instance.new("Frame")
	root.Name = "ArcadeMenu"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(14, 14, 22)
	root.BorderSizePixel = 0

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

	for index, entry in entries do
		local card = Instance.new("Frame")
		card.Name = "Card_" .. entry.id
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
		thumb.Text = initials(entry.displayName)
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
		end
		text(entry.displayName, 22, Enum.Font.GothamBold, Color3.fromRGB(255, 215, 0), 1)
		text(entry.description, 15, Enum.Font.Gotham, Color3.new(1, 1, 1), 2)
		text("Controls: " .. entry.controls, 13, Enum.Font.Gotham, Color3.fromRGB(190, 190, 205), 3)
		if entry.supportedDevices and #entry.supportedDevices > 0 then
			text("Devices: " .. table.concat(entry.supportedDevices, ", "), 12, Enum.Font.GothamMedium, Color3.fromRGB(150, 200, 255), 4)
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

		local id = entry.id
		table.insert(conns, play.Activated:Connect(function()
			local now = os.clock()
			if not mounted or now - lastPlay < PLAY_DEBOUNCE then
				return
			end
			lastPlay = now
			onPlay(id)
		end))

		card.Parent = list
	end

	root.Parent = parent

	return function()
		if not mounted then
			return
		end
		mounted = false
		for _, c in conns do
			c:Disconnect()
		end
		table.clear(conns)
		root:Destroy()
	end
end

return Menu
