--!strict
-- Plays a horizontal fighter sheet from AssetManifest on a 96 x 96 canvas.
--
-- Each sheet is one row of 96 x 96 frames, grounded on row 88 like the static
-- idles. The manifest names the states (idle/guard/hit/basic/skill/heavy/
-- finisher) but not which frame is which, so CLIPS below is the client's
-- reading of the uploaded sheets. A clip frame past the sheet's frame count is
-- skipped, and a clip with no frames left plays idle.
--
-- A sheet is used when the server's spriteKey is a sheet key, or when it is a
-- static idle whose character has a sheet (SHEET_FOR_STATIC). Everything else
-- keeps the static image or the placeholder silhouette in FighterSprite.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local AssetManifest = require(ReplicatedStorage.Shared.Contracts.AssetManifest)

export type Clip = "idle" | "guard" | "hit" | "basic" | "skill" | "heavy" | "finisher"

export type Sheet = {
	key: AssetManifest.AssetKey,
	assetId: string,
	frames: number,
}

export type Player = {
	play: (self: Player, clip: Clip) -> (),
	current: (self: Player) -> (Clip, number),
	destroy: (self: Player) -> (),
}

local FRAME = 96
local UNSET = "rbxassetid://0"

-- Frame counts from the manifest notes (960 x 96 is 10 frames, 864 x 96 is 9).
local FRAME_COUNTS: { [string]: number } = {
	HierophantGreenSheet = 10,
	MagiciansRedSheet = 10,
	SilverChariotSheet = 9,
	StarPlatinumSheet = 10,
	TheWorldSheet = 10,
	EmperorSheet = 10,
	AnubisSheet = 10,
}

-- Static battle idles whose character also has a sheet.
local SHEET_FOR_STATIC: { [string]: string } = {
	KakyoinIdle = "HierophantGreenSheet",
	AvdolIdle = "MagiciansRedSheet",
}

-- 1-based frame numbers per state.
local CLIPS: { [Clip]: { number } } = {
	idle = { 1, 2 },
	guard = { 3 },
	hit = { 4 },
	basic = { 5, 6 },
	skill = { 7 },
	heavy = { 8 },
	finisher = { 9, 10 },
}

-- Seconds per frame, and how long the last frame of a one-shot is held
-- before returning to idle. The manifest gives no timing.
local IDLE_FRAME_SECONDS = 0.45
local ACTION_FRAME_SECONDS = 0.1
local HOLD_SECONDS: { [Clip]: number } = {
	guard = 0.45,
	hit = 0.3,
	basic = 0.2,
	skill = 0.3,
	heavy = 0.3,
	finisher = 0.4,
}

local SpriteSheet = {}

SpriteSheet.FRAME = FRAME
SpriteSheet.CLIPS = CLIPS

-- The sheet for a server spriteKey, or nil when it has none or it is unset.
function SpriteSheet.forKey(spriteKey: string?): Sheet?
	if spriteKey == nil then
		return nil
	end
	local key = if FRAME_COUNTS[spriteKey] then spriteKey else SHEET_FOR_STATIC[spriteKey]
	if key == nil then
		return nil
	end
	local id = (AssetManifest :: any)[key]
	if type(id) ~= "string" or id == UNSET then
		return nil
	end
	return { key = key :: any, assetId = id, frames = FRAME_COUNTS[key] }
end

-- The frames a clip plays on this sheet. Idle always has at least frame 1.
function SpriteSheet.framesFor(sheet: Sheet, clip: Clip): { number }
	local frames: { number } = {}
	for _, frame in CLIPS[clip] do
		if frame <= sheet.frames then
			table.insert(frames, frame)
		end
	end
	if #frames == 0 and clip ~= "idle" then
		return SpriteSheet.framesFor(sheet, "idle")
	end
	if #frames == 0 then
		frames = { 1 }
	end
	return frames
end

-- Shows `frame` (1-based) on the image. Mirrors by flipping the rect.
function SpriteSheet.showFrame(image: ImageLabel, frame: number, facingLeft: boolean)
	if facingLeft then
		image.ImageRectOffset = Vector2.new(frame * FRAME, 0)
		image.ImageRectSize = Vector2.new(-FRAME, FRAME)
	else
		image.ImageRectOffset = Vector2.new((frame - 1) * FRAME, 0)
		image.ImageRectSize = Vector2.new(FRAME, FRAME)
	end
end

-- Starts the idle loop on `image`. One-shots return to idle on their own.
-- The loop stops when the image leaves the DataModel or destroy() is called.
function SpriteSheet.player(image: ImageLabel, sheet: Sheet, facingLeft: boolean): Player
	local token = 0
	local clip: Clip = "idle"
	local frame = 1
	local alive = true

	local function show(value: number)
		frame = value
		SpriteSheet.showFrame(image, value, facingLeft)
	end

	local function running(mine: number): boolean
		return alive and token == mine and image.Parent ~= nil
	end

	local function idle()
		token += 1
		local mine = token
		clip = "idle"
		local frames = SpriteSheet.framesFor(sheet, "idle")
		local index = 1
		show(frames[index])
		if #frames < 2 then
			return
		end
		task.spawn(function()
			while true do
				task.wait(IDLE_FRAME_SECONDS)
				if not running(mine) then
					return
				end
				index = index % #frames + 1
				show(frames[index])
			end
		end)
	end

	local self = {} :: Player

	function self.play(_self: Player, wanted: Clip)
		if not alive then
			return
		end
		if wanted == "idle" then
			idle()
			return
		end
		token += 1
		local mine = token
		clip = wanted
		local frames = SpriteSheet.framesFor(sheet, wanted)
		show(frames[1])
		task.spawn(function()
			for i = 2, #frames do
				task.wait(ACTION_FRAME_SECONDS)
				if not running(mine) then
					return
				end
				show(frames[i])
			end
			task.wait(HOLD_SECONDS[wanted] or 0.2)
			if running(mine) then
				idle()
			end
		end)
	end

	function self.current(_self: Player): (Clip, number)
		return clip, frame
	end

	function self.destroy(_self: Player)
		alive = false
		token += 1
	end

	image.Destroying:Once(function()
		alive = false
	end)

	idle()
	return self
end

return SpriteSheet
