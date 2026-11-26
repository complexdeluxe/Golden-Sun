--!strict

local Assets = require("../Contracts/AssetManifest")
local Map = require("../Contracts/MapTypes")
local Save = require("../Contracts/SaveTypes")

export type FlagId = "F1" | "F2" | "F3" | "F4" | "F5" | "F6" | "F7"
export type DungeonId = "D1" | "D2" | "D3"
export type NodeId = FlagId | DungeonId | "Castle"
export type BossSetId = "ice_demon" | "ultimate_lifeform" | "crusaders_world" | "quiet_life" | "crimson_emperor"
type Encounter = {
	read opponent: string,
	read location: string,
	read hook: string,
	read stageAssetKey: Assets.AssetKey?,
	read stageTag: Map.StageTag?,
	read opponentId: string?,
}
export type Approach = { read id: string, read opponent: string, read hook: string }
export type Flag = Encounter & { read kind: "Flag", read id: FlagId }
export type Dungeon = Encounter & {
	read kind: "Dungeon", read id: DungeonId, read approaches: { Approach },
	read defaultApproachId: string?, read recruitId: string?,
}
export type BossMove = {
	read name: string, read detail: string, read multiplier: number?, read telegraphTurns: number?,
	read bonusPrimaryMultiplier: number?,
}
export type BossPhase = { read startsAtHpPct: number, read moves: { BossMove } }
export type Castle = Encounter & {
	read kind: "Castle", read id: "Castle", read bossSetId: BossSetId, read phases: { BossPhase },
}
export type Node = Flag | Dungeon | Castle
export type Part = { read storyPart: number, read title: string, read nodes: { Node } }
export type RouteEntry = { read actTier: number, read storyPart: number, read isFlashback: boolean }

local function flag(id: FlagId, opponent: string, location: string, hook: string, stage: Assets.AssetKey?, opponentId: string?, stageTag: Map.StageTag?): Flag
	return table.freeze({
		kind = "Flag" :: "Flag", id = id, opponent = opponent, location = location, hook = hook,
		stageAssetKey = stage, opponentId = opponentId, stageTag = stageTag,
	})
end

local function approach(id: string, opponent: string, hook: string): Approach
	return table.freeze({ id = id, opponent = opponent, hook = hook })
end

local function dungeon(
	id: DungeonId, opponent: string, location: string, hook: string, approaches: { Approach },
	stage: Assets.AssetKey?, opponentId: string?, defaultApproachId: string?, recruitId: string?, stageTag: Map.StageTag?
): Dungeon
	return table.freeze({
		kind = "Dungeon" :: "Dungeon", id = id, opponent = opponent, location = location, hook = hook,
		stageAssetKey = stage, stageTag = stageTag, opponentId = opponentId, approaches = table.freeze(approaches),
		defaultApproachId = defaultApproachId, recruitId = recruitId,
	})
end

local function move(name: string, detail: string, multiplier: number?, telegraphTurns: number?, bonus: number?): BossMove
	return table.freeze({ name = name, detail = detail, multiplier = multiplier, telegraphTurns = telegraphTurns, bonusPrimaryMultiplier = bonus })
end

local function phase(startsAtHpPct: number, moves: { BossMove }): BossPhase
	return table.freeze({ startsAtHpPct = startsAtHpPct, moves = table.freeze(moves) })
end

local function castle(opponent: string, location: string, hook: string, setId: BossSetId, first: BossPhase, second: BossPhase, stage: Assets.AssetKey?): Castle
	local phases: { BossPhase } = { first, second }
	return table.freeze({
		kind = "Castle" :: "Castle", id = "Castle" :: "Castle", opponent = opponent, location = location, hook = hook,
		stageAssetKey = stage, stageTag = nil, opponentId = nil, bossSetId = setId, phases = table.freeze(phases),
	})
end

local function part(storyPart: number, title: string, nodes: { Node }): Part
	return table.freeze({ storyPart = storyPart, title = title, nodes = table.freeze(nodes) })
end

-- Story order and the two authored approaches per Dungeon come from the launch roster.
-- The two Act 1 openers use the live labels and default approaches from CampaignStarter/ActOneEncounters.
local parts: { Part } = {
	part(1, "Phantom Blood", {
		flag("F1", "Ogre Street Brawler", "Ogre Street", "Guard or interrupt the heavy windup.", "OgreStreetStage", "ogre_brawler", "Neutral"),
		flag("F2", "Ogre Street Knifeman", "Night Alley", "Aimed delayed slash applies Bleed.", "NightAlleyStage", "ogre_knifeman", "Night"),
		dungeon("D1", "Speedwagon", "Ogre Street Hideout", "Hat toss threatens the back line. Nonlethal surrender opens recruitment.", {
			approach("ogre_lookout", "Ogre Street Lookout", "Interrupt the low-HP rally."),
			approach("tattoo", "Tattoo", "Fast strike followed by an aimed knife attack and a nonlethal retreat."),
		}, "OgreHideoutStage", "speedwagon", "ogre_lookout", "speedwagon", "Neutral"),
		flag("F3", "Estate Infiltrator", "London cobblestones", "Feint followed by a visible lunge."),
		flag("F4", "Weak Zombie", "Joestar Estate gates", "Bleed and regeneration; Hamon or burst can finish it."),
		dungeon("D2", "Dio Brando, Mansion Escape", "Burning Joestar Mansion", "Interrupt the drain and force Dio to retreat.", {
			approach("estate_straggler", "Estate Straggler", "Guards, then exposes an opening."),
			approach("ceiling_zombie", "Ceiling Zombie", "An overhead shadow warns which position the drop attack hits."),
		}),
		flag("F5", "Jack the Ripper", "Windknight's Lot tunnel", "Marks a lane before a blade fan."),
		flag("F6", "Wang Chan", "Windknight's Lot ruins", "Queues a strike on a wounded ally."),
		flag("F7", "Doobie", "Windknight's Lot courtyard", "Names the concealed bite target. Cleanse if it lands."),
		dungeon("D3", "Bruford and Tarkus", "Double-Chain Training Crypt", "Sequential stance and delayed heavy phases share one dungeon clear.", {
			approach("crypt_chain_guard", "Crypt Chain Guard", "An armored guard telegraphs a wide swing."),
			approach("adams", "Adams", "A zombie officer pressures the guarded front line."),
		}),
		castle("Dio Brando, Ice Demon", "Dio's Manor Spire", "Freeze and Drain lead into a telegraphed eye beam.", "ice_demon",
			phase(100, {
				move("Vaporization Freeze", "Removable Slow for two turns.", 1),
				move("Blood Drain", "Heals 8%; Hamon or UV Flash blocks the heal.", 0.95),
			}),
			phase(50, { move("Space Ripper Stingy Eyes", "+15 Defense Penetration. Guard or interrupt offensively; UV Flash does not cancel it.", 1.70, 1) }),
			"DioCastleStage"),
	}),
	part(2, "Battle Tendency", {
		flag("F1", "New York Brass Knuckle Thug", "New York backstreets", "Body jab then a clearly telegraphed clinch."),
		flag("F2", "Straizo", "Brooklyn approach", "Separate telegraphs for the eye attack and drain."),
		dungeon("D1", "Santana", "Mexican underground research facility", "Body-fold ambush with a named target.", {
			approach("donovan", "Donovan", "Ambush marker and vulnerable recovery."),
			approach("facility_experiment_subject", "Facility Experiment Subject", "Interrupt next-turn regeneration."),
		}),
		flag("F3", "Pillar Guard", "Rome catacombs", "Lowers Guard before a committed sweep.", "RomeCatacombsStage"),
		flag("F4", "Rival Security Detail, led by Stroheim", "Pillar discovery site", "Nonlethal burst telegraph followed by an alliance beat."),
		dungeon("D2", "Esidisi", "Air Supplena, Hell Climb Pillar", "Names a target for delayed heat; distinguish Guard from Cleanse.", {
			approach("vampire_cultist", "Vampire Cultist", "A visible channel buffs one ally."),
			approach("caesar_zeppeli", "Caesar Zeppeli", "Optional nonlethal training spar with a bubble volley. The cultist fills the slot if declined."),
		}),
		flag("F5", "Hamon Disciples", "Alpine approach training stop", "Nonlethal bout with an interruptible breath windup."),
		flag("F6", "Vampire Charioteer", "Swiss Alpine pass", "Marks a charge lane and recovers after impact."),
		flag("F7", "Ancient Mask Bearer", "Alpine arena approach", "Queues one low-health drain."),
		dungeon("D3", "Wamuu", "Skeleton Heel Stone arena", "Marks a wind lane before the heavy.", {
			approach("wired_beck", "Wired Beck", "Visible spike retaliation window."),
			approach("vampire_horse_handler", "Vampire Horse Handler", "Calls a charge through one marked lane."),
		}, "SkeletonHeelStoneStage"),
		castle("Kars, Thousand Blades", "Swiss Alps peak / volcano summit", "Blade Parry gives way to Bone Storm.", "ultimate_lifeform",
			phase(100, {
				move("Light-Blade Slash", "+15 Critical Chance points and Bleed.", 1.05),
				move("Blade Parry", "One-turn melee counter stance. Shatter strips Parry."),
			}),
			phase(50, { move("Brilliant Bone Storm", "AoE per ally. Kars gains 15% Speed for two turns. Guard or interrupt with offensive Stun/Hamon.", 1.35, 1) })),
	}),
	part(3, "Stardust Crusaders", {
		flag("F1", "Stand-Awakened Jail Thug", "Tokyo Jail", "Stand Jab and the Guard lesson work with or without a Stand.", "TokyoJailStage", "jail_thug", "Neutral"),
		flag("F2", "Kakyoin", "Tokyo Schoolyard", "Emerald Splash and Barrier Snare precede the flesh-bud release.", "TokyoSchoolyardStage", "kakyoin", "Neutral"),
		dungeon("D1", "Avdol", "Tiger Balm Garden", "Hong Kong harbor spar with a telegraphed fire lane and guaranteed companion milestone.", {
			approach("polnareff", "Polnareff / Silver Chariot", "Optional nonlethal duel; fall back to the swordsman if declined."),
			approach("harbor_duelist", "Harbor Sword Duelist", "Windup lunge as the standard harbor opponent."),
		}, "TigerBalmGardenStage", "avdol", "harbor_duelist", "avdol", "Neutral"),
		flag("F3", "Imposter Captain Tennille / Dark Blue Moon", "South China Sea freighter", "Barnacle Slash and visible dive tell."),
		flag("F4", "Hol Horse and J. Geil", "Calcutta streets", "Gun-line windup tied to a reflected strike.", "CalcuttaStage"),
		dungeon("D2", "Enya / Justice", "Foggy Town", "Bleed sets up a named-target stun; Cleanse or Guard.", {
			approach("fog_corpse", "Fog Corpse", "Strikes once from Justice's fog markers."),
			approach("mirror_ambusher", "Mirror Ambusher", "One announced target and strike on the Calcutta approach."),
		}, "DesertedTownStage"),
		flag("F5", "N’Doul / Geb", "Desert Road", "Shows the water strike's target before it lands."),
		flag("F6", "Alessi / Sethan", "Luxor Alley", "Shadow exposure precedes fight-local aging."),
		flag("F7", "Pet Shop / Horus", "Mansion gates", "Queues an icicle for a single ally.", "DioMansionGatesStage"),
		dungeon("D3", "Vanilla Ice / Cream", "DIO’s hallway", "Telegraph the void's path and its recovery window.", {
			approach("chaka", "Chaka / Anubis", "Preview a melee counter on the katana chase."),
			approach("mansion_watchguard", "Mansion Watchguard", "Charges before a front-line strike."),
		}, "DioMansionHallStage"),
		castle("DIO / The World", "Cairo rooftops and Clock Tower", "Visible Time Stop with a shared bonus Primary cap.", "crusaders_world",
			phase(100, { move("MUDA Barrage", "Four hits under one action budget.", 1.10), move("Knife Fan", "AoE knife attack.", 0.85) }),
			phase(50, { move("THE WORLD", "Shows Barrage and one Road Roller bonus Primary with its target. No extra regeneration or cooldown tick.", 1.10, 1, 1.75) }),
			"CairoBridgeStage"),
	}),
	part(4, "Diamond Is Unbreakable", {
		flag("F1", "Angelo / Aqua Necklace", "Morioh Station, rain", "Water marks one target before a grab.", "MoriohTownStage"),
		flag("F2", "Keicho / Bad Company", "Nijimura House", "Platoon volley and missile telegraph.", "NijimuraHouseStage"),
		dungeon("D1", "Akira / Red Hot Chili Pepper", "Morioh power lines", "Guard the target of the Stamina-draining hit.", {
			approach("morioh_delinquent", "Morioh Delinquent", "One low-cost heavy."),
			approach("okuyasu", "Okuyasu / The Hand", "Optional nonlethal duel with a visible pull. The delinquent fills the slot if declined."),
		}),
		flag("F3", "Shigechi / Harvest", "Budogaoka", "Nonlethal collection dispute and recruitment offer."),
		flag("F4", "Yuya / Highway Star", "Morioh Tunnel", "Marks a pursuit target before the drain."),
		dungeon("D2", "Rohan / Heaven’s Door", "Rohan’s studio", "Named-target Page Lock and a nonlethal mastery trial.", {
			approach("tamami", "Tamami / The Lock", "A marked ally gains a removable burden if the windup finishes."),
			approach("hazamada", "Hazamada / Surface", "A copied stance previews one repeated action."),
		}),
		flag("F5", "Stray Cat", "Kawajiri Garden", "An air bubble primes the next hit."),
		flag("F6", "Yukako / Love Deluxe", "Boyoyoing Cape", "One round to interrupt or defend against the hair bind.", "BoyoyoingCapeStage"),
		flag("F7", "Sheer Heart Attack", "Mukade Shoe Store", "Thermal Lock and Iron Shell teach defense penetration.", "TailorDistrictStage"),
		dungeon("D3", "Yoshikage Kira / Killer Queen", "Kira Estate", "Coin Bomb teaches Cleanse and builds on Stray Cat.", {
			approach("terunosuke", "Terunosuke / Enigma", "A fear tell precedes the paper trap."),
			approach("yoshihiro", "Yoshihiro / Atom Heart Father", "A photograph marks a target for next-round burst."),
		}, "KiraEstateStage"),
		castle("Kira as Kosaku / Bites the Dust", "Chaos in Morioh", "The roster retains the loop-reset story beat. The audited combat rotation uses Air Bomb and Thermal Lock.", "quiet_life",
			phase(100, { move("Coin Bomb", "Removable mark detonates at the end of the target's next turn; Cleanse defuses and Guard mitigates.", 1.50), move("Detonate Jab", "Direct attack.", 1) }),
			phase(50, {
				move("Stray Cat Air Bomb", "Single-target strike. Kira has +15 Dodge points until it lands.", 1.60, 1),
				move("Thermal Lock", "Every third phase-two turn, replaces Air Bomb and targets the highest Attack/Resolve ally.", 1.45, 1),
			}), "ChaosInMoriohStage"),
	}),
	part(5, "Golden Wind", {
		flag("F1", "Bruno / Sticky Fingers", "Naples arrival", "Zipper marks the lunge in a nonlethal companion beat.", "NaplesTrainStationStage"),
		flag("F2", "Black Sabbath, Polpo’s trial", "Polpo’s courtyard", "Audited light, Guard, interrupt, and redirect sequence.", "BlackSabbathStage"),
		dungeon("D1", "Zucchero and Sale", "Capri and Marina", "Sequential hidden attacker and stopped projectile share one clear.", {
			approach("passione_dock_enforcer", "Passione Dock Enforcer", "A front-line guard protects the backliner for one action."),
			approach("leaky_eye_luca", "Leaky-Eye Luca", "Visible shovel windup on the Naples-to-marina approach."),
		}),
		flag("F3", "Illuso / Man in the Mirror", "Pompeii ruins", "Names the isolated fighter before the mirror closes."),
		flag("F4", "Prosciutto and Pesci", "Florence Express", "Fight-local aging and an announced hook in one linked fight."),
		dungeon("D2", "Ghiaccio / White Album", "Venice canals", "Telegraphed armor and deflection windows.", {
			approach("formaggio", "Formaggio / Little Feet", "Warned shrink effect stays local to the fight."),
			approach("melone", "Melone / Baby Face", "A construct marks a threatened target before attacking."),
		}, "VeniceCanalsStage"),
		flag("F5", "Doppio / Epitaph", "Colosseum steps route marker", "Counter stance invites a delayed or alternate attack."),
		flag("F6", "Risotto / Metallica", "Sardinia cliffs", "Iron-drain mark, concealment, and the Boss Disc chase."),
		flag("F7", "Cioccolata and Secco", "Rome outskirts", "Stagger mold pressure and the ground strike.", "RomeOutskirtsStage"),
		dungeon("D3", "Chariot Requiem", "Roman Colosseum", "Shadow-light objective and Requiem Arrow fragment milestone.", {
			approach("squalo_tizzano", "Squalo and Tizzano", "One mark and one burst window on the canal detour."),
			approach("passione_cleanup_crew", "Passione Cleanup Crew", "A Rome-approach spotter marks a target for another grunt."),
		}, "RomanColosseumStage"),
		castle("Diavolo / King Crimson", "Rome sanctum", "Epitaph Counter into Time Erase with a Guard or Redirect window.", "crimson_emperor",
			phase(100, { move("Epitaph Counter", "Telegraphed stance negates the first eligible melee Primary and counters once.", 1.20, 1), move("Crimson Chop", "Applies Bleed.", 1.05) }),
			phase(50, { move("Time Erase", "Locks the target before the priority shift. Guard and Redirect remain available before the strike.", 1.70, 1) }),
			"RomeSanctumStage"),
	}),
}

local function route(order: { number }, flashbacks: boolean): { RouteEntry }
	local entries: { RouteEntry } = {}
	for actTier, storyPart in order do
		local entry: RouteEntry = { actTier = actTier, storyPart = storyPart, isFlashback = flashbacks and storyPart <= 2 }
		table.insert(entries, table.freeze(entry))
	end
	return table.freeze(entries)
end
local routes: { [Save.Origin]: { RouteEntry } } = {
	Part1_Hamon = route({ 1, 2, 3, 4, 5 }, false),
	Part3_Stand = route({ 3, 1, 2, 4, 5 }, true),
}

type Piece = { read slot: "Head" | "Body", read iconKey: Assets.AssetKey }
type SetStat = "ControlResistPp" | "Defense" | "Speed" | "PrecisionPp" | "CritPp"
export type SetEffect =
	{ read kind: "IceDemon", read trigger: "FirstLandedNaturalPrimary", read slowSpeedPct: number, read slowTurns: number, read maxSlowProcsPerFight: number,
		read bloodHealDiscount: number, read minBloodHealCost: number, read healGateAboveBlood: number,
		read maxBloodHealsPerNaturalTurn: number, read eligibleBloodRaces: { string } }
	| { read kind: "UltimateLifeform", read trigger: "GuardHostileHit", read resolve: number, read defPenPp: number, read maxProcsPerRound: number,
		read requiresUnboundHamonOrPillarMan: boolean, read nextPrimaryOnly: boolean, read expiresEndOfNextTurn: boolean, read stacks: boolean }
	| { read kind: "CrusadersWorld", read trigger: "OnFireActivation", read stamina: number, read positiveCostStandDiscount: number, read maxProcsPerOnFire: number }
	| { read kind: "QuietLife", read trigger: "StateChangingSecondary", read critPp: number, read precisionPp: number, read sameTurnOnly: boolean }
	| { read kind: "CrimsonEmperor", read trigger: "LandedCritOrCounter", read bleedTurns: number, read bleedHpPct: number, read bossTickCap: number, read resolve: number,
		read maxProcsPerAction: number, read sharedBleedPerTarget: boolean, read ticksAtTargetTurnEnd: boolean, read canProcFromBleed: boolean }
export type BossSet = {
	read id: BossSetId, read label: string, read storyPart: number, read pieces: { Piece },
	read onePieceStat: SetStat, read authoredOnePieceAmountByAct: { number }, read onePieceAmountByAct: { number },
	read pointsPerUnit: number, read fullSet: SetEffect,
}

local actAmounts = table.freeze({ 1, 2, 3, 4, 5 })
local function bossSet(id: BossSetId, label: string, storyPart: number, head: Assets.AssetKey, body: Assets.AssetKey,
	stat: SetStat, amounts: { number }, pointsPerUnit: number, effect: SetEffect): BossSet
	local headPiece: Piece = table.freeze({ slot = "Head" :: "Head", iconKey = head })
	local bodyPiece: Piece = table.freeze({ slot = "Body" :: "Body", iconKey = body })
	local pieces: { Piece } = { headPiece, bodyPiece }
	local effective: { number } = {}
	-- The authored Crimson Emperor T1 and T4 Crit quotes exceed the half-slot
	-- allowance at 1.5 points per Crit pp. Preserve the quotes and cap the usable value.
	for act, amount in amounts do effective[act] = math.min(amount, act / pointsPerUnit) end
	return table.freeze({
		id = id, label = label, storyPart = storyPart, pieces = table.freeze(pieces),
		onePieceStat = stat, authoredOnePieceAmountByAct = amounts, onePieceAmountByAct = table.freeze(effective),
		pointsPerUnit = pointsPerUnit, fullSet = table.freeze(effect),
	})
end
local bossSets: { [BossSetId]: BossSet } = {
	ice_demon = bossSet("ice_demon", "Ice Demon", 1, "IceDemonCrownIcon", "IceDemonCoatIcon", "ControlResistPp", actAmounts, 0.8, {
		kind = "IceDemon", trigger = "FirstLandedNaturalPrimary", slowSpeedPct = -20, slowTurns = 2, maxSlowProcsPerFight = 1,
		bloodHealDiscount = 3, minBloodHealCost = 7, healGateAboveBlood = 25, maxBloodHealsPerNaturalTurn = 1,
		eligibleBloodRaces = table.freeze({ "Undead", "Vampire", "PillarMan", "UltimateLifeform" }),
	}),
	ultimate_lifeform = bossSet("ultimate_lifeform", "Ultimate Lifeform", 2, "UltimateLifeformCrestIcon", "UltimateLifeformGarbIcon", "Defense", actAmounts, 1, {
		kind = "UltimateLifeform", trigger = "GuardHostileHit", resolve = 10, defPenPp = 10, maxProcsPerRound = 1,
		requiresUnboundHamonOrPillarMan = true, nextPrimaryOnly = true, expiresEndOfNextTurn = true, stacks = false,
	}),
	crusaders_world = bossSet("crusaders_world", "Crusader's World", 3, "CrusadersWorldHelmIcon", "CrusadersWorldJacketIcon", "Speed", actAmounts, 1, {
		kind = "CrusadersWorld", trigger = "OnFireActivation", stamina = 1, positiveCostStandDiscount = 1, maxProcsPerOnFire = 1,
	}),
	quiet_life = bossSet("quiet_life", "Quiet Life", 4, "QuietLifeCrestIcon", "QuietLifeSuitIcon", "PrecisionPp", actAmounts, 0.5, {
		kind = "QuietLife", trigger = "StateChangingSecondary", critPp = 6, precisionPp = 6, sameTurnOnly = true,
	}),
	crimson_emperor = bossSet("crimson_emperor", "Crimson Emperor", 5, "CrimsonEmperorCrownIcon", "CrimsonEmperorVestIcon", "CritPp", table.freeze({ 1, 1, 2, 3, 3 }), 1.5, {
		kind = "CrimsonEmperor", trigger = "LandedCritOrCounter", bleedTurns = 2, bleedHpPct = 4, bossTickCap = 25, resolve = 5,
		maxProcsPerAction = 1, sharedBleedPerTarget = true, ticksAtTargetTurnEnd = true, canProcFromBleed = false,
	}),
}

return table.freeze({
	Parts = table.freeze(parts), OriginRoutes = table.freeze(routes), BossSets = table.freeze(bossSets),
	BossSetDropProtection = table.freeze({ firstPieceClear = 1, missingPieceClear = 2 }),
	CastleTransition = table.freeze({ startsAtHpPct = 50, queueAfterCrossingAttack = true, maxTransitions = 1 }),
})
