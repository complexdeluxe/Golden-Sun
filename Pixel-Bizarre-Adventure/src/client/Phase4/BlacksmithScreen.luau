--!strict
-- The Phase 4 Blacksmith, opened from the Hub. Draws over the whole Hub.
--
-- Shows each gear copy by UUID with its base and effective (tempered) stats,
-- rolled affixes, temper level and pity, and runs the four smith services:
-- reroll offers (Accept/Keep), tempering to +10, Holy Water purification and
-- dismantling. Every price, chance and legality is the server's; a disabled
-- button explains why when pressed.
--
-- Layout (native px):
--   top bar   0..14     title, shards / materials / Holy Water, Yen
--   list      2..100    gear rows, paging, BACK TO HUB
--   detail    104..316  the selected item and its actions

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Contract = require(ReplicatedStorage.Shared.Contracts.Phase4EconomyTypes)
local CombatTypes = require(ReplicatedStorage.Shared.Contracts.CombatTypes)
local PixelUi = require(script.Parent.Parent.Battle.PixelUi)
local CampaignUi = require(script.Parent.Parent.Campaign.CampaignUi)
local Phase4Client = require(script.Parent.Phase4Client)
local Format = require(script.Parent.BlacksmithFormat)

type Snapshot = Contract.Snapshot
type ItemView = Contract.SmithItemView
type Legality = CombatTypes.ActionLegality

local Colors = PixelUi.Colors
local Palette = CampaignUi.Colors

local LIST_ROWS = 9
local ROW_HEIGHT = 12
local AFFIX_ROWS = 3
local PERK_ROWS = 6
local DETAIL_X = 104
local DETAIL_W = 212
local SLOT_ORDER: { [string]: number } = { Weapon = 1, Head = 2, Body = 3, Accessory = 4 }

export type Deps = {
	client: Phase4Client.Client,
	toast: (message: string) -> (),
	-- True when the Campaign loadout has this entry equipped.
	isEquipped: (uuid: string) -> boolean,
	-- Called once when the player leaves. The Hub refreshes Campaign there.
	onClose: () -> (),
}

export type Blacksmith = {
	destroy: (self: Blacksmith) -> (),
}

type Status = { text: string, color: Color3 }

local BlacksmithScreen = {}

function BlacksmithScreen.open(parent: Instance, deps: Deps): Blacksmith
	local client = deps.client
	local frame = PixelUi.frame(parent, "Blacksmith", 0, 0, 320, 180, Palette.Backdrop)
	frame.Active = true
	frame.ZIndex = 5

	-- Top bar.
	local bar = PixelUi.frame(frame, "TopBar", 0, 0, 320, 14, Palette.PurpleDark)
	PixelUi.frame(bar, "Edge", 0, 13, 320, 1, Palette.Purple)
	PixelUi.label(bar, "Title", 4, 2, 70, 10, "BLACKSMITH", Palette.Gold)
	local balanceLabel = PixelUi.label(bar, "Balances", 76, 2, 184, 10, "", Colors.TextDim, Enum.TextXAlignment.Right)
	local yenLabel = PixelUi.label(bar, "Yen", 262, 2, 54, 10, "", Palette.Yen, Enum.TextXAlignment.Right)

	-- Gear list.
	PixelUi.label(frame, "ListTitle", 2, 16, 60, 9, "GEAR", Palette.Gold)
	local pageLabel = PixelUi.label(frame, "Page", 52, 16, 30, 9, "", Colors.TextDim, Enum.TextXAlignment.Center)
	local prevPage = CampaignUi.button(frame, "PrevPage", 40, 16, 12, 9, "<")
	local nextPage = CampaignUi.button(frame, "NextPage", 84, 16, 12, 9, ">")
	type Row = { outline: Frame, fill: Frame, name: TextLabel, badge: TextLabel, press: TextButton }
	local rows: { Row } = {}
	for i = 1, LIST_ROWS do
		local outline, fill = PixelUi.box(frame, `Gear{i}`, 2, 27 + (i - 1) * ROW_HEIGHT, 98, ROW_HEIGHT - 1, Palette.Tile)
		rows[i] = {
			outline = outline,
			fill = fill,
			name = PixelUi.label(fill, "Name", 2, 0, 70, ROW_HEIGHT - 3, "", Colors.Text),
			badge = PixelUi.label(fill, "Badge", 72, 0, 22, ROW_HEIGHT - 3, "", Palette.Gold, Enum.TextXAlignment.Right),
			press = PixelUi.button(fill, "Press", 0, 0, 96, ROW_HEIGHT - 3, ""),
		}
	end
	local listHint = PixelUi.label(frame, "ListHint", 2, 136, 98, 20, "", Colors.TextDim)
	listHint.TextWrapped = true
	listHint.TextYAlignment = Enum.TextYAlignment.Top
	local back = CampaignUi.button(frame, "Back", 4, 159, 94, 18, "< BACK TO HUB")

	-- Detail panel.
	local detail = PixelUi.frame(frame, "Detail", DETAIL_X, 16, DETAIL_W, 162)
	local function line(name: string, y: number, color: Color3?, x: number?, w: number?): TextLabel
		return PixelUi.label(detail, name, x or 0, y, w or DETAIL_W, 9, "", color or Colors.Text)
	end
	local title = PixelUi.label(detail, "Name", 0, 0, DETAIL_W, 10, "", Palette.Gold)
	local tierLine = line("Tier", 10, Colors.TextDim, 0, 120)
	local perkLine = line("Perk", 10, Colors.Active, 120, 92)
	perkLine.TextXAlignment = Enum.TextXAlignment.Right
	line("BaseTitle", 21, Colors.TextDim, 0, 30).Text = "BASE"
	local baseLine = line("Base", 21, Colors.Text, 30, DETAIL_W - 30)
	line("NowTitle", 30, Colors.TextDim, 0, 30).Text = "NOW"
	local effectiveLine = line("Effective", 30, Colors.Active, 30, DETAIL_W - 30)
	local affixTitle = line("AffixTitle", 41, Palette.Gold, 0, 104)
	local offerTitle = line("OfferTitle", 41, Palette.Gold, 108, 104)
	local affixLines: { TextLabel } = {}
	local offerLines: { TextLabel } = {}
	for i = 1, AFFIX_ROWS do
		affixLines[i] = line(`Affix{i}`, 41 + i * 9, Colors.Text, 0, DETAIL_W)
		offerLines[i] = line(`Offer{i}`, 41 + i * 9, Colors.Active, 108, 104)
	end
	local temperLine = line("TemperLine", 79, Colors.Text)
	local nextLine = line("NextTemper", 88, Colors.TextDim)
	local priceLine = line("Prices", 97, Colors.TextDim)
	local statusLine = line("Status", 108, Colors.TextDim)

	local rerollButton = CampaignUi.button(detail, "Reroll", 0, 119, 52, 14, "REROLL")
	local temperButton = CampaignUi.button(detail, "Temper", 53, 119, 52, 14, "TEMPER")
	local purifyButton = CampaignUi.button(detail, "Purify", 106, 119, 52, 14, "PURIFY")
	local dismantleButton = CampaignUi.button(detail, "Dismantle", 159, 119, 53, 14, "SALVAGE")
	local leftChoice = CampaignUi.button(detail, "Accept", 0, 135, 105, 14, "ACCEPT NEW")
	local rightChoice = CampaignUi.button(detail, "Keep", 107, 135, 105, 14, "KEEP OLD")
	local choiceHint = line("ChoiceHint", 151, Colors.TextDim)

	-- Purification perk picker, drawn over the affix and temper lines.
	local perkPanel = PixelUi.frame(detail, "PerkPanel", 0, 41, DETAIL_W, 76, Palette.Backdrop)
	perkPanel.ZIndex = 2
	local perkTitle = PixelUi.label(perkPanel, "Title", 0, 0, DETAIL_W, 9, "", Palette.Gold)
	type PerkRow = { label: TextLabel, reason: TextLabel, choose: CampaignUi.Button }
	local perkRows: { PerkRow } = {}
	for i = 1, PERK_ROWS do
		local y = 10 + (i - 1) * 11
		perkRows[i] = {
			label = PixelUi.label(perkPanel, `Perk{i}`, 0, y, 76, 10, "", Colors.Text),
			reason = PixelUi.label(perkPanel, `Reason{i}`, 76, y, 90, 10, "", Colors.Hp),
			choose = CampaignUi.button(perkPanel, `Choose{i}`, 168, y, 44, 10, "CHOOSE"),
		}
	end

	-- Loading, empty and error messages.
	local notice = PixelUi.label(detail, "Notice", 0, 50, DETAIL_W, 10, "", Colors.TextDim, Enum.TextXAlignment.Center)
	local noticeLine = PixelUi.label(detail, "Notice2", 0, 61, DETAIL_W, 10, "", Colors.TextDim, Enum.TextXAlignment.Center)
	local retry = CampaignUi.button(detail, "Retry", 76, 76, 60, 14, "RETRY")

	local self = {} :: Blacksmith
	local alive = true
	local busy = false
	local loaded = false
	local loadError: string? = nil
	local selected: string? = nil
	local page = 1
	local purifying = false
	local confirmDismantle: string? = nil
	local status: Status? = nil
	local render: () -> ()

	local function setStatus(text: string, color: Color3)
		status = { text = text, color = color }
	end

	-- Equipped first by slot, then tier, then name, so the list does not jump
	-- when an action changes one item.
	local function ordered(snapshot: Snapshot): { ItemView }
		local list: { ItemView } = table.clone(snapshot.smithItems)
		table.sort(list, function(a: ItemView, b: ItemView): boolean
			local slotA, slotB = SLOT_ORDER[a.item.slot] or 9, SLOT_ORDER[b.item.slot] or 9
			if slotA ~= slotB then
				return slotA < slotB
			end
			if a.item.tier ~= b.item.tier then
				return a.item.tier > b.item.tier
			end
			if a.display.label ~= b.display.label then
				return a.display.label < b.display.label
			end
			return a.item.uuid < b.item.uuid
		end)
		return list
	end

	local function find(snapshot: Snapshot, uuid: string?): ItemView?
		if not uuid then
			return nil
		end
		for _, view in snapshot.smithItems do
			if view.item.uuid == uuid then
				return view
			end
		end
		return nil
	end

	local function current(): (Snapshot?, ItemView?)
		local snapshot = client:snapshot()
		if not snapshot then
			return nil, nil
		end
		return snapshot, find(snapshot, selected)
	end

	-- Keep the selection on its UUID. A resumed offer is shown first.
	local function settleSelection(snapshot: Snapshot)
		if find(snapshot, selected) then
			return
		end
		selected = nil
		local list = ordered(snapshot)
		for _, view in list do
			if view.item.pendingSmithOffer then
				selected = view.item.uuid
				break
			end
		end
		if not selected and list[1] then
			selected = list[1].item.uuid
		end
		purifying = false
		confirmDismantle = nil
	end

	local function legalButton(button: CampaignUi.Button, legality: Legality, primary: boolean?)
		if busy or not legality.canUse then
			button.setState("Disabled")
		else
			button.setState(if primary then "Primary" else "Normal")
		end
	end

	-- Runs one action and shows the committed receipt or the server's reason.
	local function run(action: Contract.Action, label: string?)
		if busy then
			return
		end
		busy = true
		setStatus("WORKING...", Colors.TextDim)
		render()
		local result = client:perform(action)
		if not alive then
			return
		end
		busy = false
		local receipt = result.receipt
		if result.ok and receipt then
			-- A reply that settled an earlier unconfirmed action describes that one.
			local text = Format.receipt(receipt, if result.resolvedPending then nil else label)
			if result.resolvedPending then
				text = "EARLIER: " .. text
			end
			local failed = receipt.kind == "Tempered" and not receipt.succeeded
			setStatus(text, if failed then Colors.Hp else Colors.Active)
			deps.toast(text)
			if receipt.kind == "Dismantled" or receipt.kind == "Purified" then
				purifying = false
			end
			confirmDismantle = nil
		else
			local message = result.message or "The Blacksmith couldn't do that."
			if result.resolvedPending then
				message = "Last action not applied: " .. message
			end
			if result.code == "StaleRevision" then
				message = "Balances changed. Press again to retry."
			end
			setStatus(string.upper(message), Colors.Hp)
			deps.toast(message)
		end
		local snapshot = client:snapshot()
		if snapshot then
			settleSelection(snapshot)
		end
		render()
	end

	local function load()
		busy = true
		loadError = nil
		render()
		local result = client:refresh()
		if not alive then
			return
		end
		busy = false
		loaded = result.ok
		if not result.ok then
			loadError = result.message or "The Blacksmith is closed."
		end
		local snapshot = client:snapshot()
		if snapshot and result.ok then
			settleSelection(snapshot)
		end
		render()
	end

	local function renderList(snapshot: Snapshot)
		local list = ordered(snapshot)
		local pages = math.max(1, math.ceil(#list / LIST_ROWS))
		page = math.clamp(page, 1, pages)
		pageLabel.Text = if pages > 1 then `{page}/{pages}` else ""
		prevPage.outline.Visible = pages > 1
		nextPage.outline.Visible = pages > 1
		prevPage.setState(if page > 1 then "Normal" else "Disabled")
		nextPage.setState(if page < pages then "Normal" else "Disabled")
		local first = (page - 1) * LIST_ROWS
		for i, row in rows do
			local view = list[first + i]
			row.outline.Visible = view ~= nil
			if view then
				local item = view.item
				-- The slot is in the detail panel. The row keeps the name, a flag and the temper level.
				row.name.Text = string.upper(view.display.label)
				local flag = if item.pendingSmithOffer then "!"
					elseif item.cursed then "C"
					elseif deps.isEquipped(item.uuid) then "E"
					else ""
				row.badge.Text = if item.temperLevel > 0 then `{flag}+{item.temperLevel}` else flag
				row.badge.TextColor3 = if item.cursed and not item.pendingSmithOffer then Colors.Hp else Palette.Gold
				local isSelected = item.uuid == selected
				row.outline.BackgroundColor3 = if isSelected then Palette.Gold else Colors.Ink
				row.fill.BackgroundColor3 = if isSelected then Colors.ButtonHover else Palette.Tile
			end
		end
		listHint.Text = if #list == 0 then "" else "! OFFER  C CURSED  E EQUIPPED"
	end

	local function showDetail(visible: boolean)
		for _, child in detail:GetChildren() do
			if child ~= notice and child ~= noticeLine and child ~= retry.outline then
				(child :: GuiObject).Visible = visible
			end
		end
	end

	local function renderPerks(view: ItemView)
		local options = view.purification
		local priceText = if options[1] then Format.cost(options[1].cost) else ""
		perkTitle.Text = `PURIFY WITH HOLY WATER   {priceText}`
		for i, row in perkRows do
			local option = options[i]
			row.label.Visible = option ~= nil
			row.reason.Visible = option ~= nil
			row.choose.outline.Visible = option ~= nil
			if option then
				row.label.Text = string.upper(option.label)
				row.reason.Text = CampaignUi.reason(option.legality)
				legalButton(row.choose, option.legality, true)
			end
		end
	end

	local function renderDetail(view: ItemView)
		local item = view.item
		local offer = item.pendingSmithOffer
		title.Text = Format.name(view)
		tierLine.Text = Format.tierLine(item)
		perkLine.Text = if item.purifiedPerk then `PERK {string.upper((string.gsub(item.purifiedPerk, "_", " ")))}` else ""
		baseLine.Text = Format.stats(item.baseStats)
		effectiveLine.Text = Format.stats(view.effectiveBaseStats)

		-- Affixes, side by side with the persisted offer when one is waiting.
		affixTitle.Text = if offer then "CURRENT AFFIXES" else "AFFIXES"
		offerTitle.Text = if offer then "NEW ROLL" else ""
		for i = 1, AFFIX_ROWS do
			local old = item.rolledLines[i]
			affixLines[i].Size = UDim2.fromOffset(if offer then 104 else DETAIL_W, 9)
			affixLines[i].Text = if old then Format.affix(old) elseif i == 1 then "PLAIN GEAR. NO ROLLED LINES." else ""
			affixLines[i].TextColor3 = if old then Colors.Text else Colors.TextDim
			local new = if offer then offer.lines[i] else nil
			offerLines[i].Text = if new then Format.affix(new) else ""
		end

		temperLine.Text = Format.temperLine(item)
		nextLine.Text = Format.nextTemper(view.temper)
		priceLine.Text = `REROLL {Format.cost(view.reroll.cost)}   SALVAGE +{view.dismantleShards} SHARD`

		local shown = status
		statusLine.Text = if shown then shown.text else ""
		statusLine.TextColor3 = if shown then shown.color else Colors.TextDim

		legalButton(rerollButton, view.reroll.legality)
		legalButton(temperButton, view.temper.legality)
		local canPurify = item.cursed and #view.purification > 0
		purifyButton.setText(if purifying then "CLOSE" else "PURIFY")
		purifyButton.setState(if busy or not canPurify then "Disabled" elseif purifying then "Selected" else "Normal")
		legalButton(dismantleButton, view.dismantleLegality)

		perkPanel.Visible = purifying and canPurify
		if perkPanel.Visible then
			renderPerks(view)
		end

		-- Second row: the offer choice, or the salvage confirmation.
		if offer then
			leftChoice.outline.Visible = true
			rightChoice.outline.Visible = true
			leftChoice.setText("ACCEPT NEW")
			rightChoice.setText("KEEP OLD")
			leftChoice.setState(if busy then "Disabled" else "Primary")
			rightChoice.setState(if busy then "Disabled" else "Normal")
			choiceHint.Text = "THE ROLL IS PAID FOR AND SAVED. PICK ONE."
		elseif confirmDismantle == item.uuid then
			leftChoice.outline.Visible = true
			rightChoice.outline.Visible = true
			leftChoice.setText(`SALVAGE +{view.dismantleShards}`)
			rightChoice.setText("CANCEL")
			leftChoice.setState(if busy then "Disabled" else "Primary")
			rightChoice.setState(if busy then "Disabled" else "Normal")
			choiceHint.Text = "THIS DESTROYS THE ITEM."
		else
			leftChoice.outline.Visible = false
			rightChoice.outline.Visible = false
			choiceHint.Text = ""
		end
		choiceHint.TextColor3 = if confirmDismantle == item.uuid and not offer then Colors.Hp else Colors.TextDim
	end

	function render()
		if not alive then
			return
		end
		back.setState(if busy then "Disabled" else "Normal")
		local snapshot = client:snapshot()
		if snapshot then
			yenLabel.Text = `{snapshot.balances.yen} YEN`
			balanceLabel.Text = Format.balances(snapshot.balances)
		else
			yenLabel.Text = ""
			balanceLabel.Text = ""
		end
		retry.outline.Visible = false
		noticeLine.Text = ""
		if not loaded or not snapshot then
			showDetail(false)
			for _, row in rows do
				row.outline.Visible = false
			end
			prevPage.outline.Visible = false
			nextPage.outline.Visible = false
			pageLabel.Text = ""
			listHint.Text = ""
			local failed = loadError
			notice.Text = if failed then string.upper(failed) else "VISITING THE BLACKSMITH..."
			notice.TextColor3 = if failed then Colors.Hp else Colors.TextDim
			retry.outline.Visible = failed ~= nil
			retry.setState(if busy then "Disabled" else "Primary")
			return
		end
		renderList(snapshot)
		local view = find(snapshot, selected)
		if not view then
			showDetail(false)
			notice.Text = "NO GEAR FOR THE SMITH YET."
			notice.TextColor3 = Colors.TextDim
			noticeLine.Text = "GEAR YOU WIN OR FIND SHOWS UP HERE."
			return
		end
		notice.Text = ""
		showDetail(true)
		renderDetail(view)
	end

	-- Input ------------------------------------------------------------------

	local function explain(legality: Legality): boolean
		if legality.canUse then
			return false
		end
		deps.toast(CampaignUi.reason(legality))
		return true
	end

	for i, row in rows do
		row.press.Activated:Connect(function()
			local snapshot = client:snapshot()
			if busy or not snapshot then
				return
			end
			local view = ordered(snapshot)[(page - 1) * LIST_ROWS + i]
			if not view or view.item.uuid == selected then
				return
			end
			selected = view.item.uuid
			purifying = false
			confirmDismantle = nil
			status = nil
			render()
		end)
	end
	prevPage.button.Activated:Connect(function()
		page -= 1
		render()
	end)
	nextPage.button.Activated:Connect(function()
		page += 1
		render()
	end)

	rerollButton.button.Activated:Connect(function()
		local _, view = current()
		if busy or not view or explain(view.reroll.legality) then
			return
		end
		run({ kind = "CreateOffer", itemUuid = view.item.uuid })
	end)
	temperButton.button.Activated:Connect(function()
		local _, view = current()
		if busy or not view or explain(view.temper.legality) then
			return
		end
		run({ kind = "Temper", itemUuid = view.item.uuid }, string.upper(view.display.label))
	end)
	purifyButton.button.Activated:Connect(function()
		local _, view = current()
		if busy or not view then
			return
		end
		if not view.item.cursed or #view.purification == 0 then
			deps.toast("Only cursed gear can be purified.")
			return
		end
		purifying = not purifying
		confirmDismantle = nil
		render()
	end)
	for i, row in perkRows do
		row.choose.button.Activated:Connect(function()
			local _, view = current()
			if busy or not view then
				return
			end
			local option = view.purification[i]
			if not option or explain(option.legality) then
				return
			end
			run({ kind = "Purify", itemUuid = view.item.uuid, perkId = option.perkId })
		end)
	end
	dismantleButton.button.Activated:Connect(function()
		local _, view = current()
		if busy or not view or explain(view.dismantleLegality) then
			return
		end
		confirmDismantle = if confirmDismantle == view.item.uuid then nil else view.item.uuid
		purifying = false
		render()
	end)
	leftChoice.button.Activated:Connect(function()
		local _, view = current()
		if busy or not view then
			return
		end
		local offer = view.item.pendingSmithOffer
		if offer then
			run({ kind = "ResolveOffer", itemUuid = view.item.uuid, offerId = offer.offerId, decision = "AcceptNew" })
		elseif confirmDismantle == view.item.uuid then
			if explain(view.dismantleLegality) then
				return
			end
			run({ kind = "Dismantle", itemUuid = view.item.uuid })
		end
	end)
	rightChoice.button.Activated:Connect(function()
		local _, view = current()
		if busy or not view then
			return
		end
		local offer = view.item.pendingSmithOffer
		if offer then
			run({ kind = "ResolveOffer", itemUuid = view.item.uuid, offerId = offer.offerId, decision = "KeepOld" })
		else
			confirmDismantle = nil
			render()
		end
	end)
	retry.button.Activated:Connect(function()
		if not busy then
			load()
		end
	end)
	back.button.Activated:Connect(function()
		if busy or not alive then
			return
		end
		self:destroy()
		deps.onClose()
	end)

	function self.destroy(_self: Blacksmith)
		if not alive then
			return
		end
		alive = false
		frame:Destroy()
	end

	render()
	task.spawn(load)
	return self
end

return BlacksmithScreen
