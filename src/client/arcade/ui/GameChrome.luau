--!strict
-- GameChrome: the in-game frame shared by every arcade game.
-- Top bar with the game title, a Controls toggle, a Codes button and a
-- reliable "Menu" (exit) button; the area below is the game's play area.
-- Owner: Claude.

local GameChrome = {}
GameChrome.__index = GameChrome

local BAR = 44

export type Options = {
	title: string,
	controls: { string },
	onCodes: (() -> ())?,
	onExit: () -> (),
}

export type Chrome = typeof(setmetatable(
	{} :: {
		root: Frame,
		playArea: Frame,
		_status: TextLabel,
		_controlsPanel: Frame,
		_conns: { RBXScriptConnection },
		_destroyed: boolean,
		_exiting: boolean,
	},
	GameChrome
))

local function barButton(parent: Instance, text: string, order: number, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Name = text
	b.Text = text
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BackgroundColor3 = color
	b.AutomaticSize = Enum.AutomaticSize.X
	b.Size = UDim2.new(0, 72, 1, -10)
	b.LayoutOrder = order
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = b
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, 10)
	p.PaddingRight = UDim.new(0, 10)
	p.Parent = b
	b.Parent = parent
	return b
end

function GameChrome.new(container: GuiObject, opts: Options): Chrome
	local root = Instance.new("Frame")
	root.Name = "GameChrome"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
	root.BorderSizePixel = 0

	local bar = Instance.new("Frame")
	bar.Name = "TopBar"
	bar.Size = UDim2.new(1, 0, 0, BAR)
	bar.BackgroundColor3 = Color3.fromRGB(24, 24, 34)
	bar.BorderSizePixel = 0
	bar.ZIndex = 20
	bar.Parent = root

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Text = opts.title
	title.Font = Enum.Font.GothamBold
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Color3.fromRGB(255, 215, 0)
	title.Position = UDim2.new(0, 12, 0, 0)
	title.Size = UDim2.new(0.4, 0, 1, 0)
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.ZIndex = 21
	title.Parent = bar

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Text = ""
	status.Font = Enum.Font.Gotham
	status.TextSize = 14
	status.TextColor3 = Color3.fromRGB(200, 200, 210)
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Position = UDim2.new(0, 12, 1, 2)
	status.Size = UDim2.new(1, -24, 0, 18)
	status.ZIndex = 21
	status.Parent = bar

	local buttons = Instance.new("Frame")
	buttons.BackgroundTransparency = 1
	buttons.AnchorPoint = Vector2.new(1, 0)
	buttons.Position = UDim2.new(1, -8, 0, 5)
	buttons.Size = UDim2.new(0.6, 0, 1, 0)
	buttons.ZIndex = 21
	buttons.Parent = bar
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = buttons

	local controlsBtn = barButton(buttons, "Controls", 1, Color3.fromRGB(60, 60, 90))
	local codesBtn: TextButton? = nil
	if opts.onCodes then
		codesBtn = barButton(buttons, "Codes", 2, Color3.fromRGB(110, 80, 20))
	end
	local exitBtn = barButton(buttons, "Menu", 3, Color3.fromRGB(140, 40, 40))

	local playArea = Instance.new("Frame")
	playArea.Name = "PlayArea"
	playArea.BackgroundTransparency = 1
	playArea.Position = UDim2.new(0, 8, 0, BAR + 22)
	playArea.Size = UDim2.new(1, -16, 1, -(BAR + 30))
	playArea.Parent = root

	local panel = Instance.new("Frame")
	panel.Name = "ControlsPanel"
	panel.AnchorPoint = Vector2.new(1, 0)
	panel.Position = UDim2.new(1, -8, 0, BAR + 4)
	panel.Size = UDim2.new(0, 340, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.fromRGB(30, 30, 44)
	panel.BackgroundTransparency = 0.05
	panel.Visible = false
	panel.ZIndex = 40
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(0, 8)
	pc.Parent = panel
	local pp = Instance.new("UIPadding")
	pp.PaddingTop = UDim.new(0, 8)
	pp.PaddingBottom = UDim.new(0, 8)
	pp.PaddingLeft = UDim.new(0, 10)
	pp.PaddingRight = UDim.new(0, 10)
	pp.Parent = panel
	local pl = Instance.new("UIListLayout")
	pl.Padding = UDim.new(0, 4)
	pl.SortOrder = Enum.SortOrder.LayoutOrder
	pl.Parent = panel
	local maxw = Instance.new("UISizeConstraint")
	maxw.MaxSize = Vector2.new(340, math.huge)
	maxw.Parent = panel
	for i, line in opts.controls do
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Text = "• " .. line
		t.Font = Enum.Font.Gotham
		t.TextSize = 14
		t.TextWrapped = true
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextColor3 = Color3.new(1, 1, 1)
		t.AutomaticSize = Enum.AutomaticSize.Y
		t.Size = UDim2.new(1, 0, 0, 16)
		t.LayoutOrder = i
		t.ZIndex = 41
		t.Parent = panel
	end
	panel.Parent = root

	local self = setmetatable({
		root = root,
		playArea = playArea,
		_status = status,
		_controlsPanel = panel,
		_conns = {},
		_destroyed = false,
		_exiting = false,
	}, GameChrome)

	table.insert(self._conns, controlsBtn.Activated:Connect(function()
		panel.Visible = not panel.Visible
	end))
	if codesBtn and opts.onCodes then
		local onCodes = opts.onCodes
		table.insert(self._conns, codesBtn.Activated:Connect(function()
			panel.Visible = false
			onCodes()
		end))
	end
	table.insert(self._conns, exitBtn.Activated:Connect(function()
		-- Debounced: one exit request per session.
		if self._exiting or self._destroyed then
			return
		end
		self._exiting = true
		opts.onExit()
	end))

	root.Parent = container
	return self
end

function GameChrome.setStatus(self: Chrome, text: string)
	if not self._destroyed then
		self._status.Text = text
	end
end

-- Idempotent.
function GameChrome.destroy(self: Chrome)
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

return GameChrome
