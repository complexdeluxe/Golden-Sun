# Arcade contract for Claude review

**Status: proposed v1.** Claude should confirm that the following signatures and paths work for selection UI and both action games, or name the smallest required change. Parallel integration starts after that reply. The only existing Rojo mapping is the connection-test script. The arcade mappings below describe the proposed implementation.

## Files and ownership

| Repository path | Proposed Studio location and owner |
| --- | --- |
| `src/shared/arcade/Registry.luau` | `ReplicatedStorage.GoldenSunArcade.Registry`. Codex owns the ordered registry. |
| `src/client/arcade/runtime/` | `StarterPlayer.StarterPlayerScripts.GoldenSunArcade.runtime`. Codex owns the bootstrap LocalScript, launcher and cleanup. Client modules resolve relative to their copied `PlayerScripts.GoldenSunArcade` folder. |
| `src/client/arcade/ui/Menu.luau` | `GoldenSunArcade.ui.Menu` beside the client runtime. Claude owns the menu and its UI helpers. |
| `src/client/arcade/games/{NumberKing,DarkMoon,TakeFlight}.luau` | `GoldenSunArcade.games` beside the client runtime. Codex owns NumberKing. Claude owns DarkMoon and TakeFlight. |
| `default.project.json`, `src/server/arcade/`, intake, contract and test results | Codex owns mappings, integration and evidence. No arcade server component is needed. |
| `docs/arcade-game-notes.md` | Claude records controls, fidelity decisions, limitations and observed tests for the two action games. |

## Menu and registry

`Registry` returns an ordered array of records. Each record has `id: string`, `displayName: string`, `description: string`, `controls: string`, `supportedDevices: {string}` and `adapterName: string`. The launcher resolves the adapter name under its sibling games folder and requires only the selected module inside its protected launch. A missing/broken port must leave the menu and other games usable.

| id | displayName | adapterName | Intended input |
| --- | --- | --- | --- |
| `number-king` | Number King | `NumberKing` | Keyboard or touch text entry |
| `dark-moon` | Dark Moon | `DarkMoon` | Keyboard |
| `take-flight` | Take Flight! | `TakeFlight` | Keyboard and mouse |

`Menu.mount(parent: Frame, entries, onPlay: (string) -> ()): () -> ()` renders cards and controls and returns an idempotent unmount function. The menu calls `onPlay(entry.id)` via button activation. The launcher owns screen visibility, transitions, error feedback and a persistent in-game Back action outside the adapter frame. The launcher can unmount and remount the menu. Menu mount is synchronous and any partial UI goes under the supplied parent. Attach button listeners only to owned UI or explicitly release other listeners on unmount.

## One session per player

`Adapter.new(ctx) -> session` is synchronous. Construct inert session data here. `session:start()` binds input, builds UI and starts gameplay without yielding. `session:destroy()` is synchronous and idempotent, including after partial startup. Game modules have no side effects at require time. State belongs to the session.

| Context field | Contract |
| --- | --- |
| `ctx.root: Frame` | Fresh game viewport under the local player's arcade ScreenGui. Parent all game UI, local sounds and other owned instances here. The launcher destroys it on exit. |
| `ctx.onCleanup(fn: () -> ())` | Register a synchronous cleanup immediately after acquiring a connection, loop, task, tween or binding. The launcher runs callbacks in reverse order, even after constructor/start/destroy errors. Late registration after stop invokes the cleanup immediately. |
| `ctx.isActive(): boolean` | True during this generation's loading/playing states. Check it after delayed work and before changing UI. |
| `ctx.requestExit(): ()` | Ask the launcher to return this session to the menu. Stale or repeated requests have no effect. |

```luau
local DarkMoon = {}
function DarkMoon.new(ctx)
    local session = {}
    function session:start()
        local elapsed = 0
        local step = game:GetService("RunService").Heartbeat:Connect(function(dt)
            if ctx.isActive() then
                elapsed += dt -- consume fixed 1/30-second simulation steps here
            end
        end)
        ctx.onCleanup(function() step:Disconnect() end)
    end
    function session:destroy()
        -- Runtime owns registered cleanup and ctx.root.
    end
    return session
end
return DarkMoon
```

The launcher accepts a valid ID only from `menu`, marks `loading` before requiring or constructing, and enters `playing` only if that generation still owns the screen. On exit, character respawn or failure, it marks `stopping`, invalidates the generation, calls destroy if constructed, drains all cleanup and destroys the owned frame. It restores the menu with a readable error on launch failure. On player departure it also tears down the launcher. Use a persistent local ScreenGui (`ResetOnSpawn = false`) and a single respawn handler. No game launches another game.

Launcher owns isolation from character movement while playing and restores any controls it suppressed on exit, failure or respawn. Adapters own their game inputs and local audio. Gate input while a text box is focused or a Codes/modal UI is open, including shots from the press that confirms a dialog. Clear held input when focus/modal changes. Games keep the default world, camera and other players untouched. Scores and codes are local to every player, with confirmation, cancel and visible validation supplied by each adapter.

**First review.** Reply with “agree v1” or a specific signature/path conflict. Once agreed, Claude builds Menu and DarkMoon first on `claude/arcade-games`, then TakeFlight. Codex builds the actual Number King adapter, launcher and mappings on `codex/arcade-runtime`. Bryce previews and owns the sole shared Studio sync.
