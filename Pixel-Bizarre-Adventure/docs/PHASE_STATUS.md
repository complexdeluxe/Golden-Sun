# Phase status

**Active phase** — Phase 3 merged and isolated persistence verified. Stage 4.1 shared contracts are ready for review.

**Base** — Phase 2 merged via PR #10 at `b3758d3`, including PR #12’s server-owned turn advancement.

| Ticket | Scope | Status |
| --- | --- | --- |
| 2A | Sandbox data shapes, remote names, asset keys, and HUD review | Merged in PR #9 |
| 2B | Audited combat math and server sandbox | Merged and verified with Combat HUD v2 |
| 2B client | Compact HUD and Manual ring QTE | Merged in PR #10 |
| 3.1 | Creator, Hub, Act 1 map, inventory, and campaign routes | Merged in PR #13 |
| 3.3 | Saved appearance, Hub economy, loadout, and campaign remotes | Merged via PR #18 |
| 3.4 | Creator, Hub, bag, map, and results screens | Merged via PR #14 |
| Act combat | F1 battle, Results and replay on the campaign server | Merged via PR #18 (includes #17) |
| Act 1 | F2, two-wave D1 and companion recruitment | Merged via PR #18 |

## Campaign server handoff

Test the server with the client from [PR #14](https://github.com/complexdeluxe/Golden-Sun/pull/14). The real campaign supports Creator, tutorial and Origin routing, the Hub, the starter Yen shop, gear and belt slots, and navigation to the Act Map. It stores campaign fields alongside the existing tutorial profile and commits mutations under an expiring session lease. Studio uses the in-memory store by default. Controlled cross-restart validation uses the isolated Studio DataStore.

The starter shop, opponent stats and clear rewards are playtest data. Both Origins can clear F1, F2 and D1 in order and return to Results. Existing F1 saves retain their clear and any unacknowledged Results.

The server exposes the Phase 3 art keys through the existing Creator, inventory and map fields. The Part 1 route uses Ogre Street, Night Alley and the hideout. The Stand route draft uses Tokyo Jail, Tokyo Schoolyard and Tiger Balm Garden. The manifest uses asset ID 0 until the images receive Roblox IDs. The client can keep its current fallback art and wire layered rendering in its own follow-up.

### FighterSprite handoff

For the player fighter in the tutorial and Act battle, read `CampaignSnapshot.character.appearance.hairColorHex` and pass `CampaignSnapshot.character.appearanceSprites` to the renderer. The sprite payload supplies `bodySpriteKey`, `overlaySpriteKey`, and `accentSpriteKey` on every scene with a saved look. Render the body first and tint the neutral hair overlay with the saved color. When the accent key is present, stack it last and render it untinted. The cap's accent key is `HairCapTrim`. All three layers share the same facing and pixelated sampling. Use the existing fallbacks for missing layers or asset ID 0.

The live Creator catalog exposes the eight hair swatches as `hairColors` entries with `id`, `label`, and `hex`. `CommitAppearance` accepts an optional palette color. Older saves and clients default to Jet Black (`#242633`). The existing Creator can keep submitting skin and hair IDs while the base Act 1 loop is built.

### Act 1 client integration

Use the [Act combat handoff](CLAUDE_PHASE_3_ACT_COMBAT_HANDOFF.md) to replace the real server's Encounter placeholder with the existing compact HUD. Start with the battle ID on `ActEncounter` and adapt the HUD to render the Act snapshot's actors, intents and stage. Send Primary, Secondary, QTE and mode inputs to `ActBattleRemotes`. The server advances turns and grades the rings. Accept the campaign snapshot in a battle reply or event and open the existing Results screen when it reaches `ActResults`. Refresh the campaign for **SAVING RESULTS...** and **RETRY**. Use the existing Creator and placeholder sprites to playtest.

F2 is the Ogre Street Knifeman for Hamon and Kakyoin for Stand. Guard or interrupt the delayed attack to avoid Bleed or Stun. D1 has one approach wave and one finale, with one active foe per wave. The Hamon route fights the Ogre Street Lookout and Speedwagon. The Stand route fights the Harbor Sword Duelist and Avdol. Each wave transition keeps the battle ID, continues revision numbering, and carries party HP, Resolve and belt stock forward. The next turn regenerates Stamina as usual.

The first D1 clear offers Speedwagon or Avdol through the existing Results and Hub screens. The offer persists until accepted. Recruited companions join Flag replays and face the player in their D1 rematch. First clears grant one level and 12, 18 or 30 Yen. Replays grant zero levels and half the Yen. Defeat and Flag retreats grant zero clear rewards. Equipped belt stock is spent when the server commits Results. Interrupted encounters return to the map, and saved Results reopen until the player returns to the map or Hub.

## Phase 3 contract review

The first slice follows Creator → existing tutorial → existing Origin selection → Hub → Act 1 F1 → F2 → D1 → first companion recruitment → rejoin. Origin remains a post-tutorial commit using `ChooseOrigin`. The Creator submits appearance IDs and renders a catalog with the four skin tones and available hairstyles.

The [Phase 3 handoff](CLAUDE_PHASE_3_HANDOFF.md) lists the exact screen scope and answers the six review questions.

| Contract | What Claude can read and submit |
| --- | --- |
| `CharacterAppearanceTypes` | Default appearance, four skin-tone swatches, hair labels and legality, optional sprite keys, and stable selected skin and hair IDs. |
| `HubTypes` | Tagged scene with the view it needs, saved appearance and Origin, character level and Yen on every scene, shop offers, and Set Out availability. |
| `InventoryTypes` | Gear and stack entries, base stat lines, quantities, icon keys, four gear slots, and numbered belt loadout slots. Slots reference `entryId`. A belt-eligible stack supplies a `CombatTypes.BeltItemId`. Gear rarity and tier are display fields. |
| `MapTypes` | Ordered F1/F2/D1 IDs, prerequisite links, stage tags, play options, active encounter identity, finalized rewards, and companion descriptions and sprite keys. |

### Campaign protocol

Stage 3.1 defines the shapes. Stage 3.3 binds `ReplicatedStorage.Shared.CampaignRemotes` and implements persistence and progression. The tutorial and sandbox continue using their existing folders. The v1 tutorial save schema stays at version 1 during contract review.

1. Send `GetCampaignSnapshot({})` when the campaign client starts. Render the returned `scene.kind` and its payload. A legacy profile that lacks appearance enters Creator once, then continues from its saved tutorial and Origin state. After completing the tutorial or saving Origin, refresh the campaign snapshot using the existing tutorial flow.
2. Submit mutations through `SubmitCampaignAction` with the current `sessionId` and `expectedRevision`. The caller selects IDs and quantities. The server validates scene, eligibility, available balance, stock, and slot compatibility and returns the refreshed snapshot or an error with optional resync state. Prices and rewards come from the server. Omit `entryId` to clear a gear or belt slot.
3. In the Hub, shop offers include a server-limited purchase quantity and Yen price. Buying a belt supply adds to that inventory stack. Equipped belt slots use `entryId` for stock and icon lookup and `beltItemId` to match the combat belt row. Show the three shared charges, two direct heals, and one Med-Kit per fight using `CombatTypes.Phase2Limits`. In combat, `PartyBelt` supplies the live remaining charges, heals, and Med-Kit usage.
4. From Act Map, send the node ID and one of its advertised `playOptionId` values. The snapshot reports node locks, stage tag, mode, tier, and level reward. First clears can advance progression. Replays award zero levels and display the tier and discovered variant the player selected. Act difficulty and story Part are independent snapshot fields.
5. `ActEncounter` carries an encounter ID and battle ID for the combat handoff. `ActResults` carries the server-finalized outcome and rewards. Review the general Act battle snapshot and actions separately before adapting the combat HUD to the map. The current Black Sabbath sandbox remains available for combat verification.
6. Recruitment is a server-issued offer linked to the first D1 clear and remains visible from the result or Hub until recruited. Consume it with `RecruitCompanion`. Both states expose the label, description, and optional sprite key. Apply `CampaignSnapshotChanged` events for server transitions such as battle results. Across a reconnect, take the new session from the startup response and ignore old-session events. Within one session render the newest revision.

### Review and exit gates

- Claude reviews resume routing, source for appearance assets, shop and inventory actions, node and replay previews, the battle handoff, and companion offer fields. Freeze the shapes before client and server implementation branches start.
- Stage 3.1 verification is Rojo build, strict Luau analysis on the shared modules and tests, and the existing four test suites plus `lune run tests/phase3_contracts.luau`.
- The Phase 3 slice is accepted after a fresh profile finishes D1 and recruits, a returning Phase 1 profile keeps its selected Origin, and a server restart preserves appearance, clears, inventory, and recruitment.

## Section 2 HUD review

| Surface | What the client can use |
| --- | --- |
| Action economy | Each actor has Primary, Secondary and Bonus Primary availability. Each Primary option belongs to `activeActorId` and gives its slot, Stamina cost, scaling tag, input mode, legality, and per-target preview. Skip Turn uses `endTurnLegality`. One shared bonus slot per actor per round gives no extra regeneration, Secondary, cooldown tick, or companion turn. |
| QTE | `qtePrompt` identifies the active challenge, available inputs, and server-graded per-check results in display order. `HighRiskHeavy` exposes the 1.70× base and the four timing bands. `Dodged` and `FailedQTE_0of3` are separate log events. The preview gives the effective dodge and interrupt odds conditional on required execution. |
| Resolve and On Fire | Actor records expose current Resolve, gains this turn, Fire duration and Finisher readiness. Resolve caps at 100, gains cap at 25 per turn, and the low-HP +20 trigger is once per fight. Fire lasts two turns, pauses Resolve gains, and grants +15% damage, +15 percentage points Crit chance and +10% Speed until expiry or Finisher. |
| Party belt | Three shared charges, two direct heals, one Med-Kit. Show stock, legal targets, live capped gains and relevant intent IDs. UV Flash cancels an eligible windup and leaves Exposure reserved for offensive interrupts. |
| Companion | Resolve the companion ID against the actor list for HP, Stamina and Guard. Show available tactic, assist readiness and a redirect preview with current target, legal recipients and Guard status. |
| Status and intent | Show removable marks, Stun and Exposure. Exposure lists its target and the next eligible follow-up actor when known. Stage tag and sandbox step indicate Lighter Strike, Shadow Grab windup, landing, or Fade. Show the Fade (+20 Dodge) badge from Black Sabbath’s `Fade` status and its remaining duration. |

## Server turn advancement

The client can use one available Secondary before committing the regular Primary. The server spends the Primary and closes the Secondary slot when it accepts the move. It advances the queue once the Primary resolves, including on an evasion, final QTE input, or last timed-out check. If an effect has granted a Bonus Primary, the server keeps that actor active through the bonus. Primary options always belong to `activeActorId`.

A fighter with no available Primary can use **Skip Turn**, including after Stun denies their regular Primary. Send `kind = "EndTurn"` with the active actor ID and latest battle ID and revision through `SubmitSandboxSecondary`. Skip Turn consumes no item or belt charge. It forfeits any unused Secondary and advances the queue. During a QTE, other actions remain locked until the challenge resolves.

Format the UV Flash tooltip in the client as “Guaranteed Shadow Cancel Only. Does not apply Exposure.” Use the server preview to decide whether the current intent is eligible.

## Sandbox wire protocol

Stage 2B creates `ReplicatedStorage.Shared.BlackSabbathRemotes`. The existing tutorial remote folder and Build 1 payloads continue to serve the tutorial.

1. Invoke `StartSandbox` with fixture level 10 or 50, stage tag and QTE preference. A successful call returns the full battle snapshot.
2. Send the battle ID and the snapshot revision for Primary, Secondary and QTE preference changes. Include the acting fighter and any required target in the request. The server validates this against the player’s battle and current action slots.
3. A committed High-Risk Heavy spends its Stamina and slot once, then returns an active challenge. The client submits one input per check using battle ID, challenge ID and check index. The server validates ordering, bounds, cue answers and receipt time. For manual window display, compare the supplied timestamps with `workspace:GetServerTimeNow()`. During a challenge, `checkResults` mirrors `checks` by position and gives `Pending`, `Hit`, or `Miss`, including timed-out checks. Untimed checks have no timing cutoff. The client sends input only. The server grades the move and calculates damage, dodge, Resolve and proc results.
4. An Auto-Good preference uses untimed cues for this tagged attack. Ordinary Auto-Good remains at 1.00×. Only a landed Manual Perfect qualifies for the manual assist. Landed 3/3 grants +15 attack Resolve and eligibility for its hit rider. Dodged 3/3 grants zero attack Resolve. A partial or failed check incurs the single −1 timing adjustment. Exposure starts after the offensive interrupt resolves and lasts through the party’s next Primary.
5. Replace the displayed state with the newest snapshot from a response, the server event `SandboxSnapshotChanged`, or `GetSandboxSnapshot` when reconnecting. The final QTE response or expiry event includes the resulting active fighter. Ignore an older revision within the same battle. On a new battle ID, initialize the UI from that battle’s snapshot.

Asset manifest entries set to `rbxassetid://0` use local fallback visuals. The sandbox adds stage, Black Sabbath, companion and belt keys for Claude to wire in the HUD.

## Verification

From `Pixel-Bizarre-Adventure/`, run `rojo build default.project.json --output "$env:TEMP/PBA-Phase2.rbxlx"`, `lune run tests/smoke.luau`, `lune run tests/tutorial.luau`, `lune run tests/phase2_contracts.luau`, and `lune run tests/phase2_sandbox.luau`. Run strict Luau analysis on shared modules and tests.

Verified with Rojo 7.7.1, Lune 0.11.1, and luau-analyze 0.748. The combined Rojo build, original smoke test, seven tutorial scenarios, Phase 2 contract smoke, sandbox parity suite, and strict analysis of the shared sandbox code and tests passed. The server bootstrap and all 11 client sources also compiled.

A local Studio build with PR #10 booted into the real Night sandbox. The HUD showed 82/82 player HP with its mock badge hidden and rendered the result of three expired manual checks. Separate client calls verified the server's timeout events, Coffee Gum, End Turn, UV cancel without Exposure, and a landed 3/3 Untimed Cue for +15 Resolve. The Studio output reported asset-load warnings for placeholder content.

## Ring QTE follow-up for the HUD

The isolated `codex/pba-ring-qte` branch serves the Manual ring contract. Pair it with the updated ring HUD for Studio playtesting. The verified Studio run above covers the earlier directional Manual HUD.

- Use `workspace:GetServerTimeNow()` to render the active ring. Start the contraction at `approachStartsAtServerTime` and align the ring and target at `overlapAtServerTime`. Highlight the target from `opensAtServerTime` until `closesAtServerTime`. The current check becomes visible at its approach timestamp. Between rings, show prior check results.
- Send `input = "Confirm"` with the current battle ID, challenge ID and check index for one mouse click, touch, or fresh Space press. Gate the gesture while the ring is active and consume it before any HUD button handles it. Use the server's `checkResults` for feedback.
- A press between the approach start and the hit window scores a miss. The server accepts the window from opening inclusive to closing exclusive. At closing it advances unanswered checks as misses and publishes the snapshot. An input during the reset or for a previous check leaves the next ring pending.
- Standard Manual has one ring and High-Risk Heavy has three. Untimed Cue keeps its directional choices. Ordinary Auto-Good runs directly at 1.00×, and a tagged High-Risk move still uses the Untimed Cue flow when Auto-Good is selected.

The provisional schedule starts the first approach after 0.15 seconds for the prompt to arrive. The ring takes 1.15 seconds to reach overlap. The base scoring window is 0.75 seconds centered on overlap and grows by up to 0.30 seconds with Focus. The next ring starts 0.30 seconds after the previous window closes.

### Fixture tuning

The sandbox uses fixed Speed values (12, 10, 8), a 25% low-HP threshold and a 2× Finisher. These are playtest parameters. Untimed checks ask for the indicated input. Companion tactics record the current selection while both party fighters use manually selected actions. The current encounter has no Bonus Primary source. The mock's extra action on a perfect check is excluded from the server.

## 2026-11-25 merge and verification

PR #18 (`e590b11`) was retargeted from the F1 branch to main and merged as `1cf724d`. PR #14 (`3153ec6`) was then merged as `460107d`. The merge preserves the shared Contracts, Core, Data and server tree from `e590b11`; Claude contributes only client files. The follow-up adds seven Act 1 fighter keys and seven Part 3 Stand sheet keys, binds all eight opponents, and gives Avdol's recruit `spriteKey = "AvdolIdle"`. Existing asset values are preserved; new IDs remain 0 pending uploads.

### Rojo build

PASS: Rojo 7.7.1 builds the combined client/server project.

### Luau analysis

PASS: Luau 0.748 strict analysis of all shared modules and tests. All 30 client/server sources compile; compilation is not full Roblox-aware type analysis.

### Lune suites

PASS: all six suites with Lune 0.11.1 — smoke, tutorial, phase2_contracts, phase2_sandbox, phase3_contracts, phase3_campaign.

### Isolated DataStore restart

**PASS — 2026-11-26.** `Fixture.luau` ran against `SaveService.new(true).campaign` and the real Roblox DataStore `PBA_TutorialProfiles_Studio_v1` in **PBA Persistence Test 2026-11-25** (place `130600351609363`, universe `10779083886`). Studio stopped the write server and started a fresh read server. The write server marker `394b6608-60aa-4f4d-a2a8-def3fc2f7d05` was absent in the new server, which returned marker `f36218c9-7719-439b-b253-095e2a8ba3df`.

- **Hamon / Speedwagon — PASS** (`player:-17956705526701`).
- **Stand / Avdol — PASS** (`player:-17956705526702`).

Both profiles matched the full saved record and the reconstructed character, companion, and inventory views after restart. Each retained Deep skin, cap hair, `#F2C94C`, the selected Origin, level 4, 100 Yen, F1/F2/D1 clears, Training Wraps in the weapon slot, three Mineral Waters with the stack in belt slot 1, one Med-Kit, and the recruited companion. The fixture seeded tutorial completion and Origin before playing the campaign.

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
