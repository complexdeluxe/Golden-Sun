--!strict
-- Talks to ReplicatedStorage.Shared.ActBattleRemotes for an Act fight.
--
-- A call that never comes back (the server errored or the connection dropped)
-- returns `lost = true` so the fight can resync instead of guessing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteContract = require(ReplicatedStorage.Shared.Contracts.RemoteContract)
local MapTypes = require(ReplicatedStorage.Shared.Contracts.MapTypes)

type Response = RemoteContract.ActBattleResponse
type Snapshot = MapTypes.ActBattleSnapshot

export type Connection = {
	getSnapshot: (battleId: string) -> Response,
	submitPrimary: (request: RemoteContract.ActBattlePrimaryRequest) -> Response,
	submitSecondary: (request: RemoteContract.ActBattleSecondaryRequest) -> Response,
	submitQteCheck: (request: RemoteContract.ActBattleQteCheckRequest) -> Response,
	setQteMode: (request: RemoteContract.ActBattleQteModeRequest) -> Response,
	onSnapshotChanged: (listener: (Snapshot) -> ()) -> () -> (),
}

local REMOTE_WAIT_SECONDS = 10

local function lost(): Response
	return { ok = false, code = "NotReady", message = "Lost contact with the server. Checking the fight...", lost = true } :: any
end

local ActBattleConnection = {}

-- Returns nil if the server never created ActBattleRemotes.
function ActBattleConnection.connect(): Connection?
	local Remotes = (RemoteContract :: any).ActBattle
	if not Remotes then
		return nil
	end
	local folder = ReplicatedStorage.Shared:WaitForChild(Remotes.FolderName, REMOTE_WAIT_SECONDS)
	if not folder then
		return nil
	end
	local function getFunction(name: string): RemoteFunction
		local remote = folder:WaitForChild(name)
		assert(remote:IsA("RemoteFunction"), `{name} should be a RemoteFunction`)
		return remote
	end
	local snapshotRemote = getFunction(Remotes.GetActBattleSnapshot.name)
	local primaryRemote = getFunction(Remotes.SubmitActBattlePrimary.name)
	local secondaryRemote = getFunction(Remotes.SubmitActBattleSecondary.name)
	local qteRemote = getFunction(Remotes.SubmitActBattleQteCheck.name)
	local modeRemote = getFunction(Remotes.SetActBattleQteMode.name)
	local changed = folder:WaitForChild(Remotes.ActBattleSnapshotChanged.name)
	assert(changed:IsA("RemoteEvent"), "ActBattleSnapshotChanged should be a RemoteEvent")

	local function call(remote: RemoteFunction, payload: any): Response
		local success, result = pcall(function()
			return remote:InvokeServer(payload)
		end)
		if not success or type(result) ~= "table" then
			return lost()
		end
		return result :: Response
	end

	return {
		getSnapshot = function(battleId)
			local request: RemoteContract.GetActBattleSnapshotRequest = { battleId = battleId }
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
			local connection = changed.OnClientEvent:Connect(function(snapshot: any)
				if type(snapshot) == "table" then
					listener(snapshot :: Snapshot)
				end
			end)
			return function()
				connection:Disconnect()
			end
		end,
	}
end

return ActBattleConnection
