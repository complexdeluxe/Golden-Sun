# Arcade verification record

First review baseline: `0ab6423`, November 19, 2026 (US Eastern). The handoff changes documentation. There is no playable Roblox adapter in this revision.

## Observed checks

| Check | Result | Reproduction and evidence |
| --- | --- | --- |
| Developer checkout | Pass | `git remote -v` pointed to `complexdeluxe/Golden-Sun`. `git log -1 --decorate` showed local main, origin/main and the initial task branch at `0ab6423`. Inspected the three named Python originals and the current project JSON. |
| Existing offline build | Pass | Rojo 7.7.1, from the intended checkout: `rojo build default.project.json --output <temp-dir>/baseline.rbxlx`. Exit 0, “Built project”. Parsed the XML: its only three Item elements were ServerScriptService, folder GoldenSunSyncTest and script ConnectionTest. This checks the pre-arcade mapping. |
| Shared sync source | Mismatch observed | The running `rojo.exe serve` command named `Golden-Sun-Rojo/default.project.json`. The developer checkout has a different path. No Studio sync was changed during intake. |
| Original Number King, easy | Pass | Ran the unmodified script via Python `runpy.run_path`, replacing console input with a sequence, sleeps with a no-op, and random draws with their lower bound. Inputs `its me → easy → 42 → oops → 40 → 42` produced a higher hint and grade S. The invalid guess did not consume a turn. |
| Original Number King, hard | Pass | Same harness, entered `its me → complex → 123`. Guessed 0 for turns 1–79, overriding targets with 143, 163, 183 and 203 immediately before turns 20, 40, 60 and 80. Guess 203 on turn 80 won with B. Observed four shift messages. |
| Original Number King, grade boundary | Source defect reproduced | With generated easy target 1, submit 0 until the chosen winning turn, then 1. Turn 99 printed D, turn 100 printed no grade, turn 101 printed F. See intake for proposed correction. |
| Desktop graphical games | Static inspection only | Both files end with `cmu_graphics.run()`. Inspected frame clocks, controls, win/death, codes and stat tables. Neither game was launched. |

## Studio acceptance queue

Each row is **not tested** until someone records the commit, Studio mode/device, observed result and relevant Output. Start in Edit mode with one authorized sync owner. After building the arcade mapping from the intended checkout, verify the preview contains only the designated arcade instances and connection test. If it proposes unrelated removals, stop before applying. Start a fresh playtest after sync.

| Area | Procedure and expected observation |
| --- | --- |
| Join and devices | Join at desktop resolution, then use a phone portrait emulator. Check three game names, controls, readable cards and working Play/Back actions. Record which individual game inputs work on touch. |
| Number King | Play easy and hard. Check directional and distance hints, grades, `its me`, `complex`, overrides before guesses 20/40/60/80, malformed entries, an optional override decline, grade at 100 and fresh restart. |
| Dark Moon | Exercise A/D, jump, dash, fast descent, collisions and death/restart. Cancel a code; submit a wrong legacy phrase in the early window; submit the correct phrase pre-run and via the legacy route. Verify the assisted marker, all ten stages and a full normal-speed run through 7:20 and its victory fade. Record the observed time, ending and Complex's fidelity assessment. |
| Take Flight! | Fly, fire, hit hazards, take damage, regenerate and reach death. Spend/refund each stat. Run score across 200/400/750/1000/2000, observe strict boundaries and repeated awards above 2000. Use both code dialogs, malformed values, cancel, and durability 6 and 7+. Verify actual derived effects and that typing/clicking dialogs never moves/fires. |
| Session lifecycle | Exit and relaunch each game. Perform 12 launches cycling Number King → Dark Moon → Take Flight!, returning to menu each time. Inspect player UI and Output for duplicate frames, stale updates, input, audio and binding leaks. Rapidly press Play twice. Force an error after a game has allocated UI and a connection in a disposable test copy, verify cleanup/error/menu, then play another game. |
| Isolation and existing place | Respawn during a game; check cleanup, menu and restored controls. Start a two-player local server, join different games, exit/leave with one client, verify the other continues. Compare unrelated scene/animation content and Output with the pre-sync baseline. |

## Coordination

| Milestone | Evidence |
| --- | --- |
| Intake and proposed interface | November 19, 2026, 10:58 p.m. ET: source review and original Number King reference checks. Codex owns runtime and integration. Claude review pending. |
| First playable, two-game, three-game | Pending. Record the first observed Studio playtest timestamp at each milestone. |
| Overhead | One proposed interface, zero agreed revisions. One handoff prepared for human relay; receipt, human coordination time and model cost unmeasured. No merge conflict observed in this checkout. The active Rojo source mismatch was detected before implementation. |
