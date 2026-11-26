--!strict

local Contract = require("../Contracts/SuccessionTypes")
local Combat = require("../Contracts/CombatTypes")
local Data = require("../Data/BloodlineTreeData")
local Tutorial = require("./TutorialProgress")

export type Lease = { sessionId: string, expiresAt: number }
export type Cause = "Voluntary" | "CastleWipe" | "OldAge"
export type Settlement = { cause: Cause, echoesAwarded: number }
export type Life = {
	id: Contract.LifeId,
	generation: number,
	age: number,
	baseNaturalDeathAge: number,
	recoveriesRemaining: number,
	awardedMilestones: { [string]: boolean },
	act5Vested: boolean,
	ledgerSettled: boolean,
	settlement: Settlement?,
	ageEvents: { [string]: boolean },
	castleWipes: { [string]: boolean },
	masteryEvents: { [string]: boolean },
}
type Mastery = { marks: number, targetMode: Contract.MasteryVariant, utilityVariant: Contract.MasteryVariant }
type SavedReceipt = { signature: string, receipt: Contract.Receipt }
export type Saved = {
	version: number,
	revision: number,
	life: Life,
	closedLives: { [Contract.LifeId]: Life },
	echoes: number,
	ranks: { [Contract.BloodlineNodeId]: number },
	unlockedHeirlooms: { [Contract.HeirloomId]: boolean },
	carriedHeirlooms: { Contract.HeirloomId },
	attunedHeirloom: Contract.HeirloomId?,
	mastery: { [Contract.KitId]: Mastery },
	receipts: { [string]: SavedReceipt },
}
export type Row = { [string]: unknown }

local MAX = 2 ^ 50
local OK: Combat.ActionLegality = { canUse = true }

local function integer(value: unknown, min: number, max: number): boolean
	return type(value) == "number" and value >= min and value <= max and value % 1 == 0
end

local function fields(value: unknown): Row?
	return if type(value) == "table" then value :: Row else nil
end

local function token(value: unknown): boolean
	return type(value) == "string" and #value <= 128 and string.match(value, "^[%w_:%-]+$") ~= nil
end

local function newLife(id: Contract.LifeId, generation: number, baseAge: number): Life
	return {
		id = id, generation = generation, age = 18, baseNaturalDeathAge = baseAge,
		recoveriesRemaining = Contract.MaxRecoveries, awardedMilestones = {}, act5Vested = false, ledgerSettled = false,
		ageEvents = {}, castleWipes = {}, masteryEvents = {},
	}
end

local function new(id: Contract.LifeId, baseAge: number): Saved
	local starter = Data.StarterHeirloomId
	return {
		version = 1, revision = 0, life = newLife(id, 1, baseAge), closedLives = {},
		echoes = 0, ranks = {}, unlockedHeirlooms = { [starter] = true },
		carriedHeirlooms = { starter }, attunedHeirloom = starter,
		mastery = {}, receipts = {},
	}
end

local function decodeRow(value: unknown): (Row?, Saved?, Lease?)
	local tutorial = Tutorial.decode(value)
	if not tutorial then return nil, nil, nil end
	local raw: Row = fields(value) or { version = tutorial.version, tutorialCompleted = tutorial.tutorialCompleted }
	local leaseFields = fields(raw.lineageLease)
	if raw.lineageLease ~= nil then
		if not leaseFields or not token(leaseFields.sessionId) or not integer(leaseFields.expiresAt, 0, MAX) then
			return nil, nil, nil
		end
	end
	if raw.lineage == nil then return raw, nil, leaseFields :: Lease? end
	local lineage = fields(raw.lineage)
	local life = if lineage then fields(lineage.life) else nil
	if not lineage or lineage.version ~= 1 or not integer(lineage.revision, 0, MAX) or not integer(lineage.echoes, 0, MAX)
		or not life or not token(life.id) or not integer(life.generation, 1, MAX)
		or not integer(life.age, 18, 95) or not integer(life.baseNaturalDeathAge, 75, 80)
		or not integer(life.recoveriesRemaining, 0, Contract.MaxRecoveries)
		or type(life.act5Vested) ~= "boolean" or type(life.ledgerSettled) ~= "boolean" then
		return nil, nil, nil
	end
	for _, key in { "ranks", "closedLives", "unlockedHeirlooms", "carriedHeirlooms", "mastery", "receipts" } do
		if type(lineage[key]) ~= "table" then return nil, nil, nil end
	end
	for _, key in { "awardedMilestones", "ageEvents", "castleWipes", "masteryEvents" } do
		if type(life[key]) ~= "table" then return nil, nil, nil end
	end
	return raw, lineage :: Saved, leaseFields :: Lease?
end

local function encodeRow(raw: Row, state: Saved, lease: Lease?): Row
	local updated = table.clone(raw)
	updated.lineage = state
	updated.lineageLease = lease
	return updated
end

local function actKey(act: number): string return "act:" .. tostring(act) end
local function challengeKey(id: string): string return "endgame:" .. id end

local function latestAct(life: Life): number
	for act = #Data.ActEchoes, 1, -1 do
		if life.awardedMilestones[actKey(act)] then return act end
	end
	return 0
end

local function naturalDeathAge(state: Saved): number
	local rank = state.ranks.bloodline_longevity or 0
	return state.life.baseNaturalDeathAge + (Data.LongevityYears[rank] or 0)
end

local function carryLimit(state: Saved): number
	return if (state.ranks.dual_heirloom_satchel or 0) > 0 then Contract.MaxHeirloomCarryLimit else Contract.BaseHeirloomCarryLimit
end

local function ledger(life: Life): Contract.RecoveryLedgerView
	local eligible, challenges = 0, 0
	for act, echoes in Data.ActEchoes do
		if life.awardedMilestones[actKey(act)] then eligible += echoes end
	end
	for id, echoes in Data.EndgameChallengeEchoes do
		if life.awardedMilestones[challengeKey(id)] then challenges += echoes end
	end
	local act = latestAct(life)
	local multiplier = Data.RetirementMultiplierPct[act]
	local canRetire = multiplier ~= nil and not life.ledgerSettled
	local terminalMultiplier = if life.act5Vested then Data.RetirementMultiplierPct[5] else 100
	return {
		recoveriesRemaining = life.recoveriesRemaining, maxRecoveries = Contract.MaxRecoveries,
		isFinalAttempt = life.recoveriesRemaining == 0 and not life.ledgerSettled, act5Vested = life.act5Vested,
		eligibleEchoes = eligible,
		retireNowEchoes = if multiplier then math.floor(eligible * multiplier / 100) + challenges else 0,
		terminalFallbackEchoes = math.floor(eligible * terminalMultiplier / 100) + challenges,
		canRetireNow = canRetire, ledgerSettled = life.ledgerSettled,
	}
end

local function settle(state: Saved, cause: Cause): Settlement
	assert(not state.life.ledgerSettled, "Life already settled")
	local quote = ledger(state.life)
	local award = if cause == "Voluntary" then quote.retireNowEchoes else quote.terminalFallbackEchoes
	local result: Settlement = { cause = cause, echoesAwarded = award }
	state.life.ledgerSettled = true
	state.life.settlement = result
	state.echoes += award
	return result
end

local function beginNextLife(state: Saved, id: string): boolean
	local life = state.life
	if not life.ledgerSettled or id == life.id or state.closedLives[id] or not token(id) or life.generation >= MAX then
		return false
	end
	state.closedLives = table.clone(state.closedLives)
	state.closedLives[life.id] = life
	state.life = newLife(id, life.generation + 1, life.baseNaturalDeathAge)
	return true
end

local function blocked(reason: string): Combat.ActionLegality
	return { canUse = false, disabledReason = reason }
end

local function snapshot(state: Saved, sessionId: string, atSafeHub: boolean): Contract.Snapshot
	local branches: { Contract.BloodlineBranchView } = {}
	for _, branch in Data.BranchOrder do
		local nodes: { Contract.BloodlineNodeView } = {}
		for _, id in Data.BranchNodes[branch] do
			local entry = Data.Nodes[id]
			local rank = state.ranks[id] or 0
			local nextCost = entry.costs[rank + 1]
			local legality = if not nextCost then blocked("Maximum rank reached.")
				elseif state.echoes < nextCost then blocked("Not enough Echoes.") else OK
			table.insert(nodes, {
				nodeId = id, label = entry.label, rank = rank, maxRank = #entry.costs, nextCostEchoes = nextCost,
				description = entry.description, legality = legality,
			})
		end
		table.insert(branches, { branchId = branch, nodes = nodes })
	end
	local heirlooms: { Contract.HeirloomId } = {}
	for _, entry in Data.Heirlooms do
		if state.unlockedHeirlooms[entry.id] then table.insert(heirlooms, entry.id) end
	end
	local mastery: { Contract.MasteryView } = {}
	local kits: { Contract.KitId } = {}
	for kitId in state.mastery do table.insert(kits, kitId) end
	table.sort(kits)
	for _, kitId in kits do
		local entry = state.mastery[kitId]
		table.insert(mastery, {
			kitId = kitId, marks = entry.marks, targetMode = entry.targetMode, utilityVariant = entry.utilityVariant,
			unlockedAltTarget = entry.marks >= Contract.MasteryAltTargetMarks,
			masteryTitleUnlocked = entry.marks >= Contract.MasteryTitleMarks,
		})
	end
	local elder = state.life.age >= Contract.ElderThreshold
	local recoveryLedger = ledger(state.life)
	recoveryLedger.canRetireNow = recoveryLedger.canRetireNow and atSafeHub
	return {
		sessionId = sessionId, revision = state.revision, lifeId = state.life.id, generation = state.life.generation,
		age = {
			currentAge = state.life.age, elderThreshold = Contract.ElderThreshold, naturalDeathAge = naturalDeathAge(state),
			isElder = elder, veteranComposureActive = elder and (state.ranks.veteran_composure or 0) > 0,
		},
		recoveryLedger = recoveryLedger, bloodlineTree = { echoesBalance = state.echoes, branches = branches },
		heirlooms = {
			catalog = Data.Heirlooms, unlockedIds = heirlooms, carriedIds = state.carriedHeirlooms,
			attunedId = state.attunedHeirloom, carryLimit = carryLimit(state),
			legality = if state.life.ledgerSettled then blocked("This life has ended.")
				elseif not atSafeHub then blocked("Return to the Safe Hub.") else OK,
		},
		mastery = mastery,
	}
end

local function copy(value: unknown): unknown
	if type(value) ~= "table" then return value end
	local detached: { [unknown]: unknown } = {}
	for k, v in value :: { [unknown]: unknown } do detached[k] = copy(v) end
	return detached
end

return table.freeze({
	MaxValue = MAX, integer = integer, fields = fields, token = token, new = new, decodeRow = decodeRow, encodeRow = encodeRow,
	actKey = actKey, challengeKey = challengeKey, latestAct = latestAct, naturalDeathAge = naturalDeathAge,
	carryLimit = carryLimit, ledger = ledger, settle = settle, beginNextLife = beginNextLife, snapshot = snapshot, copy = copy,
})
