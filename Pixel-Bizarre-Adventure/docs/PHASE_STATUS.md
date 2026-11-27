# Phase status

**Phases 0–6.1 Backend Complete.** The live campaign progression bridge and onboarding funnel are wired. Phase 4–6 client screens and Studio playtesting are next.

- Verification baseline: Rojo build, shared Luau analysis, server compilation, and 17/17 Lune suites passed. On Windows, run `scripts/check.ps1` for the build, analysis, and suites.
- **DataStore restart PASS** in the isolated Studio place on November 26, 2026. Both origins restored their saved state in a fresh server. [Restart evidence](PHASE_ARCHIVE_0_3.md#isolated-datastore-restart)
- Activity server bindings are live in the project. Auto-Battle resumes on rejoin and pays completed five-minute ticks. Expedition claims settle once per mission. First-time Dungeon and Castle clears award Expedition Tickets within the account cap. A first Castle clear unlocks Post-Act Auto-Battle for its Act.

## Live progression and onboarding

- The Option 1 routes use the existing Act 1 encounters first, then progress through all five Parts. The current map displays one section at a time. New encounters use the shared battle engine with catalog opponents, default Dungeon approaches, and two-phase Castles. Bespoke boss behaviors and a full replay selector remain follow-up work.
- First-clear settlement queues durable age, Echo, mastery, heirloom, and ticket updates. A full-party wipe at an uncleared Castle consumes one recovery. The existing client needs a final-attempt confirmation UI to submit the Castle play option with the `:confirm` suffix after five wipes.
- The Roblox onboarding funnel has nine server steps, from Joined to CompanionRecruited. Delivery is best effort. Verify analytics in a published test experience, where Roblox accepts funnel events.

## Heir reset

- Pass the Torch and the sixth qualifying Castle wipe commit the new life and its starter state in one SaveService update. The heir starts at Act 1 and level 1, with the starter kit and any earned Family Purse starting bonuses.
- A Family Purse purchase made before the heir’s first encounter credits only the extra amount for that rank. Later purchases apply to the next heir. A repeated retirement request returns the original receipt. Account ranks, Echoes, mastery, heirlooms, Vault data, Expedition Tickets, and cosmetics carry forward.

## Next Ticket — Claude

1. **PR #1 · Day-1 HUD Polish** is merged as GitHub PR #19. It covers Retreat and intent spacing, underfoot callouts, the 640×360 HUD overlay, and layered player sprites.
2. **PR #2 · Phase 4 UI.** Build the Blacksmith, Cyberware Clinic, and D’Arby’s Parlor against `Phase4Remotes`. The Blacksmith review is GitHub PR #20.
3. **PR #3 · Phase 5 UI.** Build the Lineage panel, Bloodline Tree, heirlooms, mastery, and Pass the Torch flow against `LineageRemotes`.
4. **PR #4 · Phase 6 UI.** Build the Auto-Battle claim feed and Expedition Board against `ActivityRemotes`, then verify PC and mobile layouts and polish combat feedback.

Use server snapshots and legality for station controls. Reuse the same request ID and action after an uncertain reply, and refresh after a definitive stale revision.

[Phase 0–3 archive](PHASE_ARCHIVE_0_3.md) · [Detailed Phase 4–6 handoffs and verification](PHASE_HANDOFF_4_6.md)
