--!strict
-- Connects Phase4Client to ReplicatedStorage.Shared.Phase4Remotes.
--
-- Returns nil when the server never created the folder (for example with the
-- offline mock campaign), so the Hub can say the station needs the server.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteContract = require(ReplicatedStorage.Shared.Contracts.RemoteContract)
local Phase4Client = require(script.Parent.Phase4Client)

local REMOTE_WAIT_SECONDS = 5

local Phase4Connection = {}

function Phase4Connection.connect(): Phase4Client.Client?
	local Remotes = RemoteContract.Phase4
	local folder = ReplicatedStorage.Shared:WaitForChild(Remotes.FolderName, REMOTE_WAIT_SECONDS)
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
	local snapshotRemote = getFunction(Remotes.GetPhase4Snapshot.name)
	local actionRemote = getFunction(Remotes.SubmitPhase4Action.name)
	if not snapshotRemote or not actionRemote then
		return nil
	end
	return Phase4Client.new({
		getSnapshot = function(): unknown
			local request: RemoteContract.GetPhase4SnapshotRequest = {}
			return snapshotRemote:InvokeServer(request)
		end,
		submit = function(request: RemoteContract.Phase4ActionRequest): unknown
			return actionRemote:InvokeServer(request)
		end,
	}, {
		makeId = function(): string
			return HttpService:GenerateGUID(false)
		end,
		wait = function(seconds: number)
			task.wait(seconds)
		end,
	})
end

return Phase4Connection
