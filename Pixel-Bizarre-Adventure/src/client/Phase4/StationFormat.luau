--!strict
-- Text shared by the Phase 4 Hub stations (Blacksmith, Cyberware Clinic and
-- D'Arby's Parlor). Display only: every number comes from the server's
-- snapshot or receipt.
--
-- The three stations share one Phase4Client, so a reply can settle an earlier
-- unconfirmed action from another station. `receipt` describes any receipt
-- kind for that reason.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Contract = require(ReplicatedStorage.Shared.Contracts.Phase4EconomyTypes)
local BlacksmithFormat = require(script.Parent.BlacksmithFormat)

type Snapshot = Contract.Snapshot

local StationFormat = {}

StationFormat.SITE_ORDER = { "HeadOptics", "Neural", "TorsoChassis", "Limbs", "HeartCore" } :: { Contract.CyberwareSite }
StationFormat.ROUTINE_ORDER = {
	"UVBeam", "TacticalSurge", "SuppressiveVolley", "SeismicGrip", "EmergencyOverride",
} :: { Contract.CyberwareRoutineId }

local SITE_LABEL: { [string]: string } = {
	HeadOptics = "HEAD OPTICS",
	Neural = "NEURAL",
	TorsoChassis = "TORSO CHASSIS",
	Limbs = "LIMBS",
	HeartCore = "HEART CORE",
}

local ROUTINE_LABEL: { [string]: string } = {
	UVBeam = "UV BEAM",
	TacticalSurge = "TACTICAL SURGE",
	SuppressiveVolley = "SUPPRESSIVE VOLLEY",
	SeismicGrip = "SEISMIC GRIP",
	EmergencyOverride = "EMERGENCY OVERRIDE",
}

-- Fits a 42 px toggle.
local ROUTINE_SHORT: { [string]: string } = {
	UVBeam = "UV",
	TacticalSurge = "SURGE",
	SuppressiveVolley = "VOLLEY",
	SeismicGrip = "GRIP",
	EmergencyOverride = "OVRD",
}

local BUCKET_LABEL: { [string]: string } = {
	CommonCraftingCrate = "CRAFTING CRATE",
	CommonCosmetic = "COSMETIC",
	RareSupplyCrate = "SUPPLY CRATE",
	EpicCosmetic = "COSMETIC",
	LegendaryCosmetic = "COSMETIC",
	RareCraftingCrate = "CRAFTING CRATE",
	RareCosmetic = "COSMETIC",
	EpicBaseGearCrate = "BASE GEAR CRATE",
}

-- "gold_hat" or "GoldHat" -> "GOLD HAT".
function StationFormat.idText(id: string): string
	local spaced = string.gsub(id, "_", " ")
	spaced = string.gsub(spaced, "(%l)(%u)", "%1 %2")
	return string.upper(spaced)
end

function StationFormat.site(site: string): string
	return SITE_LABEL[site] or StationFormat.idText(site)
end

function StationFormat.routine(id: string): string
	return ROUTINE_LABEL[id] or StationFormat.idText(id)
end

function StationFormat.routineShort(id: string): string
	return ROUTINE_SHORT[id] or string.sub(StationFormat.idText(id), 1, 5)
end

function StationFormat.routineList(ids: { Contract.CyberwareRoutineId }): string
	if #ids == 0 then
		return "NONE"
	end
	local parts: { string } = {}
	for _, id in ids do
		table.insert(parts, StationFormat.routine(id))
	end
	return table.concat(parts, ", ")
end

function StationFormat.bucket(bucketId: string): string
	return BUCKET_LABEL[bucketId] or StationFormat.idText(bucketId)
end

-- Odds are server percentages. Keep up to two decimals without trailing zeros.
function StationFormat.percent(value: number): string
	local rounded = math.round(value * 100) / 100
	if rounded % 1 == 0 then
		return `{rounded}%`
	end
	local text = string.format("%.2f", rounded)
	text = string.gsub(text, "0$", "")
	return text .. "%"
end

function StationFormat.cost(cost: Contract.Cost?): string
	return BlacksmithFormat.cost(cost)
end

local function gearLabel(snapshot: Snapshot?, uuid: string): string?
	if not snapshot then
		return nil
	end
	for _, view in snapshot.smithItems do
		if view.item.uuid == uuid then
			return string.upper(view.display.label)
		end
	end
	return nil
end

-- Non-zero resources as "+12 SHARD +3 MAT".
local function resources(balances: Contract.Balances): string
	local parts: { string } = {}
	if balances.yen > 0 then
		table.insert(parts, `+{balances.yen}Y`)
	end
	if balances.salvageShards > 0 then
		table.insert(parts, `+{balances.salvageShards} SHARD`)
	end
	if balances.materials > 0 then
		table.insert(parts, `+{balances.materials} MAT`)
	end
	if balances.holyWater > 0 then
		table.insert(parts, `+{balances.holyWater} HOLY`)
	end
	return table.concat(parts, " ")
end

-- One line for a Parlor prize. `snapshot` names won gear when it is listed.
function StationFormat.prize(prize: Contract.SpinPrize, snapshot: Snapshot?): string
	if prize.kind == "Cosmetic" then
		return `NEW COSMETIC {StationFormat.idText(prize.cosmeticId)}`
	elseif prize.kind == "DuplicateCosmetic" then
		return `DUPE {StationFormat.idText(prize.cosmeticId)} +{prize.shardRefund} SHARD`
	elseif prize.kind == "Gear" then
		return `GEAR {gearLabel(snapshot, prize.itemUuid) or "NEW ITEM"}`
	end
	local parts: { string } = {}
	for _, entry in prize.items do
		table.insert(parts, `{entry.quantity}x {StationFormat.idText(entry.itemId)}`)
	end
	local extra = resources(prize.resources)
	if extra ~= "" then
		table.insert(parts, extra)
	end
	return if #parts == 0 then "SUPPLIES" else table.concat(parts, " ")
end

-- Total duplicate-cosmetic shard refunds in a batch.
function StationFormat.refundTotal(results: { Contract.SpinResult }): number
	local total = 0
	for _, result in results do
		local prize = result.prize
		if prize.kind == "DuplicateCosmetic" then
			total += prize.shardRefund
		end
	end
	return total
end

local TIER_LABEL: { [string]: string } = { standard_chip = "STANDARD", high_roller_chip = "HIGH-ROLLER" }

-- A short name for an action the player sent, for example while its reply is
-- unconfirmed: "1 SPIN STANDARD", "REMOVE HEAD OPTICS".
function StationFormat.action(action: Contract.Action): string
	if action.kind == "Spin" then
		local tier = TIER_LABEL[action.tierId] or StationFormat.idText(action.tierId)
		return `{action.count} SPIN{if action.count == 1 then "" else "S"} {tier}`
	elseif action.kind == "InstallCyberware" then
		return `INSTALL T{action.tier} {StationFormat.site(action.site)}`
	elseif action.kind == "RemoveCyberware" then
		return `REMOVE {StationFormat.site(action.site)}`
	elseif action.kind == "SetEquippedRoutines" then
		return "EQUIP ROUTINES"
	elseif action.kind == "CreateOffer" then
		return "REROLL"
	elseif action.kind == "ResolveOffer" then
		return if action.decision == "AcceptNew" then "ACCEPT NEW ROLL" else "KEEP OLD ROLL"
	elseif action.kind == "Temper" then
		return "TEMPER"
	elseif action.kind == "Purify" then
		return "PURIFY"
	elseif action.kind == "Dismantle" then
		return "SALVAGE"
	end
	return "LAST ACTION"
end

-- A short line for any receipt the server committed.
function StationFormat.receipt(receipt: Contract.Receipt, label: string?): string
	if receipt.kind == "CyberwareInstalled" then
		return `INSTALLED T{receipt.install.tier} {StationFormat.site(receipt.install.site)}.`
	elseif receipt.kind == "CyberwareRemoved" then
		return `REMOVED THE {StationFormat.site(receipt.site)} IMPLANT.`
	elseif receipt.kind == "EquippedRoutinesSet" then
		return `ROUTINES SET: {StationFormat.routineList(receipt.routineIds)}.`
	elseif receipt.kind == "Spun" then
		local count = #receipt.results
		local refund = StationFormat.refundTotal(receipt.results)
		local text = `{count} SPIN{if count == 1 then "" else "S"} FOR {receipt.spentYen}Y.`
		return if refund > 0 then `{text} DUPES +{refund} SHARD.` else text
	end
	return BlacksmithFormat.receipt(receipt, label)
end

return StationFormat
