# Claude Phase 3 Handoff

Phase 2 is on main at `b3758d3`, including the compact HUD, ring QTE, and server-owned turn advancement. Review the Phase 3 contracts in [PR #13](https://github.com/complexdeluxe/Golden-Sun/pull/13). The [wire checklist](PHASE_ARCHIVE_0_3.md#phase-3-contract-review) describes the shared fields and requests.

## First playable slice

Create an appearance → clear the Raining Carriage Crash tutorial → choose an Origin → enter the public Hub → set out on the Act 1 map → clear F1, F2, and D1 → recruit the first companion → save and rejoin.

Claude owns the Creator, Hub, Act Map, and Inventory/Loadout screens. Codex owns the shared contracts, persistence, and progression. Antigravity/Gemini prepares modular hair, slice stages, and the inventory icon manifest. Use the existing 320 × 180 pixel viewport and native 32 × 32 inventory icons.

## Screen and contract checklist

| Screen | Fields and behavior |
| --- | --- |
| Creator | Use the four skin ramps, catalog hairstyles, selected IDs, option legality, and optional sprite keys in `CharacterAppearanceTypes`. A legacy player with a saved Origin and no appearance enters Creator once, then resumes from their saved progress. |
| Hub | Use `CampaignSnapshot.character.level` and `.yen` for the character panel and currency. The Hub view supplies shop offers and Set Out legality. |
| Inventory and Loadout | Gear and belt slots hold `entryId` references to inventory. A belt-eligible stack includes a `beltItemId` from `CombatTypes.BeltItemId`. Use `item.iconKey` for the loadout art and join `beltItemId` to `PartyBelt.items[].itemId` in combat. |
| Act Map | Lay out F1, F2, and D1 by node ID, and use the server prerequisite links and locks. Show the advertised first-clear or replay options and their reward preview. |
| Results and recruitment | Use `ActResults.result` for the rewards earned in the encounter and `CampaignSnapshot.character` for the resulting totals. Offered and recruited companions supply a label, short description, and optional sprite key. Use the standard placeholder when the key or its image is unavailable. |

`CombatTypes.Phase2Limits` supplies the loadout tooltip values. The party starts a fight with three shared charges, can use up to two direct heals, and can use one Med-Kit. `CombatTypes.PartyBelt` provides the live counters, stocks, and item legality for the combat HUD.

## Answers to the PR review

| Question | Phase 3 decision |
| --- | --- |
| Where do map node positions live? | Claude sets positions in the client keyed by `NodeId`. Prerequisites and unlock states come from the server. |
| What does the node preview show? | Show the node and play-option labels, stage tag, tier, level reward, and optional discovered variant label. Enemy lineup and recommended level previews are deferred to the encounter contract review. |
| What Hub stations appear? | Show Shop/restock, Inventory/Loadout, Set Out, and recruitment when offered. Blacksmith, D’Arby’s Parlor, and the other later stations appear in their own phases. |
| What can the Creator edit? | Commit skin tone and hairstyle once for the current character. Race/Clan, hair color, character name, the Starter Reroll Token, and Hub appearance editing are outside the Phase 3 slice. |
| Where can players change the loadout? | Players change gear and belt slots from the Hub. The Act Map includes a Hub button that submits `Navigate` with destination `"Hub"`. |
| How does tutorial routing work? | `Tutorial` and `OriginSelect` use the existing `TutorialRemotes` flow. After the tutorial clear the existing Origin picker can continue. Fetch `GetCampaignSnapshot({})` after `ChooseOrigin` succeeds to enter the Hub. If the session resumes between clear and selection, render the Origin picker from the `OriginSelect` scene. |

The [Act encounter combat handoff](CLAUDE_PHASE_3_ACT_COMBAT_HANDOFF.md) covers the separate review for connecting the map to the existing combat HUD. The screen flows use the frozen Campaign contracts.

## Exit checks

1. A fresh profile creates an appearance, clears the tutorial, commits an Origin, and enters the Hub.
2. A legacy Phase 1 profile keeps its tutorial completion and saved Origin through migration and can commit a missing appearance.
3. The Hub opens inventory and belt restock. The Act Map opens F1, F2, and D1 in order and shows the correct reward for first clears and replays.
4. A D1 clear offers first-companion recruitment. Rejoining preserves appearance, Origin, map clears, inventory, and recruitment.
5. Run the Phase 2 combat and tutorial regressions against the integrated build.
