--!strict

local Assets = require("../Contracts/AssetManifest")
local Map = require("../Contracts/MapTypes")
local Save = require("../Contracts/SaveTypes")
local Battle = require("../Core/BlackSabbathBattle")

type Recruit = {
	companionId: Map.CompanionId,
	label: string,
	description: string,
	spriteKey: Assets.AssetKey?,
}

type Route = {
	waves: { [Map.NodeId]: { Battle.ActOpponent } },
	recruit: Recruit,
}

local routes: { [Save.Origin]: Route } = {
	Part1_Hamon = {
		waves = {
			F1 = {
				{ id = "ogre_brawler", spriteKey = "OgreBrawlerIdle", label = "Ogre Street Brawler", jabLabel = "Street Jab", heavyLabel = "Heavy Hook" },
			},
			F2 = {
				{ id = "ogre_knifeman", spriteKey = "OgreKnifemanIdle", label = "Ogre Street Knifeman", jabLabel = "Knife Jab", heavyLabel = "Bleeding Slash",
					hp = 52, jabPower = 8, heavyPower = 15, heavyStatus = "Bleed" },
			},
			D1 = {
				{ id = "ogre_lookout", spriteKey = "OgreLookoutIdle", label = "Ogre Street Lookout", jabLabel = "Street Jab", heavyLabel = "Rally Rush", hp = 30, jabPower = 6, heavyPower = 12 },
				{ id = "speedwagon", spriteKey = "CompanionIdle", label = "Speedwagon", jabLabel = "Street Counter", heavyLabel = "Blade Hat Toss", hp = 54, jabPower = 8, heavyPower = 16 },
			},
		},
		recruit = { companionId = "speedwagon", label = "Speedwagon", description = "A streetwise ally from Ogre Street.", spriteKey = "CompanionIdle" },
	},
	Part3_Stand = {
		waves = {
			F1 = {
				{ id = "jail_thug", spriteKey = "JailThugIdle", label = "Stand-Awakened Jail Thug", jabLabel = "Stand Jab", heavyLabel = "Cell Rush" },
			},
			F2 = {
				{ id = "kakyoin", spriteKey = "KakyoinIdle", label = "Kakyoin", jabLabel = "Emerald Splash", heavyLabel = "Barrier Snare",
					hp = 52, jabPower = 8, heavyPower = 14, heavyStatus = "Stun" },
			},
			D1 = {
				{ id = "harbor_duelist", spriteKey = "HarborDuelistIdle", label = "Harbor Sword Duelist", jabLabel = "Blade Tap", heavyLabel = "Windup Lunge", hp = 30, jabPower = 6, heavyPower = 12 },
				{ id = "avdol", spriteKey = "AvdolIdle", label = "Avdol", jabLabel = "Flame Jab", heavyLabel = "Fire Lane", hp = 54, jabPower = 8, heavyPower = 16 },
			},
		},
		recruit = { companionId = "avdol", label = "Avdol", description = "A Stand user who guided you through the Tiger Balm Garden spar.", spriteKey = "AvdolIdle" },
	},
}

local firstClearYen: { [Map.NodeId]: number } = { F1 = 12, F2 = 18, D1 = 30 }

return table.freeze({ Routes = routes, FirstClearYen = firstClearYen })
