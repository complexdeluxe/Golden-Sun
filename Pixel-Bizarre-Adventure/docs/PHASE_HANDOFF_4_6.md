# Phase 4–6 handoffs and verification

### Phase 4 economy review

Reviewed local Antigravity branch `antigravity/phase4-economy-core` at `7cb2c8b`. Its existing Lune suite passed. Strict analysis failed, and deterministic probes reproduced affix-budget overflow, zero-line T1 Legendary generation, and inconsistent FullBorg strain. See the [original review](PHASE4_ECONOMY_REVIEW.md) and the follow-up below.

### Stage 4.1 contract review checklist

The contract draft is on `codex/pba-phase4-contracts` from `main` at `9182c73`. The reviewed calculator and fixes are on `codex/pba-phase4-economy-review-fixes` at `08ef2ae`, rebased onto the same main commit. That branch resolves the findings above, including the T3 unlock and the minimum-cost check for percentage affixes. The shared contract draft uses its own wire and save shapes and has no calculator dependency.

- [ ] **UUID gear and migration.** Confirm a UUID is also the inventory entry ID for a gear copy. Review the mapping from starter gear and calculator point totals to fixed stat lines, the empty package for plain gear, and persistence of tier, temper level, pity and curse state. Review runtime validation of the numeric bounds and UUIDs.
- [ ] **Blacksmith.** Confirm `CreateOffer` persists payment and replacement lines together before reveal. A reconnect snapshot must return the same offer ID and package. `ResolveOffer` matches both the UUID and offer ID and accepts the package or keeps the old one. Review request ID replay and conflicting requests, including the trade lock while an offer is pending.
- [ ] **Tempering and purification.** Confirm failed tempering returns a committed receipt with the unchanged level and new pity count. Review the +10 cap, currency settlement, removal of both curse effects, and the unique Measured Breath loadout rule.
- [ ] **Item details and dismantling.** Confirm display data and effective base stats are available with the original item record. Review the displayed shard quote and legality, and commit item removal and the shard grant together.
- [ ] **Cyberware Clinic.** Verify the five site IDs, install quotes and tolerance costs, one implant per site, racial tolerance and strain preview, and the distinction between installed routines and equipped routines. Review installation, removal, and replacement of the equipped routine list.
- [ ] **D'Arby's Hub Parlor.** Review normal and pity odds by chip tier, one and ten spin requests, the order of results and pity updates in a batch, and duplicate cosmetic shard refunds. Confirm prices, outcomes and request receipts are settled before reveal.
- [ ] **Remote lifecycle.** Confirm `Phase4Remotes` snapshot and action shapes, stale revision recovery, retry handling, and station availability before implementing server bindings.

**Verification** — Rojo build, strict analysis of shared modules and tests, and `tests/phase4_contracts.luau` passed on the contracts branch. Strict analysis of the economy modules and `tests/phase4_economy.luau` passed on the rebased economy branch.

### Stage 4.2 complete and Phase 4 client handoff for Claude

`TutorialBootstrap` binds `ReplicatedStorage.Shared.Phase4Remotes` through the same SaveService store as Campaign. The two services renew and release their own session leases. Both use the same Yen balance. An action based on a superseded wallet or revision gets a fresh snapshot with `StaleRevision` so the client can show the new price or balance and let the player retry.

- **Hub entry and refresh.** Invoke `GetPhase4Snapshot({})` on opening a station. Render the server's item, install and spin previews. For `SubmitPhase4Action`, send the latest Phase 4 `sessionId` and `expectedRevision`, a unique `requestId`, and the action selection. After an uncertain response, retry the same action with the same request ID. After a definitive stale response, refresh from its snapshot before a new attempt. Refresh the Campaign view when leaving a station so the Hub shows the current Yen.
- **Blacksmith.** Use the gear UUID and render the persisted replacement offer when the snapshot contains one. Send `ResolveOffer` with its offer ID and the player's choice. Show the committed temper level and pity count even on a failed temper, and use the returned purification and dismantle receipts.
- **Clinic.** Show the Act 2 lock, site offers and the tolerance/strain panel. Send the selected site and tier for installation, the site for removal, or the full selection for `SetEquippedRoutines`. Render the updated list after a replacement or removal.
- **D'Arby's Parlor.** Show the price and odds for the selected chip and the current pity counter. Offer one or ten spins. Present batch results in receipt order and show duplicate refunds. The binding uses stable starter prize IDs and the Act reward tables for crafting bundles. Cosmetic presentation and the player-facing display of Phase 4 prize inventory belong to client/content integration.

**Verification** — Rojo build, strict Luau analysis of shared code and tests, and all nine Lune suites passed. The shared-store regression interleaves Campaign purchases and loadout writes with Phase 4 spending, verifies stale recovery against a cached Campaign read, then renews and closes the two leases independently.

## Stage 5A succession contracts

`SuccessionTypes` defines the age and Castle recovery views, retirement and terminal Echo quotes, all 11 bloodline nodes across three branches, the heirloom catalog and loadout, and per-kit mastery. The catalog supplies labels, descriptions, and optional asset keys. Carrying two heirlooms still allows one active attunement, changed at the Safe Hub.

Alternate targeting unlocks at two marks and uses `SetMasteryTargetMode`. The independent utility variant unlocks at five marks and uses `SetMasteryVariant`. The mastery title unlocks at eight marks.

`RemoteContract.Lineage` declares `GetLineageSnapshot` and `SubmitLineageAction`. Actions carry a session ID, expected revision, and request ID. Use the same request ID and action after an uncertain reply.

**Verification** — Rojo build, strict Luau analysis of shared modules and tests, and `tests/phase5_contracts.luau` passed.

### Stage 5B session and Stage 5C binding complete

`SuccessionSession` implements the six lineage actions and the trusted progression and settlement hooks. `SuccessionService` exposes both lineage remotes from `TutorialBootstrap` on the shared SaveService store. The lineage lease renews and closes independently of the Campaign and Phase 4 leases. Safe Hub checks use the live Campaign scene, and lineage mutations serialize with Campaign navigation and combat requests.

### Phase 5 client handoff for Claude

- Open the Campaign session first. At the Safe Hub, call `ReplicatedStorage.Shared.LineageRemotes.GetLineageSnapshot({})` to open the lineage panel. Render age, recovery count, Echo quotes, and the three branches from the current snapshot. Gate voluntary retirement and heirloom edits using the supplied eligibility.
- Submit `{ sessionId, expectedRevision, requestId, action }` through `SubmitLineageAction`. When a reply is uncertain, refresh or reconnect as needed and retry the same action with the same request ID. On a definitive stale response, use the supplied snapshot before making a new request.
- For Pass the Torch, confirm against the displayed `lifeId` and render the committed payout from the receipt. Replace lineage UI state with the returned heir snapshot. Campaign progression and character reset integration are separate from this remote binding.
- Use the heirloom catalog for presentation. Carry only the advertised number and show at most one attuned heirloom. Keep mastery targeting at two marks separate from the utility variant at five marks and the title at eight marks.
- The ledger exposes the final-attempt flag, terminal payout, and settled state. Castle entry confirmation and the campaign calls that record wipes, aging, clears, endgame challenges, mastery, and heirloom unlocks remain progression integration work. The two lineage remotes accept player actions only.

**Verification** — Rojo build, strict Luau analysis of shared code and tests, server compilation, and all 11 Lune suites passed. The succession regression uses the real Campaign Safe Hub query and verifies that heirloom editing is blocked on the Act Map and available after returning to the Hub.

## Stage 5D-1 launch catalogs

- **Campaign.** `CampaignPartsData` records Option 1. Hamon follows Parts 1, 2, 3, 4, 5. Stand follows Parts 3, 1, 2, 4, 5, with Parts 1 and 2 marked as Bloodline Flashbacks. Act tier stays independent of Story Part. The five Parts contain 55 story nodes and 30 Dungeon approach options. Each Castle has two phases, and both live Act 1 openers retain their names, stage keys, tags, and default waves. Some stage keys still point to placeholder art.
- **Boss sets.** The five sets specify Head and Body pieces, the two-clear drop guarantee, and audited full-set triggers. The authored Crimson Emperor Crit bonuses at T1 and T4 cost 1.5 and 4.5 points under the Vault exchange table. The catalog retains those authored quotes separately and caps `onePieceAmountByAct` to the half-slot allowance.
- **Builds.** `BuildCatalogData` records the 9×5 launch compatibility matrix and 45 Stand records from the Vault JSON, including all Arrow Core and Disc entries. The isolated grade table keeps ∞ at the A+ numeric ceiling with at most one authored behavior per axis. Hub evolution entries require explicit confirmation. The Cyborg offer uses the lower edge of the documented 30–35 tolerance band with two installed sites and the Act 2 Clinic unlock. Evolution offers with unspecified unlock conditions require authored progression data.

**Verification** — Rojo build, strict Luau analysis of shared code and tests, and all 12 Lune suites passed. The catalog integrity test checks route and node counts, the live opener parity, asset references, Boss Set budgets and trigger bounds, acquisition coverage, Stand grade ceilings, and opt-in evolution flags.

## Stage 5D-2 headless balance parity

- All five archetypes cleared the deterministic Castle fixtures in Acts 1–5 on both origin routes. The median was seven turns in each case. The largest individual deviation was 14.29% against a 15% limit.
- Fifty overloaded loadout cases used T5 +10 gear with three rolled lines per item, the route Castle's Boss Set, and the A+ Stand Grade ceiling for Stand actions. They held the 35% source damage, 75% pre-penetration mitigation, 50% effective Dodge, and 25 Resolve per turn caps. The suite also exercises the existing Phase 2 sandbox's Resolve grant through a landed Basic Strike.
- The first-life Human Boxer cleared the Act 5 Castle at age 59 in seven turns with 172 HP left after guarding both telegraphs. Veteran Composure and the isolated Ageless comparison also cleared in seven turns, with 184 and 197 HP left respectively.

The suite uses fixed headless encounter inputs with shared combat math and catalog-defined Castle phases and move multipliers. Live progression and Studio playtesting remain separate work.

**Verification** — Rojo build, strict Luau analysis of shared code and tests, and all 13 Lune suites passed.

## Stage 6.1A activity contracts

- **Post-Act Auto-Battle.** The view lists manually cleared Acts and their per-tick reward previews. Active runs expose server UTC start and paid-through timestamps, pending ticks, and the latest claim for rejoin. The contract specifies 300-second server auto-claims and limits rewards to Yen, Salvage Shards, crafting materials, and standard gear.
- **Ticket Expeditions.** The view exposes one four-hour mission slot, a server UTC completion time, claim eligibility, and a crafting bundle capped at 25% of same-Act clear value. The ticket cap is two, or three with Quartermaster Dispatch. Expeditions add no age. Neither activity grants XP, Mastery Marks, or Echoes.
- **Activity remotes.** `ActivityRemotes` declares `GetActivitySnapshot` and `SubmitActivityAction`. All five actions include a request ID and expected revision. Auto-Battle claims and stops target a run ID, and an Expedition claim targets a single mission ID.

**Verification** — Rojo build, strict Luau analysis of shared code and tests, and `tests/phase6_contracts.luau` passed.

## Stage 6.1B session and Stage 6.1C server binding

`ActivitySession` settles Auto-Battle ticks and four-hour Expeditions through the shared SaveService store. The independent activity lease preserves Campaign, Phase 4, and Lineage sessions. Auto-Battle payouts advance the persisted paid-through timestamp in the same write as the shared balances. Expedition claims mark the mission paid in the same write as its bundle.

`ActivityService` starts in `TutorialBootstrap` and opens Activity sessions on join so active runs resume before the panel opens. It renews leases on a 30-second heartbeat, settles active runs when their five-minute UTC boundary is due, and releases activity leases on player removal and shutdown. Starting Auto-Battle shares Campaign's Safe Hub action lock.

**Verification** — Rojo build, strict Luau analysis of shared code and tests, server bytecode compilation, and all 15 Lune suites passed. A mocked server check also exercised the scheduler's renewal, due-time settlement, lost Start reply recovery, removal, and rejoin paths.

### Phase 6 client handoff for Claude

- Open the Campaign session for Safe Hub context, then call `ReplicatedStorage.Shared.ActivityRemotes.GetActivitySnapshot({})`. Use the listed manually cleared Acts and per-action legality to render the Auto-Battle panel and Expedition Board.
- Use `serverTimeUtc` to anchor countdowns. The Auto-Battle boundary comes from `lastClaimedAtUtc + tickSeconds`. Refresh the snapshot at the boundary and on panel open or rejoin. Use `lastClaim` for the claim feed and the paid-through timestamp to avoid repeating an entry. Automatic settlement runs on the server.
- Render the Expedition ticket cap, active mission, `completesAtUtc`, reward preview, and `claimable` state from the snapshot. Countdown completion can trigger a refresh. Dispatch and claim each require an explicit player action.
- Send `{ sessionId, expectedRevision, requestId, action }` to `SubmitActivityAction`. Target the current `runId` for Auto-Battle claim or stop and the current `missionId` for Expedition claim. After an uncertain reply, reconnect if needed and retry the same action with the same request ID. Refresh on a definitive stale revision before making a new action.
- Use the Phase 6 client pass for the activity panels, claim feed, VFX and SFX polish, and PC and mobile layout. The current campaign does not yet emit full-Act clears or Expedition Ticket awards. Those progression events are needed for end-to-end unlock and ticket acquisition playtests.
