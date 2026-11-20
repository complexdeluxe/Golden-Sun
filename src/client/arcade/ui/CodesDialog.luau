--!strict
-- CodesDialog: modal text-entry dialog used for every game's cheat/dev codes.
-- Confirm / Cancel / Enter-to-submit, inline validation feedback.
-- While open it sinks clicks; games must pause and ignore keyboard input
-- (check `CodesDialog.isAnyOpen()` or UserInputService:GetFocusedTextBox()).
-- Owner: Claude.

local CodesDialog = {}
CodesDialog.__index = CodesDialog

local openCount = 0

export type Options = {
	title: string,
	prompt: string,
	placeholder: string?,
	-- Called with trimmed text. Use dialog:setPrompt/setFeedback/close inside.
	onSubmit: (text: string, dialog: any) -> (),
	-- Called once if the player cancels (button or Escape is not bound; button only).
	onCancel: (() -> ())?,
}

export type Dialog = typeof(setmetatable(
	{} :: {
		_root: Frame,
		_prompt: TextLabel,
		_box: TextBox,
		_feedback: TextLabel,
		_closed: boolean,
		_conns: { RBXScriptConnection },
		_opts: Options,
	},
	CodesDialog
))

local function button(parent: Instance, text: string, color: Color3, x: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = text
	b.Text = text
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BackgroundColor3 = color
	b.AutoButtonColor = true
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.new(x, 0, 1, -12)
	b.Size = UDim2.new(0.4, 0, 0, 40)
	b.ZIndex = 52
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = b
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 8)
	pad.PaddingBottom = UDim.new(0, 8)
	pad.Parent = b
	b.Parent = parent
	return b
end

function CodesDialog.isAnyOpen(): boolean
	return openCount > 0
end

function CodesDialog.open(parent: GuiObject, opts: Options): Dialog
	local root = Instance.new("Frame")
	root.Name = "CodesDialog"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.new(0, 0, 0)
	root.BackgroundTransparency = 0.45
	root.Active = true -- sink clicks so they do not reach the game
	root.ZIndex = 50

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0.9, 0, 0, 230)
	panel.BackgroundColor3 = Color3.fromRGB(28, 28, 36)
	panel.ZIndex = 51
	panel.Active = true
	local maxw = Instance.new("UISizeConstraint")
	maxw.MaxSize = Vector2.new(420, 230)
	maxw.Parent = panel
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = panel
	panel.Parent = root

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Text = opts.title
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(255, 215, 0)
	title.Position = UDim2.new(0, 16, 0, 10)
	title.Size = UDim2.new(1, -32, 0, 26)
	title.ZIndex = 52
	title.Parent = panel

	local prompt = Instance.new("TextLabel")
	prompt.Name = "Prompt"
	prompt.BackgroundTransparency = 1
	prompt.Text = opts.prompt
	prompt.Font = Enum.Font.Gotham
	prompt.TextScaled = true
	prompt.TextColor3 = Color3.new(1, 1, 1)
	prompt.Position = UDim2.new(0, 16, 0, 42)
	prompt.Size = UDim2.new(1, -32, 0, 22)
	prompt.ZIndex = 52
	prompt.Parent = panel

	local box = Instance.new("TextBox")
	box.Name = "Entry"
	box.ClearTextOnFocus = false
	box.PlaceholderText = opts.placeholder or "Enter code"
	box.Text = ""
	box.Font = Enum.Font.Code
	box.TextSize = 18
	box.TextColor3 = Color3.new(1, 1, 1)
	box.PlaceholderColor3 = Color3.fromRGB(150, 150, 160)
	box.BackgroundColor3 = Color3.fromRGB(45, 45, 58)
	box.Position = UDim2.new(0, 16, 0, 72)
	box.Size = UDim2.new(1, -32, 0, 40)
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.ZIndex = 52
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 6)
	bc.Parent = box
	local bp = Instance.new("UIPadding")
	bp.PaddingLeft = UDim.new(0, 8)
	bp.Parent = box
	box.Parent = panel

	local feedback = Instance.new("TextLabel")
	feedback.Name = "Feedback"
	feedback.BackgroundTransparency = 1
	feedback.Text = ""
	feedback.Font = Enum.Font.Gotham
	feedback.TextScaled = true
	feedback.TextColor3 = Color3.fromRGB(255, 120, 120)
	feedback.Position = UDim2.new(0, 16, 0, 118)
	feedback.Size = UDim2.new(1, -32, 0, 20)
	feedback.ZIndex = 52
	feedback.Parent = panel

	local confirm = button(panel, "Confirm", Color3.fromRGB(46, 139, 87), 0.27)
	local cancel = button(panel, "Cancel", Color3.fromRGB(120, 50, 50), 0.73)

	local self = setmetatable({
		_root = root,
		_prompt = prompt,
		_box = box,
		_feedback = feedback,
		_closed = false,
		_conns = {},
		_opts = opts,
	}, CodesDialog)

	openCount += 1
	root.Parent = parent

	local function submit()
		if self._closed then
			return
		end
		local text = string.gsub(box.Text, "^%s*(.-)%s*$", "%1")
		if text == "" then
			self:setFeedback("Enter something first.", true)
			return
		end
		local ok, err = pcall(opts.onSubmit, text, self)
		if not ok then
			-- Never let a code handler break the session.
			self:setFeedback("That entry could not be used.", true)
			warn("[Arcade] code handler error: " .. tostring(err))
		end
	end

	table.insert(self._conns, confirm.Activated:Connect(submit))
	table.insert(self._conns, box.FocusLost:Connect(function(enter: boolean)
		if enter then
			submit()
		end
	end))
	table.insert(self._conns, cancel.Activated:Connect(function()
		if self._closed then
			return
		end
		self:close()
		if opts.onCancel then
			opts.onCancel()
		end
	end))

	task.defer(function()
		if not self._closed then
			box:CaptureFocus()
		end
	end)
	return self
end

function CodesDialog.setPrompt(self: Dialog, text: string, placeholder: string?)
	if self._closed then
		return
	end
	self._prompt.Text = text
	self._box.Text = ""
	if placeholder then
		self._box.PlaceholderText = placeholder
	end
	self._feedback.Text = ""
	self._box:CaptureFocus()
end

function CodesDialog.setFeedback(self: Dialog, text: string, isError: boolean?)
	if self._closed then
		return
	end
	self._feedback.Text = text
	self._feedback.TextColor3 = if isError then Color3.fromRGB(255, 120, 120) else Color3.fromRGB(140, 230, 140)
	if isError then
		self._box:CaptureFocus()
	end
end

function CodesDialog.isOpen(self: Dialog): boolean
	return not self._closed
end

-- Idempotent.
function CodesDialog.close(self: Dialog)
	if self._closed then
		return
	end
	self._closed = true
	openCount -= 1
	for _, c in self._conns do
		c:Disconnect()
	end
	table.clear(self._conns)
	if self._box:IsFocused() then
		self._box:ReleaseFocus()
	end
	self._root:Destroy()
end

return CodesDialog
