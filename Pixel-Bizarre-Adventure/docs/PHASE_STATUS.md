# Phase status

**Active phase** — Phase 2 (Contract Freeze), Black Sabbath intent and parity sandbox.

**Base** — Phase 1 integration merged via PR #7. Claude’s client playtest polish merged via PR #8. The real Roblox DataStore restart check remains open as a separate follow-up.

| Ticket | Scope | Status |
| --- | --- | --- |
| 2A | Sandbox data shapes, remote names, asset keys, and HUD review | Draft for Claude |
| 2B | Audited combat math and server sandbox | After contract merge |
| 2B client | Combat HUD v2 | After contract merge |

## Section 2 HUD review

| Surface | What the client can use |
| --- | --- |
| Action economy | Each actor has Primary, Secondary and Bonus Primary availability. Each Primary option gives its slot, Stamina cost, scaling tag, input mode, legality, and per-target preview. One shared bonus slot per actor per round gives no extra regeneration, Secondary, cooldown tick, or companion turn. |
| QTE | `qtePrompt` identifies the active challenge and available inputs. `HighRiskHeavy` exposes the 1.70× base and the four timing bands. `Dodged` and `FailedQTE_0of3` are separate log events. The preview gives the effective dodge and interrupt odds conditional on required execution. |
| Resolve and On Fire | Actor records expose current Resolve, gains this turn, Fire duration and Finisher readiness. Resolve caps at 100, gains cap at 25 per turn, and the low-HP +20 trigger is once per fight. Fire lasts two turns, pauses Resolve gains, and grants +15% damage, +15 percentage points Crit chance and +10% Speed until expiry or Finisher. |
| Party belt | Three shared charges, two direct heals, one Med-Kit. Show stock, legal targets, live capped gains and relevant intent IDs. UV Flash cancels an eligible windup and leaves Exposure reserved for offensive interrupts. |
| Companion | Resolve the companion ID against the actor list for HP, Stamina and Guard. Show available tactic, assist readiness and a redirect preview with current target, legal recipients and Guard status. |
| Status and intent | Show removable marks, Stun and Exposure. Exposure lists its target and the next eligible follow-up actor when known. Stage tag and sandbox step indicate Lighter Strike, Shadow Grab windup, landing, or Fade. |

## Sandbox wire protocol

Stage 2B will create `ReplicatedStorage.Shared.BlackSabbathRemotes`. The existing tutorial remote folder and Build 1 payloads continue to serve the tutorial.

1. Invoke `StartSandbox` with fixture level 10 or 50, stage tag and QTE preference. A successful call returns the full battle snapshot.
2. Send the battle ID and the snapshot revision for Primary, Secondary and QTE preference changes. Include the acting fighter and any required target in the request. The server validates this against the player’s battle and current action slots.
3. A committed High-Risk Heavy spends its Stamina and slot once, then returns an active challenge. The client submits one input per check using battle ID, challenge ID and check index. The server validates ordering, bounds, cue answers and receipt time. Manual windows use synchronized server time. Untimed checks have no timing cutoff. The client sends input only. The server grades the move and calculates damage, dodge, Resolve and proc results.
4. An Auto-Good preference uses untimed cues for this tagged attack. Ordinary Auto-Good remains at 1.00×. Only a landed Manual Perfect qualifies for the manual assist. Landed 3/3 grants +15 attack Resolve and eligibility for its hit rider. Dodged 3/3 grants zero attack Resolve. A partial or failed check incurs the single −1 timing adjustment. Exposure starts after the offensive interrupt resolves and lasts through the party’s next Primary.
5. Replace the displayed state with the newest snapshot from a response, the server event `SandboxSnapshotChanged`, or `GetSandboxSnapshot` when reconnecting. The server event covers autonomous changes such as manual check expiry. Ignore an older revision within the same battle. On a new battle ID, initialize the UI from that battle’s snapshot.

Asset manifest entries set to `rbxassetid://0` use local fallback visuals. The sandbox adds stage, Black Sabbath, companion and belt keys for Claude to wire in the HUD.

## Verification

From `Pixel-Bizarre-Adventure/`, run `rojo build default.project.json --output "$env:TEMP/PBA-Phase2-Contract.rbxlx"`, `lune run tests/smoke.luau`, `lune run tests/tutorial.luau`, and `lune run tests/phase2_contracts.luau`. Run strict Luau analysis on shared modules and tests.

Verified with Rojo 7.7.1, Lune 0.11.1, and luau-analyze 0.748. The Rojo build, original smoke test, seven tutorial scenarios, Phase 2 contract smoke test, and strict analysis all passed.

Claude checks this draft against Section 2 of the Phase 2 handoff. Bryce merges the reviewed contracts before client and server implementation branches start.
