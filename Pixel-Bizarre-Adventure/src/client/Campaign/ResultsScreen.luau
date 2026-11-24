--!strict
-- After an Act encounter: what this run earned (from ActResults.result) and the
-- new totals (from CampaignSnapshot.character). If a companion offer is open,
-- a recruit card shows here too. MAP and HUB leave the results.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HubTypes = require(ReplicatedStorage.Shared.Contracts.HubTypes)
local PixelUi = require(script.Parent.Parent.Battle.PixelUi)
local FighterSprite = require(script.Parent.Parent.Battle.FighterSprite)
local CampaignUi = require(script.Parent.CampaignUi)
local Screen = require(script.Parent.Screen)

type Snapshot = HubTypes.CampaignSnapshot

local Colors = PixelUi.Colors
local Palette = CampaignUi.Colors

local ITEM_TILES = 4

local ResultsScreen = {}

function ResultsScreen.new(root: Frame, actions: Screen.Actions): Screen.Screen
	local frame = PixelUi.frame(root, "Results", 0, 0, 320, 180, Palette.Backdrop)
	local topBar = CampaignUi.topBar(frame)

	local bannerOutline, banner = PixelUi.box(frame, "Banner", 20, 20, 280, 26, Palette.PurpleDark)
	local title = PixelUi.label(banner, "Title", 0, 2, 278, 12, "", Palette.Gold, Enum.TextXAlignment.Center)
	local subtitle = PixelUi.label(banner, "Sub", 0, 14, 278, 9, "", Colors.TextDim, Enum.TextXAlignment.Center)

	-- Rewards (left half when a recruit card shows, centred otherwise).
	local rewards = PixelUi.frame(frame, "Rewards", 20, 52, 140, 96)
	PixelUi.label(rewards, "Title", 0, 0, 140, 9, "REWARDS", Palette.Gold)
	local yenLine = PixelUi.label(rewards, "Yen", 0, 12, 140, 9, "", Palette.Yen)
	local levelLine = PixelUi.label(rewards, "Levels", 0, 22, 140, 9, "", Colors.Active)
	local itemsTitle = PixelUi.label(rewards, "ItemsTitle", 0, 34, 140, 9, "ITEMS", Colors.TextDim)
	local itemTiles: { CampaignUi.Tile } = {}
	for i = 1, ITEM_TILES do
		itemTiles[i] = CampaignUi.tile(rewards, `Item{i}`, (i - 1) * 34, 44, 32, "")
	end
	local totals = PixelUi.label(rewards, "Totals", 0, 82, 140, 9, "", Colors.Text)

	-- Recruit card.
	local recruitOutline, recruit = PixelUi.box(frame, "Recruit", 166, 52, 134, 96, Palette.PurpleDark)
	local spriteHolder = PixelUi.frame(recruit, "Sprite", -22, -6, 96, 96)
	local recruitTitle = PixelUi.label(recruit, "Title", 50, 3, 82, 9, "NEW ALLY!", Palette.Gold)
	local recruitName = PixelUi.label(recruit, "Name", 50, 13, 82, 9, "", Colors.Text)
	local recruitText = PixelUi.label(recruit, "Text", 50, 24, 82, 44, "", Colors.TextDim)
	recruitText.TextWrapped = true
	recruitText.TextYAlignment = Enum.TextYAlignment.Top
	local recruitButton = CampaignUi.button(recruit, "RecruitButton", 50, 74, 80, 16, "RECRUIT")

	local mapButton = CampaignUi.button(frame, "MapButton", 92, 156, 64, 18, "MAP")
	local hubButton = CampaignUi.button(frame, "HubButton", 164, 156, 64, 18, "HUB")

	local snapshot: Snapshot? = nil
	local busy = false
	local spriteKey: string? = nil

	local function render(current: Snapshot)
		local scene = current.scene
		if scene.kind ~= "ActResults" then
			return
		end
		local result = scene.result
		local character = current.character
		topBar.set("RESULTS", character.level, character.yen, nil)

		if result.outcome == "Clear" then
			title.Text = `{result.nodeId} CLEARED!`
			title.TextColor3 = Palette.Gold
			bannerOutline.BackgroundColor3 = Palette.Gold
		elseif result.outcome == "Defeat" then
			title.Text = "DEFEATED"
			title.TextColor3 = Colors.Defeat
			bannerOutline.BackgroundColor3 = Colors.Defeat
		else
			title.Text = "RETREATED"
			title.TextColor3 = Colors.TextDim
			bannerOutline.BackgroundColor3 = Colors.Ink
		end
		subtitle.Text = if result.mode == "Replay" then `{result.nodeId} REPLAY` else `{result.nodeId} FIRST CLEAR RUN`

		yenLine.Text = `+{result.rewards.yen} YEN`
		if result.rewards.levels > 0 then
			levelLine.Text = `+{result.rewards.levels} LV`
			levelLine.TextColor3 = Colors.Active
		else
			levelLine.Text = if result.mode == "Replay" then "NO LEVELS ON REPLAY" else "NO LEVELS"
			levelLine.TextColor3 = Colors.TextDim
		end
		local items = result.rewards.items
		itemsTitle.Text = if #items > 0 then "ITEMS" else "ITEMS: NONE"
		for i, tile in itemTiles do
			local reward = items[i]
			tile.outline.Visible = reward ~= nil
			if reward then
				tile.set(reward.item.iconKey, reward.item.label, `x{reward.quantity}`)
			end
		end
		totals.Text = `NOW LV {character.level}  -  {character.yen} YEN`

		local companion = current.companion
		local offered = companion.state == "Offered"
		recruitOutline.Visible = companion.state ~= "Locked"
		rewards.Position = UDim2.fromOffset(if recruitOutline.Visible then 20 else 90, 52)
		local key: string? = nil
		if companion.state ~= "Locked" then
			key = companion.spriteKey or "CompanionIdle"
			recruitName.Text = string.upper(companion.label)
			recruitText.Text = companion.description
			recruitTitle.Text = if offered then "NEW ALLY!" else "IN YOUR PARTY"
			recruitTitle.TextColor3 = if offered then Palette.Gold else Colors.Active
			recruitButton.outline.Visible = offered
			if companion.state == "Offered" then
				recruitButton.setState(if companion.legality.canUse and not busy then "Primary" else "Disabled")
			end
		end
		if key ~= spriteKey then
			spriteKey = key
			spriteHolder:ClearAllChildren()
			if key then
				FighterSprite.create(spriteHolder, key :: any, false)
			end
		end
		mapButton.setState(if busy then "Disabled" else "Normal")
		hubButton.setState(if busy then "Disabled" else "Normal")
	end

	recruitButton.button.Activated:Connect(function()
		local current = snapshot
		if busy or not current or current.companion.state ~= "Offered" then
			return
		end
		local companion = current.companion
		if not companion.legality.canUse then
			actions.toast(CampaignUi.reason(companion.legality))
			return
		end
		actions.submit({ kind = "RecruitCompanion", offerId = companion.offerId })
	end)
	mapButton.button.Activated:Connect(function()
		if not busy then
			actions.submit({ kind = "Navigate", destination = "ActMap" })
		end
	end)
	hubButton.button.Activated:Connect(function()
		if not busy then
			actions.submit({ kind = "Navigate", destination = "Hub" })
		end
	end)

	local self = {} :: Screen.Screen

	function self.render(_self: Screen.Screen, current: Snapshot)
		if current.scene.kind ~= "ActResults" then
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

return ResultsScreen
