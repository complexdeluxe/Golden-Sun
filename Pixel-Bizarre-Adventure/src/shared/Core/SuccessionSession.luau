--!strict

local Campaign = require("./CampaignSession")
local Profile = require("./SuccessionProfile")
local Contract = require("../Contracts/SuccessionTypes")
local Data = require("../Data/BloodlineTreeData")

export type Store = Campaign.Store
export type Options = {
	clock: () -> number,
	makeId: () -> string,
	-- Authoritative location from the host. Never accept Hub state from an action payload.
	isSafeHub: (number) -> boolean,
	-- Frozen into the life record. The default is the lower end of the spec's 75–80 range.
	baseNaturalDeathAge: number?,
	-- Live hosts patch the campaign and wallet inside the lineage transaction.
	applyHeirReset: ((Profile.Row, Profile.Saved, Profile.Saved) -> Profile.Row?)?,
}
export type CastleWipe = {
	lifeId: Contract.LifeId,
	eventId: string,
	act: number,
	encounterKind: "Tutorial" | "Flag" | "Dungeon" | "Castle",
	mode: "FirstClear" | "Replay",
	fullPartyWipe: boolean,
}
export type MasteryAward = {
	lifeId: Contract.LifeId,
	eventId: string,
	kitId: Contract.KitId,
	mode: "FirstClear" | "Replay" | "AutoBattle" | "Expedition",
}
export type HookResponse =
	{ ok: true, changed: boolean, snapshot: Contract.Snapshot, settlement: Profile.Settlement? }
	| { ok: false, code: Contract.ErrorCode, message: string }

type Saved = Profile.Saved
type Change = (Saved, boolean) -> (boolean, Contract.ErrorCode?, string?)
local LEASE_SECONDS = 180
local RENEW_BEFORE_SECONDS = 90

local function checkedRequest(raw: unknown): (Contract.ActionRequest?, string?)
	local request = Profile.fields(raw)
	if not request or not Profile.token(request.requestId) or not Profile.token(request.sessionId)
		or not Profile.integer(request.expectedRevision, 0, Profile.MaxValue) then return nil, nil end
	local action = Profile.fields(request.action)
	if not action or type(action.kind) ~= "string" then return nil, nil end
	local kind = action.kind
	local parts: { string } = { kind }
	if kind == "PurchaseBloodlineNode" then
		if type(action.nodeId) ~= "string" or not (Data.Nodes :: { [string]: Data.Node })[action.nodeId] then return nil, nil end
		table.insert(parts, action.nodeId)
	elseif kind == "PassTheTorch" then
		if not Profile.token(action.lifeId) or type(action.confirmed) ~= "boolean" then return nil, nil end
		table.insert(parts, action.lifeId :: string)
		table.insert(parts, tostring(action.confirmed))
	elseif kind == "SetCarriedHeirlooms" then
		if type(action.heirloomIds) ~= "table" then return nil, nil end
		local list = action.heirloomIds :: { [unknown]: unknown }
		local length, count = #list, 0
		if length > Contract.MaxHeirloomCarryLimit then return nil, nil end
		for key, value in list do
			if not Profile.integer(key, 1, length) or not Profile.token(value) then return nil, nil end
			count += 1
		end
		if count ~= length then return nil, nil end
		for i = 1, length do table.insert(parts, list[i] :: string) end
	elseif kind == "SetAttunedHeirloom" then
		if action.heirloomId ~= nil and not Profile.token(action.heirloomId) then return nil, nil end
		table.insert(parts, if action.heirloomId == nil then "" else action.heirloomId :: string)
	elseif kind == "SetMasteryVariant" or kind == "SetMasteryTargetMode" then
		local mode = if kind == "SetMasteryVariant" then action.variant else action.targetMode
		if not Profile.token(action.kitId) or (mode ~= "Default" and mode ~= "Alt") then return nil, nil end
		table.insert(parts, action.kitId :: string)
		table.insert(parts, mode)
	else
		return nil, nil
	end
	return request :: Contract.ActionRequest, table.concat(parts, "|")
end

local function apply(
	state: Saved, action: Contract.Action, atHub: boolean, makeLifeId: () -> string
): (Contract.Receipt?, Contract.ErrorCode?, string?)
	if action.kind == "PurchaseBloodlineNode" then
		local node = Data.Nodes[action.nodeId]
		local rank = (state.ranks[action.nodeId] or 0) + 1
		local price = node.costs[rank]
		if not price then return nil, "IllegalAction", "This node is already at maximum rank." end
		if state.echoes < price then return nil, "InsufficientEchoes", "Not enough Echoes." end
		state.ranks = table.clone(state.ranks)
		state.ranks[action.nodeId] = rank
		state.echoes -= price
		return { kind = "BloodlineNodePurchased", nodeId = action.nodeId, rank = rank, spentEchoes = price }, nil, nil
	end
	if action.kind == "PassTheTorch" then
		if state.life.ledgerSettled or state.closedLives[action.lifeId] then return nil, "AlreadySettled", "This life already settled." end
		if action.lifeId ~= state.life.id then return nil, "IllegalAction", "This life is no longer current." end
		if not atHub or not Profile.ledger(state.life).canRetireNow then
			return nil, "IllegalAction", "Voluntary retirement requires the Safe Hub and an Act 3 clear."
		end
		if not action.confirmed then return nil, "ConfirmationRequired", "Confirm retirement for this life." end
		local retiredLifeId = state.life.id
		local payout = Profile.settle(state, "Voluntary")
		if not Profile.beginNextLife(state, makeLifeId()) then return nil, "SaveUnavailable", "Could not create the next life." end
		return {
			kind = "PassedTheTorch", retiredLifeId = retiredLifeId,
			nextLifeId = state.life.id, echoesAwarded = payout.echoesAwarded,
		}, nil, nil
	end
	if state.life.ledgerSettled then return nil, "AlreadySettled", "This life already settled." end
	if action.kind == "SetCarriedHeirlooms" then
		if not atHub then return nil, "IllegalAction", "Return to the Safe Hub." end
		local selected = action.heirloomIds
		if #selected > Profile.carryLimit(state) then return nil, "IllegalAction", "Heirloom carry limit exceeded." end
		local seen: { [string]: boolean } = {}
		for _, id in selected do
			if seen[id] or not state.unlockedHeirlooms[id] then
				return nil, "IllegalAction", "Choose distinct unlocked heirlooms."
			end
			seen[id] = true
		end
		state.carriedHeirlooms = table.clone(selected)
		if state.attunedHeirloom and not seen[state.attunedHeirloom] then state.attunedHeirloom = nil end
		return { kind = "CarriedHeirloomsSet", heirloomIds = state.carriedHeirlooms, attunedId = state.attunedHeirloom }, nil, nil
	elseif action.kind == "SetAttunedHeirloom" then
		if not atHub then return nil, "IllegalAction", "Return to the Safe Hub." end
		local id = action.heirloomId
		if id and (not state.unlockedHeirlooms[id] or not table.find(state.carriedHeirlooms, id)) then
			return nil, "IllegalAction", "Only a carried heirloom can be attuned."
		end
		state.attunedHeirloom = id
		return { kind = "AttunedHeirloomSet", heirloomId = id }, nil, nil
	end
	local known = state.mastery[action.kitId]
	if not known then return nil, "IllegalAction", "This kit has no mastery record." end
	local updated = table.clone(known)
	local receipt: Contract.Receipt
	if action.kind == "SetMasteryVariant" then
		if action.variant == "Alt" and known.marks < Contract.MasteryUtilityVariantMarks then
			return nil, "IllegalAction", "Alternate utility requires five marks."
		end
		updated.utilityVariant = action.variant
		receipt = { kind = "MasteryVariantSet", kitId = action.kitId, variant = action.variant }
	else
		if action.targetMode == "Alt" and known.marks < Contract.MasteryAltTargetMarks then
			return nil, "IllegalAction", "Alternate targeting requires two marks."
		end
		updated.targetMode = action.targetMode
		receipt = { kind = "MasteryTargetModeSet", kitId = action.kitId, targetMode = action.targetMode }
	end
	state.mastery = table.clone(state.mastery)
	state.mastery[action.kitId] = updated
	return receipt, nil, nil
end

local function new(store: Store, options: Options)
	local baseAge = options.baseNaturalDeathAge or 75
	assert(Profile.integer(baseAge, 75, 80), "Base natural death age must be 75–80")
	local sessions: { [number]: Profile.Lease } = {}

	local function view(userId: number, state: Saved, id: string): Contract.Snapshot
		return Profile.copy(Profile.snapshot(state, id, options.isSafeHub(userId))) :: Contract.Snapshot
	end

	local function GetLineageSnapshot(userId: number): Contract.SnapshotResponse
		local known = sessions[userId]
		local now = options.clock()
		local id = if known and known.expiresAt > now then known.sessionId else options.makeId()
		sessions[userId] = { sessionId = id, expiresAt = now + LEASE_SECONDS }
		local denial: Contract.ErrorCode = "SaveUnavailable"
		local migrationId: string? = nil
		local committed, available = store.update(userId, function(value)
			denial = "SaveUnavailable"
			local raw, state, lease = Profile.decodeRow(value)
			if not raw then return nil end
			local at = options.clock()
			if lease and lease.sessionId ~= id and lease.expiresAt > at then
				denial = "ProfileLocked"
				return nil
			end
			if not state then
				local lifeId = migrationId or options.makeId()
				migrationId = lifeId
				if not Profile.token(lifeId) then return nil end
				state = Profile.new(lifeId, baseAge)
			end
			return Profile.encodeRow(raw, assert(state), { sessionId = id, expiresAt = at + LEASE_SECONDS })
		end)
		if available and committed then
			local _, state, lease = Profile.decodeRow(committed)
			if state and lease and lease.sessionId == id then
				sessions[userId] = lease
				return { ok = true, snapshot = view(userId, state, id) }
			end
		end
		return { ok = false, code = if available then denial else "SaveUnavailable", message = "Could not open the lineage profile." }
	end

	local function transact(
		userId: number, id: string, change: Change
	): (Saved?, boolean, Contract.ErrorCode?, string?)
		local current: Saved? = nil
		local code: Contract.ErrorCode? = nil
		local message: string? = nil
		local changed = false
		local committed, available = store.update(userId, function(value)
			current, changed, code, message = nil, false, nil, nil
			local raw, state, lease = Profile.decodeRow(value)
			if not raw or not state then
				code, message = "SaveUnavailable", "Could not open the lineage profile."
				return nil
			end
			local at = options.clock()
			if not lease or lease.sessionId ~= id or lease.expiresAt <= at then
				code, message = "ProfileLocked", "The lineage session expired or belongs to another server."
				return nil
			end
			current = state
			local updated = table.clone(state)
			updated.life = table.clone(state.life)
			changed, code, message = change(updated, options.isSafeHub(userId))
			if code or not changed then return nil end
			if state.revision >= Profile.MaxValue or not Profile.integer(updated.echoes, 0, Profile.MaxValue) then
				changed, code, message = false, "SaveUnavailable", "The lineage profile limit was reached."
				return nil
			end
			updated.revision += 1
			local persisted = if options.applyHeirReset then options.applyHeirReset(raw, state, updated) else raw
			if not persisted then
				changed, code, message = false, "SaveUnavailable", "Could not commit the heir's campaign profile."
				return nil
			end
			return Profile.encodeRow(persisted, updated, { sessionId = id, expiresAt = at + LEASE_SECONDS })
		end)
		if not available then return nil, false, "SaveUnavailable", "Could not confirm the lineage save. Retry the same request or event." end
		if not changed then return current, false, code, message end
		local _, state, lease = Profile.decodeRow(committed)
		if not state or not lease or lease.sessionId ~= id then return nil, false, "SaveUnavailable", "Could not verify the lineage save." end
		sessions[userId] = lease
		return state, true, nil, nil
	end

	local function SubmitLineageAction(userId: number, input: unknown): Contract.ActionResponse
		local request, signature = checkedRequest(input)
		if not request or not signature then return { ok = false, code = "InvalidRequest", message = "Invalid lineage request." } end
		local id, requestId = request.sessionId, request.requestId
		local session = sessions[userId]
		if not session or session.sessionId ~= id then
			return { ok = false, requestId = requestId, code = "ProfileLocked", message = "Open the current lineage session first." }
		end
		local newLifeId: string? = nil
		local state, _, code, reason = transact(userId, id, function(updated, atHub)
			local cached = updated.receipts[requestId]
			if cached then
				if cached.signature ~= signature then return false, "RequestConflict", "This request ID belongs to another action." end
				return false, nil, nil
			end
			if request.expectedRevision ~= updated.revision then return false, "StaleRevision", "The lineage state changed." end
			local receipt, failure, detail = apply(updated, request.action, atHub, function()
				local generated = newLifeId or options.makeId()
				newLifeId = generated
				return generated
			end)
			if not receipt then return false, failure or "IllegalAction", detail end
			updated.receipts = table.clone(updated.receipts)
			updated.receipts[requestId] = { signature = signature, receipt = receipt }
			return true, nil, nil
		end)
		if code or not state then
			return {
				ok = false, requestId = requestId, code = code or "SaveUnavailable", message = reason or "Could not save the action.",
				snapshot = if state then view(userId, state, id) else nil,
			}
		end
		local receipt = state.receipts[requestId]
		if not receipt or receipt.signature ~= signature then
			return { ok = false, requestId = requestId, code = "SaveUnavailable", message = "Could not verify the saved receipt." }
		end
		return {
			ok = true, requestId = requestId, receipt = Profile.copy(receipt.receipt) :: Contract.Receipt,
			snapshot = view(userId, state, id),
		}
	end

	local function invalidEvent(): HookResponse
		return { ok = false, code = "InvalidRequest", message = "Invalid lineage event." }
	end

	-- Hooks are for trusted encounter/progression code. Each targets a specific life.
		local function event(userId: number, lifeId: string, change: Change, terminalReplayId: string?): HookResponse
		if not Profile.token(lifeId) then return invalidEvent() end
		local lease = sessions[userId]
		if not lease then return { ok = false, code = "ProfileLocked", message = "Open the lineage session first." } end
		local state, changed, code, reason = transact(userId, lease.sessionId, function(updated, hub)
			local closed = updated.closedLives[lifeId]
			if closed then
				local settlement = closed.settlement
				if terminalReplayId and settlement and settlement.cause == "CastleWipe" and settlement.eventId == terminalReplayId then
					return false, nil, nil
				end
				return false, "AlreadySettled", "That life already settled."
			end
			if updated.life.id ~= lifeId then return false, "IllegalAction", "That life is not current." end
			return change(updated, hub)
		end)
		if code or not state then return { ok = false, code = code or "SaveUnavailable", message = reason or "Could not save the event." } end
		return {
			ok = true, changed = changed, snapshot = view(userId, state, lease.sessionId),
			settlement = Profile.copy((state.closedLives[lifeId] or state.life).settlement) :: Profile.Settlement?,
		}
	end

	local function recordActClear(userId: number, lifeId: string, act: number, mode: ("FirstClear" | "Replay")?): HookResponse
		if not Profile.integer(act, 1, #Data.ActEchoes) then return invalidEvent() end
		return event(userId, lifeId, function(state)
			local life, key = state.life, Profile.actKey(act)
			if mode == "Replay" or life.awardedMilestones[key] then return false, nil, nil end
			if life.ledgerSettled then return false, "AlreadySettled", "This life already settled." end
			if act ~= Profile.latestAct(life) + 1 then return false, "IllegalAction", "Record Acts in clear order." end
			life.awardedMilestones = table.clone(life.awardedMilestones)
			life.awardedMilestones[key] = true
			if act == #Data.ActEchoes then life.act5Vested = true end
			return true, nil, nil
		end)
	end

	local function recordEndgameChallenge(userId: number, lifeId: string, challengeId: string, sameTier: boolean): HookResponse
		if not Data.EndgameChallengeEchoes[challengeId] then return invalidEvent() end
		return event(userId, lifeId, function(state)
			local life, key = state.life, Profile.challengeKey(challengeId)
			if not sameTier or life.awardedMilestones[key] then return false, nil, nil end
			if life.ledgerSettled then return false, "AlreadySettled", "This life already settled." end
			if not life.act5Vested then return false, "IllegalAction", "Endgame challenges require the Act 5 clear." end
			life.awardedMilestones = table.clone(life.awardedMilestones)
			life.awardedMilestones[key] = true
			return true, nil, nil
		end)
	end

	local function recordCastleWipe(userId: number, wipe: CastleWipe): HookResponse
		if not Profile.token(wipe.eventId) or not Profile.integer(wipe.act, 1, #Data.ActEchoes) then return invalidEvent() end
		local heirId: string? = nil
		return event(userId, wipe.lifeId, function(state)
			local life = state.life
			if not wipe.fullPartyWipe or wipe.encounterKind ~= "Castle" or wipe.mode ~= "FirstClear"
				or life.awardedMilestones[Profile.actKey(wipe.act)] or life.castleWipes[wipe.eventId] then return false, nil, nil end
			if life.ledgerSettled then return false, "AlreadySettled", "This life already settled." end
			if wipe.act ~= Profile.latestAct(life) + 1 then return false, "IllegalAction", "This Castle is not the current Act." end
			life.castleWipes = table.clone(life.castleWipes)
			life.castleWipes[wipe.eventId] = true
			if life.recoveriesRemaining == 0 then
				Profile.settle(state, "CastleWipe", wipe.eventId)
				if options.applyHeirReset then
					local id = heirId or options.makeId()
					heirId = id
					if not Profile.beginNextLife(state, id) then return false, "SaveUnavailable", "Could not create the next life." end
				end
			else
				life.recoveriesRemaining -= 1
			end
			return true, nil, nil
		end, if options.applyHeirReset and wipe.fullPartyWipe and wipe.encounterKind == "Castle" and wipe.mode == "FirstClear"
			then wipe.eventId else nil)
	end

	local function advanceAge(userId: number, lifeId: string, eventId: string, years: number): HookResponse
		if not Profile.token(eventId) or not Profile.integer(years, 0, 95) then return invalidEvent() end
		return event(userId, lifeId, function(state)
			local life = state.life
			if life.ageEvents[eventId] or years == 0 then return false, nil, nil end
			if life.ledgerSettled then return false, "AlreadySettled", "This life already settled." end
			life.ageEvents = table.clone(life.ageEvents)
			life.ageEvents[eventId] = true
			local threshold = Profile.naturalDeathAge(state)
			life.age = math.min(threshold, life.age + years)
			if life.age >= threshold then Profile.settle(state, "OldAge") end
			return true, nil, nil
		end)
	end

	local function awardMasteryMark(userId: number, award: MasteryAward): HookResponse
		if not Profile.token(award.eventId) or not Profile.token(award.kitId) then return invalidEvent() end
		return event(userId, award.lifeId, function(state)
			local life, key = state.life, award.kitId .. "|" .. award.eventId
			local mastery = state.mastery[award.kitId]
			if award.mode ~= "FirstClear" or life.masteryEvents[key] or (mastery and mastery.marks >= Contract.MasteryTitleMarks) then
				return false, nil, nil
			end
			for _, closed in state.closedLives do
				if closed.masteryEvents[key] then return false, nil, nil end
			end
			if life.ledgerSettled then return false, "AlreadySettled", "This life already settled." end
			life.masteryEvents = table.clone(life.masteryEvents)
			life.masteryEvents[key] = true
			state.mastery = table.clone(state.mastery)
			state.mastery[award.kitId] = {
				marks = if mastery then mastery.marks + 1 else 1,
				targetMode = if mastery then mastery.targetMode else "Default",
				utilityVariant = if mastery then mastery.utilityVariant else "Default",
			}
			return true, nil, nil
		end)
	end

	local function unlockHeirloom(userId: number, lifeId: string, heirloomId: string): HookResponse
		if not Data.HeirloomsById[heirloomId] then return invalidEvent() end
		return event(userId, lifeId, function(state)
			if state.unlockedHeirlooms[heirloomId] then return false, nil, nil end
			if state.life.ledgerSettled then return false, "AlreadySettled", "This life already settled." end
			state.unlockedHeirlooms = table.clone(state.unlockedHeirlooms)
			state.unlockedHeirlooms[heirloomId] = true
			return true, nil, nil
		end)
	end

	-- Terminal death leaves the settled ledger visible until the host starts the heir.
	local function beginNextLife(userId: number, retiredLifeId: string): HookResponse
		local pendingLifeId: string? = nil
		return event(userId, retiredLifeId, function(state)
			if not state.life.ledgerSettled then return false, "IllegalAction", "Settle the current life first." end
			local lifeId = pendingLifeId or options.makeId()
			pendingLifeId = lifeId
			if not Profile.beginNextLife(state, lifeId) then return false, "SaveUnavailable", "Could not create the next life." end
			return true, nil, nil
		end)
	end

	local function renew(userId: number)
		local known = sessions[userId]
		if not known or known.expiresAt - options.clock() > RENEW_BEFORE_SECONDS then return end
		local result, available = store.update(userId, function(value)
			local raw, state, lease = Profile.decodeRow(value)
			local now = options.clock()
			if not raw or not state or not lease or lease.sessionId ~= known.sessionId or lease.expiresAt <= now then return nil end
			return Profile.encodeRow(raw, state, { sessionId = known.sessionId, expiresAt = now + LEASE_SECONDS })
		end)
		if available and result and sessions[userId] == known then
			local _, _, lease = Profile.decodeRow(result)
			sessions[userId] = lease
		end
	end

	local function close(userId: number)
		local known = sessions[userId]
		if not known then return end
		sessions[userId] = nil
		store.update(userId, function(value)
			local raw, state, lease = Profile.decodeRow(value)
			if not raw or not state or not lease or lease.sessionId ~= known.sessionId then return nil end
			return Profile.encodeRow(raw, state, nil)
		end)
	end

	return table.freeze({
		GetLineageSnapshot = GetLineageSnapshot, SubmitLineageAction = SubmitLineageAction,
		recordActClear = recordActClear, recordEndgameChallenge = recordEndgameChallenge, recordCastleWipe = recordCastleWipe,
		advanceAge = advanceAge, awardMasteryMark = awardMasteryMark, unlockHeirloom = unlockHeirloom,
		beginNextLife = beginNextLife, renew = renew, close = close,
	})
end

return table.freeze({ new = new })
