--!nonstrict
-- Take Flight! (Alpha 2.1): Luau port of TakeFlight.py (cmu_graphics). 2D only.
-- Owner: Claude. Original source is preserved untouched in the repo root.
--
-- Structure:
--   Sim      pure game state, one Sim:step() == one original onStep (30 Hz)
--   Session  view + input + fixed-step loop, created by TakeFlight.new(context)
--
-- Adapter interface (pending docs/arcade-contract.md):
--   TakeFlight.new(context) -> session ; session:start() ; session:destroy() (idempotent)
--   context.container : GuiObject ; context.requestExit : (reason: string?) -> ()

local TakeFlight = {}

TakeFlight.id = "take_flight"
TakeFlight.displayName = "Take Flight!"
TakeFlight.description = "Fly, shoot clouds and trees, dodge hazards and spend skill points on four plane stats."
TakeFlight.controls = {
	"W / S: climb / dive (hold both to wobble)",
	"A / D: fly backward / forward",
	"Click: fire bullets",
	"Bottom tab: open the stat window (pauses) and spend skill points with + / -",
	"Codes: complexscore (set score), complexdura (uncap durability)",
	"Legacy routes: hold Shift+S+9+0 or Shift+D+=+T, then enter the code",
}
TakeFlight.devices = { "Keyboard", "Mouse" }

local STEP = 1 / 30 -- the source counts 30 steps per second
local MAX_STEPS_PER_FRAME = 5

TakeFlight.SCORE_CODE = "complexscore"
TakeFlight.DURA_CODE = "complexdura"
TakeFlight.MAX_SCORE_INPUT = 1e12
TakeFlight.MAX_DURABILITY_INPUT = 1000000

---------------------------------------------------------------------------
-- Stat tables (verbatim from the source)
---------------------------------------------------------------------------

local health_stats = { 70, 100, 130, 180, 300, 9999 }
local health_regen_stats = { 1, 2, 3, 5, 12, 999 }
local damage_reduction_stats = { 0, 0, 0.05, 0.1, 0.2, 0 }
local bullet_damage_stats = { 1, 2, 3, 5, 8 }
local bullet_knockback_stats = { 0, 0, 1, 2, 4 }
local flight_speed_stats = { 1, 2, 2.5, 3.5, 5 }
local turning_stats = { 1, 2, 3, 4, 10 }
local acceleration_stats = { 1, 1, 1.1, 1.5, 1.8 }
local ascent_speed_stats = { 1.1, 1.1, 1.11, 1.12, 1.13 }
local decent_speed_stats = { 1.1, 1.11, 1.11, 1.12, 1.13 }
local bloom_stats = { 20, 10, 5, 3, 1 }
local bullet_speed_stats = { 3, 5, 8, 15, 30 }

-- Durability beyond the table (only reachable through complexdura).
-- Tiers 1..6 use the source table. Above 6 we extend tier 6 instead of
-- crashing or clamping: +1000 max health per extra point, regen 999,
-- damage reduction 0 (tier 6's own value). Values below 1 are rejected at input.
function TakeFlight.durabilityStats(d: number): (number, number, number)
	if d >= 1 and d <= 6 then
		return health_stats[d], health_regen_stats[d], damage_reduction_stats[d]
	elseif d > 6 then
		return 9999 + (d - 6) * 1000, 999, 0
	end
	-- d < 1 cannot be set by the UI; fall back to tier 1 defensively.
	return health_stats[1], health_regen_stats[1], damage_reduction_stats[1]
end

local function clampIndex(v: number, n: number): number
	return math.clamp(math.floor(v), 1, n)
end

local function trunc(v: number): number
	return if v >= 0 then math.floor(v) else math.ceil(v)
end

---------------------------------------------------------------------------
-- Item shapes. Parts are fractions of the item's bounding box, measured
-- from the source polygons/arcs. Clouds are arcs rotated -90 (domes).
---------------------------------------------------------------------------

type Part = { fx: number, fy: number, fw: number, fh: number, kind: string }

local function domes(arcs: { { number } }): ({ Part }, number, number, number, number)
	-- arc {cx, cy, w, h} rotated -90 -> dome of width h, height w/2, flat bottom at cy
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	local boxes = {}
	for _, a in arcs do
		local x0, x1 = a[1] - a[4] / 2, a[1] + a[4] / 2
		local y0, y1 = a[2] - a[3] / 2, a[2]
		table.insert(boxes, { x0, y0, x1, y1 })
		minX, minY, maxX, maxY = math.min(minX, x0), math.min(minY, y0), math.max(maxX, x1), math.max(maxY, y1)
	end
	local W, H = maxX - minX, maxY - minY
	local parts = {}
	for _, b in boxes do
		table.insert(parts, { fx = (b[1] - minX) / W, fy = (b[2] - minY) / H, fw = (b[3] - b[1]) / W, fh = (b[4] - b[2]) / H, kind = "dome" })
	end
	return parts, (minX + maxX) / 2, (minY + maxY) / 2, W, H
end

local function boxes(list: { { any } }): ({ Part }, number, number, number, number)
	-- {kind, x0, y0, x1, y1}
	local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
	for _, b in list do
		minX, minY, maxX, maxY = math.min(minX, b[2]), math.min(minY, b[3]), math.max(maxX, b[4]), math.max(maxY, b[5])
	end
	local W, H = maxX - minX, maxY - minY
	local parts = {}
	for _, b in list do
		table.insert(parts, { fx = (b[2] - minX) / W, fy = (b[3] - minY) / H, fw = (b[4] - b[2]) / W, fh = (b[5] - b[3]) / H, kind = b[1] })
	end
	return parts, (minX + maxX) / 2, (minY + maxY) / 2, W, H
end

local ITEM_DEFS = {
	{ name = "cloud1", isCloud = true, fill = { 252, 240, 240 }, shape = function()
		return domes({ { 220, 120, 40, 80 }, { 260, 120, 30, 60 }, { 250, 120, 40, 50 } })
	end },
	{ name = "cloud2", isCloud = true, fill = { 240, 252, 240 }, shape = function()
		return domes({ { 210, 200, 30, 50 }, { 230, 200, 40, 60 }, { 260, 200, 25, 60 } })
	end },
	{ name = "cloud3", isCloud = true, fill = { 240, 240, 252 }, shape = function()
		return domes({ { 210, 240, 30, 50 }, { 260, 240, 40, 60 }, { 230, 240, 35, 50 } })
	end },
	{ name = "cloud4", isCloud = true, fill = { 252, 195, 195 }, shape = function()
		return domes({ { 210, 280, 30, 50 }, { 260, 280, 30, 60 }, { 230, 280, 25, 50 }, { 215, 280, 35, 40 } })
	end },
	{ name = "tree1", isTree = true, fill = { 120, 250, 87 }, shape = function()
		return boxes({ { "trunk", 180, 200, 215, 230 }, { "top", 170, 130, 230, 205 } })
	end },
	{ name = "tree2", isTree = true, fill = { 87, 250, 115 }, shape = function()
		return boxes({ { "trunk", 188, 143, 212, 240 }, { "top", 180, 125, 220, 160 } })
	end },
	{ name = "tree3", isTree = true, fill = { 54, 255, 101 }, shape = function()
		return boxes({ { "trunk", 116, 180, 171, 240 }, { "top", 117, 150, 169, 215 } })
	end },
}

---------------------------------------------------------------------------
-- Sim
---------------------------------------------------------------------------

local Sim = {}
Sim.__index = Sim
TakeFlight.Sim = Sim

local function overlaps(ax, ay, aw, ah, bx, by, bw, bh): boolean
	return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
end

function Sim.new(rng: Random?)
	local self = setmetatable({}, Sim)
	self.rng = rng or Random.new()

	-- Time & score
	self.stepCount = 0
	self.second = 0
	self.minute = 0
	self.score = 0

	-- Map
	self.mapSpeed = 1
	self.mapItems = {} -- ordered list of item refs currently "on the map"
	self.items = {}
	self.byName = {}
	for _, def in ITEM_DEFS do
		local parts, cx, cy, w, h = def.shape()
		local item = {
			name = def.name,
			isCloud = def.isCloud == true,
			isTree = def.isTree == true,
			fill = def.fill,
			parts = parts,
			cx = cx, cy = cy, w = w, h = h,
			distance = 1,
			opacity = 100,
			visible = false,
		}
		table.insert(self.items, item)
		self.byName[def.name] = item
	end
	self.cloudList = { self.byName.cloud1, self.byName.cloud2, self.byName.cloud3, self.byName.cloud4 }
	self.treeList = { self.byName.tree1, self.byName.tree2, self.byName.tree3 }
	-- tree1 group was nudged (+60, +10) and tree2 resized in the source before use; irrelevant once respawned.

	self.cloudCount = 0
	self.cloudLimit = false
	self.cloudGenCount = 0
	self.treeCount = 0
	self.treeLimit = false
	self.treeGenCount = 0

	-- Skill points
	self.skillPoints = 0
	self.statPointRequirement = 200
	self.firstReq, self.secondReq, self.thirdReq, self.fourthReq = false, false, false, false

	-- Plane: Polygon(40,185,50,200,40,215,90,200) -> bounds 40..90 x 185..215
	local plane = {
		cx = 65, cy = 200, w = 50, h = 30, rot = 0,
		Durability = 2, Power = 2, Mobility = 2, Precision = 2,
		Iframes = 15,
		changingDirection = false,
		drag = 2,
		momentum = 0,
	}
	self.plane = plane
	self.ogDura, self.ogPowa, self.ogMobl, self.ogPrec = 2, 2, 2, 2
	self.ogFrames = 15
	self.iframesActivated = false
	plane.acceleration = acceleration_stats[plane.Mobility]
	self:_applyStats()

	-- Bullets
	self.bullets = {}
	self.bulletsFired = false
	self.bulletCount = 0
	self.bulletLimit = 600

	-- Keys & cooldowns
	self.wKey, self.aKey, self.sKey, self.dKey = false, false, false, false
	self.firingCooldown = false
	self.directionChangeCooldown = false

	-- Health
	self.hp = plane.healthValue
	self.statOpen = false
	self.finished = false -- hp <= 0 -> app.stop()
	self.log = {} -- recent event messages (the source prints them)
	return self
end

function Sim:_say(msg: string)
	table.insert(self.log, msg)
	if #self.log > 6 then
		table.remove(self.log, 1)
	end
end

function Sim:_applyStats()
	local p = self.plane
	-- The source branches on "!= og" but both branches index the same tables.
	p.healthValue, p.healthRegen, p.damageReduction = TakeFlight.durabilityStats(p.Durability)
	local m = clampIndex(p.Mobility, 5)
	p.flightSpeed = flight_speed_stats[m]
	p.turningSpeed = turning_stats[m]
	p.ascentSpeed = ascent_speed_stats[m]
	p.decentSpeed = decent_speed_stats[m]
	local pw = clampIndex(p.Power, 5)
	self.bulletDamage = bullet_damage_stats[pw]
	self.bulletKnockback = bullet_knockback_stats[pw]
	local pr = clampIndex(p.Precision, 5)
	self.bloom = bloom_stats[pr]
	self.bulletSpeed = bullet_speed_stats[pr]
end

-- Item geometry helpers
local function itemBox(it)
	return it.cx - it.w / 2, it.cy - it.h / 2, it.w, it.h
end

function Sim:_onMap(it): boolean
	return table.find(self.mapItems, it) ~= nil
end

function Sim:_addToMap(it)
	if not self:_onMap(it) then
		table.insert(self.mapItems, it)
	end
end

function Sim:_removeFromMap(it)
	local i = table.find(self.mapItems, it)
	if i then
		table.remove(self.mapItems, i)
	end
end

function Sim:_afterRemoval(it)
	if self.cloudLimit and self.cloudCount > 0 and it.isCloud then
		self.cloudCount -= 1
		if #self.mapItems == 2 and self.cloudCount == 1 then -- "Fixes one cloud spawn bug"
			self.cloudCount -= 1
		end
	end
	if self.treeLimit and it.isTree then
		self.treeCount -= 1
		if #self.mapItems == 2 and self.treeCount == 1 then -- "Fixes one tree spawn bug"
			self.treeCount -= 1
		end
	end
end

function Sim:_planeHits(it): boolean
	if not self:_onMap(it) or not it.visible or it.opacity <= 0 then
		return false
	end
	local p = self.plane
	local x, y, w, h = itemBox(it)
	return overlaps(p.cx - p.w / 2, p.cy - p.h / 2, p.w, p.h, x, y, w, h)
end

local function bulletHits(b, it): boolean
	local x, y, w, h = itemBox(it)
	return overlaps(b.x, b.y, 10, 5, x, y, w, h)
end

function Sim:_generateTree()
	if self.treeGenCount >= 3 then
		self.treeGenCount = 0
	end
	if self.treeCount < 2 then
		self.treeLimit = false
		local rng = self.rng
		local t = self.treeList[self.treeGenCount + 1]
		t.distance = rng:NextInteger(5, 9)
		t.h = 110 + rng:NextInteger(-5, 27)
		t.w = 40 + rng:NextInteger(-3, 5)
		if rng:NextInteger(1, 3) == 1 then
			t.distance += 5
		end
		t.visible = true
		t.cx = rng:NextInteger(500, 549)
		t.cy = rng:NextInteger(350, 359)
		self:_addToMap(t)
		self.treeGenCount += 1
		self.treeCount += 1
	else
		self.treeLimit = true
	end
end

function Sim:_generateCloud()
	if self.cloudGenCount >= 4 then
		self.cloudGenCount = 0
	end
	if self.cloudCount < 2 then
		self.cloudLimit = false
		local rng = self.rng
		local c = self.cloudList[self.cloudGenCount + 1]
		c.distance = rng:NextInteger(6, 17)
		if c.distance < 10 then
			c.h = c.distance * 3
			c.w = c.distance * 10
			if rng:NextInteger(1, 3) == 1 then
				c.distance += 5
			end
		end
		c.visible = true
		c.cx += rng:NextInteger(500, 699) -- cumulative, as in the source
		c.cy = rng:NextInteger(20, 249)
		self:_addToMap(c)
		self.cloudCount += 1
		self.cloudGenCount += 1
	else
		self.cloudLimit = true
	end
end

-- onMousePress (gameplay part). Returns true if a bullet was fired.
function Sim:fire(): boolean
	if self.bulletCount >= self.bulletLimit then
		self.firingCooldown = true
	end
	if not self.firingCooldown and not self.statOpen and not self.finished then
		local p = self.plane
		table.insert(self.bullets, {
			x = p.cx, -- Rect(Plane.centerX, Plane.centerY-5, 10, 5): left/top
			y = p.cy - 5,
			rot = self.rng:NextInteger(-self.bloom, self.bloom - 1),
		})
		self.bulletCount += 1
		return true
	end
	return false
end

function Sim:toggleStatWindow()
	self.statOpen = not self.statOpen
end

-- stat: "Durability" | "Power" | "Mobility" | "Precision"
function Sim:statUp(stat: string)
	local p = self.plane
	if self.skillPoints > 0 and p[stat] <= 4 then
		self.skillPoints -= 1
		p[stat] += 1
	end
	self:_applyStats()
end

function Sim:statDown(stat: string)
	local p = self.plane
	if p[stat] >= 2 then
		self.skillPoints += 1
		p[stat] -= 1
	end
	self:_applyStats()
end

-- Code effects (validated by the caller / parseInteger).
function Sim:setScore(n: number)
	self.score = n
end

function Sim:setDurability(n: number)
	self.plane.Durability = n
	self:_applyStats()
end

-- Strict integer parse matching Python int() on plain decimal text,
-- bounded so the value stays exactly representable.
function TakeFlight.parseInteger(text: string, minValue: number, maxValue: number): number?
	local s = string.gsub(text, "^%s*(.-)%s*$", "%1")
	s = string.gsub(s, "_", "")
	if not string.match(s, "^[%+%-]?%d+$") then
		return nil
	end
	local n = tonumber(s)
	if n == nil or n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	if n < minValue or n > maxValue then
		return nil
	end
	return n
end

export type HeldKeys = { w: boolean, a: boolean, s: boolean, d: boolean }

-- onKeyHold movement (the code chords are handled by the session).
function Sim:keyHold(k: HeldKeys)
	if self.statOpen or self.finished then
		return
	end
	local p = self.plane
	local rng = self.rng
	if k.w and k.s then
		p.cy += rng:NextInteger(-1, 1)
		p.rot += rng:NextInteger(-3, 2)
		self.directionChangeCooldown = true
		p.changingDirection = false
	end
	if k.d and p.cx <= 60 then
		p.cx += p.flightSpeed
		self.dKey = true
	elseif k.d and p.cx <= 120 then
		p.cx += p.flightSpeed - p.drag / 3
		self.dKey = true
	elseif k.d and p.cx <= 160 then
		p.cx += p.flightSpeed - p.drag / 2
		self.dKey = true
	end
	if k.a and p.cx >= 40 then
		p.cx -= p.flightSpeed + p.drag / 2
		self.aKey = true
	elseif k.a and p.cx >= 25 then
		p.cx -= p.flightSpeed
		self.aKey = true
	elseif k.a and p.cx < 25 then
		p.cx -= p.flightSpeed / 8
		self.aKey = true
	end
	if k.w and not self.sKey then
		if self.directionChangeCooldown then
			p.cy -= p.ascentSpeed / 5
		end
		if not self.directionChangeCooldown then
			self.wKey = true
			p.cy -= p.ascentSpeed ^ p.acceleration
			if p.acceleration <= 20 then
				p.acceleration += 1
			end
			p.changingDirection = true
			if p.rot <= 0 and p.rot >= -26 then
				p.rot -= 2
			end
			if p.rot < -26 then
				p.rot -= 1
			end
			p.momentum = p.ascentSpeed ^ p.acceleration
		end
	end
	if k.s and not self.wKey then
		if self.directionChangeCooldown then
			p.cy += p.decentSpeed / 5
		end
		if not self.directionChangeCooldown then
			self.sKey = true
			p.cy += p.decentSpeed ^ p.acceleration
			if p.acceleration <= 20 then
				p.acceleration += 1
			end
			p.changingDirection = true
			if p.rot >= 0 and p.rot <= 26 then
				p.rot += 2
			end
			if p.rot > 26 then
				p.rot += 1
			end
			p.momentum = p.decentSpeed ^ p.acceleration
		end
	end
end

-- onKeyRelease: "w" | "s" | "a" | "d"
function Sim:keyRelease(key: string)
	local p = self.plane
	if key == "w" then
		self.wKey = false
		p.acceleration = 1
		p.changingDirection = false
	elseif key == "s" then
		self.sKey = false
		p.acceleration = 1
		p.changingDirection = false
	elseif key == "a" then
		self.aKey = false
	elseif key == "d" then
		self.dKey = false
	end
end

function Sim:_damage(amount: number)
	self.hp -= amount - amount * self.plane.damageReduction
end

function Sim:step()
	if self.finished then
		return
	end
	local p = self.plane
	local rng = self.rng
	if not self.statOpen then
		self.stepCount += 1
		if self.stepCount % 30 == 0 then
			self.second += 1
			self.stepCount = 0
			if self.second % 60 == 0 then
				self.minute += 1
				self.second = 0
			end
		end
		if self.stepCount % 5 == 0 then
			self.score += 1 * p.acceleration
		end

		if self.statPointRequirement < self.score then
			self.skillPoints += 1
			if self.statPointRequirement == 200 and not self.firstReq then
				self.statPointRequirement = 400
				self.firstReq = true
			elseif self.statPointRequirement == 400 and not self.secondReq then
				self.statPointRequirement = 750
				self.secondReq = true
			elseif self.statPointRequirement == 750 and not self.thirdReq then
				self.statPointRequirement = 1000
				self.thirdReq = true
			elseif self.statPointRequirement == 1000 and not self.fourthReq then
				self.statPointRequirement = 2000
				self.fourthReq = true -- "Becomes Always True ON PURPOSE": +1 point every step above 2000
			end
		end

		-- Health, regen, i-frames, death
		if self.stepCount % 30 == 0 and self.hp < p.healthValue then
			self.hp += p.healthRegen
		end
		if self.iframesActivated then
			p.Iframes -= 1
			if p.Iframes <= 0 then
				self.iframesActivated = false
				p.Iframes += self.ogFrames
			end
		end
		if self.hp <= 0 then
			self.finished = true -- app.stop()
			return
		end

		-- Scroll map items
		for _, it in table.clone(self.mapItems) do
			it.cx -= self.mapSpeed * it.distance
			if self.dKey then
				it.cx -= p.flightSpeed / 2
			elseif self.aKey then
				it.cx += p.flightSpeed / 2
			end
			if it.cx + it.w / 2 < 0 then
				self:_removeFromMap(it)
				self:_afterRemoval(it)
			end
		end

		-- Level the plane and apply momentum
		if not p.changingDirection then
			self.directionChangeCooldown = true
			if p.rot < 0 then
				if p.rot <= -20 then
					p.rot += 2 + p.turningSpeed
				elseif p.rot <= -5 then
					p.rot += 1 + p.turningSpeed
				else
					p.rot += 1
				end
				p.cy -= p.momentum
				if p.momentum > 0 then
					p.momentum -= 2
				end
			elseif p.rot > 0 then
				if p.rot >= 20 then
					p.rot -= 2 + p.turningSpeed
				elseif p.rot >= 5 then
					p.rot -= 1 + p.turningSpeed
				else
					p.rot -= 1
				end
				p.cy += p.momentum
				if p.momentum > 0 then
					p.momentum -= 2
				end
			end
			if p.rot == 0 then
				self.directionChangeCooldown = false
				p.momentum = 0
			end
		end

		-- Bullets travel with bloom
		for _, b in self.bullets do
			local bcx = b.x + 5
			local angle = trunc(b.rot)
			if bcx < 160 then
				b.y += angle / 8
			end
			if bcx < 275 then
				b.x += self.bulletSpeed * 4
				b.y += angle / 4
			elseif bcx < 355 then
				b.x += self.bulletSpeed * 2
				b.y += angle / 2
			elseif bcx < 370 then
				b.x += self.bulletSpeed + 1
				b.y += angle / 1.5
			elseif bcx < 395 then
				b.x += self.bulletSpeed + 1
				b.y += angle
			else
				b.x += self.bulletSpeed
			end
		end

		-- Hazards (checked in source order; each sets i-frames)
		local by = self.byName
		if self:_planeHits(by.cloud1) and not self.iframesActivated then
			self:_damage(20)
			self:_say("Damage has been taken (Cloud)")
			if rng:NextInteger(1, 9) == 1 then
				self:_damage(20)
				self:_say("It's a Critcal Hit! (Cloud)")
			end
			self.iframesActivated = true
		end
		if self:_planeHits(by.cloud2) and not self.iframesActivated then
			if self.hp < p.healthValue then
				self.hp += 10
				self:_say("Healing has been giving (Cloud)")
				if rng:NextInteger(1, 9) == 1 and self.hp < p.healthValue then
					self.hp += 50
					self:_say("Superb Heal! (Cloud)")
				end
				self.iframesActivated = true
			end
		end
		if self:_planeHits(by.cloud3) and not self.iframesActivated then
			self:_damage(15)
			self:_say("Damage has been taken (Cloud)")
			if rng:NextInteger(1, 9) == 1 then
				self:_damage(15)
				self:_say("Its a Critcal Hit! (Cloud)")
			end
			if rng:NextInteger(1, 3) == 1 then
				if p.Mobility < 5 then
					p.Mobility += 1
					self:_say("Speed has been increased (Cloud)")
				end
			else
				if p.Mobility > 1 then
					p.Mobility -= 1
					self:_say("Speed has been decreased (Cloud)")
				end
			end
			self.iframesActivated = true
		end
		if self:_planeHits(by.cloud4) and not self.iframesActivated then
			self:_damage(50)
			self:_say("Heavy Damage has been taken (Cloud)")
			-- randrange(1,2) is always 1 in the source
			if p.Durability > 1 then
				p.Durability -= 1
				self:_say("Due to Damage, Durability has been decreased (Cloud)")
			end
			if rng:NextInteger(1, 9) == 1 then
				self:_damage(50)
				self:_say("Its a Critcal Hit! (Cloud)")
			end
			self.iframesActivated = true
		end
		if self:_planeHits(by.tree1) and not self.iframesActivated then
			self:_damage(30)
			self:_say("Damage has been taken (Tree1)")
			if rng:NextInteger(1, 3) == 1 and p.Power > 1 then
				p.Power -= 1
				self:_say("Tree Branches have got into your gun, Power has been decreased (Tree1)")
			end
			if rng:NextInteger(1, 9) == 1 then
				self:_damage(30)
				self:_say("Its a Critcal Hit! (Tree1)")
			end
			self.iframesActivated = true
		end
		if self:_planeHits(by.tree2) and not self.iframesActivated then
			self:_damage(10)
			-- randrange(1,2) is always 1: the "critical" always lands and the goblin always steals
			self:_damage(10)
			self:_say("Its a Critcal Hit! (Tree2)")
			if self.score > 0 then
				self.score -= 100
				self:_say("A Goblin in the tree stole your score! (Tree2)")
			end
			self.iframesActivated = true
		end
		if self:_planeHits(by.tree3) and not self.iframesActivated then
			self:_damage(45)
			if rng:NextInteger(1, 9) == 1 then
				self:_damage(45)
				self:_say("Its a Critcal Hit! (Tree3)")
			end
			if rng:NextInteger(1, 3) == 1 and p.Precision > 1 then
				p.Precision -= 1
				self:_say("Leaves Block your vision, Precision has been decreased (Tree3)")
			end
			self.iframesActivated = true
		end

		-- Out of bounds: world_border.contains(Plane.right, Plane.centerY)
		local right = p.cx + p.w / 2
		if not (right >= 0 and right <= 400 and p.cy >= 0 and p.cy <= 400) then
			if not self.iframesActivated then
				self:_damage(40)
				self.iframesActivated = true
				self:_say("Damage has been taken (Out of Bounds)")
			end
		end

		-- Bullets vs items
		for _, it in table.clone(self.mapItems) do
			local hit = false
			for _, b in self.bullets do
				if bulletHits(b, it) then
					hit = true
					break
				end
			end
			if hit then
				local dmg = (it.distance * 2) * (self.bulletDamage / 2)
				if it.opacity - dmg > 0 then
					it.opacity -= dmg
				elseif it.opacity - dmg < 0 then
					it.opacity = 0
				end
				if p.Power > 2 then
					it.cx += self.bulletKnockback * it.distance
				end
			end
			for i = #self.bullets, 1, -1 do
				if bulletHits(self.bullets[i], it) then
					table.remove(self.bullets, i)
					self.bulletCount -= 1
				end
			end
			if it.opacity <= 0 then
				it.opacity = 100
				self:_removeFromMap(it)
				self:_afterRemoval(it)
			end
		end

		-- clean_bullets: any bullet past x 405 clears all bullets (source behaviour)
		for _, b in table.clone(self.bullets) do
			if b.x + 5 > 405 then
				self.bulletsFired = true
				table.clear(self.bullets)
				self.bulletCount -= 1
			end
		end
		self.bulletsFired = false
		if not self.bulletsFired then
			self.firingCooldown = false
		end

		self:_generateCloud()
		self:_generateTree()

		-- Drag
		p.cx -= p.drag / 10
		if p.cx < 30 then
			p.cx -= p.drag / 2
		end
		if p.cy < 70 then
			p.cy -= p.drag / 5
			if p.cy < 40 then
				p.cy -= p.drag / 4
				if p.cy < 10 then
					p.cy -= p.drag / 2
				end
			end
		end
		if p.cy > 330 then
			p.cy += p.drag / 5
			if p.cy > 370 then
				p.cy += p.drag / 4
				if p.cy > 390 then
					p.cy += p.drag / 2
				end
			end
		end
		if p.cx > 130 then
			p.cx -= p.drag / 2
		end
	end
	self:_applyStats()
end

function Sim:healthText(): string
	return tostring(trunc(self.hp)) .. "/" .. tostring(self.plane.healthValue)
end

function Sim:clockText(): string
	return tostring(self.minute) .. ":" .. tostring(self.second)
end

---------------------------------------------------------------------------
-- Session
---------------------------------------------------------------------------

local Session = {}
Session.__index = Session

local STATS = { "Durability", "Power", "Mobility", "Precision" }
local STAT_X = { 95, 165, 235, 305 }
local STAT_ICON = { "springGreen", "fireBrick", "lightSkyBlue", "darkOrange" }
local STAT_ICON_TEXT = { "Shield\nIcon", "Bullet\nIcon", "Flying\nPlane\nIcon", "Gun\nCorsair\nIcon" }

function TakeFlight.new(context: any)
	assert(type(context) == "table", "TakeFlight.new: context table required")
	assert(typeof(context.container) == "Instance", "TakeFlight.new: context.container required")
	assert(type(context.requestExit) == "function", "TakeFlight.new: context.requestExit required")
	local self = setmetatable({}, Session)
	self.context = context
	self.conns = {}
	self.destroyed = false
	self.started = false
	self.phase = "idle" -- running | prompt | result
	self.dialog = nil
	self.chordLatch = { score = false, dura = false }
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
	local gamesFolder = script.Parent
	local arcadeFolder = gamesFolder and gamesFolder.Parent
	local ui = arcadeFolder and arcadeFolder:FindFirstChild("ui")
	assert(ui, "TakeFlight: expected sibling folder arcade/ui next to arcade/games")
	self.PlayField = require(ui:WaitForChild("PlayField"))
	self.GameChrome = require(ui:WaitForChild("GameChrome"))
	self.CodesDialog = require(ui:WaitForChild("CodesDialog"))

	self.chrome = self.GameChrome.new(self.context.container, {
		title = TakeFlight.displayName,
		controls = TakeFlight.controls,
		onCodes = function()
			self:_openCodes("any")
		end,
		onExit = function()
			self.context.requestExit("player")
		end,
	})
	self.field = self.PlayField.new(self.chrome.playArea, self.PlayField.colors.skyBlue)

	local UIS = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	self:_conn(UIS.InputBegan:Connect(function(input, processed)
		self:_onInputBegan(input, processed)
	end))
	self:_conn(UIS.InputEnded:Connect(function(input)
		-- Releases are always honoured so keys never stick (e.g. released while a dialog had focus).
		if not self.sim then
			return
		end
		local k = input.KeyCode
		if k == Enum.KeyCode.W then
			self.sim:keyRelease("w")
		elseif k == Enum.KeyCode.S then
			self.sim:keyRelease("s")
		elseif k == Enum.KeyCode.A then
			self.sim:keyRelease("a")
		elseif k == Enum.KeyCode.D then
			self.sim:keyRelease("d")
		end
	end))
	local acc = 0
	self:_conn(RunService.RenderStepped:Connect(function(dt)
		if self.phase ~= "running" or not self.sim then
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

	self:_beginRun()
end

function Session:_keysBlocked(): boolean
	local UIS = game:GetService("UserInputService")
	return self.CodesDialog.isAnyOpen() or UIS:GetFocusedTextBox() ~= nil
end

function Session:_onInputBegan(input: InputObject, processed: boolean)
	if processed or self.phase ~= "running" or self:_keysBlocked() then
		return
	end
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		-- Only clicks inside the playfield fire (GUI buttons report processed = true).
		local x, y = self.PlayField.toLogical(self.field, Vector2.new(input.Position.X, input.Position.Y))
		if x >= 0 and x <= 400 and y >= 0 and y <= 400 then
			self.sim:fire()
		end
	end
end

local function shiftDown(UIS): boolean
	return UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
end

function Session:_tick()
	local sim = self.sim
	if not self:_keysBlocked() then
		local UIS = game:GetService("UserInputService")
		local function down(k)
			return UIS:IsKeyDown(k)
		end
		-- Legacy chords: 'S'+'('+')' = Shift+S+9+0 ; 'D'+'+'+'T' = Shift+D+=+T (US layout)
		local shift = shiftDown(UIS)
		local scoreChord = shift and down(Enum.KeyCode.S) and down(Enum.KeyCode.Nine) and down(Enum.KeyCode.Zero)
		local duraChord = shift and down(Enum.KeyCode.D) and down(Enum.KeyCode.Equals) and down(Enum.KeyCode.T)
		if not scoreChord then
			self.chordLatch.score = false
		end
		if not duraChord then
			self.chordLatch.dura = false
		end
		if not sim.statOpen then
			if scoreChord and not self.chordLatch.score then
				self.chordLatch.score = true
				self:_openCodes("score")
				return
			end
			if duraChord and not self.chordLatch.dura then
				self.chordLatch.dura = true
				self:_openCodes("dura")
				return
			end
		end
		local k = { w = down(Enum.KeyCode.W), a = down(Enum.KeyCode.A), s = down(Enum.KeyCode.S), d = down(Enum.KeyCode.D) }
		if k.w or k.a or k.s or k.d then
			sim:keyHold(k)
		end
	end
	sim:step()
	if sim.finished then
		self:_showResult()
	end
end

---------------------------------------------------------------------------
-- Codes
---------------------------------------------------------------------------

-- route: "any" (Codes button) | "score" | "dura" (legacy chords accept only their own code)
function Session:_openCodes(route: string)
	if self.destroyed or self.dialog or not self.sim then
		return
	end
	if self.phase == "result" then
		self.chrome:setStatus("Start a new flight to use codes.")
		return
	end
	local resumePhase = self.phase
	self.phase = "prompt" -- the original getTextInput blocks, pausing the game
	local stage = "code"
	local function finish()
		self.dialog = nil
		if self.phase == "prompt" then
			self.phase = resumePhase
		end
	end
	self.dialog = self.CodesDialog.open(self.field, {
		title = "Take Flight! codes",
		prompt = "?",
		placeholder = "code",
		onSubmit = function(text, dialog)
			if stage == "code" then
				local wantScore = text == TakeFlight.SCORE_CODE and (route == "any" or route == "score")
				local wantDura = text == TakeFlight.DURA_CODE and (route == "any" or route == "dura")
				if wantScore then
					stage = "score"
					dialog:setPrompt("Whats the New Score?", "whole number")
				elseif wantDura then
					stage = "dura"
					dialog:setPrompt("Un-Cap Dura?", "whole number, 1 or more")
				elseif route ~= "any" then
					-- Original: an unrecognised answer simply returns.
					dialog:close()
					finish()
				else
					dialog:setFeedback("Unknown code. Nothing changed.", true)
				end
			elseif stage == "score" then
				local n = TakeFlight.parseInteger(text, -TakeFlight.MAX_SCORE_INPUT, TakeFlight.MAX_SCORE_INPUT)
				if not n then
					dialog:setFeedback("Enter a whole number (up to ±1,000,000,000,000).", true)
					return
				end
				self.sim:setScore(n)
				dialog:close()
				finish()
				self.chrome:setStatus("Score set to " .. tostring(n) .. ".")
			elseif stage == "dura" then
				local n = TakeFlight.parseInteger(text, 1, TakeFlight.MAX_DURABILITY_INPUT)
				if not n then
					dialog:setFeedback("Enter a whole number from 1 to 1,000,000.", true)
					return
				end
				self.sim:setDurability(n)
				dialog:close()
				finish()
				self.chrome:setStatus("Durability set to " .. tostring(n) .. ".")
			end
		end,
		onCancel = finish,
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

function Session:_beginRun()
	self:_clearField()
	self.sim = Sim.new()
	self.chordLatch = { score = true, dura = true } -- require a fresh press
	self:_buildView()
	self.phase = "running"
	self.chrome:setStatus("Click to fire Bullets!")
end

function Session:_showResult()
	if self.phase == "result" then
		return
	end
	self.phase = "result"
	self:_render()
	local PF = self.PlayField
	local sim = self.sim
	local holder = Instance.new("Frame")
	holder.Name = "Result"
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundColor3 = Color3.new(0, 0, 0)
	holder.BackgroundTransparency = 0.35
	holder.ZIndex = 45
	holder.Active = true
	holder.Parent = self.field
	PF.label(holder, { text = "Your plane went down", cx = 200, cy = 120, size = 26, color = PF.colors.white, font = Enum.Font.SciFi, z = 46 })
	PF.label(holder, { text = "Score | " .. tostring(sim.score) .. "    Time " .. sim:clockText(), cx = 200, cy = 160, size = 15, color = PF.colors.white, z = 46 })
	local function btn(text, y, color)
		local b = Instance.new("TextButton")
		b.Text = text
		b.Font = Enum.Font.GothamBold
		b.TextScaled = true
		b.TextColor3 = Color3.new(1, 1, 1)
		b.BackgroundColor3 = color
		b.AnchorPoint = Vector2.new(0.5, 0)
		b.Position = UDim2.fromScale(0.5, y)
		b.Size = UDim2.fromScale(0.5, 0.09)
		b.ZIndex = 46
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.2, 0)
		c.Parent = b
		local p = Instance.new("UIPadding")
		p.PaddingTop = UDim.new(0.2, 0)
		p.PaddingBottom = UDim.new(0.2, 0)
		p.Parent = b
		b.Parent = holder
		return b
	end
	local again = btn("Fly again", 0.5, Color3.fromRGB(46, 139, 87))
	local menu = btn("Back to menu", 0.62, Color3.fromRGB(140, 40, 40))
	self:_conn(again.Activated:Connect(function()
		if self.phase == "result" then
			self:_beginRun()
		end
	end))
	self:_conn(menu.Activated:Connect(function()
		self.context.requestExit("player")
	end))
	self.chrome:setStatus("Flight over.")
end

---------------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------------

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

function Session:_buildView()
	local PF = self.PlayField
	local C = PF.colors
	local f = self.field
	local v = {}
	self.view = v

	-- Static scenery (simplified from the source polygons: same layout and palette)
	local sky = PF.rect(f, { left = 0, top = 0, w = 400, h = 400, color = C.white, z = 1, name = "Sky" })
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, C.white),
		ColorSequenceKeypoint.new(0.5, C.skyBlue),
		ColorSequenceKeypoint.new(1, C.orange),
	})
	g.Parent = sky
	PF.rect(f, { left = 160, top = 240, w = 80, h = 80, color = C.yellow, z = 2, round = true, name = "Sun" })
	local function peak(cx, base, size, color, z)
		local d = PF.rect(f, { left = cx - size / 2, top = base - size / 2, w = size, h = size, color = color, z = z })
		d.Rotation = 45
		return d
	end
	peak(126, 290, 115, C.silver, 3) -- back mountain
	peak(160, 345, 40, C.gainsboro, 4) -- small front mountain
	peak(60, 330, 100, C.lightGray, 4) -- front mountain
	PF.rect(f, { left = 0, top = 270, w = 400, h = 130, color = C.forestGreen, z = 3, name = "BackGrass" })
	PF.rect(f, { left = 0, top = 270, w = 400, h = 130, color = C.black, opacity = 20, z = 3 })
	PF.rect(f, { left = 206, top = 278, w = 176, h = 36, color = C.blue, z = 5, round = true, name = "Pond" })
	PF.rect(f, { left = 209, top = 305, w = 175, h = 22, color = C.forestGreen, z = 6, name = "PondGrass" })
	PF.rect(f, { left = 0, top = 326, w = 400, h = 74, color = C.darkGreen, z = 6 })
	PF.rect(f, { left = 0, top = 340, w = 400, h = 60, color = C.darkOliveGreen, z = 7 })
	PF.rect(f, { left = 0, top = 352, w = 213, h = 48, color = C.oliveDrab, z = 8 })
	PF.rect(f, { left = 100, top = 360, w = 300, h = 40, color = C.seaGreen, z = 8 })
	PF.rect(f, { left = 0, top = 378, w = 400, h = 22, color = C.limeGreen, z = 9 })

	-- Bullets, plane, HUD, then map items (the source draws items above the plane)
	v.bulletLayer = Instance.new("Frame")
	v.bulletLayer.BackgroundTransparency = 1
	v.bulletLayer.Size = UDim2.fromScale(1, 1)
	v.bulletLayer.ZIndex = 10
	v.bulletLayer.Parent = f
	v.bulletFrames = {}

	local plane = Instance.new("Frame")
	plane.Name = "Plane"
	plane.BackgroundTransparency = 1
	plane.ZIndex = 11
	plane.Parent = f
	-- Dart shape (40,185)-(50,200)-(40,215)-(90,200) approximated with three bars.
	local function bar(x, y, w, h, rot)
		local b = Instance.new("Frame")
		b.BorderSizePixel = 0
		b.BackgroundColor3 = C.black
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = UDim2.fromScale(x, y)
		b.Size = UDim2.fromScale(w, h)
		b.Rotation = rot
		b.ZIndex = 11
		b.Parent = plane
	end
	bar(0.6, 0.5, 0.8, 0.22, 0) -- fuselage to the nose
	bar(0.15, 0.27, 0.42, 0.14, 50) -- upper tail
	bar(0.15, 0.73, 0.42, 0.14, -50) -- lower tail
	v.plane = plane

	v.clockShadow = PF.label(f, { text = "0:0", cx = 79, cy = 21, size = 15, color = C.dimGray, opacity = 60, z = 12, width = 100 })
	v.clock = PF.label(f, { text = "0:0", cx = 80, cy = 20, size = 15, color = C.white, z = 12, width = 100 })
	v.scoreShadow = PF.label(f, { text = "Score | 0", cx = 79, cy = 41, size = 18, color = C.dimGray, opacity = 60, font = Enum.Font.SciFi, z = 12, width = 160 })
	v.score = PF.label(f, { text = "Score | 0", cx = 80, cy = 40, size = 18, color = C.white, font = Enum.Font.SciFi, z = 12, width = 160 })

	v.itemLayer = Instance.new("Frame")
	v.itemLayer.BackgroundTransparency = 1
	v.itemLayer.Size = UDim2.fromScale(1, 1)
	v.itemLayer.ZIndex = 13
	v.itemLayer.Parent = f
	v.itemFrames = {}
	for _, it in self.sim.items do
		local holder = Instance.new("Frame")
		holder.Name = it.name
		holder.BackgroundTransparency = 1
		holder.ZIndex = 13
		holder.Visible = false
		holder.Parent = v.itemLayer
		local parts = {}
		for _, part in it.parts do
			local box = Instance.new("Frame")
			box.BorderSizePixel = 0
			box.Position = UDim2.fromScale(part.fx, part.fy)
			box.Size = UDim2.fromScale(part.fw, part.fh)
			box.ZIndex = if part.kind == "top" then 14 else 13
			box.Parent = holder
			if part.kind == "dome" then
				-- Half ellipse: clip the lower half of a rounded frame.
				box.BackgroundTransparency = 1
				box.ClipsDescendants = true
				local e = Instance.new("Frame")
				e.BorderSizePixel = 0
				e.Size = UDim2.fromScale(1, 2)
				e.ZIndex = 13
				local c = Instance.new("UICorner")
				c.CornerRadius = UDim.new(0.5, 0)
				c.Parent = e
				e.Parent = box
				table.insert(parts, { frame = e, kind = "dome" })
			else
				box.BackgroundColor3 = if part.kind == "trunk" then C.sienna else rgb(it.fill)
				if part.kind == "top" then
					local c = Instance.new("UICorner")
					c.CornerRadius = UDim.new(0.35, 0)
					c.Parent = box
				end
				table.insert(parts, { frame = box, kind = part.kind })
			end
		end
		v.itemFrames[it] = { holder = holder, parts = parts }
	end

	local border = PF.rect(f, { left = 0, top = 0, w = 400, h = 400, color = C.white, opacity = 0, border = C.white, borderWidth = 4, z = 15, name = "WorldBorder" })
	local borderStroke = border:FindFirstChildOfClass("UIStroke")
	if borderStroke then
		borderStroke.Transparency = 0.9 -- opacity=10 in the source
	end

	-- Health bar
	PF.rect(f, { left = 200, top = 0, w = 200, h = 40, color = C.crimson, z = 16, name = "UnderBar" })
	v.mainBar = PF.rect(f, { left = 200, top = 0, w = 200, h = 40, color = C.forestGreen, z = 17, name = "MainBar" })
	PF.rect(f, { left = 200, top = 0, w = 200, h = 40, opacity = 0, border = C.black, borderWidth = 2, z = 18, name = "BarBorder" })
	for i = 0, 3 do
		PF.rect(f, { left = 239 + 40 * i, top = 0, w = 1.5, h = 40, color = C.black, z = 18 })
	end
	v.health = PF.label(f, { text = "", cx = 300, cy = 20, size = 20, color = C.white, font = Enum.Font.GothamBold, z = 19, width = 190 })

	-- Event log (the source prints these to the console)
	v.log = PF.label(f, { text = "", cx = 200, cy = 62, size = 9, color = C.white, z = 19, width = 380 })

	-- Stat window opener tab
	local tab = Instance.new("TextButton")
	tab.Name = "StatTab"
	tab.Text = "▲"
	tab.Font = Enum.Font.GothamBlack
	tab.TextScaled = true
	tab.TextColor3 = C.black
	tab.BackgroundColor3 = C.white
	tab.ZIndex = 20
	PF.place(tab, 120, 370, 160, 30)
	tab.Parent = f
	v.tab = tab
	self:_conn(tab.Activated:Connect(function()
		if self.phase == "running" and self.sim then
			self.sim:toggleStatWindow()
			self:_render()
		end
	end))

	-- Stat window
	local win = PF.rect(f, { left = 50, top = 60, w = 300, h = 280, color = C.white, border = C.black, z = 21, name = "StatWindow" })
	win.Visible = false
	v.statWindow = win
	-- children positioned relative to the window: convert logical coords
	local function wl(text, cx, cy, size, color, font)
		local l = PF.label(win, { text = text, cx = cx, cy = cy, size = size, color = color or C.black, font = font or Enum.Font.Garamond, z = 22 })
		-- re-express relative to the 300x280 window
		l.Position = UDim2.fromScale((cx - 50) / 300, (cy - 60) / 280)
		l.Size = UDim2.fromScale(70 / 300, (size * 1.15) / 280)
		return l
	end
	v.statCounters = {}
	for i, stat in STATS do
		local x = STAT_X[i]
		wl(stat, x, 90, 20, C.black, Enum.Font.Garamond)
		v.statCounters[stat] = wl("0", x, 130, 35, C.black, Enum.Font.Garamond)
		local icon = Instance.new("TextLabel")
		icon.Text = STAT_ICON_TEXT[i]
		icon.Font = Enum.Font.Gotham
		icon.TextScaled = true
		icon.TextColor3 = C.black
		icon.BackgroundColor3 = C[STAT_ICON[i]]
		icon.AnchorPoint = Vector2.new(0.5, 0.5)
		icon.Position = UDim2.fromScale((x - 50) / 300, (180 - 60) / 280)
		icon.Size = UDim2.fromScale(40 / 300, 40 / 280)
		icon.ZIndex = 22
		local ic = Instance.new("UICorner")
		ic.CornerRadius = UDim.new(0.5, 0)
		ic.Parent = icon
		local is = Instance.new("UIStroke")
		is.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		is.Parent = icon
		icon.Parent = win
		local function pm(text, cy, color, fn)
			local b = Instance.new("TextButton")
			b.Text = text
			b.Font = Enum.Font.Code
			b.TextScaled = true
			b.TextColor3 = color
			b.BackgroundTransparency = 1
			b.AnchorPoint = Vector2.new(0.5, 0.5)
			b.Position = UDim2.fromScale((x - 50) / 300, (cy - 60) / 280)
			b.Size = UDim2.fromScale(44 / 300, 40 / 280)
			b.ZIndex = 23
			b.Parent = win
			self:_conn(b.Activated:Connect(function()
				if self.phase == "running" and self.sim and self.sim.statOpen then
					fn(stat)
					self:_render()
				end
			end))
		end
		pm("+", 230, C.green, function(s)
			self.sim:statUp(s)
		end)
		pm("-", 270, C.red, function(s)
			self.sim:statDown(s)
		end)
	end
	v.currentSP = wl("Current Skill Points: 0", 200, 300, 20, C.black, Enum.Font.Gotham)
	v.currentSP.Size = UDim2.fromScale(0.95, 20 * 1.15 / 280)
	v.nextSP = wl("Next Score until SP gain: 200", 200, 315, 10, C.black, Enum.Font.Gotham)
	v.nextSP.Size = UDim2.fromScale(0.95, 10 * 1.15 / 280)

	PF.label(f, { text = "Ver 0.0.2.1", cx = 350, cy = 390, size = 12, color = C.white, font = Enum.Font.Code, z = 19, width = 100 })
	PF.label(f, { text = "Click to fire Bullets!", cx = 60, cy = 390, size = 8, color = C.white, font = Enum.Font.Code, opacity = 50, z = 19, width = 120 })

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
	local p = sim.plane

	PF.place(v.plane, p.cx - p.w / 2, p.cy - p.h / 2, p.w, p.h)
	v.plane.Rotation = p.rot

	-- bullets
	local bullets = sim.bullets
	while #v.bulletFrames < #bullets do
		table.insert(v.bulletFrames, PF.rect(v.bulletLayer, { left = 0, top = 0, w = 10, h = 5, color = C.gold, z = 10 }))
	end
	for i, fr in v.bulletFrames do
		local b = bullets[i]
		if b then
			fr.Visible = true
			PF.place(fr, b.x, b.y, 10, 5)
			fr.Rotation = b.rot
		else
			fr.Visible = false
		end
	end

	-- items
	for it, rec in v.itemFrames do
		local shown = it.visible and table.find(sim.mapItems, it) ~= nil
		rec.holder.Visible = shown
		if shown then
			PF.place(rec.holder, it.cx - it.w / 2, it.cy - it.h / 2, it.w, it.h)
			local alpha = PF.alpha(it.opacity)
			for _, part in rec.parts do
				if part.kind == "dome" then
					part.frame.BackgroundColor3 = rgb(it.fill)
				end
				part.frame.BackgroundTransparency = alpha
			end
		end
	end

	v.clock.Text = sim:clockText()
	v.clockShadow.Text = v.clock.Text
	v.score.Text = "Score | " .. tostring(sim.score)
	v.scoreShadow.Text = v.score.Text

	-- main_bar.left = 400 - hp*2, clamped at 200 -> visible fill covers up to 100 hp
	local left = math.max(400 - sim.hp * 2, 200)
	PF.place(v.mainBar, math.min(left, 400), 0, 200, 40)
	v.health.Text = sim:healthText()
	v.log.Text = table.concat(sim.log, "  ·  ", math.max(1, #sim.log - 1))

	v.statWindow.Visible = sim.statOpen
	v.tab.Text = if sim.statOpen then "▼" else "▲"
	for _, stat in STATS do
		local l = v.statCounters[stat]
		local val = p[stat]
		l.Text = tostring(val)
		if stat == "Durability" and val >= 6 then
			l.TextColor3 = C.cyan -- 6 is cyan in the source; beyond-cap values keep the cyan marker
		elseif val == 5 then
			l.TextColor3 = C.gold
		else
			l.TextColor3 = C.black
		end
	end
	v.currentSP.Text = "Current Skill Points: " .. tostring(sim.skillPoints)
	v.nextSP.Text = "Next Score until SP gain: " .. tostring(sim.statPointRequirement)
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
	if self.chrome then
		self.chrome:destroy()
		self.chrome = nil
	end
	self.sim = nil
	self.view = nil
end

return TakeFlight
