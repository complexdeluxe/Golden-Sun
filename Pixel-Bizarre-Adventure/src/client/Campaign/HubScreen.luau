--!strict
-- The single Public Hub. Shop (restock and gear), Bag (inventory, gear and
-- belt loadout), Party (recruit when offered), the three Phase 4 stations
-- (Blacksmith, Cyberware Clinic and D'Arby's Parlor, each drawn over the Hub,
-- see Phase4/), and Set Out to the Act Map. Later stations stay hidden until
-- their phase.
--
-- Layout (native px):
--   top bar       0..14    title, level, Yen
--   left column   0..100   player preview, origin, station buttons, Set Out
--   content       104..316 the open station

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatTypes = require(ReplicatedStorage.Shared.Contracts.CombatTypes)
local HubTypes = require(ReplicatedStorage.Shared.Contracts.HubTypes)
local InventoryTypes = require(ReplicatedStorage.Shared.Contracts.InventoryTypes)
local PixelUi = require(script.Parent.Parent.Battle.PixelUi)
local FighterSprite = require(script.Parent.Parent.Battle.FighterSprite)
local OriginSelect = require(script.Parent.Parent.Battle.OriginSelect)
local CampaignUi = require(script.Parent.CampaignUi)
local Screen = require(script.Parent.Screen)
local BlacksmithScreen = require(script.Parent.Parent.Phase4.BlacksmithScreen)
local ClinicScreen = require(script.Parent.Parent.Phase4.ClinicScreen)
local ParlorScreen = require(script.Parent.Parent.Phase4.ParlorScreen)

type Snapshot = HubTypes.CampaignSnapshot
type ShopOffer = HubTypes.ShopOffer
type Inventory = InventoryTypes.InventoryView
type Entry = InventoryTypes.InventoryEntry

local Colors = PixelUi.Colors
local Palette = CampaignUi.Colors
local Limits = CombatTypes.Phase2Limits

local CONTENT_X = 104
local SHOP_ROWS = 6
local BAG_COLUMNS = 3
local BAG_ROWS = 3
local BAG_PAGE = BAG_COLUMNS * BAG_ROWS
local BELT_TILES = 3
local SLOT_SHORT: { [string]: string } = { Weapon = "WPN", Head = "HEAD", Body = "BODY", Accessory = "ACC" }

type Station = "Shop" | "Bag" | "Party"
type Phase4Station = "Smith" | "Clinic" | "Parlor"
-- An open Phase 4 station overlay.
type Overlay = { destroy: (self: any) -> () }
type Selection = { kind: "Entry", entryId: string } | { kind: "Gear", slot: InventoryTypes.GearSlot } | { kind: "Belt", index: number }

local HubScreen = {}

function HubScreen.new(root: Frame, actions: Screen.Actions): Screen.Screen
	local frame = PixelUi.frame(root, "Hub", 0, 0, 320, 180, Palette.Backdrop)
	local topBar = CampaignUi.topBar(frame)

	-- Left column.
	local stage = PixelUi.box(frame, "Stage", 2, 16, 98, 90, Palette.PurpleDark)
	PixelUi.frame(stage, "Floor", 1, 76, 96, 13, Colors.Floor)
	local preview = CampaignUi.preview(stage, "Preview", 0, -12)
	local originLabel = PixelUi.label(frame, "Origin", 2, 107, 98, 9, "", Colors.TextDim, Enum.TextXAlignment.Center)
	local stationButtons: { [Station]: CampaignUi.Button } = {
		Shop = CampaignUi.button(frame, "ShopTab", 4, 117, 46, 11, "SHOP"),
		Bag = CampaignUi.button(frame, "BagTab", 52, 117, 46, 11, "BAG"),
		Party = CampaignUi.button(frame, "PartyTab", 4, 129, 94, 11, "PARTY"),
	}
	-- Phase 4 stations open over the Hub.
	local phase4Buttons: { [Phase4Station]: CampaignUi.Button } = {
		Smith = CampaignUi.button(frame, "SmithTab", 4, 141, 46, 11, "SMITH"),
		Clinic = CampaignUi.button(frame, "ClinicTab", 52, 141, 46, 11, "CLINIC"),
		Parlor = CampaignUi.button(frame, "ParlorTab", 4, 153, 94, 11, "D'ARBY'S PARLOR"),
	}
	local PHASE4_NAME: { [Phase4Station]: string } = {
		Smith = "The Blacksmith",
		Clinic = "The Clinic",
		Parlor = "D'Arby's Parlor",
	}
	local setOut = CampaignUi.button(frame, "SetOut", 4, 165, 94, 13, "SET OUT >")

	local content = PixelUi.frame(frame, "Content", CONTENT_X, 16, 214, 162)

	-- Shop -------------------------------------------------------------------
	local shop = PixelUi.frame(content, "Shop", 0, 0, 214, 162)
	PixelUi.label(shop, "Title", 2, 0, 120, 9, "SHOP", Palette.Gold)
	PixelUi.label(shop, "Note", 90, 0, 122, 9, "RESTOCK THE PARTY BELT", Colors.TextDim, Enum.TextXAlignment.Right)
	type ShopRow = {
		root: Frame,
		tile: CampaignUi.Tile,
		name: TextLabel,
		price: TextLabel,
		minus: CampaignUi.Button,
		qty: TextLabel,
		plus: CampaignUi.Button,
		buy: CampaignUi.Button,
	}
	local shopRows: { ShopRow } = {}
	for i = 1, SHOP_ROWS do
		local row = PixelUi.frame(shop, `Offer{i}`, 0, 10 + (i - 1) * 20, 214, 19)
		local tile = CampaignUi.tile(row, "Icon", 2, 0, 16, "")
		shopRows[i] = {
			root = row,
			tile = tile,
			name = PixelUi.label(row, "Name", 22, 0, 98, 9, "", Colors.Text),
			price = PixelUi.label(row, "Price", 22, 9, 98, 9, "", Palette.Yen),
			minus = CampaignUi.button(row, "Minus", 122, 3, 12, 12, "-"),
			qty = PixelUi.label(row, "Qty", 134, 3, 16, 12, "1", Colors.Text, Enum.TextXAlignment.Center),
			plus = CampaignUi.button(row, "Plus", 150, 3, 12, 12, "+"),
			buy = CampaignUi.button(row, "Buy", 166, 2, 46, 14, "BUY"),
		}
	end
	local shopHint = PixelUi.label(shop, "Hint", 2, 134, 210, 9, "", Colors.TextDim)
	local shopHint2 = PixelUi.label(shop, "Hint2", 2, 144, 210, 9, "", Colors.TextDim)

	-- Bag --------------------------------------------------------------------
	local bag = PixelUi.frame(content, "Bag", 0, 0, 214, 162)
	PixelUi.label(bag, "GearTitle", 2, 0, 100, 9, "GEAR", Palette.Gold)
	local gearTiles: { [string]: CampaignUi.Tile } = {}
	for i, slot in InventoryTypes.GearSlots do
		local column = (i - 1) % 2
		local row = (i - 1) // 2
		gearTiles[slot] = CampaignUi.tile(bag, `Gear{slot}`, 2 + column * 36, 10 + row * 36, 32, SLOT_SHORT[slot])
	end
	PixelUi.label(bag, "BeltTitle", 2, 82, 104, 9, "BELT", Palette.Gold)
	local beltTiles: { CampaignUi.Tile } = {}
	for i = 1, BELT_TILES do
		beltTiles[i] = CampaignUi.tile(bag, `Belt{i}`, 2 + (i - 1) * 36, 92, 32, `{i}`)
	end
	PixelUi.label(bag, "BagTitle", 112, 0, 60, 9, "ITEMS", Palette.Gold)
	local pageLabel = PixelUi.label(bag, "Page", 150, 0, 40, 9, "", Colors.TextDim, Enum.TextXAlignment.Center)
	local prevPage = CampaignUi.button(bag, "PrevPage", 140, 0, 12, 9, "<")
	local nextPage = CampaignUi.button(bag, "NextPage", 190, 0, 12, 9, ">")
	local bagTiles: { CampaignUi.Tile } = {}
	for i = 1, BAG_PAGE do
		local column = (i - 1) % BAG_COLUMNS
		local row = (i - 1) // BAG_COLUMNS
		bagTiles[i] = CampaignUi.tile(bag, `Item{i}`, 112 + column * 34, 10 + row * 34, 32, "")
	end
	local detailTitle = PixelUi.label(bag, "DetailTitle", 2, 130, 150, 9, "", Colors.Text)
	local detailLine = PixelUi.label(bag, "DetailLine", 2, 140, 150, 9, "", Colors.TextDim)
	local detailReason = PixelUi.label(bag, "DetailReason", 2, 150, 150, 9, "", Colors.TextDim)
	local actionButton = CampaignUi.button(bag, "Action", 154, 132, 58, 14, "")
	local clearButton = CampaignUi.button(bag, "Clear", 154, 147, 58, 14, "REMOVE")

	-- Party ------------------------------------------------------------------
	local party = PixelUi.frame(content, "Party", 0, 0, 214, 162)
	PixelUi.label(party, "Title", 2, 0, 120, 9, "PARTY", Palette.Gold)
	local companionStage = PixelUi.box(party, "Stage", 2, 12, 98, 98, Palette.PurpleDark)
	PixelUi.frame(companionStage, "Floor", 1, 84, 96, 13, Colors.Floor)
	local companionHolder = PixelUi.frame(companionStage, "Holder", 0, -4, 96, 96)
	local companionName = PixelUi.label(party, "Name", 106, 14, 106, 10, "", Colors.Text)
	local companionState = PixelUi.label(party, "State", 106, 25, 106, 9, "", Colors.TextDim)
	local companionText = PixelUi.label(party, "Description", 106, 38, 106, 50, "", Colors.Text)
	companionText.TextWrapped = true
	companionText.TextYAlignment = Enum.TextYAlignment.Top
	local recruitButton = CampaignUi.button(party, "Recruit", 106, 94, 106, 16, "RECRUIT")
	local partyHint = PixelUi.label(party, "Hint", 2, 116, 210, 9, "", Colors.TextDim)

	local self = {} :: Screen.Screen
	local station: Station = "Bag"
	local snapshot: Snapshot? = nil
	local busy = false
	local quantities: { [string]: number } = {}
	local selection: Selection? = nil
	local bagPage = 1
	local spriteKey: string? = nil
	local overlay: Overlay? = nil
	local openingStation = false

	local function hubPayload(): (HubTypes.HubView?, Inventory?)
		local current = snapshot
		if current and current.scene.kind == "Hub" then
			return current.scene.hub, current.scene.inventory
		end
		return nil, nil
	end

	local function findEntry(inventory: Inventory, entryId: string?): Entry?
		if entryId == nil then
			return nil
		end
		for _, entry in inventory.entries do
			if entry.entryId == entryId then
				return entry
			end
		end
		return nil
	end

	local function ownedCount(inventory: Inventory, itemId: string): number
		local count = 0
		for _, entry in inventory.entries do
			if entry.item.itemId == itemId then
				count += if entry.kind == "Stack" then entry.quantity else 1
			end
		end
		return count
	end

	local function isEquipped(inventory: Inventory, entryId: string): boolean
		for _, slot in inventory.gear do
			if slot.entryId == entryId then
				return true
			end
		end
		for _, slot in inventory.belt do
			if slot.entryId == entryId then
				return true
			end
		end
		return false
	end

	-- Shop ---------------------------------------------------------------------

	local function renderShop(hub: HubTypes.HubView, inventory: Inventory)
		local yen = if snapshot then snapshot.character.yen else 0
		for i, row in shopRows do
			local offer = hub.shopOffers[i]
			row.root.Visible = offer ~= nil
			if offer then
				local quantity = math.clamp(quantities[offer.id] or 1, 1, math.max(1, offer.maxQuantity))
				quantities[offer.id] = quantity
				row.tile.set(offer.item.iconKey, offer.item.label, nil)
				local owned = ownedCount(inventory, offer.item.itemId)
				row.name.Text = string.upper(offer.item.label)
				row.price.Text = `{offer.unitPriceYen} YEN  OWN {owned}`
				row.qty.Text = `{quantity}`
				local stepper = offer.kind == "BeltSupply" and offer.maxQuantity > 1
				row.minus.outline.Visible = stepper
				row.plus.outline.Visible = stepper
				row.qty.Visible = stepper
				row.minus.setState(if busy or quantity <= 1 then "Disabled" else "Normal")
				local affordMore = (quantity + 1) * offer.unitPriceYen <= yen
				row.plus.setState(if busy or quantity >= offer.maxQuantity or not affordMore then "Disabled" else "Normal")
				local canBuy = offer.legality.canUse and not busy and quantity * offer.unitPriceYen <= yen
				row.buy.setState(if canBuy then "Primary" else "Disabled")
				row.buy.setText(if offer.legality.canUse then `{quantity * offer.unitPriceYen} Y` else "BUY")
			end
		end
	end

	for i, row in shopRows do
		local function offer(): ShopOffer?
			local hub = hubPayload()
			return if hub then hub.shopOffers[i] else nil
		end
		local function describe()
			local current = offer()
			if current then
				shopHint.Text = current.item.description
				shopHint2.Text = CampaignUi.reason(current.legality)
			end
		end
		row.minus.button.Activated:Connect(function()
			local current = offer()
			if busy or not current then
				return
			end
			quantities[current.id] = math.max(1, (quantities[current.id] or 1) - 1)
			describe()
			local hub, inventory = hubPayload()
			if hub and inventory then
				renderShop(hub, inventory)
			end
		end)
		row.plus.button.Activated:Connect(function()
			local current = offer()
			if busy or not current then
				return
			end
			quantities[current.id] = math.min(current.maxQuantity, (quantities[current.id] or 1) + 1)
			describe()
			local hub, inventory = hubPayload()
			if hub and inventory then
				renderShop(hub, inventory)
			end
		end)
		row.tile.button.Activated:Connect(describe)
		row.buy.button.Activated:Connect(function()
			local current = offer()
			if busy or not current then
				return
			end
			describe()
			if not current.legality.canUse then
				actions.toast(CampaignUi.reason(current.legality))
				return
			end
			actions.submit({ kind = "PurchaseOffer", offerId = current.id, quantity = quantities[current.id] or 1 })
		end)
	end

	-- Bag ----------------------------------------------------------------------

	local function pageEntries(inventory: Inventory): { Entry }
		local list: { Entry } = {}
		local first = (bagPage - 1) * BAG_PAGE
		for i = first + 1, math.min(#inventory.entries, first + BAG_PAGE) do
			table.insert(list, inventory.entries[i])
		end
		return list
	end

	local function emptyBeltIndex(inventory: Inventory): number?
		for _, slot in inventory.belt do
			if slot.entryId == nil and slot.legality.canUse then
				return slot.index
			end
		end
		return nil
	end

	local function beltRules(): string
		return `PER FIGHT: {Limits.PartyBeltCharges} USE, {Limits.DirectHealsPerFight} HEAL, {Limits.MedKitsPerFight} KIT`
	end

	-- What the action button does for the current selection, if anything.
	type Plan = { label: string, fields: { [string]: any }?, reason: string }
	local function actionPlan(inventory: Inventory): Plan?
		local sel = selection
		if not sel or sel.kind ~= "Entry" then
			return nil
		end
		local entry = findEntry(inventory, sel.entryId)
		if not entry then
			return nil
		end
		if entry.kind == "Gear" then
			for _, slot in inventory.gear do
				if slot.slot == entry.slot and slot.entryId == entry.entryId then
					return { label = "EQUIPPED", fields = nil, reason = "" }
				end
			end
			local reason = CampaignUi.reason(entry.equipLegality)
			return {
				label = "EQUIP",
				fields = if entry.equipLegality.canUse then { kind = "SetGearSlot", slot = entry.slot, entryId = entry.entryId } else nil,
				reason = reason,
			}
		end
		if entry.beltItemId == nil then
			return { label = "NO BELT", fields = nil, reason = CampaignUi.reason(entry.beltLegality) }
		end
		for _, slot in inventory.belt do
			if slot.entryId == entry.entryId then
				return { label = "ON BELT", fields = nil, reason = "" }
			end
		end
		if not entry.beltLegality.canUse then
			return { label = "TO BELT", fields = nil, reason = CampaignUi.reason(entry.beltLegality) }
		end
		local index = emptyBeltIndex(inventory)
		if not index then
			return { label = "TO BELT", fields = nil, reason = "Belt is full. Pick a belt slot to swap." }
		end
		return { label = "TO BELT", fields = { kind = "SetBeltSlot", index = index, entryId = entry.entryId }, reason = "" }
	end

	local function renderBag(inventory: Inventory)
		local pages = math.max(1, math.ceil(#inventory.entries / BAG_PAGE))
		bagPage = math.clamp(bagPage, 1, pages)
		pageLabel.Text = if pages > 1 then `{bagPage}/{pages}` else ""
		prevPage.outline.Visible = pages > 1
		nextPage.outline.Visible = pages > 1
		prevPage.setState(if bagPage > 1 then "Normal" else "Disabled")
		nextPage.setState(if bagPage < pages then "Normal" else "Disabled")

		local sel = selection
		for _, slotView in inventory.gear do
			local tile = gearTiles[slotView.slot]
			local entry = findEntry(inventory, slotView.entryId)
			tile.set(if entry then entry.item.iconKey else nil, if entry then entry.item.label else nil, nil)
			tile.setHighlight(if sel and sel.kind == "Gear" and sel.slot == slotView.slot then Palette.Gold else nil)
		end
		for i, tile in beltTiles do
			local slotView = inventory.belt[i]
			tile.outline.Visible = slotView ~= nil
			if slotView then
				local entry = findEntry(inventory, slotView.entryId)
				local quantity = if entry and entry.kind == "Stack" then entry.quantity else nil
				tile.set(if entry then entry.item.iconKey else nil, if entry then entry.item.label else nil, if quantity then `x{quantity}` else nil)
				local color = if sel and sel.kind == "Belt" and sel.index == slotView.index then Palette.Gold
					elseif quantity == 0 then Colors.Hp
					else nil
				tile.setHighlight(color)
			end
		end
		local entries = pageEntries(inventory)
		for i, tile in bagTiles do
			local entry = entries[i]
			tile.outline.Visible = entry ~= nil
			if entry then
				local badge = if entry.kind == "Stack" then `x{entry.quantity}` elseif isEquipped(inventory, entry.entryId) then "E" else nil
				tile.set(entry.item.iconKey, entry.item.label, badge)
				tile.setHighlight(if sel and sel.kind == "Entry" and sel.entryId == entry.entryId then Palette.Gold else nil)
			end
		end

		-- Detail bar.
		clearButton.outline.Visible = false
		actionButton.outline.Visible = false
		detailReason.TextColor3 = Colors.TextDim
		if sel and sel.kind == "Entry" then
			local entry = findEntry(inventory, sel.entryId)
			if entry then
				if entry.kind == "Gear" then
					detailTitle.Text = `{string.upper(entry.item.label)}  T{entry.tier} {string.upper(entry.rarity)}`
					detailLine.Text = `{string.upper(entry.slot)}: {table.concat(entry.baseStatLines, "  ")}`
				else
					detailTitle.Text = `{string.upper(entry.item.label)}  x{entry.quantity}`
					detailLine.Text = entry.item.description
				end
				local plan = actionPlan(inventory)
				if plan then
					actionButton.outline.Visible = true
					actionButton.setText(plan.label)
					actionButton.setState(if plan.fields and not busy then "Primary" else "Disabled")
					detailReason.Text = plan.reason
					detailReason.TextColor3 = if plan.reason ~= "" then Colors.Hp else Colors.TextDim
				end
			end
		elseif sel and sel.kind == "Gear" then
			local slotView: InventoryTypes.GearSlotView? = nil
			for _, candidate in inventory.gear do
				if candidate.slot == sel.slot then
					slotView = candidate
				end
			end
			local entry = if slotView then findEntry(inventory, slotView.entryId) else nil
			detailTitle.Text = `{string.upper(sel.slot)} SLOT`
			detailLine.Text = if entry then string.upper(entry.item.label) else "Empty. Pick gear for this slot."
			detailReason.Text = if slotView then CampaignUi.reason(slotView.legality) else ""
			clearButton.outline.Visible = entry ~= nil
			clearButton.setState(if busy or not (slotView and slotView.legality.canUse) then "Disabled" else "Normal")
		elseif sel and sel.kind == "Belt" then
			local slotView = inventory.belt[sel.index]
			local entry = if slotView then findEntry(inventory, slotView.entryId) else nil
			detailTitle.Text = `BELT SLOT {sel.index}`
			detailLine.Text = if entry then string.upper(entry.item.label) else "Empty. Pick a belt item."
			detailReason.Text = beltRules()
			clearButton.outline.Visible = entry ~= nil
			clearButton.setState(if busy or not (slotView and slotView.legality.canUse) then "Disabled" else "Normal")
		else
			detailTitle.Text = "Pick an item, then a slot."
			detailLine.Text = beltRules()
			detailReason.Text = ""
		end
	end

	local function rerender()
		local current = snapshot
		if current then
			self:render(current)
		end
	end

	local function submitAndClear(fields: { [string]: any })
		selection = nil
		actions.submit(fields)
	end

	for slot, tile in gearTiles do
		tile.button.Activated:Connect(function()
			local _, inventory = hubPayload()
			if busy or not inventory then
				return
			end
			local sel = selection
			if sel and sel.kind == "Entry" then
				local entry = findEntry(inventory, sel.entryId)
				if entry and entry.kind == "Gear" and entry.slot == slot then
					if entry.equipLegality.canUse then
						submitAndClear({ kind = "SetGearSlot", slot = slot, entryId = entry.entryId })
					else
						actions.toast(CampaignUi.reason(entry.equipLegality))
					end
					return
				end
			end
			selection = { kind = "Gear", slot = slot :: InventoryTypes.GearSlot }
			rerender()
		end)
	end
	for index, tile in beltTiles do
		tile.button.Activated:Connect(function()
			local _, inventory = hubPayload()
			if busy or not inventory then
				return
			end
			local sel = selection
			if sel and sel.kind == "Entry" then
				local entry = findEntry(inventory, sel.entryId)
				if entry and entry.kind == "Stack" and entry.beltItemId ~= nil then
					if entry.beltLegality.canUse then
						submitAndClear({ kind = "SetBeltSlot", index = index, entryId = entry.entryId })
					else
						actions.toast(CampaignUi.reason(entry.beltLegality))
					end
					return
				end
			end
			selection = { kind = "Belt", index = index }
			rerender()
		end)
	end
	for i, tile in bagTiles do
		tile.button.Activated:Connect(function()
			local _, inventory = hubPayload()
			if busy or not inventory then
				return
			end
			local entry = pageEntries(inventory)[i]
			if not entry then
				return
			end
			local sel = selection
			-- A slot picked first: put this item straight into it.
			if sel and sel.kind == "Gear" and entry.kind == "Gear" and entry.slot == sel.slot and entry.equipLegality.canUse then
				submitAndClear({ kind = "SetGearSlot", slot = sel.slot, entryId = entry.entryId })
				return
			elseif sel and sel.kind == "Belt" and entry.kind == "Stack" and entry.beltItemId ~= nil and entry.beltLegality.canUse then
				submitAndClear({ kind = "SetBeltSlot", index = sel.index, entryId = entry.entryId })
				return
			end
			selection = { kind = "Entry", entryId = entry.entryId }
			rerender()
		end)
	end
	actionButton.button.Activated:Connect(function()
		local _, inventory = hubPayload()
		if busy or not inventory then
			return
		end
		local plan = actionPlan(inventory)
		if plan and plan.fields then
			submitAndClear(plan.fields)
		elseif plan and plan.reason ~= "" then
			actions.toast(plan.reason)
		end
	end)
	clearButton.button.Activated:Connect(function()
		local sel = selection
		if busy or not sel then
			return
		end
		if sel.kind == "Gear" then
			submitAndClear({ kind = "SetGearSlot", slot = sel.slot })
		elseif sel.kind == "Belt" then
			submitAndClear({ kind = "SetBeltSlot", index = sel.index })
		end
	end)
	prevPage.button.Activated:Connect(function()
		bagPage -= 1
		rerender()
	end)
	nextPage.button.Activated:Connect(function()
		bagPage += 1
		rerender()
	end)

	-- Party --------------------------------------------------------------------

	local function renderParty(current: Snapshot)
		local companion = current.companion
		local key: string? = nil
		if companion.state == "Locked" then
			companionName.Text = "NO COMPANION YET"
			companionState.Text = "Clear D1 on the Act Map."
			companionText.Text = "Someone you meet on the road may want to join you."
			recruitButton.outline.Visible = false
			partyHint.Text = ""
		else
			key = companion.spriteKey or "CompanionIdle"
			companionName.Text = string.upper(companion.label)
			companionText.Text = companion.description
			if companion.state == "Offered" then
				companionState.Text = "WANTS TO JOIN YOU"
				companionState.TextColor3 = Palette.Gold
				recruitButton.outline.Visible = true
				recruitButton.setState(if companion.legality.canUse and not busy then "Primary" else "Disabled")
				partyHint.Text = CampaignUi.reason(companion.legality)
			else
				companionState.Text = "IN YOUR PARTY"
				companionState.TextColor3 = Colors.Active
				recruitButton.outline.Visible = false
				partyHint.Text = ""
			end
		end
		if key ~= spriteKey then
			spriteKey = key
			companionHolder:ClearAllChildren()
			if key then
				FighterSprite.create(companionHolder, key :: any, false)
			end
		end
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

	-- Stations -----------------------------------------------------------------

	local function renderStations(current: Snapshot)
		shop.Visible = station == "Shop"
		bag.Visible = station == "Bag"
		party.Visible = station == "Party"
		for name, button in stationButtons do
			button.setState(if name == station then "Selected" else "Normal")
		end
		local offered = current.companion.state == "Offered"
		stationButtons.Party.setText(if offered then "PARTY  NEW!" else "PARTY")
		if offered and station ~= "Party" then
			stationButtons.Party.setState("Primary")
		end
	end

	for name, button in stationButtons do
		button.button.Activated:Connect(function()
			station = name
			selection = nil
			rerender()
		end)
	end

	-- Blacksmith ----------------------------------------------------------------

	local function equippedEntry(uuid: string): boolean
		local _, inventory = hubPayload()
		if not inventory then
			return false
		end
		for _, slot in inventory.gear do
			if slot.entryId == uuid then
				return true
			end
		end
		return false
	end

	local function openStation(kind: Phase4Station)
		if busy or overlay or openingStation then
			return
		end
		if actions.isMock then
			actions.toast(`{PHASE4_NAME[kind]} needs the game server.`)
			return
		end
		openingStation = true
		rerender()
		local client = actions.phase4()
		openingStation = false
		if not frame.Parent then
			return
		end
		rerender()
		if not client then
			actions.toast(`{PHASE4_NAME[kind]} is closed. Try again soon.`)
			return
		end
		local function onClose()
			overlay = nil
			rerender()
			-- Every station spends the shared Yen wallet. Show the current balance.
			actions.refreshCampaign()
		end
		if kind == "Smith" then
			overlay = BlacksmithScreen.open(frame, {
				client = client,
				toast = actions.toast,
				isEquipped = equippedEntry,
				onClose = onClose,
			})
		elseif kind == "Clinic" then
			overlay = ClinicScreen.open(frame, { client = client, toast = actions.toast, onClose = onClose })
		else
			overlay = ParlorScreen.open(frame, { client = client, toast = actions.toast, onClose = onClose })
		end
	end

	for kind, button in phase4Buttons do
		button.button.Activated:Connect(function()
			openStation(kind)
		end)
	end

	setOut.button.Activated:Connect(function()
		local hub = hubPayload()
		if busy or not hub then
			return
		end
		if not hub.setOutLegality.canUse then
			actions.toast(CampaignUi.reason(hub.setOutLegality))
			return
		end
		actions.submit({ kind = "Navigate", destination = "ActMap" })
	end)

	function self.render(_self: Screen.Screen, current: Snapshot)
		local scene = current.scene
		if scene.kind ~= "Hub" then
			return
		end
		snapshot = current
		local character = current.character
		local extra = if current.companion.state == "Recruited" then `+ {string.upper(current.companion.label)}` else nil
		topBar.set("PUBLIC HUB", character.level, character.yen, extra)
		preview.set(character.appearance, nil)
		originLabel.Text = if character.origin then OriginSelect.displayName(character.origin) else ""
		-- Forget a selection whose item is gone.
		local sel = selection
		if sel and sel.kind == "Entry" and not findEntry(scene.inventory, sel.entryId) then
			selection = nil
		end
		renderStations(current)
		renderShop(scene.hub, scene.inventory)
		renderBag(scene.inventory)
		renderParty(current)
		setOut.setState(if scene.hub.setOutLegality.canUse and not busy then "Primary" else "Disabled")
		for _, button in phase4Buttons do
			button.setState(if busy or openingStation or actions.isMock then "Disabled" else "Normal")
		end
	end

	function self.setBusy(_self: Screen.Screen, value: boolean)
		busy = value
		rerender()
	end

	function self.destroy(_self: Screen.Screen)
		local open = overlay
		overlay = nil
		if open then
			open:destroy()
		end
		frame:Destroy()
	end

	return self
end

return HubScreen
