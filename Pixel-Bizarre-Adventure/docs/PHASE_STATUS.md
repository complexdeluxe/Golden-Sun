# Phase status

**Active phase** — Phase 0, project scaffold and base contracts.
**Contract status** — Draft for Claude’s client review. Bryce owns the merge to `main`.

| Ticket | Scope | Status |
| --- | --- | --- |
| 0.1 | Isolated Rojo project, tool versions, ownership notes, Lune smoke test | Ready for review |
| 0.2 | Combat, save, tutorial remote and asset contracts | Awaiting Claude’s sign-off |
| Exit gate | Review and merge the verified Phase 0 contracts | Awaiting Bryce |

## Build and smoke test

Run these commands from `Pixel-Bizarre-Adventure/` with the pinned tools installed from `rokit.toml`.

```powershell
rojo build default.project.json --output "$env:TEMP/PBA-Phase0.rbxlx"
lune run tests/smoke.luau
```

The Studio project assigns shared code to `ReplicatedStorage.Shared`, server code to `ServerScriptService.Server`, and the client folder to `StarterPlayer.StarterPlayerScripts.Client`. Missing server and client directories are supported during Phase 0. For a local Studio preview, open the built place or serve the Pixel project on `127.0.0.1:34873` with its own test place. The root project’s existing Rojo port is separate.

Verified on the Phase 0 review branch with Rojo 7.7.1, Lune 0.11.1 and luau-analyze 0.748.

- Rojo produced a place with the four contract modules and the three expected service mappings.
- The Lune smoke test loaded the contracts and checked a sample combat response, four remote names and five asset entries.
- Strict analysis passed on all four contract modules and the smoke test.


## Client review

- Check actors, HP, Stamina, turn order, action costs and disabled explanations against the three-button tutorial HUD.
- Check the intent label, attacker, target and landing turn against the visible enemy warning.
- Check defeat, retry, victory and the two origin options against the authored UI flow.
- Treat asset ID 0 as a local fallback. The five manifest keys identify the stage, three actors and starter Watch.

## Tutorial interface

Phase 1 will create the four functions from `RemoteContract` under `ReplicatedStorage.Shared.TutorialRemotes`. A successful start, action or retry returns a complete snapshot and profile. The server may return a fresh snapshot if the client submitted a stale revision. Start requests carry an empty table. Repeated starts return the current battle when available. Retry is for a defeated tutorial and starts a new battle ID. Origin selection becomes available on completion and returns the saved profile.

Action targets and enemy intents are supplied by the server. `estimatedPower` is display information for the telegraph. Snapshot logs contain an ordered battle history so a UI can replace its transcript when resyncing. Battle turns and revisions are one-based. Revisions advance within each battle, including across enemy actions. The server derives the player from the remote context.

Begin Phase 1 after the reviewed contract merges. This phase contains contract declarations and test fixtures.
