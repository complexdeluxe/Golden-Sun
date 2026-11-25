--!strict
-- Runs the existing Phase 1 tutorial (or just its Origin picker) for the
-- campaign's Tutorial and OriginSelect scenes, over TutorialRemotes.
--
-- run() yields until the Origin is saved, then returns it. A profile that
-- already finished the tutorial and saved an Origin returns at once. The
-- campaign controller fetches a fresh campaign snapshot afterwards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatTypes = require(ReplicatedStorage.Shared.Contracts.CombatTypes)
local RemoteContract = require(ReplicatedStorage.Shared.Contracts.RemoteContract)
local SaveTypes = require(ReplicatedStorage.Shared.Contracts.SaveTypes)
local AppearanceTypes = require(ReplicatedStorage.Shared.Contracts.CharacterAppearanceTypes)
local TutorialConnection = require(script.Parent.Parent.Tutorial.TutorialConnection)
local BattleViewport = require(script.Parent.Parent.Battle.BattleViewport)
local OriginSelect = require(script.Parent.Parent.Battle.OriginSelect)
local PixelUi = require(script.Parent.Parent.Battle.PixelUi)

type Origin = SaveTypes.Origin

local START_RETRY_SECONDS = 2
local START_ATTEMPTS = 5
local SAVED_PAUSE_SECONDS = 1.5

local TutorialFlow = {}

local function waitFor(start: (finish: (Origin?) -> ()) -> ()): Origin?
	local thread = coroutine.running()
	local finished = false
	local function finish(origin: Origin?)
		if finished then
			return
		end
		finished = true
		task.spawn(thread, origin)
	end
	task.spawn(start, finish)
	return coroutine.yield()
end

-- The full Raining Carriage Crash tutorial, then the Origin picker.
local function runTutorial(
	screenGui: ScreenGui,
	connection: TutorialConnection.Connection,
	appearance: AppearanceTypes.Appearance?,
	finish: (Origin?) -> ()
)
	local snapshot: CombatTypes.CombatSnapshot? = nil
	local profile: SaveTypes.Profile? = nil
	local busy = false
	local done = false
	local view: BattleViewport.BattleViewport

	local function close(origin: Origin?)
		if done then
			return
		end
		done = true
		view:destroy()
		finish(origin)
	end

	local function redraw()
		if snapshot and profile and not done then
			view:render(snapshot, profile)
		end
	end

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
		if busy or done then
			return
		end
		busy = true
		view:setBusy(true)
		work()
		busy = false
		if not done then
			view:setBusy(false)
		end
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
					redraw()
					view:toast(`Origin saved: {OriginSelect.displayName(origin)}. Heading to the Hub...`)
					task.wait(SAVED_PAUSE_SECONDS)
					close(origin)
				elseif (response :: any).code == "OriginAlreadyChosen" then
					close(nil)
				else
					view:toast((response :: RemoteContract.Rejected).message)
					redraw()
				end
			end)
		end,
		onOpenSandbox = nil,
		playerAppearance = appearance,
	})
	view:setMock(connection.isMock)

	request(function()
		for attempt = 1, START_ATTEMPTS do
			local response = connection.startTutorial()
			apply(response)
			if response.ok == true then
				local saved = response.profile
				if saved.tutorialCompleted and saved.origin ~= nil then
					-- Finished earlier: go straight on.
					task.defer(close, saved.origin)
				end
				return
			end
			if attempt < START_ATTEMPTS then
				task.wait(START_RETRY_SECONDS)
			end
		end
	end)
end

-- Only the Origin picker, for a session that resumes between the tutorial
-- clear and the Origin choice.
local function runOriginSelect(screenGui: ScreenGui, connection: TutorialConnection.Connection, finish: (Origin?) -> ())
	local root = PixelUi.integerScaledRoot(screenGui)
	local status = PixelUi.label(root, "Status", 0, 156, 320, 10, "", PixelUi.Colors.TextDim, Enum.TextXAlignment.Center)
	local picker: OriginSelect.OriginSelect
	picker = OriginSelect.new(root, function(origin)
		picker:setBusy(true)
		status.Text = ""
		local response = connection.chooseOrigin(origin)
		if response.ok == true then
			screenGui:ClearAllChildren()
			finish(origin)
		elseif (response :: any).code == "OriginAlreadyChosen" then
			-- Saved in an earlier session: let the campaign snapshot catch up.
			screenGui:ClearAllChildren()
			finish(nil)
		else
			picker:setBusy(false)
			status.Text = (response :: RemoteContract.Rejected).message
		end
	end)
	picker:show()
end

-- `appearance` is the look committed in the Creator, drawn on the player.
function TutorialFlow.run(screenGui: ScreenGui, mode: "Tutorial" | "OriginSelect", appearance: AppearanceTypes.Appearance?): Origin?
	local connection = TutorialConnection.connect()
	return waitFor(function(finish)
		if mode == "OriginSelect" then
			runOriginSelect(screenGui, connection, finish)
		else
			runTutorial(screenGui, connection, appearance, finish)
		end
	end)
end

return TutorialFlow
