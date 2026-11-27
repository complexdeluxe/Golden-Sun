--!strict

local Players = game:GetService("Players")
local AnalyticsService = game:GetService("AnalyticsService")
local HttpService = game:GetService("HttpService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")

local Remote = require("@game/ReplicatedStorage/Shared/Contracts/RemoteContract")
local Session = require("@game/ReplicatedStorage/Shared/Core/CampaignSession")
local ActBattle = require("@game/ReplicatedStorage/Shared/Core/CampaignActBattle")
local Progression = require("@game/ReplicatedStorage/Shared/Core/CampaignProgression")

local onboardingSteps = table.freeze({
	"Joined", "AppearanceCreated", "TutorialStarted", "TutorialCleared", "OriginChosen",
	"HubVisited", "Act1_F1_Cleared", "Act1_D1_Cleared", "CompanionRecruited",
})

type Payload = { [string]: unknown }
type Handler = (number, Payload) -> Remote.CampaignResponse | Remote.ActBattleResponse

local function errorResponse(code: Remote.CampaignErrorCode, message: string): Remote.CampaignResponse
	return { ok = false, code = code, message = message }
end

local function validAction(payload: Payload): boolean
	local revision = payload.expectedRevision
	if type(payload.sessionId) ~= "string" or type(revision) ~= "number" or revision < 1 or revision >= 2 ^ 53 or revision % 1 ~= 0 then
		return false
	end

	local kind = payload.kind
	if kind == "CommitAppearance" then return type(payload.appearance) == "table" end
	if kind == "Navigate" then return payload.destination == "Hub" or payload.destination == "ActMap" end
	if kind == "StartNode" then
		local nodeId = payload.nodeId
		return Progression.nodeId(nodeId) and type(payload.playOptionId) == "string"
	end
	if kind == "PurchaseOffer" then return type(payload.offerId) == "string" and type(payload.quantity) == "number" end
	if kind == "RecruitCompanion" then return type(payload.offerId) == "string" end
	if kind == "SetGearSlot" or kind == "SetBeltSlot" then
		if payload.entryId ~= nil and type(payload.entryId) ~= "string" then return false end
		if kind == "SetBeltSlot" then return type(payload.index) == "number" end
		local slot = payload.slot
		return slot == "Weapon" or slot == "Head" or slot == "Body" or slot == "Accessory"
	end
	return false
end

local function bind(store: Session.Store, bridge: Progression.Bridge)
	local function now(): number return workspace:GetServerTimeNow() end
	local rng = Random.new()
	local session = Session.new(store, os.time, function() return HttpService:GenerateGUID(false) end, now,
		function() return rng:NextNumber() end, bridge)
	local inFlight: { [number]: boolean } = {}
	local pendingClose: { [number]: boolean } = {}
	local shuttingDown = false
	local funnel: { [Player]: number } = {}

	local function recordOnboarding(player: Player, through: number)
		if player.Parent ~= Players then return end
		-- Roblox counts each onboarding step once per user. The local cursor
		-- also avoids re-emitting it from every refresh or battle reply.
		for step = (funnel[player] or 0) + 1, through do
			local ok = pcall(function()
				AnalyticsService:LogOnboardingFunnelStepEvent(player, step, onboardingSteps[step])
			end)
			if not ok then break end
			funnel[player] = step
		end
	end

	local function close(userId: number)
		if inFlight[userId] then
			pendingClose[userId] = true
			return
		end
		pendingClose[userId] = nil
		inFlight[userId] = true
		session.close(userId)
		inFlight[userId] = nil
	end

	local function finish(userId: number)
		inFlight[userId] = nil
		if pendingClose[userId] or shuttingDown then close(userId) end
	end

	local routes = Remote.Campaign
	local folder = Instance.new("Folder")
	folder.Name = routes.FolderName
	assert(not Shared:FindFirstChild(folder.Name), "Campaign remotes already exist")

	local actRoutes = Remote.ActBattle
	local actFolder = Instance.new("Folder")
	actFolder.Name = actRoutes.FolderName
	assert(not Shared:FindFirstChild(actFolder.Name), "Act battle remotes already exist")

	local updates = Instance.new("RemoteEvent")
	updates.Name = routes.CampaignSnapshotChanged.name
	updates.Parent = folder
	local actUpdates = Instance.new("RemoteEvent")
	actUpdates.Name = actRoutes.ActBattleSnapshotChanged.name
	actUpdates.Parent = actFolder

	local timers: { [number]: { battleId: string, deadline: number } } = {}
	local function scheduleCheck(player: Player)
		local userId = player.UserId
		local battleId, deadline = session.nextCheck(userId)
		local previous = timers[userId]
		if previous and previous.battleId == battleId and previous.deadline == deadline then return end
		timers[userId] = nil
		if shuttingDown or player.Parent ~= Players or not battleId or not deadline then return end
		local timer = { battleId = battleId, deadline = deadline }
		timers[userId] = timer
		local function expire()
			if shuttingDown or player.Parent ~= Players or timers[userId] ~= timer then return end
			if inFlight[userId] then
				task.delay(0.05, expire)
				return
			end
			timers[userId] = nil
			inFlight[userId] = true
			local ok, result = pcall(session.expireChecks, userId, timer.battleId)
			finish(userId)
			if not ok then
				warn("Act battle QTE timeout failed", result)
			elseif result and result.ok and player.Parent == Players then
				recordOnboarding(player, session.onboarding(userId))
				actUpdates:FireClient(player, result.snapshot)
				if result.campaignSnapshot then updates:FireClient(player, result.campaignSnapshot) end
			end
			scheduleCheck(player)
		end
		task.delay(math.max(0, deadline - now()), expire)
	end

	local function addFunction(parent: Folder, name: string, handler: Handler)
		local fn = Instance.new("RemoteFunction")
		fn.Name = name
		fn.OnServerInvoke = function(player: Player, value: unknown)
			local id = player.UserId
			if type(value) ~= "table" then return errorResponse("InvalidRequest", "Expected a campaign request.") end
			if shuttingDown or player.Parent ~= Players or inFlight[id] then
				return errorResponse("NotReady", "Wait for the current campaign request.")
			end
			inFlight[id] = true
			local ok, result = pcall(handler, id, value :: Payload)
			finish(id)
			scheduleCheck(player)
			if not ok then
				warn("Campaign request failed", name, result)
				return errorResponse("SaveUnavailable", "The campaign request could not be completed.")
			end
			if result.ok then recordOnboarding(player, session.onboarding(id)) end
			return result
		end
		fn.Parent = parent
	end

	addFunction(folder, routes.GetCampaignSnapshot.name, function(userId, payload)
		if next(payload) then return errorResponse("InvalidRequest", "GetCampaignSnapshot takes an empty request.") end
		return session.get(userId)
	end)
	addFunction(folder, routes.SubmitCampaignAction.name, function(userId, payload)
		if not validAction(payload) then return errorResponse("InvalidRequest", "Invalid campaign action or session revision.") end
		return session.submit(userId, (payload :: unknown) :: Remote.CampaignActionRequest)
	end)

	local function addActFunction(name: string, kind: "Get" | "Primary" | "Secondary" | "Check" | "Mode")
		addFunction(actFolder, name, function(userId, payload)
			local revision, actor = payload.expectedRevision, payload.actorId
			local valid = type(payload.battleId) == "string"
			if kind == "Primary" or kind == "Secondary" or kind == "Mode" then
				valid = valid and type(revision) == "number" and revision >= 1 and revision < 2 ^ 53 and revision % 1 == 0
			end
			if kind == "Primary" then
				valid = valid and type(actor) == "string" and type(payload.moveId) == "string"
					and (payload.slot == "Primary" or payload.slot == "BonusPrimary")
					and (payload.targetId == nil or type(payload.targetId) == "string")
			elseif kind == "Secondary" then
				local action = payload.kind
				valid = valid and type(actor) == "string" and (
					action == "EndTurn" or action == "Retreat"
					or (action == "UseBeltItem" and type(payload.itemId) == "string" and type(payload.targetId) == "string")
					or (action == "CompanionGuardRedirect" and type(payload.intentId) == "string" and type(payload.recipientId) == "string")
					or (action == "SetCompanionTactic" and (payload.tacticMode == "Aggressive"
						or payload.tacticMode == "Defensive" or payload.tacticMode == "Support"))
				)
			elseif kind == "Mode" then
				valid = valid and (payload.qteMode == "Manual" or payload.qteMode == "UntimedCue" or payload.qteMode == "AutoGood")
			elseif kind == "Check" then
				local index, input = payload.checkIndex, payload.input
				valid = valid and type(payload.challengeId) == "string" and (index == 1 or index == 2 or index == 3)
					and (input == "Confirm" or input == "Left" or input == "Center" or input == "Right")
			end
			if not valid then return { ok = false, code = "InvalidRequest", message = "Invalid Act battle input." } end
			return session.battle(userId, ({ kind = kind, request = payload } :: unknown) :: ActBattle.Command)
		end)
	end
	addActFunction(actRoutes.GetActBattleSnapshot.name, "Get")
	addActFunction(actRoutes.SubmitActBattlePrimary.name, "Primary")
	addActFunction(actRoutes.SubmitActBattleSecondary.name, "Secondary")
	addActFunction(actRoutes.SubmitActBattleQteCheck.name, "Check")
	addActFunction(actRoutes.SetActBattleQteMode.name, "Mode")
	actFolder.Parent = Shared
	folder.Parent = Shared

	local function joined(player: Player) recordOnboarding(player, 1) end
	Players.PlayerAdded:Connect(joined)
	for _, player in Players:GetPlayers() do joined(player) end
	Players.PlayerRemoving:Connect(function(player)
		funnel[player] = nil
		timers[player.UserId] = nil
		close(player.UserId)
	end)
	task.spawn(function()
		while not shuttingDown do
			task.wait(30)
			if shuttingDown then break end
			for _, player in Players:GetPlayers() do
				local id = player.UserId
				if not inFlight[id] then
					inFlight[id] = true
					task.spawn(function()
						session.renew(id)
						finish(id)
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

	local function withHubAction<T>(userId: number, handler: () -> T, busy: T): T
		-- Keep navigation and combat transitions idle through a Hub-checked write.
		if shuttingDown or inFlight[userId] then
			return busy
		end
		inFlight[userId] = true
		local ok, result = pcall(handler)
		finish(userId)
		if not ok then error(result) end
		return result
	end

	local function withLineageAction(userId: number, handler: () -> Remote.LineageActionResponse): Remote.LineageActionResponse
		return withHubAction(userId, handler, { ok = false, code = "SaveUnavailable", message = "Wait for the current campaign request." })
	end

	return table.freeze({ isSafeHub = session.isSafeHub, withLineageAction = withLineageAction, withHubAction = withHubAction, recordOnboarding = recordOnboarding })
end

return table.freeze({ bind = bind })
