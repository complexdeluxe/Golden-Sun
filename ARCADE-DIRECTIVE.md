# Arcade integration test: Codex and Claude handoff

## Objective and authorization

Bryce and Complex want a working arcade selection prototype using games Complex has already created. This is an experiment in reuse and collaboration efficiency; it is not a commitment to the team's commercial game concept. Create a small working experience where a player can select, play, exit, and switch between all three named games: Number King (GuessingGame.py), Take Flight! (TakeFlight.py), and Dark Moon (APCreateTask.py). Two working games are an integration checkpoint, not the final scope. Preserve and make all existing cheat/developer codes usable.

Implement and test locally and in an agreed Studio test area. Use GitHub to share code and reviewable changes. Do not publish the experience, spend Robux, add monetization, or modify unrelated animation assets as part of this test.

## Starting facts

- Repository: https://github.com/complexdeluxe/Golden-Sun ; default branch: main.
- Bryce's intended developer clone: C:\Users\bryce pc\Documents\GitHub\Golden-Sun. Verify access and contents in the new Codex session.
- The previous chat also used a separate working copy called Golden-Sun-Rojo inside its ChatGPT project directory. Do not assume this is the active developer clone or sync two copies at once.
- Both developers report a connected Rojo plugin. Bryce's server Output confirmed the v1 connection test ran. Complex's own execution check has not been independently verified here.
- Current default.project.json syncs only ServerScriptService/GoldenSunSyncTest/ConnectionTest. It does not yet sync UI, modules, remotes, or arcade code.
- It serves on localhost port 34872 and permits only Light of the Golden Sun, place ID 78369564991843. A separate test place requires a deliberate configuration update; do not silently bypass the place restriction.
- Complex confirmed uploads are complete. GuessingGame.py, TakeFlight.py, and APCreateTask.py are present on main and have been inspected as Python source. The two graphical games import cmu_graphics; GuessingGame.py uses standard-library random/time and console input. Extra uploaded Python projects are outside the selected three-game scope unless required dependencies are discovered.
- Each machine needs its own Rojo CLI server when syncing local files. Keep the server terminal open. The CLI is not committed in this repository and may need its full executable path.
- A successful connection to Studio is not proof that the complete arcade works.

## First action: intake, then one architecture decision

Uploads are complete. Pull main and verify the supplied files against the confirmed game mapping below. Read applicable AGENTS.md and CLAUDE.md instructions before editing. Inspect existing work before proposing replacements.

Record a compact inventory in docs/arcade-intake.md: filename, game name, source format, startup entry point, client/server requirements, assets, controls, storage/network dependencies, and whether it runs independently. Do not execute unknown shell installers or enable every imported script just to inspect it. Preserve originals; make adaptation changes separately.

Source files may be Luau, Roblox place/model files, or code for another engine. Do not assume they are already Roblox games. If the uploads are screenshots, exported binaries without source, or inaccessible external dependencies, explain the concrete missing input. If they use another engine, estimate the smallest adaptation before promising reuse.

Port Number King first, then Dark Moon, then Take Flight! as the recommended complexity order. All three are required for completion. Use independent client UI sessions within a shared Roblox menu as the starting architecture for these 2D games; confirm this during intake. The Python programs must be reimplemented in Luau; installing a Python package does not make them executable in Roblox. Other hosting models are relevant only if new dependencies justify them:

- Client UI games: local game sessions within a common menu, with cleanup on exit.
- Roblox world games: isolated runtime content with explicit round/player ownership.
- Existing separate places: first assess whether adaptation or place launching is appropriate; do not promise local Studio verification of a multi-place journey.

Default to independent player sessions only when the games support them. If a supplied game requires a shared round, the contract must reflect that. Do not introduce a shared-world framework for these client UI games. Scores and cheats are session-local for this test; no competitive server leaderboard or persistence is in scope.

## Minimum product

1. A readable selection screen with a title, available game cards, and Play actions. Use the actual supplied game names.
2. Launch a selected game with its essential existing gameplay preserved.
3. Show basic controls and a reliable return-to-menu action.
4. End and clean up the current game before starting another.
5. Show a useful error and recover to the menu if a game fails to load or start.
6. Support mouse/keyboard first and basic touch interaction in the menu. Assess game-specific device support rather than claiming it.

No currency, shop, persistence, elaborate lobby, matchmaking, analytics service integration, or new art pipeline is needed. Score presentation is optional and only added where an existing game exposes it cleanly. Use simple UI placeholders for missing thumbnails.

## Ownership and parallel work

This division assigns accountability; it does not claim either model is inherently better. Reassign a bounded task if measured results justify it.

| Owner | Primary responsibility | Owned paths after inspection |
| --- | --- | --- |
| Codex with Bryce | Intake, architecture, shared contract, Number King port, launcher/session coordination, server validation where needed, Rojo mappings, integration and end-to-end verification | default.project.json; src/shared/arcade/; src/client/arcade/runtime/; src/client/arcade/games/NumberKing.luau; src/server/arcade/; docs/arcade-intake.md; docs/arcade-contract.md; docs/arcade-test-results.md |
| Claude with Complex | Selection UI, Dark Moon and Take Flight! ports, preserving supplied mechanics and codes, documenting controls and adaptation issues | src/client/arcade/ui/; src/client/arcade/games/DarkMoon.luau; src/client/arcade/games/TakeFlight.luau; docs/arcade-game-notes.md |
| Complex | Identify originals, explain controls and intended behavior, confirm visual/gameplay fidelity | Supplied originals; answers about original games |
| Bryce | Choose the active shared Studio sync owner and judge usability | Product decisions and acceptance |

Paths are proposed namespaces, not permission to reorganize an existing project wholesale. Confirm them against the uploads. Server adapters, if required, are owned by Codex; Claude supplies game-specific requirements instead of editing shared/server paths concurrently. Avoid global formatters and generated place-file changes across both branches.

Codex creates the shared contract first; Claude reviews it before both implement against it. Neither assistant changes the contract unilaterally after the agreement. Shared files have one writer at a time.

## Contract to settle before parallel implementation

Write docs/arcade-contract.md with the real path mappings, signatures, responsibilities, and a tiny usage example. Use the source-specific port requirements below alongside this client UI contract:

- Registry metadata: stable id, display name, short description, controls, supported devices, and the game's adapter reference.
- Launcher lifecycle: menu -> loading -> playing -> stopping -> menu, plus recoverable error handling. Ignore/debounce repeated launch actions while transitioning.
- Adapter lifecycle: construct a session using an explicit context; start it; destroy it idempotently even if startup partially failed.
- Context: owned UI/runtime containers, a scoped cleanup mechanism, and a request-to-exit callback. Keep game references scoped to the session.
- Cleanup: disconnect events, cancel loops/tasks/tweens, release input/camera bindings, destroy owned UI/instances, and restore settings changed by the game. No gameplay callbacks should affect later sessions.
- Ownership: define who owns input, camera, character controls, audio, and any world content. Do not remove other players' or pre-existing place content during cleanup.
- Server behavior, if present: server owns authoritative shared state and validates game IDs, permissions, request rate, and applicable score/result claims. A client-provided score is not automatically trusted.

These are design requirements, not verified APIs. Adapt the contract to the source. The launcher must own switching; adapters should not directly launch one another. Keep the interface small and avoid building a general framework for three games.

## GitHub and Studio coordination

- Pull current main first and inspect uncommitted changes. Do not discard someone else's work. Preserve the original supplied files before adapting them.
- Work on codex/arcade-runtime and claude/arcade-games, or equivalent task branches. Commit related changes in small units. Use pull requests for shared changes; Codex coordinates the combined integration after review and appropriate repository authorization. Do not force-push shared history.
- One person owns Rojo syncing into the shared Studio place at a time. Start this test with Bryce/Codex as the designated sync owner; Complex/Claude can code concurrently and hand off commits. If that changes, explicitly announce the transfer.
- Separate local Studio test copies are preferable for concurrent playtests, but the current project rejects other place IDs. Establish compatible test configuration before assuming independent test places work. Do not have two Rojo servers overwrite the same shared instances.
- Confirm which working directory the running Rojo server serves. Editing a different clone will not update Studio. Restart the server after project mapping changes when necessary.
- Work in Edit mode for Rojo connection/sync. Launch or restart playtests to verify execution; syncing script source does not prove a running session restarted with that code.
- Extend the existing Rojo mappings narrowly and preserve unrelated instances. Preview changes before sync. Stop if it proposes removing unrelated assets.
- GitHub carries code, directives, and lasting decisions. Use short human-relayed Discord messages for ready/blocker/handoff notices. Neither assistant should poll continuously or assume access to the other's conversation or an automatic chat bridge.
- Send notices at task start, an interface blocker/change, a ready commit, and a test result. Use: task | status | branch/commit | files | test evidence | next owner. No repeated reassurance or transcript copying.
- Keep the directive, contract, intake, and one results record as the durable context. Do not create a second wiki or a continuously maintained Obsidian vault for this experiment.

## Build order and review checkpoints

1. Intake: inspect completed uploads, verify two candidates, record the hosting decision and dependencies.
2. Agreement: settle contract and path ownership. Codex provides the runtime entry points; Claude confirms the adapters can use them.
3. Parallel build: Codex implements launcher/runtime, mappings, and Number King. Claude implements menu plus Dark Moon and Take Flight! adapters against the agreed contract, using small local stand-ins only to unblock interface work, never as a substitute for the supplied games.
4. First integration: combine and run one actual game through select -> play -> exit. Resolve lifecycle/input issues before integrating the second.
5. Second integration: add the second game and exercise repeated switching. Review original behavior with Complex.
6. Third integration: add Take Flight!, preserve stat mechanics and both codes, then repeat switching checks across all three games.
7. Verification and handoff: run the acceptance checks, record observed results and remaining limitations, then report the efficiency evidence.

Do not spend a fixed calendar sprint before learning whether the inputs are reusable. Give a scoped estimate after intake and revise it when an actual incompatibility appears.

## Acceptance checks and evidence

Record pass/fail/not-tested, reproduction steps, and relevant Output/errors in docs/arcade-test-results.md. Do not equate a build passing with a playtest passing.

- Menu appears on a fresh join; each available game has the correct name and controls.
- All three named games launch, accept input, and demonstrate their essential original gameplay. Exercise every documented code and its invalid-input path.
- Exit returns to the menu; restarting a game creates a fresh playable session.
- Perform at least 10 alternating switches. Look for duplicate UI, repeated audio, stuck controls/camera, accumulating runtime instances, and callbacks from ended sessions.
- Rapid clicks do not create overlapping sessions. A forced startup failure returns to a usable menu and cleans partial state.
- Character respawn and player departure clean up according to the chosen game model.
- For per-player games, a two-player Studio test verifies that one player's selection/exit does not alter the other's session. For shared rounds, test the explicitly documented join/leave rules.
- Menu is usable at a desktop resolution and a phone portrait size; mark individual games' touch limitations honestly.
- Existing unrelated scene/animation content remains intact. Separate pre-existing asset warnings from errors introduced by this work.
- Run relevant existing checks and a Rojo build. Add targeted automated checks only where useful for nontrivial lifecycle/state behavior; avoid a test framework project for this prototype.

If an assistant cannot access Studio or an input file, state that limit and supply exact human verification steps. Never mark a test passed without observing evidence.

## Efficiency experiment

Measure whether the combined prototype is easier to finish, not whether two assistants produce more code. Track, without continuous logging:

- Time to the first playable supplied game, the two-game checkpoint, and all three working games.
- Approximate human coordination time; number of manual handoffs and interface revisions.
- Merge conflicts, integration defects, and work redone because assumptions were wrong.
- Model usage/cost only where the tools actually expose it; otherwise mark unavailable.
- What each assistant completed and which next task allocation should change.

Use timestamps at milestone completion and a short final table. This single trial can reveal workflow bottlenecks; it cannot establish general model superiority or guaranteed cost savings. Pause and fix the interface if coordination consumes more effort than the work it enables.

## Copy into the new Codex session

Read ARCADE-DIRECTIVE.md in complexdeluxe/Golden-Sun and the repository instructions. This is an arcade integration experiment using Complex's existing game uploads, which are now complete. Work from the intended Golden-Sun clone and verify the branch, remote, the three confirmed source files, and active Rojo source folder. Start with intake and a small shared lifecycle contract. You own runtime integration, Number King, project mappings, and final verification; Claude with Complex owns selection UI and Dark Moon/Take Flight! adapters. All three games and every existing cheat code must work. Give me a concise message to relay to Claude with the exact contract, assigned paths, and first task. Proceed with the authorized prototype after the interface is agreed, preserving originals and unrelated place content. Do not publish or spend Robux. Report actual verification evidence and coordination overhead.

## Copy into Complex's Claude session

Read ARCADE-DIRECTIVE.md in complexdeluxe/Golden-Sun and applicable repository instructions. We are adapting my uploaded existing games into a small arcade selection prototype with Codex handling runtime and integration. The upload batch is complete. Inspect APCreateTask.py (Dark Moon) and TakeFlight.py (Take Flight!), their controls, startup/cleanup, stat tables and cheat behavior. Codex owns GuessingGame.py (Number King). You own selection UI and Dark Moon/Take Flight! adapters under the agreed paths. Review docs/arcade-contract.md or request the specific missing interface through me before coding against assumptions. Work on claude/arcade-games; preserve originals, keep changes within your ownership, and hand off a commit with behavior changes, dependencies, tests, and blockers. Do not independently sync into the shared Studio place while Bryce owns the connection. Do not publish or spend Robux.



## Confirmed source-specific port requirements

This section incorporates Bryce and Complex's clarification after upload completion. It supersedes earlier conditional two-game scope. Source review is static; original Python execution and Roblox ports have not yet been verified.

| Display name | Source | Core behavior | Port owner |
| --- | --- | --- | --- |
| Number King | GuessingGame.py | Text-led number guessing, hints, grades, easy/hard modes and developer number override | Codex |
| Dark Moon | APCreateTask.py | 2D obstacle survival, movement/jump/dash, progression through ten stages, completion and invincibility | Claude |
| Take Flight! | TakeFlight.py | 2D flying/shooting, hazards, health, score-earned points and four upgrade stats | Claude |

Other uploads such as Catacombs, ArcheryScene, DrawingBoard, DrawingBoardRemastered and LoadSave are reference material, not extra arcade deliverables.

### Python reference environment versus Roblox runtime

The supplied suggestion was `pip install cmu-course-api`. The inspected games actually import `cmu_graphics`; CMU's official desktop project documents `pip install cmu-graphics`:
https://github.com/cmu-cs-academy/desktop-cmu-graphics#installation

If reference execution is needed, use a disposable Python virtual environment and install the graphics package there, then record what runs and any compatibility fixes. Do not install cmu-course-api merely because both packages have CMU in their names. Number King requires only Python's standard library. An installed Python dependency is not part of the shipped Roblox game. No package has been installed or source game executed by the handoff author.

Keep originals untouched; reference-launch fixes such as a missing desktop event-loop entry point belong in a copied harness. TakeFlight.py should be checked for the desktop run call, while APCreateTask.py includes cmu_graphics.run(). Do not promise execution before observing it.

Build native Luau modules and Roblox GUI/input/update logic. Use a scaled 400-by-400 logical playfield for the graphical games as a reasonable starting point, preserve aspect ratio, and use an elapsed-time/fixed-step strategy so original frame-based movement and timers do not speed up on high-refresh clients. Audit the original step rate before choosing constants. Avoid translating desktop blocking input/sleep calls directly into UI loops. No full Python interpreter, external Python server, or generic CMU graphics compatibility layer is needed.

### Codes: all must be usable

Expose an in-game Codes action with a text field, confirmation/cancel behavior, validation, and visible feedback. Preserve exact code strings. Support the original keyboard routes where practical, but do not make obscure simultaneous punctuation/uppercase chords the only route. These are intended game features in this prototype, not permission to execute arbitrary code or modify other users.

| Game | Original activation/code | Behavior to preserve |
| --- | --- | --- |
| Number King | Enter `its me` at initial mode prompt | Enable developer mode; reveal the target, show guess tracking, allow an integer target override before guessing and again after hard-mode target shifts. A noninteger response can decline the original optional override. |
| Number King | Enter `complex` at mode choice, including the prompt after `its me` | Select hard mode: target range 1..100000; shifts before guesses 20, 40, 60 and 80 in the source's initial loop. Default/easy range is 1..100. Keep target reveal inside developer mode. |
| Take Flight! | Hold uppercase `S`, `(`, `)`, then `complexscore` | Prompt for and set an integer score; allow the normal score/stat-point flow to react. |
| Take Flight! | Hold uppercase `D`, `+`, `T`, then `complexdura` | Prompt for and override durability beyond the normal UI cap. Handle extended values without out-of-range table access or a crash. |
| Dark Moon | In first five gameplay seconds, hold `|` and `~`, then `The Author of the Continental Page` | Enable effectively permanent invincibility for that run and show that invincibility was used for the completion. The source kills the player on an incorrect entry via that route; document and preserve intentional game behavior separately from a harmless cancelled UI dialog. |

The new Codes UI must make these features reachable reliably. Default: allow entering the Dark Moon phrase from pre-run setup so a player need not type a long phrase within five seconds; retain the original early-run route as well. Keep codes available to all prototype players in their own session, rather than silently restricting them to Studio or a developer user ID. Do not add global admin remotes or ranked rewards.

Take Flight's durability code can exceed its fixed stat tables: implement a documented extension/fallback that still permits beyond-cap durability. Do not silently clamp to the ordinary cap or preserve a crash as gameplay fidelity. Validate finite, representable numeric input; malformed entries must not break the session. Inspect intentional high-score skill-point behavior before changing it: source comments explicitly mark the final requirement flag as intentional.

Number King's announced masochist mode is a coming-soon placeholder, not an implemented code to invent. Preserve actual implemented features; identify text-only unfinished features honestly. Fix displayed count/grade inconsistencies in the port only with a documented rationale, keeping substantive mode behavior intact.

### Dark Moon completion and audio

The owner describes Dark Moon as passing ten stages to win. Static review shows stage growth capped at ten, with a victory transition at minute 7 and seconds greater than 19, followed by a fade/death-style ending. Record that mismatch during intake; implement a clear successful completion state after surviving the source's final-stage end sequence, rather than ending immediately on entering stage ten or counting the successful ending as a loss. Complex should verify intended feel. The full normal-length run remains an acceptance check; accelerated test controls are evidence for logic only, not proof of real-time pacing.

The source references uploaded local MP3 files. Roblox does not automatically play repository files as uploaded audio assets. Keep audio IDs/configuration explicit; use an existing authorized Roblox asset when supplied, otherwise leave that sound disabled with a noted limitation so core gameplay testing can proceed. Do not upload or publish audio assets as an unrequested setup step.

### Final source-specific acceptance

- Number King: easy and hard wins, hints/grade display, exact shift boundaries, developer reveal and target override, malformed input, exit/restart.
- Take Flight!: flight/shooting, hazard/health behavior, spending/refunding available stat points where supported by source, score-driven points, both codes, valid beyond-cap durability and invalid input.
- Dark Moon: movement, jump, dash, collisions/death, progression through all ten stages and successful final completion; invincibility with visible assisted-completion marker; code entry reachable before the run; invalid legacy code behavior.
- Every game: fresh state after restart/switching, Codes UI input does not leak into gameplay input, no stale events/audio/update loops, and no cross-player interference.
