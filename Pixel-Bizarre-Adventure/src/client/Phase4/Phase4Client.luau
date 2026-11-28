--!strict
-- The Phase 4 economy protocol for the Hub stations, without any UI.
--
-- The server owns every price, roll and legality check. This module only keeps
-- the latest Phase 4 snapshot and turns a player's selection into a request:
--
--   * Each action carries the snapshot's sessionId and expectedRevision and a
--     fresh requestId.
--   * An uncertain reply (the call errored, came back empty, or the server said
--     SaveUnavailable) is retried with the same request, so the server can
--     return the receipt it already committed instead of charging twice. If the
--     retries run out, or a reconnect fails, the request is kept with its
--     original ID and action. The next press of any action sends that request
--     again first. Only a definitive reply clears it.
--   * ProfileLocked means the lease expired. The client opens a new session
--     and, if an earlier attempt was uncertain, retries the same requestId and
--     action under it.
--   * StaleRevision (and any other definitive rejection) adopts the snapshot the
--     server returned so the station can show the new price or balance. It is
--     never retried automatically.
--
-- The transport is injected so the same logic runs over the real remotes in
-- Roblox and over Phase4Session in headless checks.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Contract = require(ReplicatedStorage.Shared.Contracts.Phase4EconomyTypes)

type Snapshot = Contract.Snapshot
type Action = Contract.Action
type ActionRequest = Contract.ActionRequest
type Receipt = Contract.Receipt

export type Transport = {
	-- Both may error or return a non-table when the call is lost.
	getSnapshot: () -> unknown,
	submit: (request: ActionRequest) -> unknown,
}

export type Options = {
	makeId: () -> string,
	wait: (seconds: number) -> (),
	-- Retries after the first uncertain attempt. Defaults to 3.
	retries: number?,
}

export type Result = {
	ok: boolean,
	receipt: Receipt?,
	code: string?,
	message: string?,
	-- True when the server never confirmed either way. The request is kept.
	uncertain: boolean?,
	-- True when this reply settled an earlier unconfirmed action instead of the
	-- one just pressed. The receipt (if any) belongs to that earlier action.
	resolvedPending: boolean?,
}

export type Client = {
	snapshot: (self: Client) -> Snapshot?,
	refresh: (self: Client) -> Result,
	perform: (self: Client, action: Action) -> Result,
	-- The action still waiting for a confirmed reply, if any.
	pendingAction: (self: Client) -> Action?,
}

local BACKOFF_SECONDS = { 0.5, 1, 2, 3 }

-- Same fields in the same order as the server's request fingerprint.
local function signature(action: Action): string
	local raw = action :: any
	local parts: { string } = { raw.kind }
	for _, field in { "itemUuid", "offerId", "decision", "perkId", "site", "tier", "tierId", "count" } do
		local value = raw[field]
		if value ~= nil then
			table.insert(parts, `{field}={value}`)
		end
	end
	if type(raw.routineIds) == "table" then
		table.insert(parts, "routines=" .. table.concat(raw.routineIds, ","))
	end
	return table.concat(parts, "|")
end

local function isTable(value: unknown): boolean
	return type(value) == "table"
end

local Phase4Client = {}

Phase4Client.signature = signature

function Phase4Client.new(transport: Transport, options: Options): Client
	local current: Snapshot? = nil
	-- An unconfirmed request, kept with its original ID and action until the
	-- server answers it definitively.
	local held: { request: ActionRequest, signature: string }? = nil
	local retries = options.retries or 3

	local function adopt(incoming: unknown)
		if type(incoming) ~= "table" then
			return
		end
		local snapshot = incoming :: Snapshot
		if type(snapshot.sessionId) ~= "string" or type(snapshot.revision) ~= "number" then
			return
		end
		-- Every reply is from a call this client made one at a time, so it is the
		-- newest view of the profile, even when its revision went down after a
		-- new session.
		current = snapshot
	end

	local self = {} :: Client

	function self.snapshot(_self: Client): Snapshot?
		return current
	end

	function self.pendingAction(_self: Client): Action?
		local kept = held
		return if kept then kept.request.action else nil
	end

	function self.refresh(_self: Client): Result
		local success, reply = pcall(transport.getSnapshot)
		if not success or not isTable(reply) then
			return { ok = false, code = "SaveUnavailable", message = "Couldn't reach the Blacksmith. Try again.", uncertain = true }
		end
		local response = reply :: any
		if response.ok == true then
			adopt(response.snapshot)
			return { ok = true }
		end
		return { ok = false, code = response.code, message = response.message }
	end

	local function hold(request: ActionRequest, key: string): Result
		held = { request = request, signature = key }
		return {
			ok = false, code = "SaveUnavailable", uncertain = true,
			message = "Couldn't confirm with the server. Press again to retry.",
		}
	end

	-- Sends one request until the server gives a definitive answer or the
	-- retries run out. `uncertain` is true when an earlier send of this same
	-- request may already have committed.
	local function send(request: ActionRequest, key: string, uncertain: boolean): Result
		local attempt = 0
		local reconnected = false
		while true do
			local success, reply = pcall(transport.submit, request)
			local response = if success and isTable(reply) then reply :: any else nil
			local code = if response then response.code else nil
			if response and response.ok == true then
				held = nil
				adopt(response.snapshot)
				return { ok = true, receipt = response.receipt :: Receipt }
			elseif response and code == "ProfileLocked" then
				-- The lease lapsed. The server checks the lease before it looks up
				-- receipts, so this says nothing about an earlier attempt.
				if not uncertain then
					-- This request never reached a live session: nothing was spent.
					held = nil
					local opened = self:refresh()
					return {
						ok = false, code = code,
						message = if opened.ok then "The session was renewed. Check the item and try again." else opened.message,
					}
				end
				if reconnected then
					return hold(request, key)
				end
				reconnected = true
				local opened = self:refresh()
				local fresh = current
				if not opened.ok or not fresh then
					-- Keep the original request ID and action for the next press.
					return hold(request, key)
				end
				-- Same request ID and action under the new session. The server
				-- returns the committed receipt if the first attempt landed.
				request = table.clone(request)
				request.sessionId = fresh.sessionId
				continue
			elseif response and code ~= "SaveUnavailable" then
				-- A definitive answer about this request. Show what the server has now.
				held = nil
				adopt(response.snapshot)
				return { ok = false, code = code, message = response.message }
			end
			-- Uncertain: lost call, garbled reply, or the save could not be confirmed.
			uncertain = true
			attempt += 1
			if attempt > retries then
				return hold(request, key)
			end
			options.wait(BACKOFF_SECONDS[math.min(attempt, #BACKOFF_SECONDS)])
		end
	end

	function self.perform(_self: Client, action: Action): Result
		local snapshot = current
		if not snapshot then
			return { ok = false, code = "NotReady", message = "Open the station first." }
		end
		local key = signature(action)
		local kept = held
		if kept then
			-- An earlier action may have been charged. Settle it first, whatever
			-- was pressed, with its original request ID and action under the
			-- current session. Only a definitive reply clears it.
			local request = table.clone(kept.request)
			request.sessionId = snapshot.sessionId
			local result = send(request, kept.signature, true)
			if kept.signature ~= key and not result.uncertain then
				result.resolvedPending = true
			end
			return result
		end
		return send({
			sessionId = snapshot.sessionId,
			expectedRevision = snapshot.revision,
			requestId = options.makeId(),
			action = action,
		}, key, false)
	end

	return self
end

return Phase4Client
