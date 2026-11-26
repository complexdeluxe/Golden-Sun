--!strict

local Assets = require("../Contracts/AssetManifest")

export type RaceId = "Human" | "Superhuman" | "Cyborg" | "Undead" | "Vampire" | "PillarMan" | "UltimateLifeform" | "Alien" | "Rock"
export type TechniqueId = "Hamon" | "Boxing" | "FullBorg" | "StandMastery" | "PassioneHitman"
export type Race = {
	read label: string, read baseTolerance: number, read maxImplants: number, read standCompatible: boolean,
	read naturalLifespanMin: number?, read naturalLifespanMax: number?, read ageless: boolean,
}

local function race(label: string, tolerance: number, sites: number, standCompatible: boolean, minAge: number?, maxAge: number?): Race
	return table.freeze({
		label = label, baseTolerance = tolerance, maxImplants = sites, standCompatible = standCompatible,
		naturalLifespanMin = minAge, naturalLifespanMax = maxAge, ageless = minAge == nil,
	})
end

local races: { [RaceId]: Race } = {
	Human = race("Human", 40, 5, true, 75, 80),
	Superhuman = race("Superhuman", 40, 2, true, 80, 80),
	Cyborg = race("Cyborg", 120, 5, true, 95, 95),
	Undead = race("Undead", 0, 0, true, 150, 150),
	Vampire = race("Vampire", 0, 0, true, 400, 400),
	PillarMan = race("Pillar Man", 0, 0, true),
	UltimateLifeform = race("Ultimate Lifeform", 0, 0, true),
	Alien = race("Alien", 0, 0, false),
	Rock = race("Rock", 0, 0, true),
}
local raceOrder: { RaceId } = { "Human", "Superhuman", "Cyborg", "Undead", "Vampire", "PillarMan", "UltimateLifeform", "Alien", "Rock" }
local techniqueOrder: { TechniqueId } = { "Hamon", "Boxing", "FullBorg", "StandMastery", "PassioneHitman" }
local techniques: { [TechniqueId]: string } = {
	Hamon = "Hamon", Boxing = "Boxing", FullBorg = "Full 'Borg", StandMastery = "Stand Mastery", PassioneHitman = "Passione Hitman",
}

type Compatibility = { [TechniqueId]: boolean }
local function compatible(hamon: boolean, boxing: boolean, fullBorg: boolean, standMastery: boolean, hitman: boolean): Compatibility
	local row: Compatibility = { Hamon = hamon, Boxing = boxing, FullBorg = fullBorg, StandMastery = standMastery, PassioneHitman = hitman }
	return table.freeze(row)
end
local matrix: { [RaceId]: Compatibility } = {
	Human = compatible(true, true, false, true, true),
	Superhuman = compatible(true, true, false, true, true),
	Cyborg = compatible(true, true, true, true, true),
	Undead = compatible(false, true, false, true, true),
	Vampire = compatible(false, true, false, true, true),
	PillarMan = compatible(false, true, false, true, true),
	UltimateLifeform = compatible(true, true, false, true, true),
	Alien = compatible(true, true, false, false, true),
	Rock = compatible(true, true, false, true, true),
}

export type CatalystChoice = { read branchId: string, read catalystId: string }
export type EvolutionCriteria = {
	read fromRace: RaceId?, read fromTechnique: string?, read fromStand: string?,
	read minActTier: number?, read storyPart: number?, read clinicUnlocked: boolean?,
	read minHumanStyleMarks: number?, read maxImplants: number?, read minImplantedSites: number?,
	read minUsedTolerance: number?, read toleranceOfferBand: { number }?,
	read catalystId: string?, read branchCatalysts: { CatalystChoice }?, read defaultBranchWeights: { number }?,
	read requiresAuthoredOffer: boolean?,
}
type EvolutionKind = "Race" | "Technique" | "Stand"
export type Evolution = {
	read id: string, read kind: EvolutionKind, read resultId: string,
	read trigger: "HubEvolutionEncounter", read autoTrigger: false, read requiresConfirmation: true,
	read criteria: EvolutionCriteria,
}
local function evolution(id: string, kind: EvolutionKind, result: string, criteria: EvolutionCriteria): Evolution
	return table.freeze({
		id = id, kind = kind, resultId = result,
		trigger = "HubEvolutionEncounter" :: "HubEvolutionEncounter",
		autoTrigger = false :: false, requiresConfirmation = true :: true, criteria = table.freeze(criteria),
	})
end

local function branch(id: string, catalyst: string): CatalystChoice
	return table.freeze({ branchId = id, catalystId = catalyst })
end
local pillarBranches: { CatalystChoice } = {
	branch("wamuu", "wamuus-horn"), branch("esidisi", "esidisis-flame-core"), branch("kars", "karss-blade"),
}
local evolutions: { Evolution } = {
	evolution("human_to_superhuman", "Race", "Superhuman", { fromRace = "Human", minHumanStyleMarks = 5, maxImplants = 2 }),
	-- The spec gives a 30–35 offer band. Use its lower bound for eligibility; 35 is not a maximum allowed load.
	evolution("human_to_cyborg", "Race", "Cyborg", {
		fromRace = "Human", minActTier = 2, clinicUnlocked = true, minImplantedSites = 2,
		minUsedTolerance = 30, toleranceOfferBand = table.freeze({ 30, 35 }),
	}),
	evolution("human_to_undead", "Race", "Undead", { fromRace = "Human", catalystId = "vampire-blood" }),
	evolution("undead_to_vampire", "Race", "Vampire", { fromRace = "Undead", catalystId = "stone-mask" }),
	evolution("vampire_to_pillar_man", "Race", "PillarMan", {
		fromRace = "Vampire", storyPart = 2, requiresAuthoredOffer = true,
		branchCatalysts = table.freeze(pillarBranches), defaultBranchWeights = table.freeze({ 33, 33, 33 }),
	}),
	evolution("pillar_man_to_ultimate_lifeform", "Race", "UltimateLifeform", { fromRace = "PillarMan", catalystId = "red-stone-of-aja" }),
	evolution("advanced_hamon", "Technique", "AdvancedHamon", { fromTechnique = "Hamon", storyPart = 2, requiresAuthoredOffer = true }),
	evolution("mastered_hamon", "Technique", "MasteredHamon", { fromTechnique = "AdvancedHamon", storyPart = 2, requiresAuthoredOffer = true }),
	evolution("the_world_over_heaven", "Stand", "the_world_over_heaven", { fromStand = "the_world", catalystId = "dios-diary", requiresAuthoredOffer = true }),
	evolution("bites_the_dust", "Stand", "kq_btd", { fromStand = "killer_queen", storyPart = 4, requiresAuthoredOffer = true }),
	evolution("gold_experience_requiem", "Stand", "gold_experience_requiem", { fromStand = "gold_experience", catalystId = "requiem-arrow", storyPart = 5, requiresAuthoredOffer = true }),
	evolution("chariot_requiem", "Stand", "chariot_requiem", { fromStand = "silver_chariot", catalystId = "requiem-arrow", storyPart = 5, requiresAuthoredOffer = true }),
}

export type StandGrade = "E" | "D" | "C" | "B" | "A" | "A+" | "∞"
export type GradeConversion = {
	read powerPct: number, read speedTieBreak: number, read precisionPp: number,
	read durabilityGuardPp: number, read potentialResolvePerNaturalTurn: number, read maxAuthoredBehaviorsPerAxis: number,
}
local function grade(power: number, axis: number, potential: number, signature: number): GradeConversion
	return table.freeze({
		powerPct = power, speedTieBreak = axis, precisionPp = axis, durabilityGuardPp = axis,
		potentialResolvePerNaturalTurn = potential, maxAuthoredBehaviorsPerAxis = signature,
	})
end
local grades: { [StandGrade]: GradeConversion } = {
	E = grade(0, 0, 0, 0), D = grade(1, 1, 0, 0), C = grade(2, 2, 1, 0),
	B = grade(4, 3, 1, 0), A = grade(6, 4, 2, 0), ["A+"] = grade(8, 5, 2, 0), ["∞"] = grade(8, 5, 2, 1),
}

type StandGrades = {
	read Power: StandGrade, read Speed: StandGrade, read Precision: StandGrade, read Durability: StandGrade, read Potential: StandGrade,
}
export type Stand = {
	read id: string, read storyPart: number, read name: string, read sourcePool: string, read bulkUpCandidate: boolean,
	read arrowCore: boolean, read bossDisc: boolean, read grades: StandGrades, read sheetKey: Assets.AssetKey?,
}
local function stand(id: string, storyPart: number, name: string, pool: string, bulk: boolean,
	power: StandGrade, speed: StandGrade, precision: StandGrade, durability: StandGrade, potential: StandGrade, sheet: Assets.AssetKey?
): Stand
	local axisGrades: StandGrades = table.freeze({
		Power = power, Speed = speed, Precision = precision, Durability = durability, Potential = potential,
	})
	return table.freeze({
		id = id, storyPart = storyPart, name = name, sourcePool = pool, bulkUpCandidate = bulk,
		arrowCore = string.find(pool, "Arrow Core", 1, true) ~= nil,
		bossDisc = string.find(pool, "Disc", 1, true) ~= nil, grades = axisGrades, sheetKey = sheet,
	})
end

-- Canonical grades and acquisition notes from turn_based_stand_kits.json.
-- Retain story-only and bulk-up rows for reference without marking them as general Arrow or Disc drops.
local stands: { Stand } = {
	stand("silver_chariot", 3, "Silver Chariot", "Arrow Core", false, "C", "A", "B", "B", "C", "SilverChariotSheet"),
	stand("hierophant_green", 3, "Hierophant Green", "Arrow Core / F2 Recruit", false, "C", "B", "C", "B", "D", "HierophantGreenSheet"),
	stand("magicians_red", 3, "Magician's Red", "Arrow Core / D1 Recruit", false, "B", "B", "C", "B", "D", "MagiciansRedSheet"),
	stand("hermit_purple", 3, "Hermit Purple", "Arrow Core", false, "D", "C", "B", "A", "E"),
	stand("the_fool", 3, "The Fool", "Arrow Core", false, "B", "C", "D", "C", "C"),
	stand("emperor", 3, "Emperor", "Bulk-Up Arrow / F4 Boss", true, "B", "B", "A", "D", "E", "EmperorSheet"),
	stand("anubis", 3, "Anubis", "Arrow Core + Bulk-Up Boss", true, "B", "A", "E", "A", "C", "AnubisSheet"),
	stand("star_platinum", 3, "Star Platinum", "High-Act / Boss Disc", false, "A+", "A+", "A", "A", "C", "StarPlatinumSheet"),
	stand("the_world", 3, "The World", "P3 Castle Boss / Disc", false, "A+", "A", "B", "A", "B", "TheWorldSheet"),
	stand("shadow_the_world", 3, "Shadow The World", "Bulk-Up Secret Boss", true, "A", "A", "B", "B", "C"),
	stand("cream", 3, "Cream", "D3 Boss / Boss Disc", true, "B", "B", "C", "C", "D"),
	stand("justice", 3, "Justice", "D2 Boss / Bulk-Up Boss Disc", true, "D", "E", "E", "A", "E"),
	stand("the_world_over_heaven", 3, "The World Over Heaven", "Late Diary Evo", false, "∞", "A+", "A+", "A+", "A+"),
	stand("horus", 3, "Horus", "Mini-Boss / Pet Shop Disc", false, "B", "B", "D", "C", "E"),
	stand("dark_blue_moon", 3, "Dark Blue Moon", "F3 Story / Custom Boss", false, "C", "C", "C", "B", "E"),
	stand("sethan", 3, "Sethan", "F6 Story / Custom Boss", false, "D", "D", "D", "C", "D"),
	stand("crazy_diamond", 4, "Crazy Diamond", "Arrow Core", false, "A", "A", "B", "B", "C"),
	stand("the_hand", 4, "The Hand", "Arrow Core / Spar", false, "B", "B", "C", "C", "C"),
	stand("heavens_door", 4, "Heaven's Door", "Arrow Core / D2 Boss", false, "D", "B", "B", "C", "A"),
	stand("red_hot_chili_pepper", 4, "Red Hot Chili Pepper", "Arrow Core / D1 Boss", false, "A", "A+", "C", "A", "C"),
	stand("killer_queen", 4, "Killer Queen", "Castle Boss / Boss Disc", false, "A", "B", "B", "B", "A"),
	stand("kq_btd", 4, "Killer Queen: Bites the Dust", "P4 Castle / Evolution", false, "A", "B", "B", "A", "A+"),
	stand("echoes", 4, "Echoes Acts 1–3", "Bulk-Up Arrow Core", true, "C", "C", "B", "B", "A"),
	stand("harvest", 4, "Harvest", "Bulk-Up F3 / Swarm", true, "E", "B", "C", "A", "C"),
	stand("highway_star", 4, "Highway Star", "Story / Bulk-Up F4", true, "C", "B", "A", "A", "C"),
	stand("achtung_baby", 4, "Achtung Baby", "Bulk-Up Support", true, "E", "E", "E", "E", "E"),
	stand("enigma", 4, "Enigma", "Mini-Boss / Boss Disc", false, "E", "E", "C", "A", "C"),
	stand("gold_experience", 5, "Gold Experience", "Arrow Core", false, "C", "A", "C", "D", "A"),
	stand("sticky_fingers", 5, "Sticky Fingers", "Arrow Core / F1 Companion", false, "A", "A", "C", "D", "D"),
	stand("six_pistols", 5, "Six Pistols", "Arrow Core", false, "E", "C", "A", "A", "B"),
	stand("aerosmith", 5, "Aerosmith", "Arrow Core", false, "B", "B", "B", "C", "E"),
	stand("purple_haze", 5, "Purple Haze", "Arrow Core", false, "A", "B", "E", "E", "B"),
	stand("spice_girl", 5, "Spice Girl", "Arrow Core", false, "A", "A", "D", "B", "C"),
	stand("king_crimson", 5, "King Crimson", "P5 Castle Boss / Boss Disc", false, "A", "A", "E", "E", "E"),
	stand("gold_experience_requiem", 5, "Gold Experience Requiem", "Requiem Evo", false, "∞", "∞", "∞", "∞", "∞"),
	stand("metallica", 5, "Metallica", "Mini-Boss / Boss Disc", true, "C", "C", "C", "A", "C"),
	stand("chariot_requiem", 5, "Chariot Requiem", "D3 Boss / Requiem Story", false, "E", "E", "E", "A", "A"),
	stand("moody_blues", 5, "Moody Blues", "Bulk-Up Arrow / Support", true, "C", "C", "C", "A", "C"),
	stand("white_album", 5, "White Album", "Bulk-Up D2 Boss / Tank", true, "A", "C", "E", "A", "E"),
	stand("oasis", 5, "Oasis", "Bulk-Up F6 / Grounded Boss", true, "A", "A", "E", "A", "C"),
	stand("the_grateful_dead", 5, "The Grateful Dead", "Bulk-Up F4 Linked Boss", true, "B", "E", "E", "A", "C"),
	stand("beach_boy", 5, "Beach Boy", "Bulk-Up F4 Linked Boss", true, "C", "B", "C", "A", "A"),
	stand("green_day", 5, "Green Day", "Bulk-Up F7 Boss", true, "A", "C", "E", "A", "E"),
	stand("baby_face", 5, "Baby Face", "Bulk-Up Construct Enemy", true, "A", "B", "E", "A", "E"),
	stand("black_sabbath", 5, "Black Sabbath", "F2 Story Boss (Audited)", false, "E", "A", "E", "A", "E"),
}
local standsById: { [string]: Stand } = {}
for _, entry in stands do standsById[entry.id] = entry end

return table.freeze({
	Races = table.freeze(races), RaceOrder = table.freeze(raceOrder),
	Techniques = table.freeze(techniques), TechniqueOrder = table.freeze(techniqueOrder),
	Compatibility = table.freeze(matrix), Evolutions = table.freeze(evolutions),
	StandGrades = table.freeze(grades), StandGradeScope = "StandActionsOnly",
	Stands = table.freeze(stands), StandsById = table.freeze(standsById),
})
