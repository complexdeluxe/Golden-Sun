--!strict

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Progress = require("@game/ReplicatedStorage/Shared/Core/TutorialProgress")
local Session = require("@game/ReplicatedStorage/Shared/Core/TutorialSession")
local CampaignSession = require("@game/ReplicatedStorage/Shared/Core/CampaignSession")
local Save = require("@game/ReplicatedStorage/Shared/Contracts/SaveTypes")
local Remote = require("@game/ReplicatedStorage/Shared/Contracts/RemoteContract")

local function new(useStudioDataStore: boolean)
	local memory: { [number]: { [string]: unknown } } = {}
	local dataStore: GlobalDataStore? = nil
	if not RunService:IsStudio() then
		dataStore = DataStoreService:GetDataStore("PBA_TutorialProfiles_v1")
	elseif useStudioDataStore then
		dataStore = DataStoreService:GetDataStore("PBA_TutorialProfiles_Studio_v1")
	end

	local function load(userId: number): (unknown, boolean)
		local db = dataStore
		if not db then return memory[userId], true end
		local ok, raw = pcall(function() return db:GetAsync("player:" .. userId) end)
		if not ok then
			warn("Profile load failed for user", userId)
			return nil, false
		end
		return raw, true
	end

	local function update(userId: number, transform: (unknown) -> { [string]: unknown }?): (unknown, boolean)
		local db = dataStore
		if not db then
			local value = transform(memory[userId])
			if value then memory[userId] = value end
			return value, true
		end
		local ok, raw = pcall(function() return db:UpdateAsync("player:" .. userId, transform) end)
		if not ok then
			warn("Profile update failed for user", userId)
			return nil, false
		end
		return raw, true
	end

	local campaign: CampaignSession.Store = { load = load, update = update }
	local tutorial: Session.Store = {
		load = function(userId)
			local raw, available = load(userId)
			return if available then Progress.decode(raw) else nil
		end,
		update = function(userId, transform)
			local rejection: Remote.ErrorCode? = nil
			local raw, available = update(userId, function(old)
				rejection = nil
				local current = Progress.decode(old)
				if not current then return nil end
				local updated, reason = transform(current)
				rejection = reason
				if not updated then return nil end
				local value: { [string]: unknown } =
					if type(old) == "table" then table.clone(old :: { [string]: unknown }) else {}
				value.version = updated.version
				value.tutorialCompleted = updated.tutorialCompleted
				value.origin = updated.origin
				return value
			end)
			if not available then return nil, nil end
			if raw == nil then return nil, rejection end
			return Progress.decode(raw), nil
		end,
	}
	return { tutorial = tutorial, campaign = campaign }
end

return table.freeze({ new = new })
