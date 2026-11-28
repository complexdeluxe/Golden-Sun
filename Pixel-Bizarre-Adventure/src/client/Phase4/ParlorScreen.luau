--!strict
-- D'Arby's Hub Parlor, opened from the Hub. Draws over the whole Hub.
--
-- Pick a chip tier (Standard or High-Roller), see its price, normal odds, pity
-- odds and pity counter, then spin once or ten times. The server settles the
-- price, every roll and the pity counter before it replies. The results are
-- then revealed one at a time in receipt order, including duplicate cosmetic
-- shard refunds.
--
-- Layout (body px, the body starts at y 16):
--   chips      2..100   tier selector, prices, pity, spin buttons
--   detail     104..316 odds table, revealed results

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Contract = require(ReplicatedStorage.Shared.Contracts.Phase4EconomyTypes)
local CombatTypes = require(ReplicatedStorage.Shared.Contracts.CombatTypes)
local PixelUi = require(script.Parent.Parent.Battle.PixelUi)
local CampaignUi = require(script.Parent.Parent.Campaign.CampaignUi)
local StationShell = require(script.Parent.StationShell)
local Format = require(script.Parent.StationFormat)

type Snapshot = Contract.Snapshot
type TierView = Contract.ParlorTierView
type TierId = Contract.ParlorTierId
type Legality = CombatTypes.ActionLegality

local Colors = PixelUi.Colors
local Palette = CampaignUi.Colors

local DETAIL_X = 104
local DETAIL_W = 212
local ODDS_ROWS = 5
local RESULT_ROWS = 10
local REVEAL_SECONDS = 0.18
local TIER_ORDER: { TierId } = { "standard_chip", "high_roller_chip" }
local TIER_BUTTON: { [string]: string } = { standard_chip = "STANDARD", high_roller_chip = "HIGH-ROLLER" }

local RARITY_COLOR: { [string]: Color3 } = {
	Common = Colors.TextDim,
	Rare = Colors.Guard,
	Epic = Palette.Purple,
	Legendary = Palette.Gold,
}
local RARITY_SHORT: { [string]: string } = { Common = "COM", Rare = "RARE", Epic = "EPIC", Legendary = "LEG" }

export type Parlor = {
	destroy: (self: Parlor) -> (),
}

local ParlorScreen = {}

function ParlorScreen.open(parent: Instance, deps: StationShell.Deps): Parlor
	local shell = StationShell.open(parent, deps, {
		name = "Parlor",
		title = "D'ARBY'S PARLOR",
		loadingText = "TAKING A SEAT AT THE PARLOR...",
		failText = "D'Arby won't take that bet.",
		balances = function(balances: Contract.Balances): string
			return `{balances.salvageShards} SHARD`
		end,
		-- A recovered spin reveals its original prizes here.
		recovers = { Spun = true },
	})
	local body = shell.body

	-- Chips ---------------------------------------------------------------------
	PixelUi.label(body, "ChipTitle", 2, 0, 98, 9, "CHIP", Palette.Gold)
	local tierButtons: { [TierId]: CampaignUi.Button } = {}
	for i, id in TIER_ORDER do
		tierButtons[id] = CampaignUi.button(body, `Tier{i}`, 2, 10 + (i - 1) * 14, 98, 13, TIER_BUTTON[id])
	end
	local singlePrice = PixelUi.label(body, "Single", 2, 40, 98, 9, "", Colors.Text)
	local tenPrice = PixelUi.label(body, "Ten", 2, 49, 98, 9, "", Colors.Text)
	PixelUi.label(body, "PityTitle", 2, 61, 50, 9, "PITY", Palette.Gold)
	local pityValue = PixelUi.label(body, "PityValue", 50, 61, 50, 9, "", Colors.Text, Enum.TextXAlignment.Right)
	local _, setPity = PixelUi.bar(body, "PityBar", 2, 71, 98, 6, Palette.Gold, Palette.GoldDark)
	local pityHint = PixelUi.label(body, "PityHint", 2, 79, 98, 18, "", Colors.TextDim)
	pityHint.TextWrapped = true
	pityHint.TextYAlignment = Enum.TextYAlignment.Top
	local spinOne = CampaignUi.button(body, "SpinOne", 2, 100, 47, 18, "SPIN x1")
	local spinTen = CampaignUi.button(body, "SpinTen", 53, 100, 47, 18, "SPIN x10")
	local spinHint = PixelUi.label(body, "SpinHint", 2, 120, 98, 20, "", Colors.Hp)
	spinHint.TextWrapped = true
	spinHint.TextYAlignment = Enum.TextYAlignment.Top

	-- Odds ----------------------------------------------------------------------
	local detail = PixelUi.frame(body, "Detail", DETAIL_X, 0, DETAIL_W, 164)
	local oddsTitle = PixelUi.label(detail, "OddsTitle", 0, 0, 130, 9, "", Palette.Gold)
	PixelUi.label(detail, "NormalHead", 130, 0, 40, 9, "NORMAL", Colors.TextDim, Enum.TextXAlignment.Right)
	PixelUi.label(detail, "PityHead", 172, 0, 40, 9, "PITY", Colors.TextDim, Enum.TextXAlignment.Right)
	type OddsRow = { rarity: TextLabel, bucket: TextLabel, normal: TextLabel, pity: TextLabel }
	local oddsRows: { OddsRow } = {}
	for i = 1, ODDS_ROWS do
		local y = 9 + (i - 1) * 8
		oddsRows[i] = {
			rarity = PixelUi.label(detail, `Rarity{i}`, 0, y, 30, 8, "", Colors.Text),
			bucket = PixelUi.label(detail, `Bucket{i}`, 30, y, 100, 8, "", Colors.Text),
			normal = PixelUi.label(detail, `Normal{i}`, 130, y, 40, 8, "", Colors.Text, Enum.TextXAlignment.Right),
			pity = PixelUi.label(detail, `Pity{i}`, 172, y, 40, 8, "", Colors.Text, Enum.TextXAlignment.Right),
		}
	end

	-- Results -------------------------------------------------------------------
	PixelUi.frame(detail, "Rule", 0, 50, DETAIL_W, 1, Palette.Purple)
	local resultTitle = PixelUi.label(detail, "ResultTitle", 0, 52, 100, 9, "RESULTS", Palette.Gold)
	local resultSummary = PixelUi.label(detail, "ResultSummary", 100, 52, 112, 9, "", Colors.TextDim, Enum.TextXAlignment.Right)
	type ResultRow = { index: TextLabel, rarity: TextLabel, prize: TextLabel, pity: TextLabel }
	local resultRows: { ResultRow } = {}
	for i = 1, RESULT_ROWS do
		local y = 61 + (i - 1) * 9
		resultRows[i] = {
			index = PixelUi.label(detail, `Index{i}`, 0, y, 14, 9, "", Colors.TextDim),
			rarity = PixelUi.label(detail, `ResultRarity{i}`, 14, y, 28, 9, "", Colors.Text),
			prize = PixelUi.label(detail, `Prize{i}`, 42, y, 146, 9, "", Colors.Text),
			pity = PixelUi.label(detail, `UsedPity{i}`, 188, y, 24, 9, "", Palette.Gold, Enum.TextXAlignment.Right),
		}
	end
	local statusLine = PixelUi.label(detail, "Status", 0, 153, DETAIL_W, 9, "", Colors.TextDim)

	local selected: TierId = TIER_ORDER[1]
	-- The latest batch, revealed `revealed` results at a time.
	local batch: { tierId: TierId, spentYen: number, results: { Contract.SpinResult }, recovered: boolean }? = nil
	local revealed = 0
	local revealing = false
	-- Snapshot used to name won gear, captured with the batch.
	local batchSnapshot: Snapshot? = nil

	local function tierFor(snapshot: Snapshot, id: TierId): TierView?
		for _, tier in snapshot.parlorTiers do
			if tier.tierId == id then
				return tier
			end
		end
		return nil
	end

	-- The ten-spin batch has its own price. Its legality follows from the
	-- server's price and balance; the server still decides.
	local function tenLegality(snapshot: Snapshot, tier: TierView): Legality
		if not tier.legality.canUse then
			return tier.legality
		end
		if snapshot.balances.yen < tier.tenSpinYen then
			return { canUse = false, disabledReason = "Not enough Yen for ten spins." }
		end
		return { canUse = true }
	end

	local function renderResults()
		local shown = batch
		for i, row in resultRows do
			local result = if shown and i <= revealed then shown.results[i] else nil
			row.index.Text = if result then tostring(i) else ""
			row.rarity.Text = if result then RARITY_SHORT[result.rarity] or string.upper(result.rarity) else ""
			row.rarity.TextColor3 = if result then RARITY_COLOR[result.rarity] or Colors.Text else Colors.Text
			if result then
				local prize = result.prize
				row.prize.Text = Format.prize(prize, batchSnapshot)
				row.prize.TextColor3 = if prize.kind == "DuplicateCosmetic" then Colors.TextDim
					elseif prize.kind == "Cosmetic" then Colors.Active
					else Colors.Text
			else
				row.prize.Text = if i == 1 and not shown then "PLACE A BET TO SEE WHAT D'ARBY DEALS." else ""
				row.prize.TextColor3 = Colors.TextDim
			end
			row.pity.Text = if result and result.usedPity then "PITY" else ""
		end
		if shown then
			local tierName = TIER_BUTTON[shown.tierId] or ""
			resultTitle.Text = if shown.recovered then `RECOVERED  {tierName}` else `RESULTS  {tierName}`
			if revealed >= #shown.results then
				local refund = Format.refundTotal(shown.results)
				resultSummary.Text = if refund > 0 then `-{shown.spentYen}Y  DUPES +{refund} SHARD` else `-{shown.spentYen}Y`
			else
				resultSummary.Text = `{revealed}/{#shown.results}`
			end
		else
			resultTitle.Text = "RESULTS"
			resultSummary.Text = ""
		end
	end

	local function render()
		local snapshot = shell.snapshot()
		if not snapshot then
			return
		end
		local busy = shell.busy() or revealing
		-- No new spin while an earlier action is unconfirmed: RETRY LAST ACTION first.
		local waiting = shell.pending()
		local tier = tierFor(snapshot, selected)
		for id, button in tierButtons do
			button.setState(if busy then (if id == selected then "Selected" else "Disabled")
				elseif id == selected then "Selected" else "Normal")
		end
		if not tier then
			singlePrice.Text = "CHIP UNAVAILABLE"
			tenPrice.Text = ""
			spinOne.setState("Disabled")
			spinTen.setState("Disabled")
			renderResults()
			return
		end

		singlePrice.Text = `1 SPIN   {tier.singleSpinYen}Y`
		tenPrice.Text = `10 SPIN  {tier.tenSpinYen}Y`
		pityValue.Text = `{tier.pityCounter}/{tier.pityThreshold}`
		setPity(if tier.pityThreshold > 0 then tier.pityCounter / tier.pityThreshold else 0)
		local left = tier.pityThreshold - tier.pityCounter
		pityHint.Text = if left <= 1 then "NEXT SPIN USES PITY ODDS."
			else `PITY ODDS IN {left} SPINS WITHOUT A RARE+.`
		pityHint.TextColor3 = if left <= 1 then Palette.Gold else Colors.TextDim

		local ten = tenLegality(snapshot, tier)
		spinOne.setState(if busy or waiting or not tier.legality.canUse then "Disabled" else "Primary")
		spinTen.setState(if busy or waiting or not ten.canUse then "Disabled" else "Primary")
		spinHint.Text = if waiting then "RETRY YOUR LAST ACTION FIRST."
			elseif not tier.legality.canUse then string.upper(CampaignUi.reason(tier.legality))
			elseif not ten.canUse then string.upper(CampaignUi.reason(ten))
			else ""

		-- Odds: pity odds cover only the buckets above Common.
		oddsTitle.Text = `ODDS  {string.upper(tier.label)}`
		for i, row in oddsRows do
			local odds = tier.normalOdds[i]
			row.rarity.Visible = odds ~= nil
			row.bucket.Visible = odds ~= nil
			row.normal.Visible = odds ~= nil
			row.pity.Visible = odds ~= nil
			if odds then
				row.rarity.Text = RARITY_SHORT[odds.rarity] or string.upper(odds.rarity)
				row.rarity.TextColor3 = RARITY_COLOR[odds.rarity] or Colors.Text
				row.bucket.Text = Format.bucket(odds.bucketId)
				row.normal.Text = Format.percent(odds.chancePct)
				local boosted: Contract.ParlorOdds? = nil
				for _, entry in tier.pityOdds do
					if entry.bucketId == odds.bucketId then
						boosted = entry
						break
					end
				end
				row.pity.Text = if boosted then Format.percent(boosted.chancePct) else "-"
				row.pity.TextColor3 = if boosted then Palette.Gold else Colors.TextDim
			end
		end

		renderResults()
		local shown = shell.status()
		statusLine.Text = if shown then shown.text else ""
		statusLine.TextColor3 = if shown then shown.color else Colors.TextDim
	end
	shell.setRender(render)

	-- Reveals a committed batch one result at a time, in receipt order.
	local function reveal(receipt: Contract.Receipt, recovered: boolean?)
		if receipt.kind ~= "Spun" then
			return
		end
		batch = {
			tierId = receipt.tierId, spentYen = receipt.spentYen, results = receipt.results,
			recovered = recovered == true,
		}
		batchSnapshot = shell.client:snapshot()
		selected = receipt.tierId
		revealed = 0
		revealing = true
		task.spawn(function()
			for i = 1, #receipt.results do
				local shown = batch
				if not shell.alive() or shown == nil or shown.results ~= receipt.results then
					revealing = false
					return
				end
				revealed = i
				shell.render()
				task.wait(REVEAL_SECONDS)
			end
			revealing = false
			shell.render()
		end)
	end

	local function spin(count: number)
		local snapshot = shell.snapshot()
		if shell.busy() or revealing or not snapshot then
			return
		end
		if shell.pending() then
			-- The shell retries the unconfirmed action instead of spinning.
			shell.run({ kind = "Spin", tierId = selected, count = count })
			return
		end
		local tier = tierFor(snapshot, selected)
		if not tier then
			return
		end
		if count == 1 then
			if shell.explain(tier.legality) then
				return
			end
		else
			local ten = tenLegality(snapshot, tier)
			if not ten.canUse then
				deps.toast(CampaignUi.reason(ten))
				return
			end
		end
		shell.run({ kind = "Spin", tierId = selected, count = count }, function(result)
			local receipt = result.receipt
			if result.ok and receipt then
				reveal(receipt)
			end
		end)
	end

	shell.setRecovered(function(receipt: Contract.Receipt)
		reveal(receipt, true)
	end)

	for id, button in tierButtons do
		button.button.Activated:Connect(function()
			if shell.busy() or revealing or id == selected then
				return
			end
			selected = id
			shell.render()
		end)
	end
	spinOne.button.Activated:Connect(function()
		spin(1)
	end)
	spinTen.button.Activated:Connect(function()
		spin(10)
	end)

	local self = {} :: Parlor
	function self.destroy(_self: Parlor)
		shell.destroy()
	end

	shell.render()
	task.spawn(shell.load)
	return self
end

return ParlorScreen
