--!strict

local Contract = require("../Contracts/Phase4EconomyTypes")
local Combat = require("../Contracts/CombatTypes")
local Data = require("../Data/Phase4EconomyData")
local Economy = require("./Phase4Economy")
local Profile = require("./Phase4Profile")

type Site = Contract.CyberwareSite
type Install = Contract.CyberwareInstall
type Installs = { [Site]: Install }
type Routine = Contract.CyberwareRoutineId
type Saved = Profile.Saved
local clinic = Data.Cyberware
local sites: { Site } = { "HeadOptics", "Neural", "TorsoChassis", "Limbs", "HeartCore" }
-- Site routines unlock at the tiers listed in the Clinic spec.
local routineTiers: { [Site]: number } = { HeadOptics = 3, Neural = 5, TorsoChassis = 4, Limbs = 4, HeartCore = 5 }
local OK: Combat.ActionLegality = { canUse = true }

local function blocked(reason: string): Combat.ActionLegality
	return { canUse = false, disabledReason = reason }
end

local function install(site: Site, tier: number): Install
	local routine = (clinic.Sites :: { [Site]: { read activeId: string } })[site].activeId
	return { site = site, tier = tier, routineId = if tier >= routineTiers[site] then routine :: Routine else nil }
end

local function evaluate(state: Saved, installs: Installs)
	local loadout: { Economy.CyberwareInstall } = {}
	for _, implant in installs do
		table.insert(loadout, { site = implant.site, tier = implant.tier })
	end
	return Economy.evaluateCyberwareLoadout(state.race, false, loadout, state.goldenApple, state.bloodlineTolerance)
end

local function checkInstall(state: Saved, yen: number, site: Site, tier: number): (Contract.ErrorCode?, string?)
	if state.act < clinic.UnlockAct then return "IllegalAction", "The Clinic unlocks in Act 2." end
	local previous = state.installs[site]
	if previous and previous.tier == tier then return "IllegalAction", "This implant is already installed." end
	local proposed = table.clone(state.installs)
	proposed[site] = install(site, tier)
	local assessment = evaluate(state, proposed)
	if not assessment.ok then return "IllegalAction", assessment.error end
	local cost = clinic.Tiers[tier]
	if yen < cost.yen or state.salvageShards < cost.shards then
		return "InsufficientResources", "Not enough Yen or salvage shards."
	end
	return nil, nil
end

local function view(state: Saved, yen: number): Contract.ClinicView
	local open = state.act >= clinic.UnlockAct
	local assessment = evaluate(state, state.installs)
	local race = (clinic.RacialTolerance :: { [string]: { read maxSites: number, read eligible: boolean } })[state.race]
	local siteViews: { Contract.CyberwareSlotView } = {}
	for _, site in sites do
		local offers: { Contract.CyberwareInstallOffer } = {}
		for tier, price in clinic.Tiers do
			local _, reason = checkInstall(state, yen, site, tier)
			table.insert(offers, {
				tier = tier, toleranceCost = price.tolerance, routineId = install(site, tier).routineId,
				cost = { yen = price.yen, salvageShards = price.shards, materials = 0, holyWater = 0 },
				legality = if reason then blocked(reason) else OK,
			})
		end
		table.insert(siteViews, {
			site = site, installed = state.installs[site], offers = offers,
			legality = if open then OK else blocked("The Clinic unlocks in Act 2."),
		})
	end
	return {
		legality = if open then OK else blocked("The Clinic unlocks in Act 2."),
		sites = siteViews, activeRoutineLimit = clinic.MaxEquippedHighTierActives, equippedRoutines = state.equippedRoutines,
		tolerance = {
			maxTolerance = assessment.maxTolerance, usedTolerance = assessment.usedTolerance,
			maxSites = if race.eligible then race.maxSites elseif state.goldenApple then clinic.GoldenAppleMinUnlockedSites else 0,
			strainThreshold = if state.race == "FullBorg"
				then clinic.StrainThresholdBase + math.floor(state.bloodlineTolerance * 0.8 + 0.0001) else nil,
			cyberStrainActive = assessment.cyberStrainActive,
			controlResistPenaltyPp = assessment.controlResistPenaltyPp, extraAgingYears = assessment.extraAgingYears,
		},
	}
end

local function hasRoutine(installs: Installs, id: Routine): boolean
	for _, implant in installs do
		if implant.routineId == id then return true end
	end
	return false
end

local function replace(state: Saved, site: Site, replacement: Install?)
	state.installs = table.clone(state.installs)
	state.installs[site] = replacement
	local routines: { Routine } = {}
	for _, routine in state.equippedRoutines do
		if hasRoutine(state.installs, routine) then table.insert(routines, routine) end
	end
	state.equippedRoutines = routines
end

local function validRoutines(state: Saved, routines: { Routine }): boolean
	if #routines > clinic.MaxEquippedHighTierActives then return false end
	local seen: { [Routine]: boolean } = {}
	for _, id in routines do
		if seen[id] or not hasRoutine(state.installs, id) then return false end
		seen[id] = true
	end
	return true
end

return table.freeze({
	view = view, install = install, checkInstall = checkInstall, replace = replace, validRoutines = validRoutines,
})
