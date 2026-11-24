--!strict

local Save = require("../Contracts/SaveTypes")

local function new(): Save.Profile
	return { version = Save.PROFILE_VERSION, tutorialCompleted = false, origin = nil }
end

local function decode(raw: unknown): Save.Profile?
	if raw == nil then
		return new()
	end
	if type(raw) ~= "table" then
		return nil
	end
	local fields = raw :: { [string]: unknown }
	local completed = fields.tutorialCompleted
	local origin = fields.origin
	if fields.version ~= Save.PROFILE_VERSION or type(completed) ~= "boolean" then
		return nil
	end
	if origin ~= nil and origin ~= "Part1_Hamon" and origin ~= "Part3_Stand" then
		return nil
	end
	if origin ~= nil and not completed then
		return nil
	end
	return {
		version = Save.PROFILE_VERSION,
		tutorialCompleted = completed,
		origin = origin,
	}
end

local function complete(profile: Save.Profile): Save.Profile
	return {
		version = profile.version,
		tutorialCompleted = true,
		origin = profile.origin,
	}
end

local function choose(profile: Save.Profile, origin: Save.Origin): (Save.Profile?, "TutorialIncomplete" | "OriginAlreadyChosen"?)
	if not profile.tutorialCompleted then
		return nil, "TutorialIncomplete"
	end
	if profile.origin and profile.origin ~= origin then
		return nil, "OriginAlreadyChosen"
	end
	return { version = profile.version, tutorialCompleted = true, origin = origin }, nil
end

return table.freeze({ decode = decode, complete = complete, choose = choose })
