--!strict

export type AssetId = string
export type AssetKey = "TutorialStage" | "PlayerIdle" | "DarioIdle" | "DarioWifeIdle" | "PocketWatchIcon"

-- Asset 0 is an unset placeholder. Render a local fallback for it.
local assets: { [AssetKey]: AssetId } = {
	TutorialStage = "rbxassetid://0",
	PlayerIdle = "rbxassetid://0",
	DarioIdle = "rbxassetid://0",
	DarioWifeIdle = "rbxassetid://0",
	PocketWatchIcon = "rbxassetid://0",
}

return table.freeze(assets)
