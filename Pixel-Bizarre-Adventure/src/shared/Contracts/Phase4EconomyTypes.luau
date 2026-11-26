--!strict

local Combat = require("./CombatTypes")
local Inventory = require("./InventoryTypes")
local Item = require("./ItemInstanceTypes")

export type Cost = { yen: number, salvageShards: number, materials: number, holyWater: number }
export type Balances = Cost
export type SmithDecision = "AcceptNew" | "KeepOld"
export type RerollPreview = { cost: Cost, legality: Combat.ActionLegality }
export type TemperPreview = {
	nextLevel: Item.TemperLevel?,
	successChancePct: number?,
	cost: Cost?,
	legality: Combat.ActionLegality,
}
export type PurifyPreview = {
	perkId: Item.PurifiedPerkId,
	label: string,
	cost: Cost,
	legality: Combat.ActionLegality,
}
export type SmithItemView = {
	item: Item.ItemInstance,
	display: Inventory.ItemDisplay,
	effectiveBaseStats: { Item.BaseStatLine },
	dismantleShards: number,
	dismantleLegality: Combat.ActionLegality,
	reroll: RerollPreview,
	temper: TemperPreview,
	purification: { PurifyPreview },
}

export type CyberwareSite = "HeadOptics" | "Neural" | "TorsoChassis" | "Limbs" | "HeartCore"
export type CyberwareRoutineId = "UVBeam" | "TacticalSurge" | "SuppressiveVolley" | "SeismicGrip" | "EmergencyOverride"
export type CyberwareInstall = { site: CyberwareSite, tier: Item.Tier, routineId: CyberwareRoutineId? }
export type CyberwareInstallOffer = {
	tier: Item.Tier,
	toleranceCost: number,
	cost: Cost,
	routineId: CyberwareRoutineId?,
	legality: Combat.ActionLegality,
}
export type CyberwareSlotView = {
	site: CyberwareSite,
	installed: CyberwareInstall?,
	offers: { CyberwareInstallOffer },
	legality: Combat.ActionLegality,
}
export type ToleranceView = {
	maxTolerance: number,
	usedTolerance: number,
	maxSites: number,
	strainThreshold: number?,
	cyberStrainActive: boolean,
	controlResistPenaltyPp: number,
	extraAgingYears: number,
}
export type ClinicView = {
	legality: Combat.ActionLegality,
	sites: { CyberwareSlotView },
	tolerance: ToleranceView,
	activeRoutineLimit: number,
	equippedRoutines: { CyberwareRoutineId },
}

export type ParlorTierId = "standard_chip" | "high_roller_chip"
export type SpinCount = number -- Exactly 1 or 10.
export type ParlorRarity = "Common" | "Rare" | "Epic" | "Legendary"
export type ParlorBucketId =
	"CommonCraftingCrate" | "CommonCosmetic" | "RareSupplyCrate" | "EpicCosmetic" | "LegendaryCosmetic"
	| "RareCraftingCrate" | "RareCosmetic" | "EpicBaseGearCrate"
export type ParlorOdds = { bucketId: ParlorBucketId, rarity: ParlorRarity, chancePct: number }
export type ParlorTierView = {
	tierId: ParlorTierId,
	label: string,
	singleSpinYen: number,
	tenSpinYen: number,
	-- Consecutive spins below the pity floor for this tier.
	pityCounter: number,
	pityThreshold: number,
	normalOdds: { ParlorOdds },
	pityOdds: { ParlorOdds },
	legality: Combat.ActionLegality,
}
export type SpinPrize =
	{ kind: "Cosmetic", cosmeticId: string }
	| { kind: "DuplicateCosmetic", cosmeticId: string, shardRefund: number }
	| { kind: "Gear", itemUuid: Item.ItemUuid }
	| { kind: "Supplies", items: { { itemId: Inventory.ItemId, quantity: number } }, resources: Balances }
export type SpinResult = { bucketId: ParlorBucketId, rarity: ParlorRarity, prize: SpinPrize, usedPity: boolean }

export type Snapshot = {
	sessionId: string,
	revision: number,
	balances: Balances,
	smithItems: { SmithItemView },
	clinic: ClinicView,
	parlorTiers: { ParlorTierView },
}

-- Client supplies selections only. Prices, legality, rolls and settlement are server owned.
export type Action =
	{ kind: "CreateOffer", itemUuid: Item.ItemUuid }
	| { kind: "ResolveOffer", itemUuid: Item.ItemUuid, offerId: string, decision: SmithDecision }
	| { kind: "Temper", itemUuid: Item.ItemUuid }
	| { kind: "Purify", itemUuid: Item.ItemUuid, perkId: Item.PurifiedPerkId }
	| { kind: "Dismantle", itemUuid: Item.ItemUuid }
	| { kind: "InstallCyberware", site: CyberwareSite, tier: Item.Tier }
	| { kind: "RemoveCyberware", site: CyberwareSite }
	| { kind: "SetEquippedRoutines", routineIds: { CyberwareRoutineId } }
	| { kind: "Spin", tierId: ParlorTierId, count: SpinCount }
export type ActionRequest = {
	sessionId: string,
	expectedRevision: number,
	-- Reuse the same ID when retrying an uncertain reply. Bind it to the same action.
	requestId: string,
	action: Action,
}
export type Receipt =
	{ kind: "OfferCreated", itemUuid: Item.ItemUuid, offer: Item.PendingSmithOffer }
	| { kind: "OfferResolved", itemUuid: Item.ItemUuid, offerId: string, decision: SmithDecision }
	| { kind: "Tempered", itemUuid: Item.ItemUuid, succeeded: boolean, level: Item.TemperLevel, pityFailures: number }
	| { kind: "Purified", itemUuid: Item.ItemUuid, perkId: Item.PurifiedPerkId }
	| { kind: "Dismantled", itemUuid: Item.ItemUuid, salvageShards: number }
	| { kind: "CyberwareInstalled", install: CyberwareInstall }
	| { kind: "CyberwareRemoved", site: CyberwareSite }
	| { kind: "EquippedRoutinesSet", routineIds: { CyberwareRoutineId } }
	| { kind: "Spun", tierId: ParlorTierId, spentYen: number, results: { SpinResult }, pityCounter: number }
export type ErrorCode = "InvalidRequest" | "StaleRevision" | "ProfileLocked" | "SaveUnavailable"
	| "IllegalAction" | "InsufficientResources" | "ItemNotFound" | "OfferMismatch" | "RequestConflict"
export type SnapshotResponse =
	{ ok: true, snapshot: Snapshot }
	| { ok: false, code: ErrorCode, message: string }
export type ActionResponse =
	-- Reveal only after committing the mutation and request receipt together.
	{ ok: true, requestId: string, receipt: Receipt, snapshot: Snapshot }
	| { ok: false, requestId: string?, code: ErrorCode, message: string, snapshot: Snapshot? }

return table.freeze({})
