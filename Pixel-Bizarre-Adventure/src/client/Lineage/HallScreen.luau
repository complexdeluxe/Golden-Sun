--!strict
-- The Hall of Ancestors, opened from the Hub. Draws over the whole Hub.
--
-- Four tabs over one LineageRemotes snapshot:
--   LIFE       generation, age, Elder and Veteran Composure, recoveries, Echoes,
--              the final-attempt warning, and Pass the Torch.
--   BLOODLINE  the 11 Bloodline Tree nodes in their three branches, with rank,
--              next cost, description and the server's legality.
--   HEIRLOOMS  the catalog with locked / carried / attuned state, the carry
--              limit, and separate carry and attune controls.
--   MASTERY    per-kit marks toward the 2, 5 and 8 mark unlocks, target mode
--              and utility variant controls, and the mastery title.
--
-- Every value, cost and legality is the server's. Requests go through an
-- ActionClient: an unconfirmed action shows RETRY LAST ACTION in the top bar and
-- blocks new actions until it settles. A Pass the Torch reply that is lost is
-- recovered with the original request, so the life settles once.
--
-- Layout (native px):
--   top bar   0..14     title, generation, Echoes, RETRY LAST ACTION
--   tabs      16..28
--   body      30..156   the open tab
--   bottom    158..178  BACK TO HUB, status line

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Contract = require(ReplicatedStorage.Shared.Contracts.SuccessionTypes)
local CombatTypes = require(ReplicatedStorage.Shared.Contracts.CombatTypes)
local PixelUi = require(script.Parent.Parent.Battle.PixelUi)
local CampaignUi = require(script.Parent.Parent.Campaign.CampaignUi)
local ActionClient = require(script.Parent.Parent.Net.ActionClient)
local Format = require(script.Parent.LineageFormat)

type Snapshot = Contract.Snapshot
type NodeView = Contract.BloodlineNodeView
type MasteryView = Contract.MasteryView
type Legality = CombatTypes.ActionLegality

local Colors = PixelUi.Colors
local Palette = CampaignUi.Colors

local BODY_Y = 30
local BODY_H = 126
local TAB_ORDER = { "Life", "Bloodline", "Heirlooms", "Mastery" }
local TAB_LABEL: { [string]: string } = { Life = "LIFE", Bloodline = "BLOODLINE", Heirlooms = "HEIRLOOMS", Mastery = "MASTERY" }
local HEIRLOOM_ROWS = 6
local KIT_ROWS = 6

export type Deps = {
	client: ActionClient.Client,
	toast: (message: string) -> (),
	-- Called once when the player leaves. The Hub refreshes Campaign there.
	onClose: () -> (),
	-- Called after Pass the Torch settles, so the campaign shows the new life.
	onLifeChanged: () -> (),
}

export type Hall = {
	destroy: (self: Hall) -> (),
}

local HallScreen = {}

local function wrapped(label: TextLabel): TextLabel
	label.TextWrapped = true
	label.TextYAlignment = Enum.TextYAlignment.Top
	return label
end

function HallScreen.open(parent: Instance, deps: Deps): Hall
	local client = deps.client
	local frame = PixelUi.frame(parent, "Hall", 0, 0, 320, 180, Palette.Backdrop)
	frame.Active = true
	frame.ZIndex = 5

	-- Top bar -------------------------------------------------------------------
	local bar = PixelUi.frame(frame, "TopBar", 0, 0, 320, 14, Palette.PurpleDark)
	PixelUi.frame(bar, "Edge", 0, 13, 320, 1, Palette.Purple)
	PixelUi.label(bar, "Title", 4, 2, 110, 10, "HALL OF ANCESTORS", Palette.Gold)
	local genLabel = PixelUi.label(bar, "Generation", 114, 2, 146, 10, "", Colors.TextDim, Enum.TextXAlignment.Right)
	local echoLabel = PixelUi.label(bar, "Echoes", 248, 2, 68, 10, "", Palette.Gold, Enum.TextXAlignment.Right)
	local retryLast = CampaignUi.button(bar, "RetryLast", 132, 1, 110, 12, "RETRY LAST ACTION")
	retryLast.outline.ZIndex = 2
	retryLast.outline.Visible = false

	-- Tabs ----------------------------------------------------------------------
	local tabButtons: { [string]: CampaignUi.Button } = {}
	for i, id in TAB_ORDER do
		tabButtons[id] = CampaignUi.button(frame, `{id}Tab`, 4 + (i - 1) * 79, 16, 76, 12, TAB_LABEL[id])
	end

	local body = PixelUi.frame(frame, "Body", 0, BODY_Y, 320, BODY_H)
	local notice = PixelUi.label(frame, "Notice", 0, 70, 320, 10, "", Colors.TextDim, Enum.TextXAlignment.Center)
	local reload = CampaignUi.button(frame, "Reload", 130, 86, 60, 14, "RETRY")
	local back = CampaignUi.button(frame, "Back", 4, 159, 94, 18, "< BACK TO HUB")
	local statusLine = PixelUi.label(frame, "Status", 102, 165, 214, 9, "", Colors.TextDim)

	-- LIFE ----------------------------------------------------------------------
	local life = PixelUi.frame(body, "Life", 0, 0, 320, BODY_H)
	local genTitle = PixelUi.label(life, "Generation", 4, 0, 152, 10, "", Palette.Gold)
	local ageLine = PixelUi.label(life, "Age", 4, 11, 152, 9, "", Colors.Text)
	local deathLine = PixelUi.label(life, "NaturalEnd", 4, 20, 152, 9, "", Colors.TextDim)
	local elderLine = PixelUi.label(life, "Elder", 4, 31, 152, 9, "", Colors.Text)
	local veteranLine = PixelUi.label(life, "Veteran", 4, 40, 152, 9, "", Colors.Text)
	local recoveryLine = PixelUi.label(life, "Recoveries", 4, 51, 152, 9, "", Colors.Text)
	local pips: { Frame } = {}
	for i = 1, Contract.MaxRecoveries do
		pips[i] = PixelUi.frame(life, `Pip{i}`, 4 + (i - 1) * 14, 61, 12, 5, Colors.Active)
	end
	local echoLine = PixelUi.label(life, "EchoBalance", 4, 70, 152, 9, "", Palette.Gold)
	local earnedLine = PixelUi.label(life, "Earned", 4, 79, 152, 9, "", Colors.TextDim)
	local finalBox = PixelUi.frame(life, "FinalAttempt", 2, 92, 154, 32, Colors.HpBack)
	PixelUi.label(finalBox, "Title", 3, 2, 148, 9, "FINAL ATTEMPT", Colors.Hp)
	wrapped(PixelUi.label(finalBox, "Body", 3, 11, 148, 20, "A CASTLE DEFEAT ENDS THIS GENERATION.", Colors.Text))

	PixelUi.frame(life, "Rule", 160, 0, 1, BODY_H, Palette.Purple)
	PixelUi.label(life, "TorchTitle", 166, 0, 150, 10, "PASS THE TORCH", Palette.Gold)
	local torchText = wrapped(PixelUi.label(life, "TorchText", 166, 12, 150, 84, "", Colors.Text))
	local torchButton = CampaignUi.button(life, "Torch", 166, 100, 150, 16, "PASS THE TORCH")
	local confirmButton = CampaignUi.button(life, "Confirm", 166, 100, 73, 16, "CONFIRM")
	local cancelButton = CampaignUi.button(life, "Cancel", 243, 100, 73, 16, "CANCEL")
	local heirButton = CampaignUi.button(life, "MeetHeir", 166, 100, 150, 16, "MEET YOUR HEIR")

	-- BLOODLINE -----------------------------------------------------------------
	local tree = PixelUi.frame(body, "Bloodline", 0, 0, 320, BODY_H)
	type NodeRow = { header: TextLabel?, outline: Frame, fill: Frame, name: TextLabel, rank: TextLabel, press: TextButton, nodeId: string }
	local nodeRows: { NodeRow } = {}
	do
		local y = 0
		for _, branchId in Contract.BloodlineBranchOrder do
			PixelUi.label(tree, `Branch{branchId}`, 4, y, 154, 9, Format.branch(branchId), Palette.Gold)
			y += 9
			for _, nodeId in Contract.BloodlineNodeIds[branchId] do
				local outline, fill = PixelUi.box(tree, `Node_{nodeId}`, 2, y, 158, 9, Palette.Tile)
				table.insert(nodeRows, {
					outline = outline,
					fill = fill,
					name = PixelUi.label(fill, "Name", 2, 0, 122, 7, "", Colors.Text),
					rank = PixelUi.label(fill, "Rank", 124, 0, 30, 7, "", Colors.TextDim, Enum.TextXAlignment.Right),
					-- The whole 9 px row, border included, so rows tap edge to edge on phones.
					press = PixelUi.button(outline, "Press", 0, 0, 158, 9, ""),
					nodeId = nodeId,
				})
				y += 9
			end
		end
	end
	local nodeTitle = wrapped(PixelUi.label(tree, "NodeTitle", 166, 0, 150, 18, "", Palette.Gold))
	local nodeRank = PixelUi.label(tree, "NodeRank", 166, 19, 150, 9, "", Colors.Text)
	local nodeCost = PixelUi.label(tree, "NodeCost", 166, 28, 150, 9, "", Colors.Text)
	local nodeDescription = wrapped(PixelUi.label(tree, "NodeDescription", 166, 39, 150, 68, "", Colors.TextDim))
	local buyButton = CampaignUi.button(tree, "Buy", 166, 110, 150, 15, "BUY RANK")

	-- HEIRLOOMS -----------------------------------------------------------------
	local loom = PixelUi.frame(body, "Heirlooms", 0, 0, 320, BODY_H)
	local carryTitle = PixelUi.label(loom, "CarryTitle", 4, 0, 154, 9, "", Palette.Gold)
	type LoomRow = { outline: Frame, fill: Frame, tile: CampaignUi.Tile, name: TextLabel, badge: TextLabel, press: TextButton }
	local loomRows: { LoomRow } = {}
	for i = 1, HEIRLOOM_ROWS do
		local outline, fill = PixelUi.box(loom, `Heirloom{i}`, 2, 10 + (i - 1) * 14, 158, 13, Palette.Tile)
		local tile = CampaignUi.tile(fill, "Icon", 0, 0, 9, "")
		loomRows[i] = {
			outline = outline,
			fill = fill,
			tile = tile,
			-- Native widths that fit the longest catalog name (ZEPPELI'S CHECKERED HAT
			-- needs 108) and ATTUNED (needs 33) at every UI scale, 3x included.
			name = PixelUi.label(fill, "Name", 14, 1, 108, 9, "", Colors.Text),
			badge = PixelUi.label(fill, "Badge", 122, 1, 33, 9, "", Colors.TextDim, Enum.TextXAlignment.Right),
			press = PixelUi.button(fill, "Press", 0, 0, 156, 11, ""),
		}
	end
	local carriedLine = wrapped(PixelUi.label(loom, "Carried", 4, 96, 154, 18, "", Colors.Active))
	local attunedLine = PixelUi.label(loom, "Attuned", 4, 115, 154, 9, "", Palette.Gold)
	local loomTitle = wrapped(PixelUi.label(loom, "Name", 166, 0, 150, 18, "", Palette.Gold))
	local loomState = PixelUi.label(loom, "State", 166, 19, 150, 9, "", Colors.TextDim)
	local loomDescription = wrapped(PixelUi.label(loom, "Description", 166, 30, 150, 54, "", Colors.Text))
	local carryButton = CampaignUi.button(loom, "Carry", 166, 88, 73, 14, "CARRY")
	local attuneButton = CampaignUi.button(loom, "Attune", 243, 88, 73, 14, "ATTUNE")
	local loomHint = wrapped(PixelUi.label(loom, "Hint", 166, 105, 150, 20, "", Colors.TextDim))

	-- MASTERY -------------------------------------------------------------------
	local mastery = PixelUi.frame(body, "Mastery", 0, 0, 320, BODY_H)
	PixelUi.label(mastery, "KitTitle", 4, 0, 110, 9, "KITS", Palette.Gold)
	type KitRow = { outline: Frame, fill: Frame, name: TextLabel, marks: TextLabel, press: TextButton }
	local kitRows: { KitRow } = {}
	for i = 1, KIT_ROWS do
		local outline, fill = PixelUi.box(mastery, `Kit{i}`, 2, 10 + (i - 1) * 13, 114, 12, Palette.Tile)
		kitRows[i] = {
			outline = outline,
			fill = fill,
			name = PixelUi.label(fill, "Name", 2, 1, 80, 9, "", Colors.Text),
			marks = PixelUi.label(fill, "Marks", 80, 1, 30, 9, "", Palette.Gold, Enum.TextXAlignment.Right),
			press = PixelUi.button(fill, "Press", 0, 0, 112, 10, ""),
		}
	end
	local kitEmpty = wrapped(PixelUi.label(mastery, "Empty", 4, 12, 110, 40, "NO KIT MASTERY YET. FIRST CLEARS AND REPLAYS EARN MARKS.", Colors.TextDim))
	local kitTitle = PixelUi.label(mastery, "Name", 124, 0, 192, 9, "", Palette.Gold)
	local markLine = PixelUi.label(mastery, "MarkCount", 124, 10, 192, 9, "", Colors.Text)
	local markBar, setMarks = PixelUi.bar(mastery, "MarkBar", 124, 20, 192, 6, Palette.Gold, Palette.GoldDark)
	for _, at in { Contract.MasteryAltTargetMarks, Contract.MasteryUtilityVariantMarks } do
		PixelUi.frame(markBar, `Tick{at}`, math.round(192 * at / Contract.MasteryTitleMarks), 0, 1, 6, Colors.Ink)
	end
	local milestoneLines: { TextLabel } = {}
	for i = 1, 3 do
		milestoneLines[i] = PixelUi.label(mastery, `Milestone{i}`, 124, 29 + (i - 1) * 9, 192, 9, "", Colors.TextDim)
	end
	PixelUi.label(mastery, "TargetTitle", 124, 60, 70, 12, "TARGET MODE", Colors.Text)
	local targetDefault = CampaignUi.button(mastery, "TargetDefault", 196, 59, 58, 13, "DEFAULT")
	local targetAlt = CampaignUi.button(mastery, "TargetAlt", 258, 59, 58, 13, "ALT")
	PixelUi.label(mastery, "UtilityTitle", 124, 76, 70, 12, "UTILITY", Colors.Text)
	local utilityDefault = CampaignUi.button(mastery, "UtilityDefault", 196, 75, 58, 13, "DEFAULT")
	local utilityAlt = CampaignUi.button(mastery, "UtilityAlt", 258, 75, 58, 13, "ALT")
	local titleLine = PixelUi.label(mastery, "TitleEarned", 124, 94, 192, 9, "", Palette.Gold)
	local masteryHint = wrapped(PixelUi.label(mastery, "Hint", 124, 104, 192, 20, "", Colors.TextDim))

	local panels: { [string]: Frame } = { Life = life, Bloodline = tree, Heirlooms = loom, Mastery = mastery }

	-- State -----------------------------------------------------------------------
	local alive = true
	local busy = false
	local loaded = false
	local loadError: string? = nil
	local tab = "Life"
	local status: { text: string, color: Color3 }? = nil
	local selectedNode: string = Contract.BloodlineNodeIds.Momentum[1]
	local selectedLoom: string? = nil
	local selectedKit: string? = nil
	local confirmingTorch = false
	-- Set once a Pass the Torch receipt is in hand, to show the new life.
	local passed: { retiredGeneration: number, echoesAwarded: number }? = nil
	local render: () -> ()

	local function setStatus(text: string?, color: Color3?)
		status = if text then { text = text, color = color or Colors.TextDim } else nil
	end

	local function current(): Snapshot?
		return if loaded then client:snapshot() :: Snapshot? else nil
	end

	local function pending(): string?
		local action = client:pendingAction()
		return if action then Format.action(action :: any, client:snapshot()) else nil
	end

	local function explain(legality: Legality): boolean
		if legality.canUse then
			return false
		end
		deps.toast(CampaignUi.reason(legality))
		return true
	end

	local function findNode(snapshot: Snapshot, id: string): NodeView?
		for _, branch in snapshot.bloodlineTree.branches do
			for _, node in branch.nodes do
				if node.nodeId == id then
					return node
				end
			end
		end
		return nil
	end

	local function findKit(snapshot: Snapshot, id: string?): MasteryView?
		for _, entry in snapshot.mastery do
			if entry.kitId == id then
				return entry
			end
		end
		return nil
	end

	-- A Pass the Torch receipt, from this press or recovered from a lost reply.
	local function onTorch(receipt: any, retiredGeneration: number)
		passed = { retiredGeneration = retiredGeneration, echoesAwarded = receipt.echoesAwarded }
		confirmingTorch = false
		tab = "Life"
		deps.onLifeChanged()
	end

	local function takeRecovered()
		local receipt = client:takeRecovered({ PassedTheTorch = true })
		if receipt then
			local snapshot = client:snapshot()
			onTorch(receipt, if snapshot then math.max(1, snapshot.generation - 1) else 1)
		end
	end

	-- Requests ----------------------------------------------------------------------

	local function retry()
		if busy or not alive or not client:pendingAction() then
			return
		end
		busy = true
		setStatus("RETRYING LAST ACTION...")
		render()
		local result = client:retryPending()
		if not alive then
			return
		end
		busy = false
		if client:snapshot() and (result.ok or not result.uncertain) then
			loaded = true
			loadError = nil
		elseif not loaded then
			loadError = "Couldn't reach the Hall."
		end
		local receipt = result.receipt
		if result.ok and receipt then
			local text = Format.receipt(receipt :: any, client:snapshot())
			setStatus(text, Colors.Active)
			deps.toast("Recovered: " .. text)
		elseif result.uncertain then
			setStatus("STILL UNCONFIRMED. RETRY AGAIN.", Colors.Hp)
			deps.toast(result.message or "Still unconfirmed.")
		else
			local message = result.message or "The Hall refused it."
			setStatus(string.upper("Last action not applied: " .. message), Colors.Hp)
			deps.toast(message)
		end
		takeRecovered()
		render()
	end

	local function run(action: Contract.Action, after: ((receipt: Contract.Receipt) -> ())?)
		if busy or not alive then
			return
		end
		if client:pendingAction() then
			deps.toast("Finishing your last action first.")
			retry()
			return
		end
		busy = true
		setStatus("WORKING...")
		render()
		local before = client:snapshot()
		local result = client:perform(action :: any)
		if not alive then
			return
		end
		busy = false
		local receipt = result.receipt :: Contract.Receipt?
		if result.ok and receipt then
			local text = Format.receipt(receipt, client:snapshot())
			setStatus(text, Colors.Active)
			deps.toast(text)
			if receipt.kind == "PassedTheTorch" then
				onTorch(receipt, if before then before.generation else 1)
			elseif after then
				after(receipt)
			end
		else
			local waiting = pending()
			local message = result.message or "The Hall refused it."
			if result.uncertain and waiting then
				message = `UNCONFIRMED: {waiting}.`
			elseif result.code == "StaleRevision" then
				message = "The lineage changed. Check and try again."
			end
			setStatus(string.upper(message), Colors.Hp)
			deps.toast(message)
		end
		takeRecovered()
		render()
	end

	local function load()
		if busy or not alive then
			return
		end
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
			loadError = result.message or "The Hall is closed."
		end
		local waiting = pending()
		if loaded and waiting then
			setStatus(`UNCONFIRMED: {waiting}.`, Colors.Hp)
		end
		if loaded then
			takeRecovered()
		end
		render()
	end

	-- Drawing ------------------------------------------------------------------------

	local function renderLife(snapshot: Snapshot, blocked: boolean)
		local age = snapshot.age
		local ledger = snapshot.recoveryLedger
		genTitle.Text = `GENERATION {snapshot.generation}`
		ageLine.Text = `AGE {age.currentAge}   ELDER AT {age.elderThreshold}`
		deathLine.Text = `NATURAL END AT {age.naturalDeathAge}`
		elderLine.Text = if age.isElder then "ELDER: YES" else "ELDER: NOT YET"
		elderLine.TextColor3 = if age.isElder then Colors.Hp else Colors.Active
		veteranLine.Text = if age.veteranComposureActive then "VETERAN COMPOSURE: ACTIVE" else "VETERAN COMPOSURE: OFF"
		veteranLine.TextColor3 = if age.veteranComposureActive then Colors.Active else Colors.TextDim
		recoveryLine.Text = `RECOVERIES {ledger.recoveriesRemaining}/{ledger.maxRecoveries}`
		for i, pip in pips do
			pip.Visible = i <= ledger.maxRecoveries
			pip.BackgroundColor3 = if i <= ledger.recoveriesRemaining then Colors.Active else Colors.HpBack
		end
		echoLine.Text = `ECHOES {snapshot.bloodlineTree.echoesBalance}`
		earnedLine.Text = `THIS LIFE HAS EARNED {ledger.eligibleEchoes}`
		finalBox.Visible = ledger.isFinalAttempt

		torchButton.outline.Visible = false
		confirmButton.outline.Visible = false
		cancelButton.outline.Visible = false
		heirButton.outline.Visible = false
		local done = passed
		if done then
			torchText.Text = `GENERATION {done.retiredGeneration} RETIRED. +{done.echoesAwarded} ECHOES TO THE BLOODLINE.\n\n`
				.. `GENERATION {snapshot.generation} BEGINS. YOUR HEIR STARTS AT ACT 1, LEVEL 1, `
				.. "WITH THE STARTER KIT."
			torchText.TextColor3 = Colors.Active
			heirButton.outline.Visible = true
			heirButton.setState(if busy then "Disabled" else "Primary")
		elseif confirmingTorch then
			torchText.Text = `RETIRE GENERATION {snapshot.generation} AT AGE {age.currentAge}?\n`
				.. `+{ledger.retireNowEchoes} ECHOES TO THE BLOODLINE.\n\n`
				.. `GENERATION {snapshot.generation + 1} STARTS OVER AT ACT 1, LEVEL 1. `
				.. "ECHOES, THE TREE, HEIRLOOMS AND MASTERY CARRY ON."
			torchText.TextColor3 = Colors.Text
			confirmButton.outline.Visible = true
			cancelButton.outline.Visible = true
			confirmButton.setState(if blocked then "Disabled" else "Primary")
			cancelButton.setState(if busy then "Disabled" else "Normal")
		else
			local lines = `RETIRE NOW: +{ledger.retireNowEchoes} ECHOES.\nIF THIS LIFE FALLS: +{ledger.terminalFallbackEchoes}.\n\n`
			if ledger.ledgerSettled then
				lines ..= "THIS LIFE HAS ENDED."
			elseif ledger.canRetireNow then
				lines ..= "YOUR HEIR TAKES OVER AT ACT 1."
			else
				lines ..= "RETIRING NEEDS AN ACT 3 CLEAR AND THE SAFE HUB."
			end
			torchText.Text = lines
			torchText.TextColor3 = Colors.Text
			torchButton.outline.Visible = true
			torchButton.setState(if blocked or not ledger.canRetireNow then "Disabled" else "Primary")
		end
	end

	local function renderTree(snapshot: Snapshot, blocked: boolean)
		for _, row in nodeRows do
			local node = findNode(snapshot, row.nodeId)
			row.outline.Visible = node ~= nil
			if node then
				row.name.Text = string.upper(node.label)
				row.rank.Text = `{node.rank}/{node.maxRank}`
				row.rank.TextColor3 = if node.rank >= node.maxRank then Palette.Gold
					elseif node.legality.canUse then Colors.Active
					else Colors.TextDim
				local isSelected = node.nodeId == selectedNode
				row.outline.BackgroundColor3 = if isSelected then Palette.Gold else Colors.Ink
				row.fill.BackgroundColor3 = if isSelected then Colors.ButtonHover else Palette.Tile
			end
		end
		local node = findNode(snapshot, selectedNode)
		if not node then
			nodeTitle.Text = ""
			nodeRank.Text = ""
			nodeCost.Text = ""
			nodeDescription.Text = ""
			buyButton.setState("Disabled")
			return
		end
		nodeTitle.Text = string.upper(node.label)
		nodeRank.Text = `RANK {node.rank}/{node.maxRank}`
		local cost = node.nextCostEchoes
		nodeCost.Text = if cost then `NEXT RANK {cost} ECHOES` else "MAX RANK"
		nodeCost.TextColor3 = if cost == nil then Palette.Gold
			elseif cost > snapshot.bloodlineTree.echoesBalance then Colors.Hp
			else Colors.Text
		nodeDescription.Text = string.upper(node.description)
		buyButton.setText(if cost then `BUY RANK {node.rank + 1}  {cost}E` else "MAX RANK")
		buyButton.setState(if blocked or not node.legality.canUse then "Disabled" else "Primary")
	end

	local function renderHeirlooms(snapshot: Snapshot, blocked: boolean)
		local view = snapshot.heirlooms
		carryTitle.Text = `CARRY {#view.carriedIds}/{view.carryLimit}`
		local catalog = view.catalog
		if selectedLoom == nil and catalog[1] then
			selectedLoom = catalog[1].id
		end
		for i, row in loomRows do
			local entry = catalog[i]
			row.outline.Visible = entry ~= nil
			if entry then
				local unlocked = table.find(view.unlockedIds, entry.id) ~= nil
				local carried = table.find(view.carriedIds, entry.id) ~= nil
				local attuned = view.attunedId == entry.id
				row.tile.set(entry.iconKey, entry.label, nil)
				row.name.Text = string.upper(entry.label)
				row.name.TextColor3 = if unlocked then Colors.Text else Colors.TextDim
				row.badge.Text = if attuned then "ATTUNED" elseif carried then "CARRIED" elseif unlocked then "" else "LOCKED"
				row.badge.TextColor3 = if attuned then Palette.Gold elseif carried then Colors.Active else Colors.TextDim
				local isSelected = entry.id == selectedLoom
				row.outline.BackgroundColor3 = if isSelected then Palette.Gold else Colors.Ink
				row.fill.BackgroundColor3 = if isSelected then Colors.ButtonHover else Palette.Tile
			end
		end
		carriedLine.Text = `CARRIED: {Format.heirloomList(snapshot, view.carriedIds)}`
		local attunedId = view.attunedId
		attunedLine.Text = if attunedId then `ATTUNED: {Format.heirloom(snapshot, attunedId)}` else "ATTUNED: NONE"

		local entry: Contract.HeirloomDisplay? = nil
		for _, candidate in catalog do
			if candidate.id == selectedLoom then
				entry = candidate
			end
		end
		if not entry then
			loomTitle.Text = ""
			loomState.Text = ""
			loomDescription.Text = ""
			carryButton.setState("Disabled")
			attuneButton.setState("Disabled")
			return
		end
		local unlocked = table.find(view.unlockedIds, entry.id) ~= nil
		local carried = table.find(view.carriedIds, entry.id) ~= nil
		local attuned = attunedId == entry.id
		loomTitle.Text = string.upper(entry.label)
		loomState.Text = if attuned then "CARRIED AND ATTUNED" elseif carried then "CARRIED, NOT ATTUNED"
			elseif unlocked then "UNLOCKED" else "LOCKED"
		loomState.TextColor3 = if attuned then Palette.Gold elseif carried then Colors.Active
			elseif unlocked then Colors.Text else Colors.TextDim
		loomDescription.Text = string.upper(entry.description)
		carryButton.setText(if carried then "UNCARRY" else "CARRY")
		attuneButton.setText(if attuned then "UNATTUNE" else "ATTUNE")
		local open = view.legality.canUse and not blocked
		carryButton.setState(if open and unlocked then "Normal" else "Disabled")
		attuneButton.setState(if open and carried then (if attuned then "Normal" else "Primary") else "Disabled")
		loomHint.Text = if not view.legality.canUse then string.upper(CampaignUi.reason(view.legality))
			else `CARRY UP TO {view.carryLimit}. ATTUNE ONE CARRIED HEIRLOOM TO USE IT.`
		loomHint.TextColor3 = if view.legality.canUse then Colors.TextDim else Colors.Hp
	end

	local function variantButtons(defaultButton: CampaignUi.Button, altButton: CampaignUi.Button, value: Contract.MasteryVariant, altAllowed: boolean, blocked: boolean)
		defaultButton.setState(if value == "Default" then "Selected" elseif blocked then "Disabled" else "Normal")
		altButton.setState(if value == "Alt" then "Selected" elseif blocked or not altAllowed then "Disabled" else "Normal")
	end

	local function renderMastery(snapshot: Snapshot, blocked: boolean)
		local kits = snapshot.mastery
		if findKit(snapshot, selectedKit) == nil then
			selectedKit = if kits[1] then kits[1].kitId else nil
		end
		kitEmpty.Visible = #kits == 0
		for i, row in kitRows do
			local entry = kits[i]
			row.outline.Visible = entry ~= nil
			if entry then
				row.name.Text = Format.kit(entry.kitId)
				row.marks.Text = `{entry.marks}/{Contract.MasteryTitleMarks}`
				local isSelected = entry.kitId == selectedKit
				row.outline.BackgroundColor3 = if isSelected then Palette.Gold else Colors.Ink
				row.fill.BackgroundColor3 = if isSelected then Colors.ButtonHover else Palette.Tile
			end
		end
		local kit = findKit(snapshot, selectedKit)
		local show = kit ~= nil
		for _, item: GuiObject in { kitTitle, markLine, markBar, titleLine, masteryHint, targetDefault.outline, targetAlt.outline,
			utilityDefault.outline, utilityAlt.outline } :: { any } do
			item.Visible = show
		end
		for _, line in milestoneLines do
			line.Visible = show
		end
		for _, name in { "TargetTitle", "UtilityTitle" } do
			local label = mastery:FindFirstChild(name)
			if label then
				(label :: GuiObject).Visible = show
			end
		end
		if not kit then
			return
		end
		kitTitle.Text = Format.kit(kit.kitId)
		markLine.Text = `{kit.marks}/{Contract.MasteryTitleMarks} MARKS`
		setMarks(kit.marks / Contract.MasteryTitleMarks)
		local utilityAllowed = kit.marks >= Contract.MasteryUtilityVariantMarks
		local unlocks = {
			{ Contract.MasteryAltTargetMarks, "ALT TARGET MODE", kit.unlockedAltTarget },
			{ Contract.MasteryUtilityVariantMarks, "ALT UTILITY", utilityAllowed },
			{ Contract.MasteryTitleMarks, "MASTERY TITLE", kit.masteryTitleUnlocked },
		}
		for i, line in milestoneLines do
			local unlock = unlocks[i]
			line.Text = `{unlock[1]} MARKS  {unlock[2]}  {if unlock[3] then "UNLOCKED" else "LOCKED"}`
			line.TextColor3 = if unlock[3] then Colors.Active else Colors.TextDim
		end
		variantButtons(targetDefault, targetAlt, kit.targetMode, kit.unlockedAltTarget, blocked)
		variantButtons(utilityDefault, utilityAlt, kit.utilityVariant, utilityAllowed, blocked)
		titleLine.Text = if kit.masteryTitleUnlocked then `TITLE EARNED: {Format.kit(kit.kitId)} MASTER` else ""
		masteryHint.Text = if not kit.unlockedAltTarget then `ALT TARGETING OPENS AT {Contract.MasteryAltTargetMarks} MARKS.`
			elseif not utilityAllowed then `ALT UTILITY OPENS AT {Contract.MasteryUtilityVariantMarks} MARKS.`
			else "TARGET MODE AND UTILITY ARE SET SEPARATELY."
	end

	function render()
		if not alive then
			return
		end
		back.setState(if busy then "Disabled" else "Normal")
		local waiting = pending()
		retryLast.outline.Visible = waiting ~= nil
		retryLast.setState(if busy then "Disabled" else "Primary")
		local snapshot = client:snapshot() :: Snapshot?
		genLabel.Visible = waiting == nil
		genLabel.Text = if snapshot then `GEN {snapshot.generation}  AGE {snapshot.age.currentAge}` else ""
		echoLabel.Text = if snapshot then `{snapshot.bloodlineTree.echoesBalance} ECHOES` else ""
		local shown = status
		statusLine.Text = if shown then shown.text else ""
		statusLine.TextColor3 = if shown then shown.color else Colors.TextDim

		local ready = loaded and snapshot ~= nil
		body.Visible = ready
		notice.Visible = not ready
		reload.outline.Visible = not ready and loadError ~= nil
		for id, button in tabButtons do
			button.outline.Visible = ready
			button.setState(if id == tab then "Selected" elseif busy then "Disabled" else "Normal")
		end
		if not ready or not snapshot then
			local failed = loadError
			notice.Text = if failed and waiting then string.upper(failed) .. " LAST ACTION KEPT."
				elseif failed then string.upper(failed)
				else "ENTERING THE HALL OF ANCESTORS..."
			notice.TextColor3 = if failed then Colors.Hp else Colors.TextDim
			reload.setState(if busy then "Disabled" else "Primary")
			return
		end
		for id, panel in panels do
			panel.Visible = id == tab
		end
		-- No new action while one is unconfirmed or a request is running.
		local blocked = busy or waiting ~= nil
		if tab == "Life" then
			renderLife(snapshot, blocked)
		elseif tab == "Bloodline" then
			renderTree(snapshot, blocked)
		elseif tab == "Heirlooms" then
			renderHeirlooms(snapshot, blocked)
		else
			renderMastery(snapshot, blocked)
		end
	end

	-- Input ----------------------------------------------------------------------------

	for id, button in tabButtons do
		button.button.Activated:Connect(function()
			if busy or id == tab then
				return
			end
			tab = id
			confirmingTorch = false
			render()
		end)
	end

	torchButton.button.Activated:Connect(function()
		local snapshot = current()
		if busy or not snapshot then
			return
		end
		if not snapshot.recoveryLedger.canRetireNow then
			deps.toast(if snapshot.recoveryLedger.ledgerSettled then "This life has ended."
				else "Retiring needs an Act 3 clear and the Safe Hub.")
			return
		end
		confirmingTorch = true
		render()
	end)
	cancelButton.button.Activated:Connect(function()
		if busy then
			return
		end
		confirmingTorch = false
		render()
	end)
	confirmButton.button.Activated:Connect(function()
		local snapshot = current()
		if busy or not snapshot or not confirmingTorch then
			return
		end
		run({ kind = "PassTheTorch", lifeId = snapshot.lifeId, confirmed = true })
	end)
	heirButton.button.Activated:Connect(function()
		if busy or not alive then
			return
		end
		alive = false
		frame:Destroy()
		deps.onClose()
	end)

	for _, row in nodeRows do
		row.press.Activated:Connect(function()
			if busy or row.nodeId == selectedNode then
				return
			end
			selectedNode = row.nodeId
			render()
		end)
	end
	buyButton.button.Activated:Connect(function()
		local snapshot = current()
		local node = if snapshot then findNode(snapshot, selectedNode) else nil
		if busy or not node then
			return
		end
		if not client:pendingAction() and explain(node.legality) then
			return
		end
		run({ kind = "PurchaseBloodlineNode", nodeId = node.nodeId })
	end)

	for i, row in loomRows do
		row.press.Activated:Connect(function()
			local snapshot = current()
			local entry = if snapshot then snapshot.heirlooms.catalog[i] else nil
			if busy or not entry or entry.id == selectedLoom then
				return
			end
			selectedLoom = entry.id
			render()
		end)
	end
	carryButton.button.Activated:Connect(function()
		local snapshot = current()
		local id = selectedLoom
		if busy or not snapshot or not id then
			return
		end
		local view = snapshot.heirlooms
		if not client:pendingAction() then
			if explain(view.legality) then
				return
			end
			if not table.find(view.unlockedIds, id) then
				deps.toast("This heirloom is still locked.")
				return
			end
		end
		local list = table.clone(view.carriedIds)
		local index = table.find(list, id)
		if index then
			table.remove(list, index)
		elseif #list < view.carryLimit then
			table.insert(list, id)
		elseif view.carryLimit == 1 then
			-- One slot: carrying another swaps it.
			list = { id }
		else
			deps.toast(`You can carry {view.carryLimit} heirlooms. Uncarry one first.`)
			return
		end
		run({ kind = "SetCarriedHeirlooms", heirloomIds = list })
	end)
	attuneButton.button.Activated:Connect(function()
		local snapshot = current()
		local id = selectedLoom
		if busy or not snapshot or not id then
			return
		end
		local view = snapshot.heirlooms
		if not client:pendingAction() then
			if explain(view.legality) then
				return
			end
			if not table.find(view.carriedIds, id) then
				deps.toast("Carry this heirloom first, then attune it.")
				return
			end
		end
		run({ kind = "SetAttunedHeirloom", heirloomId = if view.attunedId == id then nil else id })
	end)

	for i, row in kitRows do
		row.press.Activated:Connect(function()
			local snapshot = current()
			local entry = if snapshot then snapshot.mastery[i] else nil
			if busy or not entry or entry.kitId == selectedKit then
				return
			end
			selectedKit = entry.kitId
			render()
		end)
	end
	local function setTarget(value: Contract.MasteryVariant)
		local snapshot = current()
		local kit = if snapshot then findKit(snapshot, selectedKit) else nil
		if busy or not kit or (kit.targetMode == value and not client:pendingAction()) then
			return
		end
		if value == "Alt" and not kit.unlockedAltTarget and not client:pendingAction() then
			deps.toast(`Alt targeting opens at {Contract.MasteryAltTargetMarks} marks.`)
			return
		end
		run({ kind = "SetMasteryTargetMode", kitId = kit.kitId, targetMode = value })
	end
	local function setUtility(value: Contract.MasteryVariant)
		local snapshot = current()
		local kit = if snapshot then findKit(snapshot, selectedKit) else nil
		if busy or not kit or (kit.utilityVariant == value and not client:pendingAction()) then
			return
		end
		if value == "Alt" and kit.marks < Contract.MasteryUtilityVariantMarks and not client:pendingAction() then
			deps.toast(`Alt utility opens at {Contract.MasteryUtilityVariantMarks} marks.`)
			return
		end
		run({ kind = "SetMasteryVariant", kitId = kit.kitId, variant = value })
	end
	targetDefault.button.Activated:Connect(function()
		setTarget("Default")
	end)
	targetAlt.button.Activated:Connect(function()
		setTarget("Alt")
	end)
	utilityDefault.button.Activated:Connect(function()
		setUtility("Default")
	end)
	utilityAlt.button.Activated:Connect(function()
		setUtility("Alt")
	end)

	retryLast.button.Activated:Connect(function()
		retry()
	end)
	reload.button.Activated:Connect(function()
		load()
	end)
	back.button.Activated:Connect(function()
		if busy or not alive then
			return
		end
		alive = false
		frame:Destroy()
		deps.onClose()
	end)

	local self = {} :: Hall
	function self.destroy(_self: Hall)
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

return HallScreen
