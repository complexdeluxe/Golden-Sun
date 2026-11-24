# Phase status

**Active phase** — Phase 1, Raining Carriage Crash tutorial.

**Frozen contracts** — Phase 0 merged via GitHub PR #3 at `b842e31`, including Claude’s sprite key and individual defeat event.

| Ticket | Scope | Status |
| --- | --- | --- |
| 1.1 | Headless tutorial combat and acceptance tests | Verified in the integrated local build |
| 1.2 | Tutorial remotes and profile persistence | Verified in the integrated local build |
| 1.3 | Battle UI, feedback, retry and origin selector | Integrated from Claude PR #6 |
| 1.4 | Integrated Studio playtest and persistent-save check | Local UI and real remotes pass. Roblox DataStore restart check pending. |

## Client handoff

Use the four frozen functions under `ReplicatedStorage.Shared.TutorialRemotes`. Invoke `StartTutorial` with an empty table, show the returned snapshot, and send the current battle ID and revision with each action. Each successful response gives the next input snapshot and the entire ordered log. Use its latest events to show actions and replace the transcript when resyncing. Guard applies to the enemy actions resolved in that response.

A victory or defeat has empty actions and intents. Retreat thresholds end this encounter immediately. The lower-HP enemy emits `Flee` if still above zero. A knockout emits `Defeated`. Opening a completed tutorial returns Victory and the saved profile. If its origin is still empty, offer `ChooseOrigin`. A successfully selected origin is durable and its identical submission can be retried safely. Both origin options use the frozen Phase 0 IDs.

Asset manifest IDs are placeholders. Use the actor’s optional sprite key and local fallback visuals when the mapped ID is `rbxassetid://0`.

## Build and test

From `Pixel-Bizarre-Adventure/`, run `rojo build default.project.json --output "$env:TEMP/PBA-Phase1.rbxlx"`, `lune run tests/smoke.luau`, and `lune run tests/tutorial.luau`. Run strict analysis on the headless shared modules and tests.

For Studio, use the separate Pixel test place and Rojo at `127.0.0.1:34873`. The default Studio store is local to one running server. To test saves across Studio restarts in an API-enabled test place, set the boolean `UseTutorialDataStore` on ServerScriptService. Studio then uses `PBA_TutorialProfiles_Studio_v1`. A published game server uses `PBA_TutorialProfiles_v1`.

The combined Phase 1 gate is a full Studio run with the client, including a defeat and free retry, a victory, then a saved origin after restarting the session.

## Integrated Studio verification

Combined server PR #5 and client PR #6 in an isolated place file. Rojo 7.7.1 built the place, the Lune smoke and all seven tutorial scenarios passed, and all client and server Luau files compiled. The Studio client used all four real tutorial remotes with the mock badge clear.

- Clicked Heavy, Quick, Quick, Heavy. Dario retreated on round four and the victory banner appeared.
- Opened the origin picker, selected Hamon and confirmed. The UI displayed the saved origin and the server returned the same choice on a subsequent start request.
- Restarted the local test, took a defeat, clicked Retry, and checked that it returned a new battle ID, 32 HP, 3 Stamina and Dario’s opening intent.

The default local Studio test used in-memory storage. Persistence across a Roblox server restart remains to be checked in the API-enabled test place with the isolated Studio DataStore.
