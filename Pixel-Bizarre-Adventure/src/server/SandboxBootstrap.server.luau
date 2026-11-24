--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local Shared = ReplicatedStorage:WaitForChild("Shared")

local Battle = require("@game/ReplicatedStorage/Shared/Core/BlackSabbathBattle")
local Remote = require("@game/ReplicatedStorage/Shared/Contracts/RemoteContract")

type Payload = { [string]: unknown }
type Handler = (Battle.State, Payload) -> Remote.SandboxResponse

local routes = Remote.Sandbox
local sessions: { [Player]: Battle.State } = {}
local timers: { [Player]: number } = {}
local folder = Instance.new("Folder")
folder.Name = routes.FolderName
assert(not Shared:FindFirstChild(folder.Name), "Black Sabbath remotes already exist")

local changed = Instance.new("RemoteEvent")
changed.Name = routes.SandboxSnapshotChanged.name
changed.Parent = folder

local function invalid(message: string): Remote.SandboxResponse
	return { ok = false, code = "InvalidRequest", message = message }
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function synchronizeTimer(player: Player, battle: Battle.State)
	local deadline = Battle.nextDeadline(battle)
	if deadline == timers[player] then return end
	timers[player] = deadline
	if not deadline then return end
	task.delay(math.max(0, deadline - now()), function()
		if sessions[player] ~= battle or timers[player] ~= deadline then return end
		timers[player] = nil
		if Battle.expireChecks(battle) then changed:FireClient(player, Battle.snapshot(battle)) end
		synchronizeTimer(player, battle)
	end)
end

local function validMode(mode: unknown): boolean
	return mode == "Manual" or mode == "AutoGood" or mode == "UntimedCue"
end

local function bind(name: string, invoke: (Player, Payload) -> Remote.SandboxResponse)
	local route = Instance.new("RemoteFunction")
	route.Name = name
	route.OnServerInvoke = function(player: Player, payload: unknown)
		if type(payload) ~= "table" then return invalid("Expected a sandbox request.") end
		return invoke(player, payload :: Payload)
	end
	route.Parent = folder
end

local function bindBattle(name: string, revision: boolean, handle: Handler)
	bind(name, function(player, payload)
		local id = payload.battleId
		local expected = payload.expectedRevision
		if type(id) ~= "string" or (revision and (type(expected) ~= "number" or expected < 1 or expected > 2 ^ 53 or expected % 1 ~= 0)) then
			return invalid("Invalid battle reference.")
		end
		local battle = sessions[player]
		if not battle or battle.id ~= id then
			return { ok = false, code = "BattleNotFound", message = "Start a new sandbox battle." }
		end
		local response = handle(battle, payload)
		synchronizeTimer(player, battle)
		return response
	end)
end

bind(routes.StartSandbox.name, function(player, payload)
	local level = payload.level
	local stage = payload.stageTag
	if (level ~= 10 and level ~= 50) or (stage ~= "Night" and stage ~= "Neutral") or not validMode(payload.qteMode) then
		return invalid("Choose level 10 or 50, a stage, and a QTE mode.")
	end
	local rng = Random.new()
	local battle = Battle.new(HttpService:GenerateGUID(false), payload :: any, function() return rng:NextNumber() end, now)
	sessions[player] = battle
	timers[player] = nil
	return { ok = true, snapshot = Battle.snapshot(battle) }
end)

bindBattle(routes.GetSandboxSnapshot.name, false, function(battle)
	Battle.expireChecks(battle)
	return { ok = true, snapshot = Battle.snapshot(battle) }
end)

bindBattle(routes.SubmitSandboxPrimary.name, true, function(battle, payload)
	local slot = payload.slot
	if type(payload.actorId) ~= "string" or type(payload.moveId) ~= "string"
		or (slot ~= "Primary" and slot ~= "BonusPrimary")
		or (payload.targetId ~= nil and type(payload.targetId) ~= "string") then
		return invalid("Invalid fighter, Primary slot, move, or target.")
	end
	return Battle.submitPrimary(battle, payload :: any)
end)

bindBattle(routes.SubmitSandboxSecondary.name, true, function(battle, payload)
	if type(payload.actorId) ~= "string" then return invalid("Invalid acting fighter.") end
	local kind = payload.kind
	if kind == "UseBeltItem" then
		if type(payload.itemId) ~= "string" or type(payload.targetId) ~= "string" then return invalid("Invalid belt request.") end
	elseif kind == "CompanionGuardRedirect" then
		if type(payload.intentId) ~= "string" or type(payload.recipientId) ~= "string" then return invalid("Invalid redirect request.") end
	elseif kind == "SetCompanionTactic" then
		local tactic = payload.tacticMode
		if tactic ~= "Aggressive" and tactic ~= "Defensive" and tactic ~= "Support" then return invalid("Invalid tactic.") end
	elseif kind ~= "EndTurn" then
		return invalid("Unknown Secondary request.")
	end
	return Battle.submitSecondary(battle, payload :: any)
end)

bindBattle(routes.SetSandboxQteMode.name, true, function(battle, payload)
	if not validMode(payload.qteMode) then return invalid("Invalid QTE mode.") end
	return Battle.setQteMode(battle, payload :: any)
end)

bindBattle(routes.SubmitSandboxQteCheck.name, false, function(battle, payload)
	local index = payload.checkIndex
	local input = payload.input
	if type(payload.challengeId) ~= "string" or (index ~= 1 and index ~= 2 and index ~= 3)
		or (input ~= "Left" and input ~= "Center" and input ~= "Right" and input ~= "Confirm") then
		return invalid("Invalid challenge, check, or input.")
	end
	return Battle.submitCheck(battle, payload :: any)
end)

Players.PlayerRemoving:Connect(function(player)
	sessions[player] = nil
	timers[player] = nil
end)

folder.Parent = Shared
