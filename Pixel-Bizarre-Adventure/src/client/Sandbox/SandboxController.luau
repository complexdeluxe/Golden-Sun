--!strict
-- Runs the Phase 2 Black Sabbath sandbox: start a fight, send each press to the
-- server, and redraw Combat HUD v2 from the newest snapshot.
--
-- Snapshots can arrive three ways: a call's response, the server's
-- SandboxSnapshotChanged event (for example when a Manual QTE window expires),
-- or GetSandboxSnapshot. An older revision of the same battle is ignored; a new
-- battle ID replaces everything.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatTypes = require(ReplicatedStorage.Shared.Contracts.CombatTypes)
local RemoteContract = require(ReplicatedStorage.Shared.Contracts.RemoteContract)
local SandboxConnection = require(script.Parent.SandboxConnection)
local CombatHudV2 = require(script.Parent.Parent.Battle.CombatHudV2)

type Snapshot = CombatTypes.SandboxSnapshot
type Response = RemoteContract.SandboxResponse

local START_ATTEMPTS = 5
local START_RETRY_SECONDS = 2
local DEFAULT_START: RemoteContract.StartSandboxRequest = { level = 10, stageTag = "Night", qteMode = "Manual" }

local SandboxController = {}

function SandboxController.run(screenGui: ScreenGui)
	local connection = SandboxConnection.connect()
	local snapshot: Snapshot? = nil
	local busy = false
	local view: CombatHudV2.CombatHudV2

	local function accept(incoming: Snapshot)
		local current = snapshot
		if current and current.battleId == incoming.battleId and incoming.revision < current.revision then
			return -- Stale: we already drew something newer.
		end
		snapshot = incoming
		view:render(incoming)
	end

	local function apply(response: Response)
		if response.ok == true then
			accept(response.snapshot)
		else
			local rejected = response :: any
			view:toast(rejected.message)
			if rejected.snapshot then
				accept(rejected.snapshot)
			end
		end
	end

	local function request(work: (current: Snapshot) -> Response)
		local current = snapshot
		if busy or not current then
			return
		end
		busy = true
		view:setBusy(true)
		local response = work(current)
		busy = false
		view:setBusy(false)
		apply(response)
	end

	local function actingId(current: Snapshot): string
		return current.activeActorId or current.playerActorId
	end

	local function start(settings: RemoteContract.StartSandboxRequest)
		busy = true
		view:setBusy(true)
		for attempt = 1, START_ATTEMPTS do
			local response = connection.start(settings)
			busy = false
			view:setBusy(false)
			apply(response)
			if response.ok == true then
				return
			end
			busy = true
			view:setBusy(true)
			if attempt < START_ATTEMPTS then
				task.wait(START_RETRY_SECONDS)
			end
		end
		busy = false
		view:setBusy(false)
	end

	view = CombatHudV2.new(screenGui, {
		onPrimary = function(option, targetId)
			request(function(current)
				return connection.submitPrimary({
					battleId = current.battleId,
					expectedRevision = current.revision,
					actorId = actingId(current),
					slot = option.slot,
					moveId = option.moveId,
					targetId = targetId,
				})
			end)
		end,
		onBeltItem = function(itemId, targetId)
			request(function(current)
				return connection.submitSecondary({
					battleId = current.battleId,
					expectedRevision = current.revision,
					kind = "UseBeltItem",
					actorId = actingId(current),
					itemId = itemId,
					targetId = targetId,
				})
			end)
		end,
		onTactic = function(mode)
			request(function(current)
				return connection.submitSecondary({
					battleId = current.battleId,
					expectedRevision = current.revision,
					kind = "SetCompanionTactic",
					actorId = actingId(current),
					tacticMode = mode,
				})
			end)
		end,
		onRedirect = function(intentId, recipientId)
			request(function(current)
				return connection.submitSecondary({
					battleId = current.battleId,
					expectedRevision = current.revision,
					kind = "CompanionGuardRedirect",
					actorId = actingId(current),
					intentId = intentId,
					recipientId = recipientId,
				})
			end)
		end,
		onEndTurn = function()
			request(function(current)
				return connection.submitSecondary({
					battleId = current.battleId,
					expectedRevision = current.revision,
					kind = "EndTurn",
					actorId = actingId(current),
				})
			end)
		end,
		onQteMode = function(mode)
			request(function(current)
				return connection.setQteMode({
					battleId = current.battleId,
					expectedRevision = current.revision,
					qteMode = mode,
				})
			end)
		end,
		onQteInput = function(challengeId, checkIndex, input)
			request(function(current)
				return connection.submitQteCheck({
					battleId = current.battleId,
					challengeId = challengeId,
					checkIndex = checkIndex,
					input = input,
				})
			end)
		end,
		onRestart = function()
			if busy then
				return
			end
			local current = snapshot
			start({
				level = DEFAULT_START.level,
				stageTag = if current then current.stageTag else DEFAULT_START.stageTag,
				qteMode = if current then current.qteMode else DEFAULT_START.qteMode,
			})
		end,
	})
	view:setMock(connection.isMock)

	connection.onSnapshotChanged(function(incoming)
		accept(incoming)
	end)

	start(DEFAULT_START)
end

return SandboxController
