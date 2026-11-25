--!strict

local Appearance = require("../Contracts/CharacterAppearanceTypes")
local Combat = require("../Contracts/CombatTypes")
local Hub = require("../Contracts/HubTypes")
local Inventory = require("../Contracts/InventoryTypes")
local Map = require("../Contracts/MapTypes")
local Remote = require("../Contracts/RemoteContract")
local Save = require("../Contracts/SaveTypes")
local Starter = require("../Data/CampaignStarter")

export type Profile = {
	version: number,
	appearance: Appearance.Appearance?,
	yen: number,
	stock: { [string]: number },
	gear: { [Inventory.GearSlot]: string },
	belt: { [string]: string },
}
export type Destination = "Hub" | "ActMap"

local OK: Combat.ActionLegality = { canUse = true }
local Profile = {}

local function blocked(reason: string): Combat.ActionLegality
	return { canUse = false, disabledReason = reason }
end

local function integer(value: unknown, minimum: number, maximum: number): boolean
	return type(value) == "number" and value >= minimum and value <= maximum and value % 1 == 0
end

function Profile.appearance(value: unknown): Appearance.Appearance?
	if type(value) ~= "table" then return nil end
	local fields = value :: { [string]: unknown }
	for _, skin in Starter.Catalog.skinTones do
		if skin.id ~= fields.skinToneId then continue end
		for _, hair in Starter.Catalog.hairStyles do
			if hair.id == fields.hairStyleId and hair.legality.canUse then
				return { skinToneId = skin.id, hairStyleId = hair.id }
			end
		end
	end
	return nil
end

function Profile.decode(value: unknown): Profile?
	if value == nil then
		return {
			version = 1, yen = Starter.StartingYen, stock = { ["training-wraps"] = 1, ["tonio-water"] = 2, ["med-kit"] = 1 },
			gear = {}, belt = {},
		}
	end
	if type(value) ~= "table" then return nil end
	local raw = value :: { [string]: unknown }
	if raw.version ~= 1 or not integer(raw.yen, 0, 2 ^ 53 - 1) or type(raw.stock) ~= "table"
		or type(raw.gear) ~= "table" or type(raw.belt) ~= "table" then return nil end

	local appearance = Profile.appearance(raw.appearance)
	if raw.appearance ~= nil and not appearance then return nil end
	local stock: { [string]: number } = {}
	for id, quantity in raw.stock :: { [string]: unknown } do
		local item = Starter.Items[id]
		if not item or not integer(quantity, 0, if item.gearSlot then 1 else 2 ^ 53 - 1) then return nil end
		stock[id] = quantity :: number
	end

	local gear: { [Inventory.GearSlot]: string } = {}
	for slot, id in raw.gear :: { [string]: unknown } do
		if type(id) ~= "string" then return nil end
		local item = Starter.Items[id]
		if not item or item.gearSlot ~= slot or (stock[id] or 0) == 0 then return nil end
		gear[slot :: Inventory.GearSlot] = id
	end

	local belt: { [string]: string } = {}
	local equipped: { [string]: boolean } = {}
	for slot, id in raw.belt :: { [string]: unknown } do
		local index = tonumber(slot)
		if type(id) ~= "string" or not index or tostring(index) ~= slot or not integer(index, 1, Starter.BeltSlots) then return nil end
		local item = Starter.Items[id]
		if not item or not item.beltItemId or stock[id] == nil or equipped[id] then return nil end
		belt[slot] = id
		equipped[id] = true
	end

	return { version = 1, appearance = appearance, yen = raw.yen :: number, stock = stock, gear = gear, belt = belt }
end

local function shop(profile: Profile): { Hub.ShopOffer }
	local offers: { Hub.ShopOffer } = {}
	for _, id in Starter.ItemOrder do
		local item = Starter.Items[id]
		local offer = item.offer
		if not offer then continue end
		local room = math.max(0, offer.cap - (profile.stock[id] or 0))
		local maxQuantity = math.min(room, math.floor(profile.yen / offer.price))
		local view: Hub.ShopOffer = {
			id = id, item = item.display, kind = if item.gearSlot then "Gear" else "BeltSupply",
			unitPriceYen = offer.price, maxQuantity = maxQuantity,
			legality = if room == 0 then blocked("Stock limit reached.")
				elseif maxQuantity == 0 then blocked("Not enough Yen.") else OK,
		}
		table.insert(offers, view)
	end
	return offers
end

local function inventory(profile: Profile): Inventory.InventoryView
	local entries: { Inventory.InventoryEntry } = {}
	for _, id in Starter.ItemOrder do
		local quantity = profile.stock[id]
		if quantity == nil then continue end
		local item = Starter.Items[id]
		if item.gearSlot and quantity > 0 then
			table.insert(entries, {
				kind = "Gear" :: "Gear", entryId = id, item = item.display, slot = item.gearSlot, tier = 1,
				rarity = "Common" :: "Common", baseStatLines = item.baseStatLines or {}, equipLegality = OK,
			})
		elseif item.beltItemId then
			table.insert(entries, {
				kind = "Stack" :: "Stack", entryId = id, item = item.display, quantity = quantity, beltItemId = item.beltItemId,
				beltLegality = if quantity > 0 then OK else blocked("Restock this item first."),
			})
		end
	end
	local gear: { Inventory.GearSlotView } = {}
	for _, slot in Inventory.GearSlots do
		table.insert(gear, { slot = slot, entryId = profile.gear[slot], legality = OK })
	end
	local belt: { Inventory.BeltSlotView } = {}
	for index = 1, Starter.BeltSlots do
		table.insert(belt, { index = index, entryId = profile.belt[tostring(index)], legality = OK })
	end
	return { entries = entries, gear = gear, belt = belt }
end

function Profile.scene(profile: Profile, tutorial: Save.Profile, destination: Destination): Hub.Scene
	if not profile.appearance then return { kind = "Creator", catalog = Starter.Catalog } end
	if not tutorial.tutorialCompleted then return { kind = "Tutorial" } end
	local origin = tutorial.origin
	if not origin then return { kind = "OriginSelect" } end
	if destination == "ActMap" then
		local blockedStart: Map.PlayOption = {
			id = "F1:first", label = "Set out", mode = "FirstClear", tier = 1, levelsOnClear = 1,
			legality = blocked("Act combat is awaiting integration."),
		}
		local route = Starter.ActOneRoutes[origin]
		local nodes: { Map.NodeView } = {}
		for index, nodeId in Map.NodeOrder do
			local stage = route.stages[nodeId]
			local previous = Map.NodeOrder[index - 1]
			local node: Map.NodeView = {
				id = nodeId, label = stage.label, stageTag = stage.tag, stageAssetKey = stage.assetKey,
				prerequisites = if previous then { previous } else {},
				state = if previous then "Locked" else "Available",
				playOptions = if previous then {} else { blockedStart },
			}
			table.insert(nodes, node)
		end
		return { kind = "ActMap", map = { act = 1, part = route.part, nodes = nodes } }
	end
	return { kind = "Hub", hub = { shopOffers = shop(profile), setOutLegality = OK }, inventory = inventory(profile) }
end

function Profile.update(
	profile: Profile, request: Remote.CampaignActionRequest
): (Profile?, Remote.CampaignErrorCode?, string?)
	local updated = table.clone(profile)
	if request.kind == "CommitAppearance" then
		local appearance = Profile.appearance(request.appearance)
		if not appearance then return nil, "IllegalAction", "Choose an available appearance." end
		updated.appearance = appearance
	elseif request.kind == "PurchaseOffer" then
		local item = Starter.Items[request.offerId]
		local offer = if item then item.offer else nil
		local amount = request.quantity
		if not offer or not integer(amount, 1, 100) then return nil, "InvalidRequest", "Choose a valid offer and amount." end
		local stock = profile.stock[request.offerId] or 0
		if stock + amount > offer.cap then return nil, "OutOfStock", "Stock limit reached." end
		local total = offer.price * amount
		if total > profile.yen then return nil, "InsufficientYen", "Not enough Yen." end
		updated.yen -= total
		updated.stock = table.clone(profile.stock)
		updated.stock[request.offerId] = stock + amount
	elseif request.kind == "SetGearSlot" then
		local slot, id = request.slot, request.entryId
		if id then
			local item = Starter.Items[id]
			if not item or item.gearSlot ~= slot or (profile.stock[id] or 0) == 0 then
				return nil, "IllegalAction", "Choose owned gear for that slot."
			end
		end
		updated.gear = table.clone(profile.gear)
		updated.gear[slot] = id
	elseif request.kind == "SetBeltSlot" then
		local index, id = request.index, request.entryId
		if not integer(index, 1, Starter.BeltSlots) then return nil, "InvalidRequest", "Choose a valid belt slot." end
		local slot = tostring(index)
		if id then
			local item = Starter.Items[id]
			if not item or not item.beltItemId or (profile.stock[id] or 0) == 0 then
				return nil, "IllegalAction", "Choose an owned belt item."
			end
			for other, equipped in profile.belt do
				if equipped == id and other ~= slot then return nil, "IllegalAction", "That item is already on the belt." end
			end
		end
		updated.belt = table.clone(profile.belt)
		updated.belt[slot] = id
	else
		return nil, "IllegalAction", "This action does not update the profile."
	end
	return updated, nil, nil
end

return table.freeze(Profile)
