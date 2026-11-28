--!strict
-- Text for the Activities screen. Display only: every amount, timer and
-- legality comes from the activity snapshot or receipt.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Contract = require(ReplicatedStorage.Shared.Contracts.ActivityTypes)

local ActivityFormat = {}

-- "+12 YEN  +2 SHARDS  +1 MAT". Zero parts are left out.
function ActivityFormat.bundle(bundle: Contract.CraftingBundle): string
	local parts: { string } = {}
	if bundle.yen > 0 then
		table.insert(parts, `+{bundle.yen} YEN`)
	end
	if bundle.salvageShards > 0 then
		table.insert(parts, `+{bundle.salvageShards} SHARD{if bundle.salvageShards == 1 then "" else "S"}`)
	end
	if bundle.materials > 0 then
		table.insert(parts, `+{bundle.materials} MAT`)
	end
	return if #parts == 0 then "NOTHING" else table.concat(parts, "  ")
end

-- "4:00:00", "12:05", "0:09". Negative values read as zero.
function ActivityFormat.clock(seconds: number): string
	local whole = math.max(0, math.floor(seconds))
	local hours = whole // 3600
	local minutes = (whole % 3600) // 60
	local rest = whole % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, rest)
	end
	return string.format("%d:%02d", minutes, rest)
end

-- "4 HOURS", "5 MIN".
function ActivityFormat.duration(seconds: number): string
	if seconds >= 3600 and seconds % 3600 == 0 then
		local hours = seconds // 3600
		return `{hours} HOUR{if hours == 1 then "" else "S"}`
	end
	return `{math.max(1, math.floor(seconds / 60))} MIN`
end

-- A short name for an action the player sent, for example while its reply is
-- unconfirmed.
function ActivityFormat.action(action: Contract.Action): string
	if action.kind == "StartAutoBattle" then
		return `START AUTO-BATTLE ACT {action.act}`
	elseif action.kind == "ClaimAutoBattle" then
		return "CLAIM AUTO-BATTLE"
	elseif action.kind == "StopAutoBattle" then
		return "STOP AUTO-BATTLE"
	elseif action.kind == "DispatchExpedition" then
		return `DISPATCH ACT {action.act}`
	elseif action.kind == "ClaimExpedition" then
		return "CLAIM EXPEDITION"
	end
	return "LAST ACTION"
end

-- A short line for a committed receipt.
function ActivityFormat.receipt(receipt: Contract.Receipt): string
	if receipt.kind == "AutoBattleStarted" then
		return `AUTO-BATTLE STARTED IN ACT {receipt.act}.`
	elseif receipt.kind == "AutoBattleClaimed" then
		return `CLAIMED {receipt.ticksClaimed} TICK{if receipt.ticksClaimed == 1 then "" else "S"}: {ActivityFormat.bundle(receipt.rewards)}`
	elseif receipt.kind == "AutoBattleStopped" then
		return "AUTO-BATTLE STOPPED."
	elseif receipt.kind == "ExpeditionDispatched" then
		return `ACT {receipt.act} EXPEDITION DISPATCHED.`
	elseif receipt.kind == "ExpeditionClaimed" then
		return `EXPEDITION CLAIMED: {ActivityFormat.bundle(receipt.rewards)}`
	end
	return "DONE."
end

return ActivityFormat
