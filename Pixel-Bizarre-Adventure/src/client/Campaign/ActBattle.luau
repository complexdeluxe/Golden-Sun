--!strict
-- Runs one Act fight on the compact combat HUD (CombatHudV2), for the
-- campaign's ActEncounter scene.
--
--   * Opens on the encounter's battleId and fetches GetActBattleSnapshot.
--   * Takes snapshots only for this battle and encounter, newest revision wins.
--   * Sends Primary, Secondary (belt, tactic, redirect, Skip Turn, Retreat), QTE
--     checks and QTE mode to ActBattleRemotes. The server advances turns.
--   * A reply may carry the campaign snapshot. It goes to the campaign
--     controller, which closes this fight once the scene leaves ActEncounter.
--   * A lost reply resyncs with GetActBattleSnapshot, then the campaign.
--   * Once the fight is over and Results have not arrived: SAVING RESULTS...,
--     a few campaign refreshes, then RETRY (another campaign refresh).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MapTypes = require(ReplicatedStorage.Shared.Contracts.MapTypes)
local RemoteContract = require(ReplicatedStorage.Shared.Contracts.RemoteContract)
local AppearanceTypes = require(ReplicatedStorage.Shared.Contracts.CharacterAppearanceTypes)
local HubTypes = require(ReplicatedStorage.Shared.Contracts.HubTypes)
local CombatHudV2 = require(script.Parent.Parent.Battle.CombatHudV2)
local ActBattleConnection = require(script.Parent.ActBattleConnection)

type Snapshot = MapTypes.ActBattleSnapshot
type Response = RemoteContract.ActBattleResponse

local START_ATTEMPTS = 5
local START_RETRY_SECONDS = 2
-- Refreshes while Results save, then RETRY.
local SETTLE_WAITS = { 1, 2, 4 }
-- How long the VICTORY / DEFEAT / RETREATED banner stays before Results.
local OUTCOME_BEAT_SECONDS = 1.5
local SAVING_NOTE_DELAY = 0.5

export type Options = {
	appearance: AppearanceTypes.Appearance?,
	-- Hands a campaign snapshot from a battle reply to the campaign controller.
	acceptCampaign: (snapshot: HubTypes.CampaignSnapshot) -> (),
	-- Calls GetCampaignSnapshot and applies it.
	refreshCampaign: () -> (),
}

export type ActBattle = {
	battleId: string,
	-- Waits for the outcome beat (if the fight just ended), then removes the HUD.
	close: (self: ActBattle) -> (),
}

local ActBattle = {}

function ActBattle.open(
	screenGui: ScreenGui,
	connection: ActBattleConnection.Connection,
	encounter: MapTypes.ActiveEncounter,
	options: Options
): ActBattle
	local battleId = encounter.battleId
	local snapshot: Snapshot? = nil
	local busy = false
	local closed = false
	local endedAt: number? = nil
	local settling = false
	local view: CombatHudV2.CombatHudV2
	local stopListening: (() -> ())? = nil

	local function terminal(current: Snapshot): boolean
		return current.outcome ~= "InProgress"
	end

	local settle: () -> ()

	local function outcomeLine(current: Snapshot): string
		if current.outcome == "Victory" then
			for _, actor in current.actors do
				if actor.team == "Enemy" then
					return `{actor.displayName} is down.`
				end
			end
			return "The fight is won."
		elseif current.outcome == "Retreated" then
			return "You fall back. No clear rewards."
		end
		return "The party falls. No clear rewards."
	end

	local function accept(incoming: Snapshot)
		if closed or incoming.battleId ~= battleId then
			return
		end
		if incoming.encounterId ~= nil and incoming.encounterId ~= encounter.encounterId then
			return
		end
		local current = snapshot
		if current and incoming.revision < current.revision then
			return
		end
		snapshot = incoming
		view:render(incoming :: any)
		if terminal(incoming) and not endedAt then
			endedAt = os.clock()
			view:setOutcomeNote(outcomeLine(incoming), nil)
			task.defer(settle)
		end
	end

	local function resync()
		-- The reply was lost: ask for the fight, then for the campaign.
		local response = connection.getSnapshot(battleId)
		if closed then
			return
		end
		if (response :: any).lost then
			options.refreshCampaign()
			return
		end
		local campaign = (response :: any).campaignSnapshot
		if response.ok == true then
			accept(response.snapshot)
		elseif (response :: any).snapshot then
			accept((response :: any).snapshot)
		end
		if campaign then
			options.acceptCampaign(campaign)
		elseif response.ok ~= true and not (response :: any).snapshot then
			options.refreshCampaign()
		end
	end

	local function apply(response: Response)
		if closed then
			return
		end
		local raw = response :: any
		if raw.lost then
			view:toast(raw.message)
			resync()
			return
		end
		if response.ok == true then
			accept(response.snapshot)
		else
			view:toast(raw.message)
			if raw.snapshot then
				accept(raw.snapshot)
			end
		end
		if raw.campaignSnapshot then
			options.acceptCampaign(raw.campaignSnapshot)
		elseif response.ok ~= true and raw.snapshot == nil then
			-- No fight came back (for example ProfileLocked or BattleNotFound).
			options.refreshCampaign()
		end
	end

	local function request(work: (current: Snapshot) -> Response)
		local current = snapshot
		if busy or closed or not current then
			return
		end
		busy = true
		view:setBusy(true)
		local response = work(current)
		busy = false
		if not closed then
			view:setBusy(false)
		end
		apply(response)
	end

	local function actingId(current: Snapshot): string
		return current.activeActorId or current.playerActorId
	end

	function settle()
		if settling then
			return
		end
		settling = true
		-- Results usually come with the final reply; only say SAVING if they don't.
		task.wait(SAVING_NOTE_DELAY)
		if closed then
			return
		end
		view:setOutcomeNote("SAVING RESULTS...", nil)
		for _, seconds in SETTLE_WAITS do
			task.wait(seconds)
			if closed then
				return
			end
			options.refreshCampaign()
			if closed then
				return
			end
		end
		settling = false
		view:setOutcomeNote("RESULTS NOT SAVED YET", "RETRY")
	end

	view = CombatHudV2.new(screenGui, {
		onPrimary = function(option, targetId)
			request(function(current)
				return connection.submitPrimary({
					battleId = current.battleId,
					expectedRevision = current.revision,
					actorId = actingId(current),
					slot = option.slot,
					moveId = option.moveId,
					targetId = targetId,
				})
			end)
		end,
		onBeltItem = function(itemId, targetId)
			request(function(current)
				return connection.submitSecondary({
					battleId = current.battleId,
					expectedRevision = current.revision,
					kind = "UseBeltItem",
					actorId = actingId(current),
					itemId = itemId,
					targetId = targetId,
				})
			end)
		end,
		onTactic = function(mode)
			request(function(current)
				return connection.submitSecondary({
					battleId = current.battleId,
					expectedRevision = current.revision,
					kind = "SetCompanionTactic",
					actorId = actingId(current),
					tacticMode = mode,
				})
			end)
		end,
		onRedirect = function(intentId, recipientId)
			request(function(current)
				return connection.submitSecondary({
					battleId = current.battleId,
					expectedRevision = current.revision,
					kind = "CompanionGuardRedirect",
					actorId = actingId(current),
					intentId = intentId,
					recipientId = recipientId,
				})
			end)
		end,
		onEndTurn = function()
			-- SKIP TURN for a fighter with no usable Primary.
			request(function(current)
				return connection.submitSecondary({
					battleId = current.battleId,
					expectedRevision = current.revision,
					kind = "EndTurn",
					actorId = actingId(current),
				})
			end)
		end,
		onRetreat = function()
			request(function(current)
				return connection.submitSecondary({
					battleId = current.battleId,
					expectedRevision = current.revision,
					kind = "Retreat",
					actorId = actingId(current),
				} :: any)
			end)
		end,
		onQteMode = function(mode)
			request(function(current)
				return connection.setQteMode({
					battleId = current.battleId,
					expectedRevision = current.revision,
					qteMode = mode,
				})
			end)
		end,
		onQteInput = function(challengeId, checkIndex, input)
			request(function(current)
				return connection.submitQteCheck({
					battleId = current.battleId,
					challengeId = challengeId,
					checkIndex = checkIndex,
					input = input,
				})
			end)
		end,
		onRestart = function()
			-- RETRY on the outcome banner: ask the campaign again.
			if busy or closed or settling then
				return
			end
			view:setOutcomeNote("SAVING RESULTS...", nil)
			busy = true
			options.refreshCampaign()
			busy = false
			if not closed then
				view:setOutcomeNote("RESULTS NOT SAVED YET", "RETRY")
				view:toast("Results are still saving. Try again in a moment.")
			end
		end,
		playerAppearance = options.appearance,
	})

	stopListening = connection.onSnapshotChanged(accept)

	task.spawn(function()
		busy = true
		view:setBusy(true)
		for attempt = 1, START_ATTEMPTS do
			local response = connection.getSnapshot(battleId)
			if closed then
				return
			end
			local raw = response :: any
			if response.ok == true or raw.snapshot then
				busy = false
				view:setBusy(false)
				apply(response)
				return
			end
			if raw.campaignSnapshot then
				busy = false
				options.acceptCampaign(raw.campaignSnapshot)
				return
			end
			if not raw.lost then
				view:toast(raw.message)
			end
			if attempt < START_ATTEMPTS then
				task.wait(START_RETRY_SECONDS)
			end
		end
		busy = false
		if not closed then
			view:setBusy(false)
			options.refreshCampaign()
		end
	end)

	local self = { battleId = battleId } :: ActBattle

	function self.close(_self: ActBattle)
		if closed then
			return
		end
		closed = true
		local stop = stopListening
		if stop then
			stop()
		end
		local ended = endedAt
		if ended then
			local remaining = OUTCOME_BEAT_SECONDS - (os.clock() - ended)
			if remaining > 0 then
				task.wait(remaining)
			end
		end
		view:destroy()
	end

	return self
end

return ActBattle
