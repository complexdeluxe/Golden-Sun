--!strict
-- One place for Combat HUD v2 to talk to the Black Sabbath sandbox server.
--
-- Uses ReplicatedStorage.Shared.BlackSabbathRemotes when the server has created
-- them. If they don't appear within a few seconds (while Codex's Stage 2B server
-- is still being built), it falls back to the client-side MockSandboxServer so
-- the HUD can still be played in Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteContract = require(ReplicatedStorage.Shared.Contracts.RemoteContract)
local CombatTypes = require(ReplicatedStorage.Shared.Contracts.CombatTypes)
local MockSandboxServer = require(script.Parent.MockSandboxServer)

type Response = RemoteContract.SandboxResponse
type Snapshot = CombatTypes.SandboxSnapshot

export type Connection = {
	isMock: boolean,
	start: (request: RemoteContract.StartSandboxRequest) -> Response,
	getSnapshot: (battleId: string) -> Response,
	submitPrimary: (request: RemoteContract.SandboxPrimaryRequest) -> Response,
	submitSecondary: (request: RemoteContract.SandboxSecondaryRequest) -> Response,
	submitQteCheck: (request: RemoteContract.SandboxQteCheckRequest) -> Response,
	setQteMode: (request: RemoteContract.SandboxQteModeRequest) -> Response,
	onSnapshotChanged: (listener: (Snapshot) -> ()) -> (),
}

local REMOTE_WAIT_SECONDS = 5
local Remotes = RemoteContract.Sandbox

local function failure(): Response
	return { ok = false, code = "NotReady", message = "Couldn't reach the server. Try again." }
end

local function remoteConnection(folder: Instance): Connection
	local function getFunction(name: string): RemoteFunction
		local remote = folder:WaitForChild(name)
		assert(remote:IsA("RemoteFunction"), `{name} should be a RemoteFunction`)
		return remote
	end
	local startRemote = getFunction(Remotes.StartSandbox.name)
	local snapshotRemote = getFunction(Remotes.GetSandboxSnapshot.name)
	local primaryRemote = getFunction(Remotes.SubmitSandboxPrimary.name)
	local secondaryRemote = getFunction(Remotes.SubmitSandboxSecondary.name)
	local qteRemote = getFunction(Remotes.SubmitSandboxQteCheck.name)
	local modeRemote = getFunction(Remotes.SetSandboxQteMode.name)
	local changed = folder:WaitForChild(Remotes.SandboxSnapshotChanged.name)
	assert(changed:IsA("RemoteEvent"), "SandboxSnapshotChanged should be a RemoteEvent")

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
		start = function(request)
			return call(startRemote, request)
		end,
		getSnapshot = function(battleId)
			local request: RemoteContract.SandboxBattleRef = { battleId = battleId }
			return call(snapshotRemote, request)
		end,
		submitPrimary = function(request)
			return call(primaryRemote, request)
		end,
		submitSecondary = function(request)
			return call(secondaryRemote, request)
		end,
		submitQteCheck = function(request)
			return call(qteRemote, request)
		end,
		setQteMode = function(request)
			return call(modeRemote, request)
		end,
		onSnapshotChanged = function(listener)
			changed.OnClientEvent:Connect(function(snapshot: any)
				if type(snapshot) == "table" then
					listener(snapshot :: Snapshot)
				end
			end)
		end,
	}
end

local function mockConnection(): Connection
	return {
		isMock = true,
		start = MockSandboxServer.StartSandbox,
		getSnapshot = function(battleId)
			return MockSandboxServer.GetSandboxSnapshot({ battleId = battleId })
		end,
		submitPrimary = MockSandboxServer.SubmitSandboxPrimary,
		submitSecondary = MockSandboxServer.SubmitSandboxSecondary,
		submitQteCheck = MockSandboxServer.SubmitSandboxQteCheck,
		setQteMode = MockSandboxServer.SetSandboxQteMode,
		onSnapshotChanged = MockSandboxServer.onChanged,
	}
end

local SandboxConnection = {}

function SandboxConnection.connect(): Connection
	local folder = ReplicatedStorage.Shared:WaitForChild(Remotes.FolderName, REMOTE_WAIT_SECONDS)
	if folder then
		return remoteConnection(folder)
	end
	warn("[PBA] BlackSabbathRemotes not found. Using the client-side mock sandbox server.")
	return mockConnection()
end

return SandboxConnection
