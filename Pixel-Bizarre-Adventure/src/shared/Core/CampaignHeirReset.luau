--!strict

local Bloodline = require("../Data/BloodlineTreeData")
local Campaign = require("./CampaignProfile")
local Economy = require("./Phase4Profile")
local Lineage = require("./SuccessionProfile")

type Row = Lineage.Row

local function apply(raw: Row, previous: Lineage.Saved, current: Lineage.Saved): Row?
	local newLife = previous.life.id ~= current.life.id
	local rank = current.ranks.family_purse or 0
	if not newLife and rank == (previous.ranks.family_purse or 0) then return raw end

	local record = Economy.decode(raw)
	if not record then return nil end
	local campaign = record.campaign
	local purseRank = campaign.progression.starterPurseRank
	if not newLife and (campaign.progression.lifeId ~= current.life.id or purseRank == nil or purseRank >= rank) then
		return raw
	end
	if record.campaignRevision >= Economy.Limit then return nil end
	local quote = Bloodline.FamilyPurseBonuses[rank]
	if not quote then return nil end

	local updated = table.clone(raw)
	local campaignFields = Lineage.fields(raw.campaign)
	local nextCampaign: Row = if campaignFields then table.clone(campaignFields) else {}
	local phase4 = table.clone(record.phase4)
	local progression = table.clone(campaign.progression)
	if newLife then
		local starter = assert(Campaign.decode(nil))
		nextCampaign.version = starter.version
		nextCampaign.appearance = campaign.appearance
		nextCampaign.stock, nextCampaign.gear, nextCampaign.belt = starter.stock, starter.gear, starter.belt
		nextCampaign.actOne = starter.actOne
		nextCampaign.f1 = nil -- Clear the legacy F1 fallback with the rest of the run.
		nextCampaign.yen = starter.yen + quote.yen
		progression = { clears = {}, lifeId = current.life.id, starterPurseRank = rank }
		phase4.act, phase4.salvageShards = 1, quote.salvageShards
		phase4.equippedGear, phase4.installs, phase4.equippedRoutines = {}, {}, {}
		phase4.goldenApple = false
	else
		local applied = Bloodline.FamilyPurseBonuses[assert(purseRank)]
		if not applied then return nil end
		local yen = campaign.yen + quote.yen - applied.yen
		local shards = phase4.salvageShards + quote.salvageShards - applied.salvageShards
		if not Economy.integer(yen, 0, Economy.Limit) or not Economy.integer(shards, 0, Economy.Limit) then return nil end
		nextCampaign.yen, phase4.salvageShards = yen, shards
		progression.starterPurseRank = rank
	end
	nextCampaign.progression = progression
	updated.campaign = nextCampaign
	updated.campaignWriteRevision = record.campaignRevision + 1
	-- The row clone retains account containers such as the Vault and Activity.
	-- Phase 4 keeps owned items, cosmetics, pity, and durable request receipts.
	updated.phase4 = phase4
	return updated
end

return table.freeze({ apply = apply })
