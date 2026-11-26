--!strict

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")

local Remote = require("@game/ReplicatedStorage/Shared/Contracts/RemoteContract")
local Contract = require("@game/ReplicatedStorage/Shared/Contracts/Phase4EconomyTypes")
local Session = require("@game/ReplicatedStorage/Shared/Core/Phase4Session")
local Parlor = require("@game/ReplicatedStorage/Shared/Core/Phase4Parlor")
local EconomyData = require("@game/ReplicatedStorage/Shared/Data/Phase4EconomyData")

type Response = Remote.Phase4SnapshotResponse | Remote.Phase4ActionResponse
type Handler = (number, unknown) -> Response

-- Stable ownership IDs until the client supplies presentation for the stock Parlor prizes.
local cosmetics: { [Contract.ParlorBucketId]: string } = {
	CommonCosmetic = "parlor-common-hair-swatch",
	RareCosmetic = "parlor-rare-aura",
	EpicCosmetic = "parlor-epic-pose",
	LegendaryCosmetic = "parlor-legendary-title",
}

local function prizeFor(bucket: Contract.ParlorBucketId, act: number): Parlor.Grant?
	local cosmeticId = cosmetics[bucket]
	if cosmeticId then return { kind = "Cosmetic", cosmeticId = cosmeticId } end
	local income = EconomyData.ActIncome[act]
	if bucket == "EpicBaseGearCrate" then
		return {
			kind = "Gear", familyId = "training-wraps", slot = "Weapon",
			baseStats = { { statId = "Physical", value = EconomyData.GlobalCaps.BaseGearBudgetPerSlotMultiplier * act } },
		}
	elseif bucket == "RareSupplyCrate" then
		return {
			kind = "Supplies", items = { { itemId = "tonio-water", quantity = 1 } },
			resources = { yen = 0, salvageShards = 0, materials = 0, holyWater = 0 },
		}
	elseif bucket == "CommonCraftingCrate" or bucket == "RareCraftingCrate" then
		local rare = bucket == "RareCraftingCrate"
		return {
			kind = "Supplies", items = {},
			resources = {
				yen = 0, holyWater = 0,
				salvageShards = if rare then income.dismantleShards.Rare else income.dismantleShards.Common,
				materials = if rare then income.materialDrops.dungeon else income.materialDrops.flag,
			},
		}
	end
	return nil
end

local function bind(store: Session.Store)
	local rng = Random.new()
	local session = Session.new(store, {
		clock = os.time,
		makeId = function() return HttpService:GenerateGUID(false) end,
		roll = function() return rng:NextNumber() end,
		prizeFor = prizeFor,
	})
	local routes = Remote.Phase4
	local folder = Instance.new("Folder")
	folder.Name = routes.FolderName
	assert(not Shared:FindFirstChild(folder.Name), "Phase 4 remotes already exist")

	local inFlight: { [number]: boolean } = {}
	local pendingClose: { [number]: boolean } = {}
	local shuttingDown = false

	local function close(userId: number)
		if inFlight[userId] then
			pendingClose[userId] = true
			return
		end
		pendingClose[userId] = nil
		inFlight[userId] = true
		local ok, err = pcall(session.close, userId)
		inFlight[userId] = nil
		if not ok then warn("Phase 4 lease cleanup failed", userId, err) end
	end

	local function finish(userId: number)
		inFlight[userId] = nil
		if pendingClose[userId] or shuttingDown then close(userId) end
	end

	local function addFunction(name: string, handler: Handler)
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.OnServerInvoke = function(player: Player, payload: unknown): Response
			local userId = player.UserId
			if shuttingDown or player.Parent ~= Players or inFlight[userId] then
				return { ok = false, code = "SaveUnavailable", message = "Wait for the current economy request." }
			end
			inFlight[userId] = true
			local ok, result = pcall(handler, userId, payload)
			finish(userId)
			if not ok then
				warn("Phase 4 request failed", name, result)
				return { ok = false, code = "SaveUnavailable", message = "Could not confirm the economy request." }
			end
			return result
		end
		remote.Parent = folder
	end

	addFunction(routes.GetPhase4Snapshot.name, function(userId, payload)
		if type(payload) ~= "table" or next(payload) ~= nil then
			return { ok = false, code = "InvalidRequest", message = "GetPhase4Snapshot takes an empty request." }
		end
		return session.GetPhase4Snapshot(userId)
	end)
	addFunction(routes.SubmitPhase4Action.name, session.SubmitPhase4Action)
	folder.Parent = Shared

	Players.PlayerRemoving:Connect(function(player)
		close(player.UserId)
	end)
	task.spawn(function()
		-- Same 30-second lease heartbeat as CampaignService.
		while not shuttingDown do
			task.wait(30)
			if shuttingDown then break end
			for _, player in Players:GetPlayers() do
				local userId = player.UserId
				if not inFlight[userId] then
					inFlight[userId] = true
					task.spawn(function()
						local ok, err = pcall(session.renew, userId)
						finish(userId)
						if not ok then warn("Phase 4 lease renewal failed", userId, err) end
					end)
				end
			end
		end
	end)
	game:BindToClose(function()
		shuttingDown = true
		for _, player in Players:GetPlayers() do task.spawn(close, player.UserId) end
		local deadline = os.clock() + 10
		while next(inFlight) and os.clock() < deadline do task.wait() end
	end)
end

return table.freeze({ bind = bind })
