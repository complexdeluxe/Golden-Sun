--!strict

local Succession = require("../Contracts/SuccessionTypes")

export type Node = { read label: string, read description: string, read costs: { number } }
local function node(label: string, description: string, costs: { number }): Node
	return table.freeze({ label = label, description = description, costs = table.freeze(costs) })
end

-- Branch membership and display order are shared with the lineage wire contract.
local nodes: { [Succession.BloodlineNodeId]: Node } = {
	family_purse = node("Family Purse", "Start with +50 / +120 / +220 Yen and +5 / +12 / +25 Salvage Shards.", { 20, 35, 55 }),
	early_conditioning = node("Early Conditioning", "+2 / +4 / +6 early stats at level 1, with no increase to the level 50 cap.", { 25, 45, 75 }),
	speedwagon_contacts = node("Speedwagon Contacts", "Rank 1 opens companion swapping and the Race Phial desk in Act 1. Rank 2 adds 15% to Hub Shop restock caps.", { 40, 75 }),
	quartermaster_dispatch = node("Quartermaster Dispatch", "Store up to 3 Expedition Tickets instead of 2.", { 60 }),
	bloodline_vault = node("Bloodline Vault Expansion", "Adds 4 / 8 / 14 permanent Vault item slots.", { 20, 40, 70 }),
	resonance_attunement = node("Resonance Attunement", "+10% / +20% Resonance Shards from eligible story clears.", { 35, 70 }),
	tactical_breadth = node("Tactical Breadth", "+1 move slot within the global cap of 7.", { 85 }),
	dual_heirloom_satchel = node("Dual Heirloom Satchel", "Carry 2 heirlooms and attune 1 at the Safe Hub.", { 90 }),
	bloodline_longevity = node("Bloodline Longevity", "Adds 5 / 10 / 15 years to natural lifespan. Elder still begins at 56.", { 20, 45, 80 }),
	veteran_composure = node("Veteran Composure", "Reduces the Elder HP penalty from 10% to 5% and removes the Max Stamina penalty.", { 65 }),
	chrome_resilience = node("Chrome Resilience", "Eligible races gain +5 / +10 tolerance; Full Borg strain thresholds rise to 132 / 136. Zero-tolerance races gain 1 year less Dungeon/retry aging at rank 1 and +5 Control Resist at rank 2.", { 35, 70 }),
}

local familyPurseBonuses = table.freeze({
	[0] = table.freeze({ yen = 0, salvageShards = 0 }),
	table.freeze({ yen = 50, salvageShards = 5 }),
	table.freeze({ yen = 120, salvageShards = 12 }),
	table.freeze({ yen = 220, salvageShards = 25 }),
})

local milestones = table.freeze({ 8, 10, 12, 20, 30 })
local multipliers: { [number]: number } = { [3] = 100, [4] = 110, [5] = 125 }
-- The spec names two examples. The other three slots have stable IDs for future encounter content.
local challenges: { [string]: number } = {
	two_boss_castle_gauntlet = 4,
	marked_modifier_clear = 4,
	endgame_challenge_3 = 4,
	endgame_challenge_4 = 4,
	endgame_challenge_5 = 4,
}

local starter = "pocket_watch"
local heirlooms: { Succession.HeirloomDisplay } = {
	{ id = starter, label = "George's Pocket Watch", description = "+5% Max HP and +1 starting Stamina while attuned.", iconKey = "PocketWatchIcon" },
	{ id = "zeppelis_checkered_hat", label = "Zeppeli's Checkered Hat", description = "+10% Hamon and Anti-Undead damage within the cap. The first eligible Hamon Breathing grants 1 bonus Stamina.", iconKey = "ZeppelisCheckeredHatIcon" },
	{ id = "caesars_headband", label = "Caesar's Headband", description = "Survive a lethal hit at 1 HP once per fight, sharing the lethal save with Emergency Override.", iconKey = "CaesarsHeadbandIcon" },
	{ id = "jotaros_torn_cap", label = "Jotaro's Torn Cap", description = "+6 Precision. The first landed 3/3 tagged High-Risk Heavy refunds 1 Stamina.", iconKey = "JotarosTornCapIcon" },
	{ id = "josukes_peace_pin", label = "Josuke's Peace Pin", description = "Consumable and companion heals restore 20% more HP and cleanse one minor removable debuff.", iconKey = "JosukesPeacePinIcon" },
	{ id = "brunos_zipper_brooch", label = "Bruno's Zipper Brooch", description = "Once per fight, redirect a telegraphed single-target intent to a living ally.", iconKey = "BrunosZipperBroochIcon" },
}
local heirloomsById: { [Succession.HeirloomId]: Succession.HeirloomDisplay } = {}
for _, heirloom in heirlooms do
	heirloomsById[heirloom.id] = heirloom
	table.freeze(heirloom)
end

return table.freeze({
	BranchOrder = Succession.BloodlineBranchOrder,
	BranchNodes = Succession.BloodlineNodeIds,
	Nodes = table.freeze(nodes),
	ActEchoes = milestones,
	FamilyPurseBonuses = familyPurseBonuses,
	RetirementMultiplierPct = table.freeze(multipliers),
	EndgameChallengeEchoes = table.freeze(challenges),
	LongevityYears = table.freeze({ 5, 10, 15 }),
	StarterHeirloomId = starter,
	Heirlooms = table.freeze(heirlooms),
	HeirloomsById = table.freeze(heirloomsById),
})
