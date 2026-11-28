--!strict
-- The Retry last action control shared by the Phase 4 stations.
--
-- The stations share one Phase4Client. When it keeps an unconfirmed request
-- (the reply was lost, the session expired, or the station was closed before
-- the server answered), this control appears in the station's top bar,
-- whatever the snapshot allows. A player who spent their last Yen on a spin, or
-- whose implant is already removed, can still fetch that action's receipt.
-- Pressing it sends the original request again with its original requestId and
-- action, under the current or a refreshed session.

local PixelUi = require(script.Parent.Parent.Battle.PixelUi)
local CampaignUi = require(script.Parent.Parent.Campaign.CampaignUi)
local Phase4Client = require(script.Parent.Phase4Client)
local StationFormat = require(script.Parent.StationFormat)

local Colors = PixelUi.Colors

export type Control = {
	-- Shows or hides the control. Returns the pending action's name, if any.
	render: (busy: boolean) -> string?,
	-- Status text for a retry result, and whether it succeeded.
	describe: (result: Phase4Client.Result) -> (string, Color3),
}

local PendingControl = {}

PendingControl.X = 150
PendingControl.W = 110

function PendingControl.attach(bar: Frame, client: Phase4Client.Client, onPress: () -> ()): Control
	local button = CampaignUi.button(bar, "RetryLast", PendingControl.X, 1, PendingControl.W, 12, "RETRY LAST ACTION")
	button.outline.ZIndex = 2
	button.outline.Visible = false
	button.button.Activated:Connect(function()
		onPress()
	end)

	local control = {} :: Control

	function control.render(busy: boolean): string?
		local action = client:pendingAction()
		button.outline.Visible = action ~= nil
		if not action then
			return nil
		end
		button.setState(if busy then "Disabled" else "Primary")
		return StationFormat.action(action)
	end

	function control.describe(result: Phase4Client.Result): (string, Color3)
		local receipt = result.receipt
		if result.ok and receipt then
			return "RECOVERED: " .. StationFormat.receipt(receipt), Colors.Active
		elseif result.uncertain then
			return "STILL UNCONFIRMED. RETRY AGAIN.", Colors.Hp
		end
		return string.upper("Last action not applied: " .. (result.message or "the server refused it.")), Colors.Hp
	end

	return control
end

-- The status line while an action is unconfirmed.
function PendingControl.waitingText(name: string): string
	return `UNCONFIRMED: {name}.`
end

return PendingControl
