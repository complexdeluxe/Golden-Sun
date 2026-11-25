--!strict

local Hub = require("../Contracts/HubTypes")
local Remote = require("../Contracts/RemoteContract")
local Save = require("../Contracts/SaveTypes")
local Progress = require("./TutorialProgress")
local Profile = require("./CampaignProfile")

export type Store = {
	load: (number) -> (unknown, boolean),
	-- A nil transform result cancels the transaction. The boolean reports storage availability.
	update: (number, (unknown) -> { [string]: unknown }?) -> (unknown, boolean),
}

type Lease = { sessionId: string, expiresAt: number }
type Record = { profile: Profile.Profile, tutorial: Save.Profile, lease: Lease?, writeRevision: number }
type State = {
	sessionId: string,
	revision: number,
	destination: Profile.Destination,
	record: Record,
}

local LEASE_SECONDS = 180
local RENEW_BEFORE_SECONDS = 90

local function decode(value: unknown): Record?
	local tutorial = Progress.decode(value)
	if not tutorial then return nil end
	local raw: { [string]: unknown } = if type(value) == "table" then value :: { [string]: unknown } else {}
	local profile = Profile.decode(raw.campaign)
	local storedRevision = raw.campaignWriteRevision
	local writeRevision = if storedRevision == nil then 0 else storedRevision
	if not profile or type(writeRevision) ~= "number" or writeRevision < 0 or writeRevision >= 2 ^ 53
		or writeRevision % 1 ~= 0 then return nil end
	local lease: Lease? = nil
	if raw.campaignLease ~= nil then
		if type(raw.campaignLease) ~= "table" then return nil end
		local fields = raw.campaignLease :: { [string]: unknown }
		local id, expiresAt = fields.sessionId, fields.expiresAt
		if type(id) ~= "string" or type(expiresAt) ~= "number" or not (expiresAt >= 0 and expiresAt < 2 ^ 53) then return nil end
		lease = { sessionId = id, expiresAt = expiresAt }
	end
	return { profile = profile, tutorial = tutorial, lease = lease, writeRevision = writeRevision }
end

local function snapshot(state: State): Hub.CampaignSnapshot
	local record = state.record
	return {
		sessionId = state.sessionId, revision = state.revision,
		character = {
			appearance = record.profile.appearance,
			tutorialCompleted = record.tutorial.tutorialCompleted,
			origin = record.tutorial.origin,
			level = 1, yen = record.profile.yen,
		},
		scene = Profile.scene(record.profile, record.tutorial, state.destination),
		companion = { state = "Locked" },
	}
end

local function reject(code: Remote.CampaignErrorCode, message: string, state: State?): Remote.CampaignResponse
	return { ok = false, code = code, message = message, snapshot = if state then snapshot(state) else nil }
end

local function new(store: Store, clock: () -> number, makeId: () -> string)
	local sessions: { [number]: State } = {}

	local function transact(
		userId: number, id: string, operation: "Acquire" | "Renew" | "Write" | "Release",
		profile: Profile.Profile?, expectedWriteRevision: number?
	): (Record?, Remote.CampaignErrorCode)
		local rejection: Remote.CampaignErrorCode = "SaveUnavailable"
		local committed, available = store.update(userId, function(value)
			rejection = "SaveUnavailable"
			local record = decode(value)
			if not record then return nil end
			local now = clock()
			local lease = record.lease
			local ownsLease = lease ~= nil and lease.sessionId == id
			if operation == "Acquire" then
				if lease and not ownsLease and lease.expiresAt > now then
					rejection = "ProfileLocked"
					return nil
				end
			elseif not ownsLease or (operation ~= "Release" and assert(lease).expiresAt <= now) then
				rejection = "ProfileLocked"
				return nil
			end
			if operation == "Write" and record.writeRevision ~= expectedWriteRevision then
				rejection = "StaleRevision"
				return nil
			end

			local raw: { [string]: unknown } = if type(value) == "table" then table.clone(value :: { [string]: unknown }) else {}
			raw.version = record.tutorial.version
			raw.tutorialCompleted = record.tutorial.tutorialCompleted
			raw.origin = record.tutorial.origin
			raw.campaign = profile or record.profile
			raw.campaignWriteRevision = if operation == "Write" then record.writeRevision + 1 else record.writeRevision
			raw.campaignLease = if operation == "Release" then nil else { sessionId = id, expiresAt = now + LEASE_SECONDS }
			return raw
		end)
		if not available then return nil, "SaveUnavailable" end
		return if committed then decode(committed) else nil, rejection
	end

	local function replaceRecord(state: State, record: Record)
		if record.writeRevision ~= state.record.writeRevision
			or record.tutorial.tutorialCompleted ~= state.record.tutorial.tutorialCompleted
			or record.tutorial.origin ~= state.record.tutorial.origin then
			state.revision += 1
		end
		state.record = record
	end

	local function get(userId: number): Remote.CampaignResponse
		local state = sessions[userId]
		if not state then
			local id = makeId()
			local record, code = transact(userId, id, "Acquire")
			if not record then return reject(code, "Could not open this campaign profile. Try again.", nil) end
			state = { sessionId = id, revision = 1, destination = "Hub", record = record }
			sessions[userId] = state
		else
			local value, available = store.load(userId)
			local record = if available then decode(value) else nil
			if not record then return reject("SaveUnavailable", "Could not refresh this campaign profile.", nil) end
			local lease = record.lease
			if not lease or lease.sessionId ~= state.sessionId or lease.expiresAt <= clock() then
				sessions[userId] = nil
				return reject("ProfileLocked", "Campaign session expired. Refresh to reconnect.", nil)
			end
			local previous = state.record
			if record.writeRevision >= previous.writeRevision and (not previous.tutorial.tutorialCompleted or record.tutorial.tutorialCompleted)
				and (not previous.tutorial.origin or previous.tutorial.origin == record.tutorial.origin) then
				replaceRecord(state, record)
			end
		end
		return { ok = true, snapshot = snapshot(state) }
	end

	local function submit(userId: number, request: Remote.CampaignActionRequest): Remote.CampaignResponse
		local state = sessions[userId]
		if not state then return reject("NotReady", "Open the campaign first.", nil) end
		if assert(state.record.lease).expiresAt <= clock() then
			sessions[userId] = nil
			return reject("ProfileLocked", "Campaign session expired. Refresh to reconnect.", nil)
		end
		if state.sessionId ~= request.sessionId or state.revision ~= request.expectedRevision then
			return reject("StaleRevision", "Campaign state changed. Try again.", state)
		end

		local scene = Profile.scene(state.record.profile, state.record.tutorial, state.destination)
		if request.kind == "Navigate" then
			if scene.kind ~= "Hub" and scene.kind ~= "ActMap" then return reject("IllegalAction", "Finish onboarding first.", state) end
			state.destination = request.destination
			state.revision += 1
			return { ok = true, snapshot = snapshot(state) }
		end
		if request.kind == "StartNode" then
			if scene.kind ~= "ActMap" then return reject("IllegalAction", "Open the Act Map first.", state) end
			if request.nodeId ~= "F1" then return reject("NodeLocked", "Clear the previous node first.", state) end
			return reject("NotReady", "Act combat is awaiting integration.", state)
		end
		if request.kind == "RecruitCompanion" then return reject("IllegalAction", "Complete Dungeon 1 to recruit.", state) end
		if request.kind == "CommitAppearance" then
			if scene.kind ~= "Creator" then return reject("IllegalAction", "Appearance has already been set.", state) end
		elseif scene.kind ~= "Hub" then
			return reject("IllegalAction", "Return to the Hub to change the loadout or shop.", state)
		end

		local profile, code, message = Profile.update(state.record.profile, request)
		if not profile then return reject(code or "IllegalAction", message or "Action is unavailable.", state) end
		local current, failure = transact(userId, state.sessionId, "Write", profile, state.record.writeRevision)
		if not current then
			if failure == "ProfileLocked" then
				sessions[userId] = nil
				return reject(failure, "This session no longer owns the profile.", nil)
			end
			if failure == "StaleRevision" then
				local refreshed = get(userId)
				if refreshed.ok then return reject(failure, "Saved state changed. Try again.", sessions[userId]) end
				return refreshed
			end
			return reject(failure, "Could not save the change. Try again.", state)
		end

		replaceRecord(state, current)
		return { ok = true, snapshot = snapshot(state) }
	end

	local function renew(userId: number)
		local state = sessions[userId]
		if not state or assert(state.record.lease).expiresAt - clock() > RENEW_BEFORE_SECONDS then return end
		local record, code = transact(userId, state.sessionId, "Renew")
		if record then
			replaceRecord(state, record)
		elseif code == "ProfileLocked" then
			sessions[userId] = nil
		end
	end

	local function close(userId: number)
		local state = sessions[userId]
		if not state then return end
		sessions[userId] = nil
		transact(userId, state.sessionId, "Release")
	end

	return table.freeze({ get = get, submit = submit, renew = renew, close = close })
end

return table.freeze({ new = new })
