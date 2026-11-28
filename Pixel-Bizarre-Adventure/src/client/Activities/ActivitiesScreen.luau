--!strict
-- Activities, opened from the Hub. Draws over the whole Hub.
--
-- Two tabs over one ActivityRemotes snapshot:
--   AUTO-BATTLE  the five Acts (unlocked once cleared by hand), the active run,
--                the per-tick reward preview, the next 5-minute tick, ticks
--                waiting to be claimed, the last payout, and START / CLAIM /
--                STOP by the server's legality.
--   EXPEDITIONS  tickets and capacity, one mission per cleared Act, the
--                4-hour duration, the active mission with time remaining and
--                its reward, and DISPATCH / CLAIM by the server's legality.
--
-- Every amount, timer and legality is the server's. Countdowns run from the
-- snapshot's serverTimeUtc, and the screen reloads once when a mission
-- returns or a tick is due, so the server's numbers replace the estimate.
-- Requests go through an ActionClient: an unconfirmed action shows RETRY LAST
-- ACTION in the top bar and blocks new actions until it settles. A retry
-- returns the committed receipt, so nothing pays out twice.
--
-- Layout (native px):
--   top bar   0..14     title, tickets, RETRY LAST ACTION
--   tabs      16..28
--   body      30..156   the open tab
--   bottom    158..178  BACK TO HUB, status line

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Contract = require(ReplicatedStorage.Shared.Contracts.ActivityTypes)
local CombatTypes = require(ReplicatedStorage.Shared.Contracts.CombatTypes)
local PixelUi = require(script.Parent.Parent.Battle.PixelUi)
local CampaignUi = require(script.Parent.Parent.Campaign.CampaignUi)
local ActionClient = require(script.Parent.Parent.Net.ActionClient)
local Format = require(script.Parent.ActivityFormat)

type Snapshot = Contract.Snapshot
type Legality = CombatTypes.ActionLegality

local Colors = PixelUi.Colors
local Palette = CampaignUi.Colors

local BODY_Y = 30
local BODY_H = 126
local ACTS = 5
local TAB_ORDER = { "Auto", "Expedition" }
local TAB_LABEL: { [string]: string } = { Auto = "AUTO-BATTLE", Expedition = "EXPEDITIONS" }
local RECEIPT_KINDS = {
	AutoBattleStarted = true,
	AutoBattleClaimed = true,
	AutoBattleStopped = true,
	ExpeditionDispatched = true,
	ExpeditionClaimed = true,
}
-- Seconds past a server boundary before reloading, so the server's own
-- scheduler has settled the tick first.
local TICK_SETTLE_SECONDS = 3

export type Deps = {
	client: ActionClient.Client,
	toast: (message: string) -> (),
	-- Called once when the player leaves. The Hub refreshes Campaign there,
	-- since payouts change the Yen balance.
	onClose: () -> (),
	-- Tests pass a fake clock. Defaults to os.clock.
	clock: (() -> number)?,
	-- Tests drive the countdown by hand. Defaults to a one-second loop.
	autoTick: boolean?,
}

export type Activities = {
	destroy: (self: Activities) -> (),
	-- Redraws the countdowns and reloads at a boundary. The screen calls this
	-- every second on its own unless autoTick is false.
	tick: (self: Activities) -> (),
}

local ActivitiesScreen = {}

local function wrapped(label: TextLabel): TextLabel
	label.TextWrapped = true
	label.TextYAlignment = Enum.TextYAlignment.Top
	return label
end

local function actView(snapshot: Snapshot, act: number): Contract.AutoBattleActView?
	for _, view in snapshot.autoBattle.unlockedActs do
		if view.act == act then
			return view
		end
	end
	return nil
end

function ActivitiesScreen.open(parent: Instance, deps: Deps): Activities
	local client = deps.client
	local clock = deps.clock or os.clock
	local frame = PixelUi.frame(parent, "Activities", 0, 0, 320, 180, Palette.Backdrop)
	frame.Active = true
	frame.ZIndex = 5

	-- Top bar -------------------------------------------------------------------
	local bar = PixelUi.frame(frame, "TopBar", 0, 0, 320, 14, Palette.PurpleDark)
	PixelUi.frame(bar, "Edge", 0, 13, 320, 1, Palette.Purple)
	PixelUi.label(bar, "Title", 4, 2, 110, 10, "ACTIVITIES", Palette.Gold)
	local ticketLabel = PixelUi.label(bar, "Tickets", 200, 2, 116, 10, "", Palette.Gold, Enum.TextXAlignment.Right)
	local retryLast = CampaignUi.button(bar, "RetryLast", 132, 1, 110, 12, "RETRY LAST ACTION")
	retryLast.outline.ZIndex = 2
	retryLast.outline.Visible = false

	-- Tabs ----------------------------------------------------------------------
	local tabButtons: { [string]: CampaignUi.Button } = {}
	for i, id in TAB_ORDER do
		tabButtons[id] = CampaignUi.button(frame, `{id}Tab`, 4 + (i - 1) * 158, 16, 154, 12, TAB_LABEL[id])
	end

	local body = PixelUi.frame(frame, "Body", 0, BODY_Y, 320, BODY_H)
	local notice = PixelUi.label(frame, "Notice", 0, 70, 320, 10, "", Colors.TextDim, Enum.TextXAlignment.Center)
	local reload = CampaignUi.button(frame, "Reload", 130, 86, 60, 14, "RETRY")
	local back = CampaignUi.button(frame, "Back", 4, 159, 94, 18, "< BACK TO HUB")
	local statusLine = PixelUi.label(frame, "Status", 102, 165, 214, 9, "", Colors.TextDim)

	type ActRow = { outline: Frame, fill: Frame, name: TextLabel, state: TextLabel, press: TextButton }
	local function actRows(panel: Frame, y0: number, label: (number) -> string): { ActRow }
		local rows: { ActRow } = {}
		for act = 1, ACTS do
			local outline, fill = PixelUi.box(panel, `Act{act}`, 2, y0 + (act - 1) * 12, 156, 11, Palette.Tile)
			rows[act] = {
				outline = outline,
				fill = fill,
				name = PixelUi.label(fill, "Name", 3, 1, 100, 8, label(act), Colors.Text),
				state = PixelUi.label(fill, "State", 100, 1, 50, 8, "", Colors.TextDim, Enum.TextXAlignment.Right),
				press = PixelUi.button(fill, "Press", 0, 0, 154, 9, ""),
			}
		end
		return rows
	end

	-- AUTO-BATTLE ----------------------------------------------------------------
	local auto = PixelUi.frame(body, "Auto", 0, 0, 320, BODY_H)
	PixelUi.label(auto, "ActsTitle", 4, 0, 152, 9, "ACTS", Palette.Gold)
	local autoRows = actRows(auto, 10, function(act)
		return `ACT {act}`
	end)
	local autoHint = wrapped(PixelUi.label(auto, "Hint", 4, 72, 152, 18, "", Colors.TextDim))
	wrapped(PixelUi.label(auto, "Rules", 4, 96, 152, 28, "EARNS YEN, SHARDS AND MATERIALS ONLY. NO XP, MARKS OR ECHOES.", Colors.TextDim))
	PixelUi.frame(auto, "Rule", 160, 0, 1, BODY_H, Palette.Purple)
	local autoTitle = PixelUi.label(auto, "ActTitle", 166, 0, 150, 10, "", Palette.Gold)
	local autoState = PixelUi.label(auto, "RunState", 166, 11, 150, 9, "", Colors.Text)
	local perTickTitle = PixelUi.label(auto, "PerTickTitle", 166, 22, 150, 9, "", Colors.TextDim)
	local perTick = PixelUi.label(auto, "PerTick", 166, 31, 150, 9, "", Colors.Text)
	local gearLine = PixelUi.label(auto, "Gear", 166, 40, 150, 9, "", Colors.TextDim)
	local nextTick = PixelUi.label(auto, "NextTick", 166, 51, 150, 9, "", Colors.Text)
	local pendingLine = PixelUi.label(auto, "PendingTicks", 166, 60, 150, 9, "", Colors.TextDim)
	local lastClaim = wrapped(PixelUi.label(auto, "LastClaim", 166, 71, 150, 27, "", Colors.TextDim))
	local startButton = CampaignUi.button(auto, "Start", 166, 100, 150, 16, "START AUTO-BATTLE")
	local claimButton = CampaignUi.button(auto, "Claim", 166, 100, 73, 16, "CLAIM")
	local stopButton = CampaignUi.button(auto, "Stop", 243, 100, 73, 16, "STOP")

	-- EXPEDITIONS ----------------------------------------------------------------
	local expedition = PixelUi.frame(body, "Expedition", 0, 0, 320, BODY_H)
	local ticketTitle = PixelUi.label(expedition, "TicketTitle", 4, 0, 100, 9, "", Palette.Gold)
	local ticketPips: { Frame } = {}
	for i = 1, Contract.QuartermasterExpeditionMaxTickets do
		ticketPips[i] = PixelUi.frame(expedition, `Ticket{i}`, 104 + (i - 1) * 18, 2, 16, 5, Colors.Active)
	end
	PixelUi.label(expedition, "MissionsTitle", 4, 11, 152, 9, "MISSIONS", Palette.Gold)
	local missionRows = actRows(expedition, 21, function(act)
		return `ACT {act} EXPEDITION`
	end)
	local missionHint = wrapped(PixelUi.label(expedition, "Hint", 4, 83, 152, 18, "", Colors.TextDim))
	wrapped(PixelUi.label(expedition, "Rules", 4, 103, 152, 22, "ONE MISSION AT A TIME. NO XP, MARKS, ECHOES OR GEAR.", Colors.TextDim))
	PixelUi.frame(expedition, "Rule", 160, 0, 1, BODY_H, Palette.Purple)
	local missionTitle = PixelUi.label(expedition, "MissionTitle", 166, 0, 150, 10, "", Palette.Gold)
	local missionState = PixelUi.label(expedition, "MissionState", 166, 11, 150, 9, "", Colors.Text)
	local missionCost = PixelUi.label(expedition, "Cost", 166, 22, 150, 9, "", Colors.TextDim)
	local missionTimer = PixelUi.label(expedition, "Timer", 166, 33, 150, 9, "", Colors.Text)
	local barBack = PixelUi.frame(expedition, "Progress", 166, 43, 150, 5, Colors.HpBack)
	local barFill = PixelUi.frame(barBack, "Fill", 0, 0, 0, 5, Palette.Gold)
	PixelUi.label(expedition, "RewardTitle", 166, 52, 150, 9, "REWARD", Palette.Gold)
	local rewardLine = wrapped(PixelUi.label(expedition, "Reward", 166, 61, 150, 36, "", Colors.Text))
	local dispatchButton = CampaignUi.button(expedition, "Dispatch", 166, 100, 150, 16, "DISPATCH")
	local missionClaim = CampaignUi.button(expedition, "ClaimMission", 166, 100, 150, 16, "CLAIM REWARD")

	local panels: { [string]: Frame } = { Auto = auto, Expedition = expedition }

	-- State -----------------------------------------------------------------------
	local alive = true
	local busy = false
	local loaded = false
	local loadError: string? = nil
	local tab = "Auto"
	local status: { text: string, color: Color3 }? = nil
	local selectedAuto: number? = nil
	local selectedMission: number? = nil
	-- The snapshot the countdowns run from (by session, revision and server
	-- time), and when this client first drew it.
	local seen: string? = nil
	local seenAt = 0
	-- The server boundary already reloaded for, so each is reloaded once.
	local reloadedFor: string? = nil
	local render: () -> ()

	local function setStatus(text: string?, color: Color3?)
		status = if text then { text = text, color = color or Colors.TextDim } else nil
	end

	local function current(): Snapshot?
		return if loaded then client:snapshot() :: Snapshot? else nil
	end

	local function pending(): string?
		local action = client:pendingAction()
		return if action then Format.action(action :: any) else nil
	end

	-- The server's clock now, estimated from the latest snapshot.
	local function serverNow(snapshot: Snapshot): number
		local key = `{snapshot.sessionId}:{snapshot.revision}:{snapshot.serverTimeUtc}`
		if key ~= seen then
			seen = key
			seenAt = clock()
		end
		return snapshot.serverTimeUtc + (clock() - seenAt)
	end

	local function explain(legality: Legality): boolean
		if legality.canUse then
			return false
		end
		deps.toast(CampaignUi.reason(legality))
		return true
	end

	local function takeRecovered()
		local receipt = client:takeRecovered(RECEIPT_KINDS)
		if receipt then
			setStatus(Format.receipt(receipt :: any), Colors.Active)
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
			loadError = "Couldn't reach Activities."
		end
		local receipt = result.receipt
		if result.ok and receipt then
			local text = Format.receipt(receipt :: any)
			setStatus(text, Colors.Active)
			deps.toast("Recovered: " .. text)
			client:takeRecovered(RECEIPT_KINDS)
		elseif result.uncertain then
			setStatus("STILL UNCONFIRMED. RETRY AGAIN.", Colors.Hp)
			deps.toast(result.message or "Still unconfirmed.")
		else
			local message = result.message or "Activities refused it."
			setStatus(string.upper("Last action not applied: " .. message), Colors.Hp)
			deps.toast(message)
		end
		render()
	end

	local function run(action: Contract.Action)
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
		local result = client:perform(action :: any)
		if not alive then
			return
		end
		busy = false
		local receipt = result.receipt :: Contract.Receipt?
		if result.ok and receipt then
			local text = Format.receipt(receipt)
			setStatus(text, Colors.Active)
			deps.toast(text)
		else
			local waiting = pending()
			local message = result.message or "Activities refused it."
			if result.uncertain and waiting then
				message = `UNCONFIRMED: {waiting}.`
			elseif result.code == "StaleRevision" then
				message = "Activities changed. Check and try again."
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
			loadError = result.message or "Activities are closed."
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

	-- A reload at a server boundary. Keeps the current view if it fails.
	local function quietReload()
		if busy or not alive or client:pendingAction() then
			return
		end
		busy = true
		local result = client:refresh()
		if not alive then
			return
		end
		busy = false
		if result.ok then
			loaded = true
		end
		render()
	end

	-- Drawing ------------------------------------------------------------------------

	local function rowState(row: ActRow, selected: boolean, unlocked: boolean, state: string, color: Color3)
		row.fill.BackgroundColor3 = if selected then Colors.ButtonHover else Palette.Tile
		row.outline.BackgroundColor3 = if selected then Palette.Gold else Colors.Ink
		row.name.TextColor3 = if unlocked then Colors.Text else Colors.TextDim
		row.state.Text = state
		row.state.TextColor3 = color
	end

	local function renderAutoTimers(snapshot: Snapshot)
		local view = snapshot.autoBattle
		local paid = view.lastClaimedAtUtc
		if view.runId and paid then
			local due = paid + view.tickSeconds * (view.pendingTicks + 1)
			nextTick.Text = `NEXT TICK IN {Format.clock(due - serverNow(snapshot))}`
		else
			nextTick.Text = ""
		end
	end

	local function renderAuto(snapshot: Snapshot, blocked: boolean)
		local view = snapshot.autoBattle
		local running = view.act
		if running then
			selectedAuto = running
		elseif selectedAuto == nil then
			local first = view.unlockedActs[1]
			selectedAuto = if first then first.act else 1
		end
		local act = selectedAuto :: number
		local unlocked = actView(snapshot, act)
		for i, row in autoRows do
			local open = actView(snapshot, i) ~= nil
			rowState(row, i == act, open,
				if running == i then "RUNNING" elseif open then "" else "LOCKED",
				if running == i then Colors.Active else Colors.TextDim)
		end
		autoHint.Text = if #view.unlockedActs == 0 then "CLEAR AN ACT BY HAND TO UNLOCK AUTO-BATTLE."
			elseif #view.unlockedActs < ACTS then "CLEAR MORE ACTS BY HAND TO UNLOCK THEM."
			else ""

		autoTitle.Text = `ACT {act} AUTO-BATTLE`
		local isRunning = running == act and view.runId ~= nil
		autoState.Text = if isRunning then "RUNNING" elseif unlocked then "NOT RUNNING" else "LOCKED"
		autoState.TextColor3 = if isRunning then Colors.Active elseif unlocked then Colors.Text else Colors.TextDim
		if unlocked then
			perTickTitle.Text = `PER {Format.duration(view.tickSeconds)} TICK`
			perTick.Text = Format.bundle(unlocked.rewardPreview)
			local drops = unlocked.rewardPreview.maxStandardGearDrops
			gearLine.Text = if drops > 0 then `UP TO {drops} GEAR DROP{if drops == 1 then "" else "S"}` else "NO GEAR DROPS"
		else
			perTickTitle.Text = ""
			perTick.Text = `CLEAR ACT {act} BY HAND FIRST.`
			gearLine.Text = ""
		end
		if isRunning then
			renderAutoTimers(snapshot)
			pendingLine.Text = if view.pendingTicks > 0
				then `{view.pendingTicks} TICK{if view.pendingTicks == 1 then "" else "S"} READY TO CLAIM`
				else "TICKS PAY OUT AUTOMATICALLY."
			pendingLine.TextColor3 = if view.pendingTicks > 0 then Colors.Active else Colors.TextDim
		else
			nextTick.Text = ""
			pendingLine.Text = ""
		end
		local last = view.lastClaim
		lastClaim.Text = if last
			then `LAST PAYOUT, ACT {last.act}: {last.ticksClaimed} TICK{if last.ticksClaimed == 1 then "" else "S"}  {Format.bundle(last.rewards)}`
			else "NO PAYOUTS YET."

		startButton.outline.Visible = not isRunning
		claimButton.outline.Visible = isRunning
		stopButton.outline.Visible = isRunning
		local legal = view.legality
		startButton.setState(if blocked or not unlocked or not legal.start.canUse then "Disabled" else "Primary")
		claimButton.setState(if blocked or not legal.claim.canUse then "Disabled" else "Primary")
		stopButton.setState(if blocked or not legal.stop.canUse then "Disabled" else "Normal")
	end

	local function renderMissionTimers(snapshot: Snapshot)
		local view = snapshot.expedition
		local started, completes = view.startedAtUtc, view.completesAtUtc
		if view.missionId and started and completes then
			local now = serverNow(snapshot)
			local left = completes - now
			missionTimer.Text = if view.claimable or left <= 0 then "RETURNED" else `RETURNS IN {Format.clock(left)}`
			local span = math.max(1, completes - started)
			local fraction = if view.claimable then 1 else math.clamp((now - started) / span, 0, 1)
			barFill.Size = UDim2.fromOffset(math.floor(150 * fraction), 5)
		else
			missionTimer.Text = ""
			barFill.Size = UDim2.fromOffset(0, 5)
		end
	end

	local function renderExpedition(snapshot: Snapshot, blocked: boolean)
		local view = snapshot.expedition
		local active = view.act
		if active then
			selectedMission = active
		elseif selectedMission == nil then
			local first = snapshot.autoBattle.unlockedActs[1]
			selectedMission = if first then first.act else 1
		end
		local act = selectedMission :: number
		-- Missions follow the Acts cleared by hand, the same list Auto-Battle uses.
		local unlocked = actView(snapshot, act) ~= nil
		ticketTitle.Text = `TICKETS {view.tickets}/{view.maxTickets}`
		for i, pip in ticketPips do
			pip.Visible = i <= view.maxTickets
			pip.BackgroundColor3 = if i <= view.tickets then Colors.Active else Colors.HpBack
		end
		for i, row in missionRows do
			local open = actView(snapshot, i) ~= nil
			local state = if active == i then (if view.claimable then "READY" else "UNDERWAY")
				elseif open then "" else "LOCKED"
			rowState(row, i == act, open, state,
				if active == i and view.claimable then Palette.Gold elseif active == i then Colors.Active else Colors.TextDim)
		end
		missionHint.Text = if view.tickets == 0 and not active then "NO TICKETS. CLEARS BY HAND EARN THEM."
			elseif #snapshot.autoBattle.unlockedActs == 0 then "CLEAR AN ACT BY HAND TO UNLOCK MISSIONS."
			else ""

		missionTitle.Text = `ACT {act} EXPEDITION`
		missionCost.Text = `TAKES {Format.duration(view.durationSeconds)}. COSTS 1 TICKET.`
		local isActive = active == act and view.missionId ~= nil
		if isActive then
			missionState.Text = if view.claimable then "RETURNED. READY TO CLAIM." else "UNDERWAY"
			missionState.TextColor3 = if view.claimable then Palette.Gold else Colors.Active
			local reward = view.rewardPreview
			rewardLine.Text = if reward then Format.bundle(reward) else "SHOWN BY THE SERVER."
			rewardLine.TextColor3 = Colors.Text
		else
			missionState.Text = if active then `ACT {active} MISSION IS OUT.`
				elseif not unlocked then "LOCKED"
				elseif view.tickets == 0 then "NO TICKET"
				else "READY TO DISPATCH"
			missionState.TextColor3 = if unlocked and view.tickets > 0 and not active then Colors.Text else Colors.TextDim
			rewardLine.Text = if unlocked then "ONE BUNDLE OF YEN, SHARDS AND MATERIALS. THE SERVER SETS IT ON DISPATCH."
				else `CLEAR ACT {act} BY HAND FIRST.`
			rewardLine.TextColor3 = Colors.TextDim
		end
		barBack.Visible = isActive
		if isActive then
			renderMissionTimers(snapshot)
		else
			missionTimer.Text = ""
		end
		dispatchButton.outline.Visible = not isActive
		missionClaim.outline.Visible = isActive
		local legal = view.legality
		dispatchButton.setState(if blocked or not unlocked or not legal.dispatch.canUse then "Disabled" else "Primary")
		missionClaim.setState(if blocked or not legal.claim.canUse then "Disabled" else "Primary")
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
		ticketLabel.Visible = waiting == nil
		ticketLabel.Text = if snapshot then `{snapshot.expedition.tickets}/{snapshot.expedition.maxTickets} TICKETS` else ""
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
				else "CHECKING ACTIVITIES..."
			notice.TextColor3 = if failed then Colors.Hp else Colors.TextDim
			reload.setState(if busy then "Disabled" else "Primary")
			return
		end
		for id, panel in panels do
			panel.Visible = id == tab
		end
		-- No new action while one is unconfirmed or a request is running.
		local blocked = busy or waiting ~= nil
		if tab == "Auto" then
			renderAuto(snapshot, blocked)
		else
			renderExpedition(snapshot, blocked)
		end
	end

	-- Countdown: redraw the timers, and reload once a server boundary passes.
	local function tick()
		local snapshot = current()
		if not alive or not snapshot then
			return
		end
		if tab == "Auto" and snapshot.autoBattle.runId then
			renderAutoTimers(snapshot)
		elseif tab == "Expedition" and snapshot.expedition.missionId then
			renderMissionTimers(snapshot)
		end
		if busy or client:pendingAction() then
			return
		end
		local now = serverNow(snapshot)
		local boundary: string? = nil
		local mission = snapshot.expedition
		if mission.missionId and not mission.claimable and mission.completesAtUtc and now >= mission.completesAtUtc + 1 then
			boundary = `mission:{mission.missionId}`
		end
		local view = snapshot.autoBattle
		local paid = view.lastClaimedAtUtc
		if not boundary and view.runId and paid then
			local due = paid + view.tickSeconds * (view.pendingTicks + 1)
			if now >= due + TICK_SETTLE_SECONDS then
				boundary = `tick:{view.runId}:{due}`
			end
		end
		if boundary and boundary ~= reloadedFor then
			reloadedFor = boundary
			quietReload()
		end
	end

	-- Input ----------------------------------------------------------------------------

	for id, button in tabButtons do
		button.button.Activated:Connect(function()
			if busy or id == tab then
				return
			end
			tab = id
			render()
		end)
	end
	for act, row in autoRows do
		row.press.Activated:Connect(function()
			local snapshot = current()
			if busy or not snapshot or act == selectedAuto then
				return
			end
			if snapshot.autoBattle.act then
				deps.toast("Stop the current Auto-Battle to pick another Act.")
				return
			end
			selectedAuto = act
			render()
		end)
	end
	for act, row in missionRows do
		row.press.Activated:Connect(function()
			local snapshot = current()
			if busy or not snapshot or act == selectedMission then
				return
			end
			if snapshot.expedition.act then
				deps.toast("Claim the current expedition first.")
				return
			end
			selectedMission = act
			render()
		end)
	end

	startButton.button.Activated:Connect(function()
		local snapshot = current()
		local act = selectedAuto
		if busy or not snapshot or not act then
			return
		end
		if not client:pendingAction() then
			if not actView(snapshot, act) then
				deps.toast(`Clear Act {act} by hand first.`)
				return
			end
			if explain(snapshot.autoBattle.legality.start) then
				return
			end
		end
		run({ kind = "StartAutoBattle", act = act })
	end)
	claimButton.button.Activated:Connect(function()
		local snapshot = current()
		local runId = if snapshot then snapshot.autoBattle.runId else nil
		if busy or not snapshot or not runId then
			return
		end
		if not client:pendingAction() and explain(snapshot.autoBattle.legality.claim) then
			return
		end
		run({ kind = "ClaimAutoBattle", runId = runId })
	end)
	stopButton.button.Activated:Connect(function()
		local snapshot = current()
		local runId = if snapshot then snapshot.autoBattle.runId else nil
		if busy or not snapshot or not runId then
			return
		end
		if not client:pendingAction() and explain(snapshot.autoBattle.legality.stop) then
			return
		end
		run({ kind = "StopAutoBattle", runId = runId })
	end)
	dispatchButton.button.Activated:Connect(function()
		local snapshot = current()
		local act = selectedMission
		if busy or not snapshot or not act then
			return
		end
		if not client:pendingAction() then
			if not actView(snapshot, act) then
				deps.toast(`Clear Act {act} by hand first.`)
				return
			end
			if explain(snapshot.expedition.legality.dispatch) then
				return
			end
		end
		run({ kind = "DispatchExpedition", act = act })
	end)
	missionClaim.button.Activated:Connect(function()
		local snapshot = current()
		local missionId = if snapshot then snapshot.expedition.missionId else nil
		if busy or not snapshot or not missionId then
			return
		end
		if not client:pendingAction() and explain(snapshot.expedition.legality.claim) then
			return
		end
		run({ kind = "ClaimExpedition", missionId = missionId })
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

	local self = {} :: Activities
	function self.destroy(_self: Activities)
		if not alive then
			return
		end
		alive = false
		frame:Destroy()
	end
	function self.tick(_self: Activities)
		tick()
	end

	render()
	task.spawn(load)
	if deps.autoTick ~= false then
		task.spawn(function()
			while alive do
				task.wait(1)
				tick()
			end
		end)
	end
	return self
end

return ActivitiesScreen
