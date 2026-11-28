--!strict
-- Runs the Phase 3 campaign client: fetch the campaign snapshot, draw the
-- screen for its scene, send each choice to the server, redraw from the reply.
--
--   Creator      -> CreatorScreen
--   Tutorial     -> the existing Phase 1 tutorial (TutorialFlow), then refresh
--   OriginSelect -> the existing Origin picker (TutorialFlow), then refresh
--   Hub          -> HubScreen (Shop, Bag, Party, Set Out)
--   ActMap       -> ActMapScreen
--   ActEncounter -> the compact combat HUD over ActBattleRemotes (ActBattle).
--                   The offline mock keeps the EncounterScreen placeholder.
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
local ActBattle = require(script.Parent.ActBattle)
local ActBattleConnection = require(script.Parent.ActBattleConnection)
local Phase4Client = require(script.Parent.Parent.Phase4.Phase4Client)
local Phase4Connection = require(script.Parent.Parent.Phase4.Phase4Connection)
local ActionClient = require(script.Parent.Parent.Net.ActionClient)
local LineageConnection = require(script.Parent.Parent.Lineage.LineageConnection)

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
	local battle: ActBattle.ActBattle? = nil
	local actConnection: ActBattleConnection.Connection? = nil
	local actConnecting = false
	local phase4: Phase4Client.Client? = nil
	local phase4Connecting = false
	local lineage: ActionClient.Client? = nil
	local lineageConnecting = false
	local actions: Screen.Actions
	local accept: (incoming: Snapshot, fromEvent: boolean) -> ()
	local show: (current: Snapshot) -> ()

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
		local current = snapshot
		local appearance = if current then current.character.appearance else nil
		local sprites = if current then current.character.appearanceSprites else nil
		local origin = TutorialFlow.run(battleGui, mode, appearance, sprites)
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

	-- Leaves the fight: the HUD keeps its outcome banner for a moment, then the
	-- campaign screen underneath (already drawn) comes back.
	local function closeBattle()
		local open = battle
		if not open then
			return
		end
		battle = nil
		task.spawn(function()
			open:close()
			if battle == nil then
				battleGui:ClearAllChildren()
				battleGui.Enabled = false
				campaignGui.Enabled = true
			end
		end)
	end

	local function openBattle(current: Snapshot): boolean
		local scene = current.scene
		if scene.kind ~= "ActEncounter" then
			return false
		end
		local encounter = scene.encounter
		local open = battle
		if open and open.battleId == encounter.battleId then
			return true
		end
		local act = actConnection
		if not act then
			if not actConnecting then
				actConnecting = true
				task.spawn(function()
					actConnection = ActBattleConnection.connect()
					actConnecting = false
					if not actConnection then
						toast("The fight server is not ready.")
					end
					local latest = snapshot
					if latest and actConnection then
						show(latest)
					end
				end)
			end
			return true
		end
		if open then
			open:close()
			battleGui:ClearAllChildren()
		end
		campaignGui.Enabled = false
		battleGui.Enabled = true
		battle = ActBattle.open(battleGui, act, encounter, {
			appearance = current.character.appearance,
			appearanceSprites = current.character.appearanceSprites,
			acceptCampaign = function(incoming)
				accept(incoming, false)
			end,
			refreshCampaign = function()
				apply(connection.getSnapshot())
			end,
		})
		return true
	end

	function show(current: Snapshot)
		local kind = current.scene.kind :: SceneKind
		if kind == "ActEncounter" and not connection.isMock then
			if openBattle(current) then
				loading.Visible = false
				return
			end
		elseif battle then
			closeBattle()
		end
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
			apply(response)
			-- A rejection with no snapshot means the server dropped this session
			-- (lease expired, or it was never opened). Reconnect so the next tap works.
			local rejected = response :: any
			if response.ok ~= true and rejected.snapshot == nil and (rejected.code == "ProfileLocked" or rejected.code == "NotReady") then
				refresh()
			end
			setBusy(false)
		end,
		toast = toast,
		isMock = connection.isMock,
		resolveEncounter = connection.resolveEncounter,
		phase4 = function(): Phase4Client.Client?
			if phase4 or connection.isMock or phase4Connecting then
				return phase4
			end
			phase4Connecting = true
			phase4 = Phase4Connection.connect()
			phase4Connecting = false
			return phase4
		end,
		lineage = function(): ActionClient.Client?
			if lineage or connection.isMock or lineageConnecting then
				return lineage
			end
			lineageConnecting = true
			lineage = LineageConnection.connect()
			lineageConnecting = false
			return lineage
		end,
		refreshCampaign = function()
			if busy then
				return
			end
			setBusy(true)
			local response = connection.getSnapshot()
			apply(response)
			if response.ok ~= true then
				refresh()
			end
			setBusy(false)
		end,
	}

	connection.onSnapshotChanged(function(incoming)
		accept(incoming, true)
	end)

	refresh()
end

return CampaignController
