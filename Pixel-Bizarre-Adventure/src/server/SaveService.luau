--!strict

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Progress = require("@game/ReplicatedStorage/Shared/Core/TutorialProgress")
local Session = require("@game/ReplicatedStorage/Shared/Core/TutorialSession")
local Save = require("@game/ReplicatedStorage/Shared/Contracts/SaveTypes")
local Remote = require("@game/ReplicatedStorage/Shared/Contracts/RemoteContract")

local function new(useStudioDataStore: boolean): Session.Store
	local memory: { [number]: Save.Profile } = {}
	local dataStore: GlobalDataStore? = nil
	if not RunService:IsStudio() then
		dataStore = DataStoreService:GetDataStore("PBA_TutorialProfiles_v1")
	elseif useStudioDataStore then
		dataStore = DataStoreService:GetDataStore("PBA_TutorialProfiles_Studio_v1")
	end

	return {
		load = function(userId)
			local db = dataStore
			if not db then
				return Progress.decode(memory[userId])
			end
			local ok, raw = pcall(function()
				return db:GetAsync("player:" .. userId)
			end)
			if not ok then
				warn("Tutorial profile load failed for user", userId)
				return nil
			end
			return Progress.decode(raw)
		end,
		update = function(userId, transform)
			local db = dataStore
			if not db then
				local current = Progress.decode(memory[userId])
				if not current then
					return nil, nil
				end
				local updated, rejection = transform(current)
				if updated then
					memory[userId] = table.clone(updated)
				end
				return updated, rejection
			end

			local rejection: Remote.ErrorCode? = nil
			local ok, raw = pcall(function()
				return db:UpdateAsync("player:" .. userId, function(old: unknown)
					rejection = nil
					local current = Progress.decode(old)
					if not current then
						return nil
					end
					local updated, reason = transform(current)
					rejection = reason
					if not updated then
						return nil
					end
					-- Preserve additional fields already present in this version.
					local value: { [string]: unknown } =
						if type(old) == "table" then table.clone(old :: { [string]: unknown }) else {}
					value.version = updated.version
					value.tutorialCompleted = updated.tutorialCompleted
					value.origin = updated.origin
					return value
				end)
			end)
			if not ok then
				warn("Tutorial profile update failed for user", userId)
				return nil, nil
			end
			-- A cancelled UpdateAsync has no committed value.
			if raw == nil then
				return nil, rejection
			end
			return Progress.decode(raw), nil
		end,
	}
end

return table.freeze({ new = new })
