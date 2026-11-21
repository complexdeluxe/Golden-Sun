--!nonstrict
-- Dark Moon: Luau port of APCreateTask.py (cmu_graphics). 2D only.
-- Owner: Claude. Original source is preserved untouched in the repo root.
--
-- Structure:
--   Sim      pure game state, one call to Sim:step() == one original onStep (30 Hz)
--   Session  view + input + fixed-step loop, created by DarkMoon.new(context)
--
-- Adapter interface: docs/arcade-contract.md v1
--   Game.new(ctx) -> session (inert) ; session:start() ; session:destroy() (idempotent)
--   ctx.root : Frame         game viewport owned by the runtime; we letterbox a 400x400 playfield inside
--   ctx.onCleanup(fn)        runtime-run cleanup (reverse order)
--   ctx.isActive() -> bool   false once the runtime has stopped this generation
--   ctx.requestExit()        ask the launcher to return to the menu

local DarkMoon = {}

DarkMoon.id = "dark_moon"
DarkMoon.displayName = "Dark Moon"
DarkMoon.description = "Dodge the obstacles and survive all ten stages until the End."
DarkMoon.controls = {
	"A / D: move left / right",
	"Space: jump (also works in mid-air, like the original)",
	"S: fall faster",
	"W: dash in the direction you are moving",
	"Codes: invincibility phrase, before the run or in its first 5 seconds",
	"Legacy route: hold | and ~ in the first 5 seconds (a wrong phrase ends the run)",
}
DarkMoon.devices = { "Keyboard" }

local STEP = 1 / 30 -- cmu_graphics default stepsPerSecond; source counts 30 frames per second
local MAX_STEPS_PER_FRAME = 5

DarkMoon.INVINCIBILITY_PHRASE = "The Author of the Continental Page"
DarkMoon.LEGACY_PROMPT = "%*(@!&%)(!*&!@)(*&SH{{}~F~HA"
local INVINCIBLE_IFRAMES = 869251968158709

-- Audio: the original plays local MP3s. Roblox needs uploaded, authorized
-- asset ids. None are configured, so audio is disabled (see arcade-game-notes).
DarkMoon.AUDIO = {
	music = nil :: string?, -- "rbxassetid://..." for Dimrain47 - Every End
	deathSounds = {} :: { string },
}

local STAGE_COLORS_1 = {
	"royalBlue", "lightCoral", "paleGreen", "darkCyan", "slateBlue",
	"deepPink", "mediumPurple", "darkRed", "cornsilk", "darkGreen",
}
local STAGE_COLORS_2 = {
	"cadetBlue", "crimson", "khaki", "violet", "tomato", "peru",
	"lightSkyBlue", "bisque", "oldLace", "maroon",
}
local DISTANCES = { 500, 600, 700, 800 }
local ROOF_BOTTOM = 30
local FLOOR_TOP = 370

---------------------------------------------------------------------------
-- Sim
---------------------------------------------------------------------------

export type Rect = { x: number, y: number, w: number, h: number }
export type Obstacle = { id: number, rects: { Rect }, speed: number }
export type Afterimage = { x: number, y: number, w: number, h: number, opacity: number, rot: number, endgame: boolean }

local Sim = {}
Sim.__index = Sim
DarkMoon.Sim = Sim

local function overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

function Sim.new(rng: Random?)
	local self = setmetatable({}, Sim)
	self.rng = rng or Random.new()
	self.player = { x = 200, y = 200, w = 20, h = 20 } :: Rect -- cmu Rect(200,200,20,20): left/top
	self.playerFill = "skyBlue"
	self.playerBorder = "dodgerBlue"
	self.playerOpacity = 100
	self.movingLeft = false
	self.movingRight = false
	self.jumpHeight = 70
	self.jumpDes = 0
	self.jumping = false
	self.endgame = false
	self.movementSpeed = 5
	self.alive = true
	self.minutes = 0
	self.realSeconds = 0
	self.seconds = 0
	self.score = 0
	self.frames = 0
	self.iFrames = 10
	self.ogIFrames = 10
	self.iFramesActive = false
	self.stage = 1
	self.stageIndex = 0 -- 0-based, as in the source
	self.gravity = 4
	self.ogGrav = 4
	self.obGap = 100
	self.obDGap = 0
	self.obLimit = 6
	self.objects = {} :: { Obstacle }
	self.nextId = 0
	self.afterimages = {} :: { Afterimage }
	self.borderOpacity = 100 -- full-screen black world_border fading in/out
	self.messageText = "Dodge Obstacles Until the End..."
	self.messageOpacity = 100
	self.scoreText = "XXXX"
	self.scoreSize = 18
	self.scoreCentered = false
	self.timeText = "0:00"
	self.stageText = "1"
	self.stageBorder = "black"
	self.stageBorderWidth = 0
	self.stageSize = 18
	self.stageFill = "white"
	self.uiOpacity = 100
	self.roofTop = -75
	self.floorTop = FLOOR_TOP
	self.cheated = false -- shows "Invicibility was used for this Completion"
	self.victory = false
	self.songPlaying = true
	self.deathSoundRequested = false
	self.finished = false -- equivalent of app.stop()
	return self
end

function Sim:centerX(): number
	return self.player.x + self.player.w / 2
end
function Sim:centerY(): number
	return self.player.y + self.player.h / 2
end
function Sim:setCenterX(v: number)
	self.player.x = v - self.player.w / 2
end
function Sim:setCenterY(v: number)
	self.player.y = v - self.player.h / 2
end

function Sim:_color(fill: string, border: string)
	self.playerFill = fill
	self.playerBorder = border
end

function Sim:_message(text: string)
	self.messageText = text
	self.messageOpacity = 100
end

function Sim:_upStageLabel(sizeNum: number, border: string)
	self.stageBorder = border
	self.stageSize += sizeNum
end

function Sim:death()
	self:_color("salmon", "fireBrick")
	self.alive = false
end

function Sim:_dash(length: number)
	self:setCenterX(self:centerX() + length)
	local p = self.player
	for i = 0, 5 do
		local w, h = p.w / 1.5, p.h / 1.5
		table.insert(self.afterimages, {
			x = p.x - (length / 6) * i,
			y = self:centerY() - h / 2,
			w = w,
			h = h,
			opacity = 90 - 10 * i,
			rot = if self.endgame then self.rng:NextInteger(0, 360) else 0,
			endgame = self.endgame,
		})
	end
	self.iFramesActive = true
end

-- onKeyPress: "space" or "w"
function Sim:keyPress(key: string)
	if not self.alive then
		return
	end
	if key == "space" then
		self:setCenterY(self:centerY() - 10)
		self.jumping = true
		self.jumpDes = self:centerY() - self.jumpHeight
	elseif key == "w" then
		if self.movingRight then
			self:_dash(85)
		end
		if self.movingLeft then
			self:_dash(-85)
		end
	end
end

export type HeldKeys = { a: boolean, d: boolean, s: boolean, chord: boolean }

-- onKeyHold: called once per step while any key is held.
-- Returns "legacyPrompt" when the original | + ~ invincibility prompt should open.
function Sim:keyHold(k: HeldKeys): string?
	if not self.alive then
		return nil
	end
	if k.a then
		self.player.x -= self.movementSpeed
		self.movingLeft = true
		self.movingRight = false
	end
	if k.d then
		self.player.x += self.movementSpeed
		self.movingRight = true
		self.movingLeft = false
	end
	if k.a and k.d then
		self.movingRight = false
		self.movingLeft = false
	end
	if k.s then
		self.gravity = self.ogGrav * 2
		self.jumping = false
		self:_color("dimGray", "gainsboro")
	else
		self.gravity = self.ogGrav
		self:_color("skyBlue", "dodgerBlue")
	end
	if self.realSeconds < 5 and k.chord then
		return "legacyPrompt"
	end
	return nil
end

function Sim:enableInvincibility()
	self.iFrames = INVINCIBLE_IFRAMES
	self.iFramesActive = true
	self.cheated = true
end

-- Original route: correct phrase -> invincible; anything else (including a
-- cancelled prompt, which returns no text) -> "The End You Seek..." and death.
function Sim:applyLegacyCode(text: string?)
	if text == DarkMoon.INVINCIBILITY_PHRASE then
		self:enableInvincibility()
	else
		self:_message("The End You Seek... ")
		self:death()
	end
end

-- New Codes UI route (harmless on mismatch). Valid before the run or during
-- the original's 5-second window.
function Sim:codeWindowOpen(): boolean
	return self.alive and self.realSeconds < 5
end

function Sim:_generateObstacle()
	local rng = self.rng
	local kind = rng:NextInteger(1, 3)
	local speed = rng:NextInteger(self.stage + 1, self.stage + 4)
	local x = DISTANCES[self.obDGap + 1]
	local s = self.stage
	local rects: { Rect }
	if kind == 1 then
		local w, h = 45 + 2.5 * s, 200 + (self.obGap * 0.75 + s)
		rects = { { x = x, y = 400 - h, w = w, h = h } }
	elseif kind == 2 then
		local w, h = 45 + 2.5 * s, 200 + (self.obGap * 0.75 + s)
		rects = { { x = x, y = 0, w = w, h = h } }
	else
		local w = 45 + 5 * s
		local off = self.obGap - 7 * s
		rects = {
			{ x = x, y = 200 + off, w = w, h = 200 },
			{ x = x, y = 0 - off, w = w, h = 200 },
		}
	end
	self.obDGap += 1
	if self.obDGap > 3 then
		self.obDGap = 0
	end
	self.nextId += 1
	table.insert(self.objects, { id = self.nextId, rects = rects, speed = speed })
end

local function obstacleRight(o: Obstacle): number
	local r = -math.huge
	for _, rect in o.rects do
		r = math.max(r, rect.x + rect.w)
	end
	return r
end

function Sim:_moveObstacles()
	local keep = {}
	for _, o in self.objects do
		if obstacleRight(o) >= 0 then
			for _, rect in o.rects do
				rect.x -= o.speed
			end
		end
		if obstacleRight(o) >= 0 then
			table.insert(keep, o)
		end
	end
	self.objects = keep
end

function Sim:_hitsObstacle(): boolean
	for _, o in self.objects do
		for _, rect in o.rects do
			if overlaps(self.player, rect) then
				return true
			end
		end
	end
	return false
end

function Sim:step()
	if self.finished then
		return
	end
	self.frames += 1

	if self.frames % 2 == 0 then
		if self.messageOpacity > 0 then
			self.messageOpacity -= 1
		end
		if self.borderOpacity > 0 and self.minutes < 1 then
			self.borderOpacity -= 1
		elseif self.minutes == 7 and self.seconds > 19 and self.borderOpacity < 100 then
			self.borderOpacity += 1
			self.scoreText = "Victory is Yours"
			self.scoreSize = 7.5
			self.victory = true
		end
	end

	if self.alive then
		if self.frames % 5 == 0 then
			self.score += 1
			if not self.victory then
				self.scoreText = tostring(self.score)
			end
		end
		if self.frames % 30 == 0 then
			self.seconds += 1
			self.realSeconds += 1
			if self.seconds < 10 then
				self.timeText = tostring(self.minutes) .. ":0" .. tostring(self.seconds)
			else
				self.timeText = tostring(self.minutes) .. ":" .. tostring(self.seconds)
			end
			if self.realSeconds % 40 == 0 and self.stage < 5 then
				self.stage += 1
				self.stageIndex += 1
				self:_upStageLabel(0, "darkGoldenrod")
				self:_message("Obstacle Size and Speed Increased!")
				self.stageBorderWidth = 1
			end
			if self.realSeconds % 40 == 0 and self.stage > 3 and self.stage <= 5 then
				self:_upStageLabel(0, "gainsboro")
			end
			if self.realSeconds % 50 == 0 and self.stage < 10 and self.stage >= 5 then
				self.stage += 1
				self.stageIndex += 1
			end
			if self.stage == 6 and self.stageBorder ~= "gold" then
				self:_upStageLabel(1, "gold")
			end
			if self.stage == 8 and self.stageBorder ~= "lightCyan" then
				if not self.endgame then
					self:_message("The End draws near...")
					self.endgame = true
					self.ogIFrames += 5
				end
				self:_upStageLabel(1, "lightCyan")
			end
			if self.stage == 10 and self.stageBorder ~= "limeGreen" then
				self.stageFill = "black"
				self:_upStageLabel(1, "limeGreen")
			end
			self.stageText = tostring(self.stage)
			if self.realSeconds % 60 == 0 then
				self.minutes += 1
				self.seconds = 0
			end
		end

		local p = self.player
		if p.y < ROOF_BOTTOM then
			p.y = ROOF_BOTTOM
			self.jumping = false
		end
		if p.y + p.h < FLOOR_TOP then
			p.y += self.gravity
		end
		if self.jumping then
			self:_color("limeGreen", "chartreuse")
			if self:centerY() >= self.jumpDes then
				self:setCenterY(self:centerY() - self.jumpHeight / 6)
			else
				self.jumping = false
				self:_color("skyBlue", "dodgerBlue")
			end
		end

		local keepImages = {}
		for _, img in self.afterimages do
			if img.opacity > 0 then
				img.opacity -= 10
				table.insert(keepImages, img)
			end
		end
		self.afterimages = keepImages

		if self.iFramesActive then
			self.playerBorder = "azure"
			self.iFrames -= 1
			if self.iFrames == 0 then
				self.iFrames = self.ogIFrames
				self.iFramesActive = false
				self.playerBorder = "dodgerBlue"
			end
		end

		if not self.victory then
			self.movementSpeed = self.stage + 5
			self:_moveObstacles()
			if #self.objects < self.obLimit and self.realSeconds > 5 then
				self:_generateObstacle()
			end
		else
			table.clear(self.objects)
			if self.borderOpacity == 100 then
				self:death()
			end
		end

		local inWorld = overlaps({ x = 0, y = 0, w = 400, h = 400 }, p)
		if self:_hitsObstacle() or not inWorld then
			if not self.iFramesActive then
				self:death()
			end
		end
	else
		if self.songPlaying then
			self.songPlaying = false
			if not self.victory then
				self.deathSoundRequested = true
			end
		end
		if self.frames % 2 == 0 then
			if self.playerOpacity > 0 then
				self.playerOpacity -= 1
			else
				self.finished = true
			end
			if self.uiOpacity > 0 then
				self.uiOpacity -= 2
			end
			self.roofTop -= 0.35
			self.floorTop += 0.35
			self.scoreCentered = true
			self.scoreSize = 28
		end
	end
end

-- "victory" | "death" | nil (still running)
function Sim:outcome(): string?
	if not self.finished then
		return nil
	end
	return if self.victory then "victory" else "death"
end

function Sim:backgroundColors(): (string, string)
	return STAGE_COLORS_1[self.stageIndex + 1], STAGE_COLORS_2[self.stageIndex + 1]
end

---------------------------------------------------------------------------
-- Session (view, input, loop)
---------------------------------------------------------------------------

local Session = {}
Session.__index = Session

function DarkMoon.new(context: any)
	assert(type(context) == "table", "DarkMoon.new: context table required")
	assert(typeof(context.root) == "Instance", "DarkMoon.new: ctx.root required")
	assert(type(context.requestExit) == "function", "DarkMoon.new: ctx.requestExit required")
	assert(type(context.onCleanup) == "function", "DarkMoon.new: ctx.onCleanup required")
	assert(type(context.isActive) == "function", "DarkMoon.new: ctx.isActive required")
	local self = setmetatable({}, Session)
	self.context = context
	self.conns = {} :: { RBXScriptConnection }
	self.destroyed = false
	self.started = false
	self.phase = "setup" -- setup | running | prompt | result
	self.preRunInvincible = false
	self.dialog = nil :: any
	self.chordLatched = false
	return self
end

function Session:_conn(c: RBXScriptConnection)
	table.insert(self.conns, c)
end

function Session:start()
	if self.started or self.destroyed then
		return
	end
	self.started = true
	self.context.onCleanup(function()
		self:destroy()
	end)
	local gamesFolder = script.Parent
	local arcadeFolder = gamesFolder and gamesFolder.Parent
	local ui = arcadeFolder and arcadeFolder:FindFirstChild("ui")
	assert(ui, "DarkMoon: expected sibling folder arcade/ui next to arcade/games")
	self.PlayField = require(ui:WaitForChild("PlayField")) :: any
	self.GameChrome = require(ui:WaitForChild("GameChrome")) :: any
	self.CodesDialog = require(ui:WaitForChild("CodesDialog")) :: any

	self.chrome = self.GameChrome.new(self.context.root, {
		title = DarkMoon.displayName,
		controls = DarkMoon.controls,
		onCodes = function()
			self:_openCodes()
		end,
	})
	self.field = self.PlayField.new(self.chrome.playArea, Color3.new(0, 0, 0))
	self:_showSetup()

	local UIS = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	self:_conn(UIS.InputBegan:Connect(function(input: InputObject, processed: boolean)
		self:_onInputBegan(input, processed)
	end))
	local acc = 0
	self:_conn(RunService.Heartbeat:Connect(function(dt: number)
		if self.phase ~= "running" or not self.sim or not self.context.isActive() then
			acc = 0
			return
		end
		acc = math.min(acc + dt, STEP * MAX_STEPS_PER_FRAME)
		while acc >= STEP and self.phase == "running" do
			acc -= STEP
			self:_tick()
		end
		self:_render()
	end))
end

function Session:_keysBlocked(): boolean
	local UIS = game:GetService("UserInputService")
	return self.CodesDialog.isAnyOpen() or UIS:GetFocusedTextBox() ~= nil
end

function Session:_onInputBegan(input: InputObject, processed: boolean)
	if processed or self.phase ~= "running" or self:_keysBlocked() or not self.context.isActive() then
		return
	end
	if input.KeyCode == Enum.KeyCode.Space then
		self.sim:keyPress("space")
	elseif input.KeyCode == Enum.KeyCode.W then
		self.sim:keyPress("w")
	end
end

function Session:_tick()
	local sim = self.sim
	if not self:_keysBlocked() then
		local UIS = game:GetService("UserInputService")
		local down = function(k: Enum.KeyCode)
			return UIS:IsKeyDown(k)
		end
		-- '|' is Shift+Backslash and '~' is Shift+Backquote on US layouts; accept the keys with or without Shift.
		local chord = down(Enum.KeyCode.BackSlash) and down(Enum.KeyCode.Backquote)
		if not chord then
			self.chordLatched = false
		end
		if #UIS:GetKeysPressed() > 0 then
			local result = sim:keyHold({
				a = down(Enum.KeyCode.A),
				d = down(Enum.KeyCode.D),
				s = down(Enum.KeyCode.S),
				chord = chord and not self.chordLatched,
			})
			if result == "legacyPrompt" then
				self.chordLatched = true
				self:_openLegacyPrompt()
				return
			end
		end
	end
	sim:step()
	if sim.deathSoundRequested then
		sim.deathSoundRequested = false
		self:_playDeathSound()
	end
	if sim.finished then
		self:_showResult()
	end
end

---------------------------------------------------------------------------
-- Codes
---------------------------------------------------------------------------

function Session:_openCodes()
	if self.destroyed or self.dialog then
		return
	end
	if self.phase == "result" then
		self.chrome:setStatus("Codes are entered before a run or in its first 5 seconds.")
		return
	end
	local wasRunning = self.phase == "running"
	if wasRunning and not self.sim:codeWindowOpen() then
		self.chrome:setStatus("The code window has passed: use Codes before the run or in its first 5 seconds.")
		return
	end
	if wasRunning then
		self.phase = "prompt"
	end
	self.dialog = self.CodesDialog.open(self.field, {
		title = "Dark Moon codes",
		prompt = "Enter a code:",
		placeholder = "code",
		onSubmit = function(text: string, dialog: any)
			if text == DarkMoon.INVINCIBILITY_PHRASE then
				if self.phase == "setup" then
					self.preRunInvincible = true
					self:_refreshSetup()
				elseif self.sim then
					self.sim:enableInvincibility()
				end
				dialog:close()
				self.dialog = nil
				self.chrome:setStatus("Invincibility enabled for this run.")
				if wasRunning and self.phase == "prompt" then
					self.phase = "running"
				end
			else
				dialog:setFeedback("Unknown code. Nothing changed.", true)
			end
		end,
		onCancel = function()
			self.dialog = nil
			if wasRunning and self.phase == "prompt" then
				self.phase = "running"
			end
		end,
	})
end

function Session:_openLegacyPrompt()
	if self.dialog then
		return
	end
	self.phase = "prompt"
	local function resolve(text: string?)
		self.dialog = nil
		if self.destroyed or not self.sim then
			return
		end
		self.sim:applyLegacyCode(text)
		if self.sim.cheated then
			self.chrome:setStatus("Invincibility enabled for this run.")
		end
		self.phase = "running"
	end
	self.dialog = self.CodesDialog.open(self.field, {
		title = DarkMoon.LEGACY_PROMPT,
		prompt = "(original route: a wrong answer ends the run)",
		placeholder = "",
		onSubmit = function(text: string, dialog: any)
			dialog:close()
			resolve(text)
		end,
		onCancel = function()
			resolve(nil)
		end,
	})
end

---------------------------------------------------------------------------
-- Screens
---------------------------------------------------------------------------

function Session:_clearField()
	if self.dialog then
		self.dialog:close()
		self.dialog = nil
	end
	for _, child in self.field:GetChildren() do
		if not child:IsA("UIAspectRatioConstraint") then
			child:Destroy()
		end
	end
	self.view = nil
end

local function panelButton(parent: Instance, text: string, y: number, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Text = text
	b.Name = text
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.TextColor3 = Color3.new(1, 1, 1)
	b.BackgroundColor3 = color
	b.AnchorPoint = Vector2.new(0.5, 0)
	b.Position = UDim2.fromScale(0.5, y)
	b.Size = UDim2.fromScale(0.5, 0.09)
	b.ZIndex = 30
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.2, 0)
	c.Parent = b
	local p = Instance.new("UIPadding")
	p.PaddingTop = UDim.new(0.2, 0)
	p.PaddingBottom = UDim.new(0.2, 0)
	p.Parent = b
	b.Parent = parent
	return b
end

function Session:_showSetup()
	self:_clearField()
	self.phase = "setup"
	self.sim = nil
	local PF = self.PlayField
	local holder = Instance.new("Frame")
	holder.Name = "Setup"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundColor3 = Color3.fromRGB(8, 8, 20)
	holder.ZIndex = 29
	holder.Parent = self.field
	PF.label(holder, { text = "Dark Moon", cx = 200, cy = 70, size = 36, color = PF.colors.white, font = Enum.Font.SciFi, z = 30 })
	PF.label(holder, { text = "Dodge Obstacles Until the End...", cx = 200, cy = 110, size = 14, color = PF.colors.gainsboro, font = Enum.Font.SciFi, z = 30 })
	self.setupStatus = PF.label(holder, { text = "", cx = 200, cy = 140, size = 12, color = PF.colors.aquamarine, z = 30 })
	local start = panelButton(holder, "Start run", 0.45, Color3.fromRGB(46, 139, 87))
	local codes = panelButton(holder, "Codes", 0.57, Color3.fromRGB(110, 80, 20))
	PF.label(holder, { text = "A/D move · Space jump · S fall · W dash", cx = 200, cy = 330, size = 11, color = PF.colors.white, z = 30 })
	self:_conn(start.Activated:Connect(function()
		if self.phase == "setup" and not self.dialog then
			self:_beginRun()
		end
	end))
	self:_conn(codes.Activated:Connect(function()
		self:_openCodes()
	end))
	self:_refreshSetup()
	self.chrome:setStatus("Ready.")
end

function Session:_refreshSetup()
	if self.setupStatus then
		self.setupStatus.Text = if self.preRunInvincible then "Invincibility armed for the next run" else ""
	end
end

function Session:_beginRun()
	self:_clearField()
	self.sim = Sim.new()
	if self.preRunInvincible then
		self.sim:enableInvincibility()
	end
	self.chordLatched = false
	self:_buildView()
	self.phase = "running"
	self:_startMusic()
	self.chrome:setStatus(if self.sim.cheated then "Invincibility enabled for this run." else "Run started.")
end

function Session:_showResult()
	if self.phase == "result" then
		return
	end
	self.phase = "result"
	self:_stopMusic()
	local sim = self.sim
	local PF = self.PlayField
	local holder = Instance.new("Frame")
	holder.Name = "Result"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundColor3 = Color3.new(0, 0, 0)
	holder.BackgroundTransparency = 0.25
	holder.ZIndex = 29
	holder.Parent = self.field
	local victory = sim:outcome() == "victory"
	PF.label(holder, {
		text = if victory then "Victory is Yours" else "The End...",
		cx = 200, cy = 110, size = 28,
		color = if victory then PF.colors.gold else PF.colors.salmon,
		font = Enum.Font.SciFi, z = 30,
	})
	PF.label(holder, {
		text = string.format("Score %d   ·   Time %s   ·   Stage %d", sim.score, sim.timeText, sim.stage),
		cx = 200, cy = 150, size = 13, color = PF.colors.white, z = 30,
	})
	if sim.cheated then
		PF.label(holder, { text = "Invicibility was used for this Completion", cx = 200, cy = 175, size = 11, color = PF.colors.aquamarine, z = 30 })
	end
	local again = panelButton(holder, "Run again", 0.52, Color3.fromRGB(46, 139, 87))
	local menu = panelButton(holder, "Back to menu", 0.64, Color3.fromRGB(140, 40, 40))
	self:_conn(again.Activated:Connect(function()
		if self.phase == "result" then
			self.preRunInvincible = false -- codes apply per run
			self:_showSetup()
		end
	end))
	self:_conn(menu.Activated:Connect(function()
		self.context.requestExit()
	end))
	self.chrome:setStatus(if victory then "Run complete." else "Run over.")
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

function Session:_buildView()
	local PF = self.PlayField
	local C = PF.colors
	local f = self.field
	local v: any = {}
	self.view = v

	local bg = PF.rect(f, { left = 0, top = 0, w = 400, h = 400, color = C.white, z = 1, name = "Background" })
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Parent = bg
	v.bgGradient = grad
	v.bgKey = ""

	v.obstacleLayer = Instance.new("Frame")
	v.obstacleLayer.BackgroundTransparency = 1
	v.obstacleLayer.Size = UDim2.fromScale(1, 1)
	v.obstacleLayer.ZIndex = 2
	v.obstacleLayer.Parent = f
	v.obstacles = {} :: { [number]: { Frame } }

	v.border = PF.rect(f, { left = 0, top = 0, w = 400, h = 400, color = C.black, z = 3, name = "WorldBorder" })

	v.afterLayer = Instance.new("Frame")
	v.afterLayer.BackgroundTransparency = 1
	v.afterLayer.Size = UDim2.fromScale(1, 1)
	v.afterLayer.ZIndex = 4
	v.afterLayer.Parent = f
	v.afterFrames = {} :: { Frame }

	v.player = PF.rect(f, { left = 200, top = 200, w = 20, h = 20, color = C.skyBlue, border = C.dodgerBlue, z = 5, name = "Player" })
	v.playerStroke = v.player:FindFirstChildOfClass("UIStroke")

	v.roof = PF.rect(f, { left = -5, top = -75, w = 410, h = 105, color = C.black, border = C.dimGray, z = 6, name = "Roof" })
	v.floor = PF.rect(f, { left = -5, top = 370, w = 410, h = 105, color = C.black, border = C.dimGray, z = 6, name = "Floor" })

	v.score = PF.label(f, { text = "XXXX", cx = 160, cy = 15, size = 18, color = C.white, font = Enum.Font.SciFi, z = 8, width = 200 })
	v.time = PF.label(f, { text = "0:00", cx = 240, cy = 15, size = 18, color = C.white, font = Enum.Font.SciFi, z = 8, width = 80 })
	v.stageLabel = PF.label(f, { text = "Stage: ", cx = 185, cy = 385, size = 18, color = C.white, font = Enum.Font.SciFi, z = 8, width = 90 })
	v.stageCount = PF.label(f, { text = "1", cx = 230, cy = 385, size = 18, color = C.white, font = Enum.Font.SciFi, z = 8, width = 40 })
	v.stageStroke = Instance.new("UIStroke")
	v.stageStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	v.stageStroke.Thickness = 0
	v.stageStroke.Parent = v.stageCount
	v.instructions = {
		PF.label(f, { text = "Press |A| and |D| to move left and right", cx = 75, cy = 385, size = 7.5, color = C.white, z = 8, width = 150 }),
		PF.label(f, { text = "Press |S| in the air to fall down faster", cx = 315, cy = 385, size = 7.5, color = C.white, z = 8, width = 150 }),
		PF.label(f, { text = "Press |Space| to jump into the air", cx = 65, cy = 15, size = 7.5, color = C.white, z = 8, width = 130 }),
		PF.label(f, { text = "Press |W| to dash either left or right", cx = 330, cy = 15, size = 7.5, color = C.white, z = 8, width = 140 }),
	}
	v.message = PF.label(f, { text = "", cx = 200, cy = 200, size = 18, color = C.white, font = Enum.Font.SciFi, z = 9, width = 400 })
	v.cheated = PF.label(f, { text = "Invicibility was used for this Completion", cx = 200, cy = 360, size = 10, color = C.white, z = 9, opacity = 40, width = 400 })
	v.cheated.Visible = false
	self:_render()
end

function Session:_render()
	local v = self.view
	local sim = self.sim
	if not v or not sim then
		return
	end
	local PF = self.PlayField
	local C = PF.colors

	local c1, c2 = sim:backgroundColors()
	local key = c1 .. c2
	if key ~= v.bgKey then
		v.bgKey = key
		v.bgGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, C.black),
			ColorSequenceKeypoint.new(1 / 3, C[c1]),
			ColorSequenceKeypoint.new(2 / 3, C[c2]),
			ColorSequenceKeypoint.new(1, C.black),
		})
	end

	-- obstacles (default cmu Rect fill is black, border white)
	local seen = {}
	for _, o in sim.objects do
		seen[o.id] = true
		local frames = v.obstacles[o.id]
		if not frames then
			frames = {}
			for _, r in o.rects do
				table.insert(frames, PF.rect(v.obstacleLayer, { left = r.x, top = r.y, w = r.w, h = r.h, color = C.black, border = C.white, z = 2 }))
			end
			v.obstacles[o.id] = frames
		end
		for i, r in o.rects do
			PF.place(frames[i], r.x, r.y, r.w, r.h)
		end
	end
	for id, frames in v.obstacles do
		if not seen[id] then
			for _, fr in frames do
				fr:Destroy()
			end
			v.obstacles[id] = nil
		end
	end

	v.border.BackgroundTransparency = PF.alpha(sim.borderOpacity)

	-- afterimages: resize pool
	local imgs = sim.afterimages
	while #v.afterFrames < #imgs do
		local fr = PF.rect(v.afterLayer, { left = 0, top = 0, w = 1, h = 1, color = C.black, z = 4 })
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(C.aquamarine, C.cyan)
		g.Enabled = false
		g.Parent = fr
		table.insert(v.afterFrames, fr)
	end
	for i, fr in v.afterFrames do
		local img = imgs[i]
		if img then
			fr.Visible = true
			PF.place(fr, img.x, img.y, img.w, img.h)
			fr.Rotation = img.rot
			fr.BackgroundColor3 = if img.endgame then C.white else C.black
			local grad = fr:FindFirstChildOfClass("UIGradient")
			if grad then
				grad.Enabled = img.endgame
			end
			fr.BackgroundTransparency = PF.alpha(img.opacity)
		else
			fr.Visible = false
		end
	end

	local p = sim.player
	PF.place(v.player, p.x, p.y, p.w, p.h)
	v.player.BackgroundColor3 = C[sim.playerFill]
	v.player.BackgroundTransparency = PF.alpha(sim.playerOpacity)
	v.playerStroke.Color = C[sim.playerBorder]
	v.playerStroke.Transparency = PF.alpha(sim.playerOpacity)

	PF.place(v.roof, -5, sim.roofTop, 410, 105)
	PF.place(v.floor, -5, sim.floorTop, 410, 105)

	v.score.Text = sim.scoreText
	if sim.scoreCentered then
		PF.setLabel(v.score, 200, 200, sim.scoreSize, 400)
	else
		PF.setLabel(v.score, 160, 15, sim.scoreSize, 200)
	end

	local uiAlpha = PF.alpha(sim.uiOpacity)
	v.time.Text = sim.timeText
	v.time.TextTransparency = uiAlpha
	v.stageLabel.TextTransparency = uiAlpha
	v.stageCount.Text = sim.stageText
	v.stageCount.TextTransparency = uiAlpha
	v.stageCount.TextColor3 = C[sim.stageFill]
	PF.setLabel(v.stageCount, 230, 385, sim.stageSize, 40)
	v.stageStroke.Color = C[sim.stageBorder]
	v.stageStroke.Thickness = sim.stageBorderWidth
	for _, l in v.instructions do
		l.TextTransparency = uiAlpha
	end

	v.message.Text = sim.messageText
	v.message.TextTransparency = PF.alpha(sim.messageOpacity)
	v.cheated.Visible = sim.cheated
end

---------------------------------------------------------------------------
-- Audio (disabled unless asset ids are configured)
---------------------------------------------------------------------------

function Session:_startMusic()
	self:_stopMusic()
	if DarkMoon.AUDIO.music then
		local s = Instance.new("Sound")
		s.SoundId = DarkMoon.AUDIO.music
		s.Looped = false
		s.Parent = self.field
		s:Play()
		self.music = s
	end
end

function Session:_stopMusic()
	if self.music then
		self.music:Destroy()
		self.music = nil
	end
end

function Session:_playDeathSound()
	self:_stopMusic()
	local list = DarkMoon.AUDIO.deathSounds
	if #list > 0 then
		local s = Instance.new("Sound")
		s.SoundId = list[math.random(1, #list)]
		s.Parent = self.field
		s:Play()
	end
end

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------

-- Idempotent; safe after a partial start.
function Session:destroy()
	if self.destroyed then
		return
	end
	self.destroyed = true
	self.phase = "destroyed"
	for _, c in self.conns do
		c:Disconnect()
	end
	table.clear(self.conns)
	if self.dialog then
		pcall(function()
			self.dialog:close()
		end)
		self.dialog = nil
	end
	self:_stopMusic()
	if self.chrome then
		self.chrome:destroy()
		self.chrome = nil
	end
	self.sim = nil
	self.view = nil
end

return DarkMoon
