--!strict
-- Client entry point.
--
-- Phase 3: the campaign. The campaign snapshot decides the screen: Character
-- Creator -> the Phase 1 Raining Carriage Crash tutorial -> Origin -> Public
-- Hub -> Act 1 map (F1 -> F2 -> D1) -> results and companion recruitment.
-- See Campaign/CampaignController.
--
-- Phase 2 test hook: set the workspace attribute PBA_StartInSandbox = true to
-- skip straight to the Black Sabbath Night sandbox (Combat HUD v2).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Contracts")

local SandboxController = require(script.Parent.Sandbox.SandboxController)
local CampaignController = require(script.Parent.Campaign.CampaignController)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

if workspace:GetAttribute("PBA_StartInSandbox") == true then
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PixelBattle"
	screenGui.Parent = playerGui
	SandboxController.run(screenGui)
	return
end

CampaignController.run(playerGui)
