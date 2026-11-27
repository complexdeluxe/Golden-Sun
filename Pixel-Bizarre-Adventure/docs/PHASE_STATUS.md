# Phase status

**Phases 0–6.1 Backend Complete.** Live campaign progression and the Phase 4–6 client screens are the remaining launch integration work.

- Verification baseline: Rojo build, shared Luau analysis, server compilation, and 15/15 Lune suites passed. On Windows, run `scripts/check.ps1` for the build, analysis, and suites.
- **DataStore restart PASS** in the isolated Studio place on November 26, 2026. Both origins restored their saved state in a fresh server. [Restart evidence](PHASE_ARCHIVE_0_3.md#isolated-datastore-restart)
- Activity server bindings are live in the project. Auto-Battle resumes on rejoin and pays completed five-minute ticks. Expedition claims settle once per mission. The live campaign still needs the full-Act clear and ticket award hooks.

## Next Ticket — Codex

- Integrate live Acts 1–5 progression. Wire authoritative first-clear settlement to Act unlocks, the lineage ledger, and eligible Expedition Ticket awards. Connect Castle wipes, aging, mastery, and heirloom grants as their encounters come online. Verify both origins and keep replay rewards separate from first clears.
- Add a server-side `AnalyticsService` Onboarding Funnel for Join → Tutorial complete → Origin chosen → Hub → F1 clear → F2 clear → D1 clear. Record steps from committed progression and verify that reloads and replays do not advance the funnel twice.

## Next Ticket — Claude

1. **PR #1 · Day-1 HUD Polish** is merged as GitHub PR #19. It covers Retreat and intent spacing, underfoot callouts, the 640×360 HUD overlay, and layered player sprites.
2. **PR #2 · Phase 4 UI.** Build the Blacksmith, Cyberware Clinic, and D’Arby’s Parlor against `Phase4Remotes`. The Blacksmith review is GitHub PR #20.
3. **PR #3 · Phase 5 UI.** Build the Lineage panel, Bloodline Tree, heirlooms, mastery, and Pass the Torch flow against `LineageRemotes`.
4. **PR #4 · Phase 6 UI.** Build the Auto-Battle claim feed and Expedition Board against `ActivityRemotes`, then verify PC and mobile layouts and polish combat feedback.

Use server snapshots and legality for station controls. Reuse the same request ID and action after an uncertain reply, and refresh after a definitive stale revision.

[Phase 0–3 archive](PHASE_ARCHIVE_0_3.md) · [Detailed Phase 4–6 handoffs and verification](PHASE_HANDOFF_4_6.md)
