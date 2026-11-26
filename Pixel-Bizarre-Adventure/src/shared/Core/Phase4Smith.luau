--!strict

local Contract = require("../Contracts/Phase4EconomyTypes")
local Combat = require("../Contracts/CombatTypes")
local Inventory = require("../Contracts/InventoryTypes")
local Item = require("../Contracts/ItemInstanceTypes")
local Data = require("../Data/Phase4EconomyData")
local Starter = require("../Data/CampaignStarter")
local Economy = require("./Phase4Economy")
local Profile = require("./Phase4Profile")

type Saved = Profile.Saved
type Gear = Item.ItemInstance
type SmithAction =
	{ kind: "CreateOffer", itemUuid: Item.ItemUuid }
	| { kind: "ResolveOffer", itemUuid: Item.ItemUuid, offerId: string, decision: Contract.SmithDecision }
	| { kind: "Temper", itemUuid: Item.ItemUuid }
	| { kind: "Purify", itemUuid: Item.ItemUuid, perkId: Item.PurifiedPerkId }
	| { kind: "Dismantle", itemUuid: Item.ItemUuid }
type Perk = { read id: Item.PurifiedPerkId, read label: string, read minTier: number }
local perks = Data.PurifiedPerks :: { [Item.PurifiedPerkId]: Perk }
local perkOrder: { Item.PurifiedPerkId } = { "iron_ward", "keen_edge", "steady_sight", "clear_mind", "armor_piercer", "measured_breath" }
local OK: Combat.ActionLegality = { canUse = true }

local function cost(yen: number, shards: number?, materials: number?, holyWater: number?): Contract.Cost
	return { yen = yen, salvageShards = shards or 0, materials = materials or 0, holyWater = holyWater or 0 }
end

local function canAfford(state: Saved, yen: number, price: Contract.Cost): boolean
	return yen >= price.yen and state.salvageShards >= price.salvageShards
		and state.materials >= price.materials and state.holyWater >= price.holyWater
end

local function legality(reason: string?): Combat.ActionLegality
	return if reason then { canUse = false, disabledReason = reason } else OK
end

local function toCalculator(gear: Gear): Economy.GearInstance
	local total = 0
	for _, line in gear.baseStats do total += line.value end
	return {
		uuid = gear.uuid, familyId = gear.familyId, slot = gear.slot, tier = gear.tier,
		rarity = if gear.rarity == "BossSet" then "Legendary" else gear.rarity,
		baseStatPts = total, rolledLines = gear.rolledLines, temperLevel = gear.temperLevel,
		temperPityFailures = gear.temperPityFailures, cursed = gear.cursed, purifiedPerk = gear.purifiedPerk,
		pendingSmithOffer = if gear.pendingSmithOffer then gear.pendingSmithOffer.lines else nil,
	}
end

local function measuredBreathConflict(state: Saved, uuid: string): boolean
	if not state.equippedGear[uuid] then return false end
	for id, gear in state.items do
		if id ~= uuid and state.equippedGear[id] and gear.purifiedPerk == "measured_breath" then return true end
	end
	return false
end

local function dismantleReason(state: Saved, gear: Gear): string?
	if gear.pendingSmithOffer then return "Resolve the pending smith offer first." end
	if state.equippedGear[gear.uuid] then return "Unequip the item first." end
	-- The published salvage table only specifies the four ordinary rarities.
	if gear.rarity == "BossSet" then return "Boss set salvage is unavailable." end
	return nil
end

local function salvage(gear: Gear): number
	if gear.rarity == "BossSet" then return 0 end
	local amounts = Data.ActIncome[gear.tier].dismantleShards :: { [Contract.ParlorRarity]: number }
	return amounts[gear.rarity]
end

local function view(
	state: Saved, yen: number, gear: Gear, displayItem: ((Inventory.ItemId) -> Inventory.ItemDisplay?)?
): Contract.SmithItemView
	local starterItem = Starter.Items[gear.familyId]
	local fallback: Inventory.ItemDisplay = { itemId = gear.familyId, label = gear.familyId, description = "" }
	local display = (if displayItem then displayItem(gear.familyId) else nil)
		or (if starterItem then starterItem.display else fallback)
	local effective: { Item.BaseStatLine } = {}
	local calculator = toCalculator(gear)
	for _, line in gear.baseStats do
		calculator.baseStatPts = line.value
		table.insert(effective, { statId = line.statId, value = Economy.effectiveBaseStatPts(calculator) })
	end
	local smithPrice = Data.BlacksmithRerollCostByTier[gear.tier]
	local rerollCost = cost(smithPrice.yen, smithPrice.shards)
	local pending = if gear.pendingSmithOffer then "Resolve the pending smith offer first." else nil
	local rerollReason = pending or (if #gear.rolledLines == 0 then "Plain gear has no rolled lines."
		elseif not canAfford(state, yen, rerollCost) then "Not enough Yen or salvage shards." else nil)
	local temper: Contract.TemperPreview = { legality = legality("Already +10.") }
	local nextLevel = gear.temperLevel + 1
	if nextLevel <= Data.GlobalCaps.TemperMaxLevel then
		local row = Data.TemperLevels[nextLevel]
		local price = cost(Economy.temperCost(gear.tier, nextLevel))
		temper.nextLevel = nextLevel
		temper.cost = price
		temper.successChancePct = math.min(100, row.successRatePct + gear.temperPityFailures * row.pityAddPctPerFail)
		temper.legality = legality(if canAfford(state, yen, price) then nil else "Not enough resources.")
	end
	local purification: { Contract.PurifyPreview } = {}
	if gear.cursed then
		local price = cost(Data.HolyWaterPriceByTier[gear.tier], 0, 0, 1)
		for _, perkId in perkOrder do
			local perk = perks[perkId]
			local reason = if gear.tier < perk.minTier then "Perk requires a higher tier."
				elseif perkId == "measured_breath" and measuredBreathConflict(state, gear.uuid) then "Measured Breath limit reached."
				elseif not canAfford(state, yen, price) then "Need Holy Water and sufficient Yen." else nil
			table.insert(purification, { perkId = perkId, label = perk.label, cost = price, legality = legality(reason) })
		end
	end
	return {
		item = gear, display = display, effectiveBaseStats = effective, dismantleShards = salvage(gear),
		dismantleLegality = legality(dismantleReason(state, gear)),
		reroll = { cost = rerollCost, legality = legality(rerollReason) }, temper = temper, purification = purification,
	}
end

local function apply(
	state: Saved, yen: number, action: SmithAction, roll: () -> number, makeId: () -> string
): (Contract.Receipt?, number, Contract.ErrorCode?, string?)
	local gear = state.items[action.itemUuid]
	if not gear then return nil, yen, "ItemNotFound", "Gear UUID not found." end
	local updated = table.clone(gear)
	local receipt: Contract.Receipt
	local remainingYen = yen
	if action.kind == "Dismantle" then
		local reason = dismantleReason(state, gear)
		if reason then return nil, yen, "IllegalAction", reason end
		local amount = salvage(gear)
		state.items = table.clone(state.items)
		state.items[gear.uuid] = nil
		state.salvageShards += amount
		return { kind = "Dismantled", itemUuid = gear.uuid, salvageShards = amount }, yen, nil, nil
	elseif action.kind == "CreateOffer" then
		if gear.pendingSmithOffer or #gear.rolledLines == 0 then
			return nil, yen, "IllegalAction", "Resolve the pending offer first. Plain gear cannot be rerolled."
		end
		local price = Data.BlacksmithRerollCostByTier[gear.tier]
		if not canAfford(state, yen, cost(price.yen, price.shards)) then
			return nil, yen, "InsufficientResources", "Not enough Yen or salvage shards."
		end
		local result = Economy.createSmithRerollOffer(toCalculator(gear), yen, state.salvageShards, roll)
		if not result.ok then return nil, yen, "IllegalAction", result.error end
		local offer: Item.PendingSmithOffer = { offerId = makeId(), lines = assert(result.item.pendingSmithOffer) }
		updated.pendingSmithOffer = offer
		remainingYen, state.salvageShards = result.yen, result.shards
		receipt = { kind = "OfferCreated", itemUuid = gear.uuid, offer = offer }
	elseif action.kind == "ResolveOffer" then
		if not gear.pendingSmithOffer or gear.pendingSmithOffer.offerId ~= action.offerId then
			return nil, yen, "OfferMismatch", "This smith offer is no longer current."
		end
		local result = Economy.resolveSmithOffer(toCalculator(gear), action.decision)
		updated.rolledLines = result.item.rolledLines
		updated.pendingSmithOffer = nil
		receipt = { kind = "OfferResolved", itemUuid = gear.uuid, offerId = action.offerId, decision = action.decision }
	elseif action.kind == "Temper" then
		if gear.temperLevel >= Data.GlobalCaps.TemperMaxLevel then return nil, yen, "IllegalAction", "Already +10." end
		if not canAfford(state, yen, cost(Economy.temperCost(gear.tier, gear.temperLevel + 1))) then
			return nil, yen, "InsufficientResources", "Not enough resources."
		end
		local result = Economy.temperGear(toCalculator(gear), yen, state.salvageShards, state.materials, roll)
		if not result.ok then return nil, yen, "IllegalAction", result.error end
		remainingYen, state.salvageShards, state.materials = result.yen, result.shards, result.materials
		updated.temperLevel, updated.temperPityFailures = result.item.temperLevel, result.item.temperPityFailures
		receipt = {
			kind = "Tempered", itemUuid = gear.uuid, succeeded = result.succeeded,
			level = updated.temperLevel, pityFailures = updated.temperPityFailures,
		}
	else
		if not canAfford(state, yen, cost(Data.HolyWaterPriceByTier[gear.tier], 0, 0, 1)) then
			return nil, yen, "InsufficientResources", "Need Holy Water and sufficient Yen."
		end
		local result = Economy.purifyCursedGear(toCalculator(gear), action.perkId, yen, state.holyWater, measuredBreathConflict(state, gear.uuid))
		if not result.ok then return nil, yen, "IllegalAction", result.error end
		remainingYen, state.holyWater = result.yen, result.holyWaterCount
		updated.cursed, updated.purifiedPerk = result.item.cursed, result.item.purifiedPerk
		receipt = { kind = "Purified", itemUuid = gear.uuid, perkId = action.perkId }
	end
	state.items = table.clone(state.items)
	state.items[gear.uuid] = updated
	return receipt, remainingYen, nil, nil
end

return table.freeze({ view = view, apply = apply })
