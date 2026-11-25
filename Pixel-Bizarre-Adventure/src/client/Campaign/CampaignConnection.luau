--!strict
-- One place for the campaign screens to talk to the campaign server.
--
-- Uses ReplicatedStorage.Shared.CampaignRemotes once the server creates them
-- (Codex's Stage 3.3). Until then it falls back to the client-side
-- MockCampaignServer so the screens can be played in Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteContract = require(ReplicatedStorage.Shared.Contracts.RemoteContract)
local HubTypes = require(ReplicatedStorage.Shared.Contracts.HubTypes)
local SaveTypes = require(ReplicatedStorage.Shared.Contracts.SaveTypes)
local MockCampaignServer = require(script.Parent.MockCampaignServer)

type Response = RemoteContract.CampaignResponse
type Snapshot = HubTypes.CampaignSnapshot

export type Connection = {
	isMock: boolean,
	getSnapshot: () -> Response,
	submit: (request: RemoteContract.CampaignActionRequest) -> Response,
	onSnapshotChanged: (listener: (Snapshot) -> ()) -> (),
	-- Mock only. Nil on the real server.
	noteOrigin: ((origin: SaveTypes.Origin) -> ())?,
	resolveEncounter: ((outcome: "Clear" | "Defeat" | "Retreat") -> ())?,
}

local REMOTE_WAIT_SECONDS = 5
local Remotes = RemoteContract.Campaign

local function failure(): Response
	return { ok = false, code = "NotReady", message = "Couldn't reach the server. Try again." }
end

local function remoteConnection(folder: Instance): Connection
	local function getFunction(name: string): RemoteFunction
		local remote = folder:WaitForChild(name)
		assert(remote:IsA("RemoteFunction"), `{name} should be a RemoteFunction`)
		return remote
	end
	local snapshotRemote = getFunction(Remotes.GetCampaignSnapshot.name)
	local actionRemote = getFunction(Remotes.SubmitCampaignAction.name)
	local changed = folder:WaitForChild(Remotes.CampaignSnapshotChanged.name)
	assert(changed:IsA("RemoteEvent"), "CampaignSnapshotChanged should be a RemoteEvent")

	local function call(remote: RemoteFunction, payload: any): Response
		local success, result = pcall(function()
			return remote:InvokeServer(payload)
		end)
		if not success or type(result) ~= "table" then
			return failure()
		end
		return result :: Response
	end

	return {
		isMock = false,
		getSnapshot = function()
			local request: RemoteContract.GetCampaignSnapshotRequest = {}
			return call(snapshotRemote, request)
		end,
		submit = function(request)
			return call(actionRemote, request)
		end,
		onSnapshotChanged = function(listener)
			changed.OnClientEvent:Connect(function(snapshot: any)
				if type(snapshot) == "table" then
					listener(snapshot :: Snapshot)
				end
			end)
		end,
		noteOrigin = nil,
		resolveEncounter = nil,
	}
end

local function mockConnection(): Connection
	return {
		isMock = true,
		getSnapshot = function()
			return MockCampaignServer.GetCampaignSnapshot({})
		end,
		submit = MockCampaignServer.SubmitCampaignAction,
		onSnapshotChanged = MockCampaignServer.onChanged,
		noteOrigin = MockCampaignServer.noteOrigin,
		resolveEncounter = MockCampaignServer.resolveEncounter,
	}
end

local CampaignConnection = {}

function CampaignConnection.connect(): Connection
	local folder = ReplicatedStorage.Shared:WaitForChild(Remotes.FolderName, REMOTE_WAIT_SECONDS)
	if folder then
		return remoteConnection(folder)
	end
	warn("[PBA] CampaignRemotes not found. Using the client-side mock campaign server.")
	return mockConnection()
end

return CampaignConnection
