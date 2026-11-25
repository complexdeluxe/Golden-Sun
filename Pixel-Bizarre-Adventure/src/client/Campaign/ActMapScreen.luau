--!strict
-- Node-path Act Map for the Act 1 slice: F1 -> F2 -> D1.
--
-- The client places the nodes (keyed by NodeId). The server decides links,
-- locks, play options and rewards. Pick a node, pick one of its advertised
-- options, then START. The HUB button goes back to change the loadout.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HubTypes = require(ReplicatedStorage.Shared.Contracts.HubTypes)
local MapTypes = require(ReplicatedStorage.Shared.Contracts.MapTypes)
local PixelUi = require(script.Parent.Parent.Battle.PixelUi)
local CampaignUi = require(script.Parent.CampaignUi)
local Screen = require(script.Parent.Screen)

type Snapshot = HubTypes.CampaignSnapshot
type NodeView = MapTypes.NodeView
type PlayOption = MapTypes.PlayOption

local Colors = PixelUi.Colors
local Palette = CampaignUi.Colors

local NODE_SIZE = 24
local OPTION_ROWS = 3
-- Top-left corner of each node on the map, in native px.
local NODE_POSITIONS: { [string]: Vector2 } = {
	F1 = Vector2.new(44, 68),
	F2 = Vector2.new(146, 30),
	D1 = Vector2.new(250, 62),
}
local FALLBACK_X = 20

local STAGE_COLORS: { [string]: Color3 } = {
	Neutral = Color3.fromHex("#6d6f80"),
	Night = Color3.fromHex("#7a4fd6"),
	WaterRain = Color3.fromHex("#59a7e6"),
	Sunlit = Color3.fromHex("#f2c94c"),
}

local ActMapScreen = {}

function ActMapScreen.new(root: Frame, actions: Screen.Actions): Screen.Screen
	local frame = PixelUi.frame(root, "ActMap", 0, 0, 320, 180, Palette.Backdrop)
	local topBar = CampaignUi.topBar(frame)

	local map = PixelUi.frame(frame, "Map", 0, 14, 320, 112, Color3.fromHex("#1d2a2a"))
	PixelUi.frame(map, "Ground", 0, 70, 320, 42, Color3.fromHex("#243326"))
	local paths = PixelUi.frame(map, "Paths", 0, 0, 320, 112)
	local nodesLayer = PixelUi.frame(map, "Nodes", 0, 0, 320, 112)
	local hubButton = CampaignUi.button(frame, "HubButton", 4, 18, 40, 12, "< HUB")

	local panel = PixelUi.frame(frame, "Panel", 0, 126, 320, 54, Palette.PurpleDark)
	PixelUi.frame(panel, "Edge", 0, 0, 320, 1, Palette.Purple)
	local nodeTitle = PixelUi.label(panel, "NodeTitle", 4, 3, 200, 10, "", Palette.Gold)
	local nodeInfo = PixelUi.label(panel, "NodeInfo", 204, 3, 112, 10, "", Colors.TextDim, Enum.TextXAlignment.Right)
	type OptionRow = { button: CampaignUi.Button, tier: TextLabel, reward: TextLabel }
	local optionRows: { OptionRow } = {}
	for i = 1, OPTION_ROWS do
		local y = 14 + (i - 1) * 12
		local button = CampaignUi.button(panel, `Option{i}`, 4, y, 120, 11, "")
		optionRows[i] = {
			button = button,
			tier = PixelUi.label(panel, `Tier{i}`, 128, y + 1, 24, 9, "", Colors.Text),
			reward = PixelUi.label(panel, `Reward{i}`, 152, y + 1, 92, 9, "", Colors.Active),
		}
	end
	local reasonLabel = PixelUi.label(panel, "Reason", 128, 42, 120, 9, "", Colors.Hp)
	local startButton = CampaignUi.button(panel, "Start", 252, 16, 64, 34, "START")

	type NodeWidget = { outline: Frame, fill: Frame, mark: TextLabel, label: TextLabel, button: TextButton }
	local widgets: { [string]: NodeWidget } = {}
	local drawnLinks = ""

	local self = {} :: Screen.Screen
	local snapshot: Snapshot? = nil
	local busy = false
	local selectedNode: string? = nil
	local selectedOption: string? = nil

	local function mapPayload(): MapTypes.ActMapView?
		local current = snapshot
		if current and current.scene.kind == "ActMap" then
			return current.scene.map
		end
		return nil
	end

	local function nodeById(view: MapTypes.ActMapView, id: string?): NodeView?
		for _, node in view.nodes do
			if node.id == id then
				return node
			end
		end
		return nil
	end

	local function position(id: string, index: number): Vector2
		return NODE_POSITIONS[id] or Vector2.new(FALLBACK_X + (index - 1) * 60, 50)
	end

	local function optionById(node: NodeView, id: string?): PlayOption?
		for _, option in node.playOptions do
			if option.id == id then
				return option
			end
		end
		return nil
	end

	-- Dotted path between two node centres; gold once the earlier node is cleared.
	local function drawLinks(view: MapTypes.ActMapView)
		local key = ""
		for _, node in view.nodes do
			key ..= `{node.id}:{node.state};`
		end
		if key == drawnLinks then
			return
		end
		drawnLinks = key
		paths:ClearAllChildren()
		for index, node in view.nodes do
			local to = position(node.id, index) + Vector2.new(NODE_SIZE / 2, NODE_SIZE / 2)
			for _, prereqId in node.prerequisites do
				local prereqIndex = 1
				for i, candidate in view.nodes do
					if candidate.id == prereqId then
						prereqIndex = i
					end
				end
				local prereq = nodeById(view, prereqId)
				local from = position(prereqId, prereqIndex) + Vector2.new(NODE_SIZE / 2, NODE_SIZE / 2)
				local color = if prereq and prereq.state == "Cleared" then Palette.Gold else Palette.Locked
				local distance = (to - from).Magnitude
				local steps = math.floor(distance / 5)
				for step = 1, steps - 1 do
					local point = from:Lerp(to, step / steps)
					PixelUi.frame(paths, `Dot{node.id}{step}`, math.floor(point.X) - 1, math.floor(point.Y) - 1, 2, 2, color)
				end
			end
		end
	end

	local function ensureWidget(node: NodeView, index: number): NodeWidget
		local existing = widgets[node.id]
		if existing then
			return existing
		end
		local at = position(node.id, index)
		local outline, fill = PixelUi.box(nodesLayer, node.id, at.X, at.Y, NODE_SIZE, NODE_SIZE, Palette.Locked)
		local mark = PixelUi.label(fill, "Mark", 0, 0, NODE_SIZE - 2, NODE_SIZE - 2, node.id, Colors.Text, Enum.TextXAlignment.Center)
		local label = PixelUi.label(nodesLayer, `{node.id}Label`, at.X - 28, at.Y + NODE_SIZE + 1, NODE_SIZE + 56, 9, "", Colors.Text, Enum.TextXAlignment.Center)
		local button = PixelUi.button(fill, "Press", 0, 0, NODE_SIZE - 2, NODE_SIZE - 2, "")
		button.ZIndex = 2
		local widget = { outline = outline, fill = fill, mark = mark, label = label, button = button }
		widgets[node.id] = widget
		button.Activated:Connect(function()
			if busy then
				return
			end
			selectedNode = node.id
			selectedOption = nil
			local current = snapshot
			if current then
				self:render(current)
			end
		end)
		return widget
	end

	local function defaultNode(view: MapTypes.ActMapView): string?
		for _, node in view.nodes do
			if node.state == "Available" then
				return node.id
			end
		end
		local last = view.nodes[#view.nodes]
		return if last then last.id else nil
	end

	local function defaultOption(node: NodeView): string?
		for _, option in node.playOptions do
			if option.legality.canUse then
				return option.id
			end
		end
		local first = node.playOptions[1]
		return if first then first.id else nil
	end

	local function renderPanel(view: MapTypes.ActMapView)
		local node = nodeById(view, selectedNode)
		if not node then
			nodeTitle.Text = "PICK A NODE"
			nodeInfo.Text = ""
			for _, row in optionRows do
				row.button.outline.Visible = false
				row.tier.Text = ""
				row.reward.Text = ""
			end
			reasonLabel.Text = ""
			startButton.setState("Disabled")
			return
		end
		if not optionById(node, selectedOption) then
			selectedOption = defaultOption(node)
		end
		nodeTitle.Text = `{node.id}  {string.upper(node.label)}`
		nodeInfo.Text = `{string.upper(node.stageTag)}  {string.upper(node.state)}`
		nodeInfo.TextColor3 = STAGE_COLORS[node.stageTag] or Colors.TextDim
		for i, row in optionRows do
			local option = node.playOptions[i]
			row.button.outline.Visible = option ~= nil
			if option then
				local text = string.upper(option.label)
				if option.variantLabel then
					text ..= ` - {string.upper(option.variantLabel)}`
				end
				row.button.setText(text)
				row.button.setState(if not option.legality.canUse then "Disabled" elseif option.id == selectedOption then "Selected" else "Normal")
				row.tier.Text = `T{option.tier}`
				if option.levelsOnClear > 0 then
					row.reward.Text = `+{option.levelsOnClear} LV FIRST CLEAR`
					row.reward.TextColor3 = Colors.Active
				else
					row.reward.Text = if option.mode == "Replay" then "REPLAY - NO LV" else "NO LV"
					row.reward.TextColor3 = Colors.TextDim
				end
			else
				row.tier.Text = ""
				row.reward.Text = ""
			end
		end
		local option = optionById(node, selectedOption)
		reasonLabel.Text = if option then CampaignUi.reason(option.legality) else "No way in yet."
		local ready = option ~= nil and option.legality.canUse and not busy
		startButton.setState(if ready then "Primary" else "Disabled")
	end

	local function render(current: Snapshot)
		local view = mapPayload()
		if not view then
			return
		end
		drawLinks(view)
		if nodeById(view, selectedNode) == nil then
			selectedNode = defaultNode(view)
		end
		for index, node in view.nodes do
			local widget = ensureWidget(node, index)
			local color = if node.state == "Cleared" then Palette.Cleared elseif node.state == "Available" then Palette.GoldDark else Palette.Locked
			widget.fill.BackgroundColor3 = color
			widget.mark.Text = if node.state == "Locked" then "?" else node.id
			widget.mark.TextColor3 = if node.state == "Locked" then Colors.TextDim else Colors.Text
			widget.outline.BackgroundColor3 = if node.id == selectedNode then Palette.Gold else Colors.Ink
			widget.label.Text = if node.state == "Cleared" then `{string.upper(node.label)} - CLEAR` else string.upper(node.label)
			widget.label.TextColor3 = if node.state == "Locked" then Colors.TextDim else Colors.Text
		end
		renderPanel(view)
		local character = current.character
		topBar.set(`ACT {view.act} - PART {view.part}`, character.level, character.yen, nil)
	end

	for i, row in optionRows do
		row.button.button.Activated:Connect(function()
			local view = mapPayload()
			local node = if view then nodeById(view, selectedNode) else nil
			local option = if node then node.playOptions[i] else nil
			if busy or not view or not option then
				return
			end
			if not option.legality.canUse then
				actions.toast(CampaignUi.reason(option.legality))
			end
			selectedOption = option.id
			renderPanel(view)
		end)
	end

	startButton.button.Activated:Connect(function()
		local view = mapPayload()
		local node = if view then nodeById(view, selectedNode) else nil
		local option = if node then optionById(node, selectedOption) else nil
		if busy or not node or not option then
			return
		end
		if not option.legality.canUse then
			actions.toast(CampaignUi.reason(option.legality))
			return
		end
		actions.submit({ kind = "StartNode", nodeId = node.id, playOptionId = option.id })
	end)

	hubButton.button.Activated:Connect(function()
		if busy then
			return
		end
		actions.submit({ kind = "Navigate", destination = "Hub" })
	end)

	function self.render(_self: Screen.Screen, current: Snapshot)
		if current.scene.kind ~= "ActMap" then
			return
		end
		snapshot = current
		render(current)
	end

	function self.setBusy(_self: Screen.Screen, value: boolean)
		busy = value
		local current = snapshot
		if current then
			render(current)
		end
	end

	function self.destroy(_self: Screen.Screen)
		frame:Destroy()
	end

	return self
end

return ActMapScreen
