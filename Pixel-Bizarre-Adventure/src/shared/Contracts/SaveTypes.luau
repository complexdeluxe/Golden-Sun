--!strict

export type Origin = "Part1_Hamon" | "Part3_Stand"

export type Profile = {
	version: number,
	tutorialCompleted: boolean,
	origin: Origin?,
}

-- Add future persisted fields under a new version and migrate saved profiles.
return table.freeze({
	PROFILE_VERSION = 1,
})
