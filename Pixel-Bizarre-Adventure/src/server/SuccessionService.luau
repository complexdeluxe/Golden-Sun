--!strict

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")

local Remote = require("@game/ReplicatedStorage/Shared/Contracts/RemoteContract")
local Session = require("@game/ReplicatedStorage/Shared/Core/SuccessionSession")

type Response = Remote.LineageSnapshotResponse | Remote.LineageActionResponse
type Handler = (number, unknown) -> Response
type CampaignAccess = {

	read withLineageAction: (number, () -> Remote.LineageActionResponse) -> Remote.LineageActionResponse,
}

local function bind(session: typeof(Session.new((nil :: any), (nil :: any))), campaign: CampaignAccess)
	local routes = Remote.Lineage
	local folder = Instance.new("Folder")
	folder.Name = routes.FolderName
	assert(not Shared:FindFirstChild(folder.Name), "Lineage remotes already exist")

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
		if not ok then warn("Lineage lease cleanup failed", userId, err) end
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
				return { ok = false, code = "SaveUnavailable", message = "Wait for the current lineage request." }
			end
			inFlight[userId] = true
			local ok, result = pcall(handler, userId, payload)
			finish(userId)
			if not ok then
				warn("Lineage request failed", name, result)
				return { ok = false, code = "SaveUnavailable", message = "Could not confirm the lineage request." }
			end
			return result
		end
		remote.Parent = folder
	end

	addFunction(routes.GetLineageSnapshot.name, function(userId, payload)
		if type(payload) ~= "table" or next(payload) ~= nil then
			return { ok = false, code = "InvalidRequest", message = "GetLineageSnapshot takes an empty request." }
		end
		return session.GetLineageSnapshot(userId)
	end)
	addFunction(routes.SubmitLineageAction.name, function(userId, payload)
		return campaign.withLineageAction(userId, function()
			return session.SubmitLineageAction(userId, payload)
		end)
	end)
	folder.Parent = Shared

	Players.PlayerRemoving:Connect(function(player)
		close(player.UserId)
	end)
	task.spawn(function()
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
						if not ok then warn("Lineage lease renewal failed", userId, err) end
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
