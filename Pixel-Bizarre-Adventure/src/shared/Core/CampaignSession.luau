--!strict

local Hub = require("../Contracts/HubTypes")
local Combat = require("../Contracts/CombatTypes")
local Remote = require("../Contracts/RemoteContract")
local Save = require("../Contracts/SaveTypes")
local Progress = require("./TutorialProgress")
local Profile = require("./CampaignProfile")
local F1 = require("./CampaignF1")
local Starter = require("../Data/CampaignStarter")

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
	fight: F1.Fight?,
	finishedBattles: { [string]: Remote.ActBattleResponse },
	settleAfter: number,
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

local function currentFight(state: State): F1.Fight?
	local pending = state.record.profile.f1.pending
	local fight = state.fight
	return if pending and fight and pending.battleId == fight.attempt.battleId then fight else nil
end

local function scene(state: State): Hub.Scene
	local fight = currentFight(state)
	if fight then return { kind = "ActEncounter", encounter = F1.encounter(fight) } end
	return Profile.scene(state.record.profile, state.record.tutorial, state.destination)
end

local function snapshot(state: State): Hub.CampaignSnapshot
	local record = state.record
	return {
		sessionId = state.sessionId, revision = state.revision,
		character = {
			appearance = record.profile.appearance,
			appearanceSprites = Profile.appearanceSprites(record.profile.appearance),
			tutorialCompleted = record.tutorial.tutorialCompleted,
			origin = record.tutorial.origin,
			level = Profile.level(record.profile), yen = record.profile.yen,
		},
		scene = scene(state),
		companion = { state = "Locked" },
	}
end

local function reject(code: Remote.CampaignErrorCode, message: string, state: State?): Remote.CampaignResponse
	return { ok = false, code = code, message = message, snapshot = if state then snapshot(state) else nil }
end

local function new(
	store: Store, clock: () -> number, makeId: () -> string, battleClock: (() -> number)?, random: (() -> number)?
)
	local sessions: { [number]: State } = {}
	local battleNow = battleClock or clock
	local roll = random or function() return math.random() end

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

	local function settle(userId: number, state: State, retry: boolean): Hub.CampaignSnapshot?
		local fight = state.fight
		if not fight then return nil end
		local result = F1.result(fight)
		if not result then return nil end
		local saved = state.record.profile.f1.result
		if not saved or saved.attempt.battleId ~= fight.attempt.battleId then
			if not retry or not currentFight(state) or battleNow() < state.settleAfter then return nil end
			local profile = table.clone(state.record.profile)
			profile.f1 = { cleared = profile.f1.cleared or result.outcome == "Clear", result = result }
			profile.yen += result.yen
			profile.stock = table.clone(profile.stock)
			for _, entryId in profile.belt do
				local itemId = Starter.Items[entryId].beltItemId
				if itemId then
					local spent = (fight.startingStock[itemId] or 0) - (fight.battle.stock[itemId] or 0)
					profile.stock[entryId] = math.max(0, (profile.stock[entryId] or 0) - spent)
				end
			end
			local record = transact(userId, state.sessionId, "Write", profile, state.record.writeRevision)
			if not record then
				state.settleAfter = battleNow() + 2
				return nil
			end
			replaceRecord(state, record)
		end
		local campaign = snapshot(state)
		state.finishedBattles[fight.attempt.battleId] = { ok = true, snapshot = F1.snapshot(fight), campaignSnapshot = campaign }
		state.fight = nil
		state.settleAfter = 0
		return campaign
	end

	local function get(userId: number): Remote.CampaignResponse
		local state = sessions[userId]
		if not state then
			local id = makeId()
			local record, code = transact(userId, id, "Acquire")
			if not record then return reject(code, "Could not open this campaign profile. Try again.", nil) end
			local opened: State = {
				sessionId = id, revision = 1, record = record,
				destination = if record.profile.f1.pending then "ActMap" else "Hub",
				finishedBattles = {}, settleAfter = 0,
			}
			state = opened
			sessions[userId] = opened
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
		return { ok = true, snapshot = settle(userId, state, true) or snapshot(state) }
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

		local currentScene = scene(state)
		local updated: Profile.Profile? = nil
		if request.kind == "Navigate" then
			if currentScene.kind ~= "Hub" and currentScene.kind ~= "ActMap" and currentScene.kind ~= "ActResults" then
				return reject("IllegalAction", "Finish the current scene first.", state)
			end
			state.destination = request.destination
			if currentScene.kind ~= "ActResults" then
				state.revision += 1
				return { ok = true, snapshot = snapshot(state) }
			end
			updated = table.clone(state.record.profile)
			updated.f1 = { cleared = updated.f1.cleared }
		elseif request.kind == "StartNode" then
			if currentScene.kind ~= "ActMap" then return reject("IllegalAction", "Open the Act Map first.", state) end
			if request.nodeId ~= "F1" then return reject("NodeLocked", "Clear the previous node first.", state) end
			local profile = state.record.profile
			local option = F1.option(profile.f1.cleared)
			if request.playOptionId ~= option.id then return reject("IllegalAction", "Choose the available F1 option.", state) end
			local fight = state.fight
			if not fight then
				local stock: { [Combat.BeltItemId]: number } = {}
				for _, entryId in profile.belt do
					local itemId = Starter.Items[entryId].beltItemId
					if itemId then stock[itemId] = profile.stock[entryId] or 0 end
				end
				local attempt: F1.Attempt = { battleId = makeId(), mode = option.mode }
				fight = F1.new(attempt, assert(state.record.tutorial.origin), Profile.level(profile), stock,
					if profile.gear.Weapon == "training-wraps" then 2 else 0,
					if profile.gear.Head == "brimmed-cap" then 2 else 0, roll, battleNow)
				state.fight = fight
			end
			updated = table.clone(profile)
			updated.f1 = { cleared = profile.f1.cleared, pending = assert(fight).attempt }
		elseif request.kind == "RecruitCompanion" then
			return reject("IllegalAction", "Complete Dungeon 1 to recruit.", state)
		else
			if request.kind == "CommitAppearance" then
				if currentScene.kind ~= "Creator" then return reject("IllegalAction", "Appearance has already been set.", state) end
			elseif currentScene.kind ~= "Hub" then
				return reject("IllegalAction", "Return to the Hub to change the loadout or shop.", state)
			end
			local profile, code, message = Profile.update(state.record.profile, request)
			if not profile then return reject(code or "IllegalAction", message or "Action is unavailable.", state) end
			updated = profile
		end
		local current, failure = transact(userId, state.sessionId, "Write", updated, state.record.writeRevision)
		if not current then
			if request.kind == "StartNode" and failure ~= "SaveUnavailable" and failure ~= "StaleRevision" then state.fight = nil end
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
		if request.kind ~= "StartNode" and not currentFight(state) then state.fight = nil end
		return { ok = true, snapshot = snapshot(state) }
	end

	local function battle(userId: number, command: F1.Command): Remote.ActBattleResponse
		local state = sessions[userId]
		if not state or assert(state.record.lease).expiresAt <= clock() then
			return { ok = false, code = "ProfileLocked", message = "Refresh the campaign to reconnect." }
		end
		local id = command.request.battleId
		local finished = state.finishedBattles[id]
		if finished then return finished end
		local fight = currentFight(state)
		if not fight or fight.attempt.battleId ~= id then
			return { ok = false, code = "BattleNotFound", message = "This battle is no longer open." }
		end
		local wasTerminal = F1.result(fight) ~= nil
		F1.expireChecks(fight)
		local result = F1.apply(fight, command)
		local finalized = settle(userId, state, not wasTerminal)
		if finalized then return state.finishedBattles[id] end
		return result
	end

	local function nextCheck(userId: number): (string?, number?)
		local state = sessions[userId]
		local fight = if state then currentFight(state) else nil
		if not fight then return nil, nil end
		return fight.attempt.battleId, F1.nextDeadline(fight)
	end

	local function expireChecks(userId: number, battleId: string): Remote.ActBattleResponse?
		local state = sessions[userId]
		local fight = if state then currentFight(state) else nil
		if not state or not fight or fight.attempt.battleId ~= battleId or not F1.expireChecks(fight) then return nil end
		local campaign = settle(userId, state, true)
		return { ok = true, snapshot = F1.snapshot(fight), campaignSnapshot = campaign }
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
		settle(userId, state, true)
		sessions[userId] = nil
		transact(userId, state.sessionId, "Release")
	end

	return table.freeze({
		get = get, submit = submit, renew = renew, close = close,
		battle = battle, nextCheck = nextCheck, expireChecks = expireChecks,
	})
end

return table.freeze({ new = new })
