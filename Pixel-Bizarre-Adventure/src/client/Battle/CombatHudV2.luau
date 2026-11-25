--!strict
-- Combat HUD v2 (compact layout): the Phase 2 Black Sabbath sandbox screen on
-- the 320 x 180 grid, following the compact "big arena + bottom dock" concept.
--
-- Like the tutorial screen, it only shows what the server's SandboxSnapshot
-- says and reports presses through callbacks. It never decides damage, odds,
-- legality or turn order itself.
--
-- Layout (native pixels):
--   arena (y 0-126)  stage, fighters on 96 x 96 canvases (feet at y 118) with
--                    small plates (name, HP, Stamina, Resolve, statuses) and
--                    callouts (TARGETED, BOOSTED HIT, EXPOSED, ON FIRE,
--                    FINISHER, GUARD). Top-left: stage + turn and the Black
--                    Sabbath step. Top-centre: one intent banner (plus Fade).
--                    Top-right: MOCK badge and LOG. The QTE (contracting ring
--                    or untimed cue) renders in the middle of the arena.
--   dock (y 127-180) left: ATTACK / SKILLS / GUARD / BELT and the QTE mode.
--                    centre: detail for the chosen entry, the skill list, the
--                    belt or Guard Redirect targets. No pop-ups.
--                    right: PARTY / FOES tabs (tactics and Redirect on PARTY).
--
-- There is no End Turn button: a Primary (ATTACK, a SKILL or GUARD) ends the
-- turn. Belt items and the companion's Secondary come first. A fighter with no
-- usable Primary (for example Stunned) gets SKIP TURN in place of GUARD.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CombatTypes = require(ReplicatedStorage.Shared.Contracts.CombatTypes)
local AssetManifest = require(ReplicatedStorage.Shared.Contracts.AssetManifest)
local PixelUi = require(script.Parent.PixelUi)
local FighterSprite = require(script.Parent.FighterSprite)
local AppearanceTypes = require(ReplicatedStorage.Shared.Contracts.CharacterAppearanceTypes)

-- The HUD draws the shared battle fields. The sandbox adds the Black Sabbath
-- step; an Act battle adds the stage art, the wave count and Retreat.
type Snapshot = CombatTypes.BattleHudSnapshot & {
	stageTag: string?,
	blackSabbathStep: string?,
	outcome: string,
	stageAssetKey: string?,
	waveIndex: number?,
	waveCount: number?,
	retreatLegality: Legality?,
}
type Actor = CombatTypes.SandboxActorState
type Intent = CombatTypes.SandboxIntent
type PrimaryOption = CombatTypes.PrimaryOption
type BeltItemView = CombatTypes.BeltItemView
type QtePrompt = CombatTypes.QtePrompt
type QteInput = CombatTypes.QteInput
type QteSubmissionInput = CombatTypes.QteSubmissionInput
type QteMode = CombatTypes.QteMode
type TacticMode = CombatTypes.TacticMode
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
	Resolve = Color3.fromHex("#e0559e"),
	ResolveBack = Color3.fromHex("#40182e"),
	Removable = Color3.fromHex("#7fe08a"),
	Miss = Color3.fromHex("#e0463c"),
	Dock = Color3.fromHex("#16122a"),
	DockEdge = Color3.fromHex("#7a4fd6"),
	Select = Color3.fromHex("#3a2a6e"),
	Banner = Color3.fromHex("#2a1420"),
	Gold = Color3.fromHex("#d9a441"),
}

export type Callbacks = {
	onPrimary: (option: PrimaryOption, targetId: string?) -> (),
	onBeltItem: (itemId: CombatTypes.BeltItemId, targetId: string) -> (),
	onTactic: (mode: TacticMode) -> (),
	onRedirect: (intentId: string, recipientId: string) -> (),
	onEndTurn: () -> (),
	onQteMode: (mode: QteMode) -> (),
	onQteInput: (challengeId: string, checkIndex: number, input: QteSubmissionInput) -> (),
	-- The outcome banner's button: FIGHT AGAIN in the sandbox, RETRY in an Act fight.
	onRestart: () -> (),
	-- Act fights only: shows RETREAT in the top bar.
	onRetreat: (() -> ())?,
	-- Drawn on the PlayerIdle fighter (the look saved in the Creator).
	playerAppearance: AppearanceTypes.Appearance?,
}

export type CombatHudV2 = {
	render: (self: CombatHudV2, snapshot: Snapshot) -> (),
	setBusy: (self: CombatHudV2, busy: boolean) -> (),
	toast: (self: CombatHudV2, message: string) -> (),
	setMock: (self: CombatHudV2, isMock: boolean) -> (),
	-- Act fights: replace the outcome banner's line and button. A nil button hides it.
	setOutcomeNote: (self: CombatHudV2, line: string?, button: string?) -> (),
	destroy: (self: CombatHudV2) -> (),
}

type FighterView = {
	root: Frame,
	sprite: Frame,
	aura: Frame,
	flash: Frame,
	marker: Frame,
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

type Row = { box: Frame, fill: Frame, cells: { TextLabel }, button: TextButton }

-- Arena and dock.
local ARENA_H = 126
local DOCK_Y = 127
local DOCK_H = PixelUi.NATIVE_HEIGHT - DOCK_Y
local FEET_Y = 118
local PLATE_W = 50
local PARTY_SLOTS_X = { 16, 74 }
local ENEMY_SLOT_X = 206
local FULL_LOG_LINES = 11
local QTE_CHOICES: { QteInput } = { "Left", "Center", "Right" }

-- Manual ring, in native pixels. The approach ring shrinks from RING_START to
-- RING_TARGET between approachStartsAtServerTime and overlapAtServerTime.
local RING_TARGET = 20
local RING_START = 60
local RING_MIN = 4

-- Dock panes.
local MENU_W = 66
local CENTER_X = 67
local CENTER_W = 160
local RIGHT_X = 228
local RIGHT_W = 92
local SKILL_ROWS = 4
local TARGET_ROWS = 3

type MenuEntry = "Attack" | "Skills" | "Guard" | "Belt"
local MENU_ORDER: { MenuEntry } = { "Attack", "Skills", "Guard", "Belt" }

local MOVE_NAME: { [string]: string } = {
	BasicStrike = "QUICK STRIKE",
	HeavyStrike = "HEAVY STRIKE",
	HighRiskHeavy = "HIGH-RISK HEAVY",
	Defend = "GUARD",
	HamonInterrupt = "HAMON INTERRUPT",
	Finisher = "FINISHER",
}

local MOVE_BLURB: { [string]: string } = {
	BasicStrike = "A quick hit with your Stand or martial arts. Taking a Primary ends your turn.",
	HeavyStrike = "1.5x heavy hit with a timing check.",
	HighRiskHeavy = "3-check timing attack. 3/3 hits hardest.",
	Defend = "Brace until your next turn: take less damage, regain 1 Stamina. Ends your turn.",
	HamonInterrupt = "Breaks a Shadow Grab windup and Exposes Black Sabbath.",
	Finisher = "Spend Fire for a huge hit. Needs 100 Resolve.",
}

local TAG_SHORT: { [string]: string } = {
	Physical = "[PHY]",
	Special = "[SPC]",
	Hybrid = "[HYB]",
	AutoBest = "[AUTO]",
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

local STAGE_TEXT: { [string]: string } = {
	Night = "NIGHT",
	Neutral = "NEUTRAL",
	WaterRain = "RAIN",
	Sunlit = "SUNLIT",
}

local STEP_TEXT: { [string]: string } = {
	LighterStrike = "LIGHTER",
	ShadowGrabWindup = "GRAB WINDUP",
	ShadowGrabLanding = "GRAB LANDING",
	FadeIntoShadow = "FADE",
}

local QTE_MODE_TEXT: { [string]: string } = {
	Manual = "MANUAL",
	AutoGood = "AUTO",
	UntimedCue = "CUE",
}
local QTE_MODE_ORDER: { QteMode } = { "Manual", "AutoGood", "UntimedCue" }
local TACTICS: { TacticMode } = { "Aggressive", "Defensive", "Support" }
local TACTIC_SHORT: { [string]: string } = { Aggressive = "AGG", Defensive = "DEF", Support = "SUP" }

local UV_TOOLTIP = "Guaranteed Shadow Cancel Only. Does NOT apply Exposure."

local CombatHudV2 = {}

local function reasonOf(legality: Legality): string
	if legality.canUse then
		return ""
	end
	return legality.disabledReason
end

local function chip(parent: Instance, name: string, x: number, y: number, w: number, h: number, text: string, color: Color3, textColor: Color3?)
	local outline, fill = PixelUi.box(parent, name, x, y, w, h, color)
	local label = PixelUi.label(fill, "Text", 0, 0, w - 2, h - 2, text, textColor or Colors.Text, Enum.TextXAlignment.Center)
	return outline, fill, label
end

local function drawPlaceholderNight(parent: Frame, night: boolean)
	local sky = if night then Night.Sky else Colors.Sky
	local stage = PixelUi.frame(parent, "Stage", 0, 0, PixelUi.NATIVE_WIDTH, PixelUi.NATIVE_HEIGHT, sky)
	PixelUi.frame(stage, "SkyLow", 0, 56, PixelUi.NATIVE_WIDTH, FEET_Y - 56, if night then Night.SkyLow else Colors.SkyLow)
	if night then
		PixelUi.frame(stage, "Moon", 276, 30, 12, 12, Night.Moon)
		PixelUi.frame(stage, "MoonBite", 280, 28, 10, 10, sky)
	end
	-- Fixed skyline so the placeholder stays pixel-stable.
	local skyline = { { 0, 66, 30 }, { 32, 80, 22 }, { 56, 60, 26 }, { 86, 76, 20 }, { 108, 70, 34 }, { 144, 84, 18 },
		{ 164, 64, 28 }, { 194, 78, 24 }, { 220, 68, 30 }, { 252, 82, 20 }, { 274, 62, 26 }, { 302, 74, 18 } }
	for index, block in skyline do
		local x, top, w = block[1], block[2], block[3]
		PixelUi.frame(stage, `Building{index}`, x, top, w, FEET_Y - top, Night.Building)
		if night and index % 2 == 1 then
			PixelUi.frame(stage, `Window{index}`, x + 4, top + 6, 2, 3, Night.Window)
		end
	end
	PixelUi.frame(stage, "FloorEdge", 0, FEET_Y, PixelUi.NATIVE_WIDTH, 2, Night.FloorEdge)
	PixelUi.frame(stage, "Floor", 0, FEET_Y + 2, PixelUi.NATIVE_WIDTH, ARENA_H - FEET_Y - 2, Night.Floor)
	return stage
end

function CombatHudV2.new(screenGui: ScreenGui, callbacks: Callbacks): CombatHudV2
	local root = PixelUi.integerScaledRoot(screenGui)
	local connections: { RBXScriptConnection } = {}

	local stageLayer = PixelUi.frame(root, "StageLayer", 0, 0, PixelUi.NATIVE_WIDTH, PixelUi.NATIVE_HEIGHT)
	local stageNight: string? = nil
	local fighterLayer = PixelUi.frame(root, "Fighters", 0, 0, PixelUi.NATIVE_WIDTH, ARENA_H)
	fighterLayer.ClipsDescendants = true
	local hud = PixelUi.frame(root, "Hud", 0, 0, PixelUi.NATIVE_WIDTH, PixelUi.NATIVE_HEIGHT)
	hud.ZIndex = 2

	-- Arena corners -----------------------------------------------------------------
	local stageBox, stageFill, stageLabel = chip(hud, "StageTag", 2, 2, 72, 11, "NIGHT - TURN 1", Night.Tag)
	local stepBox, stepFill, stepLabel = chip(hud, "SabbathStep", 2, 14, 72, 10, "", Colors.Panel)
	local mockBadge = chip(hud, "ServerBadge", 250, 2, 34, 11, "MOCK", Colors.Mock, Colors.Ink)
	mockBadge.Visible = false
	local logBox = chip(hud, "LogButton", 286, 2, 32, 11, "LOG", Colors.Panel)
	local logButton = PixelUi.button(logBox, "Press", 0, 0, 32, 11, "")
	-- Act fights: Retreat. The first press arms it, the second sends it.
	local retreatBox, retreatFill, retreatLabel = chip(hud, "Retreat", 208, 2, 40, 11, "RETREAT", Colors.Panel)
	local retreatButton = PixelUi.button(retreatBox, "Press", 0, 0, 40, 11, "")
	retreatBox.Visible = false
	local retreatArmed = 0
	local _ = stageBox
	local _ = stepBox

	-- One intent banner, top centre, gold trim ---------------------------------------
	local intentBox, intentFill = PixelUi.box(hud, "SabbathIntent", 82, 3, 156, 21, Night.Banner)
	intentBox.BackgroundColor3 = Night.Gold
	local intentIcon = chip(intentFill, "Icon", 2, 2, 13, 15, "!", Colors.Heavy)
	local intentLine1 = PixelUi.label(intentFill, "Move", 17, 1, 136, 9, "", Colors.Victory)
	local intentLine2 = PixelUi.label(intentFill, "Detail", 17, 10, 136, 9, "", Colors.Text)
	local _ = intentIcon
	intentBox.Visible = false
	local fadeBox, _fadeFill, fadeLabel = chip(hud, "FadeBadge", 150, 25, 76, 10, "", Night.Shadow)
	fadeBox.Visible = false

	-- Dock -------------------------------------------------------------------------
	local dock = PixelUi.frame(hud, "Dock", 0, DOCK_Y - 1, PixelUi.NATIVE_WIDTH, DOCK_H + 1, Night.DockEdge)
	local menuPanel, menuFill = PixelUi.box(dock, "Menu", 0, 1, MENU_W, DOCK_H, Night.Dock)
	local centerPanel, centerFill = PixelUi.box(dock, "Center", CENTER_X, 1, CENTER_W, DOCK_H, Night.Dock)
	local rightPanel, rightFill = PixelUi.box(dock, "Side", RIGHT_X, 1, RIGHT_W, DOCK_H, Night.Dock)
	local _ = menuPanel
	local _ = centerPanel
	local _ = rightPanel

	-- Left: who is acting, the four entries, QTE mode.
	local actorLabel = PixelUi.label(menuFill, "Actor", 2, 0, 46, 9, "", Colors.Active)
	local staLabel = PixelUi.label(menuFill, "Stamina", 48, 0, 14, 9, "", Colors.Guard, Enum.TextXAlignment.Right)
	type MenuView = { fill: Frame, label: TextLabel, extra: TextLabel, button: TextButton }
	local menuViews: { [MenuEntry]: MenuView } = {}
	for i, entry in MENU_ORDER do
		local outline, fill = PixelUi.box(menuFill, entry, 1, 9 + (i - 1) * 9, MENU_W - 4, 9, Night.Dock)
		outline.BackgroundColor3 = Night.Dock
		local label = PixelUi.label(fill, "Text", 1, 0, 58, 7, "", Colors.Text)
		local extra = PixelUi.label(fill, "Extra", 40, 0, 20, 7, "", Colors.TextDim, Enum.TextXAlignment.Right)
		local button = PixelUi.button(outline, "Press", 0, 0, MENU_W - 4, 9, "")
		menuViews[entry] = { fill = fill, label = label, extra = extra, button = button }
	end
	local qteModeLabel = PixelUi.label(menuFill, "QteMode", 2, 45, 60, 7, "QTE: MANUAL", Colors.TextDim)
	local qteModeButton = PixelUi.button(menuFill, "QteModePress", 0, 45, MENU_W - 2, 6, "")

	-- Centre: header + body. Body content is one of: detail, skill list, belt grid,
	-- target rows (belt item or Guard Redirect).
	local centerTitle = PixelUi.label(centerFill, "Title", 2, 0, 70, 9, "", Colors.Victory)
	local centerTag = PixelUi.label(centerFill, "Tag", 72, 0, 84, 9, "", Colors.Active, Enum.TextXAlignment.Right)

	local detailBody = PixelUi.frame(centerFill, "Detail", 0, 9, CENTER_W - 2, DOCK_H - 11)
	local detailText = PixelUi.label(detailBody, "Text", 2, 0, CENTER_W - 6, 17, "", Colors.Text)
	detailText.TextWrapped = true
	detailText.TextYAlignment = Enum.TextYAlignment.Top
	detailText.TextTruncate = Enum.TextTruncate.None
	local detailOdds = PixelUi.label(detailBody, "Odds", 2, 18, CENTER_W - 6, 8, "", Colors.TextDim)
	local warnBox, warnFill, warnLabel = chip(detailBody, "Warning", 1, 30, 108, 10, "", Night.Banner, Colors.Heavy)
	warnBox.BackgroundColor3 = Colors.Heavy
	local useBox, useFill, useLabel = chip(detailBody, "Use", 112, 30, 44, 10, "USE >", Colors.Button)
	local useButton = PixelUi.button(useBox, "Press", 0, 0, 44, 10, "")
	local _ = warnFill

	local function makeRow(parent: Instance, name: string, y: number, widths: { number }): Row
		local box, fill = PixelUi.box(parent, name, 1, y, CENTER_W - 4, 10, Night.Dock)
		box.BackgroundColor3 = Night.Dock
		local cells: { TextLabel } = {}
		local x = 2
		for i, w in widths do
			table.insert(cells, PixelUi.label(fill, `Cell{i}`, x, 0, w, 8, "", Colors.Text))
			x += w
		end
		local button = PixelUi.button(box, "Press", 0, 0, CENTER_W - 4, 10, "")
		return { box = box, fill = fill, cells = cells, button = button }
	end

	local skillsBody = PixelUi.frame(centerFill, "Skills", 0, 9, CENTER_W - 2, DOCK_H - 11)
	local skillRows: { Row } = {}
	for i = 1, SKILL_ROWS do
		-- name | cost | tag | note
		table.insert(skillRows, makeRow(skillsBody, `Skill{i}`, (i - 1) * 10, { 66, 20, 26, 40 }))
	end

	local beltBody = PixelUi.frame(centerFill, "Belt", 0, 9, CENTER_W - 2, DOCK_H - 11)
	type Tile = { box: Frame, fill: Frame, icon: ImageLabel, code: TextLabel, stock: TextLabel, button: TextButton }
	local beltTiles: { Tile } = {}
	for i = 1, 8 do
		local col = (i - 1) % 4
		local row = (i - 1) // 4
		local box, fill = PixelUi.box(beltBody, `Item{i}`, 1 + col * 39, row * 20, 38, 19, Colors.PanelLight)
		local icon = PixelUi.image(fill, "Icon", 1, 1, 15, 15, PixelUi.UNSET_ASSET)
		local code = PixelUi.label(fill, "Code", 0, 0, 36, 9, "", Colors.Text, Enum.TextXAlignment.Center)
		local stock = PixelUi.label(fill, "Stock", 0, 8, 36, 9, "", Colors.Stamina, Enum.TextXAlignment.Center)
		local button = PixelUi.button(box, "Press", 0, 0, 38, 19, "")
		beltTiles[i] = { box = box, fill = fill, icon = icon, code = code, stock = stock, button = button }
	end

	local targetBody = PixelUi.frame(centerFill, "Targets", 0, 9, CENTER_W - 2, DOCK_H - 11)
	local targetTip = PixelUi.label(targetBody, "Tip", 2, 0, CENTER_W - 6, 9, "", Colors.Victory)
	local targetRows: { Row } = {}
	for i = 1, TARGET_ROWS do
		-- who + effect | ready or reason
		table.insert(targetRows, makeRow(targetBody, `Target{i}`, 9 + (i - 1) * 10, { 100, 52 }))
	end
	local backBox = chip(targetBody, "Back", CENTER_W - 36, -9, 32, 9, "BACK", Colors.PanelLight)
	local backButton = PixelUi.button(backBox, "Press", 0, 0, 32, 9, "")

	-- Right: PARTY / FOES tabs.
	local partyTabBox, partyTabFill, partyTabLabel = chip(rightFill, "PartyTab", 1, 1, 44, 9, "PARTY", Colors.PanelLight)
	local foesTabBox, foesTabFill, foesTabLabel = chip(rightFill, "FoesTab", 45, 1, 44, 9, "FOES", Colors.PanelLight)
	local partyTabButton = PixelUi.button(partyTabBox, "Press", 0, 0, 44, 9, "")
	local foesTabButton = PixelUi.button(foesTabBox, "Press", 0, 0, 44, 9, "")

	local foesBody = PixelUi.frame(rightFill, "Foes", 0, 11, RIGHT_W - 2, DOCK_H - 13)
	local foeName = PixelUi.label(foesBody, "Name", 2, 0, 86, 8, "", Colors.Text)
	local foeLevel = PixelUi.label(foesBody, "Level", 60, 0, 28, 8, "", Colors.TextDim, Enum.TextXAlignment.Right)
	local foeHpOuter, setFoeHp = PixelUi.bar(foesBody, "Hp", 2, 8, 86, 4, Colors.Hp, Colors.HpBack)
	local foeHpText = PixelUi.label(foesBody, "HpText", 2, 12, 86, 8, "", Colors.Text, Enum.TextXAlignment.Right)
	local foeStatus = PixelUi.label(foesBody, "Status", 2, 12, 60, 8, "", Colors.TextDim)
	local nextBox, nextFill = PixelUi.box(foesBody, "Next", 1, 21, 88, 19, Night.Banner)
	nextBox.BackgroundColor3 = Colors.Heavy
	local nextLine1 = PixelUi.label(nextFill, "Line1", 1, 0, 84, 9, "", Colors.Heavy)
	local nextLine2 = PixelUi.label(nextFill, "Line2", 1, 8, 84, 9, "", Colors.Text)
	local _ = foeHpOuter

	local partyBody = PixelUi.frame(rightFill, "Party", 0, 11, RIGHT_W - 2, DOCK_H - 13)
	type PartyView = { name: TextLabel, hp: TextLabel, setHp: (number) -> () }
	local partyViews: { PartyView } = {}
	for i = 1, 2 do
		local y = (i - 1) * 12
		local name = PixelUi.label(partyBody, `Name{i}`, 2, y, 64, 8, "", Colors.Text)
		local hp = PixelUi.label(partyBody, `Hp{i}`, 62, y, 26, 8, "", Colors.TextDim, Enum.TextXAlignment.Right)
		local _outer, setHp = PixelUi.bar(partyBody, `HpBar{i}`, 2, y + 8, 86, 3, Colors.Active, Colors.HpBack)
		table.insert(partyViews, { name = name, hp = hp, setHp = setHp })
	end
	type TacticView = { fill: Frame, label: TextLabel, button: TextButton }
	local tacticButtons: { [TacticMode]: TacticView } = {}
	for i, mode in TACTICS do
		local box, fill, label = chip(partyBody, mode, 1 + (i - 1) * 30, 24, 29, 9, TACTIC_SHORT[mode], Colors.PanelLight)
		local button = PixelUi.button(box, "Press", 0, 0, 29, 9, "")
		tacticButtons[mode] = { fill = fill, label = label, button = button }
	end
	local redirectBox, redirectFill, redirectLabel = chip(partyBody, "Redirect", 1, 33, 88, 9, "SEC: REDIRECT 1/1", Night.Select)
	local redirectButton = PixelUi.button(redirectBox, "Press", 0, 0, 88, 9, "")

	-- QTE, dead centre of the arena -------------------------------------------------
	local qtePanel, qteFill = PixelUi.box(hud, "Qte", 60, 30, 200, 84, Colors.Panel)
	qtePanel.BackgroundColor3 = Night.Gold
	qtePanel.ZIndex = 6
	qtePanel.Visible = false
	local qteTitle = PixelUi.label(qteFill, "Title", 4, 1, 190, 9, "", Colors.Victory, Enum.TextXAlignment.Center)
	local qteModeHint = PixelUi.label(qteFill, "Mode", 4, 10, 190, 9, "", Colors.TextDim, Enum.TextXAlignment.Center)
	type CheckBox = { outline: Frame, fill: Frame, label: TextLabel }
	local qteChecks: { CheckBox } = {}
	for i = 1, 3 do
		local outline, fill, label = chip(qteFill, `Check{i}`, 0, 21, 38, 13, `{i}`, Colors.PanelLight)
		table.insert(qteChecks, { outline = outline, fill = fill, label = label })
	end
	local qtePromptLabel = PixelUi.label(qteFill, "Prompt", 4, 37, 190, 10, "", Colors.Text, Enum.TextXAlignment.Center)
	type ChoiceButton = { box: Frame, fill: Frame, label: TextLabel, button: TextButton }
	local qteChoiceButtons: { ChoiceButton } = {}
	for i, input in QTE_CHOICES do
		local box, fill, label = chip(qteFill, input, 6 + (i - 1) * 63, 58, 60, 18, string.upper(input), Colors.Button)
		local button = PixelUi.button(box, "Press", 0, 0, 60, 18, "")
		table.insert(qteChoiceButtons, { box = box, fill = fill, label = label, button = button })
	end

	-- Manual ring: a fixed target ring and an approach ring that closes on it.
	local function circle(parent: Instance, name: string, color: Color3): (Frame, UIStroke)
		local ring = PixelUi.frame(parent, name, 0, 0, RING_TARGET, RING_TARGET)
		ring.AnchorPoint = Vector2.new(0.5, 0.5)
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = ring
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 1
		stroke.Color = color
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = ring
		return ring, stroke
	end
	local ringArea = PixelUi.frame(qteFill, "Ring", 59, 19, 80, 62)
	ringArea.ClipsDescendants = true
	local ringTarget, ringTargetStroke = circle(ringArea, "Target", Colors.Text)
	ringTarget.Position = UDim2.fromOffset(40, 31)
	local ringApproach, ringApproachStroke = circle(ringArea, "Approach", Colors.Victory)
	ringApproach.Position = UDim2.fromOffset(40, 31)
	ringApproachStroke.Thickness = 2
	local ringCount = PixelUi.label(qteFill, "RingCount", 142, 30, 54, 9, "", Colors.Text)
	local ringHint = PixelUi.label(qteFill, "RingHint", 142, 44, 54, 9, "", Colors.TextDim)

	-- While a Manual ring is up, this invisible layer takes every click or tap
	-- on the HUD so it counts as one Confirm instead of pressing a button.
	local confirmCatcher = PixelUi.button(hud, "QteConfirm", 0, 0, PixelUi.NATIVE_WIDTH, PixelUi.NATIVE_HEIGHT, "")
	confirmCatcher.ZIndex = 9
	confirmCatcher.Visible = false

	-- Arena overlays ----------------------------------------------------------------
	local fullLog = PixelUi.box(hud, "FullLog", 20, 16, 280, 108, Colors.Panel)
	fullLog.ZIndex = 8
	fullLog.Visible = false
	PixelUi.label(fullLog, "Title", 6, 2, 200, 9, "COMBAT LOG  (TAP TO CLOSE)", Colors.Victory)
	local fullLogLines: { TextLabel } = {}
	for i = 1, FULL_LOG_LINES do
		table.insert(fullLogLines, PixelUi.label(fullLog, `Line{i}`, 6, 11 + (i - 1) * 8, 268, 8, "", Colors.Text))
	end
	local closeLog = PixelUi.button(fullLog, "Close", 0, 0, 280, 108, "")

	local nightBanner = PixelUi.box(hud, "NightBanner", 60, 46, 200, 30, Night.Tag)
	nightBanner.ZIndex = 5
	nightBanner.Visible = false
	PixelUi.label(nightBanner, "Title", 0, 3, 200, 12, "NIGHT", Night.Moon, Enum.TextXAlignment.Center)
	PixelUi.label(nightBanner, "Sub", 0, 16, 200, 10, "Black Sabbath hunts in the shadows.", Colors.Text, Enum.TextXAlignment.Center)

	local pop, popFill, popLabel = chip(hud, "Feedback", 80, 98, 160, 14, "", Colors.Ink)
	pop.ZIndex = 5
	pop.Visible = false
	local popToken = 0

	local banner = PixelUi.box(hud, "OutcomeBanner", 70, 34, 180, 60, Colors.Panel)
	banner.ZIndex = 9
	banner.Visible = false
	local bannerTitle = PixelUi.label(banner, "Title", 0, 6, 180, 12, "", Colors.Victory, Enum.TextXAlignment.Center)
	local bannerSub = PixelUi.label(banner, "Subtitle", 6, 20, 168, 10, "", Colors.TextDim, Enum.TextXAlignment.Center)
	local bannerButtonBox, _bannerButtonFill, bannerButtonLabel = chip(banner, "ButtonBox", 40, 36, 100, 16, "FIGHT AGAIN", Colors.Button)
	local bannerButton = PixelUi.button(bannerButtonBox, "Button", 0, 0, 100, 16, "")

	local toastBox = PixelUi.box(hud, "Toast", 40, 36, 240, 14, Colors.PanelLight)
	toastBox.ZIndex = 10
	toastBox.Visible = false
	local toastLabel = PixelUi.label(toastBox, "Text", 4, 1, 232, 12, "", Colors.Text, Enum.TextXAlignment.Center)
	local toastToken = 0

	-- State ----------------------------------------------------------------------
	local fighters: { [string]: FighterView } = {}
	local lastSnapshot: Snapshot? = nil
	local lastLogCount = 0
	local busy = false
	local nightShownFor: string? = nil
	local menu: MenuEntry = "Attack"
	-- What the centre pane shows on top of the menu entry: a belt item's targets
	-- or the Guard Redirect targets.
	local centerMode: "Menu" | "ItemTargets" | "Redirect" = "Menu"
	local selectedItem: CombatTypes.BeltItemId? = nil
	local rightTab: "Party" | "Foes" = "Foes"
	local menuActorKey: string? = nil
	local hoverNote: string? = nil

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

	local function activeParty(snapshot: Snapshot): Actor?
		for _, actor in snapshot.actors do
			if actor.id == snapshot.activeActorId and actor.team == "Player" then
				return actor
			end
		end
		return nil
	end

	local function optionFor(snapshot: Snapshot, moveId: string): PrimaryOption?
		for _, option in snapshot.primaryOptions do
			if option.moveId == moveId then
				return option
			end
		end
		return nil
	end

	local function skillOptions(snapshot: Snapshot): { PrimaryOption }
		local list: { PrimaryOption } = {}
		for _, option in snapshot.primaryOptions do
			if option.moveId ~= "BasicStrike" and option.moveId ~= "Defend" then
				table.insert(list, option)
			end
		end
		return list
	end

	-- A fighter with no usable Primary (Stunned, or only a spent Bonus) skips with
	-- End Turn; everyone else ends the turn by taking a Primary.
	local function canSkip(snapshot: Snapshot): boolean
		if not snapshot.endTurnLegality.canUse then
			return false
		end
		for _, option in snapshot.primaryOptions do
			if option.legality.canUse then
				return false
			end
		end
		return true
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

	local function usePrimary(option: PrimaryOption?)
		if busy or not option then
			return
		end
		if not option.legality.canUse then
			toast(reasonOf(option.legality))
			return
		end
		callbacks.onPrimary(option, pickTarget(option))
	end

	-- Stage ----------------------------------------------------------------------
	local function renderStage(snapshot: Snapshot)
		local night = snapshot.stageTag == "Night"
		local key = snapshot.stageAssetKey or "BlackSabbathStage"
		local drawnKey = `{key}:{night}`
		if stageNight == drawnKey then
			return
		end
		stageNight = drawnKey
		stageLayer:ClearAllChildren()
		local id = (AssetManifest :: any)[key]
		if type(id) == "string" and id ~= PixelUi.UNSET_ASSET then
			PixelUi.image(stageLayer, "Stage", 0, 0, PixelUi.NATIVE_WIDTH, ARENA_H, id)
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
		local look = if actor.spriteKey == "PlayerIdle" then callbacks.playerAppearance else nil
		local sprite = FighterSprite.create(holder, actor.spriteKey, facingLeft, look)
		local flash = PixelUi.frame(holder, "HitFlash", 34, 28, 28, 60, Colors.Hp)
		flash.BackgroundTransparency = 1

		-- Small plate over the head: name, HP bar, HP + Stamina pips, Resolve.
		local plateX = (96 - PLATE_W) // 2 - 1
		local plateOutline, plate = PixelUi.box(holder, "Plate", plateX, -6, PLATE_W + 2, 25, Colors.Panel)
		plateOutline.ZIndex = 2
		local nameLabel = PixelUi.label(plate, "Name", 0, 0, PLATE_W, 8, "", Colors.Text, Enum.TextXAlignment.Center)
		local _, setHp = PixelUi.bar(plate, "Hp", 0, 8, PLATE_W, 4, Colors.Hp, Colors.HpBack)
		local hpText = PixelUi.label(plate, "HpText", 1, 12, 30, 8, "", Colors.Text)
		local pipRow = PixelUi.frame(plate, "Stamina", 30, 14, 20, 3)
		local resolveOuter, setResolve = PixelUi.bar(plate, "Resolve", 0, 20, PLATE_W, 3, Night.Resolve, Night.ResolveBack)
		local statusRow = PixelUi.frame(holder, "Statuses", plateX, 19, PLATE_W + 2, 8)
		statusRow.ZIndex = 2
		-- Active-fighter marker beside the plate.
		local marker = PixelUi.frame(holder, "Marker", plateX - 4, 0, 3, 7, Colors.Victory)
		marker.ZIndex = 2

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
			marker = marker,
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
			-- Fit up to 20 px: 3 px pips with a 1 px gap, narrower if needed.
			local step = if maxPips > 0 then math.max(2, math.min(4, (20 + 1) // maxPips)) else 4
			local width = maxPips * step - 1
			view.pipRow.Position = UDim2.fromOffset(PLATE_W - width, 14)
			-- No Stamina (Black Sabbath): give the HP text the whole plate.
			view.hpText.Size = UDim2.fromOffset(if maxPips > 0 then PLATE_W - width - 2 else PLATE_W - 2, 8)
			for i = 1, maxPips do
				table.insert(view.pips, PixelUi.frame(view.pipRow, `Pip{i}`, (i - 1) * step, 0, step - 1, 3, Colors.StaminaBack))
			end
		end
		for i, pip in view.pips do
			pip.BackgroundColor3 = if i <= actor.stamina then Colors.Guard else Colors.StaminaBack
		end
	end

	local function renderStatuses(view: FighterView, actor: Actor)
		view.statusRow:ClearAllChildren()
		for index, status in actor.statuses do
			if index > 2 then
				break
			end
			local code = STATUS_SHORT[status.id] or string.upper(string.sub(status.id, 1, 3))
			local color = if status.id == "Exposed" then Colors.Victory
				elseif status.id == "Fade" then Night.Shadow
				elseif status.id == "Stun" then Colors.Defeat
				else Colors.PanelLight
			local outline, _fill, label = chip(view.statusRow, status.id, (index - 1) * 26, 0, 25, 8, code, color)
			-- Removable statuses get a green outline so cures are easy to spot.
			outline.BackgroundColor3 = if status.isRemovable then Night.Removable else Colors.Ink
			label.TextColor3 = if status.id == "Exposed" then Colors.Ink else Colors.Text
			local press = PixelUi.button(outline, "Press", 0, 0, 25, 8, "")
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
			view.marker.Visible = active and snapshot.outcome == "InProgress"
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

	-- Arena corners + intent banner ---------------------------------------------------
	local function grabState(snapshot: Snapshot): (boolean, boolean)
		local step = snapshot.blackSabbathStep
		local grabStep = step == "ShadowGrabWindup" or step == "ShadowGrabLanding"
		local grabLive = false
		for _, intent in snapshot.enemyIntents do
			if intent.moveId == "ShadowGrab" then
				grabLive = true
			end
		end
		return grabStep, grabLive
	end

	local function renderCorners(snapshot: Snapshot)
		local night = snapshot.stageTag == "Night"
		local tag = snapshot.stageTag or "Neutral"
		stageLabel.Text = `{STAGE_TEXT[tag] or string.upper(tag)} - TURN {snapshot.turn}`
		stageFill.BackgroundColor3 = if night then Night.Tag else Colors.PanelLight
		local step = snapshot.blackSabbathStep
		local waves = snapshot.waveCount
		-- Act fights show the wave in the second corner chip. The sandbox shows
		-- the Black Sabbath step there.
		stepBox.Visible = step ~= nil or (waves ~= nil and waves > 1)
		if step == nil then
			stepLabel.Text = if waves and waves > 1 then `WAVE {snapshot.waveIndex or 1}/{waves}` else ""
			stepFill.BackgroundColor3 = Colors.Panel
		end
		local retreat = snapshot.retreatLegality
		retreatBox.Visible = callbacks.onRetreat ~= nil and retreat ~= nil and snapshot.outcome == "InProgress"
		if retreat then
			local armed = retreatArmed > os.clock()
			retreatLabel.Text = if armed then "SURE?" else "RETREAT"
			retreatFill.BackgroundColor3 = if armed then Colors.Heavy elseif retreat.canUse and not busy then Colors.Panel else Colors.Disabled
			retreatLabel.TextColor3 = if retreat.canUse and not busy then Colors.Text else Colors.TextDim
		end
		for i, line in fullLogLines do
			local event = snapshot.log[#snapshot.log - FULL_LOG_LINES + i]
			line.Text = if event then `T{event.turn}  {event.message}` else ""
		end
		if step == nil then
			return
		end
		local grabStep, grabLive = grabState(snapshot)
		-- A UV Flash or Hamon Interrupt removes the grab intent; say so instead of
		-- still warning that it is about to land.
		local grabBroken = grabStep and not grabLive
		stepLabel.Text = if grabBroken then "GRAB BROKEN" else STEP_TEXT[step] or step
		stepFill.BackgroundColor3 = if grabBroken then Colors.Panel
			elseif step == "ShadowGrabWindup" then Night.Shadow
			elseif step == "ShadowGrabLanding" then Colors.Heavy
			else Colors.Panel
	end

	local function intentTexts(snapshot: Snapshot, intent: Intent): (string, string)
		local when = if intent.landingTurn <= snapshot.turn then "NOW" else `T{intent.landingTurn}`
		local verb = if intent.stage == "Windup" then "LANDS" elseif intent.stage == "Landing" then "LANDING" else "HITS"
		local line1 = `INTENT: {string.upper(intent.label)} ({verb} {when})`
		if #line1 > 33 then
			-- Long move names: drop the prefix so the timing stays readable.
			line1 = `{string.upper(intent.label)} ({verb} {when})`
		end
		local parts: { string } = {}
		if intent.targetId == intent.actorId then
			table.insert(parts, "Self")
		else
			local who = if intent.targeting == "Party" then "PARTY" else shortName(snapshot, intent.targetId)
			table.insert(parts, `Target: {who}`)
		end
		if intent.estimatedPower > 0 then
			table.insert(parts, `PWR {math.round(intent.estimatedPower)}`)
		end
		if intent.uvCancelable then
			table.insert(parts, "UV")
		end
		if intent.offensiveInterruptible then
			table.insert(parts, "INT")
		end
		return line1, table.concat(parts, " - ")
	end

	local function renderIntent(snapshot: Snapshot, actors: { [string]: Actor })
		local intent: Intent? = snapshot.enemyIntents[1]
		if intent and snapshot.outcome == "InProgress" then
			local color = if intent.telegraphKind == "Heavy" then Colors.Heavy
				elseif intent.telegraphKind == "Guard" then Night.Shadow
				else Colors.Attack
			intentBox.Visible = true
			local line1, line2 = intentTexts(snapshot, intent)
			intentLine1.Text = line1
			intentLine1.TextColor3 = if intent.telegraphKind == "Heavy" then Colors.Victory else color
			intentLine2.Text = line2
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
			local turns = if fade.turnsRemaining then ` {fade.turnsRemaining}T` else ""
			fadeLabel.Text = `FADE +20 DODGE{turns}`
		end
	end

	-- Dock: left menu ---------------------------------------------------------------
	local renderDock: (snapshot: Snapshot) -> ()

	local function rerender()
		local snapshot = lastSnapshot
		if snapshot then
			renderDock(snapshot)
		end
	end

	for _, entry in MENU_ORDER do
		local view = menuViews[entry]
		view.button.Activated:Connect(function()
			local snapshot = lastSnapshot
			if busy or not snapshot then
				return
			end
			if entry == "Guard" and canSkip(snapshot) then
				callbacks.onEndTurn()
				return
			end
			if menu == entry and centerMode == "Menu" and (entry == "Attack" or entry == "Guard") then
				-- Second press on ATTACK / GUARD confirms, like the USE button.
				usePrimary(optionFor(snapshot, if entry == "Attack" then "BasicStrike" else "Defend"))
				return
			end
			menu = entry
			centerMode = "Menu"
			selectedItem = nil
			rerender()
		end)
	end

	local function renderMenu(snapshot: Snapshot, actor: Actor?)
		local live = snapshot.outcome == "InProgress"
		if actor then
			actorLabel.Text = shortName(snapshot, actor.id)
			actorLabel.TextColor3 = Colors.Active
			staLabel.Text = `{actor.stamina}/{actor.maxStamina}`
		elseif live then
			actorLabel.Text = shortName(snapshot, snapshot.activeActorId)
			actorLabel.TextColor3 = Colors.Heavy
			staLabel.Text = ""
		else
			actorLabel.Text = ""
			staLabel.Text = ""
		end
		local skip = canSkip(snapshot)
		for _, entry in MENU_ORDER do
			local view = menuViews[entry]
			local selected = menu == entry and actor ~= nil
			local text = string.upper(entry)
			local extra = ""
			local usable = actor ~= nil and not busy
			if entry == "Attack" then
				local option = optionFor(snapshot, "BasicStrike")
				usable = usable and option ~= nil and option.legality.canUse
			elseif entry == "Skills" then
				local any = false
				for _, option in skillOptions(snapshot) do
					any = any or option.legality.canUse
				end
				usable = usable and #snapshot.primaryOptions > 0
				extra = if any then "" else "-"
			elseif entry == "Guard" then
				if skip then
					text = "SKIP TURN"
				else
					local option = optionFor(snapshot, "Defend")
					usable = usable and option ~= nil and option.legality.canUse
				end
			else
				extra = `x{snapshot.belt.beltChargesRemaining}`
			end
			view.label.Text = if selected then `> {text}` else `  {text}`
			view.extra.Text = extra
			view.fill.BackgroundColor3 = if selected then Night.Select else Night.Dock
			view.label.TextColor3 = if usable then Colors.Text else Colors.TextDim
			view.extra.TextColor3 = if snapshot.belt.beltChargesRemaining > 0 then Colors.TextDim else Colors.Defeat
		end
		qteModeLabel.Text = `QTE: [{QTE_MODE_TEXT[snapshot.qteMode] or snapshot.qteMode}]`
		local canToggle = not busy and not qteActive() and live
		qteModeLabel.TextColor3 = if canToggle then Colors.TextDim else Colors.Disabled
	end

	-- Dock: centre pane ---------------------------------------------------------------
	local rowActions: { [Row]: () -> () } = {}
	local function bindRow(row: Row, action: (() -> ())?)
		rowActions[row] = action :: any
	end
	for _, row in skillRows do
		row.button.Activated:Connect(function()
			local action = rowActions[row]
			if action and not busy then
				action()
			end
		end)
	end
	for _, row in targetRows do
		row.button.Activated:Connect(function()
			local action = rowActions[row]
			if action and not busy then
				action()
			end
		end)
	end

	local function grabWarning(snapshot: Snapshot): string
		local intent = snapshot.enemyIntents[1]
		if not intent or snapshot.outcome ~= "InProgress" then
			return ""
		end
		if intent.offensiveInterruptible or intent.uvCancelable then
			return "WINDUP: GUARD / INT / UV!"
		end
		if intent.stage == "Landing" then
			return `{string.upper(intent.label)} LANDS NOW!`
		end
		return ""
	end

	local function oddsText(option: PrimaryOption): string
		local parts: { string } = {}
		local target = option.targets[1]
		if target then
			table.insert(parts, `HIT {target.hitIfExecutedPercent}%`)
			if target.interruptIfExecutedPercent then
				table.insert(parts, `INT {target.interruptIfExecutedPercent}%`)
			end
		end
		if option.qte == "HighRiskThreeCheck" then
			table.insert(parts, "3 CHECKS")
		elseif option.qte == "Standard" then
			table.insert(parts, "1 CHECK")
		end
		if option.effectiveQteMode then
			table.insert(parts, `QTE {QTE_MODE_TEXT[option.effectiveQteMode] or option.effectiveQteMode}`)
		end
		return table.concat(parts, "  ")
	end

	local function showBody(which: Frame)
		detailBody.Visible = which == detailBody
		skillsBody.Visible = which == skillsBody
		beltBody.Visible = which == beltBody
		targetBody.Visible = which == targetBody
		-- Target rows put BACK where the tag goes, so the title can run longer.
		centerTitle.Size = UDim2.fromOffset(if which == targetBody then 118 else 70, 9)
	end

	local function slotTag(option: PrimaryOption): string
		local slot = if option.slot == "BonusPrimary" then "BONUS" else "PRI"
		return `{slot} {option.staminaCost}STA ENDS TURN`
	end

	local function renderDetail(snapshot: Snapshot, moveId: string)
		showBody(detailBody)
		local option = optionFor(snapshot, moveId)
		centerTitle.Text = MOVE_NAME[moveId] or moveId
		if not option then
			centerTag.Text = ""
			detailText.Text = "Waiting for your turn."
			detailOdds.Text = ""
			warnBox.Visible = false
			useBox.Visible = false
			return
		end
		centerTag.Text = slotTag(option)
		centerTag.TextColor3 = if option.slot == "BonusPrimary" then Colors.Victory else Colors.Active
		detailText.Text = MOVE_BLURB[moveId] or option.label
		if option.legality.canUse then
			detailOdds.Text = `{TAG_SHORT[option.scalingTag] or ""} {oddsText(option)}`
			detailOdds.TextColor3 = Colors.TextDim
		else
			detailOdds.Text = reasonOf(option.legality)
			detailOdds.TextColor3 = Colors.Heavy
		end
		local warning = grabWarning(snapshot)
		warnBox.Visible = warning ~= ""
		warnLabel.Text = warning
		useBox.Visible = true
		local usable = option.legality.canUse and not busy
		useFill.BackgroundColor3 = if usable then Colors.Button else Colors.Disabled
		useLabel.TextColor3 = if usable then Colors.Text else Colors.TextDim
	end

	local function renderSkills(snapshot: Snapshot)
		showBody(skillsBody)
		local actor = activeParty(snapshot)
		local _ = actor
		centerTitle.Text = "SKILLS"
		centerTag.Text = hoverNote or "PRI - ENDS TURN"
		centerTag.TextColor3 = if hoverNote then Colors.Heavy else Colors.Active
		local list = skillOptions(snapshot)
		for i, row in skillRows do
			local option = list[i]
			row.box.Visible = option ~= nil
			if option then
				local usable = option.legality.canUse and not busy
				local finisher = option.moveId == "Finisher" and option.legality.canUse
				row.cells[1].Text = MOVE_NAME[option.moveId] or option.label
				row.cells[2].Text = if option.staminaCost > 0 then `{option.staminaCost}ST` else "-"
				row.cells[3].Text = TAG_SHORT[option.scalingTag] or ""
				local note = if option.legality.canUse
					then (if option.qte == "HighRiskThreeCheck" then "3 CHECKS"
						elseif option.qte == "Standard" then "1 CHECK"
						else (option.targets[1] and `HIT {option.targets[1].hitIfExecutedPercent}%` or ""))
					else "LOCKED"
				row.cells[4].Text = note
				row.fill.BackgroundColor3 = if finisher then Night.Fire elseif usable then Night.Dock else Night.Dock
				row.box.BackgroundColor3 = if finisher then Colors.Victory elseif usable then Night.Select else Night.Dock
				for c, cell in row.cells do
					cell.TextColor3 = if not usable then Colors.TextDim
						elseif c == 2 then Colors.Guard
						elseif c == 3 then Colors.Victory
						else Colors.Text
				end
				bindRow(row, function()
					local current = lastSnapshot
					usePrimary(if current then optionFor(current, option.moveId) else nil)
				end)
			else
				bindRow(row, nil)
			end
		end
	end

	local function renderBelt(snapshot: Snapshot)
		showBody(beltBody)
		local belt = snapshot.belt
		local limits = CombatTypes.Phase2Limits
		centerTitle.Text = "BELT - SECONDARY"
		centerTag.Text = `CHG {belt.beltChargesRemaining}/{limits.PartyBeltCharges} HEAL {belt.directHealsRemaining}/{limits.DirectHealsPerFight}`
		centerTag.TextColor3 = if belt.beltChargesRemaining > 0 then Colors.Active else Colors.Defeat
		for i, tile in beltTiles do
			local item = belt.items[i]
			tile.box.Visible = item ~= nil
			if item then
				local usable = item.legality.canUse and not busy
				local assetId = (AssetManifest :: any)[`{item.itemId}Icon`]
				local hasIcon = type(assetId) == "string" and assetId ~= PixelUi.UNSET_ASSET
				tile.icon.Visible = hasIcon
				if hasIcon then
					tile.icon.Image = assetId
				end
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

	local function setTargetRow(row: Row, text: string, legality: Legality, onUse: () -> ())
		row.box.Visible = true
		local usable = legality.canUse and not busy
		row.cells[1].Text = text
		row.cells[1].TextColor3 = if usable then Colors.Text else Colors.TextDim
		row.cells[2].Text = if legality.canUse then "> USE" else reasonOf(legality)
		row.cells[2].TextColor3 = if legality.canUse then Colors.Active else Colors.Heavy
		row.box.BackgroundColor3 = if usable then Night.Select else Night.Dock
		bindRow(row, function()
			if legality.canUse then
				centerMode = "Menu"
				selectedItem = nil
				onUse()
			else
				toast(reasonOf(legality))
			end
		end)
	end

	local function renderTargets(snapshot: Snapshot)
		showBody(targetBody)
		for _, row in targetRows do
			row.box.Visible = false
			bindRow(row, nil)
		end
		if centerMode == "ItemTargets" then
			local item: BeltItemView? = nil
			for _, candidate in snapshot.belt.items do
				if candidate.itemId == selectedItem then
					item = candidate
				end
			end
			if not item then
				centerMode = "Menu"
				renderBelt(snapshot)
				return
			end
			centerTitle.Text = `{string.upper(item.label)} x{item.stock}`
			centerTag.Text = "" -- BACK sits here
			centerTag.TextColor3 = Colors.Guard
			targetTip.Text = if item.itemId == "UVFlash" then UV_TOOLTIP
				elseif item.legality.canUse then "Pick who gets it:"
				else reasonOf(item.legality)
			targetTip.TextColor3 = if item.legality.canUse or item.itemId == "UVFlash" then Colors.Victory else Colors.Heavy
			for i, preview in item.targets do
				local row = targetRows[i]
				if not row then
					break
				end
				local itemId = item.itemId
				local targetId = preview.targetId
				local text = if preview.summary ~= "" then `{shortName(snapshot, targetId)}: {preview.summary}` else shortName(snapshot, targetId)
				setTargetRow(row, text, preview.legality, function()
					callbacks.onBeltItem(itemId, targetId)
				end)
			end
		else
			local companion = snapshot.companion
			local redirect = companion and companion.redirect
			if not redirect then
				centerMode = "Menu"
				return
			end
			local limit = CombatTypes.Phase2Limits.CompanionRedirectsPerFight
			centerTitle.Text = `REDIRECT {redirect.usesRemaining}/{limit}`
			centerTag.Text = "" -- BACK sits here
			centerTag.TextColor3 = Colors.Guard
			local intentName = "the attack"
			for _, intent in snapshot.enemyIntents do
				if intent.id == redirect.intentId then
					intentName = string.upper(intent.label)
				end
			end
			targetTip.Text = if redirect.legality.canUse
				then `{intentName} -> {shortName(snapshot, redirect.originalTargetId)}. Who takes it?`
				else reasonOf(redirect.legality)
			targetTip.TextColor3 = if redirect.legality.canUse then Colors.Victory else Colors.Heavy
			local intentId = redirect.intentId
			for i, target in redirect.targets do
				local row = targetRows[i]
				if not row then
					break
				end
				local recipientId = target.recipientId
				local guard = if target.recipientIsDefending then "GUARDING" else "NOT GUARDING"
				setTargetRow(row, `{shortName(snapshot, recipientId)} ({guard})`, target.legality, function()
					callbacks.onRedirect(intentId, recipientId)
				end)
			end
		end
	end

	local function renderCenter(snapshot: Snapshot)
		if snapshot.outcome ~= "InProgress" then
			showBody(detailBody)
			centerTitle.Text = if snapshot.outcome == "Victory" then "VICTORY"
				elseif snapshot.outcome == "Retreated" then "RETREATED"
				else "DEFEAT"
			centerTag.Text = ""
			detailText.Text = "The fight is over."
			detailOdds.Text = ""
			warnBox.Visible = false
			useBox.Visible = false
			return
		end
		if centerMode ~= "Menu" then
			renderTargets(snapshot)
			if centerMode ~= "Menu" then
				return
			end
		end
		if menu == "Attack" then
			renderDetail(snapshot, "BasicStrike")
		elseif menu == "Guard" then
			if canSkip(snapshot) then
				showBody(detailBody)
				centerTitle.Text = "SKIP TURN"
				centerTag.Text = ""
				local actor = activeParty(snapshot)
				local stunned = false
				if actor then
					for _, status in actor.statuses do
						stunned = stunned or status.id == "Stun"
					end
				end
				detailText.Text = if stunned
					then "Stunned: no Primary this turn. Use your Secondary, then skip."
					else "No Primary left this turn. Skip to the next fighter."
				detailOdds.Text = ""
				warnBox.Visible = false
				useBox.Visible = true
				useFill.BackgroundColor3 = if busy then Colors.Disabled else Colors.Button
				useLabel.TextColor3 = if busy then Colors.TextDim else Colors.Text
			else
				renderDetail(snapshot, "Defend")
			end
		elseif menu == "Skills" then
			renderSkills(snapshot)
		else
			renderBelt(snapshot)
		end
	end

	useButton.Activated:Connect(function()
		local snapshot = lastSnapshot
		if busy or not snapshot then
			return
		end
		if menu == "Guard" and canSkip(snapshot) then
			callbacks.onEndTurn()
			return
		end
		usePrimary(optionFor(snapshot, if menu == "Guard" then "Defend" else "BasicStrike"))
	end)

	for i, tile in beltTiles do
		tile.button.Activated:Connect(function()
			local snapshot = lastSnapshot
			local item = snapshot and snapshot.belt.items[i]
			if not item or busy then
				return
			end
			-- Always open the targets: they show the previews and why an item is locked.
			centerMode = "ItemTargets"
			selectedItem = item.itemId
			rerender()
		end)
	end

	backButton.Activated:Connect(function()
		centerMode = "Menu"
		selectedItem = nil
		rerender()
	end)

	for i, row in skillRows do
		row.button.MouseEnter:Connect(function()
			local snapshot = lastSnapshot
			local option = snapshot and skillOptions(snapshot)[i]
			if snapshot and option and not option.legality.canUse then
				hoverNote = reasonOf(option.legality)
				renderSkills(snapshot)
			end
		end)
		row.button.MouseLeave:Connect(function()
			if hoverNote then
				hoverNote = nil
				rerender()
			end
		end)
	end

	-- Dock: right pane ----------------------------------------------------------------
	local function renderSide(snapshot: Snapshot, actors: { [string]: Actor })
		local partyCount, foeCount = 0, 0
		local foe: Actor? = nil
		local party: { Actor } = {}
		for _, actor in snapshot.actors do
			if actor.team == "Player" then
				if actor.hp > 0 then
					partyCount += 1
				end
				table.insert(party, actor)
			elseif actor.hp > 0 or foe == nil then
				if actor.hp > 0 then
					foeCount += 1
				end
				foe = actor
			end
		end
		partyTabLabel.Text = `PARTY {partyCount}`
		foesTabLabel.Text = `FOES {foeCount}`
		local onParty = rightTab == "Party"
		partyTabFill.BackgroundColor3 = if onParty then Night.Select else Colors.PanelLight
		foesTabFill.BackgroundColor3 = if onParty then Colors.PanelLight else Colors.Heavy
		partyTabLabel.TextColor3 = if onParty then Colors.Text else Colors.TextDim
		foesTabLabel.TextColor3 = if onParty then Colors.TextDim else Colors.Text
		partyBody.Visible = onParty
		foesBody.Visible = not onParty

		-- Foes.
		if foe then
			foeName.Text = string.upper(foe.displayName)
			foeLevel.Text = ""
			setFoeHp(if foe.maxHp > 0 then foe.hp / foe.maxHp else 0)
			foeHpText.Text = `{foe.hp}/{foe.maxHp}`
			local codes: { string } = {}
			for _, status in foe.statuses do
				table.insert(codes, STATUS_SHORT[status.id] or status.id)
			end
			foeStatus.Text = if #codes > 0 then table.concat(codes, " ")
				elseif snapshot.stageTag == "Night" then "NIGHT"
				else ""
		end
		local intent = snapshot.enemyIntents[1]
		nextBox.Visible = intent ~= nil and snapshot.outcome == "InProgress"
		if intent then
			local when = if intent.landingTurn <= snapshot.turn then "NOW" else `T{intent.landingTurn}`
			nextLine1.Text = `{string.upper(intent.label)} {when}`
			local who = if intent.targetId == intent.actorId then "SELF" else shortName(snapshot, intent.targetId)
			local power = math.round(intent.estimatedPower)
			nextLine2.Text = if power > 0 then `NEXT > {who} PWR {power}` else `NEXT > {who}`
		end

		-- Party.
		local companion = snapshot.companion
		for i, view in partyViews do
			local actor = party[i]
			if actor then
				local name = shortName(snapshot, actor.id)
				if companion and actor.id == companion.actorId then
					name = `{name} [{TACTIC_SHORT[companion.tacticMode] or "?"}]`
				end
				view.name.Text = if actor.hp > 0 then name else `{name} DOWN`
				view.name.TextColor3 = if actor.id == snapshot.activeActorId then Colors.Active else Colors.Text
				view.hp.Text = `{actor.hp}/{actor.maxHp}`
				view.setHp(if actor.maxHp > 0 then actor.hp / actor.maxHp else 0)
			else
				view.name.Text = ""
				view.hp.Text = ""
				view.setHp(0)
			end
		end
		for mode, view in tacticButtons do
			local current = companion ~= nil and companion.tacticMode == mode
			local usable = companion ~= nil and companion.tacticLegality.canUse and not busy
			view.fill.BackgroundColor3 = if current then Colors.Active elseif usable then Colors.Button else Colors.PanelLight
			view.label.TextColor3 = if current then Colors.Ink elseif usable then Colors.Text else Colors.TextDim
		end
		local redirect = companion and companion.redirect
		local limit = CombatTypes.Phase2Limits.CompanionRedirectsPerFight
		if redirect then
			local usable = redirect.legality.canUse and not busy
			redirectLabel.Text = `SEC: REDIRECT {redirect.usesRemaining}/{limit}`
			redirectFill.BackgroundColor3 = if usable then Night.Select else Colors.Disabled
			redirectLabel.TextColor3 = if usable then Colors.Victory else Colors.TextDim
		else
			redirectLabel.Text = "SEC: REDIRECT -"
			redirectFill.BackgroundColor3 = Colors.Disabled
			redirectLabel.TextColor3 = Colors.TextDim
		end
		local _ = actors
	end

	partyTabButton.Activated:Connect(function()
		rightTab = "Party"
		rerender()
	end)
	foesTabButton.Activated:Connect(function()
		rightTab = "Foes"
		rerender()
	end)

	for mode, view in tacticButtons do
		view.button.Activated:Connect(function()
			local snapshot = lastSnapshot
			local companion = snapshot and snapshot.companion
			if busy or not companion or companion.tacticMode == mode then
				return
			end
			if not companion.tacticLegality.canUse then
				toast(reasonOf(companion.tacticLegality))
				return
			end
			callbacks.onTactic(mode)
		end)
	end

	redirectButton.Activated:Connect(function()
		local snapshot = lastSnapshot
		local companion = snapshot and snapshot.companion
		if busy or not companion then
			return
		end
		if not companion.redirect then
			toast("No attack to redirect right now.")
			return
		end
		centerMode = "Redirect"
		selectedItem = nil
		rerender()
	end)

	function renderDock(snapshot: Snapshot)
		local actor = activeParty(snapshot)
		-- A new fighter's turn starts back on ATTACK.
		local key = if actor then `{snapshot.battleId}:{snapshot.turn}:{actor.id}` else nil
		if key ~= menuActorKey then
			menuActorKey = key
			-- A fighter who can only skip (for example Stunned) opens on SKIP TURN.
			menu = if actor and canSkip(snapshot) then "Guard" else "Attack"
			centerMode = "Menu"
			selectedItem = nil
			hoverNote = nil
		end
		renderMenu(snapshot, actor)
		renderCenter(snapshot)
		renderSide(snapshot, actorMap(snapshot))
	end

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
		if busy or not prompt or prompt.mode == "Manual" then
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

	-- One Confirm per gesture, and at most one per ring. Presses before the
	-- current ring appears (the reset gap) are ignored here; the server scores a
	-- press during the approach but before the window as a miss.
	local lastConfirmKey: string? = nil
	local function sendConfirm()
		local snapshot = lastSnapshot
		local prompt = snapshot and snapshot.qtePrompt
		if busy or not prompt or prompt.mode ~= "Manual" then
			return
		end
		local index, check = currentCheck(prompt)
		if index == nil or check == nil then
			return
		end
		if workspace:GetServerTimeNow() < check.approachStartsAtServerTime then
			return
		end
		local key = `{prompt.id}#{index}`
		if lastConfirmKey == key then
			return
		end
		lastConfirmKey = key
		callbacks.onQteInput(prompt.id, index, "Confirm")
	end
	confirmCatcher.Activated:Connect(sendConfirm)

	local function renderQte(snapshot: Snapshot)
		local prompt = snapshot.qtePrompt
		qtePanel.Visible = prompt ~= nil
		local manual = prompt ~= nil and prompt.mode == "Manual"
		confirmCatcher.Visible = manual and prompt ~= nil and prompt.nextCheckIndex ~= nil
		if not prompt then
			return
		end
		local count = #prompt.checks
		qteTitle.Text = if prompt.kind == "HighRiskThreeCheck" then "HIGH-RISK HEAVY  3 CHECKS" else "HEAVY STRIKE TIMING"
		qteModeHint.Text = if manual
			then "CLICK, TAP OR SPACE WHEN THE RINGS MEET"
			else "UNTIMED CUE: NO CLOCK, MATCH EACH CUE"
		local hits = 0
		for i, box in qteChecks do
			box.outline.Visible = i <= count
			if i <= count then
				-- Manual stacks the check boxes on the left of the ring.
				if manual then
					box.outline.Position = UDim2.fromOffset(6, 21 + (i - 1) * 18)
				else
					box.outline.Position = UDim2.fromOffset((198 - (count * 40 - 2)) // 2 + (i - 1) * 40, 21)
				end
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
		ringArea.Visible = manual
		ringHint.Visible = manual
		ringCount.Visible = manual
		qtePromptLabel.Visible = not manual
		for _, view in qteChoiceButtons do
			view.box.Visible = not manual
		end
		if manual then
			ringCount.Text = if index then `RING {index}/{count}` else `{hits}/{count} HIT`
			return
		end
		if index and check then
			qtePromptLabel.Text = `{check.prompt}   ({hits}/{count} so far)`
		else
			qtePromptLabel.Text = `{hits}/{count}`
		end
		local usable = not busy and index ~= nil
		for i, view in qteChoiceButtons do
			local input = QTE_CHOICES[i]
			local offered = check == nil or table.find(check.choices, input) ~= nil
			view.fill.BackgroundColor3 = if usable and offered then Colors.Button else Colors.Disabled
			view.label.TextColor3 = if usable and offered then Colors.Text else Colors.TextDim
		end
	end

	-- The ring animates on the server clock (workspace:GetServerTimeNow()) so it
	-- matches the timestamps the server scores against.
	table.insert(connections, RunService.Heartbeat:Connect(function()
		local snapshot = lastSnapshot
		local prompt = snapshot and snapshot.qtePrompt
		if not prompt or prompt.mode ~= "Manual" then
			return
		end
		local index, check = currentCheck(prompt)
		if not index or not check then
			ringTarget.Visible = false
			ringApproach.Visible = false
			ringHint.Text = "..."
			return
		end
		local t = workspace:GetServerTimeNow()
		local starts: number = check.approachStartsAtServerTime
		local overlap: number = check.overlapAtServerTime
		local opens: number = check.opensAtServerTime
		local closes: number = check.closesAtServerTime
		if t < starts then
			-- Reset gap: earlier results stay on the check boxes.
			ringTarget.Visible = false
			ringApproach.Visible = false
			ringHint.Text = if index == 1 then "GET READY" else "NEXT..."
			ringHint.TextColor3 = Colors.TextDim
			return
		end
		ringTarget.Visible = true
		ringApproach.Visible = true
		local progress = (overlap - t) / math.max(0.001, overlap - starts)
		local size = math.max(RING_MIN, math.round(RING_TARGET + (RING_START - RING_TARGET) * progress))
		ringApproach.Size = UDim2.fromOffset(size, size)
		-- Open from opensAt (inclusive) to closesAt (exclusive), like the server.
		local inWindow = t >= opens and t < closes
		ringTarget.BackgroundTransparency = if inWindow then 0.35 else 1
		ringTarget.BackgroundColor3 = Colors.Active
		ringTargetStroke.Color = if inWindow then Colors.Active else Colors.Text
		if inWindow then
			ringHint.Text = "NOW!"
			ringHint.TextColor3 = Colors.Active
		elseif t < opens then
			ringHint.Text = "WAIT..."
			ringHint.TextColor3 = Colors.Text
		else
			ringHint.Text = "TOO LATE"
			ringHint.TextColor3 = Night.Miss
		end
	end))

	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		local snapshot = lastSnapshot
		local prompt = snapshot and snapshot.qtePrompt
		if not prompt then
			return
		end
		local key = input.KeyCode
		if prompt.mode == "Manual" then
			-- Space is the keyboard Confirm. A focused HUD button can mark it as
			-- processed, so only a focused text box blocks it.
			if key == Enum.KeyCode.Space and UserInputService:GetFocusedTextBox() == nil then
				sendConfirm()
			end
			return
		end
		if processed then
			return
		end
		if key == Enum.KeyCode.A or key == Enum.KeyCode.Left then
			sendChoice("Left")
		elseif key == Enum.KeyCode.S or key == Enum.KeyCode.Down or key == Enum.KeyCode.Up then
			sendChoice("Center")
		elseif key == Enum.KeyCode.D or key == Enum.KeyCode.Right then
			sendChoice("Right")
		end
	end))

	-- QTE mode toggle ----------------------------------------------------------------
	qteModeButton.Activated:Connect(function()
		local snapshot = lastSnapshot
		if busy or not snapshot or snapshot.qtePrompt or snapshot.outcome ~= "InProgress" then
			return
		end
		local index = table.find(QTE_MODE_ORDER, snapshot.qteMode) or 0
		callbacks.onQteMode(QTE_MODE_ORDER[index % #QTE_MODE_ORDER + 1])
	end)

	-- Outcome ------------------------------------------------------------------------
	-- Set by an Act fight (for example "SAVING RESULTS..." and RETRY).
	local outcomeNote: { line: string?, button: string? }? = nil

	local function renderOutcome(snapshot: Snapshot)
		local outcome = snapshot.outcome
		if outcome == "Victory" then
			banner.Visible = true
			bannerTitle.Text = "VICTORY!"
			bannerTitle.TextColor3 = Colors.Victory
			bannerSub.Text = "Black Sabbath is driven off."
		elseif outcome == "Defeat" then
			banner.Visible = true
			bannerTitle.Text = "DEFEATED"
			bannerTitle.TextColor3 = Colors.Defeat
			bannerSub.Text = "The sandbox is safe to retry."
		elseif outcome == "Retreated" then
			banner.Visible = true
			bannerTitle.Text = "RETREATED"
			bannerTitle.TextColor3 = Colors.TextDim
			bannerSub.Text = ""
		else
			banner.Visible = false
		end
		local note = outcomeNote
		if note then
			bannerSub.Text = note.line or ""
			bannerButtonBox.Visible = note.button ~= nil
			if note.button then
				bannerButtonLabel.Text = note.button
			end
		else
			bannerButtonBox.Visible = true
		end
	end

	retreatButton.Activated:Connect(function()
		local snapshot = lastSnapshot
		local retreat = snapshot and snapshot.retreatLegality
		local onRetreat = callbacks.onRetreat
		if busy or not snapshot or not retreat or not onRetreat or snapshot.outcome ~= "InProgress" then
			return
		end
		if not retreat.canUse then
			toast(reasonOf(retreat))
			return
		end
		if retreatArmed < os.clock() then
			retreatArmed = os.clock() + 2
			toast("Press RETREAT again to leave the fight. No clear rewards.")
			renderCorners(snapshot)
			task.delay(2.05, function()
				local latest = lastSnapshot
				if latest then
					renderCorners(latest)
				end
			end)
			return
		end
		retreatArmed = 0
		onRetreat()
	end)

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
			menuActorKey = nil
			rightTab = "Foes"
		end
		lastSnapshot = snapshot

		renderStage(snapshot)
		renderCorners(snapshot)
		renderFighters(snapshot, actors)
		renderIntent(snapshot, actors)
		renderDock(snapshot)
		renderQte(snapshot)
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
			renderDock(snapshot)
			renderQte(snapshot)
		end
	end

	function self.toast(_self: CombatHudV2, message: string)
		toast(message)
	end

	function self.setMock(_self: CombatHudV2, isMock: boolean)
		mockBadge.Visible = isMock
	end

	function self.setOutcomeNote(_self: CombatHudV2, line: string?, button: string?)
		outcomeNote = { line = line, button = button }
		local snapshot = lastSnapshot
		if snapshot then
			renderOutcome(snapshot)
		end
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
