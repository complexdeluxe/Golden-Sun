--!strict

local Appearance = require("./CharacterAppearanceTypes")
local Combat = require("./CombatTypes")
local Inventory = require("./InventoryTypes")
local Map = require("./MapTypes")
local Save = require("./SaveTypes")

export type ShopOfferId = string

export type ShopOffer = {
	id: ShopOfferId,
	item: Inventory.ItemDisplay,
	kind: "Gear" | "BeltSupply",
	unitPriceYen: number,
	maxQuantity: number,
	legality: Combat.ActionLegality,
}

export type HubView = {
	shopOffers: { ShopOffer },
	setOutLegality: Combat.ActionLegality,
}

export type Scene =
	{ kind: "Creator", catalog: Appearance.Catalog }
	| { kind: "Tutorial" }
	| { kind: "OriginSelect" }
	| { kind: "Hub", hub: HubView, inventory: Inventory.InventoryView }
	| { kind: "ActMap", map: Map.ActMapView }
	| { kind: "ActEncounter", encounter: Map.ActiveEncounter }
	| { kind: "ActResults", result: Map.EncounterResult }

export type CampaignSnapshot = {
	-- Revision is monotonic within a server-assigned profile session.
	sessionId: string,
	revision: number,
	character: {
		appearance: Appearance.Appearance?,
		tutorialCompleted: boolean,
		origin: Save.Origin?,
		level: number,
		yen: number,
	},
	scene: Scene,
	companion: Map.CompanionView,
}

return table.freeze({})
