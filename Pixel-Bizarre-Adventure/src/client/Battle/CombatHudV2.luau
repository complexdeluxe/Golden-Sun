--!strict
-- Combat HUD v2: the Phase 2 Black Sabbath sandbox screen on the 320 x 180 grid.
--
-- Like the tutorial screen, it only shows what the server's SandboxSnapshot
-- says and reports presses through callbacks. It never decides damage, odds,
-- legality or turn order itself.
--
-- Layout (native pixels):
--   row 1 (y 2)    turn + Speed queue, NIGHT stage tag, Black Sabbath step,
--                  QTE mode toggle (Manual / Auto-Good / Untimed Cue)
--   row 2 (y 16)   latest log line (tap for the full log), MOCK badge
--   middle         You, the companion and Black Sabbath on 96 x 96 canvases
--                  (feet at y 120). Each plate shows name, HP, Stamina, a
--                  Resolve bar and status chips. Callouts under the plate show
--                  TARGETED, BOOSTED HIT, ON FIRE, FINISHER and GUARD.
--                  Black Sabbath's intent badge sits to its left, with the
--                  Fade (+20 Dodge) badge under it.
--   bottom-left    Primary/Secondary/Bonus slots, six move buttons with scaling
--                  tag and Stamina cost, an info line and END TURN
--   bottom-middle  shared belt: charges, direct heals, Med-Kit lock, 8 items
--   bottom-right   companion: HP/Guard, tactic switcher, assist, Guard Redirect
--   overlays       QTE bar, item and redirect pickers, full log, Night banner,
--                  hit feedback, outcome banner, toast

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CombatTypes = require(ReplicatedStorage.Shared.Contracts.CombatTypes)
local AssetManifest = require(ReplicatedStorage.Shared.Contracts.AssetManifest)
local PixelUi = require(script.Parent.PixelUi)
local FighterSprite = require(script.Parent.FighterSprite)

type Snapshot = CombatTypes.SandboxSnapshot
type Actor = CombatTypes.SandboxActorState
type Intent = CombatTypes.SandboxIntent
type PrimaryOption = CombatTypes.PrimaryOption
type BeltItemView = CombatTypes.BeltItemView
type QtePrompt = CombatTypes.QtePrompt
type QteInput = CombatTypes.QteInput
type QteMode = CombatTypes.QteMode
type TacticMode = CombatTypes.TacticMode
type StatusId = CombatTypes.StatusId
type Legality = CombatTypes.ActionLegality

local Colors = PixelUi.Colors
local Night = {
	Sky = Color3.fromHex("#10132a"),
	SkyLow = Color3.fromHex("#1b2142"),
	Moon = Color3.fromHex("#e8e4c9"),
	Building = Color3.fromHex("#0b0d1c"),
	Window = Color3.fromHex("#c9a94a"),
	Floor = Color3.fromHex("#2b2630"),
	FloorEdge = Color3.fromHex("#3d3644"),
	Tag = Color3.fromHex("#5b3f9e"),
	Shadow = Color3.fromHex("#7a4fd6"),
	Fire = Color3.fromHex("#ff7a1f"),
	Resolve = Color3.fromHex("#f08c2e"),
	ResolveBack = Color3.fromHex("#4a2c14"),
	Removable = Color3.fromHex("#7fe08a"),
	Miss = Color3.fromHex("#e0463c"),
}

export type Callbacks = {
	onPrimary: (option: PrimaryOption, targetId: string?) -> (),
	onBeltItem: (itemId: CombatTypes.BeltItemId, targetId: string) -> (),
	onTactic: (mode: TacticMode) -> (),
	onRedirect: (intentId: string, recipientId: string) -> (),
	onEndTurn: () -> (),
	onQteMode: (mode: QteMode) -> (),
	onQteInput: (challengeId: string, checkIndex: number, input: QteInput) -> (),
	onRestart: () -> (),
}

export type CombatHudV2 = {
	render: (self: CombatHudV2, snapshot: Snapshot) -> (),
	setBusy: (self: CombatHudV2, busy: boolean) -> (),
	toast: (self: CombatHudV2, message: string) -> (),
	setMock: (self: CombatHudV2, isMock: boolean) -> (),
	destroy: (self: CombatHudV2) -> (),
}

type FighterView = {
	root: Frame,
	sprite: Frame,
	aura: Frame,
	flash: Frame,
	plateOutline: Frame,
	nameLabel: TextLabel,
	setHp: (number) -> (),
	hpText: TextLabel,
	pipRow: Frame,
	pips: { Frame },
	setResolve: (number) -> (),
	resolveOuter: Frame,
	statusRow: Frame,
	callouts: Frame,
}

type MoveButton = {
	box: Frame,
	fill: Frame,
	title: TextLabel,
	tag: TextLabel,
	cost: TextLabel,
	button: TextButton,
}

local FEET_Y = 120
local PLATE_W = 64
local MAX_MOVES = 6
local FULL_LOG_LINES = 15
local QTE_CHOICES: { QteInput } = { "Left", "Center", "Right" }

local PARTY_SLOTS_X = { 2, 70 }
local ENEMY_SLOT_X = 214

local MOVE_SHORT: { [string]: string } = {
	BasicStrike = "BASIC",
	HeavyStrike = "HEAVY",
	HighRiskHeavy = "HI-RISK",
	Defend = "DEFEND",
	HamonInterrupt = "INTERRUPT",
	Finisher = "FINISHER",
}

local TAG_SHORT: { [string]: string } = {
	Physical = "[PHY]",
	Special = "[SPC]",
	Hybrid = "[HYB]",
	AutoBest = "[AUTO]",
}

local TAG_LONG: { [string]: string } = {
	Physical = "[Physical]",
	Special = "[Special]",
	Hybrid = "[Hybrid]",
	AutoBest = "[AutoBest]",
}

local STATUS_SHORT: { [string]: string } = {
	Bleed = "BLD",
	Burn = "BRN",
	Slow = "SLW",
	FogWound = "FOG",
	AgeDown = "AGE",
	CoinBomb = "BMB",
	Stun = "STN",
	Exposed = "EXP",
	Fade = "FAD",
}

local ITEM_SHORT: { [string]: string } = {
	MineralWater = "WTR",
	CapreseSalad = "SAL",
	MedKit = "KIT",
	CoffeeGum = "GUM",
	BloodVial = "VIL",
	UVFlash = "UV",
	SmellingSalts = "SLT",
	SmokePellet = "SMK",
	PassioneEspresso = "ESP",
	SpikedWhetstone = "WHT",
}

local STEP_TEXT: { [string]: string } = {
	LighterStrike = "LIGHTER",
	ShadowGrabWindup = "GRAB WINDUP",
	ShadowGrabLanding = "GRAB LANDING",
	FadeIntoShadow = "FADE",
}

local QTE_MODE_TEXT: { [string]: string } = {
	Manual = "QTE MANUAL",
	AutoGood = "QTE AUTO",
	UntimedCue = "QTE CUE",
}
local QTE_MODE_ORDER: { QteMode } = { "Manual", "AutoGood", "UntimedCue" }
local TACTICS: { TacticMode } = { "Aggressive", "Defensive", "Support" }
local TACTIC_SHORT: { [string]: string } = { Aggressive = "AGG", Defensive = "DEF", Support = "SUP" }

local UV_TOOLTIP = "Guaranteed Shadow Cancel Only. Does NOT apply Exposure."

local CombatHudV2 = {}

local function reasonOf(legality: Legality): string
	return if legality.canUse then "" else legality.disabledReason or ""
end

-- A small ink-outlined chip with centred text.
local function chip(parent: Instance, name: string, x: number, y: number, w: number, h: number, text: string, color: Color3, textColor: Color3?)
	local outline, fill = PixelUi.box(parent, name, x, y, w, h, color)
	local label = PixelUi.label(fill, "Text", 0, 0, w - 2, h - 2, text, textColor or Colors.Text, Enum.TextXAlignment.Center)
	return outline, fill, label
end

local function drawPlaceholderNight(parent: Frame, night: boolean)
	local sky = if night then Night.Sky else Colors.Sky
	local stage = PixelUi.frame(parent, "Stage", 0, 0, PixelUi.NATIVE_WIDTH, PixelUi.NATIVE_HEIGHT, sky)
	PixelUi.frame(stage, "SkyLow", 0, 60, PixelUi.NATIVE_WIDTH, FEET_Y - 60, if night then Night.SkyLow else Colors.SkyLow)
	if night then
		PixelUi.frame(stage, "Moon", 280, 30, 12, 12, Night.Moon)
		PixelUi.frame(stage, "MoonBite", 284, 28, 10, 10, sky)
	end
	-- Fixed skyline so the placeholder stays pixel-stable.
	local skyline = { { 0, 70, 30 }, { 32, 84, 22 }, { 56, 64, 26 }, { 86, 80, 20 }, { 108, 74, 34 }, { 144, 88, 18 },
		{ 164, 68, 28 }, { 194, 82, 24 }, { 220, 72, 30 }, { 252, 86, 20 }, { 274, 66, 26 }, { 302, 78, 18 } }
	for index, block in skyline do
		local x, top, w = block[1], block[2], block[3]
		PixelUi.frame(stage, `Building{index}`, x, top, w, FEET_Y - top, Night.Building)
		if night and index % 2 == 1 then
			PixelUi.frame(stage, `Window{index}`, x + 4, top + 6, 2, 3, Night.Window)
		end
	end
	PixelUi.frame(stage, "FloorEdge", 0, FEET_Y, PixelUi.NATIVE_WIDTH, 2, Night.FloorEdge)
	PixelUi.frame(stage, "Floor", 0, FEET_Y + 2, PixelUi.NATIVE_WIDTH, PixelUi.NATIVE_HEIGHT - FEET_Y - 2, Night.Floor)
	return stage
end

function CombatHudV2.new(screenGui: ScreenGui, callbacks: Callbacks): CombatHudV2
	local root = PixelUi.integerScaledRoot(screenGui)
	local connections: { RBXScriptConnection } = {}

	local stageLayer = PixelUi.frame(root, "StageLayer", 0, 0, PixelUi.NATIVE_WIDTH, PixelUi.NATIVE_HEIGHT)
	local stageNight: boolean? = nil
	local fighterLayer = PixelUi.frame(root, "Fighters", 0, 0, PixelUi.NATIVE_WIDTH, PixelUi.NATIVE_HEIGHT)
	local hud = PixelUi.frame(root, "Hud", 0, 0, PixelUi.NATIVE_WIDTH, PixelUi.NATIVE_HEIGHT)
	hud.ZIndex = 2

	-- Row 1: queue, stage tag, Black Sabbath step, QTE mode --------------------
	local queuePanel = PixelUi.box(hud, "TurnQueue", 2, 2, 146, 13, Colors.Panel)
	local turnLabel = PixelUi.label(queuePanel, "Turn", 2, 1, 20, 11, "T1", Colors.Text)
	local queueChips: { Frame } = {}

	local stageTagBox, stageTagFill, stageTagLabel = chip(hud, "StageTag", 150, 2, 36, 13, "NIGHT", Night.Tag)
	local stepBox, stepFill, stepLabel = chip(hud, "SabbathStep", 188, 2, 74, 13, "", Colors.Panel)
	local qteModeBox, qteModeFill, qteModeLabel = chip(hud, "QteMode", 264, 2, 54, 13, "QTE MANUAL", Colors.Button)
	local qteModeButton = PixelUi.button(qteModeBox, "Press", 0, 0, 54, 13, "")
	local _ = stageTagBox
	local _ = stepBox

	-- Row 2: latest log line + server badge -------------------------------------
	local logStrip = PixelUi.box(hud, "LogStrip", 2, 16, 280, 11, Colors.Panel)
	local logLine = PixelUi.label(logStrip, "Line", 3, 0, 274, 11, "", Colors.Text)
	local logButton = PixelUi.button(logStrip, "OpenFullLog", 0, 0, 280, 11, "")
	local mockBadge = chip(hud, "ServerBadge", 284, 16, 34, 11, "MOCK", Colors.Mock, Colors.Ink)
	mockBadge.Visible = false

	-- Black Sabbath intent + Fade badges (positioned in render) -----------------
	local intentBox, intentFill = PixelUi.box(hud, "SabbathIntent", 151, 29, 76, 38, Colors.Panel)
	local intentLine1 = PixelUi.label(intentFill, "Move", 1, 0, 73, 9, "", Colors.Heavy)
	local intentLine2 = PixelUi.label(intentFill, "Target", 1, 9, 73, 9, "", Colors.Text)
	local intentLine3 = PixelUi.label(intentFill, "Power", 1, 18, 73, 9, "", Colors.Text)
	local intentLine4 = PixelUi.label(intentFill, "Stage", 1, 27, 73, 9, "", Colors.TextDim)
	intentBox.Visible = false
	local fadeBox, fadeFill = PixelUi.box(hud, "FadeBadge", 151, 69, 76, 20, Night.Shadow)
	PixelUi.label(fadeFill, "Title", 0, 0, 74, 9, "FADE +20 DODGE", Colors.Text, Enum.TextXAlignment.Center)
	local fadeLabel = PixelUi.label(fadeFill, "Turns", 0, 9, 74, 9, "", Night.Moon, Enum.TextXAlignment.Center)
	fadeBox.Visible = false

	-- Bottom-left: action panel -------------------------------------------------
	local actionPanel, actionFill = PixelUi.box(hud, "Actions", 2, 122, 160, 56, Colors.Panel)
	local actorLabel = PixelUi.label(actionFill, "Actor", 2, 0, 56, 10, "", Colors.Active)
	local priChip, priFill, priLabel = chip(actionFill, "PrimarySlot", 60, 1, 22, 9, "PRI", Colors.PanelLight)
	local secChip, secFill, secLabel = chip(actionFill, "SecondarySlot", 83, 1, 22, 9, "SEC", Colors.PanelLight)
	local bonusChip, bonusFill, bonusLabel = chip(actionFill, "BonusSlot", 106, 1, 34, 9, "BONUS", Colors.PanelLight)
	local _ = priChip
	local _ = secChip
	local _ = bonusChip
	local moveButtons: { MoveButton } = {}
	local infoLine = PixelUi.label(actionFill, "Info", 2, 43, 104, 11, "", Colors.TextDim)
	local endBox, endFill, endLabel = chip(actionFill, "EndTurn", 107, 42, 50, 12, "END TURN", Colors.Button)
	local endButton = PixelUi.button(endBox, "Press", 0, 0, 50, 12, "")
	local _ = actionPanel

	-- Bottom-middle: party belt ------------------------------------------------
	local beltPanel, beltFill = PixelUi.box(hud, "Belt", 164, 122, 80, 56, Colors.Panel)
	local beltCharges = PixelUi.label(beltFill, "Charges", 2, 0, 76, 9, "BELT 3/3", Colors.Text)
	local beltHeals = PixelUi.label(beltFill, "Heals", 2, 8, 44, 9, "HEAL 2/2", Colors.TextDim)
	local beltKit = PixelUi.label(beltFill, "MedKit", 44, 8, 32, 9, "KIT 1", Colors.TextDim, Enum.TextXAlignment.Right)
	local beltTiles: { { box: Frame, fill: Frame, icon: ImageLabel, code: TextLabel, stock: TextLabel, button: TextButton } } = {}
	local _ = beltPanel

	-- Bottom-right: companion --------------------------------------------------
	local companionPanel, companionFill = PixelUi.box(hud, "Companion", 246, 122, 72, 56, Colors.Panel)
	local companionName = PixelUi.label(companionFill, "Name", 2, 0, 68, 9, "COMPANION", Colors.TextDim)
	local companionHp = PixelUi.label(companionFill, "Hp", 2, 8, 44, 9, "", Colors.Text)
	local companionGuard = chip(companionFill, "Guard", 46, 8, 22, 9, "GRD", Colors.Guard, Colors.Ink)
	companionGuard.Visible = false
	local tacticButtons: { [TacticMode]: { fill: Frame, label: TextLabel, button: TextButton } } = {}
	local assistLabel = PixelUi.label(companionFill, "Assist", 2, 30, 68, 9, "", Colors.TextDim)
	local redirectBox, redirectFill, redirectLabel = chip(companionFill, "Redirect", 1, 40, 68, 13, "REDIRECT 1/1", Colors.Button)
	local redirectButton = PixelUi.button(redirectBox, "Press", 0, 0, 68, 13, "")
	local _ = companionPanel

	-- Overlays -----------------------------------------------------------------
	local fullLog = PixelUi.box(hud, "FullLog", 20, 20, 280, 150, Colors.Panel)
	fullLog.ZIndex = 8
	fullLog.Visible = false
	PixelUi.label(fullLog, "Title", 6, 3, 200, 10, "COMBAT LOG  (TAP TO CLOSE)", Colors.Victory)
	local fullLogLines: { TextLabel } = {}
	for i = 1, FULL_LOG_LINES do
		table.insert(fullLogLines, PixelUi.label(fullLog, `Line{i}`, 6, 14 + (i - 1) * 9, 268, 9, "", Colors.Text))
	end
	local closeLog = PixelUi.button(fullLog, "Close", 0, 0, 280, 150, "")

	-- Picker popup for belt items and Guard Redirect.
	local picker, pickerFill = PixelUi.box(hud, "Picker", 30, 30, 260, 118, Colors.Panel)
	picker.ZIndex = 7
	picker.Visible = false
	local pickerTitle = PixelUi.label(pickerFill, "Title", 4, 2, 220, 10, "", Colors.Victory)
	local pickerSub = PixelUi.label(pickerFill, "Subtitle", 4, 12, 250, 9, "", Colors.TextDim)
	local pickerTip = PixelUi.label(pickerFill, "Tooltip", 4, 21, 250, 18, "", Colors.Victory)
	pickerTip.TextWrapped = true
	pickerTip.TextYAlignment = Enum.TextYAlignment.Top
	local pickerClose = chip(pickerFill, "Close", 238, 2, 18, 11, "X", Colors.Defeat)
	local pickerCloseButton = PixelUi.button(pickerClose, "Press", 0, 0, 18, 11, "")
	type PickerRow = { box: Frame, name: TextLabel, detail: TextLabel, useBox: Frame, useFill: Frame, useLabel: TextLabel, use: TextButton }
	local pickerRows: { PickerRow } = {}
	for i = 1, 3 do
		local y = 42 + (i - 1) * 24
		local box = PixelUi.box(pickerFill, `Row{i}`, 3, y, 252, 22, Colors.PanelLight)
		local name = PixelUi.label(box, "Name", 3, 1, 196, 10, "", Colors.Text)
		local detail = PixelUi.label(box, "Detail", 3, 11, 196, 10, "", Colors.TextDim)
		local useBox, useFill, useLabel = chip(box, "Use", 202, 4, 46, 14, "USE", Colors.Button)
		local use = PixelUi.button(useBox, "Press", 0, 0, 46, 14, "")
		table.insert(pickerRows, { box = box, name = name, detail = detail, useBox = useBox, useFill = useFill, useLabel = useLabel, use = use })
	end

	-- QTE panel.
	local qtePanel, qteFill = PixelUi.box(hud, "Qte", 50, 40, 220, 76, Colors.Panel)
	qtePanel.ZIndex = 6
	qtePanel.Visible = false
	local qteTitle = PixelUi.label(qteFill, "Title", 4, 2, 210, 10, "", Colors.Victory, Enum.TextXAlignment.Center)
	local qteModeHint = PixelUi.label(qteFill, "Mode", 4, 11, 210, 9, "", Colors.TextDim, Enum.TextXAlignment.Center)
	type CheckBox = { outline: Frame, fill: Frame, label: TextLabel }
	local qteChecks: { CheckBox } = {}
	for i = 1, 3 do
		local outline, fill, label = chip(qteFill, `Check{i}`, 0, 21, 38, 13, `{i}`, Colors.PanelLight)
		table.insert(qteChecks, { outline = outline, fill = fill, label = label })
	end
	local qtePromptLabel = PixelUi.label(qteFill, "Prompt", 4, 35, 210, 10, "", Colors.Text, Enum.TextXAlignment.Center)
	local qteTimerOuter, setQteTimer = PixelUi.bar(qteFill, "Timer", 30, 46, 158, 6, Colors.Active, Colors.PanelLight)
	type ChoiceButton = { fill: Frame, label: TextLabel, button: TextButton }
	local qteChoiceButtons: { ChoiceButton } = {}
	for i, input in QTE_CHOICES do
		local box, fill, label = chip(qteFill, input, 8 + (i - 1) * 70, 55, 64, 16, string.upper(input), Colors.Button)
		local button = PixelUi.button(box, "Press", 0, 0, 64, 16, "")
		table.insert(qteChoiceButtons, { fill = fill, label = label, button = button })
	end

	-- Night banner, feedback pop, outcome banner, toast.
	local nightBanner, _nightFill = PixelUi.box(hud, "NightBanner", 60, 56, 200, 30, Night.Tag)
	nightBanner.ZIndex = 5
	nightBanner.Visible = false
	PixelUi.label(nightBanner, "Title", 0, 3, 200, 12, "NIGHT", Night.Moon, Enum.TextXAlignment.Center)
	PixelUi.label(nightBanner, "Sub", 0, 16, 200, 10, "Black Sabbath hunts in the shadows.", Colors.Text, Enum.TextXAlignment.Center)

	local pop, popFill, popLabel = chip(hud, "Feedback", 80, 84, 160, 14, "", Colors.Ink)
	pop.ZIndex = 5
	pop.Visible = false
	local popToken = 0

	local banner = PixelUi.box(hud, "OutcomeBanner", 70, 44, 180, 60, Colors.Panel)
	banner.ZIndex = 9
	banner.Visible = false
	local bannerTitle = PixelUi.label(banner, "Title", 0, 6, 180, 12, "", Colors.Victory, Enum.TextXAlignment.Center)
	local bannerSub = PixelUi.label(banner, "Subtitle", 6, 20, 168, 10, "", Colors.TextDim, Enum.TextXAlignment.Center)
	local bannerButtonBox = chip(banner, "ButtonBox", 40, 36, 100, 16, "FIGHT AGAIN", Colors.Button)
	local bannerButton = PixelUi.button(bannerButtonBox, "Button", 0, 0, 100, 16, "")

	local toastBox = PixelUi.box(hud, "Toast", 40, 30, 240, 14, Colors.PanelLight)
	toastBox.ZIndex = 10
	toastBox.Visible = false
	local toastLabel = PixelUi.label(toastBox, "Text", 4, 1, 232, 12, "", Colors.Text, Enum.TextXAlignment.Center)
	local toastToken = 0

	-- State ----------------------------------------------------------------------
	local fighters: { [string]: FighterView } = {}
	local lastSnapshot: Snapshot? = nil
	local lastLogCount = 0
	local busy = false
	local hoverInfo: string? = nil
	local defaultInfo = ""
	local pickerKind: "Item" | "Redirect" | nil = nil
	local pickerItemId: CombatTypes.BeltItemId? = nil
	local nightShownFor: string? = nil

	local function actorMap(snapshot: Snapshot): { [string]: Actor }
		local map: { [string]: Actor } = {}
		for _, actor in snapshot.actors do
			map[actor.id] = actor
		end
		return map
	end

	local function shortName(snapshot: Snapshot, id: string?): string
		if id == nil then
			return "?"
		end
		if id == snapshot.playerActorId then
			return "YOU"
		end
		for _, actor in snapshot.actors do
			if actor.id == id then
				local name = string.upper(actor.displayName)
				-- "Black Sabbath" -> SABBATH; one-word names stay whole.
				return string.match(name, "(%S+)$") or name
			end
		end
		return string.upper(id)
	end

	local function toast(message: string)
		toastToken += 1
		local token = toastToken
		toastLabel.Text = message
		toastBox.Visible = true
		task.delay(2.5, function()
			if toastToken == token then
				toastBox.Visible = false
			end
		end)
	end

	local function showPop(text: string, color: Color3)
		if text == "" then
			return
		end
		popToken += 1
		local token = popToken
		popLabel.Text = text
		popLabel.TextColor3 = color
		popFill.BackgroundColor3 = Colors.Ink
		pop.BackgroundColor3 = color
		pop.Visible = true
		task.delay(1.6, function()
			if popToken == token then
				pop.Visible = false
			end
		end)
	end

	local function refreshInfo()
		infoLine.Text = hoverInfo or defaultInfo
	end

	local function flashHit(view: FighterView)
		view.flash.BackgroundTransparency = 0.35
		task.delay(0.12, function()
			view.flash.BackgroundTransparency = 1
		end)
	end

	local function qteActive(): boolean
		local snapshot = lastSnapshot
		return snapshot ~= nil and snapshot.qtePrompt ~= nil
	end

	local function inProgress(): boolean
		local snapshot = lastSnapshot
		return snapshot ~= nil and snapshot.outcome == "InProgress"
	end

	-- Stage ----------------------------------------------------------------------
	local function renderStage(snapshot: Snapshot)
		local night = snapshot.stageTag == "Night"
		if stageNight == night then
			return
		end
		stageNight = night
		stageLayer:ClearAllChildren()
		local id = AssetManifest.BlackSabbathStage
		if id ~= PixelUi.UNSET_ASSET then
			PixelUi.image(stageLayer, "Stage", 0, 0, PixelUi.NATIVE_WIDTH, PixelUi.NATIVE_HEIGHT, id)
		else
			drawPlaceholderNight(stageLayer, night)
		end
	end

	-- Fighters -------------------------------------------------------------------
	local function makeFighter(actor: Actor): FighterView
		local facingLeft = actor.team == "Enemy"
		local holder = PixelUi.frame(fighterLayer, actor.id, 0, FEET_Y - FighterSprite.FEET_ROW, 96, 96)
		local aura = PixelUi.frame(holder, "FireAura", 30, 24, 36, 66, Night.Fire)
		aura.BackgroundTransparency = 0.55
		aura.ZIndex = 0
		aura.Visible = false
		local sprite = FighterSprite.create(holder, actor.spriteKey, facingLeft)
		local flash = PixelUi.frame(holder, "HitFlash", 34, 28, 28, 60, Colors.Hp)
		flash.BackgroundTransparency = 1

		-- Plate: name / HP bar / HP + Stamina / Resolve / statuses.
		local plateOutline, plate = PixelUi.box(holder, "Plate", (96 - PLATE_W) // 2 - 1, -5, PLATE_W + 2, 35, Colors.Panel)
		plateOutline.ZIndex = 2
		local nameLabel = PixelUi.label(plate, "Name", 0, 0, PLATE_W, 8, "", Colors.Text, Enum.TextXAlignment.Center)
		local _, setHp = PixelUi.bar(plate, "Hp", 0, 8, PLATE_W, 5, Colors.Hp, Colors.HpBack)
		local hpText = PixelUi.label(plate, "HpText", 1, 13, 34, 8, "", Colors.Text)
		local pipRow = PixelUi.frame(plate, "Stamina", 34, 15, 30, 4)
		local resolveOuter, setResolve = PixelUi.bar(plate, "Resolve", 0, 21, PLATE_W, 4, Night.Resolve, Night.ResolveBack)
		local statusRow = PixelUi.frame(plate, "Statuses", 0, 25, PLATE_W, 8)

		local callouts = PixelUi.frame(holder, "Callouts", 18, 34, 60, 40)
		callouts.ZIndex = 2
		local layout = Instance.new("UIListLayout")
		layout.FillDirection = Enum.FillDirection.Vertical
		layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 1)
		layout.Parent = callouts

		return {
			root = holder,
			sprite = sprite,
			aura = aura,
			flash = flash,
			plateOutline = plateOutline,
			nameLabel = nameLabel,
			setHp = setHp,
			hpText = hpText,
			pipRow = pipRow,
			pips = {},
			setResolve = setResolve,
			resolveOuter = resolveOuter,
			statusRow = statusRow,
			callouts = callouts,
		}
	end

	local function renderPips(view: FighterView, actor: Actor)
		local maxPips = math.max(0, actor.maxStamina)
		if #view.pips ~= maxPips then
			for _, pip in view.pips do
				pip:Destroy()
			end
			table.clear(view.pips)
			-- Fit up to 30 px: 4 px pips with a 1 px gap, narrower if needed.
			local step = if maxPips > 0 then math.max(2, math.min(5, (30 + 1) // maxPips)) else 5
			local width = maxPips * step - 1
			view.pipRow.Position = UDim2.fromOffset(PLATE_W - width, 15)
			for i = 1, maxPips do
				table.insert(view.pips, PixelUi.frame(view.pipRow, `Pip{i}`, (i - 1) * step, 0, step - 1, 4, Colors.StaminaBack))
			end
		end
		for i, pip in view.pips do
			pip.BackgroundColor3 = if i <= actor.stamina then Colors.Stamina else Colors.StaminaBack
		end
	end

	local function renderStatuses(view: FighterView, actor: Actor)
		view.statusRow:ClearAllChildren()
		for index, status in actor.statuses do
			if index > 3 then
				break
			end
			local code = STATUS_SHORT[status.id] or string.upper(string.sub(status.id, 1, 3))
			local color = if status.id == "Exposed" then Colors.Victory
				elseif status.id == "Fade" then Night.Shadow
				elseif status.id == "Stun" then Colors.Defeat
				else Colors.PanelLight
			local outline, _fill, label = chip(view.statusRow, status.id, (index - 1) * 21 + 1, 0, 20, 8, code, color)
			-- Removable statuses get a green outline so cures are easy to spot.
			outline.BackgroundColor3 = if status.isRemovable then Night.Removable else Colors.Ink
			label.TextColor3 = if status.id == "Exposed" then Colors.Ink else Colors.Text
			local press = PixelUi.button(outline, "Press", 0, 0, 20, 8, "")
			press.Activated:Connect(function()
				local turns = if status.turnsRemaining then `, {status.turnsRemaining} turn(s) left` else ""
				toast(`{status.label}{turns}{if status.isRemovable then " [Removable]" else ""}`)
			end)
		end
	end

	local function addCallout(view: FighterView, order: number, text: string, color: Color3, textColor: Color3?)
		local outline = chip(view.callouts, `Callout{order}`, 0, 0, 58, 9, text, color, textColor)
		outline.LayoutOrder = order
	end

	local function renderFighters(snapshot: Snapshot, actors: { [string]: Actor })
		for id, view in fighters do
			if not actors[id] then
				view.root:Destroy()
				fighters[id] = nil
			end
		end

		local intent = snapshot.enemyIntents[1]
		local exposure = snapshot.exposure
		local partyIndex = 0
		for _, actor in snapshot.actors do
			local view = fighters[actor.id]
			if not view then
				view = makeFighter(actor)
				fighters[actor.id] = view
			end
			assert(view)
			local x = ENEMY_SLOT_X
			if actor.team == "Player" then
				partyIndex += 1
				x = PARTY_SLOTS_X[math.min(partyIndex, #PARTY_SLOTS_X)]
			end
			view.root.Position = UDim2.fromOffset(x, FEET_Y - FighterSprite.FEET_ROW)

			local down = actor.hp <= 0
			local onFire = actor.onFireTurnsRemaining > 0
			local active = actor.id == snapshot.activeActorId
			view.sprite.Visible = not down
			view.aura.Visible = onFire and not down
			view.nameLabel.Text = if down then `{shortName(snapshot, actor.id)} DOWN` else shortName(snapshot, actor.id)
			view.nameLabel.TextColor3 = if actor.finisherReady then Colors.Victory elseif active then Colors.Active else Colors.Text
			view.plateOutline.BackgroundColor3 = if onFire then Night.Fire elseif active then Colors.Active else Colors.Ink
			view.setHp(if actor.maxHp > 0 then actor.hp / actor.maxHp else 0)
			view.hpText.Text = `{actor.hp}/{actor.maxHp}`
			renderPips(view, actor)
			view.resolveOuter.Visible = actor.team == "Player"
			view.setResolve(math.clamp(actor.resolve / CombatTypes.Phase2Limits.MaxResolve, 0, 1))
			renderStatuses(view, actor)

			for _, child in view.callouts:GetChildren() do
				if child:IsA("Frame") then
					child:Destroy()
				end
			end
			if not down then
				if intent and intent.targetId == actor.id and actor.team == "Player" then
					addCallout(view, 1, "TARGETED", Colors.Heavy)
				end
				if exposure and exposure.exposedFollowUpActorId == actor.id then
					addCallout(view, 2, "BOOSTED HIT", Colors.Victory, Colors.Ink)
				end
				if exposure and exposure.targetId == actor.id then
					addCallout(view, 2, `EXPOSED -{exposure.mitigationPenaltyPp}`, Colors.Victory, Colors.Ink)
				end
				if onFire then
					addCallout(view, 3, `ON FIRE {actor.onFireTurnsRemaining}T`, Night.Fire, Colors.Ink)
				end
				if actor.finisherReady then
					addCallout(view, 4, "FINISHER!", Colors.Victory, Colors.Ink)
				end
				if actor.isDefending then
					addCallout(view, 5, "GUARD", Colors.Guard, Colors.Ink)
				end
			end
		end
	end

	-- Top rows ---------------------------------------------------------------------
	local function renderTop(snapshot: Snapshot)
		turnLabel.Text = `T{snapshot.turn}`
		for _, c in queueChips do
			c:Destroy()
		end
		table.clear(queueChips)
		local x = 22
		for index, entry in snapshot.turnOrder do
			if x + 40 > 146 then
				break
			end
			local isActive = entry.actorId == snapshot.activeActorId
			local name = string.sub(shortName(snapshot, entry.actorId), 1, 4)
			local c = chip(queuePanel, `Q{index}`, x, 1, 40, 11, `{name} {entry.speed}`,
				if isActive then Colors.Active else Colors.PanelLight, if isActive then Colors.Ink else Colors.Text)
			table.insert(queueChips, c)
			x += 41
		end

		local night = snapshot.stageTag == "Night"
		stageTagLabel.Text = if night then "NIGHT" else "NEUTRAL"
		stageTagFill.BackgroundColor3 = if night then Night.Tag else Colors.PanelLight
		local step = snapshot.blackSabbathStep
		local grabStep = step == "ShadowGrabWindup" or step == "ShadowGrabLanding"
		local grabLive = false
		for _, intent in snapshot.enemyIntents do
			if intent.moveId == "ShadowGrab" then
				grabLive = true
			end
		end
		-- A UV Flash or Hamon Interrupt removes the grab intent; say so instead of
		-- still warning that it is about to land.
		local grabBroken = grabStep and not grabLive
		stepLabel.Text = if grabBroken then "GRAB BROKEN" else STEP_TEXT[step] or step
		local stepColor = if grabBroken then Colors.Panel
			elseif step == "ShadowGrabWindup" then Night.Shadow
			elseif step == "ShadowGrabLanding" then Colors.Heavy
			else Colors.Panel
		stepFill.BackgroundColor3 = stepColor

		qteModeLabel.Text = QTE_MODE_TEXT[snapshot.qteMode] or snapshot.qteMode
		local canToggle = not busy and not qteActive() and inProgress()
		qteModeFill.BackgroundColor3 = if canToggle then Colors.Button else Colors.Disabled

		local last = snapshot.log[#snapshot.log]
		logLine.Text = if last then last.message else ""

		for i, line in fullLogLines do
			local event = snapshot.log[#snapshot.log - FULL_LOG_LINES + i]
			line.Text = if event then `T{event.turn}  {event.message}` else ""
		end
	end

	-- Intent + Fade badges --------------------------------------------------------
	local function renderIntent(snapshot: Snapshot, actors: { [string]: Actor })
		local intent: Intent? = snapshot.enemyIntents[1]
		if intent and snapshot.outcome == "InProgress" then
			local color = if intent.telegraphKind == "Heavy" then Colors.Heavy
				elseif intent.telegraphKind == "Guard" then Night.Shadow
				else Colors.Attack
			intentBox.Visible = true
			intentBox.BackgroundColor3 = color
			intentLine1.Text = string.upper(intent.label)
			intentLine1.TextColor3 = color
			local when = if intent.landingTurn <= snapshot.turn then "NOW" else `T{intent.landingTurn}`
			if intent.targetId == intent.actorId then
				intentLine2.Text = `SELF  {when}`
			else
				local who = if intent.targeting == "Party" then "PARTY" else shortName(snapshot, intent.targetId)
				intentLine2.Text = `> {who} {when}`
			end
			intentLine3.Text = if intent.estimatedPower > 0 then `PWR {intent.estimatedPower}` else ""
			local flags = {}
			if intent.uvCancelable then
				table.insert(flags, "UV")
			end
			if intent.offensiveInterruptible then
				table.insert(flags, "INT")
			end
			local stage = if intent.stage == "Windup" then "WINDUP"
				elseif intent.stage == "Landing" then "LANDING!"
				else "THIS TURN"
			intentLine4.Text = if #flags > 0 then `{stage} {table.concat(flags, " ")}` else stage
			intentLine4.TextColor3 = if intent.stage == "Landing" then Colors.Heavy else Colors.TextDim
		else
			intentBox.Visible = false
		end

		local fade: CombatTypes.StatusView? = nil
		for _, actor in actors do
			if actor.team == "Enemy" then
				for _, status in actor.statuses do
					if status.id == "Fade" then
						fade = status
					end
				end
			end
		end
		fadeBox.Visible = fade ~= nil and snapshot.outcome == "InProgress"
		if fade then
			fadeLabel.Text = if fade.turnsRemaining then `{fade.turnsRemaining} TURN(S) LEFT` else "ACTIVE"
		end
	end

	-- Action panel ----------------------------------------------------------------
	local function activeParty(snapshot: Snapshot): Actor?
		for _, actor in snapshot.actors do
			if actor.id == snapshot.activeActorId and actor.team == "Player" then
				return actor
			end
		end
		return nil
	end

	local function optionAt(index: number): PrimaryOption?
		local snapshot = lastSnapshot
		return if snapshot then snapshot.primaryOptions[index] else nil
	end

	local function pickTarget(option: PrimaryOption): string?
		for _, target in option.targets do
			if target.legality.canUse then
				return target.targetId
			end
		end
		local first = option.targets[1]
		return if first then first.targetId else nil
	end

	local function describeOption(option: PrimaryOption): string
		if not option.legality.canUse then
			return reasonOf(option.legality)
		end
		local parts = { TAG_LONG[option.scalingTag] or option.scalingTag }
		local target = option.targets[1]
		if target then
			table.insert(parts, `HIT {target.hitIfExecutedPercent}%`)
			if target.interruptIfExecutedPercent then
				table.insert(parts, `INT {target.interruptIfExecutedPercent}%`)
			end
		elseif option.moveId == "Defend" then
			table.insert(parts, "Guard until next turn")
		end
		if option.qte == "HighRiskThreeCheck" then
			table.insert(parts, "3 CHECKS")
		end
		return table.concat(parts, " ")
	end

	for i = 1, MAX_MOVES do
		local col = (i - 1) % 3
		local row = (i - 1) // 3
		local box, fill = PixelUi.box(actionFill, `Move{i}`, 1 + col * 52, 11 + row * 16, 51, 15, Colors.Button)
		local title = PixelUi.label(fill, "Title", 0, 0, 49, 7, "", Colors.Text, Enum.TextXAlignment.Center)
		local tag = PixelUi.label(fill, "Tag", 1, 6, 30, 7, "", Colors.TextDim)
		local cost = PixelUi.label(fill, "Cost", 28, 6, 20, 7, "", Colors.Stamina, Enum.TextXAlignment.Right)
		local button = PixelUi.button(box, "Press", 0, 0, 51, 15, "")
		local view: MoveButton = { box = box, fill = fill, title = title, tag = tag, cost = cost, button = button }
		moveButtons[i] = view

		button.MouseEnter:Connect(function()
			local option = optionAt(i)
			if option then
				hoverInfo = describeOption(option)
				if option.legality.canUse and not busy then
					fill.BackgroundColor3 = Colors.ButtonHover
				end
			end
			refreshInfo()
		end)
		button.MouseLeave:Connect(function()
			hoverInfo = nil
			local option = optionAt(i)
			if option and option.legality.canUse and not busy then
				fill.BackgroundColor3 = if option.moveId == "Finisher" then Night.Fire else Colors.Button
			end
			refreshInfo()
		end)
		button.Activated:Connect(function()
			local option = optionAt(i)
			if busy or not option then
				return
			end
			if not option.legality.canUse then
				hoverInfo = reasonOf(option.legality)
				refreshInfo()
				return
			end
			callbacks.onPrimary(option, pickTarget(option))
		end)
	end

	local function slotChip(fill: Frame, label: TextLabel, lit: boolean, color: Color3)
		fill.BackgroundColor3 = if lit then color else Colors.PanelLight
		label.TextColor3 = if lit then Colors.Ink else Colors.TextDim
	end

	local function renderActions(snapshot: Snapshot)
		local actor = activeParty(snapshot)
		local live = snapshot.outcome == "InProgress"
		if actor then
			actorLabel.Text = shortName(snapshot, actor.id)
			actorLabel.TextColor3 = Colors.Active
		elseif live then
			actorLabel.Text = shortName(snapshot, snapshot.activeActorId)
			actorLabel.TextColor3 = Colors.Heavy
		else
			actorLabel.Text = ""
		end
		slotChip(priFill, priLabel, actor ~= nil and actor.primaryAvailable, Colors.Active)
		slotChip(secFill, secLabel, actor ~= nil and actor.secondaryAvailable, Colors.Guard)
		slotChip(bonusFill, bonusLabel, actor ~= nil and actor.bonusPrimaryAvailable, Colors.Victory)

		local firstReason = ""
		for i, view in moveButtons do
			local option = snapshot.primaryOptions[i]
			if option then
				view.box.Visible = true
				local usable = option.legality.canUse and not busy
				local finisher = option.moveId == "Finisher" and option.legality.canUse
				view.title.Text = MOVE_SHORT[option.moveId] or string.upper(string.match(option.label, "^%S+") or option.label)
				view.tag.Text = TAG_SHORT[option.scalingTag] or ""
				view.cost.Text = if option.staminaCost > 0 then `{option.staminaCost}ST` else "-"
				view.fill.BackgroundColor3 = if not usable then Colors.Disabled elseif finisher then Night.Fire else Colors.Button
				view.box.BackgroundColor3 = if finisher then Colors.Victory
					elseif usable and option.slot == "BonusPrimary" then Colors.Victory
					else Colors.Ink
				view.title.TextColor3 = if usable then Colors.Text else Colors.TextDim
				view.tag.TextColor3 = if usable then Colors.Text else Colors.TextDim
				view.cost.TextColor3 = if usable then Colors.Stamina else Colors.TextDim
				if not option.legality.canUse and firstReason == "" then
					firstReason = reasonOf(option.legality)
				end
			else
				view.box.Visible = false
			end
		end

		-- Default info: Resolve readout for the acting fighter, else why nothing works.
		if busy then
			defaultInfo = "..."
		elseif actor then
			if actor.onFireTurnsRemaining > 0 then
				defaultInfo = `ON FIRE {actor.onFireTurnsRemaining}T RES {actor.resolve}`
			else
				defaultInfo = `RES {actor.resolve} +{actor.resolveGainedThisTurn}/{CombatTypes.Phase2Limits.ResolveGainPerTurn}`
			end
		else
			defaultInfo = if live then firstReason else ""
		end
		hoverInfo = nil
		refreshInfo()

		local canEnd = snapshot.endTurnLegality.canUse and not busy
		endFill.BackgroundColor3 = if canEnd then Colors.Button else Colors.Disabled
		endLabel.TextColor3 = if canEnd then Colors.Text else Colors.TextDim
	end

	endButton.MouseEnter:Connect(function()
		local snapshot = lastSnapshot
		if snapshot then
			hoverInfo = if snapshot.endTurnLegality.canUse
				then "Skip unused Secondary / Bonus"
				else reasonOf(snapshot.endTurnLegality)
			refreshInfo()
		end
	end)
	endButton.MouseLeave:Connect(function()
		hoverInfo = nil
		refreshInfo()
	end)
	endButton.Activated:Connect(function()
		local snapshot = lastSnapshot
		if busy or not snapshot then
			return
		end
		if not snapshot.endTurnLegality.canUse then
			hoverInfo = reasonOf(snapshot.endTurnLegality)
			refreshInfo()
			return
		end
		callbacks.onEndTurn()
	end)

	-- Picker ------------------------------------------------------------------------
	local renderPicker: () -> ()

	local function closePicker()
		pickerKind = nil
		pickerItemId = nil
		picker.Visible = false
	end

	local function setRow(row: PickerRow, name: string, detail: string, legality: Legality, onUse: () -> ())
		row.box.Visible = true
		row.name.Text = if detail ~= "" then `{name}: {detail}` else name
		local usable = legality.canUse and not busy
		row.detail.Text = if legality.canUse then "Ready" else reasonOf(legality)
		row.detail.TextColor3 = if legality.canUse then Colors.Active else Colors.Heavy
		row.useFill.BackgroundColor3 = if usable then Colors.Button else Colors.Disabled
		row.useLabel.TextColor3 = if usable then Colors.Text else Colors.TextDim
		-- Rebind the button for this render.
		row.use:Destroy()
		local use = PixelUi.button(row.useBox, "Press", 0, 0, 46, 14, "")
		row.use = use
		use.Activated:Connect(function()
			if busy or not legality.canUse then
				return
			end
			closePicker()
			onUse()
		end)
	end

	function renderPicker()
		local snapshot = lastSnapshot
		for _, row in pickerRows do
			row.box.Visible = false
		end
		if not snapshot or not pickerKind then
			picker.Visible = false
			return
		end
		picker.Visible = true
		if pickerKind == "Item" then
			local item: BeltItemView? = nil
			for _, candidate in snapshot.belt.items do
				if candidate.itemId == pickerItemId then
					item = candidate
				end
			end
			if not item then
				closePicker()
				return
			end
			pickerTitle.Text = `{string.upper(item.label)}  x{item.stock}`
			local belt = snapshot.belt
			pickerSub.Text = `BELT {belt.beltChargesRemaining}/{CombatTypes.Phase2Limits.PartyBeltCharges}   HEALS {belt.directHealsRemaining}/{CombatTypes.Phase2Limits.DirectHealsPerFight}   MED-KIT {if belt.medKitUsed then "USED" else "READY"}`
			if item.itemId == "UVFlash" then
				pickerTip.Text = UV_TOOLTIP
				pickerTip.TextColor3 = Colors.Victory
			else
				pickerTip.Text = if item.legality.canUse then "Uses 1 belt charge and your Secondary." else reasonOf(item.legality)
				pickerTip.TextColor3 = if item.legality.canUse then Colors.TextDim else Colors.Heavy
			end
			for i, preview in item.targets do
				local row = pickerRows[i]
				if not row then
					break
				end
				local detail = preview.summary
				if preview.cancelsIntentId then
					detail = `{detail} (cancel eligible)`
				end
				local itemId = item.itemId
				local targetId = preview.targetId
				setRow(row, shortName(snapshot, preview.targetId), detail, preview.legality, function()
					callbacks.onBeltItem(itemId, targetId)
				end)
			end
		else
			local companion = snapshot.companion
			local redirect = companion and companion.redirect
			if not redirect then
				closePicker()
				return
			end
			local intentLabel = "attack"
			for _, intent in snapshot.enemyIntents do
				if intent.id == redirect.intentId then
					intentLabel = intent.label
				end
			end
			pickerTitle.Text = `GUARD REDIRECT  {redirect.usesRemaining}/{CombatTypes.Phase2Limits.CompanionRedirectsPerFight}`
			pickerSub.Text = `{string.upper(intentLabel)} now targets {shortName(snapshot, redirect.originalTargetId)}`
			pickerTip.Text = if redirect.legality.canUse then "Pick who takes the hit instead. Uses your Secondary." else reasonOf(redirect.legality)
			pickerTip.TextColor3 = if redirect.legality.canUse then Colors.TextDim else Colors.Heavy
			local intentId = redirect.intentId
			for i, target in redirect.targets do
				local row = pickerRows[i]
				if not row then
					break
				end
				local recipientId = target.recipientId
				setRow(
					row,
					shortName(snapshot, target.recipientId),
					if target.recipientIsDefending then "GUARDING (takes less damage)" else "NOT GUARDING",
					target.legality,
					function()
						callbacks.onRedirect(intentId, recipientId)
					end
				)
			end
		end
	end

	pickerCloseButton.Activated:Connect(closePicker)

	-- Belt -----------------------------------------------------------------------------
	for i = 1, 8 do
		local col = (i - 1) % 4
		local row = (i - 1) // 4
		local box, fill = PixelUi.box(beltFill, `Item{i}`, 1 + col * 19, 18 + row * 18, 18, 17, Colors.PanelLight)
		local icon = PixelUi.image(fill, "Icon", 0, 0, 16, 15, PixelUi.UNSET_ASSET)
		local code = PixelUi.label(fill, "Code", 0, 0, 16, 8, "", Colors.Text, Enum.TextXAlignment.Center)
		local stock = PixelUi.label(fill, "Stock", 0, 7, 16, 8, "", Colors.TextDim, Enum.TextXAlignment.Center)
		local button = PixelUi.button(box, "Press", 0, 0, 18, 17, "")
		beltTiles[i] = { box = box, fill = fill, icon = icon, code = code, stock = stock, button = button }
		button.MouseEnter:Connect(function()
			local snapshot = lastSnapshot
			local item = snapshot and snapshot.belt.items[i]
			if item then
				hoverInfo = if item.itemId == "UVFlash" then "UV: Shadow cancel only" else `{item.label} x{item.stock}`
				refreshInfo()
			end
		end)
		button.MouseLeave:Connect(function()
			hoverInfo = nil
			refreshInfo()
		end)
		button.Activated:Connect(function()
			local snapshot = lastSnapshot
			local item = snapshot and snapshot.belt.items[i]
			if not item or busy then
				return
			end
			-- Always open the picker: it shows the previews and why an item is locked.
			pickerKind = "Item"
			pickerItemId = item.itemId
			renderPicker()
		end)
	end

	local function renderBelt(snapshot: Snapshot)
		local belt = snapshot.belt
		local limits = CombatTypes.Phase2Limits
		beltCharges.Text = `BELT {belt.beltChargesRemaining}/{limits.PartyBeltCharges}`
		beltCharges.TextColor3 = if belt.beltChargesRemaining > 0 then Colors.Text else Colors.Defeat
		beltHeals.Text = `HEAL {belt.directHealsRemaining}/{limits.DirectHealsPerFight}`
		beltHeals.TextColor3 = if belt.directHealsRemaining > 0 then Colors.TextDim else Colors.Defeat
		beltKit.Text = if belt.medKitUsed then "KIT 0" else "KIT 1"
		beltKit.TextColor3 = if belt.medKitUsed then Colors.Defeat else Colors.TextDim
		for i, tile in beltTiles do
			local item = belt.items[i]
			tile.box.Visible = item ~= nil
			if item then
				local usable = item.legality.canUse and not busy
				local iconKey = `{item.itemId}Icon`
				local assetId = (AssetManifest :: any)[iconKey]
				local hasIcon = type(assetId) == "string" and assetId ~= PixelUi.UNSET_ASSET
				tile.icon.Visible = hasIcon
				if hasIcon then
					tile.icon.Image = assetId
				end
				tile.code.Visible = not hasIcon
				tile.code.Text = ITEM_SHORT[item.itemId] or string.upper(string.sub(item.itemId, 1, 3))
				tile.stock.Text = `x{item.stock}`
				tile.fill.BackgroundColor3 = if usable then Colors.Button
					elseif item.itemId == "UVFlash" and item.stock > 0 then Night.Tag
					else Colors.Disabled
				tile.code.TextColor3 = if usable then Colors.Text else Colors.TextDim
				tile.stock.TextColor3 = if item.stock > 0 then Colors.Stamina else Colors.Defeat
				tile.box.BackgroundColor3 = if item.itemId == "UVFlash" and item.legality.canUse then Colors.Victory else Colors.Ink
			end
		end
	end

	-- Companion ----------------------------------------------------------------------
	for i, mode in TACTICS do
		local box, fill, label = chip(companionFill, mode, 1 + (i - 1) * 23, 18, 22, 11, TACTIC_SHORT[mode], Colors.PanelLight)
		local button = PixelUi.button(box, "Press", 0, 0, 22, 11, "")
		tacticButtons[mode] = { fill = fill, label = label, button = button }
		button.MouseEnter:Connect(function()
			local snapshot = lastSnapshot
			local companion = snapshot and snapshot.companion
			if companion then
				hoverInfo = if companion.tacticLegality.canUse then `Tactic: {mode}` else reasonOf(companion.tacticLegality)
				refreshInfo()
			end
		end)
		button.MouseLeave:Connect(function()
			hoverInfo = nil
			refreshInfo()
		end)
		button.Activated:Connect(function()
			local snapshot = lastSnapshot
			local companion = snapshot and snapshot.companion
			if busy or not companion or companion.tacticMode == mode then
				return
			end
			if not companion.tacticLegality.canUse then
				hoverInfo = reasonOf(companion.tacticLegality)
				refreshInfo()
				return
			end
			callbacks.onTactic(mode)
		end)
	end

	local function renderCompanion(snapshot: Snapshot, actors: { [string]: Actor })
		local companion = snapshot.companion
		companionPanel.Visible = companion ~= nil
		if not companion then
			return
		end
		local actor = actors[companion.actorId]
		companionName.Text = if actor then string.upper(actor.displayName) else "COMPANION"
		companionHp.Text = if actor then `HP {actor.hp}/{actor.maxHp}` else ""
		companionGuard.Visible = actor ~= nil and actor.isDefending
		for mode, view in tacticButtons do
			local current = companion.tacticMode == mode
			local usable = companion.tacticLegality.canUse and not busy
			view.fill.BackgroundColor3 = if current then Colors.Active elseif usable then Colors.Button else Colors.PanelLight
			view.label.TextColor3 = if current then Colors.Ink elseif usable then Colors.Text else Colors.TextDim
		end
		local strength = math.round(CombatTypes.Phase2Limits.ManualAssistStrength * 100)
		assistLabel.Text = if companion.assistAvailableThisRound then `ASSIST {strength}%` else "ASSIST USED"
		assistLabel.TextColor3 = if companion.assistAvailableThisRound then Colors.Active else Colors.TextDim
		local redirect = companion.redirect
		if redirect then
			local usable = redirect.legality.canUse and not busy
			redirectLabel.Text = `REDIRECT {redirect.usesRemaining}/{CombatTypes.Phase2Limits.CompanionRedirectsPerFight}`
			redirectFill.BackgroundColor3 = if usable then Colors.Button else Colors.Disabled
			redirectLabel.TextColor3 = if usable then Colors.Text else Colors.TextDim
		else
			redirectLabel.Text = "REDIRECT -"
			redirectFill.BackgroundColor3 = Colors.Disabled
			redirectLabel.TextColor3 = Colors.TextDim
		end
	end

	redirectButton.MouseEnter:Connect(function()
		local snapshot = lastSnapshot
		local companion = snapshot and snapshot.companion
		if companion then
			local redirect = companion.redirect
			hoverInfo = if redirect then reasonOf(redirect.legality) else "No attack to redirect."
			if hoverInfo == "" then
				hoverInfo = "Guard Redirect (1/fight)"
			end
			refreshInfo()
		end
	end)
	redirectButton.MouseLeave:Connect(function()
		hoverInfo = nil
		refreshInfo()
	end)
	redirectButton.Activated:Connect(function()
		local snapshot = lastSnapshot
		local companion = snapshot and snapshot.companion
		if busy or not companion then
			return
		end
		if not companion.redirect then
			hoverInfo = "No attack to redirect."
			refreshInfo()
			return
		end
		pickerKind = "Redirect"
		renderPicker()
	end)

	-- QTE ------------------------------------------------------------------------------
	local function currentCheck(prompt: QtePrompt): (number?, any)
		local index = prompt.nextCheckIndex
		if index == nil then
			return nil, nil
		end
		return index, prompt.checks[index]
	end

	local function sendChoice(input: QteInput)
		local snapshot = lastSnapshot
		local prompt = snapshot and snapshot.qtePrompt
		if busy or not prompt then
			return
		end
		local index = currentCheck(prompt)
		if index == nil then
			return
		end
		callbacks.onQteInput(prompt.id, index, input)
	end

	for i, view in qteChoiceButtons do
		view.button.Activated:Connect(function()
			sendChoice(QTE_CHOICES[i])
		end)
	end

	local function renderQte(snapshot: Snapshot)
		local prompt = snapshot.qtePrompt
		qtePanel.Visible = prompt ~= nil
		if not prompt then
			return
		end
		local count = #prompt.checks
		qteTitle.Text = if prompt.kind == "HighRiskThreeCheck" then "HIGH-RISK HEAVY  3 CHECKS" else "HEAVY STRIKE TIMING"
		qteModeHint.Text = if prompt.mode == "Manual"
			then "MANUAL: PRESS INSIDE THE GREEN WINDOW (A S D)"
			else "UNTIMED CUE: NO CLOCK, MATCH EACH CUE"
		local hits = 0
		local startX = (218 - (count * 40 - 2)) // 2
		for i, box in qteChecks do
			box.outline.Visible = i <= count
			if i <= count then
				box.outline.Position = UDim2.fromOffset(startX + (i - 1) * 40, 21)
				local result = prompt.checkResults[i] or "Pending"
				local isNext = prompt.nextCheckIndex == i
				if result == "Hit" then
					hits += 1
				end
				box.fill.BackgroundColor3 = if result == "Hit" then Colors.Active
					elseif result == "Miss" then Night.Miss
					else Colors.PanelLight
				box.label.Text = if result == "Hit" then "HIT" elseif result == "Miss" then "MISS" else `{i}`
				box.label.TextColor3 = if result == "Pending" then Colors.Text else Colors.Ink
				box.outline.BackgroundColor3 = if isNext then Colors.Victory else Colors.Ink
			end
		end
		local index, check = currentCheck(prompt)
		if index and check then
			qtePromptLabel.Text = `{check.prompt}   ({hits}/{count} so far)`
		else
			qtePromptLabel.Text = `{hits}/{count}`
		end
		qteTimerOuter.Visible = prompt.mode == "Manual"
		local usable = not busy and index ~= nil
		for i, view in qteChoiceButtons do
			local input = QTE_CHOICES[i]
			local offered = check == nil or table.find(check.choices, input) ~= nil
			view.fill.BackgroundColor3 = if usable and offered then Colors.Button else Colors.Disabled
			view.label.TextColor3 = if usable and offered then Colors.Text else Colors.TextDim
		end
	end

	-- Manual windows tick on the server clock (workspace:GetServerTimeNow()).
	table.insert(connections, RunService.Heartbeat:Connect(function()
		local snapshot = lastSnapshot
		local prompt = snapshot and snapshot.qtePrompt
		if not prompt or prompt.mode ~= "Manual" then
			return
		end
		local _, check = currentCheck(prompt)
		if not check then
			setQteTimer(0)
			return
		end
		local t = workspace:GetServerTimeNow()
		local opens: number = check.opensAtServerTime
		local closes: number = check.closesAtServerTime
		if t < opens then
			setQteTimer(0)
			qteTimerOuter.BackgroundColor3 = Colors.Ink
		elseif t <= closes then
			-- Bar drains as the window closes.
			setQteTimer(1 - (t - opens) / math.max(0.001, closes - opens))
			qteTimerOuter.BackgroundColor3 = Colors.Active
		else
			setQteTimer(0)
			qteTimerOuter.BackgroundColor3 = Colors.Defeat
		end
	end))

	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not qteActive() then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.A or key == Enum.KeyCode.Left then
			sendChoice("Left")
		elseif key == Enum.KeyCode.S or key == Enum.KeyCode.Down or key == Enum.KeyCode.Space or key == Enum.KeyCode.Up then
			sendChoice("Center")
		elseif key == Enum.KeyCode.D or key == Enum.KeyCode.Right then
			sendChoice("Right")
		end
	end))

	-- QTE mode toggle ----------------------------------------------------------------
	qteModeButton.MouseEnter:Connect(function()
		hoverInfo = "Manual / Auto-Good / Untimed Cue"
		refreshInfo()
	end)
	qteModeButton.MouseLeave:Connect(function()
		hoverInfo = nil
		refreshInfo()
	end)
	qteModeButton.Activated:Connect(function()
		local snapshot = lastSnapshot
		if busy or not snapshot or snapshot.qtePrompt or snapshot.outcome ~= "InProgress" then
			return
		end
		local index = table.find(QTE_MODE_ORDER, snapshot.qteMode) or 0
		callbacks.onQteMode(QTE_MODE_ORDER[index % #QTE_MODE_ORDER + 1])
	end)

	-- Outcome ------------------------------------------------------------------------
	local function renderOutcome(snapshot: Snapshot)
		if snapshot.outcome == "Victory" then
			banner.Visible = true
			bannerTitle.Text = "VICTORY!"
			bannerTitle.TextColor3 = Colors.Victory
			bannerSub.Text = "Black Sabbath is driven off."
		elseif snapshot.outcome == "Defeat" then
			banner.Visible = true
			bannerTitle.Text = "DEFEATED"
			bannerTitle.TextColor3 = Colors.Defeat
			bannerSub.Text = "The sandbox is safe to retry."
		else
			banner.Visible = false
		end
		if snapshot.outcome ~= "InProgress" then
			closePicker()
		end
	end

	bannerButton.Activated:Connect(function()
		if not busy then
			callbacks.onRestart()
		end
	end)
	logButton.Activated:Connect(function()
		fullLog.Visible = true
	end)
	closeLog.Activated:Connect(function()
		fullLog.Visible = false
	end)

	-- Feedback from new log events ---------------------------------------------------
	-- One pop per update: the most important event wins. Dodged and 0/3 are
	-- deliberately distinct so a perfect-but-dodged attack never reads as a miss.
	local function playEvents(snapshot: Snapshot, from: number)
		local bestText, bestColor, bestRank = "", Colors.Text, 0
		local function offer(rank: number, text: string, color: Color3)
			if rank > bestRank then
				bestText, bestColor, bestRank = text, color, rank
			end
		end
		for i = from, #snapshot.log do
			local event = snapshot.log[i]
			if event.kind == "Damage" and event.targetId then
				local view = fighters[event.targetId]
				if view then
					flashHit(view)
				end
			elseif event.kind == "Dodged" then
				offer(6, "DODGED!", Colors.Guard)
			elseif event.kind == "FailedQTE_0of3" then
				offer(7, "0/3 MISSED TIMING!", Night.Miss)
			elseif event.kind == "Interrupt" then
				offer(5, "INTERRUPTED!", Colors.Active)
			elseif event.kind == "UVCancel" then
				offer(5, "SHADOW CANCELLED!", Colors.Victory)
			elseif event.kind == "Redirect" then
				offer(4, "GUARD REDIRECT!", Colors.Guard)
			elseif event.kind == "Action" and event.qteGrade == 3 then
				offer(3, "PERFECT 3/3!", Colors.Victory)
			elseif event.kind == "Action" and event.qteGrade ~= nil then
				offer(2, `{event.qteGrade}/3 CHECKS`, Colors.Attack)
			elseif event.kind == "Assist" and event.amount then
				offer(1, "ASSIST +25%!", Colors.Active)
			end
		end
		showPop(bestText, bestColor)
	end

	-- Public ---------------------------------------------------------------------------
	local self = {} :: CombatHudV2

	function self.render(_self: CombatHudV2, snapshot: Snapshot)
		local actors = actorMap(snapshot)
		local previous = lastSnapshot
		local sameBattle = previous ~= nil and previous.battleId == snapshot.battleId
		if not sameBattle then
			lastLogCount = #snapshot.log
			closePicker()
		end
		lastSnapshot = snapshot

		renderStage(snapshot)
		renderTop(snapshot)
		renderFighters(snapshot, actors)
		renderIntent(snapshot, actors)
		renderActions(snapshot)
		renderBelt(snapshot)
		renderCompanion(snapshot, actors)
		renderQte(snapshot)
		renderPicker()
		renderOutcome(snapshot)

		if sameBattle then
			playEvents(snapshot, lastLogCount + 1)
		end
		lastLogCount = #snapshot.log

		-- Prominent Night banner once per battle.
		if snapshot.stageTag == "Night" and nightShownFor ~= snapshot.battleId then
			nightShownFor = snapshot.battleId
			nightBanner.Visible = true
			task.delay(2.2, function()
				nightBanner.Visible = false
			end)
		end
	end

	function self.setBusy(_self: CombatHudV2, value: boolean)
		busy = value
		local snapshot = lastSnapshot
		if snapshot then
			renderTop(snapshot)
			renderActions(snapshot)
			renderBelt(snapshot)
			renderCompanion(snapshot, actorMap(snapshot))
			renderQte(snapshot)
			renderPicker()
		end
	end

	function self.toast(_self: CombatHudV2, message: string)
		toast(message)
	end

	function self.setMock(_self: CombatHudV2, isMock: boolean)
		mockBadge.Visible = isMock
	end

	function self.destroy(_self: CombatHudV2)
		for _, connection in connections do
			connection:Disconnect()
		end
		screenGui:ClearAllChildren()
	end

	return self
end

return CombatHudV2
