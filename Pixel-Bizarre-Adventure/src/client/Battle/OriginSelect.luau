--!strict
-- Act 1 Origin Select: pick Part 1 Hamon or Part 3 Stand after winning the
-- tutorial. The choice is sent to the server, which saves it. This screen only
-- shows the two options and a confirm button.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SaveTypes = require(ReplicatedStorage.Shared.Contracts.SaveTypes)
local PixelUi = require(script.Parent.PixelUi)

type Origin = SaveTypes.Origin

local Colors = PixelUi.Colors

type OriginInfo = { origin: Origin, title: string, part: string, blurb: { string } }

local ORIGINS: { OriginInfo } = {
	{
		origin = "Part1_Hamon",
		title = "HAMON",
		part = "PART 1",
		blurb = { "Breathing technique.", "Sunlight energy", "through your fists." },
	},
	{
		origin = "Part3_Stand",
		title = "STAND",
		part = "PART 3",
		blurb = { "A fighting spirit", "that battles", "at your side." },
	},
}

export type OriginSelect = {
	show: (self: OriginSelect) -> (),
	hide: (self: OriginSelect) -> (),
	setBusy: (self: OriginSelect, busy: boolean) -> (),
}

local OriginSelect = {}

function OriginSelect.displayName(origin: Origin): string
	for _, info in ORIGINS do
		if info.origin == origin then
			return `{info.title} ({info.part})`
		end
	end
	return origin
end

function OriginSelect.new(parent: Instance, onChoose: (Origin) -> ()): OriginSelect
	local modal = PixelUi.box(parent, "OriginSelect", 40, 22, 240, 128, Colors.Panel)
	modal.ZIndex = 6
	modal.Visible = false

	PixelUi.label(modal, "Title", 0, 4, 240, 10, "CHOOSE YOUR ORIGIN", Colors.Victory, Enum.TextXAlignment.Center)
	PixelUi.label(modal, "Subtitle", 0, 15, 240, 9, "Your pick becomes Act 1.", Colors.TextDim, Enum.TextXAlignment.Center)

	local selected: Origin? = nil
	local busy = false
	local cards: { [Origin]: Frame } = {}

	local confirmBox, confirmFill = PixelUi.box(modal, "ConfirmBox", 70, 106, 100, 16, Colors.Disabled)
	local confirm = PixelUi.button(confirmBox, "Confirm", 0, 0, 100, 16, "PICK ONE")

	local function refresh()
		for origin, cardFill in cards do
			cardFill.BackgroundColor3 = if origin == selected then Colors.PanelLight else Colors.Panel
		end
		local ready = selected ~= nil and not busy
		confirmFill.BackgroundColor3 = if ready then Colors.Button else Colors.Disabled
		confirm.Text = if busy then "SAVING..." elseif selected then "CONFIRM" else "PICK ONE"
		confirm.TextColor3 = if ready then Colors.Text else Colors.TextDim
	end

	for index, info in ORIGINS do
		local x = 10 + (index - 1) * 114
		local card, cardFill = PixelUi.box(modal, info.origin, x, 28, 106, 72, Colors.Panel)
		cards[info.origin] = cardFill
		PixelUi.label(card, "Part", 0, 4, 106, 9, info.part, Colors.TextDim, Enum.TextXAlignment.Center)
		PixelUi.label(card, "Title", 0, 14, 106, 12, info.title, Colors.Text, Enum.TextXAlignment.Center)
		for line, text in info.blurb do
			PixelUi.label(card, `Blurb{line}`, 4, 30 + (line - 1) * 10, 98, 9, text, Colors.TextDim, Enum.TextXAlignment.Center)
		end
		local pick = PixelUi.button(card, "Pick", 0, 0, 106, 72, "")
		pick.Activated:Connect(function()
			if busy then
				return
			end
			selected = info.origin
			refresh()
		end)
	end

	confirm.Activated:Connect(function()
		local origin = selected
		if busy or origin == nil then
			return
		end
		onChoose(origin)
	end)

	local self = {} :: OriginSelect

	function self.show(_self: OriginSelect)
		modal.Visible = true
		refresh()
	end

	function self.hide(_self: OriginSelect)
		modal.Visible = false
	end

	function self.setBusy(_self: OriginSelect, value: boolean)
		busy = value
		refresh()
	end

	refresh()
	return self
end

return OriginSelect
