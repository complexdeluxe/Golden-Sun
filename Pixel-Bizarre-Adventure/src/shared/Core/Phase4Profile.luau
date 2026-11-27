--!strict

local Campaign = require("./CampaignProfile")
local Tutorial = require("./TutorialProgress")
local Progression = require("./CampaignProgression")
local Contract = require("../Contracts/Phase4EconomyTypes")
local Item = require("../Contracts/ItemInstanceTypes")
local Data = require("../Data/Phase4EconomyData")

export type Lease = { sessionId: string, expiresAt: number }
export type SavedReceipt = { signature: string, receipt: Contract.Receipt }
export type Saved = {
	version: number,
	revision: number,
	lease: Lease?,
	act: number,
	race: Data.RaceId,
	goldenApple: boolean,
	bloodlineTolerance: number,
	salvageShards: number,
	materials: number,
	holyWater: number,
	items: { [string]: Item.ItemInstance },
	equippedGear: { [string]: boolean },
	installs: { [Contract.CyberwareSite]: Contract.CyberwareInstall },
	equippedRoutines: { Contract.CyberwareRoutineId },
	cosmetics: { [string]: boolean },
	supplies: { [string]: number },
	pity: { [Contract.ParlorTierId]: number },
	receipts: { [string]: SavedReceipt },
}
export type Record = {
	raw: { [string]: unknown },
	phase4: Saved,
	campaign: Campaign.Profile,
	campaignRevision: number,
}

local LIMIT = 2 ^ 50
local function integer(value: unknown, min: number, max: number): boolean
	return type(value) == "number" and value >= min and value <= max and value % 1 == 0
end

local function empty(): Saved
	return {
		version = 1, revision = 0, act = 1, race = "Human", goldenApple = false, bloodlineTolerance = 0,
		salvageShards = 0, materials = 0, holyWater = 0,
		items = {}, equippedGear = {}, installs = {}, equippedRoutines = {},
		cosmetics = {}, supplies = {}, pity = {}, receipts = {},
	}
end

local function decode(value: unknown): Record?
	local tutorial = Tutorial.decode(value)
	if not tutorial then return nil end
	local raw: { [string]: unknown } =
		if value == nil then { version = tutorial.version, tutorialCompleted = tutorial.tutorialCompleted }
		else value :: { [string]: unknown }
	local campaign = Campaign.decode(raw.campaign)
	local campaignRevision = if raw.campaignWriteRevision == nil then 0 else raw.campaignWriteRevision
	if not campaign or not integer(campaignRevision, 0, LIMIT) or campaign.yen > LIMIT then return nil end
	local campaignAct = Progression.currentAct(campaign.progression, campaign.actOne.clears)
	local stored = raw.phase4
	if stored == nil then
		local phase4 = empty()
		phase4.act = campaignAct
		return { raw = raw, phase4 = phase4, campaign = campaign, campaignRevision = campaignRevision :: number }
	end
	if type(stored) ~= "table" then return nil end
	local fields = stored :: { [string]: unknown }
	if fields.version ~= 1 or not integer(fields.revision, 0, LIMIT)
		or not integer(fields.act, 1, 5) or type(fields.race) ~= "string"
		or not (Data.Cyberware.RacialTolerance :: { [string]: unknown })[fields.race]
		or type(fields.goldenApple) ~= "boolean" or not integer(fields.bloodlineTolerance, 0, LIMIT)
		or not integer(fields.salvageShards, 0, LIMIT) or not integer(fields.materials, 0, LIMIT)
		or not integer(fields.holyWater, 0, LIMIT) then return nil end
	for _, name in { "items", "equippedGear", "installs", "equippedRoutines", "cosmetics", "supplies", "pity", "receipts" } do
		if type(fields[name]) ~= "table" then return nil end
	end
	local lease = fields.lease
	if lease ~= nil then
		if type(lease) ~= "table" then return nil end
		local leaseFields = lease :: { [string]: unknown }
		if type(leaseFields.sessionId) ~= "string" or not integer(leaseFields.expiresAt, 0, LIMIT) then return nil end
	end
	-- Collections are written by trusted profile/grant code. Actions never supply these records.
		local phase4 = stored :: Saved
	if phase4.act < campaignAct then
		phase4 = table.clone(phase4)
		phase4.act = campaignAct
	end
	return { raw = raw, phase4 = phase4, campaign = campaign, campaignRevision = campaignRevision :: number }
end

local function encode(record: Record, phase4: Saved, yen: number): { [string]: unknown }
	local raw = table.clone(record.raw)
	raw.phase4 = phase4
	if yen ~= record.campaign.yen then
		-- Keep unknown and legacy campaign fields while updating the existing shared wallet.
		local previous = raw.campaign
		local campaign = if type(previous) == "table" then table.clone(previous :: { [string]: unknown })
			else table.clone(record.campaign) :: { [string]: unknown }
		campaign.yen = yen
		raw.campaign = campaign
		raw.campaignWriteRevision = record.campaignRevision + 1
	end
	return raw
end

return table.freeze({ decode = decode, encode = encode, integer = integer, Limit = LIMIT })
