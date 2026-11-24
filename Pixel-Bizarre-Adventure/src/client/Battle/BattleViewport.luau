--!strict
-- The Build 1 tutorial battle screen, drawn on the native 320 x 180 grid.
--
-- It only displays what the server's CombatSnapshot says and reports button
-- presses back through callbacks. It never decides damage, legality or turn
-- order itself.
--
-- Layout (native pixels):
--   top-left      turn number and Speed queue
--   above the log server badge (shows MOCK SERVER while the stand-in is used)
--   middle        fighters on 96 x 96 canvases, feet on the floor at y = 140,
--                 each with a name / HP / Stamina plate and, for enemies, an
--                 intent badge naming the move, target, landing turn and power
--   bottom-left   Quick Strike / Heavy Strike / Defend with cost and a line
--                 that explains why a button is disabled
--   bottom-right  latest combat log lines (tap for the full log)
--   overlays      Victory / Defeat banner, Origin Select, toast messages

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatTypes = require(ReplicatedStorage.Shared.Contracts.CombatTypes)
local SaveTypes = require(ReplicatedStorage.Shared.Contracts.SaveTypes)
local AssetManifest = require(ReplicatedStorage.Shared.Contracts.AssetManifest)
local PixelUi = require(script.Parent.PixelUi)
local FighterSprite = require(script.Parent.FighterSprite)
local OriginSelect = require(script.Parent.OriginSelect)

type CombatSnapshot = CombatTypes.CombatSnapshot
type ActorState = CombatTypes.ActorState
type EnemyIntent = CombatTypes.EnemyIntent
type ActionOption = CombatTypes.ActionOption
type MoveId = CombatTypes.MoveId
type Profile = SaveTypes.Profile

local Colors = PixelUi.Colors

export type Callbacks = {
	onAction: (moveId: MoveId, targetId: string?) -> (),
	onRetry: () -> (),
	onChooseOrigin: (origin: SaveTypes.Origin) -> (),
	-- Optional: after the Origin is saved, the victory banner offers the
	-- Phase 2 Black Sabbath sandbox.
	onOpenSandbox: (() -> ())?,
}

type FighterView = {
	root: Frame,
	sprite: Frame,
	flash: Frame,
	nameLabel: TextLabel,
	setHp: (number) -> (),
	hpOuter: Frame,
	hpText: TextLabel,
	pips: { Frame },
	guardTag: Frame,
	intent: Frame,
	intentFill: Frame,
	intentLine1: TextLabel,
	intentLine2: TextLabel,
	hitbox: TextButton,
	displayName: string,
}

type ActionButtonView = {
	box: Frame,
	button: TextButton,
	fill: Frame,
	title: TextLabel,
	cost: TextLabel,
}

export type BattleViewport = {
	render: (self: BattleViewport, snapshot: CombatSnapshot, profile: Profile) -> (),
	setBusy: (self: BattleViewport, busy: boolean) -> (),
	toast: (self: BattleViewport, message: string) -> (),
	setMock: (self: BattleViewport, isMock: boolean) -> (),
	destroy: (self: BattleViewport) -> (),
}

local FLOOR_Y = 120
local FEET_Y = 140
local PLATE_W = 64
local INTENT_W = 88
local ACTION_ORDER: { MoveId } = { "QuickStrike", "HeavyStrike", "Defend" }
local LOG_LINES = 2
local FULL_LOG_LINES = 15

-- Where each fighter's 96 x 96 canvas sits. Player on the left facing right,
-- enemies on the right facing left. Extra enemies fall back to the last slot.
local PLAYER_SLOT_X = 30
local ENEMY_SLOTS_X = { 150, 214 }

local BattleViewport = {}

local function shortName(snapshot: CombatSnapshot, actorId: string?, actors: { [string]: ActorState }): string
	if actorId == nil then
		return "?"
	end
	if actorId == snapshot.playerActorId then
		return "YOU"
	end
	local actor = actors[actorId]
	if not actor then
		return string.upper(actorId)
	end
	-- Short label: "Dario Brando" -> DARIO, "Dario's Wife" -> WIFE (straight or curly apostrophe).
	local first = string.match(actor.displayName, "^%S+") or actor.displayName
	if string.sub(first, -2) == "'s" or string.sub(first, -4) == "\u{2019}s" then
		return string.upper(string.match(actor.displayName, "%S+$") or first)
	end
	return string.upper(first)
end

local function drawPlaceholderStage(parent: Frame)
	local stage = PixelUi.frame(parent, "Stage", 0, 0, PixelUi.NATIVE_WIDTH, PixelUi.NATIVE_HEIGHT, Colors.Sky)
	PixelUi.frame(stage, "SkyLow", 0, 70, PixelUi.NATIVE_WIDTH, FLOOR_Y - 70, Colors.SkyLow)
	PixelUi.frame(stage, "FloorEdge", 0, FLOOR_Y, PixelUi.NATIVE_WIDTH, 2, Colors.FloorEdge)
	PixelUi.frame(stage, "Floor", 0, FLOOR_Y + 2, PixelUi.NATIVE_WIDTH, PixelUi.NATIVE_HEIGHT - FLOOR_Y - 2, Colors.Floor)
	-- Rain streaks on a fixed pattern so the placeholder stays pixel-stable.
	for i = 0, 23 do
		local x = (i * 37 + 11) % PixelUi.NATIVE_WIDTH
		local y = (i * 53 + 7) % (FLOOR_Y - 8)
		PixelUi.frame(stage, `Rain{i}`, x, y, 1, 4, Colors.Rain)
	end
end

local function drawStage(parent: Frame)
	local id = AssetManifest.TutorialStage
	if id ~= PixelUi.UNSET_ASSET then
		PixelUi.image(parent, "Stage", 0, 0, PixelUi.NATIVE_WIDTH, PixelUi.NATIVE_HEIGHT, id)
	else
		drawPlaceholderStage(parent)
	end
end

function BattleViewport.new(screenGui: ScreenGui, callbacks: Callbacks): BattleViewport
	local root = PixelUi.integerScaledRoot(screenGui)
	drawStage(root)

	local fighterLayer = PixelUi.frame(root, "Fighters", 0, 0, PixelUi.NATIVE_WIDTH, PixelUi.NATIVE_HEIGHT)
	local hud = PixelUi.frame(root, "Hud", 0, 0, PixelUi.NATIVE_WIDTH, PixelUi.NATIVE_HEIGHT)
	hud.ZIndex = 2

	-- Turn and Speed queue -------------------------------------------------
	local queuePanel = PixelUi.box(hud, "TurnQueue", 4, 4, 200, 14, Colors.Panel)
	local turnLabel = PixelUi.label(queuePanel, "Turn", 3, 1, 40, 12, "TURN 1", Colors.Text)
	local queueChips: { Frame } = {}

	-- Server badge ---------------------------------------------------------
	local serverBadge = PixelUi.label(hud, "ServerBadge", 246, 30, 70, 10, "", Colors.Mock, Enum.TextXAlignment.Right)

	-- Action bar -----------------------------------------------------------
	local actionBar = PixelUi.box(hud, "Actions", 4, 146, 168, 30, Colors.Panel)
	local actionViews: { [MoveId]: ActionButtonView } = {}
	local reasonLabel = PixelUi.label(actionBar, "DisabledReason", 4, 19, 160, 9, "", Colors.TextDim)
	local hoveredReason: string? = nil
	local defaultReason = ""

	-- Combat log -----------------------------------------------------------
	local logPanel = PixelUi.box(hud, "Log", 176, 146, 140, 30, Colors.Panel)
	local logLines: { TextLabel } = {}
	for i = 1, LOG_LINES do
		local line = PixelUi.label(logPanel, `Line{i}`, 3, 1 + (i - 1) * 14, 134, 14, "", Colors.Text)
		line.TextWrapped = true
		table.insert(logLines, line)
	end
	local logButton = PixelUi.button(logPanel, "OpenFullLog", 0, 0, 140, 30, "")
	logButton.ZIndex = 3

	local fullLog = PixelUi.box(hud, "FullLog", 20, 20, 280, 150, Colors.Panel)
	fullLog.ZIndex = 5
	fullLog.Visible = false
	PixelUi.label(fullLog, "Title", 6, 3, 200, 10, "COMBAT LOG", Colors.Victory)
	local fullLogLines: { TextLabel } = {}
	for i = 1, FULL_LOG_LINES do
		table.insert(fullLogLines, PixelUi.label(fullLog, `Line{i}`, 6, 14 + (i - 1) * 9, 268, 9, "", Colors.Text))
	end
	local closeLog = PixelUi.button(fullLog, "Close", 0, 0, 280, 150, "")
	closeLog.ZIndex = 6

	-- Outcome banner -------------------------------------------------------
	local banner = PixelUi.box(hud, "OutcomeBanner", 70, 44, 180, 60, Colors.Panel)
	banner.ZIndex = 4
	banner.Visible = false
	local bannerTitle = PixelUi.label(banner, "Title", 0, 6, 180, 12, "", Colors.Victory, Enum.TextXAlignment.Center)
	local bannerSub = PixelUi.label(banner, "Subtitle", 6, 20, 168, 10, "", Colors.TextDim, Enum.TextXAlignment.Center)
	local bannerButtonBox = PixelUi.box(banner, "ButtonBox", 40, 36, 100, 16, Colors.Button)
	local bannerButton = PixelUi.button(bannerButtonBox, "Button", 0, 0, 100, 16, "")

	-- Origin select --------------------------------------------------------
	local originSelect = OriginSelect.new(hud, callbacks.onChooseOrigin)

	-- Toast ----------------------------------------------------------------
	local toastBox = PixelUi.box(hud, "Toast", 40, 24, 240, 14, Colors.PanelLight)
	toastBox.ZIndex = 7
	toastBox.Visible = false
	local toastLabel = PixelUi.label(toastBox, "Text", 4, 1, 232, 12, "", Colors.Text, Enum.TextXAlignment.Center)
	local toastToken = 0

	-- State ----------------------------------------------------------------
	local fighters: { [string]: FighterView } = {}
	local updateTargetNames: () -> ()
	local selectedTargetId: string? = nil
	local lastSnapshot: CombatSnapshot? = nil
	local lastProfile: Profile? = nil
	local lastLogCount = 0
	local busy = false
	local originShown = false

	local function refreshReason()
		reasonLabel.Text = hoveredReason or defaultReason
	end

	local function currentOption(moveId: MoveId): ActionOption?
		local snapshot = lastSnapshot
		if not snapshot then
			return nil
		end
		for _, option in snapshot.actions do
			if option.moveId == moveId then
				return option
			end
		end
		return nil
	end

	local function pickTarget(option: ActionOption): string?
		if #option.targetIds == 0 then
			return nil
		end
		if selectedTargetId and table.find(option.targetIds, selectedTargetId) then
			return selectedTargetId
		end
		return option.targetIds[1]
	end

	for index, moveId in ACTION_ORDER do
		local x = 3 + (index - 1) * 54
		local box, fill = PixelUi.box(actionBar, moveId, x, 3, 52, 16, Colors.Button)
		local title = PixelUi.label(box, "Title", 0, 0, 52, 9, moveId, Colors.Text, Enum.TextXAlignment.Center)
		local cost = PixelUi.label(box, "Cost", 0, 8, 52, 8, "", Colors.Stamina, Enum.TextXAlignment.Center)
		local button = PixelUi.button(box, "Press", 0, 0, 52, 16, "")
		local view: ActionButtonView = { box = box, button = button, fill = fill, title = title, cost = cost }
		actionViews[moveId] = view

		button.MouseEnter:Connect(function()
			local option = currentOption(moveId)
			if option and not option.legality.canUse then
				hoveredReason = option.legality.disabledReason
			elseif option then
				fill.BackgroundColor3 = Colors.ButtonHover
			end
			refreshReason()
		end)
		button.MouseLeave:Connect(function()
			hoveredReason = nil
			local option = currentOption(moveId)
			if option and option.legality.canUse then
				fill.BackgroundColor3 = Colors.Button
			end
			refreshReason()
		end)
		button.Activated:Connect(function()
			local option = currentOption(moveId)
			if busy or not option then
				return
			end
			if not option.legality.canUse then
				-- Tapping a disabled move on touch screens shows why.
				hoveredReason = option.legality.disabledReason
				refreshReason()
				return
			end
			callbacks.onAction(moveId, pickTarget(option))
		end)
	end

	local function makeFighter(actor: ActorState): FighterView
		local facingLeft = actor.team == "Enemy"
		local holder = PixelUi.frame(fighterLayer, actor.id, 0, FEET_Y - FighterSprite.FEET_ROW, 96, 96)
		local sprite = FighterSprite.create(holder, actor.spriteKey, facingLeft)
		local flash = PixelUi.frame(holder, "HitFlash", 34, 28, 28, 60, Colors.Hp)
		flash.BackgroundTransparency = 1

		-- Plate: name, HP bar, HP numbers, Stamina pips. Sits above the head.
		local plate = PixelUi.frame(holder, "Plate", (96 - PLATE_W) // 2, -2, PLATE_W, 28)
		local nameLabel = PixelUi.label(plate, "Name", 0, 0, PLATE_W, 8, actor.displayName, Colors.Text, Enum.TextXAlignment.Center)
		local hpOuter, setHp = PixelUi.bar(plate, "Hp", 0, 9, PLATE_W, 5, Colors.Hp, Colors.HpBack)
		local hpText = PixelUi.label(plate, "HpText", 0, 14, PLATE_W, 8, "", Colors.Text, Enum.TextXAlignment.Center)
		local pips: { Frame } = {}
		local pipsWidth = math.max(0, actor.maxStamina * 7 - 1)
		local pipRow = PixelUi.frame(plate, "Stamina", (PLATE_W - pipsWidth) // 2, 23, pipsWidth, 4)
		for i = 1, actor.maxStamina do
			table.insert(pips, PixelUi.frame(pipRow, `Pip{i}`, (i - 1) * 7, 0, 6, 4, Colors.StaminaBack))
		end

		local guardTag = PixelUi.box(holder, "Guard", 30, 52, 36, 10, Colors.Guard)
		PixelUi.label(guardTag, "Text", 0, 0, 36, 10, "GUARD", Colors.Ink, Enum.TextXAlignment.Center)
		guardTag.Visible = false

		-- Intent badge: two lines above the plate. renderIntents moves it up a
		-- row for every second enemy so neighbouring badges never overlap.
		local intent, intentFill = PixelUi.box(holder, "Intent", (96 - INTENT_W) // 2, -24, INTENT_W, 21, Colors.Panel)
		intent.ZIndex = 2
		local intentLine1 = PixelUi.label(intent, "Move", 3, 1, INTENT_W - 6, 9, "", Colors.Attack)
		local intentLine2 = PixelUi.label(intent, "Detail", 3, 10, INTENT_W - 6, 9, "", Colors.Text)
		intent.Visible = false

		-- Tap an enemy to target it. The selected enemy gets a yellow name and HP frame.
		local hitbox = PixelUi.button(holder, "Select", 30, 20, 36, 70, "")
		hitbox.Visible = actor.team == "Enemy"
		hitbox.Activated:Connect(function()
			selectedTargetId = actor.id
			updateTargetNames()
		end)

		return {
			root = holder,
			sprite = sprite,
			flash = flash,
			nameLabel = nameLabel,
			setHp = setHp,
			hpOuter = hpOuter,
			hpText = hpText,
			pips = pips,
			guardTag = guardTag,
			intent = intent,
			intentFill = intentFill,
			intentLine1 = intentLine1,
			intentLine2 = intentLine2,
			hitbox = hitbox,
			displayName = actor.displayName,
		}
	end

	function updateTargetNames()
		local snapshot = lastSnapshot
		local living = 0
		if snapshot then
			for _, actor in snapshot.actors do
				if actor.team == "Enemy" and actor.hp > 0 then
					living += 1
				end
			end
		end
		local showMarker = living > 1 and snapshot ~= nil and snapshot.outcome == "InProgress"
		for id, view in fighters do
			local selected = showMarker and id == selectedTargetId
			view.nameLabel.Text = view.displayName
			view.hpOuter.BackgroundColor3 = if selected then Colors.Victory else Colors.Ink
			local active = snapshot ~= nil and id == snapshot.activeActorId
			view.nameLabel.TextColor3 = if selected then Colors.Victory elseif active then Colors.Active else Colors.Text
		end
	end

	local function flashHit(view: FighterView)
		view.flash.BackgroundTransparency = 0.35
		task.delay(0.12, function()
			view.flash.BackgroundTransparency = 1
		end)
	end

	local function renderQueue(snapshot: CombatSnapshot, actors: { [string]: ActorState })
		turnLabel.Text = `TURN {snapshot.turn}`
		for _, chip in queueChips do
			chip:Destroy()
		end
		table.clear(queueChips)
		local x = 44
		for index, entry in snapshot.turnOrder do
			local isActive = entry.actorId == snapshot.activeActorId
			local color = if isActive then Colors.Active else Colors.PanelLight
			local chip = PixelUi.box(queuePanel, `Q{index}`, x, 1, 50, 12, color)
			local text = `{shortName(snapshot, entry.actorId, actors)} {entry.speed}`
			PixelUi.label(chip, "Text", 2, 1, 46, 10, text, if isActive then Colors.Ink else Colors.Text, Enum.TextXAlignment.Center)
			table.insert(queueChips, chip)
			x += 52
			if x + 50 > 200 then
				break
			end
		end
	end

	local function renderFighters(snapshot: CombatSnapshot, actors: { [string]: ActorState })
		-- Remove fighters that left the snapshot (e.g. after a retry).
		for id, view in fighters do
			if not actors[id] then
				view.root:Destroy()
				fighters[id] = nil
			end
		end

		local enemyIndex = 0
		for _, actor in snapshot.actors do
			local view = fighters[actor.id]
			if not view then
				view = makeFighter(actor)
				fighters[actor.id] = view
			end
			assert(view)
			local x = PLAYER_SLOT_X
			if actor.team == "Enemy" then
				enemyIndex += 1
				x = ENEMY_SLOTS_X[math.min(enemyIndex, #ENEMY_SLOTS_X)]
			end
			view.root.Position = UDim2.fromOffset(x, FEET_Y - FighterSprite.FEET_ROW)

			local down = actor.hp <= 0
			view.sprite.Visible = not down
			view.hitbox.Visible = actor.team == "Enemy" and not down
			view.displayName = if down then `{actor.displayName} (DOWN)` else actor.displayName
			view.nameLabel.Text = view.displayName
			view.setHp(if actor.maxHp > 0 then actor.hp / actor.maxHp else 0)
			view.hpText.Text = `HP {actor.hp}/{actor.maxHp}`
			for i, pip in view.pips do
				pip.BackgroundColor3 = if i <= actor.stamina then Colors.Stamina else Colors.StaminaBack
				pip.Visible = i <= actor.maxStamina
			end
			view.guardTag.Visible = actor.isDefending and not down
			view.intent.Visible = false
		end

		-- Keep a valid target selected.
		local targetStillValid = false
		if selectedTargetId then
			local target = actors[selectedTargetId]
			targetStillValid = target ~= nil and target.hp > 0 and target.team == "Enemy"
		end
		if not targetStillValid then
			selectedTargetId = nil
			for _, actor in snapshot.actors do
				if actor.team == "Enemy" and actor.hp > 0 then
					selectedTargetId = actor.id
					break
				end
			end
		end
		updateTargetNames()
	end

	local function renderIntents(snapshot: CombatSnapshot, actors: { [string]: ActorState })
		local row = 0
		for _, intent in snapshot.enemyIntents do
			local view = fighters[intent.actorId]
			if view then
				view.intent.Position = UDim2.fromOffset((96 - INTENT_W) // 2, -24 - (row % 2) * 22)
				row += 1
				local kindColor = if intent.telegraphKind == "Heavy"
					then Colors.Heavy
					elseif intent.telegraphKind == "Guard" then Colors.Guard
					else Colors.Attack
				local when = if intent.landingTurn <= snapshot.turn then "NOW" else `T{intent.landingTurn}`
				view.intent.Visible = true
				view.intentFill.BackgroundColor3 = Colors.Panel
				view.intent.BackgroundColor3 = kindColor
				view.intentLine1.Text = `! {string.upper(intent.label)}`
				view.intentLine1.TextColor3 = kindColor
				view.intentLine2.Text =
					`> {shortName(snapshot, intent.targetId, actors)} {when} PWR {intent.estimatedPower}`
			end
		end
	end

	local function renderActions(snapshot: CombatSnapshot)
		local firstReason = ""
		local byId: { [MoveId]: ActionOption } = {}
		for _, option in snapshot.actions do
			byId[option.moveId] = option
		end
		for _, moveId in ACTION_ORDER do
			local view = actionViews[moveId]
			local option = byId[moveId]
			if option then
				view.box.Visible = true
				local usable = option.legality.canUse and not busy
				-- First word only so it fits the button: "Quick Strike" -> QUICK.
				view.title.Text = string.upper(string.match(option.label, "^%S+") or option.label)
				view.cost.Text = if option.staminaCost > 0 then `{option.staminaCost} STA` else "FREE"
				view.fill.BackgroundColor3 = if usable then Colors.Button else Colors.Disabled
				view.title.TextColor3 = if usable then Colors.Text else Colors.TextDim
				view.cost.TextColor3 = if usable then Colors.Stamina else Colors.TextDim
				if not option.legality.canUse and firstReason == "" and snapshot.outcome == "InProgress" then
					firstReason = option.legality.disabledReason or ""
				end
			else
				view.box.Visible = false
			end
		end
		defaultReason = if busy then "..." else firstReason
		hoveredReason = nil
		refreshReason()
	end

	local function renderLog(snapshot: CombatSnapshot)
		local count = #snapshot.log
		for i, line in logLines do
			local event = snapshot.log[count - LOG_LINES + i]
			line.Text = if event then event.message else ""
			line.TextColor3 = if i == LOG_LINES then Colors.Text else Colors.TextDim
		end
		for i, line in fullLogLines do
			local event = snapshot.log[count - FULL_LOG_LINES + i]
			line.Text = if event then `T{event.turn}  {event.message}` else ""
		end
	end

	local function renderOutcome(snapshot: CombatSnapshot, profile: Profile)
		if snapshot.outcome == "Victory" then
			if profile.origin ~= nil then
				-- Saved: close the picker and show the result on the banner.
				originShown = false
				originSelect:hide()
			end
			banner.Visible = not originShown
			bannerTitle.Text = "VICTORY!"
			bannerTitle.TextColor3 = Colors.Victory
			if profile.origin ~= nil then
				bannerSub.Text = `ORIGIN SAVED: {OriginSelect.displayName(profile.origin)}`
				bannerButton.Text = "NIGHT SANDBOX"
				bannerButtonBox.Visible = callbacks.onOpenSandbox ~= nil
			else
				bannerSub.Text = "Choose how your story begins."
				bannerButton.Text = "CHOOSE ORIGIN"
				bannerButtonBox.Visible = true
			end
		elseif snapshot.outcome == "Defeat" then
			banner.Visible = true
			originShown = false
			originSelect:hide()
			bannerTitle.Text = "DEFEATED"
			bannerTitle.TextColor3 = Colors.Defeat
			bannerSub.Text = "The tutorial is safe to retry."
			bannerButton.Text = "RETRY"
			bannerButtonBox.Visible = true
		else
			banner.Visible = false
			originShown = false
			originSelect:hide()
		end
	end

	bannerButton.Activated:Connect(function()
		local snapshot = lastSnapshot
		if busy or not snapshot then
			return
		end
		if snapshot.outcome == "Defeat" then
			callbacks.onRetry()
		elseif snapshot.outcome == "Victory" and lastProfile ~= nil and lastProfile.origin ~= nil then
			local openSandbox = callbacks.onOpenSandbox
			if openSandbox then
				openSandbox()
			end
		elseif snapshot.outcome == "Victory" then
			originShown = true
			banner.Visible = false
			originSelect:show()
		end
	end)

	logButton.Activated:Connect(function()
		fullLog.Visible = true
	end)
	closeLog.Activated:Connect(function()
		fullLog.Visible = false
	end)

	local self = {} :: BattleViewport

	function self.render(_self: BattleViewport, snapshot: CombatSnapshot, profile: Profile)
		local actors: { [string]: ActorState } = {}
		for _, actor in snapshot.actors do
			actors[actor.id] = actor
		end

		local previous = lastSnapshot
		local sameBattle = previous ~= nil and previous.battleId == snapshot.battleId
		if not sameBattle then
			lastLogCount = 0
		end
		lastSnapshot = snapshot

		renderQueue(snapshot, actors)
		renderFighters(snapshot, actors)
		renderIntents(snapshot, actors)
		renderActions(snapshot)
		renderLog(snapshot)
		lastProfile = profile
		renderOutcome(snapshot, profile)

		-- Flash anyone who took damage since the last snapshot we drew.
		if sameBattle then
			for i = lastLogCount + 1, #snapshot.log do
				local event = snapshot.log[i]
				if event.kind == "Damage" and event.targetId then
					local view = fighters[event.targetId]
					if view then
						flashHit(view)
					end
				end
			end
		end
		lastLogCount = #snapshot.log

	end

	function self.setBusy(_self: BattleViewport, value: boolean)
		busy = value
		originSelect:setBusy(value)
		local snapshot = lastSnapshot
		if snapshot then
			renderActions(snapshot)
		end
	end

	function self.toast(_self: BattleViewport, message: string)
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

	function self.setMock(_self: BattleViewport, isMock: boolean)
		serverBadge.Text = if isMock then "MOCK SERVER" else ""
	end

	function self.destroy(_self: BattleViewport)
		screenGui:ClearAllChildren()
	end

	return self
end

return BattleViewport
