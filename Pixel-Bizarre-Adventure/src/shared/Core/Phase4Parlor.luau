--!strict

local Contract = require("../Contracts/Phase4EconomyTypes")
local Combat = require("../Contracts/CombatTypes")
local Inventory = require("../Contracts/InventoryTypes")
local Item = require("../Contracts/ItemInstanceTypes")
local Data = require("../Data/Phase4EconomyData")
local Economy = require("./Phase4Economy")
local Profile = require("./Phase4Profile")

type Saved = Profile.Saved
type TierId = Contract.ParlorTierId
export type Grant =
	{ kind: "Cosmetic", cosmeticId: string }
	| { kind: "Gear", familyId: Inventory.ItemId, slot: Inventory.GearSlot, baseStats: { Item.BaseStatLine } }
	| { kind: "Supplies", items: { { itemId: Inventory.ItemId, quantity: number } }, resources: Contract.Balances }
-- Server-owned content catalog. Must be pure for a Store transform retry.
export type Catalog = (Contract.ParlorBucketId, number, () -> number) -> Grant?

local tiers: { TierId } = { "standard_chip", "high_roller_chip" }
local config = Data.DarbyParlor

local function views(state: Saved, yen: number): { Contract.ParlorTierView }
	local result: { Contract.ParlorTierView } = {}
	for _, id in tiers do
		local tier = config.Tiers[id]
		local normal: { Contract.ParlorOdds } = {}
		local boosted: { Contract.ParlorOdds } = {}
		local total = 0
		for _, entry in tier.odds do
			if entry.rarity ~= "Common" then total += entry.weightPct end
		end
		for _, entry in tier.odds do
			local bucket = entry.bucket :: Contract.ParlorBucketId
			table.insert(normal, { bucketId = bucket, rarity = entry.rarity, chancePct = entry.weightPct })
			if entry.rarity ~= "Common" then
				table.insert(boosted, { bucketId = bucket, rarity = entry.rarity, chancePct = 100 * entry.weightPct / total })
			end
		end
		local legality: Combat.ActionLegality = if yen >= tier.singleYen then { canUse = true }
			else { canUse = false, disabledReason = "Not enough Yen for one spin." }
		table.insert(result, {
			tierId = id, label = tier.label, singleSpinYen = tier.singleYen, tenSpinYen = tier.tenSpinYen,
			pityCounter = state.pity[id] or 0, pityThreshold = tier.pityThreshold, normalOdds = normal, pityOdds = boosted,
			legality = legality,
		})
	end
	return result
end

local function applyGrant(
	state: Saved, rarity: Contract.ParlorRarity, grant: Grant, makeId: () -> string
): (Contract.SpinPrize?, number)
	if grant.kind == "Cosmetic" then
		if grant.cosmeticId == "" then return nil, 0 end
		if state.cosmetics[grant.cosmeticId] then
			local refund = (config.DuplicateCosmeticShardRefund :: { [Contract.ParlorRarity]: number })[rarity]
			state.salvageShards += refund
			return { kind = "DuplicateCosmetic", cosmeticId = grant.cosmeticId, shardRefund = refund }, 0
		end
		state.cosmetics[grant.cosmeticId] = true
		return { kind = "Cosmetic", cosmeticId = grant.cosmeticId }, 0
	elseif grant.kind == "Gear" then
		local total = 0
		for _, stat in grant.baseStats do
			if not Profile.integer(stat.value, 1, 2 * state.act) then return nil, 0 end
			total += stat.value
		end
		if total < 1 or total > 2 * state.act or grant.familyId == "" then return nil, 0 end
		local uuid = makeId()
		if uuid == "" or state.items[uuid] then return nil, 0 end
		state.items[uuid] = {
			uuid = uuid, familyId = grant.familyId, slot = grant.slot, tier = state.act, rarity = rarity,
			baseStats = grant.baseStats, rolledLines = {}, temperLevel = 0, temperPityFailures = 0, cursed = false,
		}
		return { kind = "Gear", itemUuid = uuid }, 0
	end
	local resources = grant.resources
	for _, value in { resources.yen, resources.salvageShards, resources.materials, resources.holyWater } do
		if not Profile.integer(value, 0, Profile.Limit) then return nil, 0 end
	end
	for _, entry in grant.items do
		local quantity = (state.supplies[entry.itemId] or 0) + entry.quantity
		if entry.itemId == "" or not Profile.integer(entry.quantity, 1, Profile.Limit) or quantity > Profile.Limit then
			return nil, 0
		end
		state.supplies[entry.itemId] = quantity
	end
	state.salvageShards += resources.salvageShards
	state.materials += resources.materials
	state.holyWater += resources.holyWater
	return { kind = "Supplies", items = grant.items, resources = resources }, resources.yen
end

local function spin(
	state: Saved, yen: number, tierId: TierId, count: number, catalog: Catalog,
	roll: () -> number, makeId: () -> string
): (Contract.Receipt?, number, Contract.ErrorCode?, string?)
	local tier = config.Tiers[tierId]
	local spent = if count == 1 then tier.singleYen else tier.tenSpinYen
	if yen < spent then return nil, yen, "InsufficientResources", "Not enough Yen for this spin." end
	local remaining = yen - spent
	local pity = state.pity[tierId] or 0
	local results: { Contract.SpinResult } = {}
	state.items = table.clone(state.items)
	state.cosmetics = table.clone(state.cosmetics)
	state.supplies = table.clone(state.supplies)
	for _ = 1, count do
		-- Pay once at the batch price. The calculator handles each roll's rarity and pity.
		local rolled = Economy.spinDarbyParlor(tierId, tier.singleYen, pity, false, roll)
		if not rolled.ok or not rolled.bucket or not rolled.rarity then
			return nil, yen, "SaveUnavailable", "The Parlor could not settle this spin."
		end
		local bucket = rolled.bucket :: Contract.ParlorBucketId
		local grant = catalog(bucket, state.act, roll)
		local cosmeticBucket = bucket == "CommonCosmetic" or bucket == "RareCosmetic"
			or bucket == "EpicCosmetic" or bucket == "LegendaryCosmetic"
		if not grant or cosmeticBucket ~= (grant.kind == "Cosmetic")
			or (grant.kind == "Gear" and bucket ~= "RareSupplyCrate" and bucket ~= "EpicBaseGearCrate")
			or (bucket == "EpicBaseGearCrate" and grant.kind ~= "Gear") then
			return nil, yen, "SaveUnavailable", "This Parlor prize is unavailable."
		end
		local prize, addedYen = applyGrant(state, rolled.rarity, grant, makeId)
		if not prize then return nil, yen, "SaveUnavailable", "This Parlor prize is invalid." end
		remaining += addedYen
		table.insert(results, { bucketId = bucket, rarity = rolled.rarity, prize = prize, usedPity = pity + 1 >= tier.pityThreshold })
		pity = rolled.nextPityCounter
	end
	state.pity = table.clone(state.pity)
	state.pity[tierId] = pity
	return { kind = "Spun", tierId = tierId, spentYen = spent, results = results, pityCounter = pity }, remaining, nil, nil
end

return table.freeze({ views = views, spin = spin })
