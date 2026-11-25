--!strict
-- Runs the Phase 3 campaign client: fetch the campaign snapshot, draw the
-- screen for its scene, send each choice to the server, redraw from the reply.
--
--   Creator      -> CreatorScreen
--   Tutorial     -> the existing Phase 1 tutorial (TutorialFlow), then refresh
--   OriginSelect -> the existing Origin picker (TutorialFlow), then refresh
--   Hub          -> HubScreen (Shop, Bag, Party, Set Out)
--   ActMap       -> ActMapScreen
--   ActEncounter -> EncounterScreen (placeholder until the Act combat review)
--   ActResults   -> ResultsScreen
--
-- Snapshot rules from the contract: a call's reply is always taken (it may
-- carry a new session after a reconnect). A CampaignSnapshotChanged event from
-- another session is ignored. Within a session only the newest revision draws.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HubTypes = require(ReplicatedStorage.Shared.Contracts.HubTypes)
local RemoteContract = require(ReplicatedStorage.Shared.Contracts.RemoteContract)
local PixelUi = require(script.Parent.Parent.Battle.PixelUi)
local CampaignConnection = require(script.Parent.CampaignConnection)
local CampaignUi = require(script.Parent.CampaignUi)
local Screen = require(script.Parent.Screen)
local TutorialFlow = require(script.Parent.TutorialFlow)
local CreatorScreen = require(script.Parent.CreatorScreen)
local HubScreen = require(script.Parent.HubScreen)
local ActMapScreen = require(script.Parent.ActMapScreen)
local EncounterScreen = require(script.Parent.EncounterScreen)
local ResultsScreen = require(script.Parent.ResultsScreen)

type Snapshot = HubTypes.CampaignSnapshot
type Response = RemoteContract.CampaignResponse
type SceneKind = "Creator" | "Tutorial" | "OriginSelect" | "Hub" | "ActMap" | "ActEncounter" | "ActResults"

local Colors = PixelUi.Colors

local START_ATTEMPTS = 5
local START_RETRY_SECONDS = 2
local TOAST_SECONDS = 2.5

local SCREENS: { [string]: (root: Frame, actions: Screen.Actions) -> Screen.Screen } = {
	Creator = CreatorScreen.new,
	Hub = HubScreen.new,
	ActMap = ActMapScreen.new,
	ActEncounter = EncounterScreen.new,
	ActResults = ResultsScreen.new,
}

local CampaignController = {}

function CampaignController.run(playerGui: Instance)
	local campaignGui = Instance.new("ScreenGui")
	campaignGui.Name = "PixelCampaign"
	campaignGui.Parent = playerGui
	local root = PixelUi.integerScaledRoot(campaignGui)
	root.BackgroundColor3 = CampaignUi.Colors.Backdrop
	-- The tutorial keeps its own ScreenGui so the battle screen works unchanged.
	local battleGui = Instance.new("ScreenGui")
	battleGui.Name = "PixelBattle"
	battleGui.Enabled = false
	battleGui.ResetOnSpawn = false
	battleGui.Parent = playerGui

	local screens = PixelUi.frame(root, "Screens", 0, 0, 320, 180)
	local loading = PixelUi.label(root, "Loading", 0, 84, 320, 10, "LOADING...", Colors.TextDim, Enum.TextXAlignment.Center)

	-- Just under the top bar, clear of the station buttons and START.
	local toastOutline, toastFill = PixelUi.box(root, "Toast", 60, 16, 200, 14, Colors.PanelLight)
	toastOutline.ZIndex = 10
	toastOutline.Visible = false
	local toastLabel = PixelUi.label(toastFill, "Text", 2, 0, 196, 12, "", Colors.Text, Enum.TextXAlignment.Center)
	local toastToken = 0
	local mockBadge = PixelUi.label(root, "ServerBadge", 160, 2, 62, 10, "", Colors.Mock, Enum.TextXAlignment.Right)
	mockBadge.ZIndex = 10

	local function toast(message: string)
		if message == "" then
			return
		end
		toastToken += 1
		local token = toastToken
		toastLabel.Text = message
		toastOutline.Visible = true
		task.delay(TOAST_SECONDS, function()
			if toastToken == token then
				toastOutline.Visible = false
			end
		end)
	end

	local connection = CampaignConnection.connect()
	mockBadge.Text = if connection.isMock then "MOCK SERVER" else ""

	local snapshot: Snapshot? = nil
	local busy = false
	local screen: Screen.Screen? = nil
	local screenKind: SceneKind? = nil
	local tutorialRunning = false
	local actions: Screen.Actions
	local accept: (incoming: Snapshot, fromEvent: boolean) -> ()

	local function apply(response: Response)
		if response.ok == true then
			accept(response.snapshot, false)
		else
			local rejected = response :: any
			toast(rejected.message)
			if rejected.snapshot then
				accept(rejected.snapshot, false)
			end
		end
	end

	local function refresh()
		for attempt = 1, START_ATTEMPTS do
			local response = connection.getSnapshot()
			apply(response)
			if response.ok == true then
				return
			end
			if attempt < START_ATTEMPTS then
				task.wait(START_RETRY_SECONDS)
			end
		end
	end

	local function setBusy(value: boolean)
		busy = value
		local current = screen
		if current then
			current:setBusy(value)
		end
	end

	local function runTutorial(mode: "Tutorial" | "OriginSelect")
		if tutorialRunning then
			return
		end
		tutorialRunning = true
		campaignGui.Enabled = false
		battleGui.Enabled = true
		local origin = TutorialFlow.run(battleGui, mode)
		battleGui:ClearAllChildren()
		battleGui.Enabled = false
		campaignGui.Enabled = true
		tutorialRunning = false
		local note = connection.noteOrigin
		if note and origin then
			note(origin)
		end
		refresh()
	end

	local function show(current: Snapshot)
		local kind = current.scene.kind :: SceneKind
		if kind ~= screenKind then
			local old = screen
			if old then
				old:destroy()
			end
			screen = nil
			screenKind = kind
			local make = SCREENS[kind]
			if make then
				screen = make(screens, actions)
			end
		end
		loading.Visible = screen == nil
		local active = screen
		if active then
			active:setBusy(busy)
			active:render(current)
		elseif kind == "Tutorial" or kind == "OriginSelect" then
			loading.Text = "STARTING THE TUTORIAL..."
			task.defer(runTutorial, kind)
		end
	end

	function accept(incoming: Snapshot, fromEvent: boolean)
		local current = snapshot
		if current then
			if incoming.sessionId ~= current.sessionId then
				if fromEvent then
					return -- An event from an older session.
				end
			elseif incoming.revision < current.revision then
				return -- Already drew something newer.
			end
		end
		snapshot = incoming
		show(incoming)
	end

	actions = {
		submit = function(fields: { [string]: any })
			local current = snapshot
			if busy or not current then
				return
			end
			local request = table.clone(fields)
			request.sessionId = current.sessionId
			request.expectedRevision = current.revision
			setBusy(true)
			local response = connection.submit(request :: any)
			setBusy(false)
			apply(response)
		end,
		toast = toast,
		isMock = connection.isMock,
		resolveEncounter = connection.resolveEncounter,
	}

	connection.onSnapshotChanged(function(incoming)
		accept(incoming, true)
	end)

	refresh()
end

return CampaignController
