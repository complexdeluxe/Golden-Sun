--!strict

local Hub = require("../Contracts/HubTypes")
local Combat = require("../Contracts/CombatTypes")
local Remote = require("../Contracts/RemoteContract")
local Save = require("../Contracts/SaveTypes")
local Progress = require("./TutorialProgress")
local Profile = require("./CampaignProfile")
local ActBattle = require("./CampaignActBattle")
local Starter = require("../Data/CampaignStarter")
local Map = require("../Contracts/MapTypes")
local Progression = require("./CampaignProgression")

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
	fight: ActBattle.Fight?,
	finishedBattles: { [string]: Remote.ActBattleResponse },
	settleAfter: number,
	fullRoute: boolean,
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

local function currentFight(state: State): ActBattle.Fight?
	local pending = state.record.profile.actOne.pending
	local fight = state.fight
	return if pending and fight and pending.battleId == fight.attempt.battleId then fight else nil
end

local function clearsFor(profile: Profile.Profile, act: number): { [Map.NodeId]: boolean }
	return if act == 1 then profile.actOne.clears else profile.progression.clears[tostring(act)] or {}
end

local function routeMap(profile: Profile.Profile, origin: Save.Origin): Hub.Scene
	local act = Progression.currentAct(profile.progression, profile.actOne.clears)
	local part = Progression.part(origin, act)
	local clears = clearsFor(profile, act)
	local nextNode = #part.nodes
	for i, node in part.nodes do
		if not clears[node.id] then
			nextNode = i
			break
		end
	end
	-- Keep each section small enough for the existing map layout.
	local first = math.floor((nextNode - 1) / 3) * 3 + 1
	local nodes: { Map.NodeView } = {}
	for i = first, math.min(first + 2, #part.nodes) do
		local node, previous = part.nodes[i], part.nodes[i - 1]
		local cleared = clears[node.id] == true
		local allowed = previous == nil or clears[previous.id] == true
		local stage = if act == 1 and (node.id == "F1" or node.id == "F2" or node.id == "D1")
			then Starter.ActOneRoutes[origin].stages[node.id :: Map.ActOneNodeId] else nil
		local view: Map.NodeView = {
			id = node.id, label = if stage then stage.label else node.location,
			stageTag = if stage then stage.tag else node.stageTag or "Neutral",
			stageAssetKey = if stage then stage.assetKey else node.stageAssetKey,
			prerequisites = if i > first and previous then { previous.id } else {},
			state = if cleared then "Cleared" else if allowed then "Available" else "Locked",
			playOptions = if allowed then { ActBattle.option(node.id, cleared, act) } else {},
		}
		table.insert(nodes, view)
	end
	return { kind = "ActMap", map = { act = act, part = part.storyPart, nodes = nodes } }
end

local function scene(state: State): Hub.Scene
	local fight = currentFight(state)
	if fight then return { kind = "ActEncounter", encounter = ActBattle.encounter(fight) } end
	local record = state.record
	local base = Profile.scene(record.profile, record.tutorial, state.destination)
	if state.fullRoute and base.kind == "ActMap" then return routeMap(record.profile, assert(record.tutorial.origin)) end
	return base
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
		companion = ActBattle.companion(record.tutorial.origin, record.profile.actOne),
	}
end

local function reject(code: Remote.CampaignErrorCode, message: string, state: State?): Remote.CampaignResponse
	return { ok = false, code = code, message = message, snapshot = if state then snapshot(state) else nil }
end

local function new(
		store: Store, clock: () -> number, makeId: () -> string, battleClock: (() -> number)?, random: (() -> number)?,
	bridge: Progression.Bridge?
)
	local sessions: { [number]: State } = {}
	local battleNow = battleClock or clock
	local roll = random or function() return math.random() end

	local function transact(
		userId: number, id: string, operation: "Acquire" | "Renew" | "Write" | "Release",
		profile: Profile.Profile?, expectedWriteRevision: number?
	): (Record?, Remote.CampaignErrorCode, Record?)
		local rejection: Remote.CampaignErrorCode = "SaveUnavailable"
		local newerRecord: Record? = nil
		local committed, available = store.update(userId, function(value)
			rejection = "SaveUnavailable"
			newerRecord = nil
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
				newerRecord = record
				return nil
			end

			local raw: { [string]: unknown } = if type(value) == "table" then table.clone(value :: { [string]: unknown }) else {}
			raw.version = record.tutorial.version
			raw.tutorialCompleted = record.tutorial.tutorialCompleted
			raw.origin = record.tutorial.origin
			if profile then
				-- Patch only campaign-owned fields on the current row, including its shared wallet.
				local current = raw.campaign
				local campaign: { [string]: unknown } =
					if type(current) == "table" then table.clone(current :: { [string]: unknown }) else {}
				campaign.version = profile.version
				campaign.appearance = profile.appearance
				campaign.yen = profile.yen
				campaign.stock = profile.stock
				campaign.gear = profile.gear
				campaign.belt = profile.belt
				campaign.actOne = profile.actOne
				campaign.progression = profile.progression
				raw.campaign = campaign
			elseif raw.campaign == nil then
				raw.campaign = record.profile
			end
			raw.campaignWriteRevision = if operation == "Write" then record.writeRevision + 1 else record.writeRevision
			raw.campaignLease = if operation == "Release" then nil else { sessionId = id, expiresAt = now + LEASE_SECONDS }
			return raw
		end)
		if not available then return nil, "SaveUnavailable", nil end
		return if committed then decode(committed) else nil, rejection, newerRecord
	end

	local function replaceRecord(state: State, record: Record)
		local previousLife = state.record.profile.progression.lifeId
		local progression = record.profile.progression
		if previousLife ~= progression.lifeId and progression.starterPurseRank ~= nil then
			state.destination = "Hub"
			state.fight = nil
			state.finishedBattles = {}
		end
		if record.writeRevision ~= state.record.writeRevision
			or record.tutorial.tutorialCompleted ~= state.record.tutorial.tutorialCompleted
			or record.tutorial.origin ~= state.record.tutorial.origin then
			state.revision += 1
		end
		state.record = record
	end

	local function drain(userId: number, state: State): boolean
		local event = state.record.profile.progression.pending
		if not event then return true end
		if not bridge or not bridge.apply(userId, event) then return false end
		local profile = table.clone(state.record.profile)
		profile.progression = table.clone(profile.progression)
		profile.progression.pending = nil
		local saved, _, newer = transact(userId, state.sessionId, "Write", profile, state.record.writeRevision)
		if saved then
			replaceRecord(state, saved)
			return true
		end
		if newer then
			replaceRecord(state, newer)
			-- A terminal wipe can acknowledge its outbox entry by atomically
			-- replacing the whole campaign with the heir's starter state.
			return newer.profile.progression.pending == nil
		end
		return false
	end

	local function settle(userId: number, state: State, retry: boolean): Hub.CampaignSnapshot?
		local fight = state.fight
		if not fight then return nil end
		local result = ActBattle.result(fight)
		if not result then return nil end
		local saved = state.record.profile.actOne.result
		if not saved or saved.attempt.battleId ~= fight.attempt.battleId then
			if not retry or not currentFight(state) or battleNow() < state.settleAfter then return nil end
			local profile = table.clone(state.record.profile)
			local progress = table.clone(profile.actOne)
			progress.pending = nil
			progress.result = result
			local attempt = result.attempt
			local act, id = attempt.act or 1, attempt.nodeId
			local first = attempt.mode == "FirstClear"
			profile.progression = table.clone(profile.progression)
			if result.outcome == "Clear" and first then
				local clears = table.clone(clearsFor(profile, act))
				clears[id] = true
				if act == 1 then
					progress.clears = clears
				else
					profile.progression.clears = table.clone(profile.progression.clears)
					profile.progression.clears[tostring(act)] = clears
				end
			end
			if bridge and attempt.lifeId and first
				and (result.outcome == "Clear" or (id == "Castle" and result.outcome == "Defeat")) then
				profile.progression.pending = {
					lifeId = attempt.lifeId, battleId = attempt.battleId, act = act, part = Progression.part(fight.origin, act).storyPart,
					nodeId = id, outcome = result.outcome :: "Clear" | "Defeat",
					kitId = if fight.contributed then attempt.kitId else nil, years = Progression.years(id),
				}
			end
			profile.actOne = progress
			profile.yen += result.yen
			profile.stock = table.clone(profile.stock)
			for _, entryId in profile.belt do
				local itemId = Starter.Items[entryId].beltItemId
				if itemId then
					local spent = (fight.startingStock[itemId] or 0) - (fight.battle.stock[itemId] or 0)
					profile.stock[entryId] = math.max(0, (profile.stock[entryId] or 0) - spent)
				end
			end
			local record, _, newerRecord = transact(userId, state.sessionId, "Write", profile, state.record.writeRevision)
			if not record then
				if newerRecord then replaceRecord(state, newerRecord) end
				state.settleAfter = battleNow() + 2
				return nil
			end
			replaceRecord(state, record)
		end
		if not drain(userId, state) then return nil end
		local campaign = snapshot(state)
		state.finishedBattles[fight.attempt.battleId] = { ok = true, snapshot = ActBattle.snapshot(fight), campaignSnapshot = campaign }
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
				destination = if record.profile.actOne.pending then "ActMap" else "Hub",
				finishedBattles = {}, settleAfter = 0, fullRoute = bridge ~= nil,
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
		local settled = settle(userId, state, true)
		if not settled and not state.fight then drain(userId, state) end
		return { ok = true, snapshot = settled or snapshot(state) }
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

		if state.record.profile.progression.pending and not drain(userId, state) then
			return reject("SaveUnavailable", "Progression is still saving. Try again.", state)
		end
		if state.revision ~= request.expectedRevision then return reject("StaleRevision", "Refresh the committed progression.", state) end
		local entryScene = scene(state)
		local enteringMap = request.kind == "Navigate" and request.destination == "ActMap"
			and (entryScene.kind == "Hub" or entryScene.kind == "ActResults" or entryScene.kind == "ActMap")
		local life: Progression.Life? = nil
		if bridge and (enteringMap or (request.kind == "StartNode" and entryScene.kind == "ActMap")) then
			life = bridge.life(userId, request.kind == "Navigate")
			if not life then return reject("SaveUnavailable", "Could not open the lineage ledger.", state) end
			if life.settled then return reject("IllegalAction", "This life has ended. Begin the next life at the Hub.", state) end
			local old = state.record.profile
			if old.progression.lifeId ~= life.id then
				local profile = table.clone(old)
				profile.progression = table.clone(old.progression)
				profile.progression.lifeId = life.id
				if old.progression.lifeId then
					profile.actOne = { clears = {}, recruited = false }
					profile.progression.clears = {}
				end
				local bound, code, newer = transact(userId, state.sessionId, "Write", profile, state.record.writeRevision)
				if not bound then
					if newer then replaceRecord(state, newer) end
					return reject(code, "Could not bind this campaign to the current life.", state)
				end
				replaceRecord(state, bound)
				if request.kind == "StartNode" then return reject("StaleRevision", "Campaign life changed. Choose the stage again.", state) end
			end
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
			updated.actOne = table.clone(updated.actOne)
			updated.actOne.result = nil
		elseif request.kind == "StartNode" then
			if currentScene.kind ~= "ActMap" then return reject("IllegalAction", "Open the Act Map first.", state) end
			local profile = state.record.profile
			local finalAttempt = request.nodeId == "Castle" and life ~= nil and life.isFinalAttempt
				and not clearsFor(profile, currentScene.map.act).Castle
			local option
			for _, node in currentScene.map.nodes do
				if node.id == request.nodeId then
					option = node.playOptions[1]
					break
				end
			end
			if not option then return reject("NodeLocked", "Clear the previous node first.", state) end
			local optionId = if finalAttempt then option.id .. ":confirm" else option.id
			if request.playOptionId ~= optionId then
				return reject("IllegalAction", if finalAttempt then "Final attempt: confirm that defeat ends this generation."
					else "Choose the available play option.", state)
			end
			local fight = state.fight
			if fight and fight.attempt.nodeId ~= request.nodeId then
				-- A prior StartNode may have committed even if its save reply was lost.
				local refreshed = get(userId)
				if not refreshed.ok then return refreshed end
				if refreshed.snapshot.scene.kind ~= "ActMap" or refreshed.snapshot.revision ~= request.expectedRevision then
					return reject("StaleRevision", "Campaign state changed. Try again.", state)
				end
				fight = nil
			end
			if not fight then
				local stock: { [Combat.BeltItemId]: number } = {}
				for _, entryId in profile.belt do
					local itemId = Starter.Items[entryId].beltItemId
					if itemId then stock[itemId] = profile.stock[entryId] or 0 end
				end
				local origin = assert(state.record.tutorial.origin)
				local attempt: ActBattle.Attempt = {
					battleId = makeId(), nodeId = request.nodeId, mode = option.mode,
					act = if bridge then currentScene.map.act else nil, lifeId = if life then life.id else nil,
					kitId = if bridge then (if origin == "Part1_Hamon" then "hamon" else "stand_origin") else nil,
				}
				fight = ActBattle.new(attempt, assert(state.record.tutorial.origin), Profile.level(profile), stock,
					if profile.gear.Weapon == "training-wraps" then 2 else 0,
					if profile.gear.Head == "brimmed-cap" then 2 else 0, profile.actOne.recruited, roll, battleNow)
				state.fight = fight
			end
			updated = table.clone(profile)
			updated.actOne = table.clone(profile.actOne)
			updated.actOne.pending = assert(fight).attempt
			if profile.progression.starterPurseRank ~= nil then
				updated.progression = table.clone(profile.progression)
				updated.progression.starterPurseRank = nil
			end
		elseif request.kind == "RecruitCompanion" then
			if currentScene.kind ~= "Hub" and currentScene.kind ~= "ActResults" then
				return reject("IllegalAction", "Recruit from Results or the Hub.", state)
			end
			local profile = state.record.profile
			local offer = ActBattle.companion(state.record.tutorial.origin, profile.actOne)
			if offer.state ~= "Offered" or offer.offerId ~= request.offerId then
				return reject("IllegalAction", "Choose the active companion offer.", state)
			end
			updated = table.clone(profile)
			updated.actOne = table.clone(profile.actOne)
			updated.actOne.recruited = true
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
		local current, failure, newerRecord = transact(userId, state.sessionId, "Write", updated, state.record.writeRevision)
		if not current then
			if request.kind == "StartNode" and failure ~= "SaveUnavailable" and failure ~= "StaleRevision" then state.fight = nil end
			if failure == "ProfileLocked" then
				sessions[userId] = nil
				return reject(failure, "This session no longer owns the profile.", nil)
			end
			if failure == "StaleRevision" then
				-- The atomic transform saw the newer wallet. Avoid a cached GetAsync here.
				replaceRecord(state, assert(newerRecord))
				if request.kind == "StartNode" and not currentFight(state) then state.fight = nil end
				settle(userId, state, true)
				return reject(failure, "Saved state changed. Try again.", state)
			end
			return reject(failure, "Could not save the change. Try again.", state)
		end

		replaceRecord(state, current)
		if request.kind ~= "StartNode" and not currentFight(state) then state.fight = nil end
		return { ok = true, snapshot = snapshot(state) }
	end

	local function battle(userId: number, command: ActBattle.Command): Remote.ActBattleResponse
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
		local wasTerminal = ActBattle.result(fight) ~= nil
		ActBattle.expireChecks(fight)
		local result = ActBattle.apply(fight, command)
		local finalized = settle(userId, state, not wasTerminal)
		if finalized then return state.finishedBattles[id] end
		return result
	end

	local function nextCheck(userId: number): (string?, number?)
		local state = sessions[userId]
		local fight = if state then currentFight(state) else nil
		if not fight then return nil, nil end
		return fight.attempt.battleId, ActBattle.nextDeadline(fight)
	end

	local function expireChecks(userId: number, battleId: string): Remote.ActBattleResponse?
		local state = sessions[userId]
		local fight = if state then currentFight(state) else nil
		if not state or not fight or fight.attempt.battleId ~= battleId or not ActBattle.expireChecks(fight) then return nil end
		local campaign = settle(userId, state, true)
		return { ok = true, snapshot = ActBattle.snapshot(fight), campaignSnapshot = campaign }
	end

	local function renew(userId: number)
		local state = sessions[userId]
		if not state or assert(state.record.lease).expiresAt - clock() > RENEW_BEFORE_SECONDS then return end
		local record, code = transact(userId, state.sessionId, "Renew")
		if record then
			replaceRecord(state, record)
			if state.fight then settle(userId, state, true) else drain(userId, state) end
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

		local function onboarding(userId: number): number
		local state = sessions[userId]
		if not state or not state.record.profile.appearance then return 1 end
		local tutorial, progress = state.record.tutorial, state.record.profile.actOne
		if not tutorial.tutorialCompleted then return 2 end
		if not tutorial.origin then return 4 end
		if progress.recruited then return 9 end
		if progress.clears.D1 then return 8 end
		if progress.clears.F1 then return 7 end
		return if scene(state).kind == "Hub" then 6 else 5
	end

	local function isSafeHub(userId: number): boolean
		local state = sessions[userId]
		local lease = if state then state.record.lease else nil
		return state ~= nil and lease ~= nil and lease.expiresAt > clock()
			and state.destination == "Hub" and scene(state).kind == "Hub"
	end

	return table.freeze({
		get = get, submit = submit, renew = renew, close = close,
		isSafeHub = isSafeHub, onboarding = onboarding,
		battle = battle, nextCheck = nextCheck, expireChecks = expireChecks,
	})
end

return table.freeze({ new = new })
