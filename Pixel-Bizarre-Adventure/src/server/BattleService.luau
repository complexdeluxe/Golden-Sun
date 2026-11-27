--!strict

local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local HttpService = game:GetService("HttpService")

local Session = require("@game/ReplicatedStorage/Shared/Core/TutorialSession")
local Combat = require("@game/ReplicatedStorage/Shared/Contracts/CombatTypes")
local Save = require("@game/ReplicatedStorage/Shared/Contracts/SaveTypes")
local Remote = require("@game/ReplicatedStorage/Shared/Contracts/RemoteContract")

type Route = (number, { [string]: unknown }) -> Remote.TutorialResponse | Remote.ChooseOriginResponse

local function validRevision(value: unknown): boolean
	return type(value) == "number" and value >= 1 and value <= 2 ^ 53 and value % 1 == 0
end

local function invalid(message: string): Remote.Rejected
	return { ok = false, code = "InvalidRequest", message = message }
end

local function bind(store: Session.Store, recordOnboarding: (Player, number) -> ())
	local session = Session.new(store, function()
		return HttpService:GenerateGUID(false)
	end)
	local inFlight: { [number]: boolean } = {}

	local folder = Instance.new("Folder")
	folder.Name = Remote.FolderName
	assert(not Shared:FindFirstChild(folder.Name), "Tutorial remotes already exist")

	local function createRemote(name: string, handler: Route)
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.OnServerInvoke = function(player: Player, payload: unknown)
			if type(payload) ~= "table" then
				return invalid("Expected a tutorial request.")
			end
			local userId = player.UserId
			if player.Parent ~= Players or inFlight[userId] then
				return { ok = false, code = "NotReady", message = "Wait for the current tutorial request." }
			end
			inFlight[userId] = true
			local ok, result = pcall(handler, userId, payload :: { [string]: unknown })
			inFlight[userId] = nil
			if player.Parent ~= Players then
				session.remove(userId)
			end
			if not ok then
				warn("Tutorial request failed", name, result)
				return { ok = false, code = "NotReady", message = "The tutorial request failed. Try again." }
			end
			if result.ok then
				if result.profile.origin then recordOnboarding(player, 5)
				elseif result.profile.tutorialCompleted then recordOnboarding(player, 4)
				elseif name == Remote.StartTutorial.name then recordOnboarding(player, 3) end
			end
			return result
		end
		remote.Parent = folder
	end

	createRemote(Remote.StartTutorial.name, function(userId, payload)
		if next(payload) ~= nil then
			return invalid("StartTutorial takes an empty request.")
		end
		return session.start(userId)
	end)
	createRemote(Remote.SubmitPrimaryAction.name, function(userId, payload)
		local move = payload.moveId
		local target = payload.targetId
		if type(payload.battleId) ~= "string" or not validRevision(payload.expectedRevision)
			or (move ~= "QuickStrike" and move ~= "HeavyStrike" and move ~= "Defend")
			or (target ~= nil and type(target) ~= "string")
		then
			return invalid("Invalid move, target, or battle revision.")
		end
		local request: Combat.ActionRequest = {
			battleId = payload.battleId :: string,
			expectedRevision = payload.expectedRevision :: number,
			moveId = move,
			targetId = target :: string?,
		}
		return session.submit(userId, request)
	end)
	createRemote(Remote.RetryTutorial.name, function(userId, payload)
		if type(payload.battleId) ~= "string" or not validRevision(payload.expectedRevision) then
			return invalid("Invalid battle or revision.")
		end
		return session.retry(userId, { battleId = payload.battleId :: string, expectedRevision = payload.expectedRevision :: number })
	end)
	createRemote(Remote.ChooseOrigin.name, function(userId, payload)
		local origin = payload.origin
		if origin ~= "Part1_Hamon" and origin ~= "Part3_Stand" then
			return invalid("Choose a valid origin.")
		end
		return session.choose(userId, { origin = origin :: Save.Origin })
	end)

	Players.PlayerRemoving:Connect(function(player)
		session.remove(player.UserId)
	end)
	folder.Parent = Shared
end

return table.freeze({ bind = bind })
