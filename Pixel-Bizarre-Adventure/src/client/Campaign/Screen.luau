--!strict
-- The shape every campaign screen shares, and what the controller lets a
-- screen do. A screen only draws the snapshot and asks for actions; the
-- controller adds the session ID and revision and talks to the server.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HubTypes = require(ReplicatedStorage.Shared.Contracts.HubTypes)

export type Actions = {
	-- The action fields without sessionId / expectedRevision, for example
	-- { kind = "Navigate", destination = "Hub" }.
	submit: (fields: { [string]: any }) -> (),
	toast: (message: string) -> (),
	isMock: boolean,
	-- Mock only: finish the current encounter (Act combat is not wired yet).
	resolveEncounter: ((outcome: "Clear" | "Defeat" | "Retreat") -> ())?,
}

export type Screen = {
	render: (self: Screen, snapshot: HubTypes.CampaignSnapshot) -> (),
	setBusy: (self: Screen, busy: boolean) -> (),
	destroy: (self: Screen) -> (),
}

return {}
