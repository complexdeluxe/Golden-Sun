--!strict
-- Connects an ActionClient to a remotes folder under ReplicatedStorage.Shared
-- that has a snapshot RemoteFunction and an action RemoteFunction, such as
-- LineageRemotes or ActivityRemotes.
--
-- Returns nil when the server never created the folder (for example with the
-- offline mock campaign), so the Hub can say the screen needs the server.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ActionClient = require(script.Parent.ActionClient)

local REMOTE_WAIT_SECONDS = 5

export type Routes = {
	folder: string,
	snapshot: string,
	action: string,
	-- Shown when the snapshot call fails.
	unreachable: string,
}

local ActionConnection = {}

function ActionConnection.connect(routes: Routes): ActionClient.Client?
	local folder = ReplicatedStorage.Shared:WaitForChild(routes.folder, REMOTE_WAIT_SECONDS)
	if not folder then
		return nil
	end
	local function getFunction(name: string): RemoteFunction?
		local remote = folder:WaitForChild(name, REMOTE_WAIT_SECONDS)
		if remote and remote:IsA("RemoteFunction") then
			return remote
		end
		return nil
	end
	local snapshotRemote = getFunction(routes.snapshot)
	local actionRemote = getFunction(routes.action)
	if not snapshotRemote or not actionRemote then
		return nil
	end
	return ActionClient.new({
		getSnapshot = function(): unknown
			return snapshotRemote:InvokeServer({})
		end,
		submit = function(request): unknown
			return actionRemote:InvokeServer(request)
		end,
	}, {
		makeId = function(): string
			return HttpService:GenerateGUID(false)
		end,
		wait = function(seconds: number)
			task.wait(seconds)
		end,
		unreachable = routes.unreachable,
	})
end

return ActionConnection
