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

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Contract = require(ReplicatedStorage.Shared.Contracts.Phase4EconomyTypes)
local CombatTypes = require(ReplicatedStorage.Shared.Contracts.CombatTypes)
local PixelUi = require(script.Parent.Parent.Battle.PixelUi)
local CampaignUi = require(script.Parent.Parent.Campaign.CampaignUi)
local Phase4Client = require(script.Parent.Phase4Client)
local StationFormat = require(script.Parent.StationFormat)

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
	-- Sends one action. `after` sees the result before the station redraws.
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
		yenLabel.Text = if snapshot then `{snapshot.balances.yen} YEN` else ""
		balanceLabel.Text = if snapshot then config.balances(snapshot.balances) else ""
		local ready = loaded and snapshot ~= nil
		body.Visible = ready
		notice.Visible = not ready
		local failed = loadError
		retry.outline.Visible = not ready and failed ~= nil
		if not ready then
			notice.Text = if failed then string.upper(failed) else config.loadingText
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

	function shell.run(action: Contract.Action, after: ((result: Phase4Client.Result) -> ())?)
		if busy or not alive then
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
			if result.code == "StaleRevision" then
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
