--!strict
-- Text for the Hall of Ancestors. Display only: every number, label,
-- description and legality comes from the lineage snapshot or receipt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Contract = require(ReplicatedStorage.Shared.Contracts.SuccessionTypes)

local LineageFormat = {}

local BRANCH_LABEL: { [string]: string } = {
	Momentum = "MOMENTUM",
	LegacyLoadout = "LEGACY LOADOUT",
	VitalityGrit = "VITALITY & GRIT",
}

function LineageFormat.branch(id: string): string
	return BRANCH_LABEL[id] or string.upper(id)
end

-- "stand_origin" -> "STAND ORIGIN".
function LineageFormat.kit(id: string): string
	return string.upper((string.gsub(id, "[_%-]", " ")))
end

function LineageFormat.variant(value: Contract.MasteryVariant): string
	return if value == "Alt" then "ALT" else "DEFAULT"
end

-- The heirloom's server label, or its ID when the catalog lacks it.
function LineageFormat.heirloom(snapshot: Contract.Snapshot, id: string): string
	for _, entry in snapshot.heirlooms.catalog do
		if entry.id == id then
			return string.upper(entry.label)
		end
	end
	return string.upper((string.gsub(id, "_", " ")))
end

function LineageFormat.heirloomList(snapshot: Contract.Snapshot, ids: { string }): string
	if #ids == 0 then
		return "NONE"
	end
	local names: { string } = {}
	for _, id in ids do
		table.insert(names, LineageFormat.heirloom(snapshot, id))
	end
	return table.concat(names, ", ")
end

function LineageFormat.nodeLabel(snapshot: Contract.Snapshot?, id: string): string
	if snapshot then
		for _, branch in snapshot.bloodlineTree.branches do
			for _, node in branch.nodes do
				if node.nodeId == id then
					return string.upper(node.label)
				end
			end
		end
	end
	return string.upper((string.gsub(id, "_", " ")))
end

-- A short name for an action the player sent, for example while its reply is
-- unconfirmed.
function LineageFormat.action(action: Contract.Action, snapshot: Contract.Snapshot?): string
	if action.kind == "PurchaseBloodlineNode" then
		return `BUY {LineageFormat.nodeLabel(snapshot, action.nodeId)}`
	elseif action.kind == "PassTheTorch" then
		return "PASS THE TORCH"
	elseif action.kind == "SetCarriedHeirlooms" then
		return "CARRY HEIRLOOMS"
	elseif action.kind == "SetAttunedHeirloom" then
		return if action.heirloomId then "ATTUNE HEIRLOOM" else "CLEAR ATTUNEMENT"
	elseif action.kind == "SetMasteryVariant" then
		return `{LineageFormat.kit(action.kitId)} UTILITY`
	elseif action.kind == "SetMasteryTargetMode" then
		return `{LineageFormat.kit(action.kitId)} TARGET`
	end
	return "LAST ACTION"
end

-- A short line for a committed receipt.
function LineageFormat.receipt(receipt: Contract.Receipt, snapshot: Contract.Snapshot?): string
	if receipt.kind == "BloodlineNodePurchased" then
		return `{LineageFormat.nodeLabel(snapshot, receipt.nodeId)} RANK {receipt.rank}. -{receipt.spentEchoes} ECHOES.`
	elseif receipt.kind == "PassedTheTorch" then
		return `TORCH PASSED. +{receipt.echoesAwarded} ECHOES.`
	elseif receipt.kind == "CarriedHeirloomsSet" then
		return `CARRYING {#receipt.heirloomIds} HEIRLOOM{if #receipt.heirloomIds == 1 then "" else "S"}.`
	elseif receipt.kind == "AttunedHeirloomSet" then
		local id = receipt.heirloomId
		if id and snapshot then
			return `ATTUNED {LineageFormat.heirloom(snapshot, id)}.`
		end
		return if id then "HEIRLOOM ATTUNED." else "ATTUNEMENT CLEARED."
	elseif receipt.kind == "MasteryVariantSet" then
		return `{LineageFormat.kit(receipt.kitId)} UTILITY {LineageFormat.variant(receipt.variant)}.`
	elseif receipt.kind == "MasteryTargetModeSet" then
		return `{LineageFormat.kit(receipt.kitId)} TARGET {LineageFormat.variant(receipt.targetMode)}.`
	end
	return "DONE."
end

return LineageFormat
