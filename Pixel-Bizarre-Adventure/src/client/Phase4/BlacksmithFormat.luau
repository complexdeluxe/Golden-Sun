--!strict
-- Text for the Blacksmith panel. Display only: every number comes from the
-- server's snapshot or receipt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Contract = require(ReplicatedStorage.Shared.Contracts.Phase4EconomyTypes)
local Item = require(ReplicatedStorage.Shared.Contracts.ItemInstanceTypes)

local BlacksmithFormat = {}

BlacksmithFormat.MAX_TEMPER = 10

local STAT_SHORT: { [string]: string } = {
	Physical = "PHY",
	Special = "SPC",
	Defense = "DEF",
	Focus = "FOC",
	Speed = "SPD",
	Health = "HP",
	Stamina = "STA",
	Precision = "PRC",
	DefPen = "PEN",
}

-- { prefix, suffix } around the rolled value.
local AFFIX_TEXT: { [string]: { string } } = {
	flat_physical = { "+", " PHYSICAL" },
	flat_special = { "+", " SPECIAL" },
	flat_defense = { "+", " DEFENSE" },
	flat_focus = { "+", " FOCUS" },
	flat_speed = { "+", " SPEED" },
	precision_pp = { "+", "PP PRECISION" },
	control_resist_pp = { "+", "PP CONTROL RESIST" },
	def_pen_pp = { "+", "PP DEF PEN" },
	crit_pp = { "+", "PP CRIT" },
	cond_dmg_bleed = { "+", "% DMG VS BLEEDING" },
	proc_bleed_or_burn = { "", "% BLEED/BURN ON HIT" },
}

local function number(value: number): string
	if value % 1 == 0 then
		return tostring(value)
	end
	return string.format("%.1f", value)
end

function BlacksmithFormat.stats(lines: { Item.BaseStatLine }): string
	if #lines == 0 then
		return "NONE"
	end
	local parts: { string } = {}
	for _, line in lines do
		table.insert(parts, `{STAT_SHORT[line.statId] or string.upper(line.statId)} {number(line.value)}`)
	end
	return table.concat(parts, "  ")
end

function BlacksmithFormat.affix(line: Item.RolledLine): string
	local text = AFFIX_TEXT[line.affixId]
	if not text then
		return `{string.upper(line.affixId)} {number(line.value)}`
	end
	return text[1] .. number(line.value) .. text[2]
end

function BlacksmithFormat.cost(cost: Contract.Cost?): string
	if not cost then
		return ""
	end
	local parts: { string } = {}
	if cost.yen > 0 then
		table.insert(parts, `{cost.yen}Y`)
	end
	if cost.salvageShards > 0 then
		table.insert(parts, `{cost.salvageShards} SHARD`)
	end
	if cost.materials > 0 then
		table.insert(parts, `{cost.materials} MAT`)
	end
	if cost.holyWater > 0 then
		table.insert(parts, `{cost.holyWater} HOLY`)
	end
	return if #parts == 0 then "FREE" else table.concat(parts, " ")
end

function BlacksmithFormat.balances(balances: Contract.Balances): string
	return `{balances.salvageShards} SHARD  {balances.materials} MAT  {balances.holyWater} HOLY`
end

-- "TRAINING WRAPS +3", for list rows and titles.
function BlacksmithFormat.name(view: Contract.SmithItemView): string
	local label = string.upper(view.display.label)
	local level = view.item.temperLevel
	return if level > 0 then `{label} +{level}` else label
end

function BlacksmithFormat.tierLine(item: Item.ItemInstance): string
	local parts = { `T{item.tier}`, string.upper(item.rarity), string.upper(item.slot) }
	if item.cursed then
		table.insert(parts, "CURSED")
	end
	return table.concat(parts, "  ")
end

function BlacksmithFormat.temperLine(item: Item.ItemInstance): string
	return `TEMPER +{item.temperLevel}/+{BlacksmithFormat.MAX_TEMPER}   PITY {item.temperPityFailures}`
end

function BlacksmithFormat.nextTemper(preview: Contract.TemperPreview): string
	local nextLevel = preview.nextLevel
	if not nextLevel then
		return "MAX TEMPER REACHED"
	end
	local chance = preview.successChancePct or 0
	return `NEXT +{nextLevel}: {number(chance)}%  {BlacksmithFormat.cost(preview.cost)}`
end

-- A short line for the receipt the server committed.
function BlacksmithFormat.receipt(receipt: Contract.Receipt, label: string?): string
	local name = label or "ITEM"
	if receipt.kind == "OfferCreated" then
		return "NEW ROLL READY. ACCEPT OR KEEP."
	elseif receipt.kind == "OfferResolved" then
		return if receipt.decision == "AcceptNew" then "NEW AFFIXES APPLIED." else "KEPT THE OLD AFFIXES."
	elseif receipt.kind == "Tempered" then
		if receipt.succeeded then
			return `TEMPER SUCCESS! {name} IS NOW +{receipt.level}.`
		end
		return `TEMPER FAILED. STILL +{receipt.level}, PITY {receipt.pityFailures}.`
	elseif receipt.kind == "Purified" then
		return "PURIFIED. THE CURSE IS LIFTED."
	elseif receipt.kind == "Dismantled" then
		return `DISMANTLED FOR {receipt.salvageShards} SHARDS.`
	end
	return "DONE."
end

return BlacksmithFormat
