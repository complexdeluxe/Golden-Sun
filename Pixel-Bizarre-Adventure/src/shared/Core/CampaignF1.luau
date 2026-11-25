--!strict

local Battle = require("./BlackSabbathBattle")
local Combat = require("../Contracts/CombatTypes")
local Map = require("../Contracts/MapTypes")
local Remote = require("../Contracts/RemoteContract")
local Save = require("../Contracts/SaveTypes")
local Starter = require("../Data/CampaignStarter")

export type Attempt = { battleId: string, mode: Map.RunMode }
type ResultOutcome = "Clear" | "Defeat" | "Retreat"
export type SavedResult = {
	attempt: Attempt,
	outcome: ResultOutcome,
	yen: number,
	levels: number,
}
export type Progress = { cleared: boolean, pending: Attempt?, result: SavedResult? }
export type Fight = {
	attempt: Attempt,
	origin: Save.Origin,
	battle: Battle.State,
	startingStock: { [Combat.BeltItemId]: number },
	retreated: boolean,
}
export type Command =
	{ kind: "Get", request: Remote.GetActBattleSnapshotRequest }
	| { kind: "Primary", request: Remote.ActBattlePrimaryRequest }
	| { kind: "Secondary", request: Remote.ActBattleSecondaryRequest }
	| { kind: "Check", request: Remote.ActBattleQteCheckRequest }
	| { kind: "Mode", request: Remote.ActBattleQteModeRequest }

local F1 = {}
local foes: { [Save.Origin]: Battle.FlagOpponent } = {
	Part1_Hamon = { id = "ogre_brawler", label = "Ogre Street Brawler", jabLabel = "Street Jab", heavyLabel = "Heavy Hook" },
	Part3_Stand = { id = "jail_thug", label = "Stand-Awakened Jail Thug", jabLabel = "Stand Jab", heavyLabel = "Cell Rush" },
}

local function decodeAttempt(value: unknown): Attempt?
	if type(value) ~= "table" then return nil end
	local raw = value :: { [string]: unknown }
	local id, mode = raw.battleId, raw.mode
	if type(id) ~= "string" or id == "" or (mode ~= "FirstClear" and mode ~= "Replay") then return nil end
	return { battleId = id, mode = mode }
end

function F1.decode(value: unknown): Progress?
	if value == nil then return { cleared = false } end
	if type(value) ~= "table" then return nil end
	local raw = value :: { [string]: unknown }
	if type(raw.cleared) ~= "boolean" then return nil end
	local pending = decodeAttempt(raw.pending)
	if raw.pending ~= nil and not pending then return nil end
	local result: SavedResult? = nil
	if raw.result ~= nil then
		if pending or type(raw.result) ~= "table" then return nil end
		local row = raw.result :: { [string]: unknown }
		local attempt = decodeAttempt(row.attempt)
		local outcome, yen, levels = row.outcome, row.yen, row.levels
		if not attempt or (outcome ~= "Clear" and outcome ~= "Defeat" and outcome ~= "Retreat")
			or type(yen) ~= "number" or not (yen >= 0 and yen < 2 ^ 53 and yen % 1 == 0)
			or type(levels) ~= "number" or (levels ~= 0 and levels ~= 1) then return nil end
		result = { attempt = attempt, outcome = outcome, yen = yen, levels = levels }
	end
	return { cleared = raw.cleared, pending = pending, result = result }
end

function F1.option(cleared: boolean): Map.PlayOption
	return {
		id = if cleared then "F1:replay" else "F1:first",
		label = if cleared then "Replay" else "Set out",
		mode = if cleared then "Replay" else "FirstClear",
		tier = 1,
		levelsOnClear = if cleared then 0 else 1,
		legality = { canUse = true },
	}
end

function F1.encounter(fight: Fight): Map.ActiveEncounter
	local attempt = fight.attempt
	return {
		encounterId = attempt.battleId .. ":F1", battleId = attempt.battleId, nodeId = "F1", mode = attempt.mode,
		stageTag = Starter.ActOneRoutes[fight.origin].stages.F1.tag,
	}
end

function F1.resultView(result: SavedResult): Map.EncounterResult
	return {
		encounterId = result.attempt.battleId .. ":F1", nodeId = "F1", mode = result.attempt.mode, outcome = result.outcome,
		rewards = { yen = result.yen, levels = result.levels, items = {} },
	}
end

function F1.new(
	attempt: Attempt, origin: Save.Origin, level: number, stock: { [Combat.BeltItemId]: number },
	physicalBonus: number, focus: number, random: () -> number, clock: () -> number
): Fight
	return {
		attempt = attempt, origin = origin, startingStock = stock, retreated = false,
		battle = Battle.newFlag(attempt.battleId, {
			level = level, opponent = foes[origin], stock = stock, physicalBonus = physicalBonus, focus = focus,
		}, random, clock),
	}
end

function F1.snapshot(fight: Fight): Map.ActBattleSnapshot
	local battle = fight.battle
	local snapshot = Battle.hudSnapshot(battle) :: Map.ActBattleSnapshot
	local stage = Starter.ActOneRoutes[fight.origin].stages.F1
	snapshot.encounterId = fight.attempt.battleId .. ":F1"
	snapshot.stageTag, snapshot.stageAssetKey = stage.tag, stage.assetKey
	snapshot.waveIndex, snapshot.waveCount = 1, 1
	snapshot.outcome = if fight.retreated then "Retreated" else battle.outcome
	snapshot.retreatLegality = Battle.retreatLegality(battle)
	return snapshot
end

function F1.result(fight: Fight): SavedResult?
	local outcome = fight.battle.outcome
	if not fight.retreated and outcome == "InProgress" then return nil end
	local first = fight.attempt.mode == "FirstClear"
	return {
		attempt = fight.attempt,
		outcome = if fight.retreated then "Retreat" elseif outcome == "Victory" then "Clear" else "Defeat",
		yen = if outcome == "Victory" then (if first then 12 else 6) else 0,
		levels = if outcome == "Victory" and first then 1 else 0,
	}
end

function F1.apply(fight: Fight, command: Command): Remote.ActBattleResponse
	local reply: Remote.SandboxResponse? = nil
	local battle = fight.battle
	if not F1.result(fight) then
		if command.kind == "Primary" then
			reply = Battle.submitPrimary(battle, command.request)
		elseif command.kind == "Secondary" then
			local request = command.request
			if request.kind == "Retreat" then
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
	local snapshot = F1.snapshot(fight)
	if reply and not reply.ok and snapshot.outcome == "InProgress" then
		return { ok = false, code = reply.code, message = reply.message, snapshot = snapshot }
	end
	return { ok = true, snapshot = snapshot }
end

function F1.nextDeadline(fight: Fight): number?
	return Battle.nextDeadline(fight.battle)
end

function F1.expireChecks(fight: Fight): boolean
	return Battle.expireChecks(fight.battle)
end

return table.freeze(F1)
