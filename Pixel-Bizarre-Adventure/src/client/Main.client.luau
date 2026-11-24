--!strict
-- Phase 1 client entry point: the Build 1 Raining Carriage Crash tutorial.
--
-- Flow: start the tutorial -> show the battle -> send each button press to the
-- server -> redraw from whatever snapshot comes back. On defeat the player can
-- retry for free. On victory they pick an Origin, which the server saves.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Contracts")

local CombatTypes = require(ReplicatedStorage.Shared.Contracts.CombatTypes)
local RemoteContract = require(ReplicatedStorage.Shared.Contracts.RemoteContract)
local SaveTypes = require(ReplicatedStorage.Shared.Contracts.SaveTypes)
local TutorialConnection = require(script.Parent.Tutorial.TutorialConnection)
local BattleViewport = require(script.Parent.Battle.BattleViewport)

local START_RETRY_SECONDS = 2
local START_ATTEMPTS = 5

local player = Players.LocalPlayer
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PixelBattle"
screenGui.Parent = player:WaitForChild("PlayerGui")

local connection = TutorialConnection.connect()

local snapshot: CombatTypes.CombatSnapshot? = nil
local profile: SaveTypes.Profile? = nil
local busy = false
local view: BattleViewport.BattleViewport

local function redraw()
	if snapshot and profile then
		view:render(snapshot, profile)
	end
end

-- Apply any tutorial response. A rejection may still carry a fresh snapshot,
-- for example after a stale revision, so we resync to it.
local function apply(response: RemoteContract.TutorialResponse)
	if response.ok == true then
		snapshot = response.snapshot
		profile = response.profile
	else
		local rejected = response :: RemoteContract.Rejected
		view:toast(rejected.message)
		if rejected.snapshot then
			snapshot = rejected.snapshot
		end
	end
	redraw()
end

local function request(work: () -> ())
	if busy then
		return
	end
	busy = true
	view:setBusy(true)
	work()
	busy = false
	view:setBusy(false)
end

view = BattleViewport.new(screenGui, {
	onAction = function(moveId, targetId)
		request(function()
			local current = snapshot
			if not current then
				return
			end
			apply(connection.submitPrimaryAction({
				battleId = current.battleId,
				expectedRevision = current.revision,
				moveId = moveId,
				targetId = targetId,
			}))
		end)
	end,
	onRetry = function()
		request(function()
			local current = snapshot
			if not current then
				return
			end
			apply(connection.retryTutorial(current.battleId, current.revision))
		end)
	end,
	onChooseOrigin = function(origin)
		request(function()
			local response = connection.chooseOrigin(origin)
			if response.ok == true then
				profile = response.profile
				view:toast(`Origin saved: {if origin == "Part1_Hamon" then "Hamon" else "Stand"}`)
			else
				view:toast((response :: RemoteContract.Rejected).message)
			end
			redraw()
		end)
	end,
})
view:setMock(connection.isMock)

request(function()
	for attempt = 1, START_ATTEMPTS do
		local response = connection.startTutorial()
		apply(response)
		if response.ok == true then
			return
		end
		if attempt < START_ATTEMPTS then
			task.wait(START_RETRY_SECONDS)
		end
	end
end)
