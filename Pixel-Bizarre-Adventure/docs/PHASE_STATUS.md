# Phase status

**Active phase** — Phase 2B, Black Sabbath intent and parity sandbox.

**Base** — Phase 1 integration merged via PR #7. Claude’s client playtest polish merged via PR #8. The real Roblox DataStore restart check remains open as a separate follow-up.

| Ticket | Scope | Status |
| --- | --- | --- |
| 2A | Sandbox data shapes, remote names, asset keys, and HUD review | Merged in PR #9 |
| 2B | Audited combat math and server sandbox | Verified locally with the Phase 2 HUD |
| 2B client | Combat HUD v2 | PR #10 at `68ff68b` verified against the real server in a local Studio place |

## Section 2 HUD review

| Surface | What the client can use |
| --- | --- |
| Action economy | Each actor has Primary, Secondary and Bonus Primary availability. Each Primary option belongs to `activeActorId` and gives its slot, Stamina cost, scaling tag, input mode, legality, and per-target preview. End Turn has its own legality. One shared bonus slot per actor per round gives no extra regeneration, Secondary, cooldown tick, or companion turn. |
| QTE | `qtePrompt` identifies the active challenge, available inputs, and server-graded per-check results in display order. `HighRiskHeavy` exposes the 1.70× base and the four timing bands. `Dodged` and `FailedQTE_0of3` are separate log events. The preview gives the effective dodge and interrupt odds conditional on required execution. |
| Resolve and On Fire | Actor records expose current Resolve, gains this turn, Fire duration and Finisher readiness. Resolve caps at 100, gains cap at 25 per turn, and the low-HP +20 trigger is once per fight. Fire lasts two turns, pauses Resolve gains, and grants +15% damage, +15 percentage points Crit chance and +10% Speed until expiry or Finisher. |
| Party belt | Three shared charges, two direct heals, one Med-Kit. Show stock, legal targets, live capped gains and relevant intent IDs. UV Flash cancels an eligible windup and leaves Exposure reserved for offensive interrupts. |
| Companion | Resolve the companion ID against the actor list for HP, Stamina and Guard. Show available tactic, assist readiness and a redirect preview with current target, legal recipients and Guard status. |
| Status and intent | Show removable marks, Stun and Exposure. Exposure lists its target and the next eligible follow-up actor when known. Stage tag and sandbox step indicate Lighter Strike, Shadow Grab windup, landing, or Fade. Show the Fade (+20 Dodge) badge from Black Sabbath’s `Fade` status and its remaining duration. |

## Turn order and end-turn control

The client can use one available Secondary before or after the regular Primary in the same actor turn. A legal Bonus Primary follows the regular Primary and uses its own slot. During an active QTE, the server locks other actions and End Turn until the challenge resolves. The Primary options always belong to `activeActorId` in that snapshot.

Send `kind = "EndTurn"` with the active actor ID and latest battle ID and revision through `SubmitSandboxSecondary`. Show the command using `endTurnLegality`. The player can end the turn after the regular Primary resolves or a rule makes it unavailable. Ending the turn consumes no item, belt charge or action slot. It forfeits the unused Secondary and Bonus Primary and advances the queue.

Format the UV Flash tooltip in the client as “Guaranteed Shadow Cancel Only. Does not apply Exposure.” Use the server preview to decide whether the current intent is eligible.

## Sandbox wire protocol

Stage 2B creates `ReplicatedStorage.Shared.BlackSabbathRemotes`. The existing tutorial remote folder and Build 1 payloads continue to serve the tutorial.

1. Invoke `StartSandbox` with fixture level 10 or 50, stage tag and QTE preference. A successful call returns the full battle snapshot.
2. Send the battle ID and the snapshot revision for Primary, Secondary and QTE preference changes. Include the acting fighter and any required target in the request. The server validates this against the player’s battle and current action slots.
3. A committed High-Risk Heavy spends its Stamina and slot once, then returns an active challenge. The client submits one input per check using battle ID, challenge ID and check index. The server validates ordering, bounds, cue answers and receipt time. For manual window display, compare the supplied timestamps with `workspace:GetServerTimeNow()`. During a challenge, `checkResults` mirrors `checks` by position and gives `Pending`, `Hit`, or `Miss`, including timed-out checks. Untimed checks have no timing cutoff. The client sends input only. The server grades the move and calculates damage, dodge, Resolve and proc results.
4. An Auto-Good preference uses untimed cues for this tagged attack. Ordinary Auto-Good remains at 1.00×. Only a landed Manual Perfect qualifies for the manual assist. Landed 3/3 grants +15 attack Resolve and eligibility for its hit rider. Dodged 3/3 grants zero attack Resolve. A partial or failed check incurs the single −1 timing adjustment. Exposure starts after the offensive interrupt resolves and lasts through the party’s next Primary.
5. Replace the displayed state with the newest snapshot from a response, the server event `SandboxSnapshotChanged`, or `GetSandboxSnapshot` when reconnecting. The server event covers autonomous changes such as manual check expiry. Ignore an older revision within the same battle. On a new battle ID, initialize the UI from that battle’s snapshot.

Asset manifest entries set to `rbxassetid://0` use local fallback visuals. The sandbox adds stage, Black Sabbath, companion and belt keys for Claude to wire in the HUD.

## Verification

From `Pixel-Bizarre-Adventure/`, run `rojo build default.project.json --output "$env:TEMP/PBA-Phase2.rbxlx"`, `lune run tests/smoke.luau`, `lune run tests/tutorial.luau`, `lune run tests/phase2_contracts.luau`, and `lune run tests/phase2_sandbox.luau`. Run strict Luau analysis on shared modules and tests.

Verified with Rojo 7.7.1, Lune 0.11.1, and luau-analyze 0.748. The combined Rojo build, original smoke test, seven tutorial scenarios, Phase 2 contract smoke, sandbox parity suite, and strict analysis of the shared sandbox code and tests passed. The server bootstrap and all 11 client sources also compiled.

A local Studio build with PR #10 booted into the real Night sandbox. The HUD showed 82/82 player HP with its mock badge hidden and rendered the result of three expired manual checks. Separate client calls verified the server's timeout events, Coffee Gum, End Turn, UV cancel without Exposure, and a landed 3/3 Untimed Cue for +15 Resolve. The Studio output reported asset-load warnings for placeholder content.

### Fixture tuning

The sandbox uses fixed Speed values (12, 10, 8), a 25% low-HP threshold, a 2× Finisher and a 0.45-second base manual timing window with Focus scaling. These are playtest parameters. Untimed checks ask for the indicated input. Companion tactics record the current selection while both party fighters use manually selected actions. The current encounter has no Bonus Primary source. The mock's extra action on a perfect check is excluded from the server.
