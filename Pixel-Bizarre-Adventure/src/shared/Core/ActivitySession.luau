--!strict

local Contract = require("../Contracts/ActivityTypes")
local Combat = require("../Contracts/CombatTypes")
local Income = require("../Data/Phase4EconomyData").ActIncome
local Campaign = require("./CampaignSession")
local Wallet = require("./Phase4Profile")
local Lineage = require("./SuccessionProfile")

export type Store = Campaign.Store
export type Options = {
	clock: () -> number, -- Server UTC Unix seconds.
	makeId: () -> string, -- Unique across sessions, runs, and missions.
	isSafeHub: (number) -> boolean,
}

type Action = Contract.Action
type Receipt = Contract.Receipt
type Bundle = Contract.CraftingBundle
type Row = Lineage.Row
type Lease = Wallet.Lease
type Failure = { code: Contract.ErrorCode, message: string }
type Run = { id: string, act: number, startedAtUtc: number, lastClaimedAtUtc: number }
type Mission = { id: string, act: number, startedAtUtc: number }
type Saved = {
	version: number,
	revision: number,
	run: Run?,
	mission: Mission?,
	lastClaim: Contract.AutoBattleClaim?,
	tickets: number,
	ticketAwards: { [string]: boolean },
	claimedMissions: { [string]: boolean },
	receipts: { [string]: { signature: string, receipt: Receipt } },
}
type Record = {
	wallet: Wallet.Record,
	activity: Saved,
	lineage: Lineage.Saved?,
	lease: Lease?,
}
type Change = (Saved, Record, number) -> (boolean, Bundle?, Failure?)

local LEASE_SECONDS = 180
local RENEW_BEFORE_SECONDS = 90
local MAX = Wallet.Limit
local TICK = Contract.AutoBattleTickSeconds
local DURATION = Contract.ExpeditionDurationSeconds

local function failure(code: Contract.ErrorCode, message: string): Failure
	return { code = code, message = message }
end

local function legality(reason: string?): Combat.ActionLegality
	return if reason then { canUse = false, disabledReason = reason } else { canUse = true }
end

local function empty(): Saved
	return { version = 1, revision = 0, tickets = 0, ticketAwards = {}, claimedMissions = {}, receipts = {} }
end

local function decode(value: unknown): Record?
	local wallet = Wallet.decode(value)
	if not wallet then return nil end
	local raw, lineage = Lineage.decodeRow(value)
	if not raw then return nil end
	local lease = Lineage.fields(raw.activityLease)
	if raw.activityLease ~= nil and (not lease or not Lineage.token(lease.sessionId)
		or not Wallet.integer(lease.expiresAt, 0, MAX)) then return nil end
	local activity = Lineage.fields(raw.activity)
	if raw.activity ~= nil then
		if not activity or activity.version ~= 1 or not Wallet.integer(activity.revision, 0, MAX)
			or not Wallet.integer(activity.tickets, 0, Contract.QuartermasterExpeditionMaxTickets)
			or type(activity.ticketAwards) ~= "table" or type(activity.claimedMissions) ~= "table"
			or type(activity.receipts) ~= "table" then return nil end
		for _, field in { "run", "mission" } do
			local entry = Lineage.fields(activity[field])
			if activity[field] ~= nil then
				if not entry or not Lineage.token(entry.id) or not Wallet.integer(entry.act, 1, 5)
					or not Wallet.integer(entry.startedAtUtc, 0, MAX - DURATION) then return nil end
				if field == "run" and not Wallet.integer(entry.lastClaimedAtUtc, entry.startedAtUtc :: number, MAX) then return nil end
			end
		end
	end
	return { wallet = wallet, activity = if activity then activity :: Saved else empty(), lineage = lineage, lease = lease :: Lease? }
end

local function maxTickets(record: Record): number
	local lineage = record.lineage
	return if lineage and (lineage.ranks.quartermaster_dispatch or 0) > 0
		then Contract.QuartermasterExpeditionMaxTickets else Contract.BaseExpeditionMaxTickets
end

local function cleared(lineage: Lineage.Saved?, act: number): boolean
	if not lineage then return false end
	-- Only the trusted first-clear hook records Act milestones. Act 1 node
	-- clears and replay rewards do not establish completion of an Act.
	local key = Lineage.actKey(act)
	if lineage.life.awardedMilestones[key] == true then return true end
	for _, life in lineage.closedLives do
		if life.awardedMilestones[key] == true then return true end
	end
	return false
end

local function bundle(quote: { read yen: number, read shards: number, read materials: number }, count: number): Bundle
	return { yen = quote.yen * count, salvageShards = quote.shards * count, materials = quote.materials * count }
end

local function pending(run: Run, at: number): number
	return math.max(0, math.floor((at - run.lastClaimedAtUtc) / TICK))
end

local function snapshot(record: Record, id: string, at: number, atHub: boolean): Contract.Snapshot
	local state = record.activity
	local unlocked: { Contract.AutoBattleActView } = {}
	for act = 1, 5 do
		if cleared(record.lineage, act) then
			local quote = Income[act].autoBattle5Min
			table.insert(unlocked, { act = act, rewardPreview = {
				yen = quote.yen, salvageShards = quote.shards, materials = quote.materials,
				maxStandardGearDrops = 0,
			} })
		end
	end
	local run, mission = state.run, state.mission
	local ticks = if run then pending(run, at) else 0
	local completesAt = if mission then mission.startedAtUtc + DURATION else nil
	local claimable = completesAt ~= nil and completesAt <= at
	local cap = maxTickets(record)
	return {
		sessionId = id, revision = state.revision, serverTimeUtc = at,
		autoBattle = {
			unlockedActs = unlocked, tickSeconds = TICK,
			runId = if run then run.id else nil, act = if run then run.act else nil,
			startedAtUtc = if run then run.startedAtUtc else nil, lastClaimedAtUtc = if run then run.lastClaimedAtUtc else nil,
			pendingTicks = ticks, lastClaim = Lineage.copy(state.lastClaim) :: Contract.AutoBattleClaim?,
			legality = {
				start = legality(if run then "Auto-Battle is already running." elseif not atHub then "Return to the Safe Hub."
					elseif #unlocked == 0 then "Manually clear an Act first." else nil),
				claim = legality(if ticks == 0 then "No Auto-Battle ticks are due." else nil),
				stop = legality(if not run then "No Auto-Battle is running." else nil),
			},
		},
		expedition = {
			tickets = math.min(state.tickets, cap), maxTickets = cap, durationSeconds = DURATION,
			missionId = if mission then mission.id else nil, act = if mission then mission.act else nil,
			startedAtUtc = if mission then mission.startedAtUtc else nil, completesAtUtc = completesAt, claimable = claimable,
			rewardPreview = if mission then bundle(Income[mission.act].expedition4Hr, 1) else nil,
			legality = {
				dispatch = legality(if mission then "Claim the current expedition first."
					elseif state.tickets == 0 then "An Expedition Ticket is required." else nil),
				claim = legality(if not claimable then "No expedition is ready to claim." else nil),
			},
		},
	}
end

local function checkedRequest(input: unknown): (Contract.ActionRequest?, string?)
	local row = Lineage.fields(input)
	local action = if row then Lineage.fields(row.action) else nil
	if not row or not action or not Lineage.token(row.sessionId) or not Lineage.token(row.requestId)
		or not Wallet.integer(row.expectedRevision, 0, MAX) then return nil, nil end
	local kind = action.kind
	local normalized: Action
	local argument: string
	if kind == "StartAutoBattle" or kind == "DispatchExpedition" then
		if not Wallet.integer(action.act, 1, 5) then return nil, nil end
		local act = action.act :: number
		normalized = if kind == "StartAutoBattle" then { kind = "StartAutoBattle" :: "StartAutoBattle", act = act }
			else { kind = "DispatchExpedition" :: "DispatchExpedition", act = act }
		argument = tostring(act)
	elseif kind == "ClaimAutoBattle" or kind == "StopAutoBattle" then
		if not Lineage.token(action.runId) then return nil, nil end
		local id = action.runId :: string
		normalized = if kind == "ClaimAutoBattle" then { kind = "ClaimAutoBattle" :: "ClaimAutoBattle", runId = id }
			else { kind = "StopAutoBattle" :: "StopAutoBattle", runId = id }
		argument = id
	elseif kind == "ClaimExpedition" then
		if not Lineage.token(action.missionId) then return nil, nil end
		local id = action.missionId :: string
		normalized, argument = { kind = kind, missionId = id }, id
	else
		return nil, nil
	end
	return {
		sessionId = row.sessionId :: string, requestId = row.requestId :: string,
		expectedRevision = row.expectedRevision :: number, action = normalized,
	}, normalized.kind .. ":" .. argument
end

local function settleRun(state: Saved, run: Run, at: number): Contract.AutoBattleClaim?
	local ticks = pending(run, at)
	if ticks == 0 then return nil end
	local paidThrough = run.lastClaimedAtUtc + ticks * TICK
	local claim: Contract.AutoBattleClaim = {
		runId = run.id, act = run.act, ticksClaimed = ticks, lastClaimedAtUtc = paidThrough,
		rewards = bundle(Income[run.act].autoBattle5Min, ticks), standardGear = {},
	}
	local advanced = table.clone(run)
	advanced.lastClaimedAtUtc = paidThrough
	state.run, state.lastClaim = advanced, claim
	return claim
end

local function apply(
	action: Action, state: Saved, record: Record, at: number, atHub: () -> boolean, makeId: () -> string
): (Receipt?, Bundle?, Failure?)
	local run, mission = state.run, state.mission
	if action.kind == "StartAutoBattle" then
		if run then return nil, nil, failure("AutoBattleAlreadyRunning", "Stop the current Auto-Battle first.") end
		if not cleared(record.lineage, action.act) then return nil, nil, failure("ActNotCleared", "Manually clear this Act first.") end
		if not atHub() then return nil, nil, failure("IllegalAction", "Start Auto-Battle from the Safe Hub.") end
		local id = makeId()
		if not Lineage.token(id) then return nil, nil, failure("SaveUnavailable", "Could not allocate an Auto-Battle ID.") end
		state.run = { id = id, act = action.act, startedAtUtc = at, lastClaimedAtUtc = at }
		return { kind = "AutoBattleStarted", runId = id, act = action.act, startedAtUtc = at }, nil, nil
	elseif action.kind == "ClaimAutoBattle" or action.kind == "StopAutoBattle" then
		if not run or run.id ~= action.runId then return nil, nil, failure("AutoBattleRunMismatch", "This run is no longer active.") end
		local claim = settleRun(state, run, at)
		if action.kind == "StopAutoBattle" then
			state.run = nil
			return { kind = "AutoBattleStopped", runId = run.id, stoppedAtUtc = at }, if claim then claim.rewards else nil, nil
		end
		if not claim then return nil, nil, failure("NoPendingTicks", "No Auto-Battle ticks are due.") end
		return {
			kind = "AutoBattleClaimed", runId = claim.runId, act = claim.act, ticksClaimed = claim.ticksClaimed,
			lastClaimedAtUtc = claim.lastClaimedAtUtc, rewards = claim.rewards, standardGear = claim.standardGear,
		}, claim.rewards, nil
	elseif action.kind == "DispatchExpedition" then
		if mission then return nil, nil, failure("ExpeditionSlotOccupied", "Claim the current expedition first.") end
		if state.tickets == 0 then return nil, nil, failure("InsufficientTickets", "An Expedition Ticket is required.") end
		local id = makeId()
		if not Lineage.token(id) or state.claimedMissions[id] then
			return nil, nil, failure("SaveUnavailable", "Could not allocate an Expedition ID.")
		end
		state.tickets -= 1
		state.mission = { id = id, act = action.act, startedAtUtc = at }
		return {
			kind = "ExpeditionDispatched", missionId = id, act = action.act,
			startedAtUtc = at, completesAtUtc = at + DURATION, ticketsSpent = 1,
		}, nil, nil
	end
	if state.claimedMissions[action.missionId] then return nil, nil, failure("AlreadyClaimed", "This expedition already paid out.") end
	if not mission or mission.id ~= action.missionId then return nil, nil, failure("ExpeditionMissionMismatch", "This mission is not active.") end
	if at < mission.startedAtUtc + DURATION then return nil, nil, failure("ExpeditionNotReady", "This expedition is still running.") end
	local rewards = bundle(Income[mission.act].expedition4Hr, 1)
	state.claimedMissions = table.clone(state.claimedMissions)
	state.claimedMissions[mission.id] = true
	state.mission = nil
	return { kind = "ExpeditionClaimed", missionId = mission.id, act = mission.act, rewards = rewards }, rewards, nil
end

local function withRewards(record: Wallet.Record, rewards: Bundle): Row?
	local yen = record.campaign.yen + rewards.yen
	local phase4 = table.clone(record.phase4)
	phase4.salvageShards += rewards.salvageShards
	phase4.materials += rewards.materials
	if not Wallet.integer(yen, 0, MAX) or not Wallet.integer(phase4.salvageShards, 0, MAX)
		or not Wallet.integer(phase4.materials, 0, MAX) or phase4.revision >= MAX or record.campaignRevision >= MAX then
		return nil
	end
	phase4.revision += 1
	return Wallet.encode(record, phase4, yen)
end

local function new(store: Store, options: Options)
	local sessions: { [number]: Lease } = {}

	local function now(): number
		local value = math.floor(options.clock())
		assert(Wallet.integer(value, 0, MAX - DURATION), "Activity requires a valid UTC clock")
		return value
	end

	local function transact(
		userId: number, id: string, mode: "Open" | "Renew" | "Change", change: Change?
	): (Record?, Failure?)
		local current: Record? = nil
		local rejected: Failure? = nil
		local committed, available = store.update(userId, function(value)
			current, rejected = nil, nil
			local session = sessions[userId]
			if not session or session.sessionId ~= id then
				rejected = failure("ProfileLocked", "This activity session is no longer open.")
				return nil
			end
			local record = decode(value)
			if not record then return nil end
			local at = now()
			local lease = record.lease
			local live = lease ~= nil and lease.expiresAt > at
			local owns = lease ~= nil and lease.sessionId == id
			if (mode == "Open" and live and not owns) or (mode ~= "Open" and not (live and owns)) then
				rejected = failure("ProfileLocked", "Open the activity session on the current server.")
				return nil
			end
			current = record
			local state = table.clone(record.activity)
			local raw: Row? = nil
			if change then
				local changed, rewards, denial = change(state, record, at)
				rejected = denial
				if not changed or denial then return nil end
				if state.revision >= MAX then
					rejected = failure("SaveUnavailable", "The activity profile limit was reached.")
					return nil
				end
				if rewards then
					raw = withRewards(record.wallet, rewards)
					if not raw then
						rejected = failure("IllegalAction", "The rewards would exceed the profile limit.")
						return nil
					end
				end
				state.revision += 1
			end
			local updated = raw or table.clone(record.wallet.raw)
			updated.activity = state
			updated.activityLease = { sessionId = id, expiresAt = at + LEASE_SECONDS }
			return updated
		end)
		if not available then
			return nil, failure("SaveUnavailable", "Could not confirm the activity save. Retry with the same request ID.")
		end
		if not committed then
			if current or rejected then return current, rejected end
			return nil, failure("SaveUnavailable", "Could not read the activity profile.")
		end
		local record = decode(committed)
		local lease = if record then record.lease else nil
		if not record or not lease or lease.sessionId ~= id then
			return nil, failure("SaveUnavailable", "Could not verify the activity save.")
		end
		if sessions[userId] and sessions[userId].sessionId == id then sessions[userId] = lease end
		return record, nil
	end

	local function view(userId: number, record: Record, id: string): Contract.Snapshot
		return snapshot(record, id, now(), options.isSafeHub(userId))
	end

	local function GetActivitySnapshot(userId: number): Contract.SnapshotResponse
		local at = now()
		local known = sessions[userId]
		local id = if known and known.expiresAt > at then known.sessionId else options.makeId()
		if not Lineage.token(id) then return { ok = false, code = "SaveUnavailable", message = "Could not allocate an activity session." } end
		sessions[userId] = { sessionId = id, expiresAt = at + LEASE_SECONDS }
		local record, reason = transact(userId, id, "Open", nil)
		if not record or reason then
			return { ok = false, code = if reason then reason.code else "SaveUnavailable",
				message = if reason then reason.message else "Could not open the activity profile." }
		end
		return { ok = true, snapshot = view(userId, record, id) }
	end

	local function SubmitActivityAction(userId: number, input: unknown): Contract.ActionResponse
		local request, signature = checkedRequest(input)
		if not request or not signature then return { ok = false, code = "InvalidRequest", message = "Invalid activity request." } end
		local id, requestId = request.sessionId, request.requestId
		local localLease = sessions[userId]
		if not localLease or localLease.sessionId ~= id then
			return { ok = false, requestId = requestId, code = "ProfileLocked", message = "Open the current activity session first." }
		end
		local generated: string? = nil
		local function actionId(): string
			local assigned = generated or options.makeId()
			generated = assigned
			return assigned
		end
		local record, reason = transact(userId, id, "Change", function(state, current, at)
			local cached = state.receipts[requestId]
			if cached then
				return false, nil, if cached.signature ~= signature
					then failure("RequestConflict", "This request ID belongs to a different action.") else nil
			end
			if request.expectedRevision ~= state.revision then
				return false, nil, failure("StaleRevision", "The activity state changed. Refresh and try again.")
			end
			local receipt, rewards, denial = apply(request.action, state, current, at, function()
				return options.isSafeHub(userId)
			end, actionId)
			if not receipt then return false, nil, denial end
			state.receipts = table.clone(state.receipts)
			state.receipts[requestId] = { signature = signature, receipt = receipt }
			return true, rewards, nil
		end)
		local saved = if record then record.activity.receipts[requestId] else nil
		if reason or not record or not saved then
			return { ok = false, requestId = requestId, code = if reason then reason.code else "SaveUnavailable",
				message = if reason then reason.message else "Could not verify the activity receipt.",
				snapshot = if record then view(userId, record, id) else nil }
		end
		return { ok = true, requestId = requestId, receipt = Lineage.copy(saved.receipt) :: Receipt, snapshot = view(userId, record, id) }
	end

	-- Host scheduler entry point. The stored boundary makes concurrent or lost-reply tick calls safe.
	local function tick(userId: number): Contract.SnapshotResponse
		local session = sessions[userId]
		if not session then return { ok = false, code = "ProfileLocked", message = "Open the activity session first." } end
		local id = session.sessionId
		local record, reason = transact(userId, id, "Change", function(state, _, at)
			local run = state.run
			local claim = if run then settleRun(state, run, at) else nil
			return claim ~= nil, if claim then claim.rewards else nil, nil
		end)
		if not record or reason then
			return { ok = false, code = if reason then reason.code else "SaveUnavailable",
				message = if reason then reason.message else "Could not settle Auto-Battle." }
		end
		return { ok = true, snapshot = view(userId, record, id) }
	end

	-- Trusted active-clear hook. Mark the source even at the cap so retrying it
	-- after dispatch cannot mint another ticket.
	local function grantExpeditionTicket(userId: number, awardId: string): boolean
		local session = sessions[userId]
		if not session or not Lineage.token(awardId) then return false end
		local record, reason = transact(userId, session.sessionId, "Change", function(state, current)
			if state.ticketAwards[awardId] then return false, nil, nil end
			state.ticketAwards = table.clone(state.ticketAwards)
			state.ticketAwards[awardId] = true
			state.tickets = math.min(state.tickets + 1, maxTickets(current))
			return true, nil, nil
		end)
		return record ~= nil and reason == nil
	end

	local function renew(userId: number)
		local lease = sessions[userId]
		if not lease or lease.expiresAt - now() > RENEW_BEFORE_SECONDS then return end
		local _, reason = transact(userId, lease.sessionId, "Renew", nil)
		if reason and reason.code == "ProfileLocked" and sessions[userId] == lease then sessions[userId] = nil end
	end

	local function close(userId: number)
		local lease = sessions[userId]
		if not lease then return end
		sessions[userId] = nil
		store.update(userId, function(value)
			local record = decode(value)
			if not record or not record.lease or record.lease.sessionId ~= lease.sessionId then return nil end
			local raw = table.clone(record.wallet.raw)
			raw.activityLease = nil
			return raw
		end)
	end

	return table.freeze({
		GetActivitySnapshot = GetActivitySnapshot, SubmitActivityAction = SubmitActivityAction,
		tick = tick, grantExpeditionTicket = grantExpeditionTicket, renew = renew, close = close,
	})
end

return table.freeze({ new = new })
