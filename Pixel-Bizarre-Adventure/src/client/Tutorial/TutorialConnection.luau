--!strict
-- One place for the battle screen to talk to the tutorial server.
--
-- Uses the real RemoteFunctions under ReplicatedStorage.Shared.TutorialRemotes
-- when the server has created them. If they don't appear within a few seconds
-- (for example while Codex's BattleService is still being built), it falls back
-- to the client-side MockTutorialServer so the UI can still be played in Studio.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RemoteContract = require(ReplicatedStorage.Shared.Contracts.RemoteContract)
local CombatTypes = require(ReplicatedStorage.Shared.Contracts.CombatTypes)
local SaveTypes = require(ReplicatedStorage.Shared.Contracts.SaveTypes)
local MockTutorialServer = require(script.Parent.MockTutorialServer)

type TutorialResponse = RemoteContract.TutorialResponse
type ChooseOriginResponse = RemoteContract.ChooseOriginResponse

export type Connection = {
	isMock: boolean,
	startTutorial: () -> TutorialResponse,
	submitPrimaryAction: (request: CombatTypes.ActionRequest) -> TutorialResponse,
	retryTutorial: (battleId: string, expectedRevision: number) -> TutorialResponse,
	chooseOrigin: (origin: SaveTypes.Origin) -> ChooseOriginResponse,
}

local REMOTE_WAIT_SECONDS = 5

local function networkFailure(message: string): TutorialResponse
	return { ok = false, code = "NotReady", message = message }
end

local function invoke(remote: RemoteFunction, payload: any): (boolean, any)
	return pcall(function()
		return remote:InvokeServer(payload)
	end)
end

local function remoteConnection(folder: Instance): Connection
	local function get(name: string): RemoteFunction
		local remote = folder:WaitForChild(name)
		assert(remote:IsA("RemoteFunction"), `{name} should be a RemoteFunction`)
		return remote
	end
	local startRemote = get(RemoteContract.StartTutorial.name)
	local actionRemote = get(RemoteContract.SubmitPrimaryAction.name)
	local retryRemote = get(RemoteContract.RetryTutorial.name)
	local originRemote = get(RemoteContract.ChooseOrigin.name)

	local function tutorialCall(remote: RemoteFunction, payload: any): TutorialResponse
		local success, result = invoke(remote, payload)
		if not success or type(result) ~= "table" then
			return networkFailure("Couldn't reach the server. Try again.")
		end
		return result :: TutorialResponse
	end

	return {
		isMock = false,
		startTutorial = function()
			local request: RemoteContract.StartTutorialRequest = {}
			return tutorialCall(startRemote, request)
		end,
		submitPrimaryAction = function(request)
			return tutorialCall(actionRemote, request)
		end,
		retryTutorial = function(battleId, expectedRevision)
			local request: RemoteContract.RetryTutorialRequest = {
				battleId = battleId,
				expectedRevision = expectedRevision,
			}
			return tutorialCall(retryRemote, request)
		end,
		chooseOrigin = function(origin)
			local request: RemoteContract.ChooseOriginRequest = { origin = origin }
			local success, result = invoke(originRemote, request)
			if not success or type(result) ~= "table" then
				return { ok = false, code = "NotReady", message = "Couldn't reach the server. Try again." }
			end
			return result :: ChooseOriginResponse
		end,
	}
end

local function mockConnection(): Connection
	return {
		isMock = true,
		startTutorial = function()
			return MockTutorialServer.StartTutorial({})
		end,
		submitPrimaryAction = function(request)
			return MockTutorialServer.SubmitPrimaryAction(request)
		end,
		retryTutorial = function(battleId, expectedRevision)
			return MockTutorialServer.RetryTutorial({ battleId = battleId, expectedRevision = expectedRevision })
		end,
		chooseOrigin = function(origin)
			return MockTutorialServer.ChooseOrigin({ origin = origin })
		end,
	}
end

local TutorialConnection = {}

function TutorialConnection.connect(): Connection
	local folder = ReplicatedStorage.Shared:WaitForChild(RemoteContract.FolderName, REMOTE_WAIT_SECONDS)
	if folder then
		return remoteConnection(folder)
	end
	warn("[PBA] TutorialRemotes not found. Using the client-side mock tutorial server.")
	return mockConnection()
end

return TutorialConnection
