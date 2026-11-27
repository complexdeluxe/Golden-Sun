--!strict

local ActivityService = require("./ActivityService")
local BattleService = require("./BattleService")
local CampaignService = require("./CampaignService")
local Phase4Service = require("./Phase4Service")
local SaveService = require("./SaveService")
local SuccessionService = require("./SuccessionService")
local HttpService = game:GetService("HttpService")
local Succession = require("@game/ReplicatedStorage/Shared/Core/SuccessionSession")
local Activity = require("@game/ReplicatedStorage/Shared/Core/ActivitySession")
local Bridge = require("@game/ReplicatedStorage/Shared/Core/CampaignProgressionBridge")
local HeirReset = require("@game/ReplicatedStorage/Shared/Core/CampaignHeirReset")

-- Studio defaults to a server-local test profile. The published game uses DataStore.
-- Existing Studio API-enabled test places can enable the isolated Studio store.
local useStudioDataStore = game:GetService("ServerScriptService"):GetAttribute("UseTutorialDataStore") == true
local saves = SaveService.new(useStudioDataStore)
local checkHub: ((number) -> boolean)? = nil
local options: Succession.Options = {
	applyHeirReset = HeirReset.apply,
	clock = os.time,
	makeId = function() return HttpService:GenerateGUID(false) end,
	isSafeHub = function(userId: number): boolean
		return if checkHub then checkHub(userId) else false
	end,
}
local lineage = Succession.new(saves.campaign, options)
local activity = Activity.new(saves.campaign, options)
local campaignAccess = CampaignService.bind(saves.campaign, Bridge.new(lineage, activity))
checkHub = campaignAccess.isSafeHub
BattleService.bind(saves.tutorial, campaignAccess.recordOnboarding)
Phase4Service.bind(saves.campaign)
SuccessionService.bind(lineage, campaignAccess)
ActivityService.bind(activity, campaignAccess)
