--!strict
-- Connects an ActionClient to ReplicatedStorage.Shared.LineageRemotes. Nil
-- without the game server (offline mock campaign).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteContract = require(ReplicatedStorage.Shared.Contracts.RemoteContract)
local ActionClient = require(script.Parent.Parent.Net.ActionClient)
local ActionConnection = require(script.Parent.Parent.Net.ActionConnection)

local LineageConnection = {}

function LineageConnection.connect(): ActionClient.Client?
	local routes = RemoteContract.Lineage
	return ActionConnection.connect({
		folder = routes.FolderName,
		snapshot = routes.GetLineageSnapshot.name,
		action = routes.SubmitLineageAction.name,
		unreachable = "Couldn't reach the Hall. Try again.",
	})
end

return LineageConnection
