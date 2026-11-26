--!strict

local BattleService = require("./BattleService")
local CampaignService = require("./CampaignService")
local Phase4Service = require("./Phase4Service")
local SaveService = require("./SaveService")
local SuccessionService = require("./SuccessionService")

-- Studio defaults to a server-local test profile. The published game uses DataStore.
-- Existing Studio API-enabled test places can enable the isolated Studio store.
local useStudioDataStore = game:GetService("ServerScriptService"):GetAttribute("UseTutorialDataStore") == true
local saves = SaveService.new(useStudioDataStore)
BattleService.bind(saves.tutorial)
local campaignAccess = CampaignService.bind(saves.campaign)
Phase4Service.bind(saves.campaign)
SuccessionService.bind(saves.campaign, campaignAccess)
