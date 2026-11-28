--!strict
-- The Phase 4 Cyberware Clinic, opened from the Hub. Draws over the whole Hub.
--
-- Lists the five body sites with what is installed, the tolerance gauge with
-- the Cyber-Strain threshold, the server's install offers for the selected
-- site, removal, and the Equipped Active Routines selector. Every price,
-- tolerance cost and legality is the server's. Before Act 2 the server blocks
-- the Clinic and the detail panel shows its reason.
--
-- Layout (body px, the body starts at y 16):
--   sites      2..100   five site rows, tolerance gauge, strain
--   detail     104..316 site, offers, remove, routines

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Contract = require(ReplicatedStorage.Shared.Contracts.Phase4EconomyTypes)
local PixelUi = require(script.Parent.Parent.Battle.PixelUi)
local CampaignUi = require(script.Parent.Parent.Campaign.CampaignUi)
local StationShell = require(script.Parent.StationShell)
local Format = require(script.Parent.StationFormat)

type Snapshot = Contract.Snapshot
type Site = Contract.CyberwareSite
type SlotView = Contract.CyberwareSlotView
type Routine = Contract.CyberwareRoutineId

local Colors = PixelUi.Colors
local Palette = CampaignUi.Colors

local DETAIL_X = 104
local DETAIL_W = 212
local OFFER_ROWS = 5
local ROUTINE_W = 42

export type Clinic = {
	destroy: (self: Clinic) -> (),
}

local ClinicScreen = {}

-- Same routines in the same order.
local function sameList(a: { Routine }, b: { Routine }): boolean
	if #a ~= #b then
		return false
	end
	for i, value in a do
		if b[i] ~= value then
			return false
		end
	end
	return true
end

function ClinicScreen.open(parent: Instance, deps: StationShell.Deps): Clinic
	local shell = StationShell.open(parent, deps, {
		name = "Clinic",
		title = "CYBERWARE CLINIC",
		loadingText = "VISITING THE CLINIC...",
		failText = "The Clinic couldn't do that.",
		balances = function(balances: Contract.Balances): string
			return `{balances.salvageShards} SHARD`
		end,
	})
	local body = shell.body

	-- Sites -------------------------------------------------------------------
	PixelUi.label(body, "SitesTitle", 2, 0, 60, 9, "BODY SITES", Palette.Gold)
	local sitesCount = PixelUi.label(body, "SiteCount", 50, 0, 50, 9, "", Colors.TextDim, Enum.TextXAlignment.Right)
	type Row = { outline: Frame, fill: Frame, name: TextLabel, badge: TextLabel, press: TextButton }
	local rows: { Row } = {}
	for i, site in Format.SITE_ORDER do
		local outline, fill = PixelUi.box(body, `Site{i}`, 2, 11 + (i - 1) * 12, 98, 11, Palette.Tile)
		rows[i] = {
			outline = outline,
			fill = fill,
			name = PixelUi.label(fill, "Name", 2, 0, 70, 9, Format.site(site), Colors.Text),
			badge = PixelUi.label(fill, "Badge", 72, 0, 22, 9, "", Palette.Gold, Enum.TextXAlignment.Right),
			press = PixelUi.button(fill, "Press", 0, 0, 96, 9, ""),
		}
	end

	PixelUi.label(body, "TolTitle", 2, 73, 60, 9, "TOLERANCE", Palette.Gold)
	local tolValue = PixelUi.label(body, "TolValue", 50, 73, 50, 9, "", Colors.Text, Enum.TextXAlignment.Right)
	local gaugeOuter, setGauge = PixelUi.bar(body, "Gauge", 2, 83, 98, 7, Colors.Guard, Colors.HpBack)
	-- A 1 px mark at the Cyber-Strain threshold, when the race has one.
	local strainMark = PixelUi.frame(gaugeOuter, "StrainMark", 0, 0, 1, 7, Colors.Hp)
	local strainLine = PixelUi.label(body, "Strain", 2, 92, 98, 9, "", Colors.TextDim)
	local penaltyLine = PixelUi.label(body, "Penalty", 2, 101, 98, 9, "", Colors.Hp)
	local thresholdLine = PixelUi.label(body, "Threshold", 2, 110, 98, 9, "", Colors.TextDim)

	-- Detail ------------------------------------------------------------------
	local detail = PixelUi.frame(body, "Detail", DETAIL_X, 0, DETAIL_W, 162)
	local function line(name: string, y: number, color: Color3?, x: number?, w: number?): TextLabel
		return PixelUi.label(detail, name, x or 0, y, w or DETAIL_W, 9, "", color or Colors.Text)
	end
	local title = PixelUi.label(detail, "Name", 0, 0, 120, 10, "", Palette.Gold)
	local installedLine = line("Installed", 0, Colors.Active, 120, 92)
	installedLine.TextXAlignment = Enum.TextXAlignment.Right
	local routineLine = line("Routine", 10, Colors.TextDim)

	line("OfferHead", 20, Colors.TextDim, 0, 160).Text = "TIER  TOL   COST              ROUTINE"
	type OfferRow = { text: TextLabel, routine: TextLabel, install: CampaignUi.Button }
	local offerRows: { OfferRow } = {}
	for i = 1, OFFER_ROWS do
		local y = 29 + (i - 1) * 11
		offerRows[i] = {
			text = line(`Offer{i}`, y, Colors.Text, 0, 118),
			routine = line(`OfferRoutine{i}`, y, Colors.Active, 118, 50),
			install = CampaignUi.button(detail, `Install{i}`, 168, y, 44, 10, "INSTALL"),
		}
	end
	local removeButton = CampaignUi.button(detail, "Remove", 0, 85, 80, 12, "REMOVE")
	local removeHint = line("RemoveHint", 86, Colors.TextDim, 84, 128)

	local routineTitle = line("RoutineTitle", 100, Palette.Gold)
	type Toggle = { id: Routine, button: CampaignUi.Button }
	local toggles: { Toggle } = {}
	for i, id in Format.ROUTINE_ORDER do
		toggles[i] = {
			id = id,
			button = CampaignUi.button(detail, `Routine{i}`, (i - 1) * (ROUTINE_W + 0.5) // 1, 110, ROUTINE_W, 12, Format.routineShort(id)),
		}
	end
	local draftLine = line("Draft", 124, Colors.Text)
	local saveButton = CampaignUi.button(detail, "SaveRoutines", 0, 134, 104, 13, "EQUIP ROUTINES")
	local resetButton = CampaignUi.button(detail, "ResetRoutines", 108, 134, 104, 13, "UNDO CHANGES")
	local statusLine = line("Status", 150, Colors.TextDim)

	-- Act 2 lock, drawn over the detail controls.
	local lock = PixelUi.frame(detail, "Lock", 0, 20, DETAIL_W, 128, Palette.Backdrop)
	lock.ZIndex = 2
	PixelUi.label(lock, "Title", 0, 30, DETAIL_W, 10, "CLINIC LOCKED", Colors.Hp, Enum.TextXAlignment.Center)
	local lockReason = PixelUi.label(lock, "Reason", 0, 42, DETAIL_W, 10, "", Colors.Text, Enum.TextXAlignment.Center)
	PixelUi.label(lock, "Hint", 0, 54, DETAIL_W, 10, "IMPLANTS AND ROUTINES OPEN THEN.", Colors.TextDim, Enum.TextXAlignment.Center)

	local selected: Site = Format.SITE_ORDER[1]
	local confirmRemove: Site? = nil
	local confirmReplace: { site: Site, tier: number }? = nil
	-- The routines the player is choosing, before EQUIP ROUTINES. Reset when the
	-- server's list changes.
	local draft: { Routine } = {}
	local draftBase: { Routine }? = nil

	local function slotFor(snapshot: Snapshot, site: Site): SlotView?
		for _, slot in snapshot.clinic.sites do
			if slot.site == site then
				return slot
			end
		end
		return nil
	end

	-- Routines granted by an installed implant.
	local function installedRoutines(snapshot: Snapshot): { [Routine]: Site }
		local found: { [Routine]: Site } = {}
		for _, slot in snapshot.clinic.sites do
			local implant = slot.installed
			if implant and implant.routineId then
				found[implant.routineId] = slot.site
			end
		end
		return found
	end

	local function syncDraft(snapshot: Snapshot)
		local equipped = snapshot.clinic.equippedRoutines
		local base = draftBase
		if base == nil or not sameList(base, equipped) then
			draftBase = table.clone(equipped)
			draft = table.clone(equipped)
		end
	end

	local function render()
		local snapshot = shell.snapshot()
		if not snapshot then
			return
		end
		syncDraft(snapshot)
		local clinic = snapshot.clinic
		-- No new Clinic action while an earlier one is unconfirmed.
		local busy = shell.busy() or shell.pending() ~= nil
		local open = clinic.legality.canUse

		-- Site list.
		local used = 0
		for i, site in Format.SITE_ORDER do
			local row = rows[i]
			local slot = slotFor(snapshot, site)
			local implant = if slot then slot.installed else nil
			if implant then
				used += 1
			end
			row.badge.Text = if implant then `T{implant.tier}` else "-"
			row.badge.TextColor3 = if implant then Palette.Gold else Colors.TextDim
			row.name.TextColor3 = if open then Colors.Text else Colors.TextDim
			local isSelected = site == selected
			row.outline.BackgroundColor3 = if isSelected then Palette.Gold else Colors.Ink
			row.fill.BackgroundColor3 = if isSelected then Colors.ButtonHover else Palette.Tile
		end

		-- Tolerance and Cyber-Strain.
		local tol = clinic.tolerance
		sitesCount.Text = `{used}/{tol.maxSites} SITES`
		tolValue.Text = `{tol.usedTolerance}/{tol.maxTolerance}`
		local scale = math.max(tol.maxTolerance, tol.strainThreshold or 0, 1)
		setGauge(tol.usedTolerance / scale)
		local threshold = tol.strainThreshold
		strainMark.Visible = threshold ~= nil
		if threshold then
			strainMark.Position = UDim2.fromOffset(math.clamp(math.round(98 * threshold / scale), 1, 96), 0)
		end
		if tol.cyberStrainActive then
			strainLine.Text = "CYBER-STRAIN ACTIVE"
			strainLine.TextColor3 = Colors.Hp
			penaltyLine.Text = `-{tol.controlResistPenaltyPp}PP CTRL RES +{tol.extraAgingYears} YR`
		else
			strainLine.Text = if tol.maxSites == 0 then "NO IMPLANT TOLERANCE" else "NO CYBER-STRAIN"
			strainLine.TextColor3 = if tol.maxSites == 0 then Colors.Hp else Colors.Active
			penaltyLine.Text = ""
		end
		thresholdLine.Text = if threshold then `STRAIN AT {threshold}` else ""

		-- Selected site.
		local slot = slotFor(snapshot, selected)
		local implant = if slot then slot.installed else nil
		title.Text = Format.site(selected)
		installedLine.Text = if implant then `INSTALLED T{implant.tier}` else "EMPTY"
		installedLine.TextColor3 = if implant then Colors.Active else Colors.TextDim
		routineLine.Text = if implant and implant.routineId then `ROUTINE {Format.routine(implant.routineId)}`
			elseif implant then "NO ACTIVE ROUTINE AT THIS TIER"
			else "INSTALL AN IMPLANT HERE"

		local offers = if slot then slot.offers else {}
		for i, row in offerRows do
			local offer = offers[i]
			row.text.Visible = offer ~= nil
			row.routine.Visible = offer ~= nil
			row.install.outline.Visible = offer ~= nil
			if offer then
				local current = implant ~= nil and implant.tier == offer.tier
				row.text.Text = `T{offer.tier}    {offer.toleranceCost}    {Format.cost(offer.cost)}`
				row.text.TextColor3 = if offer.legality.canUse then Colors.Text else Colors.TextDim
				row.routine.Text = if offer.routineId then Format.routineShort(offer.routineId) else "-"
				local pending = confirmReplace
				local confirming = pending ~= nil and pending.site == selected and pending.tier == offer.tier
				row.install.setText(if current then "IN" elseif confirming then "SURE?" elseif implant then "SWAP" else "INSTALL")
				if busy or not offer.legality.canUse then
					row.install.setState("Disabled")
				else
					row.install.setState(if confirming then "Primary" else "Normal")
				end
			end
		end

		local removing = confirmRemove == selected
		removeButton.setText(if removing then "CONFIRM" else "REMOVE")
		removeButton.setState(if busy or not open or not implant then "Disabled" elseif removing then "Primary" else "Normal")
		removeHint.Text = if removing then "NO REFUND. PRESS AGAIN." elseif confirmReplace and confirmReplace.site == selected
			then "SWAPPING REPLACES THE IMPLANT."
			else ""
		removeHint.TextColor3 = Colors.Hp

		-- Equipped Active Routines.
		local available = installedRoutines(snapshot)
		local limit = clinic.activeRoutineLimit
		routineTitle.Text = `ACTIVE ROUTINES  {#draft}/{limit} EQUIPPED`
		for _, toggle in toggles do
			local chosen = table.find(draft, toggle.id) ~= nil
			if busy or not open or not available[toggle.id] then
				toggle.button.setState(if chosen then "Selected" else "Disabled")
			else
				toggle.button.setState(if chosen then "Selected" else "Normal")
			end
		end
		draftLine.Text = Format.routineList(draft)
		local changed = draftBase ~= nil and not sameList(draftBase, draft)
		saveButton.setState(if busy or not open or not changed then "Disabled" else "Primary")
		resetButton.setState(if busy or not changed then "Disabled" else "Normal")

		local shown = shell.status()
		statusLine.Text = if shown then shown.text else ""
		statusLine.TextColor3 = if shown then shown.color else Colors.TextDim

		lock.Visible = not open
		lockReason.Text = string.upper(CampaignUi.reason(clinic.legality))
	end
	shell.setRender(render)

	local function clearConfirm()
		confirmRemove = nil
		confirmReplace = nil
	end

	-- Input ------------------------------------------------------------------

	for i, row in rows do
		row.press.Activated:Connect(function()
			local site = Format.SITE_ORDER[i]
			if shell.busy() or site == selected then
				return
			end
			selected = site
			clearConfirm()
			shell.setStatus(nil)
			shell.render()
		end)
	end

	for i, row in offerRows do
		row.install.button.Activated:Connect(function()
			local snapshot = shell.snapshot()
			if shell.busy() or not snapshot then
				return
			end
			local slot = slotFor(snapshot, selected)
			local offer = if slot then slot.offers[i] else nil
			if not slot or not offer or shell.explain(offer.legality) then
				return
			end
			-- Replacing an implant takes a second press.
			local replacing = slot.installed ~= nil
			local pending = confirmReplace
			if replacing and not (pending and pending.site == selected and pending.tier == offer.tier) then
				confirmRemove = nil
				confirmReplace = { site = selected, tier = offer.tier }
				shell.render()
				return
			end
			clearConfirm()
			shell.run({ kind = "InstallCyberware", site = selected, tier = offer.tier })
		end)
	end

	removeButton.button.Activated:Connect(function()
		local snapshot = shell.snapshot()
		if shell.busy() or not snapshot then
			return
		end
		if shell.explain(snapshot.clinic.legality) then
			return
		end
		local slot = slotFor(snapshot, selected)
		if not slot or not slot.installed then
			deps.toast("This site is empty.")
			return
		end
		if confirmRemove ~= selected then
			confirmReplace = nil
			confirmRemove = selected
			shell.render()
			return
		end
		clearConfirm()
		shell.run({ kind = "RemoveCyberware", site = selected })
	end)

	for _, toggle in toggles do
		toggle.button.button.Activated:Connect(function()
			local snapshot = shell.snapshot()
			if shell.busy() or not snapshot then
				return
			end
			if shell.explain(snapshot.clinic.legality) then
				return
			end
			local index = table.find(draft, toggle.id)
			if index then
				table.remove(draft, index)
			elseif not installedRoutines(snapshot)[toggle.id] then
				deps.toast(`Install a T3+ implant that grants {Format.routine(toggle.id)} first.`)
				return
			elseif #draft >= snapshot.clinic.activeRoutineLimit then
				deps.toast(`Only {snapshot.clinic.activeRoutineLimit} active routines can be equipped.`)
				return
			else
				table.insert(draft, toggle.id)
			end
			shell.render()
		end)
	end

	saveButton.button.Activated:Connect(function()
		local snapshot = shell.snapshot()
		if shell.busy() or not snapshot or shell.explain(snapshot.clinic.legality) then
			return
		end
		clearConfirm()
		shell.run({ kind = "SetEquippedRoutines", routineIds = table.clone(draft) })
	end)

	resetButton.button.Activated:Connect(function()
		local base = draftBase
		if shell.busy() or not base then
			return
		end
		draft = table.clone(base)
		shell.render()
	end)

	local self = {} :: Clinic
	function self.destroy(_self: Clinic)
		shell.destroy()
	end

	shell.render()
	task.spawn(shell.load)
	return self
end

return ClinicScreen
