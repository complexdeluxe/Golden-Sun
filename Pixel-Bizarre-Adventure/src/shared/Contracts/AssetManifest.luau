--!strict

export type AssetId = string
export type AssetKey = "TutorialStage" | "PlayerIdle" | "DarioIdle" | "DarioWifeIdle" | "PocketWatchIcon"
	| "BlackSabbathStage" | "BlackSabbathIdle" | "CompanionIdle" | "MineralWaterIcon" | "CapreseSaladIcon" | "MedKitIcon" | "CoffeeGumIcon" | "BloodVialIcon" | "UVFlashIcon" | "SmellingSaltsIcon" | "SmokePelletIcon" | "PassioneEspressoIcon" | "SpikedWhetstoneIcon"
	| "TrainingWrapsIcon"
	| "BrimmedCapIcon"
	| "PaddedHeadguardIcon"
	| "QuiltedJacketIcon"
	| "RunnersVestIcon"
	| "AnubisCursedKatanaIcon"
	| "BalancedGripsIcon"
	| "ClackerVolleyIcon"
	| "EmperorsRevolverIcon"
	| "FocusingBeadsIcon"
	| "GlassCharmIcon"
	| "HandMirrorIcon"
	| "IronSignetIcon"
	| "LuckAndPluckIcon"
	| "TarotFocusDeckIcon"
	| "FieldDressingIcon"
	| "ScoutingMapIcon"
	| "HolyWaterIcon"
	| "ZeppelisCheckeredHatIcon"
	| "CaesarsHeadbandIcon"
	| "JotarosTornCapIcon"
	| "JosukesPeacePinIcon"
	| "BrunosZipperBroochIcon"
	| "OpticalTargetingLensIcon"
	| "StroheimUVVisorIcon"
	| "HydraulicCrushArmIcon"
	| "AbdominalAutocannonIcon"
	| "OverclockCoProcessorIcon"
	| "OverclockedAjaCoreIcon"
	| "StandArrowIcon"
	| "StandArrowKeyArt"
	| "RequiemArrowIcon"
	| "RokakaFruitIcon"
	| "GoldenAppleIcon"
	| "StoneMaskIcon"
	| "RedStoneOfAjaIcon"
	| "DiosDiaryIcon"
	| "StandDiscIcon"
	| "RacePhialIcon"
	| "ResonanceShardIcon"
	| "SalvageShardsIcon"
	| "ExpeditionTicketIcon"
	| "IceDemonCrownIcon"
	| "IceDemonCoatIcon"
	| "UltimateLifeformCrestIcon"
	| "UltimateLifeformGarbIcon"
	| "CrusadersWorldHelmIcon"
	| "CrusadersWorldJacketIcon"
	| "QuietLifeCrestIcon"
	| "QuietLifeSuitIcon"
	| "CrimsonEmperorCrownIcon"
	| "CrimsonEmperorVestIcon"
	| "PlayerBodyFair"
	| "PlayerBodyTan"
	| "PlayerBodyBrown"
	| "PlayerBodyDeep"
	| "HairBuzz"
	| "HairPompadour"
	| "HairLong"
	| "HairSpiky"
	| "HairCap"
	| "HairCapTrim"
	| "OgreStreetStage"
	| "NightAlleyStage"
	| "OgreHideoutStage"
	| "TokyoJailStage"
	| "TokyoSchoolyardStage"
	| "TigerBalmGardenStage"
	| "DioCastleStage"
	| "RomeCatacombsStage"
	| "SkeletonHeelStoneStage"
	| "CalcuttaStage"
	| "DesertedTownStage"
	| "CairoRoadStage"
	| "CairoAlleyStage"
	| "DioMansionGatesStage"
	| "DioMansionHallStage"
	| "CairoBridgeStage"
	| "MoriohTownStage"
	| "NijimuraHouseStage"
	| "BoyoyoingCapeStage"
	| "TailorDistrictStage"
	| "KiraEstateStage"
	| "ChaosInMoriohStage"
	| "NaplesTrainStationStage"
	| "VeniceCanalsStage"
	| "RomeStreetsStage"
	| "RomeOutskirtsStage"
	| "RomanColosseumStage"
	| "RomeSanctumStage"

	| "OgreBrawlerIdle"
	| "OgreKnifemanIdle"
	| "OgreLookoutIdle"
	| "JailThugIdle"
	| "HarborDuelistIdle"
	| "KakyoinIdle"
	| "AvdolIdle"
	| "HierophantGreenSheet"
	| "MagiciansRedSheet"
	| "SilverChariotSheet"
	| "StarPlatinumSheet"
	| "TheWorldSheet"
	| "EmperorSheet"
	| "AnubisSheet"

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
	TrainingWrapsIcon = "rbxassetid://0", -- [32x32] CampaignStarter training-wraps
	BrimmedCapIcon = "rbxassetid://0", -- [32x32] CampaignStarter brimmed-cap
	PaddedHeadguardIcon = "rbxassetid://0", -- [32x32] Padded Headguard
	QuiltedJacketIcon = "rbxassetid://0", -- [32x32] Quilted Jacket
	RunnersVestIcon = "rbxassetid://0", -- [32x32] Runner's Vest
	AnubisCursedKatanaIcon = "rbxassetid://0", -- [32x32] Anubis Cursed Katana
	BalancedGripsIcon = "rbxassetid://0", -- [32x32] Balanced Grips
	ClackerVolleyIcon = "rbxassetid://0", -- [32x32] Clacker Volley
	EmperorsRevolverIcon = "rbxassetid://0", -- [32x32] Emperor's Revolver
	FocusingBeadsIcon = "rbxassetid://0", -- [32x32] Focusing Beads
	GlassCharmIcon = "rbxassetid://0", -- [32x32] Glass Charm
	HandMirrorIcon = "rbxassetid://0", -- [32x32] Hand Mirror
	IronSignetIcon = "rbxassetid://0", -- [32x32] Iron Signet
	LuckAndPluckIcon = "rbxassetid://0", -- [32x32] Luck & Pluck
	TarotFocusDeckIcon = "rbxassetid://0", -- [32x32] Tarot Focus Deck
	FieldDressingIcon = "rbxassetid://0", -- [32x32] Field Dressing
	ScoutingMapIcon = "rbxassetid://0", -- [32x32] Scouting Map
	HolyWaterIcon = "rbxassetid://0", -- [32x32] Holy Water (Cursed purification)
	ZeppelisCheckeredHatIcon = "rbxassetid://0", -- [32x32] Zeppeli's Checkered Hat
	CaesarsHeadbandIcon = "rbxassetid://0", -- [32x32] Caesar's Headband
	JotarosTornCapIcon = "rbxassetid://0", -- [32x32] Jotaro's Torn Cap
	JosukesPeacePinIcon = "rbxassetid://0", -- [32x32] Josuke's Peace Pin
	BrunosZipperBroochIcon = "rbxassetid://0", -- [32x32] Bruno's Zipper Brooch
	OpticalTargetingLensIcon = "rbxassetid://0", -- [32x32] Optical Targeting Lens
	StroheimUVVisorIcon = "rbxassetid://0", -- [32x32] Stroheim UV Visor
	HydraulicCrushArmIcon = "rbxassetid://0", -- [32x32] Hydraulic Crush Arm
	AbdominalAutocannonIcon = "rbxassetid://0", -- [32x32] Abdominal Autocannon
	OverclockCoProcessorIcon = "rbxassetid://0", -- [32x32] Overclock Co-Processor
	OverclockedAjaCoreIcon = "rbxassetid://0", -- [32x32] Overclocked Aja Core
	StandArrowIcon = "rbxassetid://0", -- [32x32] Native 32x32 inventory icon
	StandArrowKeyArt = "rbxassetid://0", -- [high-res] High-res Awakening modal ONLY (never grid)
	RequiemArrowIcon = "rbxassetid://0", -- [32x32] Requiem Arrow
	RokakaFruitIcon = "rbxassetid://0", -- [32x32] Rokaka Fruit
	GoldenAppleIcon = "rbxassetid://0", -- [32x32] The Golden Apple
	StoneMaskIcon = "rbxassetid://0", -- [32x32] Stone Mask
	RedStoneOfAjaIcon = "rbxassetid://0", -- [32x32] Red Stone of Aja
	DiosDiaryIcon = "rbxassetid://0", -- [32x32] DIO's Diary
	StandDiscIcon = "rbxassetid://0", -- [32x32] Stand Disc
	RacePhialIcon = "rbxassetid://0", -- [32x32] Race Phial
	ResonanceShardIcon = "rbxassetid://0", -- [32x32] Resonance Shard
	SalvageShardsIcon = "rbxassetid://0", -- [32x32] Salvage Shards
	ExpeditionTicketIcon = "rbxassetid://0", -- [32x32] Expedition Ticket
	IceDemonCrownIcon = "rbxassetid://0", -- [32x32] P1 Dio Head
	IceDemonCoatIcon = "rbxassetid://0", -- [32x32] P1 Dio Body
	UltimateLifeformCrestIcon = "rbxassetid://0", -- [32x32] P2 Kars Head
	UltimateLifeformGarbIcon = "rbxassetid://0", -- [32x32] P2 Kars Body
	CrusadersWorldHelmIcon = "rbxassetid://0", -- [32x32] P3 DIO Head
	CrusadersWorldJacketIcon = "rbxassetid://0", -- [32x32] P3 DIO Body
	QuietLifeCrestIcon = "rbxassetid://0", -- [32x32] P4 Kira Head
	QuietLifeSuitIcon = "rbxassetid://0", -- [32x32] P4 Kira Body
	CrimsonEmperorCrownIcon = "rbxassetid://0", -- [32x32] P5 Diavolo Head
	CrimsonEmperorVestIcon = "rbxassetid://0", -- [32x32] P5 Diavolo Body
	PlayerBodyFair = "rbxassetid://0", -- [96x96] SkinTone Fair
	PlayerBodyTan = "rbxassetid://0", -- [96x96] SkinTone Tan (Default)
	PlayerBodyBrown = "rbxassetid://0", -- [96x96] SkinTone Brown
	PlayerBodyDeep = "rbxassetid://0", -- [96x96] SkinTone Deep
	HairBuzz = "rbxassetid://0", -- [96x96] Hair ID: buzz (Tintable in Hair/Tintable/)
	HairPompadour = "rbxassetid://0", -- [96x96] Hair ID: pompadour (Tintable in Hair/Tintable/)
	HairLong = "rbxassetid://0", -- [96x96] Hair ID: long (Tintable in Hair/Tintable/)
	HairSpiky = "rbxassetid://0", -- [96x96] Hair ID: spiky (Tintable in Hair/Tintable/)
	HairCap = "rbxassetid://0", -- [96x96] Hair ID: cap (Tintable in Hair/Tintable/)
	HairCapTrim = "rbxassetid://0", -- [96x96] Optional Layer-3 untinted gold pins/cord for tinted HairCap
	OgreStreetStage = "rbxassetid://0", -- [320x180] Part 1 F1 Ogre Street
	NightAlleyStage = "rbxassetid://0", -- [320x180] Part 1 F2 Night Alley
	OgreHideoutStage = "rbxassetid://0", -- [320x180] Part 1 D1 Ogre Street Hideout
	TokyoJailStage = "rbxassetid://0", -- [320x180] Part 3 F1 Tokyo Jail
	TokyoSchoolyardStage = "rbxassetid://0", -- [320x180] Part 3 F2 Tokyo Schoolyard
	TigerBalmGardenStage = "rbxassetid://0", -- [320x180] Part 3 D1 Tiger Balm Garden
	DioCastleStage = "rbxassetid://0", -- [320x180] Part 1 Castle
	RomeCatacombsStage = "rbxassetid://0", -- [320x180] NEEDS FIX: MUGEN Awakening preview is black layer
	SkeletonHeelStoneStage = "rbxassetid://0", -- [320x180] Part 2 D3 Wamuu Arena (Verified)
	CalcuttaStage = "rbxassetid://0", -- [320x180] NEEDS FIX: MUGEN Calcutta preview has red tint
	DesertedTownStage = "rbxassetid://0", -- [320x180] NEEDS FIX: MUGEN preview is sky-gradient only
	CairoRoadStage = "rbxassetid://0", -- [320x180] NEEDS FIX: MUGEN magenta cutout mask
	CairoAlleyStage = "rbxassetid://0", -- [320x180] NEEDS FIX: MUGEN preview is sky-only layer
	DioMansionGatesStage = "rbxassetid://0", -- [320x180] Part 3 F7 Mansion Gates (Verified)
	DioMansionHallStage = "rbxassetid://0", -- [320x180] Part 3 D3 Vanilla Ice (Verified)
	CairoBridgeStage = "rbxassetid://0", -- [320x180] Part 3 Castle DIO (Verified)
	MoriohTownStage = "rbxassetid://0", -- [320x180] Part 4 F1 Morioh Station (Verified)
	NijimuraHouseStage = "rbxassetid://0", -- [320x180] Part 4 F2 Nijimura House (Verified)
	BoyoyoingCapeStage = "rbxassetid://0", -- [320x180] NEEDS FIX: MUGEN preview is sky-only layer
	TailorDistrictStage = "rbxassetid://0", -- [320x180] NEEDS FIX: MUGEN magenta cutout mask
	KiraEstateStage = "rbxassetid://0", -- [320x180] NEEDS FIX: MUGEN preview is sky-only layer
	ChaosInMoriohStage = "rbxassetid://0", -- [320x180] NEEDS FIX: MUGEN MANU_Jo-06 preview has red tint
	NaplesTrainStationStage = "rbxassetid://0", -- [320x180] Part 5 F1 Naples Station (Verified)
	VeniceCanalsStage = "rbxassetid://0", -- [320x180] PARTIAL: MUGEN rooftops + sky only (missing canal water)
	RomeStreetsStage = "rbxassetid://0", -- [320x180] NEEDS FIX: MUGEN preview is sky gradient + birds
	RomeOutskirtsStage = "rbxassetid://0", -- [320x180] Part 5 F7 Rome Outskirts (Verified)
	RomanColosseumStage = "rbxassetid://0", -- [320x180] Part 5 D3 Roman Colosseum (Verified)
	RomeSanctumStage = "rbxassetid://0", -- [320x180] NEEDS FIX: MUGEN gio2 preview has red tint
	OgreBrawlerIdle = "rbxassetid://0", -- [96x96] Part 1 F1 Ogre Street Brawler battle idle (Row 88)
	OgreKnifemanIdle = "rbxassetid://0", -- [96x96] Part 1 F2 Ogre Street Knifeman battle idle (Row 88)
	OgreLookoutIdle = "rbxassetid://0", -- [96x96] Part 1 D1 Wave 1 Ogre Street Lookout battle idle (Row 88)
	JailThugIdle = "rbxassetid://0", -- [96x96] Part 3 F1 Stand-Awakened Jail Thug battle idle (Row 88)
	HarborDuelistIdle = "rbxassetid://0", -- [96x96] Part 3 D1 Wave 1 Harbor Sword Duelist battle idle (Row 88)
	KakyoinIdle = "rbxassetid://0", -- [96x96] Part 3 F2 Kakyoin battle idle (MUGEN v7 Row 88)
	AvdolIdle = "rbxassetid://0", -- [96x96] Part 3 D1 Wave 2 & Companion: Avdol battle idle (MUGEN v7 Row 88)
	HierophantGreenSheet = "rbxassetid://0", -- [960x96] 10f grounded sheet (idle/guard/hit/basic/skill/heavy/finisher)
	MagiciansRedSheet = "rbxassetid://0", -- [960x96] 10f grounded sheet (idle/guard/hit/basic/skill/heavy/finisher)
	SilverChariotSheet = "rbxassetid://0", -- [864x96] 9f grounded sheet (idle/guard/hit/basic/skill/heavy/finisher)
	StarPlatinumSheet = "rbxassetid://0", -- [960x96] 10f grounded sheet (idle/guard/hit/basic/skill/heavy/finisher)
	TheWorldSheet = "rbxassetid://0", -- [960x96] 10f grounded sheet (idle/guard/hit/basic/skill/heavy/finisher)
	EmperorSheet = "rbxassetid://0", -- [960x96] 10f grounded sheet (idle/guard/hit/basic/skill/heavy/finisher)
	AnubisSheet = "rbxassetid://0", -- [960x96] 10f grounded sheet (idle/guard/hit/basic/skill/heavy/finisher)
}

return table.freeze(assets)
