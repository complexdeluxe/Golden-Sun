--!strict
-- Drop-in AssetManifest for Pixel's Bizarre Adventure (Synced via Open Cloud)
-- Preserves all existing Phase 0-2 keys and includes all uploaded icons, bodies, tintable hair, Act 1 fighters, Part 3 Stand sheets, and stages.

export type AssetId = string
export type AssetKey =
	  "TutorialStage"
	| "PlayerIdle"
	| "DarioIdle"
	| "DarioWifeIdle"
	| "PocketWatchIcon"
	| "BlackSabbathStage"
	| "BlackSabbathIdle"
	| "CompanionIdle"
	| "MineralWaterIcon"
	| "CapreseSaladIcon"
	| "MedKitIcon"
	| "CoffeeGumIcon"
	| "BloodVialIcon"
	| "UVFlashIcon"
	| "SmellingSaltsIcon"
	| "SmokePelletIcon"
	| "PassioneEspressoIcon"
	| "SpikedWhetstoneIcon"
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
	TutorialStage = "rbxassetid://125950299050411", -- [STAGE 320x180] Raining Carriage Crash backdrop
	PlayerIdle = "rbxassetid://132770080817195", -- [CHARACTER_LEGACY 96x96] Default modular fighter base (Tan)
	DarioIdle = "rbxassetid://122621350377738", -- [CHARACTER 96x96] Tutorial Boss: Dario Brando battle idle (Row 88)
	DarioWifeIdle = "rbxassetid://139194949847303", -- [CHARACTER 96x96] Tutorial Wave 2: Dario's Wife battle idle (Row 88)
	PocketWatchIcon = "rbxassetid://113913891571079", -- [ICON 32x32] George's Pocket Watch
	BlackSabbathStage = "rbxassetid://102434676539926", -- [STAGE 320x180] Midnight alley backdrop (until Polpo's Courtyard)
	BlackSabbathIdle = "rbxassetid://129209179032147", -- [STAND 96x96] Black Sabbath battle idle
	CompanionIdle = "rbxassetid://73342318441872", -- [CHARACTER 96x96] Part 1 D1 Boss & Companion: Robert E. O. Speedwagon battle idle (Row 88)
	MineralWaterIcon = "rbxassetid://86790749217874", -- [ICON 32x32] CampaignStarter tonio-water
	CapreseSaladIcon = "rbxassetid://122403441625128", -- [ICON 32x32] Tonio's Caprese Salad
	MedKitIcon = "rbxassetid://72655041178911", -- [ICON 32x32] CampaignStarter med-kit
	CoffeeGumIcon = "rbxassetid://105514548417299", -- [ICON 32x32] Coffee Gum
	BloodVialIcon = "rbxassetid://136331632054039", -- [ICON 32x32] Sealed Blood Vial
	UVFlashIcon = "rbxassetid://134119286566601", -- [ICON 32x32] UV Flash Capsule
	SmellingSaltsIcon = "rbxassetid://100802671092264", -- [ICON 32x32] Smelling Salts
	SmokePelletIcon = "rbxassetid://126856140624788", -- [ICON 32x32] Smoke Pellet
	PassioneEspressoIcon = "rbxassetid://135622031033283", -- [ICON 32x32] Passione Espresso
	SpikedWhetstoneIcon = "rbxassetid://115538019988861", -- [ICON 32x32] Spiked Whetstone
	TrainingWrapsIcon = "rbxassetid://114572471184242", -- [ICON 32x32] CampaignStarter training-wraps
	BrimmedCapIcon = "rbxassetid://107823392852812", -- [ICON 32x32] CampaignStarter brimmed-cap
	PaddedHeadguardIcon = "rbxassetid://140267348463671", -- [ICON 32x32] Padded Headguard
	QuiltedJacketIcon = "rbxassetid://89774639444413", -- [ICON 32x32] Quilted Jacket
	RunnersVestIcon = "rbxassetid://133739002290390", -- [ICON 32x32] Runner's Vest
	AnubisCursedKatanaIcon = "rbxassetid://73788252021177", -- [ICON 32x32] Anubis Cursed Katana
	BalancedGripsIcon = "rbxassetid://92808907515002", -- [ICON 32x32] Balanced Grips
	ClackerVolleyIcon = "rbxassetid://137457862361448", -- [ICON 32x32] Clacker Volley
	EmperorsRevolverIcon = "rbxassetid://119178008787918", -- [ICON 32x32] Emperor's Revolver
	FocusingBeadsIcon = "rbxassetid://110157242861469", -- [ICON 32x32] Focusing Beads
	GlassCharmIcon = "rbxassetid://133464432302146", -- [ICON 32x32] Glass Charm
	HandMirrorIcon = "rbxassetid://106616597528811", -- [ICON 32x32] Hand Mirror
	IronSignetIcon = "rbxassetid://137418173329194", -- [ICON 32x32] Iron Signet
	LuckAndPluckIcon = "rbxassetid://78734460210023", -- [ICON 32x32] Luck & Pluck
	TarotFocusDeckIcon = "rbxassetid://103099880904954", -- [ICON 32x32] Tarot Focus Deck
	FieldDressingIcon = "rbxassetid://139641687248584", -- [ICON 32x32] Field Dressing
	ScoutingMapIcon = "rbxassetid://116532696250608", -- [ICON 32x32] Scouting Map
	HolyWaterIcon = "rbxassetid://107639094064349", -- [ICON 32x32] Holy Water (Cursed purification)
	ZeppelisCheckeredHatIcon = "rbxassetid://115443681398857", -- [ICON 32x32] Zeppeli's Checkered Hat
	CaesarsHeadbandIcon = "rbxassetid://112346659668642", -- [ICON 32x32] Caesar's Headband
	JotarosTornCapIcon = "rbxassetid://115585392985823", -- [ICON 32x32] Jotaro's Torn Cap
	JosukesPeacePinIcon = "rbxassetid://80063957524447", -- [ICON 32x32] Josuke's Peace Pin
	BrunosZipperBroochIcon = "rbxassetid://83819415407967", -- [ICON 32x32] Bruno's Zipper Brooch
	OpticalTargetingLensIcon = "rbxassetid://71448109040106", -- [ICON 32x32] Optical Targeting Lens
	StroheimUVVisorIcon = "rbxassetid://90764369178715", -- [ICON 32x32] Stroheim UV Visor
	HydraulicCrushArmIcon = "rbxassetid://105545592807846", -- [ICON 32x32] Hydraulic Crush Arm
	AbdominalAutocannonIcon = "rbxassetid://138094834985461", -- [ICON 32x32] Abdominal Autocannon
	OverclockCoProcessorIcon = "rbxassetid://120881033569453", -- [ICON 32x32] Overclock Co-Processor
	OverclockedAjaCoreIcon = "rbxassetid://112763929286741", -- [ICON 32x32] Overclocked Aja Core
	StandArrowIcon = "rbxassetid://78584791833804", -- [ICON 32x32] Native 32x32 inventory icon
	StandArrowKeyArt = "rbxassetid://140040184791326", -- [KEY_ART high-res] High-res Awakening modal ONLY (never grid)
	RequiemArrowIcon = "rbxassetid://115141792917412", -- [ICON 32x32] Requiem Arrow
	RokakaFruitIcon = "rbxassetid://84590666707842", -- [ICON 32x32] Rokaka Fruit
	GoldenAppleIcon = "rbxassetid://119056957703747", -- [ICON 32x32] The Golden Apple
	StoneMaskIcon = "rbxassetid://104303450492794", -- [ICON 32x32] Stone Mask
	RedStoneOfAjaIcon = "rbxassetid://101214815920673", -- [ICON 32x32] Red Stone of Aja
	DiosDiaryIcon = "rbxassetid://101711207518316", -- [ICON 32x32] DIO's Diary
	StandDiscIcon = "rbxassetid://128992424415147", -- [ICON 32x32] Stand Disc
	RacePhialIcon = "rbxassetid://94722316203355", -- [ICON 32x32] Race Phial
	ResonanceShardIcon = "rbxassetid://111559066941620", -- [ICON 32x32] Resonance Shard
	SalvageShardsIcon = "rbxassetid://78198025430743", -- [ICON 32x32] Salvage Shards
	ExpeditionTicketIcon = "rbxassetid://114679234178823", -- [ICON 32x32] Expedition Ticket
	IceDemonCrownIcon = "rbxassetid://88377497834561", -- [ICON 32x32] P1 Dio Head
	IceDemonCoatIcon = "rbxassetid://120975505883332", -- [ICON 32x32] P1 Dio Body
	UltimateLifeformCrestIcon = "rbxassetid://109069330085843", -- [ICON 32x32] P2 Kars Head
	UltimateLifeformGarbIcon = "rbxassetid://94734172560326", -- [ICON 32x32] P2 Kars Body
	CrusadersWorldHelmIcon = "rbxassetid://132611250431866", -- [ICON 32x32] P3 DIO Head
	CrusadersWorldJacketIcon = "rbxassetid://115341134394219", -- [ICON 32x32] P3 DIO Body
	QuietLifeCrestIcon = "rbxassetid://140218280405357", -- [ICON 32x32] P4 Kira Head
	QuietLifeSuitIcon = "rbxassetid://92071380310905", -- [ICON 32x32] P4 Kira Body
	CrimsonEmperorCrownIcon = "rbxassetid://81004039799627", -- [ICON 32x32] P5 Diavolo Head
	CrimsonEmperorVestIcon = "rbxassetid://137821180810338", -- [ICON 32x32] P5 Diavolo Body
	PlayerBodyFair = "rbxassetid://138369849875294", -- [BODY 96x96] SkinTone Fair
	PlayerBodyTan = "rbxassetid://132770080817195", -- [BODY 96x96] SkinTone Tan (Default)
	PlayerBodyBrown = "rbxassetid://124746187243630", -- [BODY 96x96] SkinTone Brown
	PlayerBodyDeep = "rbxassetid://121818290268430", -- [BODY 96x96] SkinTone Deep
	HairBuzz = "rbxassetid://112398514109799", -- [HAIR 96x96] Hair ID: buzz (Neutral greyscale for live ImageColor3 tinting)
	HairPompadour = "rbxassetid://86958938226517", -- [HAIR 96x96] Hair ID: pompadour (Neutral greyscale for live ImageColor3 tinting)
	HairLong = "rbxassetid://113806875118844", -- [HAIR 96x96] Hair ID: long (Neutral greyscale for live ImageColor3 tinting)
	HairSpiky = "rbxassetid://119293671263207", -- [HAIR 96x96] Hair ID: spiky (Neutral greyscale for live ImageColor3 tinting)
	HairCap = "rbxassetid://118745859821736", -- [HAIR 96x96] Hair ID: cap (Neutral greyscale for live ImageColor3 tinting)
	HairCapTrim = "rbxassetid://76244511706218", -- [HAIR_TRIM 96x96] Layer-3 untinted gold emblem & cord for live ImageColor3 tinted HairCap
	OgreStreetStage = "rbxassetid://102606650650906", -- [STAGE 320x180] Part 1 F1 Ogre Street
	NightAlleyStage = "rbxassetid://102434676539926", -- [STAGE 320x180] Part 1 F2 Night Alley
	OgreHideoutStage = "rbxassetid://94526774504905", -- [STAGE 320x180] Part 1 D1 Ogre Street Hideout
	TokyoJailStage = "rbxassetid://98531213600849", -- [STAGE 320x180] Part 3 F1 Tokyo Jail
	TokyoSchoolyardStage = "rbxassetid://138505143024990", -- [STAGE 320x180] Part 3 F2 Tokyo Schoolyard
	TigerBalmGardenStage = "rbxassetid://120892312288437", -- [STAGE 320x180] Part 3 D1 Tiger Balm Garden
	DioCastleStage = "rbxassetid://73428746662715", -- [STAGE 320x180] Part 1 Castle
	RomeCatacombsStage = "rbxassetid://0", -- [STAGE 320x180] NEEDS FIX: MUGEN Awakening preview is black layer
	SkeletonHeelStoneStage = "rbxassetid://91125722725749", -- [STAGE 320x180] Part 2 D3 Wamuu Arena (Verified)
	CalcuttaStage = "rbxassetid://0", -- [STAGE 320x180] NEEDS FIX: MUGEN Calcutta preview has red tint
	DesertedTownStage = "rbxassetid://0", -- [STAGE 320x180] NEEDS FIX: MUGEN preview is sky-gradient only
	CairoRoadStage = "rbxassetid://0", -- [STAGE 320x180] NEEDS FIX: MUGEN magenta cutout mask
	CairoAlleyStage = "rbxassetid://0", -- [STAGE 320x180] NEEDS FIX: MUGEN preview is sky-only layer
	DioMansionGatesStage = "rbxassetid://72583588366999", -- [STAGE 320x180] Part 3 F7 Mansion Gates (Verified)
	DioMansionHallStage = "rbxassetid://120360623539105", -- [STAGE 320x180] Part 3 D3 Vanilla Ice (Verified)
	CairoBridgeStage = "rbxassetid://130232004702893", -- [STAGE 320x180] Part 3 Castle DIO (Verified)
	MoriohTownStage = "rbxassetid://113168031827774", -- [STAGE 320x180] Part 4 F1 Morioh Station (Verified)
	NijimuraHouseStage = "rbxassetid://101781386959912", -- [STAGE 320x180] Part 4 F2 Nijimura House (Verified)
	BoyoyoingCapeStage = "rbxassetid://0", -- [STAGE 320x180] NEEDS FIX: MUGEN preview is sky-only layer
	TailorDistrictStage = "rbxassetid://0", -- [STAGE 320x180] NEEDS FIX: MUGEN magenta cutout mask
	KiraEstateStage = "rbxassetid://0", -- [STAGE 320x180] NEEDS FIX: MUGEN preview is sky-only layer
	ChaosInMoriohStage = "rbxassetid://0", -- [STAGE 320x180] NEEDS FIX: MUGEN MANU_Jo-06 preview has red tint
	NaplesTrainStationStage = "rbxassetid://124750804424788", -- [STAGE 320x180] Part 5 F1 Naples Station (Verified)
	VeniceCanalsStage = "rbxassetid://0", -- [STAGE 320x180] PARTIAL: MUGEN rooftops + sky only (missing canal water)
	RomeStreetsStage = "rbxassetid://0", -- [STAGE 320x180] NEEDS FIX: MUGEN preview is sky gradient + birds
	RomeOutskirtsStage = "rbxassetid://118285655449966", -- [STAGE 320x180] Part 5 F7 Rome Outskirts (Verified)
	RomanColosseumStage = "rbxassetid://95090540884864", -- [STAGE 320x180] Part 5 D3 Roman Colosseum (Verified)
	RomeSanctumStage = "rbxassetid://0", -- [STAGE 320x180] NEEDS FIX: MUGEN gio2 preview has red tint
	OgreBrawlerIdle = "rbxassetid://122405969088067", -- [CHARACTER 96x96] Part 1 F1 Ogre Street Brawler battle idle (Row 88)
	OgreKnifemanIdle = "rbxassetid://129098934960515", -- [CHARACTER 96x96] Part 1 F2 Ogre Street Knifeman battle idle (Row 88)
	OgreLookoutIdle = "rbxassetid://113869937564800", -- [CHARACTER 96x96] Part 1 D1 Wave 1 Ogre Street Lookout battle idle (Row 88)
	JailThugIdle = "rbxassetid://115315353830216", -- [CHARACTER 96x96] Part 3 F1 Stand-Awakened Jail Thug battle idle (Row 88)
	HarborDuelistIdle = "rbxassetid://96338018277308", -- [CHARACTER 96x96] Part 3 D1 Wave 1 Harbor Sword Duelist battle idle (Row 88)
	KakyoinIdle = "rbxassetid://111276683171946", -- [CHARACTER 96x96] Part 3 F2 Kakyoin battle idle (MUGEN v7 Row 88)
	AvdolIdle = "rbxassetid://118601613443071", -- [CHARACTER 96x96] Part 3 D1 Wave 2 & Companion: Avdol battle idle (MUGEN v7 Row 88)
	HierophantGreenSheet = "rbxassetid://95098649469348", -- [STAND_SHEET 960x96] Grounded 10-frame 96x96 horizontal sheet (idle/guard/hit/basic/skill/heavy/finisher)
	MagiciansRedSheet = "rbxassetid://106283174462346", -- [STAND_SHEET 960x96] Grounded 10-frame 96x96 horizontal sheet (idle/guard/hit/basic/skill/heavy/finisher)
	SilverChariotSheet = "rbxassetid://123698784998359", -- [STAND_SHEET 864x96] Grounded 9-frame 96x96 horizontal sheet (idle/guard/hit/basic/skill/heavy/finisher)
	StarPlatinumSheet = "rbxassetid://126116770985426", -- [STAND_SHEET 960x96] Grounded 10-frame 96x96 horizontal sheet (idle/guard/hit/basic/skill/heavy/finisher)
	TheWorldSheet = "rbxassetid://73191403027477", -- [STAND_SHEET 960x96] Grounded 10-frame 96x96 horizontal sheet (idle/guard/hit/basic/skill/heavy/finisher)
	EmperorSheet = "rbxassetid://104152246077452", -- [STAND_SHEET 960x96] Grounded 10-frame 96x96 horizontal sheet (idle/guard/hit/basic/skill/heavy/finisher)
	AnubisSheet = "rbxassetid://138418549971432", -- [STAND_SHEET 960x96] Grounded 10-frame 96x96 horizontal sheet (idle/guard/hit/basic/skill/heavy/finisher)
}

return table.freeze(assets)
