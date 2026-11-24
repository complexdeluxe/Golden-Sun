--!strict
-- Placeholder for an Act encounter. The general Act combat protocol gets its
-- own contract review before the map connects to the battle HUD, so for now
-- this shows which fight started and waits for the server's result.
--
-- On the mock server it also offers CLEAR / DEFEAT / RETREAT so the map,
-- rewards and recruitment flow can be tested end to end.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HubTypes = require(ReplicatedStorage.Shared.Contracts.HubTypes)
local PixelUi = require(script.Parent.Parent.Battle.PixelUi)
local CampaignUi = require(script.Parent.CampaignUi)
local Screen = require(script.Parent.Screen)

type Snapshot = HubTypes.CampaignSnapshot

local Colors = PixelUi.Colors
local Palette = CampaignUi.Colors

local EncounterScreen = {}

function EncounterScreen.new(root: Frame, actions: Screen.Actions): Screen.Screen
	local frame = PixelUi.frame(root, "Encounter", 0, 0, 320, 180, Palette.Backdrop)
	local topBar = CampaignUi.topBar(frame)
	local _, panel = PixelUi.box(frame, "Panel", 40, 34, 240, 112, Palette.PurpleDark)
	local title = PixelUi.label(panel, "Title", 0, 6, 238, 12, "", Palette.Gold, Enum.TextXAlignment.Center)
	local info = PixelUi.label(panel, "Info", 0, 20, 238, 9, "", Colors.Text, Enum.TextXAlignment.Center)
	local note = PixelUi.label(panel, "Note", 10, 34, 218, 30, "", Colors.TextDim, Enum.TextXAlignment.Center)
	note.TextWrapped = true
	note.TextYAlignment = Enum.TextYAlignment.Top

	local outcomes: { { outcome: "Clear" | "Defeat" | "Retreat", button: CampaignUi.Button } } = {}
	for i, outcome in { "Clear", "Defeat", "Retreat" } :: { "Clear" | "Defeat" | "Retreat" } do
		local button = CampaignUi.button(panel, `Sim{outcome}`, 12 + (i - 1) * 74, 84, 68, 16, string.upper(outcome))
		table.insert(outcomes, { outcome = outcome, button = button })
	end
	local mockLabel = PixelUi.label(panel, "MockLabel", 0, 72, 238, 9, "MOCK: PICK HOW THE FIGHT ENDS", Colors.Mock, Enum.TextXAlignment.Center)

	local busy = false
	for _, entry in outcomes do
		entry.button.button.Activated:Connect(function()
			local resolve = actions.resolveEncounter
			if busy or not resolve then
				return
			end
			resolve(entry.outcome)
		end)
	end

	local self = {} :: Screen.Screen

	function self.render(_self: Screen.Screen, current: Snapshot)
		local scene = current.scene
		if scene.kind ~= "ActEncounter" then
			return
		end
		local encounter = scene.encounter
		topBar.set("ENCOUNTER", current.character.level, current.character.yen, nil)
		title.Text = `{encounter.nodeId} - {string.upper(encounter.stageTag)}`
		info.Text = if encounter.mode == "Replay" then "REPLAY RUN" else "FIRST CLEAR RUN"
		note.Text = "The Act battle screen connects after the Act combat contract review. Waiting for the fight result."
		local mock = actions.resolveEncounter ~= nil
		mockLabel.Visible = mock
		for _, entry in outcomes do
			entry.button.outline.Visible = mock
			entry.button.setState(if busy then "Disabled" elseif entry.outcome == "Clear" then "Primary" else "Normal")
		end
	end

	function self.setBusy(_self: Screen.Screen, value: boolean)
		busy = value
	end

	function self.destroy(_self: Screen.Screen)
		frame:Destroy()
	end

	return self
end

return EncounterScreen
