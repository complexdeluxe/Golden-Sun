--!strict

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")

local Remote = require("@game/ReplicatedStorage/Shared/Contracts/RemoteContract")
local Session = require("@game/ReplicatedStorage/Shared/Core/CampaignSession")

type Payload = { [string]: unknown }
type Handler = (number, Payload) -> Remote.CampaignResponse

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
		return (nodeId == "F1" or nodeId == "F2" or nodeId == "D1") and type(payload.playOptionId) == "string"
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

local function bind(store: Session.Store)
	local session = Session.new(store, os.time, function() return HttpService:GenerateGUID(false) end)
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

	local function addFunction(name: string, handler: Handler)
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
			if not ok then
				warn("Campaign request failed", name, result)
				return errorResponse("SaveUnavailable", "The campaign request could not be completed.")
			end
			return result
		end
		fn.Parent = folder
	end

	addFunction(routes.GetCampaignSnapshot.name, function(userId, payload)
		if next(payload) then return errorResponse("InvalidRequest", "GetCampaignSnapshot takes an empty request.") end
		return session.get(userId)
	end)
	addFunction(routes.SubmitCampaignAction.name, function(userId, payload)
		if not validAction(payload) then return errorResponse("InvalidRequest", "Invalid campaign action or session revision.") end
		return session.submit(userId, (payload :: unknown) :: Remote.CampaignActionRequest)
	end)

	local updates = Instance.new("RemoteEvent")
	updates.Name = routes.CampaignSnapshotChanged.name
	updates.Parent = folder
	folder.Parent = Shared

	Players.PlayerRemoving:Connect(function(player) close(player.UserId) end)
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
end

return table.freeze({ bind = bind })
