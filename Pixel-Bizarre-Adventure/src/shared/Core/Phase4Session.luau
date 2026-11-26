--!strict

local CampaignSession = require("./CampaignSession")
local Contract = require("../Contracts/Phase4EconomyTypes")
local Inventory = require("../Contracts/InventoryTypes")
local Data = require("../Data/Phase4EconomyData")
local Clinic = require("./Phase4Clinic")
local Parlor = require("./Phase4Parlor")
local Profile = require("./Phase4Profile")
local Smith = require("./Phase4Smith")

export type Store = CampaignSession.Store
export type Options = {
	clock: () -> number, -- UTC Unix seconds.
	makeId: () -> string, -- Unique IDs for sessions, smith offers and gear copies.
	roll: () -> number,
	prizeFor: Parlor.Catalog,
	displayItem: ((Inventory.ItemId) -> Inventory.ItemDisplay?)?,
}

type Saved = Profile.Saved
type Action = Contract.Action
local LEASE_SECONDS = 180
local RENEW_BEFORE_SECONDS = 90

local function fields(value: unknown): { [string]: unknown }?
	return if type(value) == "table" then value :: { [string]: unknown } else nil
end

local function token(value: unknown): boolean
	return type(value) == "string" and #value <= 128 and string.match(value, "^[%w_:%-]+$") ~= nil
end

local function checkRequest(raw: unknown): (Contract.ActionRequest?, string?)
	local request = fields(raw)
	if not request or not token(request.sessionId) or not token(request.requestId)
		or not Profile.integer(request.expectedRevision, 0, 2 * Profile.Limit) then return nil, nil end
	local action = fields(request.action)
	if not action or type(action.kind) ~= "string" then return nil, nil end
	local kind = action.kind
	local arguments: { string } = { kind }
	if kind == "CreateOffer" or kind == "ResolveOffer" or kind == "Temper" or kind == "Purify" or kind == "Dismantle" then
		if not token(action.itemUuid) then return nil, nil end
		table.insert(arguments, action.itemUuid :: string)
		if kind == "ResolveOffer" then
			local decision = action.decision
			if not token(action.offerId) or (decision ~= "AcceptNew" and decision ~= "KeepOld") then return nil, nil end
			table.insert(arguments, action.offerId :: string)
			table.insert(arguments, decision)
		elseif kind == "Purify" then
			local perk = action.perkId
			if type(perk) ~= "string" or not (Data.PurifiedPerks :: { [string]: unknown })[perk] then return nil, nil end
			table.insert(arguments, perk)
		end
	elseif kind == "InstallCyberware" or kind == "RemoveCyberware" then
		local site = action.site
		if type(site) ~= "string" or not (Data.Cyberware.Sites :: { [string]: unknown })[site] then return nil, nil end
		table.insert(arguments, site)
		if kind == "InstallCyberware" then
			if not Profile.integer(action.tier, 1, #Data.Cyberware.Tiers) then return nil, nil end
			table.insert(arguments, tostring(action.tier))
		end
	elseif kind == "SetEquippedRoutines" then
		if type(action.routineIds) ~= "table" then return nil, nil end
		local list = action.routineIds :: { [unknown]: unknown }
		-- Validate a dense numeric sequence before indexing it or fingerprinting it.
		local length = #list
		if length > 5 then return nil, nil end
		local count = 0
		for key, routine in list do
			if not Profile.integer(key, 1, length) or not token(routine) then return nil, nil end
			count += 1
		end
		if count ~= length then return nil, nil end
		for i = 1, length do table.insert(arguments, list[i] :: string) end
	elseif kind == "Spin" then
		local tierId = action.tierId
		if (tierId ~= "standard_chip" and tierId ~= "high_roller_chip")
			or (action.count ~= 1 and action.count ~= 10) then return nil, nil end
		table.insert(arguments, tierId)
		table.insert(arguments, tostring(action.count))
	else
		return nil, nil
	end
	-- The separator cannot appear in any accepted identifier.
	return request :: Contract.ActionRequest, table.concat(arguments, "|")
end

local function revision(record: Profile.Record): number
	return record.phase4.revision + record.campaignRevision
end

local function snapshot(record: Profile.Record, id: string, options: Options): Contract.Snapshot
	local state = record.phase4
	local yen = record.campaign.yen
	local entries: { Contract.SmithItemView } = {}
	local ids = {}
	for uuid in state.items do table.insert(ids, uuid) end
	table.sort(ids)
	for _, uuid in ids do table.insert(entries, Smith.view(state, yen, state.items[uuid], options.displayItem)) end
	return {
		sessionId = id, revision = revision(record),
		balances = { yen = yen, salvageShards = state.salvageShards, materials = state.materials, holyWater = state.holyWater },
		smithItems = entries, clinic = Clinic.view(state, yen), parlorTiers = Parlor.views(state, yen),
	}
end

local function apply(
	state: Saved, yen: number, action: Action, options: Options, roll: () -> number, makeId: () -> string
): (Contract.Receipt?, number, Contract.ErrorCode?, string?)
	if action.kind == "Spin" then
		return Parlor.spin(state, yen, action.tierId, action.count, options.prizeFor, roll, makeId)
	end
	if action.kind == "InstallCyberware" or action.kind == "RemoveCyberware" or action.kind == "SetEquippedRoutines" then
		if state.act < Data.Cyberware.UnlockAct then return nil, yen, "IllegalAction", "The Clinic unlocks in Act 2." end
		if action.kind == "InstallCyberware" then
			local code, reason = Clinic.checkInstall(state, yen, action.site, action.tier)
			if code then return nil, yen, code, reason end
			local implant = Clinic.install(action.site, action.tier)
			local price = Data.Cyberware.Tiers[action.tier]
			Clinic.replace(state, action.site, implant)
			state.salvageShards -= price.shards
			return { kind = "CyberwareInstalled", install = implant }, yen - price.yen, nil, nil
		elseif action.kind == "RemoveCyberware" then
			if not state.installs[action.site] then return nil, yen, "IllegalAction", "This site is empty." end
			Clinic.replace(state, action.site, nil)
			return { kind = "CyberwareRemoved", site = action.site }, yen, nil, nil
		end
		if action.kind == "SetEquippedRoutines" then
			if not Clinic.validRoutines(state, action.routineIds) then
				return nil, yen, "IllegalAction", "Choose distinct installed routines within the active limit."
			end
			state.equippedRoutines = table.clone(action.routineIds)
			return { kind = "EquippedRoutinesSet", routineIds = state.equippedRoutines }, yen, nil, nil
		end
		return nil, yen, "InvalidRequest", "Unknown Clinic action."
	end
	return Smith.apply(state, yen, action, roll, makeId)
end

local function replayable<T>(source: () -> T): () -> () -> T
	local draws: { T } = {}
	return function()
		local index = 0
		return function()
			index += 1
			local chosen = draws[index]
			if chosen ~= nil then return chosen end
			local fresh = source()
			draws[index] = fresh
			return fresh
		end
	end
end

-- Return detached data so headless callers cannot mutate the Store's in-memory records.
local function copy(value: unknown): unknown
	if type(value) ~= "table" then return value end
	local detached: { [unknown]: unknown } = {}
	for key, child in value :: { [unknown]: unknown } do detached[key] = copy(child) end
	return detached
end

local function new(store: Store, options: Options)
	local sessions: { [number]: Profile.Lease } = {}

	local function GetPhase4Snapshot(userId: number): Contract.SnapshotResponse
		local previous = sessions[userId]
		local now = options.clock()
		local id = if previous and previous.expiresAt > now then previous.sessionId else options.makeId()
		-- Keep the proposed ID when an acquire may have committed before losing its reply.
		sessions[userId] = { sessionId = id, expiresAt = now + LEASE_SECONDS }
		local denied: Contract.ErrorCode = "SaveUnavailable"
		local raw, available = store.update(userId, function(value)
			denied = "SaveUnavailable"
			local record = Profile.decode(value)
			if not record then return nil end
			local lease = record.phase4.lease
			local at = options.clock()
			if lease and lease.sessionId ~= id and lease.expiresAt > at then
				denied = "ProfileLocked"
				return nil
			end
			local state = table.clone(record.phase4)
			state.lease = { sessionId = id, expiresAt = at + LEASE_SECONDS }
			return Profile.encode(record, state, record.campaign.yen)
		end)
		local record = if available and raw then Profile.decode(raw) else nil
		if not record then
			return { ok = false, code = if available then denied else "SaveUnavailable", message = "Could not open the economy profile." }
		end
		sessions[userId] = assert(record.phase4.lease)
		return { ok = true, snapshot = copy(snapshot(record, id, options)) :: Contract.Snapshot }
	end

	local function SubmitPhase4Action(userId: number, input: unknown): Contract.ActionResponse
		local request, signature = checkRequest(input)
		if not request or not signature then return { ok = false, code = "InvalidRequest", message = "Invalid economy request." } end
		local requestId = request.requestId
		local id = request.sessionId
		local localLease = sessions[userId]
		if not localLease or localLease.sessionId ~= id then
			return { ok = false, requestId = requestId, code = "ProfileLocked", message = "Open the current economy session first." }
		end
		local beginRoll = replayable(options.roll)
		local beginId = replayable(options.makeId)
		local denial: Contract.ErrorCode = "SaveUnavailable"
		local message = "Could not save the economy action."
		local rejectedRecord: Profile.Record? = nil
		local raw, available = store.update(userId, function(value)
			denial, message, rejectedRecord = "SaveUnavailable", "Could not save the economy action.", nil
			local record = Profile.decode(value)
			if not record then return nil end
			local state = record.phase4
			local at = options.clock()
			local lease = state.lease
			if not lease or lease.sessionId ~= id or lease.expiresAt <= at then
				denial, message = "ProfileLocked", "The economy session expired. Refresh to reconnect."
				return nil
			end
			rejectedRecord = record
			local saved = state.receipts[requestId]
			if saved then
				if saved.signature ~= signature then
					denial, message = "RequestConflict", "This request ID belongs to a different action."
					return nil
				end
				-- Read the durable receipt even when the original expected revision is stale.
				return record.raw
			end
			if request.expectedRevision ~= revision(record) then
				denial, message = "StaleRevision", "The economy profile changed. Refresh and try again."
				return nil
			end
			local updated = table.clone(state)
			local receipt, yen, code, reason = apply(updated, record.campaign.yen, request.action, options, beginRoll(), beginId())
			if not receipt then
				denial, message = code or "IllegalAction", reason or "The economy action is unavailable."
				return nil
			end
			if not Profile.integer(yen, 0, Profile.Limit) or not Profile.integer(updated.salvageShards, 0, Profile.Limit)
				or not Profile.integer(updated.materials, 0, Profile.Limit) or not Profile.integer(updated.holyWater, 0, Profile.Limit)
				or updated.revision >= Profile.Limit or (yen ~= record.campaign.yen and record.campaignRevision >= Profile.Limit) then
				denial, message = "IllegalAction", "This action would exceed the profile limit."
				return nil
			end
			updated.revision += 1
			updated.lease = { sessionId = id, expiresAt = at + LEASE_SECONDS }
			updated.receipts = table.clone(state.receipts)
			updated.receipts[requestId] = { signature = signature, receipt = receipt }
			return Profile.encode(record, updated, yen)
		end)
		if not available then return { ok = false, requestId = requestId, code = "SaveUnavailable", message = "Could not confirm the save. Retry with the same request ID." } end
		local record = if raw then Profile.decode(raw) else nil
		local saved = if record then record.phase4.receipts[requestId] else nil
		if not record or not saved or saved.signature ~= signature then
			local current = rejectedRecord
			return {
				ok = false, requestId = requestId, code = denial, message = message,
				snapshot = if current then copy(snapshot(current, id, options)) :: Contract.Snapshot else nil,
			}
		end
		sessions[userId] = assert(record.phase4.lease)
		return {
			ok = true, requestId = requestId, receipt = copy(saved.receipt) :: Contract.Receipt,
			snapshot = copy(snapshot(record, id, options)) :: Contract.Snapshot,
		}
	end

	local function renew(userId: number)
		local lease = sessions[userId]
		if not lease or lease.expiresAt - options.clock() > RENEW_BEFORE_SECONDS then return end
		local lostLease = false
		local raw, available = store.update(userId, function(value)
			lostLease = false
			local record = Profile.decode(value)
			if not record then return nil end
			local at = options.clock()
			local current = record.phase4.lease
			if not current or current.sessionId ~= lease.sessionId or current.expiresAt <= at then
				lostLease = true
				return nil
			end
			local state = table.clone(record.phase4)
			state.lease = { sessionId = lease.sessionId, expiresAt = at + LEASE_SECONDS }
			return Profile.encode(record, state, record.campaign.yen)
		end)
		if sessions[userId] ~= lease or not available then return end
		local record = if raw then Profile.decode(raw) else nil
		if record then
			sessions[userId] = assert(record.phase4.lease)
		elseif lostLease then
			sessions[userId] = nil
		end
	end

	local function close(userId: number)
		local lease = sessions[userId]
		if not lease then return end
		sessions[userId] = nil
		store.update(userId, function(value)
			local record = Profile.decode(value)
			if not record or not record.phase4.lease or record.phase4.lease.sessionId ~= lease.sessionId then return nil end
			local state = table.clone(record.phase4)
			state.lease = nil
			return Profile.encode(record, state, record.campaign.yen)
		end)
	end

	return table.freeze({
		GetPhase4Snapshot = GetPhase4Snapshot, SubmitPhase4Action = SubmitPhase4Action, renew = renew, close = close,
	})
end

return table.freeze({ new = new })
