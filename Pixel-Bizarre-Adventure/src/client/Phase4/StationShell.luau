--!strict
-- The frame shared by the Cyberware Clinic and D'Arby's Parlor: a 320x180
-- overlay over the Hub with a top bar (title, balances, Yen), BACK TO HUB, a
-- loading / error notice with RETRY, and the request runner.
--
-- The runner sends one action at a time through the shared Phase4Client and
-- turns its result into a status line. The client keeps an unconfirmed request
-- with its original ID and action and sends it again on the next press, so a
-- reply may describe an earlier action, possibly from another station. The
-- status says so ("EARLIER: ...").
--
-- While the client keeps an unconfirmed request, the top bar shows RETRY LAST
-- ACTION (PendingControl) and the station sends no new action: any action press
-- retries the kept one instead. A recovered receipt goes to the station that
-- claims its kind (the Parlor reveals a recovered spin), here or the next time
-- that station opens.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Contract = require(ReplicatedStorage.Shared.Contracts.Phase4EconomyTypes)
local CombatTypes = require(ReplicatedStorage.Shared.Contracts.CombatTypes)
local PixelUi = require(script.Parent.Parent.Battle.PixelUi)
local CampaignUi = require(script.Parent.Parent.Campaign.CampaignUi)
local Phase4Client = require(script.Parent.Phase4Client)
local StationFormat = require(script.Parent.StationFormat)
local PendingControl = require(script.Parent.PendingControl)

type Snapshot = Contract.Snapshot
type Legality = CombatTypes.ActionLegality

local Colors = PixelUi.Colors
local Palette = CampaignUi.Colors

export type Deps = {
	client: Phase4Client.Client,
	toast: (message: string) -> (),
	-- Called once when the player leaves. The Hub refreshes Campaign there.
	onClose: () -> (),
}

export type Config = {
	name: string,
	title: string,
	-- Shown while the first snapshot loads.
	loadingText: string,
	-- Fallback when the server gives no message.
	failText: string,
	balances: (balances: Contract.Balances) -> string,
	-- Receipt kinds this station shows itself when they settle a kept request.
	recovers: { [string]: boolean }?,
}

export type Status = { text: string, color: Color3 }

export type Shell = {
	frame: Frame,
	-- Everything below the top bar. Hidden until the first snapshot loads.
	body: Frame,
	client: Phase4Client.Client,
	toast: (message: string) -> (),
	alive: () -> boolean,
	busy: () -> boolean,
	-- The snapshot once the station has loaded, otherwise nil.
	snapshot: () -> Snapshot?,
	status: () -> Status?,
	setStatus: (text: string?, color: Color3?) -> (),
	-- The screen's own drawing. Called after the shell draws its parts.
	setRender: (fn: () -> ()) -> (),
	render: () -> (),
	-- Toasts the server's reason and returns true when the control is blocked.
	explain: (legality: Legality) -> boolean,
	-- The unconfirmed action's name while the client keeps one.
	pending: () -> string?,
	-- Sends the kept request again (RETRY LAST ACTION).
	retry: () -> (),
	-- Called with a recovered receipt of a kind in `config.recovers`.
	setRecovered: (fn: (receipt: Contract.Receipt) -> ()) -> (),
	-- Sends one action. `after` sees the result before the station redraws.
	-- While an action is unconfirmed, this retries that one instead.
	run: (action: Contract.Action, after: ((result: Phase4Client.Result) -> ())?) -> (),
	load: () -> (),
	destroy: () -> (),
}

local StationShell = {}

function StationShell.open(parent: Instance, deps: Deps, config: Config): Shell
	local client = deps.client
	local frame = PixelUi.frame(parent, config.name, 0, 0, 320, 180, Palette.Backdrop)
	frame.Active = true
	frame.ZIndex = 5

	local bar = PixelUi.frame(frame, "TopBar", 0, 0, 320, 14, Palette.PurpleDark)
	PixelUi.frame(bar, "Edge", 0, 13, 320, 1, Palette.Purple)
	PixelUi.label(bar, "Title", 4, 2, 110, 10, config.title, Palette.Gold)
	local balanceLabel = PixelUi.label(bar, "Balances", 114, 2, 146, 10, "", Colors.TextDim, Enum.TextXAlignment.Right)
	local yenLabel = PixelUi.label(bar, "Yen", 262, 2, 54, 10, "", Palette.Yen, Enum.TextXAlignment.Right)
	local retryLast: () -> () = function() end
	local pendingControl = PendingControl.attach(bar, client, function()
		retryLast()
	end)

	local body = PixelUi.frame(frame, "Body", 0, 16, 320, 164)
	local notice = PixelUi.label(frame, "Notice", 0, 70, 320, 10, "", Colors.TextDim, Enum.TextXAlignment.Center)
	local retry = CampaignUi.button(frame, "Retry", 130, 86, 60, 14, "RETRY")
	-- Created after the body so it draws on top of it.
	local back = CampaignUi.button(frame, "Back", 4, 159, 94, 18, "< BACK TO HUB")

	local alive = true
	local busy = false
	local loaded = false
	local loadError: string? = nil
	local status: Status? = nil
	local screenRender: () -> () = function() end
	local onRecovered: (receipt: Contract.Receipt) -> () = function() end
	local recovers = config.recovers or {}

	local shell = {} :: Shell
	shell.frame = frame
	shell.body = body
	shell.client = client
	shell.toast = deps.toast

	function shell.alive(): boolean
		return alive
	end

	function shell.busy(): boolean
		return busy
	end

	function shell.snapshot(): Snapshot?
		return if loaded then client:snapshot() else nil
	end

	function shell.status(): Status?
		return status
	end

	function shell.setStatus(text: string?, color: Color3?)
		status = if text then { text = text, color = color or Colors.TextDim } else nil
	end

	function shell.setRender(fn: () -> ())
		screenRender = fn
	end

	function shell.render()
		if not alive then
			return
		end
		back.setState(if busy then "Disabled" else "Normal")
		local snapshot = client:snapshot()
		local waiting = pendingControl.render(busy)
		yenLabel.Text = if snapshot then `{snapshot.balances.yen} YEN` else ""
		balanceLabel.Text = if snapshot then config.balances(snapshot.balances) else ""
		-- RETRY LAST ACTION sits over the balances while an action is unconfirmed.
		balanceLabel.Visible = waiting == nil
		local ready = loaded and snapshot ~= nil
		body.Visible = ready
		notice.Visible = not ready
		local failed = loadError
		retry.outline.Visible = not ready and failed ~= nil
		if not ready then
			notice.Text = if failed and waiting then string.upper(failed) .. " LAST ACTION KEPT."
				elseif failed then string.upper(failed)
				else config.loadingText
			notice.TextColor3 = if failed then Colors.Hp else Colors.TextDim
			retry.setState(if busy then "Disabled" else "Primary")
			return
		end
		screenRender()
	end

	function shell.explain(legality: Legality): boolean
		if legality.canUse then
			return false
		end
		deps.toast(CampaignUi.reason(legality))
		return true
	end

	function shell.pending(): string?
		local action = client:pendingAction()
		return if action then StationFormat.action(action) else nil
	end

	function shell.setRecovered(fn: (receipt: Contract.Receipt) -> ())
		onRecovered = fn
	end

	-- Hands a recovered receipt to this station when it shows that kind.
	local function deliverRecovered()
		local receipt = client:takeRecovered(recovers)
		if receipt then
			onRecovered(receipt)
		end
	end

	function shell.retry()
		if busy or not alive or not client:pendingAction() then
			return
		end
		busy = true
		shell.setStatus("RETRYING LAST ACTION...", Colors.TextDim)
		shell.render()
		local result = client:retryPending()
		if not alive then
			return
		end
		busy = false
		-- A retry that opened a session also loads the station.
		if client:snapshot() and (result.ok or not result.uncertain) then
			loaded = true
			loadError = nil
		elseif not loaded then
			-- Still no session: the notice says so and keeps both retries.
			loadError = "Couldn't reach the server."
		end
		local text, color = pendingControl.describe(result)
		shell.setStatus(text, color)
		deps.toast(if result.ok then text else (result.message or text))
		deliverRecovered()
		shell.render()
	end
	retryLast = shell.retry

	function shell.run(action: Contract.Action, after: ((result: Phase4Client.Result) -> ())?)
		if busy or not alive then
			return
		end
		if client:pendingAction() then
			-- Finish the unconfirmed action before sending a new one.
			deps.toast("Finishing your last action first.")
			shell.retry()
			return
		end
		busy = true
		shell.setStatus("WORKING...", Colors.TextDim)
		shell.render()
		local result = client:perform(action)
		if not alive then
			return
		end
		busy = false
		local receipt = result.receipt
		if result.ok and receipt then
			local text = StationFormat.receipt(receipt)
			if result.resolvedPending then
				text = "EARLIER: " .. text
			end
			shell.setStatus(text, Colors.Active)
			deps.toast(text)
		else
			local message = result.message or config.failText
			local waiting = shell.pending()
			if result.uncertain and waiting then
				message = PendingControl.waitingText(waiting)
			elseif result.code == "StaleRevision" then
				message = "Balances changed. Press again to retry."
			elseif result.resolvedPending then
				message = "Last action not applied: " .. message
			end
			shell.setStatus(string.upper(message), Colors.Hp)
			deps.toast(message)
		end
		if after then
			after(result)
		end
		deliverRecovered()
		shell.render()
	end

	function shell.load()
		if busy or not alive then
			return
		end
		busy = true
		loadError = nil
		shell.render()
		local result = client:refresh()
		if not alive then
			return
		end
		busy = false
		loaded = result.ok
		if not result.ok then
			loadError = result.message or config.failText
		end
		local waiting = shell.pending()
		if loaded and waiting then
			shell.setStatus(PendingControl.waitingText(waiting), Colors.Hp)
		end
		if loaded then
			-- A receipt recovered at another station for this one.
			deliverRecovered()
		end
		shell.render()
	end

	function shell.destroy()
		if not alive then
			return
		end
		alive = false
		frame:Destroy()
	end

	retry.button.Activated:Connect(function()
		shell.load()
	end)
	back.button.Activated:Connect(function()
		if busy or not alive then
			return
		end
		shell.destroy()
		deps.onClose()
	end)

	return shell
end

return StationShell
