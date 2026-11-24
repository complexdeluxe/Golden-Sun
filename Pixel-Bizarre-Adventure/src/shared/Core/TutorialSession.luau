--!strict

local Combat = require("../Contracts/CombatTypes")
local Remote = require("../Contracts/RemoteContract")
local Save = require("../Contracts/SaveTypes")
local Engine = require("./CombatEngine")
local Progress = require("./TutorialProgress")

export type Store = {
	load: (userId: number) -> Save.Profile?,
	-- Returns the committed profile, or nil with an optional domain rejection.
	update: (userId: number, transform: (Save.Profile) -> (Save.Profile?, Remote.ErrorCode?)) -> (Save.Profile?, Remote.ErrorCode?),
}

type Session = {
	profile: Save.Profile,
	battle: Engine.Battle,
}

local function rejected(code: Remote.ErrorCode, message: string, session: Session?): Remote.Rejected
	return {
		ok = false,
		code = code,
		message = message,
		snapshot = if session then Engine.snapshot(session.battle) else nil,
	}
end

local function response(session: Session): Remote.TutorialResponse
	return { ok = true, snapshot = Engine.snapshot(session.battle), profile = table.clone(session.profile) }
end

export type Controller = {
	read start: (number) -> Remote.TutorialResponse,
	read submit: (number, Combat.ActionRequest) -> Remote.TutorialResponse,
	read retry: (number, Remote.RetryTutorialRequest) -> Remote.TutorialResponse,
	read choose: (number, Remote.ChooseOriginRequest) -> Remote.ChooseOriginResponse,
	read remove: (number) -> (),
}

local function new(store: Store, newId: () -> string): Controller
	local sessions: { [number]: Session } = {}

	local function start(userId: number): Remote.TutorialResponse
		local existing = sessions[userId]
		if existing then
			return response(existing)
		end

		local profile = store.load(userId)
		if not profile then
			return rejected("SaveUnavailable", "Your profile could not be loaded. Try again.", nil)
		end
		local battle = Engine.new(newId())
		if profile.tutorialCompleted then
			battle.outcome = "Victory"
			table.insert(battle.log, { turn = 1, kind = "Outcome" :: "Outcome", message = "Tutorial already complete." })
		end
		local session = { profile = profile, battle = battle }
		sessions[userId] = session
		return response(session)
	end

	local function submit(userId: number, request: Combat.ActionRequest): Remote.TutorialResponse
		local session = sessions[userId]
		if not session or request.battleId ~= session.battle.id then
			return rejected("BattleNotFound", "Open the current tutorial battle.", session)
		end
		if request.expectedRevision ~= session.battle.revision then
			return rejected("StaleRevision", "The battle has advanced. Check the updated turn.", session)
		end
		local staged, reason = Engine.apply(session.battle, request)
		if not staged then
			return rejected("IllegalAction", reason or "Select an available action.", session)
		end

		if staged.outcome == "Victory" and not session.profile.tutorialCompleted then
			local committed = store.update(userId, function(profile)
				return Progress.complete(profile), nil
			end)
			if not committed then
				return rejected("SaveUnavailable", "Victory could not be saved. Try this action again.", session)
			end
			session.profile = committed
		end
		session.battle = staged
		return response(session)
	end

	local function retry(userId: number, request: Remote.RetryTutorialRequest): Remote.TutorialResponse
		local session = sessions[userId]
		if not session or request.battleId ~= session.battle.id then
			return rejected("BattleNotFound", "Open the current tutorial battle.", session)
		end
		if request.expectedRevision ~= session.battle.revision then
			return rejected("StaleRevision", "The battle has advanced.", session)
		end
		if session.battle.outcome ~= "Defeat" then
			return rejected("RetryUnavailable", "Retry is available after a defeat.", session)
		end
		session.battle = Engine.new(newId())
		return response(session)
	end

	local function choose(userId: number, request: Remote.ChooseOriginRequest): Remote.ChooseOriginResponse
		local session = sessions[userId]
		if not session or not session.profile.tutorialCompleted then
			return rejected("TutorialIncomplete", "Win the tutorial before choosing an origin.", session)
		end
		if session.profile.origin == request.origin then
			return { ok = true, profile = table.clone(session.profile) }
		end
		if session.profile.origin then
			return rejected("OriginAlreadyChosen", "This profile already has an origin.", session)
		end
		local committed, code = store.update(userId, function(profile)
			return Progress.choose(profile, request.origin)
		end)
		if not committed then
			if code == "OriginAlreadyChosen" then
				return rejected(code, "This profile already has an origin.", session)
			end
			return rejected("SaveUnavailable", "Your origin could not be saved. Try again.", session)
		end
		session.profile = committed
		return { ok = true, profile = table.clone(committed) }
	end

	return table.freeze({
		start = start,
		submit = submit,
		retry = retry,
		choose = choose,
		remove = function(userId: number) sessions[userId] = nil end,
	})
end

return table.freeze({ new = new })
