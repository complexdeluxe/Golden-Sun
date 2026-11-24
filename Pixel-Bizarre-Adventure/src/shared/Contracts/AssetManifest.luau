--!strict

export type AssetId = string
export type AssetKey = "TutorialStage" | "PlayerIdle" | "DarioIdle" | "DarioWifeIdle" | "PocketWatchIcon"
	| "BlackSabbathStage" | "BlackSabbathIdle" | "CompanionIdle" | "MineralWaterIcon" | "CapreseSaladIcon" | "MedKitIcon" | "CoffeeGumIcon" | "BloodVialIcon" | "UVFlashIcon" | "SmellingSaltsIcon" | "SmokePelletIcon" | "PassioneEspressoIcon" | "SpikedWhetstoneIcon"

-- Asset 0 is an unset placeholder. Render a local fallback for it.
local assets: { [AssetKey]: AssetId } = {
	TutorialStage = "rbxassetid://0",
	PlayerIdle = "rbxassetid://0",
	DarioIdle = "rbxassetid://0",
	DarioWifeIdle = "rbxassetid://0",
	PocketWatchIcon = "rbxassetid://0",
	BlackSabbathStage = "rbxassetid://0",
	BlackSabbathIdle = "rbxassetid://0",
	CompanionIdle = "rbxassetid://0",
	MineralWaterIcon = "rbxassetid://0",
	CapreseSaladIcon = "rbxassetid://0",
	MedKitIcon = "rbxassetid://0",
	CoffeeGumIcon = "rbxassetid://0",
	BloodVialIcon = "rbxassetid://0",
	UVFlashIcon = "rbxassetid://0",
	SmellingSaltsIcon = "rbxassetid://0",
	SmokePelletIcon = "rbxassetid://0",
	PassioneEspressoIcon = "rbxassetid://0",
	SpikedWhetstoneIcon = "rbxassetid://0",
}

return table.freeze(assets)
