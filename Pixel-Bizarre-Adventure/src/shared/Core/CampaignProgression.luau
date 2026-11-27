--!strict

local Campaign = require("../Data/CampaignPartsData")
local Map = require("../Contracts/MapTypes")
local Save = require("../Contracts/SaveTypes")

export type Life = { id: string, settled: boolean, isFinalAttempt: boolean }
export type Event = {
	lifeId: string, battleId: string, act: number, part: number, nodeId: Map.NodeId,
	outcome: "Clear" | "Defeat", kitId: string?, years: number,
}
export type Bridge = {
	life: (number, boolean?) -> Life?,
	apply: (number, Event) -> boolean,
}
export type Saved = {
	lifeId: string?,
	clears: { [string]: { [Map.NodeId]: boolean } },
	pending: Event?,
}

local Progression = {}
function Progression.nodeId(id: unknown): boolean
	return id == "F1" or id == "F2" or id == "F3" or id == "F4" or id == "F5" or id == "F6" or id == "F7"
		or id == "D1" or id == "D2" or id == "D3" or id == "Castle"
end

function Progression.decode(value: unknown): Saved?
	if value == nil then return { clears = {} } end
	if type(value) ~= "table" then return nil end
	local raw = value :: { [string]: unknown }
	if type(raw.clears) ~= "table" or (raw.lifeId ~= nil and type(raw.lifeId) ~= "string") then return nil end
	for act, nodes in raw.clears :: { [string]: unknown } do
		if (act ~= "2" and act ~= "3" and act ~= "4" and act ~= "5") or type(nodes) ~= "table" then return nil end
		for id, cleared in nodes :: { [string]: unknown } do
			if not Progression.nodeId(id) or cleared ~= true then return nil end
		end
	end
	if raw.pending ~= nil then
		if type(raw.pending) ~= "table" then return nil end
		local event = raw.pending :: { [string]: unknown }
		local act, part, years = event.act, event.part, event.years
		if type(event.lifeId) ~= "string" or event.lifeId ~= raw.lifeId or type(event.battleId) ~= "string"
			or not Progression.nodeId(event.nodeId) or (event.outcome ~= "Clear" and event.outcome ~= "Defeat")
			or (event.outcome == "Defeat" and event.nodeId ~= "Castle")
			or type(act) ~= "number" or not (act >= 1 and act <= 5 and act % 1 == 0)
			or type(part) ~= "number" or not (part >= 1 and part <= 5 and part % 1 == 0)
			or type(years) ~= "number" or not (years >= 0 and years <= 4 and years % 1 == 0)
			or (event.kitId ~= nil and type(event.kitId) ~= "string") then return nil end
	end
	return raw :: Saved
end

function Progression.currentAct(progression: Saved, first: { [Map.NodeId]: boolean }): number
	if not first.Castle then return 1 end
	for act = 2, 4 do
		local clears = progression.clears[tostring(act)]
		if not clears or not clears.Castle then return act end
	end
	return 5
end

function Progression.part(origin: Save.Origin, act: number): Campaign.Part
	return Campaign.Parts[Campaign.OriginRoutes[origin][act].storyPart]
end

function Progression.node(origin: Save.Origin, act: number, id: Map.NodeId): Campaign.Node
	for _, node in Progression.part(origin, act).nodes do
		if node.id == id then return node end
	end
	error("Missing campaign catalog node")
end

-- Nine years per Act. The final Castle awards four years on a first clear.
-- Early flags and the three dungeons account for the other five.
function Progression.years(id: Map.NodeId): number
	if id == "Castle" then return 4 end
	return if id == "F1" or id == "F2" or id == "F4" or id == "D2" or id == "D3" then 1 else 0
end

return table.freeze(Progression)
