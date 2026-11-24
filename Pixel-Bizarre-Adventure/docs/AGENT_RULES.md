# Project coordination

1. **Freeze contracts first.** Codex drafts shared types and routes on a review branch. Claude checks the client requirements. Bryce merges the signed-off contract before the server and client branches begin.
2. **Keep folder ownership clear.** Codex owns `src/shared/Contracts/`, `src/shared/Core/`, `src/shared/Data/`, `src/server/` and `tests/`. Claude owns `src/client/`. Gemini owns art and tooling under `assets/` and `tools/`, and maintains phase status after the kickoff. Request a contract change on the shared review branch before consuming a new field.
3. **Read phase status at session start.** Update from `main`, read [Phase status](PHASE_STATUS.md), and check active tickets before editing. Record test results and review status at handoff. Work stays within the active phase.
4. **Run headless checks first.** Keep `src/shared/Core/` independent of Roblox Instances. Run the Lune suite before Studio tests and pass the build and test gates before merging server or core work.

Pixel’s Bizarre Adventure lives below `Pixel-Bizarre-Adventure/` in Golden-Sun. Run its project commands from that folder. The repo’s root Rojo project serves the existing arcade.
