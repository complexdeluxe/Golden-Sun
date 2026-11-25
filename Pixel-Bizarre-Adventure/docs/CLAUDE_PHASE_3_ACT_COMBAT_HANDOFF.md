# Phase 3 Act combat contract review

The first live campaign slice runs from the Act Map through F1, F2 and D1 to recruitment. Reuse the compact combat HUD and ring QTE from Phase 2. The existing Creator, tutorial, Hub, map and Results screens come from PR #14. The campaign profile and Hub backend come from PR #15.

## Map to fight

1. Continue using `SubmitCampaignAction` with `kind = "StartNode"`, the current campaign session and revision, the selected node and its advertised play option. The server checks the node, unlock order and option, then returns `ActEncounter` with an `encounterId` and `battleId`.
2. Open the HUD against `ReplicatedStorage.Shared.ActBattleRemotes`. Subscribe to `ActBattleSnapshotChanged` and call `GetActBattleSnapshot({ battleId })`. The snapshot includes the encounter ID, stage tag and optional stage art, the current wave out of the total, and the actors, action options, intents, QTE prompt and belt. Use the campaign snapshot for the player's saved appearance.
3. Accept battle events and replies only for the current encounter and battle IDs. Keep the greatest battle revision for that battle. Campaign revisions belong to the profile session and are tracked separately. Once the campaign advances to Results, map or Hub, close the HUD and ignore late battle events. A fresh campaign snapshot can reopen an active battle in the same server session.
4. Render enemy names and moves from the server's actors, intentions and labels. Use `stageAssetKey` where available and the existing placeholder otherwise. Show the wave count for a multi-wave fight. Wave advances keep the same battle ID and increase its revision. Defeating an intermediate wave keeps the outcome `InProgress`.

## Fight inputs

| Function | Client request |
| --- | --- |
| `SubmitActBattlePrimary` | The battle ID and latest battle revision with actor, slot, move and optional target. Use the options on the active actor. The server closes the Secondary slot when it accepts a regular Primary and advances after the move resolves, unless an earned Bonus Primary is available. |
| `SubmitActBattleSecondary` | The battle ID and latest battle revision with a legal belt item, tactic, redirect, Skip Turn or Retreat action. Show Retreat from `retreatLegality`. Show belt stock and target legality from the battle snapshot. |
| `SubmitActBattleQteCheck` | The battle ID, challenge ID, check index and input. Manual uses `Confirm` and `workspace:GetServerTimeNow()` for the ring. Untimed Cue sends a direction. The server grades input, updates `checkResults`, and publishes unanswered timeouts. |
| `SetActBattleQteMode` | The battle ID and latest battle revision with the selected preference. Use the returned mode and each option's effective mode for its prompt. |

The server owns each player's active battle, action legality, time windows and result. A stale action can return the current snapshot for resync. Retransmitting a QTE input for a settled check leaves that check unchanged. Only equipped supplies appear with usable stock. The server accounts for stock spent across the entire encounter and enforces the existing per-fight caps.

## Fight to Results

- A terminal battle outcome is `Victory`, `Defeat` or `Retreated`. Show the campaign Results screen from `ActResults` once it arrives. An action reply can carry the new `campaignSnapshot`, and `CampaignSnapshotChanged` carries the same transition for asynchronous completions such as QTE expiry. If the battle finishes and the campaign still shows `ActEncounter`, the client can refresh with `GetCampaignSnapshot`. While settlement is pending, keep the fight controls disabled and show a saving or retry state.
- **Lost final reply.** For the owner's terminal battle ID in the same server session, every valid battle call returns the same final battle snapshot, even if it repeats a stale action or QTE input. Once Results are saved, those replies also include the saved `ActResults` campaign snapshot.
- **Slow or failed Results save.** The server attempts settlement immediately on completion. A subsequent `GetCampaignSnapshot({})` triggers a retry when the save backoff allows, with at most one attempt in flight per encounter. Show **SAVING RESULTS...**, refresh a few times, then have **RETRY** call that same route.
- **Rejoin on a new server.** Return to saved, unacknowledged `ActResults` if settlement committed. An interrupted Act 1 encounter without a saved result returns to the Act Map with saved progress and the node available to start again.
- Read the outcome, reward amounts and the next available recruitment option from the campaign snapshot. The server settles rewards and inventory once per encounter before advertising Results, including when a reply is lost. Duplicate submissions and refreshes must return the existing settlement. Defeat and retreat grant zero clear rewards and do not advance the node. Replays can award Yen and items with zero levels.
- The first D1 clear unlocks the existing recruit offer for that route. Recruitment stays an explicit campaign action and the offer remains available from Results or the Hub until accepted. MAP and HUB remain campaign navigation actions.

## Review before implementation

- Claude checks HUD entry and teardown, stage and wave display, ring timing, retained combat controls, recovery from stale replies and save failures, and Results routing. Review the contract before wiring the client.
- Codex implements the battle runtime and persistent settlement after contract sign-off. Play both Origin routes through F1, F2 and D1. Verify an intermediate wave, QTE timeout, defeat, retreat, lost reply, replay, recruitment and rejoin.
- Preserve each node's authored opponents and readable fight cues from the vault. The server tuning pass needs to reconcile the existing first-clear level preview with the vault's first Lv 1 clear granting points. Replays always preview zero levels.
