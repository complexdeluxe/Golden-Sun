--!strict
-- One place for music and sound effects.
--
-- Music: one track at a time. Asking for the track that is already playing
-- does nothing, so screen changes and fight restarts never stack it. A new
-- track replaces the old one, and stopMusic() ends it.
--
-- Effects: each cue owns one Sound that restarts when played again, so a
-- burst of the same cue never piles up. A cue played again within
-- SFX_COOLDOWN is skipped.
--
-- No approved clips are uploaded yet, so every cue below is still the unset
-- asset and nothing plays. Each cue lists its intended use; see the art and
-- audio handoff for the missing clip list.

local SoundService = game:GetService("SoundService")

export type MusicCue = "Hub" | "Battle" | "Boss"
export type SfxCue = "Hit" | "HeavyHit" | "Guard" | "Dodge" | "QteMiss" | "Victory" | "Defeat"

local UNSET = "rbxassetid://0"
local SFX_COOLDOWN = 0.06
local MUSIC_VOLUME = 0.35
local SFX_VOLUME = 0.6

-- Intended use for each cue is in the comment beside it.
local MUSIC: { [MusicCue]: string } = {
	Hub = UNSET, -- Hub, Act Map, stations, Hall and Activities (loop)
	Battle = UNSET, -- Tutorial and Act fights (loop)
	Boss = UNSET, -- Castle fights (loop)
}

local SFX: { [SfxCue]: string } = {
	Hit = UNSET, -- a fighter takes damage
	HeavyHit = UNSET, -- a heavy or finisher lands
	Guard = UNSET, -- a fighter guards
	Dodge = UNSET, -- an attack is dodged
	QteMiss = UNSET, -- a timing check missed
	Victory = UNSET, -- fight won (one shot over the music)
	Defeat = UNSET, -- fight lost
}

local Audio = {}

local folder: Folder? = nil
local musicCue: MusicCue? = nil
local musicSound: Sound? = nil
local effects: { [SfxCue]: Sound } = {}
local lastPlayed: { [SfxCue]: number } = {}

local function root(): Folder
	local existing = folder
	if existing and existing.Parent then
		return existing
	end
	local made = Instance.new("Folder")
	made.Name = "PBA_Audio"
	made.Parent = SoundService
	folder = made
	return made
end

local function isSet(id: string?): boolean
	return id ~= nil and id ~= "" and id ~= UNSET
end

-- Plays `cue` on loop, replacing any other track. Nil stops the music.
function Audio.music(cue: MusicCue?)
	if cue == musicCue and (cue == nil or (musicSound ~= nil and musicSound.Parent ~= nil)) then
		return
	end
	Audio.stopMusic()
	musicCue = cue
	if cue == nil then
		return
	end
	local id = MUSIC[cue]
	if not isSet(id) then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = `Music_{cue}`
	sound.SoundId = id
	sound.Looped = true
	sound.Volume = MUSIC_VOLUME
	sound.Parent = root()
	sound:Play()
	musicSound = sound
end

function Audio.stopMusic()
	local sound = musicSound
	musicSound = nil
	musicCue = nil
	if sound then
		sound:Stop()
		sound:Destroy()
	end
end

-- Plays a one-shot effect. Unset cues and repeats inside the cooldown do nothing.
function Audio.sfx(cue: SfxCue)
	local id = SFX[cue]
	if not isSet(id) then
		return
	end
	local now = os.clock()
	local last = lastPlayed[cue]
	if last and now - last < SFX_COOLDOWN then
		return
	end
	lastPlayed[cue] = now
	local sound = effects[cue]
	if sound == nil or sound.Parent == nil then
		local made = Instance.new("Sound")
		made.Name = `Sfx_{cue}`
		made.SoundId = id
		made.Volume = SFX_VOLUME
		made.Parent = root()
		effects[cue] = made
		sound = made
	end
	local playing = sound :: Sound
	playing.TimePosition = 0
	playing:Play()
end

-- What is loaded, for Studio checks: the music cue and how many Sounds exist.
function Audio.state(): (MusicCue?, number)
	local count = 0
	local existing = folder
	if existing then
		for _, child in existing:GetChildren() do
			if child:IsA("Sound") then
				count += 1
			end
		end
	end
	return musicCue, count
end

return Audio
