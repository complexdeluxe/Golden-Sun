--!strict

local Combat = require("../src/shared/Contracts/CombatTypes")
local Remote = require("../src/shared/Contracts/RemoteContract")
local Succession = require("../src/shared/Contracts/SuccessionTypes")

local allowed: Combat.ActionLegality = { canUse = true }
local maxed: Combat.ActionLegality = { canUse = false, disabledReason = "Maximum rank reached" }
local catalog: { [Succession.BloodlineNodeId]: { label: string, maxRank: number, firstCost: number, description: string } } = {
	family_purse = { label = "Family Purse", maxRank = 3, firstCost = 20, description = "New-life Yen and salvage shards." },
	early_conditioning = { label = "Early Conditioning", maxRank = 3, firstCost = 25, description = "Early stats within the same level 50 cap." },
	speedwagon_contacts = { label = "Speedwagon Contacts", maxRank = 2, firstCost = 40, description = "Hub contacts and improved restock caps." },
	quartermaster_dispatch = { label = "Quartermaster Dispatch", maxRank = 1, firstCost = 60, description = "One more stored expedition ticket." },
	bloodline_vault = { label = "Bloodline Vault Expansion", maxRank = 3, firstCost = 20, description = "Permanent vault slots." },
	resonance_attunement = { label = "Resonance Attunement", maxRank = 2, firstCost = 35, description = "More shards from eligible clears." },
	tactical_breadth = { label = "Tactical Breadth", maxRank = 1, firstCost = 85, description = "One move slot within the global cap." },
	dual_heirloom_satchel = { label = "Dual Heirloom Satchel", maxRank = 1, firstCost = 90, description = "Carry two and attune one." },
	bloodline_longevity = { label = "Bloodline Longevity", maxRank = 3, firstCost = 20, description = "Later natural death age." },
	veteran_composure = { label = "Veteran Composure", maxRank = 1, firstCost = 65, description = "Softer Elder penalties." },
	chrome_resilience = { label = "Chrome Resilience", maxRank = 2, firstCost = 35, description = "Race-specific tolerance or aging benefits." },
}

local branches: { Succession.BloodlineBranchView } = {}
local seen: { [Succession.BloodlineNodeId]: boolean } = {}
local count, ranks = 0, 0
for _, branch in Succession.BloodlineBranchOrder do
	local nodes: { Succession.BloodlineNodeView } = {}
	for _, id in Succession.BloodlineNodeIds[branch] do
		assert(not seen[id])
		seen[id] = true
		local spec = catalog[id]
		local purchased = id == "dual_heirloom_satchel" or id == "veteran_composure"
		count += 1
		ranks += spec.maxRank
		table.insert(nodes, {
			nodeId = id, label = spec.label, maxRank = spec.maxRank, rank = if purchased then 1 else 0,
			nextCostEchoes = if purchased then nil else spec.firstCost,
			description = spec.description, legality = if purchased then maxed else allowed,
		})
	end
	table.insert(branches, { branchId = branch, nodes = nodes })
end
assert(#branches == 3 and count == 11 and ranks == 22)
assert(branches[1].nodes[1].nodeId == "family_purse" and branches[1].nodes[1].nextCostEchoes == 20)
assert(branches[2].nodes[4].nodeId == "dual_heirloom_satchel" and branches[2].nodes[4].nextCostEchoes == nil)

local snapshot: Succession.Snapshot = {
	sessionId = "lineage-session", revision = 12, lifeId = "life-4", generation = 4,
	age = {
		currentAge = 63, elderThreshold = Succession.ElderThreshold, naturalDeathAge = 90,
		isElder = true, veteranComposureActive = true, upcomingAgeDelta = 1,
	},
	recoveryLedger = {
		recoveriesRemaining = 0, maxRecoveries = Succession.MaxRecoveries, isFinalAttempt = true,
		act5Vested = true, eligibleEchoes = 80, retireNowEchoes = 112, terminalFallbackEchoes = 112,
		canRetireNow = true, ledgerSettled = false,
	},
	bloodlineTree = { echoesBalance = 65, branches = branches },
	heirlooms = {
		catalog = {
			{ id = "heirloom-a", label = "Pocket Watch", description = "A keepsake from the first journey.", iconKey = "PocketWatchIcon" },
			{ id = "heirloom-b", label = "Family Crest", description = "A crest handed down through the bloodline." },
			{ id = "heirloom-c", label = "Travel Journal", description = "Notes from a previous life." },
		},
		unlockedIds = { "heirloom-a", "heirloom-b", "heirloom-c" },
		carriedIds = { "heirloom-a", "heirloom-b" }, attunedId = "heirloom-b",
		carryLimit = Succession.MaxHeirloomCarryLimit, legality = allowed,
	},
	mastery = {
		{ kitId = "kit-a", marks = 0, unlockedAltTarget = false, targetMode = "Default", utilityVariant = "Default", masteryTitleUnlocked = false },
		{ kitId = "kit-b", marks = 2, unlockedAltTarget = true, targetMode = "Alt", utilityVariant = "Default", masteryTitleUnlocked = false },
		{ kitId = "kit-c", marks = 5, unlockedAltTarget = true, targetMode = "Default", utilityVariant = "Alt", masteryTitleUnlocked = false },
		{ kitId = "kit-d", marks = 8, unlockedAltTarget = true, targetMode = "Alt", utilityVariant = "Alt", masteryTitleUnlocked = true },
	},
}
local function get(_: Remote.GetLineageSnapshotRequest): Remote.LineageSnapshotResponse
	return { ok = true, snapshot = snapshot }
end
local restored = get({})
assert(restored.ok)
assert(restored.snapshot.age.elderThreshold == 56 and restored.snapshot.age.naturalDeathAge == 90)
assert(restored.snapshot.recoveryLedger.maxRecoveries == 5 and restored.snapshot.recoveryLedger.isFinalAttempt)
assert(restored.snapshot.recoveryLedger.terminalFallbackEchoes == restored.snapshot.recoveryLedger.retireNowEchoes)
assert(#restored.snapshot.heirlooms.carriedIds == 2 and restored.snapshot.heirlooms.attunedId == "heirloom-b")
assert(restored.snapshot.heirlooms.catalog[1].id == restored.snapshot.heirlooms.carriedIds[1])
assert(restored.snapshot.heirlooms.catalog[1].iconKey == "PocketWatchIcon" and restored.snapshot.heirlooms.catalog[2].iconKey == nil)
assert(restored.snapshot.mastery[2].marks == Succession.MasteryAltTargetMarks)
assert(restored.snapshot.mastery[2].targetMode == "Alt" and restored.snapshot.mastery[2].utilityVariant == "Default")
assert(restored.snapshot.mastery[3].marks == Succession.MasteryUtilityVariantMarks)
assert(restored.snapshot.mastery[3].targetMode == "Default" and restored.snapshot.mastery[3].utilityVariant == "Alt")
assert(restored.snapshot.mastery[4].marks == Succession.MasteryTitleMarks)

local cases: { { action: Succession.Action, receipt: Succession.Receipt } } = {
	{
		action = { kind = "PurchaseBloodlineNode", nodeId = "family_purse" },
		receipt = { kind = "BloodlineNodePurchased", nodeId = "family_purse", rank = 1, spentEchoes = 20 },
	},
	{
		action = { kind = "PassTheTorch", lifeId = "life-4", confirmed = true },
		receipt = { kind = "PassedTheTorch", retiredLifeId = "life-4", nextLifeId = "life-5", echoesAwarded = 112 },
	},
	{
		action = { kind = "SetCarriedHeirlooms", heirloomIds = { "heirloom-a" } },
		receipt = { kind = "CarriedHeirloomsSet", heirloomIds = { "heirloom-a" }, attunedId = nil },
	},
	{
		action = { kind = "SetAttunedHeirloom" },
		receipt = { kind = "AttunedHeirloomSet" },
	},
	{
		action = { kind = "SetMasteryVariant", kitId = "kit-c", variant = "Alt" },
		receipt = { kind = "MasteryVariantSet", kitId = "kit-c", variant = "Alt" },
	},
	{
		action = { kind = "SetMasteryTargetMode", kitId = "kit-b", targetMode = "Alt" },
		receipt = { kind = "MasteryTargetModeSet", kitId = "kit-b", targetMode = "Alt" },
	},
}
for _, case in cases do
	local request: Remote.LineageActionRequest = {
		sessionId = snapshot.sessionId, expectedRevision = snapshot.revision,
		requestId = "lineage-fixture-" .. case.action.kind, action = case.action,
	}
	local reply: Remote.LineageActionResponse = {
		ok = true, requestId = request.requestId, receipt = case.receipt, snapshot = snapshot,
	}
	assert(reply.ok and reply.requestId == request.requestId and reply.receipt.kind == case.receipt.kind)
end

local finalAttempt: Remote.LineageActionResponse = {
	ok = false, code = "FinalAttemptConfirmRequired", message = "Defeat ends this generation.", snapshot = snapshot,
}
local settled: Remote.LineageActionResponse = {
	ok = false, code = "AlreadySettled", message = "This life already settled.", requestId = "lineage-fixture-PassTheTorch",
}
assert(not finalAttempt.ok and finalAttempt.snapshot == snapshot and not settled.ok)
assert(Remote.Lineage.FolderName == "LineageRemotes")
assert(Remote.Lineage.GetLineageSnapshot.name == "GetLineageSnapshot" and Remote.Lineage.GetLineageSnapshot.className == "RemoteFunction")
assert(Remote.Lineage.SubmitLineageAction.name == "SubmitLineageAction" and Remote.Lineage.SubmitLineageAction.className == "RemoteFunction")
print("Phase 5 contracts passed: age, recoveries, 11 bloodline nodes, heirlooms, mastery, and lineage requests and receipts")
