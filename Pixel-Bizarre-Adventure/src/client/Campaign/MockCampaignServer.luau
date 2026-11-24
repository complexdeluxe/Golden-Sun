--!strict
-- Client-side stand-in for the Phase 3 campaign server (Codex's Stage 3.3).
--
-- Used only when ReplicatedStorage.Shared.CampaignRemotes does not exist. It
-- follows the frozen contract shapes so the Creator, Hub, Inventory, Act Map
-- and Results screens can be played in Studio before the real server lands.
-- Prices, rewards and stock here are placeholders, not design numbers.
--
-- The tutorial still runs on its own remotes. The controller tells the mock
-- when the tutorial and Origin are done (noteOrigin). The Act combat protocol
-- is not reviewed yet, so a mock encounter is finished with resolveEncounter.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CombatTypes = require(ReplicatedStorage.Shared.Contracts.CombatTypes)
local AppearanceTypes = require(ReplicatedStorage.Shared.Contracts.CharacterAppearanceTypes)
local HubTypes = require(ReplicatedStorage.Shared.Contracts.HubTypes)
local InventoryTypes = require(ReplicatedStorage.Shared.Contracts.InventoryTypes)
local MapTypes = require(ReplicatedStorage.Shared.Contracts.MapTypes)
local RemoteContract = require(ReplicatedStorage.Shared.Contracts.RemoteContract)
local SaveTypes = require(ReplicatedStorage.Shared.Contracts.SaveTypes)

type Snapshot = HubTypes.CampaignSnapshot
type Response = RemoteContract.CampaignResponse
type Legality = CombatTypes.ActionLegality
type Entry = InventoryTypes.InventoryEntry

local OK: Legality = { canUse = true }
local function blocked(reason: string): Legality
	return { canUse = false, disabledReason = reason }
end

local CATALOG: AppearanceTypes.Catalog = {
	defaultAppearance = { skinToneId = "Tan", hairStyleId = "buzz" },
	skinTones = {
		{ id = "Fair", label = "Fair", swatchHex = "#f1c9a5" },
		{ id = "Tan", label = "Tan", swatchHex = "#d9a066" },
		{ id = "Brown", label = "Brown", swatchHex = "#9c6b43" },
		{ id = "Deep", label = "Deep", swatchHex = "#5e3b25" },
	},
	hairStyles = {
		{ id = "buzz", label = "Buzz Cut", legality = OK },
		{ id = "pompadour", label = "Pompadour", legality = OK },
		{ id = "long", label = "Long", legality = OK },
		{ id = "spiky", label = "Spiky", legality = OK },
		{ id = "cap", label = "Cap", legality = OK },
		{ id = "bald", label = "Bald", legality = OK },
		{ id = "crown", label = "Crown Braid", legality = blocked("Unlocks in a later Act.") },
	},
}

type ItemDef = { itemId: string, label: string, description: string, iconKey: any, beltItemId: CombatTypes.BeltItemId? }

local ITEMS: { [string]: ItemDef } = {
	water = { itemId = "tonio-water", label = "Mineral Water", description = "Heals 25% Max HP.", iconKey = "MineralWaterIcon", beltItemId = "MineralWater" },
	gum = { itemId = "coffee-gum", label = "Coffee Gum", description = "Restores 1 Stamina.", iconKey = "CoffeeGumIcon", beltItemId = "CoffeeGum" },
	medkit = { itemId = "med-kit", label = "Med-Kit", description = "Heals 50% Max HP. 1 per fight.", iconKey = "MedKitIcon", beltItemId = "MedKit" },
	watch = { itemId = "pocket-watch", label = "Pocket Watch", description = "A keepsake. Not for the belt.", iconKey = "PocketWatchIcon" },
}

local GEAR = {
	gloves = { itemId = "ripple-gloves", label = "Ripple Gloves", description = "Worn by Hamon students.", slot = "Weapon", tier = 1, rarity = "Common", stats = { "+3 ATK" } },
	jacket = { itemId = "school-jacket", label = "School Jacket", description = "Long and dramatic.", slot = "Body", tier = 1, rarity = "Common", stats = { "+8 HP" } },
	bandana = { itemId = "red-bandana", label = "Red Bandana", description = "Keeps sweat out.", slot = "Head", tier = 1, rarity = "Rare", stats = { "+2 SPD", "+4 HP" } },
}

local LEVELS_ON_FIRST_CLEAR: { [string]: number } = { F1 = 1, F2 = 1, D1 = 2 }
local YEN_ON_CLEAR: { [string]: number } = { F1 = 15, F2 = 20, D1 = 40 }
local NODE_LABELS: { [string]: string } = { F1 = "Ogre Street", F2 = "Night Alley", D1 = "Old Mansion" }
local NODE_TAGS: { [string]: MapTypes.StageTag } = { F1 = "Neutral", F2 = "Night", D1 = "Sunlit" }
local PREREQS: { [string]: { MapTypes.NodeId } } = { F1 = {}, F2 = { "F1" }, D1 = { "F2" } }

type Stack = { key: string, entryId: string, quantity: number }
type Gear = { key: string, entryId: string }

type State = {
	revision: number,
	appearance: AppearanceTypes.Appearance?,
	tutorialCompleted: boolean,
	origin: SaveTypes.Origin?,
	level: number,
	yen: number,
	place: "Hub" | "ActMap" | "ActEncounter" | "ActResults",
	stacks: { Stack },
	gear: { Gear },
	equipped: { [string]: string },
	belt: { string | false },
	cleared: { [string]: boolean },
	discovered: { [string]: boolean },
	encounter: MapTypes.ActiveEncounter?,
	result: MapTypes.EncounterResult?,
	companion: "Locked" | "Offered" | "Recruited",
	encounterCount: number,
}

local SESSION = "mock-session"
local listeners: { (Snapshot) -> () } = {}
local state: State

local function reset()
	state = {
		revision = 1,
		appearance = nil,
		tutorialCompleted = false,
		origin = nil,
		level = 1,
		yen = 60,
		place = "Hub",
		stacks = {
			{ key = "water", entryId = "stack-water", quantity = 2 },
			{ key = "gum", entryId = "stack-gum", quantity = 1 },
			{ key = "medkit", entryId = "stack-medkit", quantity = 1 },
			{ key = "watch", entryId = "stack-watch", quantity = 1 },
		},
		gear = {
			{ key = "jacket", entryId = "gear-jacket" },
			{ key = "gloves", entryId = "gear-gloves" },
		},
		equipped = { Body = "gear-jacket" },
		belt = { "stack-water", "stack-gum", false },
		cleared = {},
		discovered = {},
		encounter = nil,
		result = nil,
		companion = "Locked",
		encounterCount = 0,
	}
end
reset()

local function display(def: ItemDef | any): InventoryTypes.ItemDisplay
	return { itemId = def.itemId, label = def.label, description = def.description, iconKey = def.iconKey }
end

local function findStack(entryId: string?): Stack?
	for _, stack in state.stacks do
		if stack.entryId == entryId then
			return stack
		end
	end
	return nil
end

local function findGear(entryId: string?): Gear?
	for _, gear in state.gear do
		if gear.entryId == entryId then
			return gear
		end
	end
	return nil
end

local function inventoryView(): InventoryTypes.InventoryView
	local entries: { Entry } = {}
	for _, gear in state.gear do
		local def = (GEAR :: any)[gear.key]
		table.insert(entries, {
			kind = "Gear",
			entryId = gear.entryId,
			item = display(def),
			slot = def.slot,
			tier = def.tier,
			rarity = def.rarity,
			baseStatLines = def.stats,
			equipLegality = OK,
		})
	end
	for _, stack in state.stacks do
		local def = ITEMS[stack.key]
		local legality = if def.beltItemId == nil then blocked("Not a belt item.") elseif stack.quantity <= 0 then blocked("Out of stock. Restock in the Shop.") else OK
		table.insert(entries, {
			kind = "Stack",
			entryId = stack.entryId,
			item = display(def),
			quantity = stack.quantity,
			beltItemId = def.beltItemId,
			beltLegality = legality,
		})
	end
	local gearSlots: { InventoryTypes.GearSlotView } = {}
	for _, slot in InventoryTypes.GearSlots do
		table.insert(gearSlots, { slot = slot, entryId = state.equipped[slot], legality = OK })
	end
	local belt: { InventoryTypes.BeltSlotView } = {}
	for index, entryId in state.belt do
		table.insert(belt, { index = index, entryId = if entryId then entryId else nil, legality = OK })
	end
	return { entries = entries, gear = gearSlots, belt = belt }
end

local function hubView(): HubTypes.HubView
	local offers: { HubTypes.ShopOffer } = {}
	local function supply(key: string, price: number, max: number)
		local def = ITEMS[key]
		local owned = findStack(`stack-{key}`)
		local room = max - (if owned then owned.quantity else 0)
		table.insert(offers, {
			id = `restock-{key}`,
			item = display(def),
			kind = "BeltSupply",
			unitPriceYen = price,
			maxQuantity = math.max(0, room),
			legality = if room <= 0 then blocked("You're carrying the most you can.") elseif state.yen < price then blocked("Not enough Yen.") else OK,
		})
	end
	supply("water", 10, 5)
	supply("gum", 8, 5)
	supply("medkit", 30, 2)
	local ownsBandana = findGear("gear-bandana") ~= nil
	table.insert(offers, {
		id = "gear-bandana",
		item = display(GEAR.bandana),
		kind = "Gear",
		unitPriceYen = 45,
		maxQuantity = if ownsBandana then 0 else 1,
		legality = if ownsBandana then blocked("Sold out.") elseif state.yen < 45 then blocked("Not enough Yen.") else OK,
	})
	local beltEmpty = true
	for _, entryId in state.belt do
		if entryId then
			beltEmpty = false
		end
	end
	return {
		shopOffers = offers,
		setOutLegality = if beltEmpty then blocked("Put at least one item on your belt.") else OK,
	}
end

local function nodeState(id: string): MapTypes.NodeState
	if state.cleared[id] then
		return "Cleared"
	end
	for _, prereq in PREREQS[id] do
		if not state.cleared[prereq] then
			return "Locked"
		end
	end
	return "Available"
end

local function mapView(): MapTypes.ActMapView
	local nodes: { MapTypes.NodeView } = {}
	for _, id in MapTypes.NodeOrder do
		local nodeStateValue = nodeState(id)
		local options: { MapTypes.PlayOption } = {}
		if nodeStateValue == "Cleared" then
			table.insert(options, { id = `{id}:T1:replay`, label = "Replay", mode = "Replay", tier = 1, levelsOnClear = 0, legality = OK })
			if state.discovered[id] then
				table.insert(options, {
					id = `{id}:T2:variant`, label = "Replay", mode = "Replay", tier = 2, levelsOnClear = 0,
					variantLabel = "Rain Variant", legality = blocked("Tier 2 opens at LV 5."),
				})
			end
		else
			table.insert(options, {
				id = `{id}:T1:first`, label = "Set Out", mode = "FirstClear", tier = 1, levelsOnClear = LEVELS_ON_FIRST_CLEAR[id],
				legality = if nodeStateValue == "Locked" then blocked(`Clear {PREREQS[id][1]} first.`) else OK,
			})
		end
		table.insert(nodes, {
			id = id,
			label = NODE_LABELS[id],
			prerequisites = PREREQS[id],
			state = nodeStateValue,
			stageTag = NODE_TAGS[id],
			playOptions = options,
		})
	end
	return { act = 1, part = if state.origin == "Part3_Stand" then 3 else 1, nodes = nodes }
end

local function companionView(): MapTypes.CompanionView
	local display = {
		companionId = "speedwagon",
		label = "Speedwagon",
		description = "A streetwise brawler who owes you one.",
		spriteKey = "CompanionIdle" :: any,
	}
	if state.companion == "Offered" then
		return { state = "Offered", offerId = "story-recruit", companionId = display.companionId, label = display.label, description = display.description, spriteKey = display.spriteKey, legality = OK }
	elseif state.companion == "Recruited" then
		return { state = "Recruited", companionId = display.companionId, label = display.label, description = display.description, spriteKey = display.spriteKey }
	end
	return { state = "Locked" }
end

local function scene(): HubTypes.Scene
	if state.appearance == nil then
		return { kind = "Creator", catalog = CATALOG }
	elseif not state.tutorialCompleted then
		return { kind = "Tutorial" }
	elseif state.origin == nil then
		return { kind = "OriginSelect" }
	elseif state.place == "ActMap" then
		return { kind = "ActMap", map = mapView() }
	elseif state.place == "ActEncounter" and state.encounter then
		return { kind = "ActEncounter", encounter = state.encounter }
	elseif state.place == "ActResults" and state.result then
		return { kind = "ActResults", result = state.result }
	end
	return { kind = "Hub", hub = hubView(), inventory = inventoryView() }
end

local function snapshot(): Snapshot
	return {
		sessionId = SESSION,
		revision = state.revision,
		character = {
			appearance = state.appearance,
			tutorialCompleted = state.tutorialCompleted,
			origin = state.origin,
			level = state.level,
			yen = state.yen,
		},
		scene = scene(),
		companion = companionView(),
	}
end

local function commit(): Response
	state.revision += 1
	local current = snapshot()
	return { ok = true, snapshot = current }
end

local function reject(code: RemoteContract.CampaignErrorCode, message: string): Response
	return { ok = false, code = code, message = message, snapshot = snapshot() }
end

local function publish()
	local current = snapshot()
	for _, listener in listeners do
		task.spawn(listener, current)
	end
end

local MockCampaignServer = {}

function MockCampaignServer.GetCampaignSnapshot(_request: RemoteContract.GetCampaignSnapshotRequest): Response
	return { ok = true, snapshot = snapshot() }
end

function MockCampaignServer.SubmitCampaignAction(request: RemoteContract.CampaignActionRequest): Response
	task.wait(0.05) -- Feel a little like a network call.
	if request.sessionId ~= SESSION then
		return reject("InvalidRequest", "That session has ended.")
	end
	if request.expectedRevision ~= state.revision then
		return reject("StaleRevision", "Out of date. Refreshed.")
	end
	local kind = scene().kind
	local action = request :: any

	if action.kind == "CommitAppearance" then
		if kind ~= "Creator" then
			return reject("IllegalAction", "Your look is already set.")
		end
		local skinOk = table.find(AppearanceTypes.SkinTones, action.appearance.skinToneId) ~= nil
		local hairOk = false
		for _, style in CATALOG.hairStyles do
			if style.id == action.appearance.hairStyleId and style.legality.canUse then
				hairOk = true
			end
		end
		if not skinOk or not hairOk then
			return reject("IllegalAction", "Pick an available skin tone and hairstyle.")
		end
		state.appearance = { skinToneId = action.appearance.skinToneId, hairStyleId = action.appearance.hairStyleId }
		return commit()
	elseif action.kind == "Navigate" then
		if kind ~= "Hub" and kind ~= "ActMap" and kind ~= "ActResults" then
			return reject("IllegalAction", "You can't leave right now.")
		end
		if action.destination == "ActMap" and kind == "Hub" then
			local legality = hubView().setOutLegality
			if not legality.canUse then
				return reject("IllegalAction", legality.disabledReason or "You can't set out yet.")
			end
		end
		state.place = action.destination
		state.result = nil
		return commit()
	elseif action.kind == "PurchaseOffer" then
		if kind ~= "Hub" then
			return reject("IllegalAction", "The Shop is in the Hub.")
		end
		local offer: HubTypes.ShopOffer? = nil
		for _, candidate in hubView().shopOffers do
			if candidate.id == action.offerId then
				offer = candidate
			end
		end
		if not offer then
			return reject("InvalidRequest", "That offer is gone.")
		end
		local quantity = action.quantity
		if type(quantity) ~= "number" or quantity < 1 or quantity % 1 ~= 0 then
			return reject("InvalidRequest", "Pick a quantity.")
		end
		if quantity > offer.maxQuantity then
			return reject("OutOfStock", "Not that many in stock.")
		end
		local cost = offer.unitPriceYen * quantity
		if cost > state.yen then
			return reject("InsufficientYen", "Not enough Yen.")
		end
		state.yen -= cost
		if offer.kind == "Gear" then
			table.insert(state.gear, { key = "bandana", entryId = "gear-bandana" })
		else
			local key = string.sub(offer.id, #"restock-" + 1)
			local stack = findStack(`stack-{key}`)
			if stack then
				stack.quantity += quantity
			else
				table.insert(state.stacks, { key = key, entryId = `stack-{key}`, quantity = quantity })
			end
		end
		return commit()
	elseif action.kind == "SetGearSlot" then
		if kind ~= "Hub" then
			return reject("IllegalAction", "Change gear in the Hub.")
		end
		local entryId = action.entryId
		if entryId == nil then
			state.equipped[action.slot] = nil
			return commit()
		end
		local gear = findGear(entryId)
		if not gear or (GEAR :: any)[gear.key].slot ~= action.slot then
			return reject("IllegalAction", "That doesn't go in this slot.")
		end
		for slot, equippedId in state.equipped do
			if equippedId == entryId then
				state.equipped[slot] = nil
			end
		end
		state.equipped[action.slot] = entryId
		return commit()
	elseif action.kind == "SetBeltSlot" then
		if kind ~= "Hub" then
			return reject("IllegalAction", "Change your belt in the Hub.")
		end
		local index = action.index
		if type(index) ~= "number" or state.belt[index] == nil then
			return reject("InvalidRequest", "No such belt slot.")
		end
		if action.entryId == nil then
			state.belt[index] = false
			return commit()
		end
		local stack = findStack(action.entryId)
		if not stack or ITEMS[stack.key].beltItemId == nil then
			return reject("IllegalAction", "That can't go on the belt.")
		end
		for other, entryId in state.belt do
			if entryId == action.entryId then
				state.belt[other] = false
			end
		end
		state.belt[index] = action.entryId
		return commit()
	elseif action.kind == "StartNode" then
		if kind ~= "ActMap" then
			return reject("IllegalAction", "Open the Act Map first.")
		end
		for _, node in mapView().nodes do
			if node.id == action.nodeId then
				for _, option in node.playOptions do
					if option.id == action.playOptionId then
						if not option.legality.canUse then
							return reject("NodeLocked", option.legality.disabledReason or "Locked.")
						end
						state.encounterCount += 1
						state.encounter = {
							encounterId = `mock-{node.id}-{state.encounterCount}`,
							battleId = `mock-battle-{state.encounterCount}`,
							nodeId = node.id,
							mode = option.mode,
							stageTag = node.stageTag,
						}
						state.place = "ActEncounter"
						return commit()
					end
				end
			end
		end
		return reject("InvalidRequest", "Unknown node or option.")
	elseif action.kind == "RecruitCompanion" then
		if state.companion ~= "Offered" or action.offerId ~= "story-recruit" then
			return reject("IllegalAction", "No one is waiting to join.")
		end
		state.companion = "Recruited"
		return commit()
	end
	return reject("InvalidRequest", "Unknown action.")
end

function MockCampaignServer.onChanged(listener: (Snapshot) -> ())
	table.insert(listeners, listener)
end

-- Mock-only: the tutorial flow reports the saved Origin (or an earlier save).
function MockCampaignServer.noteOrigin(origin: SaveTypes.Origin)
	state.tutorialCompleted = true
	state.origin = origin
	state.place = "Hub"
	state.revision += 1
	publish()
end

-- Mock-only: finish the active encounter, since Act combat is not wired yet.
function MockCampaignServer.resolveEncounter(outcome: "Clear" | "Defeat" | "Retreat")
	local encounter = state.encounter
	if state.place ~= "ActEncounter" or not encounter then
		return
	end
	local node = encounter.nodeId
	local firstClear = encounter.mode == "FirstClear" and outcome == "Clear"
	local levels = if firstClear then LEVELS_ON_FIRST_CLEAR[node] else 0
	local yen = if outcome == "Clear" then (if firstClear then YEN_ON_CLEAR[node] else YEN_ON_CLEAR[node] // 3) else 0
	local items: { MapTypes.ItemReward } = {}
	if outcome == "Clear" then
		table.insert(items, { item = display(ITEMS.water), quantity = 1 })
		local water = findStack("stack-water")
		if water then
			water.quantity += 1
		end
	end
	-- Belt items spent in the fight (placeholder: one Water on a clear or defeat).
	if outcome ~= "Retreat" then
		local water = findStack("stack-water")
		if water and water.quantity > 0 then
			water.quantity -= 1
		end
	end
	state.level += levels
	state.yen += yen
	if outcome == "Clear" then
		if firstClear then
			state.cleared[node] = true
		else
			state.discovered[node] = true
		end
		if node == "D1" and firstClear and state.companion == "Locked" then
			state.companion = "Offered"
		end
	end
	state.result = {
		encounterId = encounter.encounterId,
		nodeId = node,
		mode = encounter.mode,
		outcome = outcome,
		rewards = { yen = yen, levels = levels, items = items },
	}
	state.encounter = nil
	state.place = "ActResults"
	state.revision += 1
	publish()
end

-- Test hook: start over with a fresh profile.
function MockCampaignServer.reset()
	reset()
end

return MockCampaignServer
