--!strict

local Economy = require("../src/shared/Contracts/Phase4EconomyTypes")
local Combat = require("../src/shared/Contracts/CombatTypes")
local Item = require("../src/shared/Contracts/ItemInstanceTypes")
local Remote = require("../src/shared/Contracts/RemoteContract")

local id: Item.ItemUuid = "bacf6098-ddfe-4ce4-b76d-e7b5ec974485"
local offer: Item.PendingSmithOffer = {
	offerId = "smith-offer-1",
	lines = { { affixId = "precision_pp", value = 2 } },
}
local gear: Item.ItemInstance = {
	uuid = id, familyId = "training-wraps", slot = "Weapon", tier = 3, rarity = "Rare",
	baseStats = { { statId = "Physical", value = 6 } },
	rolledLines = { { affixId = "flat_physical", value = 1 } },
	temperLevel = 5, temperPityFailures = 0, cursed = true, pendingSmithOffer = offer,
}
local allowed: Combat.ActionLegality = { canUse = true }
local blocked: Combat.ActionLegality = { canUse = false, disabledReason = "Resolve the pending offer" }
local normalOdds: { Economy.ParlorOdds } = {
	{ bucketId = "CommonCraftingCrate", rarity = "Common", chancePct = 50 },
	{ bucketId = "CommonCosmetic", rarity = "Common", chancePct = 30 },
	{ bucketId = "RareSupplyCrate", rarity = "Rare", chancePct = 14 },
	{ bucketId = "EpicCosmetic", rarity = "Epic", chancePct = 5 },
	{ bucketId = "LegendaryCosmetic", rarity = "Legendary", chancePct = 1 },
}
local snapshot: Economy.Snapshot = {
	sessionId = "phase4-session", revision = 8,
	balances = { yen = 500, salvageShards = 50, materials = 10, holyWater = 1 },
	smithItems = { {
		item = gear,
		display = { itemId = "training-wraps", label = "Training Wraps", description = "Cloth wraps", iconKey = "TrainingWrapsIcon" },
		effectiveBaseStats = { { statId = "Physical", value = 7 } },
		dismantleShards = 9,
		dismantleLegality = blocked,
		reroll = { cost = { yen = 120, salvageShards = 14, materials = 0, holyWater = 0 }, legality = blocked },
		temper = {
			nextLevel = 6, successChancePct = 85,
			cost = { yen = 288, salvageShards = 24, materials = 10, holyWater = 0 }, legality = allowed,
		},
		purification = { {
			perkId = "measured_breath", label = "Measured Breath",
			cost = { yen = 120, salvageShards = 0, materials = 0, holyWater = 1 }, legality = allowed,
		} },
	} },
	clinic = {
		legality = allowed,
		sites = {
			{ site = "HeadOptics", installed = { site = "HeadOptics", tier = 5, routineId = "UVBeam" }, offers = {}, legality = allowed },
			{ site = "Neural", installed = { site = "Neural", tier = 5, routineId = "TacticalSurge" }, offers = {}, legality = allowed },
			{ site = "TorsoChassis", installed = { site = "TorsoChassis", tier = 5, routineId = "SuppressiveVolley" }, offers = {}, legality = allowed },
			{ site = "Limbs", installed = { site = "Limbs", tier = 1 }, offers = {}, legality = allowed },
			{
				site = "HeartCore", legality = allowed,
				offers = {
					{
						tier = 1, toleranceCost = 10, legality = allowed,
						cost = { yen = 80, salvageShards = 6, materials = 0, holyWater = 0 },
					},
					{
						tier = 5, toleranceCost = 42, routineId = "EmergencyOverride",
						cost = { yen = 650, salvageShards = 48, materials = 0, holyWater = 0 },
						legality = { canUse = false, disabledReason = "Tolerance exceeded" },
					},
				},
			},
		},
		tolerance = {
			maxTolerance = 170, usedTolerance = 136, maxSites = 5, strainThreshold = 128,
			cyberStrainActive = true, controlResistPenaltyPp = 10, extraAgingYears = 1,
		},
		activeRoutineLimit = 2, equippedRoutines = { "UVBeam", "TacticalSurge" },
	},
	parlorTiers = { {
		tierId = "standard_chip", label = "Standard Chip", singleSpinYen = 100, tenSpinYen = 900,
		pityCounter = 9, pityThreshold = 10, normalOdds = normalOdds,
		pityOdds = {
			{ bucketId = "RareSupplyCrate", rarity = "Rare", chancePct = 70 },
			{ bucketId = "EpicCosmetic", rarity = "Epic", chancePct = 25 },
			{ bucketId = "LegendaryCosmetic", rarity = "Legendary", chancePct = 5 },
		},
		legality = allowed,
	} },
}
local function request(action: Economy.Action): Remote.Phase4ActionRequest
	return { sessionId = snapshot.sessionId, expectedRevision = snapshot.revision, requestId = action.kind, action = action }
end
local cases: { { action: Economy.Action, receipt: Economy.Receipt } } = {
	{ action = { kind = "CreateOffer", itemUuid = id }, receipt = { kind = "OfferCreated", itemUuid = id, offer = offer } },
	{
		action = { kind = "ResolveOffer", itemUuid = id, offerId = offer.offerId, decision = "KeepOld" },
		receipt = { kind = "OfferResolved", itemUuid = id, offerId = offer.offerId, decision = "KeepOld" },
	},
	{
		action = { kind = "Temper", itemUuid = id },
		receipt = { kind = "Tempered", itemUuid = id, level = 5, succeeded = false, pityFailures = 1 },
	},
	{
		action = { kind = "Purify", itemUuid = id, perkId = "measured_breath" },
		receipt = { kind = "Purified", itemUuid = id, perkId = "measured_breath" },
	},
	{
		action = { kind = "Dismantle", itemUuid = id },
		receipt = { kind = "Dismantled", itemUuid = id, salvageShards = 9 },
	},
	{
		action = { kind = "InstallCyberware", site = "HeartCore", tier = 1 },
		receipt = { kind = "CyberwareInstalled", install = { site = "HeartCore", tier = 1 } },
	},
	{
		action = { kind = "RemoveCyberware", site = "HeartCore" },
		receipt = { kind = "CyberwareRemoved", site = "HeartCore" },
	},
	{
		action = { kind = "SetEquippedRoutines", routineIds = { "TacticalSurge", "SuppressiveVolley" } },
		receipt = { kind = "EquippedRoutinesSet", routineIds = { "TacticalSurge", "SuppressiveVolley" } },
	},
	{
		action = { kind = "Spin", tierId = "standard_chip", count = 1 },
		receipt = {
			kind = "Spun", tierId = "standard_chip", spentYen = 100, pityCounter = 0,
			results = { {
				bucketId = "EpicCosmetic", rarity = "Epic", usedPity = true,
				prize = { kind = "DuplicateCosmetic", cosmeticId = "pose-1", shardRefund = 18 },
			} },
		},
	},
}
for _, case in cases do
	local call = request(case.action)
	local reply: Remote.Phase4ActionResponse = { ok = true, requestId = call.requestId, receipt = case.receipt, snapshot = snapshot }
	assert(reply.ok and reply.requestId == call.requestId and reply.snapshot.sessionId == call.sessionId)
end
local restored: Remote.Phase4SnapshotResponse = { ok = true, snapshot = snapshot }
assert(restored.ok and restored.snapshot.smithItems[1].item.pendingSmithOffer == offer)
assert(gear.rolledLines[1].affixId ~= offer.lines[1].affixId)
local expandedStats: { Item.BaseStatId } = { "Health", "Stamina", "Precision", "DefPen" }
assert(#expandedStats == 4)
local smithItem = snapshot.smithItems[1]
assert(smithItem.display.itemId == gear.familyId and smithItem.effectiveBaseStats[1].value > gear.baseStats[1].value)
assert(smithItem.dismantleShards == 9 and not smithItem.dismantleLegality.canUse)
local clinicOffers = snapshot.clinic.sites[5].offers
assert(clinicOffers[1].legality.canUse and clinicOffers[1].routineId == nil)
assert(not clinicOffers[2].legality.canUse and clinicOffers[2].routineId == "EmergencyOverride")
local stale: Remote.Phase4ActionResponse = { ok = false, code = "StaleRevision", message = "Refresh", snapshot = snapshot }
assert(not stale.ok and stale.snapshot == snapshot)
assert(Remote.Phase4.FolderName == "Phase4Remotes")
assert(Remote.Phase4.GetPhase4Snapshot.className == "RemoteFunction")
assert(Remote.Phase4.SubmitPhase4Action.className == "RemoteFunction")
print("Phase 4 contracts passed: UUID gear, smith offer recovery, gear receipts, clinic offers and actions, and parlor pity")
