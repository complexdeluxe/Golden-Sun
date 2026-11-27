--!strict

local Progression = require("./CampaignProgression")
local Succession = require("./SuccessionSession")
local Activity = require("./ActivitySession")

type LineageController = typeof(Succession.new((nil :: any), (nil :: any)))
type ActivityController = typeof(Activity.new((nil :: any), (nil :: any)))

local heirloomForPart = table.freeze({
	"zeppelis_checkered_hat", "caesars_headband", "jotaros_torn_cap", "josukes_peace_pin", "brunos_zipper_brooch",
})

local function new(lineage: LineageController, activity: ActivityController): Progression.Bridge
	local function life(userId: number, beginNext: boolean?): Progression.Life?
		local reply = lineage.GetLineageSnapshot(userId)
		if not reply.ok then return nil end
		local snapshot = reply.snapshot
		if beginNext and snapshot.recoveryLedger.ledgerSettled then
			local heir = lineage.beginNextLife(userId, snapshot.lifeId)
			if not heir.ok then return nil end
			snapshot = heir.snapshot
		end
		return { id = snapshot.lifeId, settled = snapshot.recoveryLedger.ledgerSettled,
			isFinalAttempt = snapshot.recoveryLedger.isFinalAttempt }
	end

	local function apply(userId: number, event: Progression.Event): boolean
		local current = life(userId)
		if not current or current.id ~= event.lifeId then return false end
		local id, lifeId = event.battleId, event.lifeId
		local castle = event.nodeId == "Castle"
		if event.outcome == "Defeat" then
			return lineage.recordCastleWipe(userId, {
				lifeId = lifeId, eventId = id, act = event.act, encounterKind = "Castle",
				mode = "FirstClear", fullPartyWipe = true,
			}).ok
		end

		-- Each hook is keyed independently. The campaign outbox can replay after
		-- a failed save of any one hook, or after a lost acknowledgement.
		if castle then
			if not lineage.recordActClear(userId, lifeId, event.act, "FirstClear").ok then return false end
			if not lineage.unlockHeirloom(userId, lifeId, heirloomForPart[event.part]).ok then return false end
		end
		if castle or event.nodeId:sub(1, 1) == "D" then
			if event.kitId and not lineage.awardMasteryMark(userId, {
				lifeId = lifeId, kitId = event.kitId,
				eventId = "part:" .. event.part .. ":" .. event.nodeId, mode = "FirstClear",
			}).ok then return false end
			-- Activity reads Auto-Battle eligibility directly from Lineage's
			-- committed Act milestones. Ticket issuance has its own durable ID.
			if not activity.GetActivitySnapshot(userId).ok or not activity.grantExpeditionTicket(userId, id) then return false end
		end
		-- Apply age last so the milestone and rewards are vested before old age
		-- can settle the ledger. The age event is itself replay-safe.
		return lineage.advanceAge(userId, lifeId, id, event.years).ok
	end

	return { life = life, apply = apply }
end

return table.freeze({ new = new })
