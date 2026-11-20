# Claude handoff: 2D Roblox arcade prototype

You are working with Complex on complexdeluxe/Golden-Sun. Bryce is working with Codex. Read the latest ARCADE-DIRECTIVE.md and applicable repository instructions before editing. Pull main, inspect the working tree, and preserve existing changes. All source uploads are complete.

Goal: port three existing Python games into a fully 2D Roblox arcade selection experience. Use native Luau and Roblox GUI elements with a scaled logical playfield. No 3D lobby, 3D gameplay, models, external Python backend, or general-purpose Python interpreter. The originals are reference implementations, not scripts Roblox can execute.

Sources:
- Number King: GuessingGame.py. Codex owns this port.
- Dark Moon: APCreateTask.py. You own this port.
- Take Flight!: TakeFlight.py. You own this port.
- You also own the 2D arcade selection UI.
- Other uploaded games are outside scope unless an actual dependency requires one.

Ownership:
- Your paths: src/client/arcade/ui/, src/client/arcade/games/DarkMoon.luau, src/client/arcade/games/TakeFlight.luau, docs/arcade-game-notes.md.
- Codex owns the shared lifecycle/registry contract, launcher/runtime, NumberKing.luau, server code if needed, default.project.json, and integration/testing.
- Confirm these paths against the actual checkout. Do not independently change shared interfaces or Rojo mappings. Use claude/arcade-games or another clearly named task branch. Preserve original Python files.

First response/action:
1. Inspect both assigned games and report their controls, startup dependencies, timing, win/death behavior, and code-entry requirements.
2. Read docs/arcade-contract.md if present. If absent, send a concise interface request for Bryce to relay to Codex. Propose only the minimal session contract needed; do not create a competing runtime.
3. You may work on isolated game logic and UI layout while the interface is settled. Connect adapters once the contract is agreed; avoid two independently designed launchers.
4. Give Complex a short first milestone and proceed with the authorized implementation.

Required fidelity:
- Dark Moon: A/D movement, Space jump, W directional dash, S faster descent, obstacles/collisions, progression through ten stages, and a clear successful completion state. Source victory occurs around 7:20 rather than immediately on reaching stage ten; see the directive and ask Complex to verify intended pacing.
- Dark Moon phrase: The Author of the Continental Page. Preserve effectively permanent invincibility and a visible assisted-completion marker. Make it accessible via a pre-run Codes interface; retain the original early-run keyboard route where practical. Document the source's incorrect-code death behavior. Cancellation must be handled deliberately.
- Take Flight!: movement, shooting, hazards, health, score, earning/spending/refunding points where implemented, and Durability/Power/Mobility/Precision upgrades.
- Take Flight! codes: complexscore sets an entered integer score; complexdura permits a durability override beyond the normal cap. Validate numeric input and implement beyond-cap handling without indexing past stat tables. Do not clamp silently to the ordinary cap.
- Every actual cheat/dev code must remain usable by prototype players in their own session. These are intentional game features, not developer-account-only tools. No arbitrary code execution or global admin commands.
- Preserve frame-based gameplay pacing with a deliberate time-step strategy; do not tie speed to display frame rate.
- Keep a clean start/exit/restart lifecycle: remove owned UI/instances, disconnect input/events, stop tasks/audio, and prevent callbacks from ended games affecting new games.
- Input typed into a code field must not also move/fire the game.

Python reference execution:
The graphical originals import cmu_graphics. If needed, use a disposable Python virtual environment with cmu-graphics, following the official desktop project documentation. The suggested cmu-course-api package is not the imported graphics library. No Python installation is required for the Roblox runtime. Keep desktop-run compatibility changes in copies, not the original files.

Coordination:
GitHub carries the directive, contract, code and test evidence. There is no automatic conversation bridge to Codex; Complex/Bryce relay milestone and blocker messages. Do not continuously poll or maintain a duplicate vault. Use short notices: task | status | branch/commit | files | evidence | next owner.
Bryce/Codex is the initial shared Studio sync owner. Do not connect a second Rojo source to manage the same shared scripts. An independently configured local test copy may be used only after confirming its Rojo/place configuration. Ask for a specific missing interface or access detail, not repeated general approval.

Deliver:
A usable 2D selection UI and both assigned real game ports, all codes, controls, and clean exit/restart behavior. Hand off commits/PRs with tests actually run and known limitations. Codex integrates all three games.
Test both games, repeated switching, invalid input, cheat activation, beyond-cap durability, death/restart and completion. Distinguish static review, build checks and observed Studio playtests. If Studio access is unavailable, give exact verification steps and mark tests not run.
Use simple visual elements. Repository MP3s are not automatically Roblox audio assets; keep unsupported audio disabled/configurable instead of blocking gameplay. Do not publish, upload assets, spend Robux, add monetization/persistence, or rework unrelated animation content.
