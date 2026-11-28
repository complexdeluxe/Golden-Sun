--!strict
-- Connects an ActionClient to ReplicatedStorage.Shared.ActivityRemotes. Nil
-- without the game server (offline mock campaign).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteContract = require(ReplicatedStorage.Shared.Contracts.RemoteContract)
local ActionClient = require(script.Parent.Parent.Net.ActionClient)
local ActionConnection = require(script.Parent.Parent.Net.ActionConnection)

local ActivityConnection = {}

function ActivityConnection.connect(): ActionClient.Client?
	local routes = RemoteContract.Activity
	return ActionConnection.connect({
		folder = routes.FolderName,
		snapshot = routes.GetActivitySnapshot.name,
		action = routes.SubmitActivityAction.name,
		unreachable = "Couldn't reach Activities. Try again.",
	})
end

return ActivityConnection
