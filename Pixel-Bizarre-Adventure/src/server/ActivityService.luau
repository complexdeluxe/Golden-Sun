--!strict

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")

local Contract = require("@game/ReplicatedStorage/Shared/Contracts/ActivityTypes")
local Remote = require("@game/ReplicatedStorage/Shared/Contracts/RemoteContract")
local Session = require("@game/ReplicatedStorage/Shared/Core/ActivitySession")

type Response = Remote.ActivitySnapshotResponse | Remote.ActivityActionResponse
type Handler = (number, unknown) -> Response
type CampaignAccess = {

	read withHubAction: <T>(number, () -> T, T) -> T,
}
type Schedule = {
	player: Player,
	nextOpenAt: number?,
	nextRenewAt: number,
	nextClaimAtUtc: number?,
}

local HEARTBEAT_SECONDS = 30

local function bind(session: typeof(Session.new((nil :: any), (nil :: any))), campaign: CampaignAccess)
	local routes = Remote.Activity
	local folder = Instance.new("Folder")
	folder.Name = routes.FolderName
	assert(not Shared:FindFirstChild(folder.Name), "Activity remotes already exist")

	local schedules: { [number]: Schedule } = {}
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
		if not ok then warn("Activity lease cleanup failed", userId, err) end
	end

	local function finish(userId: number)
		inFlight[userId] = nil
		if pendingClose[userId] or shuttingDown then close(userId) end
	end

	local function remember(schedule: Schedule, snapshot: Contract.Snapshot)
		if schedule.nextOpenAt then schedule.nextRenewAt = os.clock() + HEARTBEAT_SECONDS end
		schedule.nextOpenAt = nil
		local run = snapshot.autoBattle
		local paidThrough = run.lastClaimedAtUtc
		schedule.nextClaimAtUtc = if run.runId and paidThrough then paidThrough + run.tickSeconds else nil
	end

	local function addFunction(name: string, handler: Handler)
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.OnServerInvoke = function(player: Player, payload: unknown): Response
			local userId = player.UserId
			local schedule = schedules[userId]
			if shuttingDown or player.Parent ~= Players or not schedule or schedule.player ~= player or inFlight[userId] then
				return { ok = false, code = "SaveUnavailable", message = "Wait for the current activity request." }
			end
			inFlight[userId] = true
			local ok, result = pcall(handler, userId, payload)
			if ok and result.snapshot then
				remember(schedule, result.snapshot)
			elseif not ok or (not result.ok and (result.code == "SaveUnavailable" or result.code == "ProfileLocked")) then
				-- A start or stop may have committed even if the reply was lost.
				schedule.nextOpenAt = os.clock() + 1
			end
			finish(userId)
			if not ok then
				warn("Activity request failed", name, result)
				return { ok = false, code = "SaveUnavailable", message = "Could not confirm the activity request." }
			end
			return result
		end
		remote.Parent = folder
	end

	addFunction(routes.GetActivitySnapshot.name, function(userId, payload)
		if type(payload) ~= "table" or next(payload) ~= nil then
			return { ok = false, code = "InvalidRequest", message = "GetActivitySnapshot takes an empty request." }
		end
		return session.GetActivitySnapshot(userId)
	end)
	addFunction(routes.SubmitActivityAction.name, function(userId, payload)
		if type(payload) == "table" and type(payload.action) == "table" and payload.action.kind == "StartAutoBattle" then
			local busy: Remote.ActivityActionResponse = { ok = false, code = "SaveUnavailable", message = "Wait for the current campaign request." }
			return campaign.withHubAction(userId, function()
				return session.SubmitActivityAction(userId, payload)
			end, busy)
		end
		return session.SubmitActivityAction(userId, payload)
	end)

	local function connected(schedule: Schedule): boolean
		return not shuttingDown and schedule.player.Parent == Players and schedules[schedule.player.UserId] == schedule
	end

	local function maintain(schedule: Schedule)
		if not connected(schedule) then return end
		local userId = schedule.player.UserId
		local elapsed = os.clock()
		if schedule.nextOpenAt then
			schedule.nextOpenAt = elapsed + HEARTBEAT_SECONDS
			local result = session.GetActivitySnapshot(userId)
			if not result.ok then return end
			remember(schedule, result.snapshot)
		elseif schedule.nextRenewAt <= elapsed then
			schedule.nextRenewAt = elapsed + HEARTBEAT_SECONDS
			session.renew(userId)
		end

		local now = os.time()
		local due = schedule.nextClaimAtUtc
		if not due or due > now or not connected(schedule) then return end
		-- Back off on storage errors. The session uses its persisted UTC cursor
		-- to catch up all elapsed five-minute ticks without paying twice.
		schedule.nextClaimAtUtc = now + HEARTBEAT_SECONDS
		local result = session.tick(userId)
		if result.ok then
			remember(schedule, result.snapshot)
		elseif result.code == "ProfileLocked" then
			schedule.nextOpenAt = os.clock()
		end
	end

	local function track(player: Player)
		schedules[player.UserId] = { player = player, nextOpenAt = 0, nextRenewAt = 0 }
	end

	Players.PlayerAdded:Connect(track)
	Players.PlayerRemoving:Connect(function(player)
		local schedule = schedules[player.UserId]
		if schedule and schedule.player ~= player then return end
		schedules[player.UserId] = nil
		close(player.UserId)
	end)
	for _, player in Players:GetPlayers() do track(player) end
	folder.Parent = Shared

	task.spawn(function()
		while not shuttingDown do
			local elapsed, now = os.clock(), os.time()
			-- Only in-memory checks run every second. Lease renewal follows the
			-- 30-second heartbeat, and inactive runs never call tick.
			for userId, schedule in schedules do
				local openAt, claimAt = schedule.nextOpenAt, schedule.nextClaimAtUtc
				local due = if openAt then openAt <= elapsed
					else schedule.nextRenewAt <= elapsed or (claimAt ~= nil and claimAt <= now)
				if due and not inFlight[userId] and connected(schedule) then
					inFlight[userId] = true
					task.spawn(function()
						local ok, err = pcall(maintain, schedule)
						finish(userId)
						if not ok then warn("Activity heartbeat failed", userId, err) end
					end)
				end
			end
			task.wait(1)
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
