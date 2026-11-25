--!strict

local Battle = require("./BlackSabbathBattle")
local Combat = require("../Contracts/CombatTypes")
local Map = require("../Contracts/MapTypes")
local Remote = require("../Contracts/RemoteContract")
local Save = require("../Contracts/SaveTypes")
local Starter = require("../Data/CampaignStarter")
local Encounters = require("../Data/ActOneEncounters")

export type Attempt = { battleId: string, nodeId: Map.NodeId, mode: Map.RunMode }
type ResultOutcome = "Clear" | "Defeat" | "Retreat"
export type SavedResult = {
	attempt: Attempt,
	outcome: ResultOutcome,
	yen: number,
	levels: number,
}
export type Progress = { clears: { [Map.NodeId]: boolean }, recruited: boolean, pending: Attempt?, result: SavedResult? }
export type Fight = {
	attempt: Attempt,
	origin: Save.Origin,
	battle: Battle.State,
	startingStock: { [Combat.BeltItemId]: number },
	waves: { Battle.ActOpponent },
	waveIndex: number,
	retreated: boolean,
}
export type Command =
	{ kind: "Get", request: Remote.GetActBattleSnapshotRequest }
	| { kind: "Primary", request: Remote.ActBattlePrimaryRequest }
	| { kind: "Secondary", request: Remote.ActBattleSecondaryRequest }
	| { kind: "Check", request: Remote.ActBattleQteCheckRequest }
	| { kind: "Mode", request: Remote.ActBattleQteModeRequest }

local ActBattle = {}

local function decodeAttempt(value: unknown, legacy: boolean): Attempt?
	if type(value) ~= "table" then return nil end
	local raw = value :: { [string]: unknown }
	local id, mode = raw.battleId, raw.mode
	local nodeId = if legacy then "F1" else raw.nodeId
	if type(id) ~= "string" or id == "" or (mode ~= "FirstClear" and mode ~= "Replay") then return nil end
	if nodeId ~= "F1" and nodeId ~= "F2" and nodeId ~= "D1" then return nil end
	return { battleId = id, nodeId = nodeId, mode = mode }
end

function ActBattle.decode(value: unknown, legacyF1: unknown): Progress?
	local legacy = value == nil and legacyF1 ~= nil
	local source = if legacy then legacyF1 else value
	local clears: { [Map.NodeId]: boolean } = {}
	if source == nil then return { clears = clears, recruited = false } end
	if type(source) ~= "table" then return nil end
	local raw = source :: { [string]: unknown }
	local recruited = false
	if legacy then
		if type(raw.cleared) ~= "boolean" then return nil end
		if raw.cleared then clears.F1 = true end
	else
		if type(raw.clears) ~= "table" or type(raw.recruited) ~= "boolean" then return nil end
		for key, cleared in raw.clears :: { [string]: unknown } do
			if (key ~= "F1" and key ~= "F2" and key ~= "D1") or cleared ~= true then return nil end
			clears[key :: Map.NodeId] = true
		end
		recruited = raw.recruited
		if (clears.F2 and not clears.F1) or (clears.D1 and not clears.F2) or (recruited and not clears.D1) then return nil end
	end
	local pending = decodeAttempt(raw.pending, legacy)
	if raw.pending ~= nil and not pending then return nil end
	local result: SavedResult? = nil
	if raw.result ~= nil then
		if pending or type(raw.result) ~= "table" then return nil end
		local row = raw.result :: { [string]: unknown }
		local attempt = decodeAttempt(row.attempt, legacy)
		local outcome, yen, levels = row.outcome, row.yen, row.levels
		if not attempt or (outcome ~= "Clear" and outcome ~= "Defeat" and outcome ~= "Retreat")
			or type(yen) ~= "number" or not (yen >= 0 and yen < 2 ^ 53 and yen % 1 == 0)
			or type(levels) ~= "number" or (levels ~= 0 and levels ~= 1) then return nil end
		result = { attempt = attempt, outcome = outcome, yen = yen, levels = levels }
	end
	return { clears = clears, recruited = recruited, pending = pending, result = result }
end

function ActBattle.option(nodeId: Map.NodeId, cleared: boolean): Map.PlayOption
	return {
		id = nodeId .. (if cleared then ":replay" else ":first"),
		label = if cleared then "Replay" else "Set out",
		mode = if cleared then "Replay" else "FirstClear",
		tier = 1,
		levelsOnClear = if cleared then 0 else 1,
		legality = { canUse = true },
	}
end

function ActBattle.companion(origin: Save.Origin?, progress: Progress): Map.CompanionView
	if not origin or not progress.clears.D1 then return { state = "Locked" } end
	local recruit = Encounters.Routes[origin].recruit
	if progress.recruited then
		return {
			state = "Recruited", companionId = recruit.companionId,
			label = recruit.label, description = recruit.description, spriteKey = recruit.spriteKey,
		}
	end
	return {
		state = "Offered", offerId = "D1:recruit:" .. recruit.companionId, companionId = recruit.companionId,
		label = recruit.label, description = recruit.description, spriteKey = recruit.spriteKey, legality = { canUse = true },
	}
end

local function encounterId(attempt: Attempt): string
	return attempt.battleId .. ":" .. attempt.nodeId
end

function ActBattle.encounter(fight: Fight): Map.ActiveEncounter
	local attempt = fight.attempt
	return {
		encounterId = encounterId(attempt), battleId = attempt.battleId, nodeId = attempt.nodeId, mode = attempt.mode,
		stageTag = Starter.ActOneRoutes[fight.origin].stages[attempt.nodeId].tag,
	}
end

function ActBattle.resultView(result: SavedResult): Map.EncounterResult
	return {
		encounterId = encounterId(result.attempt), nodeId = result.attempt.nodeId, mode = result.attempt.mode, outcome = result.outcome,
		rewards = { yen = result.yen, levels = result.levels, items = {} },
	}
end

function ActBattle.new(
	attempt: Attempt, origin: Save.Origin, level: number, stock: { [Combat.BeltItemId]: number },
	physicalBonus: number, focus: number, recruited: boolean, random: () -> number, clock: () -> number
): Fight
	local route = Encounters.Routes[origin]
	local waves = route.waves[attempt.nodeId]
	-- The recruit is the D1 finale opponent. On a replay they take that side of the spar.
	local companion = if recruited and attempt.nodeId ~= "D1" then route.recruit else nil
	return {
		attempt = attempt, origin = origin, startingStock = stock, retreated = false, waves = waves, waveIndex = 1,
		battle = Battle.newActEncounter(attempt.battleId, {
			level = level, opponent = waves[1], stock = stock, physicalBonus = physicalBonus, focus = focus, companion = companion,
		}, random, clock),
	}
end

function ActBattle.snapshot(fight: Fight): Map.ActBattleSnapshot
	local battle = fight.battle
	local snapshot = Battle.hudSnapshot(battle) :: Map.ActBattleSnapshot
	local stage = Starter.ActOneRoutes[fight.origin].stages[fight.attempt.nodeId]
	snapshot.encounterId = encounterId(fight.attempt)
	snapshot.stageTag, snapshot.stageAssetKey = stage.tag, stage.assetKey
	snapshot.waveIndex, snapshot.waveCount = fight.waveIndex, #fight.waves
	snapshot.outcome = if fight.retreated then "Retreated" else battle.outcome
	snapshot.retreatLegality = if fight.attempt.nodeId == "D1"
		then { canUse = false :: false, disabledReason = "Retreat is available in Flag fights." } else Battle.retreatLegality(battle)
	return snapshot
end

function ActBattle.result(fight: Fight): SavedResult?
	local outcome = fight.battle.outcome
	if not fight.retreated and outcome == "InProgress" then return nil end
	local first = fight.attempt.mode == "FirstClear"
	local yen = Encounters.FirstClearYen[fight.attempt.nodeId]
	return {
		attempt = fight.attempt,
		outcome = if fight.retreated then "Retreat" elseif outcome == "Victory" then "Clear" else "Defeat",
		yen = if outcome == "Victory" then (if first then yen else math.floor(yen / 2)) else 0,
		levels = if outcome == "Victory" and first then 1 else 0,
	}
end

local function advanceWave(fight: Fight)
	if fight.battle.outcome == "Victory" and fight.waveIndex < #fight.waves then
		fight.waveIndex += 1
		Battle.startNextWave(fight.battle, fight.waves[fight.waveIndex], fight.waveIndex)
	end
end

function ActBattle.apply(fight: Fight, command: Command): Remote.ActBattleResponse
	local reply: Remote.SandboxResponse? = nil
	local battle = fight.battle
	if not ActBattle.result(fight) then
		if command.kind == "Primary" then
			reply = Battle.submitPrimary(battle, command.request)
		elseif command.kind == "Secondary" then
			local request = command.request
			if request.kind == "Retreat" then
				if fight.attempt.nodeId == "D1" then
					return { ok = false, code = "IllegalAction", message = "Retreat is available in Flag fights.", snapshot = ActBattle.snapshot(fight) }
				end
				reply, fight.retreated = Battle.attemptFlagRetreat(battle, request, request.actorId)
			else
				reply = Battle.submitSecondary(battle, request)
			end
		elseif command.kind == "Check" then
			reply = Battle.submitCheck(battle, command.request)
		elseif command.kind == "Mode" then
			reply = Battle.setQteMode(battle, command.request)
		end
	end
	advanceWave(fight)
	local snapshot = ActBattle.snapshot(fight)
	if reply and not reply.ok and snapshot.outcome == "InProgress" then
		return { ok = false, code = reply.code, message = reply.message, snapshot = snapshot }
	end
	return { ok = true, snapshot = snapshot }
end

function ActBattle.nextDeadline(fight: Fight): number?
	return Battle.nextDeadline(fight.battle)
end

function ActBattle.expireChecks(fight: Fight): boolean
	local changed = Battle.expireChecks(fight.battle)
	if changed then advanceWave(fight) end
	return changed
end

return table.freeze(ActBattle)
