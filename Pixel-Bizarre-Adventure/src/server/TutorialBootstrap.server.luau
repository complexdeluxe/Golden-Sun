--!strict

local BattleService = require("./BattleService")
local SaveService = require("./SaveService")

-- Studio defaults to a server-local test profile. The published game uses DataStore.
-- Existing Studio API-enabled test places can enable the isolated Studio store.
local useStudioDataStore = game:GetService("ServerScriptService"):GetAttribute("UseTutorialDataStore") == true
BattleService.bind(SaveService.new(useStudioDataStore))
