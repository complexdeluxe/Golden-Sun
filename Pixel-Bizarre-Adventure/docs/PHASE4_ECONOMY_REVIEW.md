# Phase 4 economy review — 2026-11-25

Reviewed Antigravity commit `7cb2c8b`, based directly on `e590b11`. The branch exists in the local `Documents/GitHub/Golden-Sun` repository; it was not present on origin when fetched. No Phase 4 code or contracts were integrated.

## Existing suite

`lune run tests/phase4_economy.luau` passes with Lune 0.11.1.

## Strict analysis

`luau-analyze src/shared/Data/Phase4EconomyData.luau src/shared/Core/Phase4Economy.luau tests/phase4_economy.luau` fails (exit 1, Luau 0.748). Core errors occur at lines 103, 130, 132, 147 and 434; the test also fails analysis at line 88. Use explicit affix, rarity-weight and parlor-entry types instead of inference through heterogeneous frozen tables and `any`. Retain strict mode and rerun analysis before integration.

## Correctness findings

1. **P1 — Rolled affixes exceed the frozen point allowance.** `rollDistinctLines` (Core lines 124–130) forces flat values to at least 1 and samples percentage effects independently of their point cost. Deterministic T1 Rare drops with a constant RNG of 0 produce +1 Physical costing 1 point against a 0.6-point budget. RNG 0.999 produces a 10% proc costing 5 points against the same budget. Rerolls use the same routine. Resolve the fractional-budget/minimum-effect rule against the spec, then enforce total cost and test every tier/line count and percentage affix.
2. **P2 — Act clamping can erase Legendary bonus lines.** `generateGearDrop` (Core lines 147–172) discards weights above the Act cap instead of clamping sampled counts. T1 Legendary has weight only at 2 and 3 lines, so all eligible weights are zero and it returns a plain item. Clamp the drawn count to the Act cap or explicitly define the redistribution policy; cover all rarity/Act combinations. T1 Legendary currently has zero natural drop chance, but this exported generator accepts it and can be used by future reward sources.
3. **P2 — Two Full Borg representations disagree.** `RaceId` exposes `FullBorg`, but strain in Core lines 384–386 depends only on the separate boolean. `evaluateCyberwareLoadout("FullBorg", false, {T5 HeadOptics, T5 Neural, T5 TorsoChassis, T1 Limbs}, false, 0)` accepts load 136 with tolerance 170 and no strain. Normalize the representation or reject inconsistent inputs before wiring a contract. The existing suite checks only `("Cyborg", true)`.

## Contract handoff requirements

Keep economy integration gated on strict analysis and the correctness fixes above. The pure calculator returns proposed mutations; the server must persist costs, RNG outcomes, pending smith offers and parlor pity atomically before reveal. Existing tests check only an in-memory pending-offer lock, not durable reconnect behavior. Validate item state and identifiers at the server boundary. The current parlor API implements single spins only; its ten-spin pricing table does not implement a ten-spin transaction.

The Phase 3 real DataStore restart gate remains separate and open until an isolated published test place is connected and Studio API access is enabled.