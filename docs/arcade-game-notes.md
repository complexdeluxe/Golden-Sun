# Arcade game notes: selection UI, Dark Moon, Take Flight!

Owner: Claude with Complex. Branch: `claude/arcade-games`. Everything is 2D (ScreenGui only). No world content, camera, character or server code is touched.

The originals (`APCreateTask.py`, `TakeFlight.py`) are unchanged. All adaptation lives in the files below.

| Path | Purpose |
| --- | --- |
| `src/client/arcade/ui/ArcadeMenu.luau` | Selection screen: title, game cards, Play buttons, loading/error overlay, debounce |
| `src/client/arcade/ui/GameChrome.luau` | In-game top bar: title, Controls panel, Codes button, Menu (exit) button |
| `src/client/arcade/ui/CodesDialog.luau` | Shared modal code entry: confirm/cancel, Enter submits, inline validation feedback |
| `src/client/arcade/ui/PlayField.luau` | Aspect-locked 400×400 logical canvas, cmu colour table, helpers |
| `src/client/arcade/games/DarkMoon.luau` | Dark Moon port (`Sim` + session adapter) |
| `src/client/arcade/games/TakeFlight.luau` | Take Flight! port (`Sim` + session adapter) |

## Interface I need from Codex (relay)

`docs/arcade-contract.md` did not exist when this work started, so the adapters assume the smallest interface below. Please confirm it or send changes through Complex.

```lua
-- Each game module returns a table:
Game.id, Game.displayName, Game.description  -- strings
Game.controls  -- { string }
Game.devices   -- { string }
Game.new(context) -> session
session:start()     -- builds UI under context.container; may error (runtime should pcall)
session:destroy()   -- idempotent, safe after a partial or failed start

context = {
  container = <GuiObject>,               -- full-screen Frame owned by the runtime; the game only parents inside it
  requestExit = function(reason: string?) -- game asks the launcher to end the session (Menu button / result screen)
}
```

The adapters own and clean up their own connections, the RenderStepped loop, dialogs and UI. They do not need a scope or cleanup object from the context. If the contract provides one, it can be added without changing behaviour.

The launcher (Codex) owns:
- creating the container
- calling `start` inside `pcall`
- on error: calling `destroy`, removing the container and calling `menu:setState("error", msg)`
- on `requestExit`: calling `destroy`, removing the container and calling `menu:setState("menu")`

Adapters never launch each other.

Menu API for the runtime:

```lua
local menu = ArcadeMenu.new(screenGuiOrFrame, { {id, displayName, description, controls, devices}, ... }, {
  onPlay = function(id) ... end, -- called once per click; errors are caught and shown as "error"
})
menu:setState("menu" | "loading" | "playing" | "stopping" | "error", message?)
menu:getState() ; menu:destroy()
```

A Play click is ignored unless the state is `menu`. The menu switches to `loading` before calling `onPlay`, so repeated clicks cannot launch overlapping sessions. `CodesDialog` is generic, and Number King can use it for `its me` / `complex` if Codex wants that.

Rojo mapping needed (Codex owns `default.project.json`): `src/client/arcade` must sync as a client-side folder. `ui/` and `games/` must be siblings inside it. The games locate `ui/` through `script.Parent.Parent.ui`.

## Intake: Dark Moon (`APCreateTask.py`)

- **Format:** Python with `cmu_graphics`. Ends with `cmu_graphics.run()`. No storage or network.
- **Timing:** cmu's default 30 steps per second. The source counts 30 frames per second; score goes up 1 every 5 frames.
- **Input:**
  - A/D move (speed = stage + 5 pixels per step)
  - Space jumps: −10 px and a 70 px target. There is no ground check, so mid-air jumps work. This is preserved.
  - S doubles gravity
  - W dashes ±85 px in the direction of travel, with i-frames and 6 afterimages
- **Progression:**
  - Stages 2–5 arrive every 40 s (40/80/120/160 s).
  - Stages 6–10 arrive every 50 s (200/250/300/350/400 s).
  - The endgame starts at stage 8: +5 i-frames and gradient afterimages.
- **Completion (the mismatch the directive mentioned):** stage 10 arrives at 6:40, but nothing happens there. Victory starts when minutes = 7 and seconds > 19 (7:20). The screen then fades to black, "Victory is Yours" replaces the score, obstacles clear, and the source calls `death()` to run the ending fade.
  - **The port treats this as a success.** `Sim:outcome()` returns `"victory"`, no death sound is played, and the result screen says "Victory is Yours". A full run lasts about 7:33 including both fades.
  - Complex should confirm this is the intended feel.
- **Invincibility code:**
  - Legacy route (preserved): in the first 5 s, hold `|` and `~`. Roblox reports these as the BackSlash and Backquote keys, so they are accepted with or without Shift. A prompt titled `%*(@!&%)(!*&!@)(*&SH{{}~F~HA` then asks for `The Author of the Continental Page` (exact and case-sensitive). The correct phrase sets i-frames to 869251968158709. Any other answer, or cancelling, shows "The End You Seek..." and kills the player, exactly as the source's `except` branch does.
  - New route: the Codes button on the pre-run setup screen, or in the run's first 5 s. A wrong entry only shows "Unknown code"; it is harmless.
  - Either route shows "Invicibility was used for this Completion" (original spelling) during the run and on the result screen.
- **Audio:** the source plays local MP3s (one music track and six death sounds). Roblox needs authorized asset IDs, so audio is **disabled**. `DarkMoon.AUDIO.music` and `.deathSounds` accept `rbxassetid://` strings later. No assets were uploaded.
- **Visual adaptations:**
  - `orbitron` uses Roblox `SciFi`.
  - cmu gradients use `UIGradient`.
  - Collision uses rectangle overlap, which is exact for this game because every shape is a rectangle.

## Intake: Take Flight! (`TakeFlight.py`, Alpha 2.1)

- **Format:** Python with `cmu_graphics`. Ends with `cmu_graphics.run()`. No storage or network. Source `print`s become an on-screen event line.
- **Timing:** 30 steps per second. Score goes up by `acceleration` every 5 steps, about 6 per second when level.
- **Input:**
  - W/S climb or dive with exponential acceleration and tilt; holding both wobbles the plane.
  - A/D fly backward or forward, with zoned speed.
  - A mouse click fires; touch also fires.
  - The bottom tab opens the stat window, which pauses the game. The + and − buttons spend or refund points.
- **Stats:** the source tables are copied verbatim. +1 is allowed only if points > 0 and the stat is ≤ 4. −1 is allowed if the stat is ≥ 2 and refunds a point.
- **Skill points:**
  - The requirement ladder is 200 → 400 → 750 → 1000 → 2000.
  - After 2000, a point is granted on **every step** while score > 2000. The source comments say this is on purpose, so it is preserved.
- **Hazards (source order, each gives 15 i-frames):**
  - Cloud 1: −20
  - Cloud 2: heals 10, with a 1/9 chance of +50
  - Cloud 3: −15, then Mobility ±1
  - Cloud 4: −50 and Durability −1
  - Tree 1: −30 and a 1/3 chance of Power −1
  - Tree 2: −10 twice and the goblin takes 100 score. `randrange(1,2)` is always 1, so this always happens.
  - Tree 3: −45 and a 1/3 chance of Precision −1
  - Leaving the screen: −40
  - Crits are 1/9 where the source has them. Health reaching 0 ends the flight, which replaces `app.stop()`.
- **Codes:**
  - New route: the Codes button. Enter `complexscore` → "Whats the New Score?", or `complexdura` → "Un-Cap Dura?".
  - Legacy routes: hold Shift+S+9+0 (`S`, `(`, `)`) or Shift+D+=+T (`D`, `+`, `T`). Each chord accepts only its own code. An unrecognised answer silently closes the prompt, as in the source.
  - The game pauses while a prompt is open, matching the blocking `getTextInput`.
  - Validation: the source's `int()` would crash on bad input. The port accepts whole numbers only, optionally with a sign or `_` separators. Score is limited to ±1,000,000,000,000 and durability to 1–1,000,000. Invalid input shows feedback and keeps the prompt open.
  - **Beyond-cap durability:** tiers 1–6 use the source table; tier 6 is 9999 HP and 999 regen, previously reachable only through the code. Above 6, the port extends tier 6 with +1000 max HP per extra point, regen 999 and reduction 0. The value is not clamped and there is no table crash.
  - Source rules still apply to a beyond-cap value: + is refused (stat > 4), and − refunds a point per click.
- **Behaviour kept from the source:**
  - An idle plane drifts left off-screen and goes down in about 8 s.
  - Any bullet passing x 405 clears all bullets on screen.
  - The bullet counter can drift towards the 600 limit.
  - Clouds respawn using a cumulative x offset.
- **Visual adaptations:**
  - Polygons become simplified frames in the same layout and palette: the mountains are rotated squares, the plane is a three-bar dart, clouds are clipped half-ellipses, and trees are a trunk and crown.
  - The plane's collision box is its polygon bounds (50×30, ignoring rotation). Clouds and trees use their group bounds. This is slightly more generous than cmu's polygon test.
  - Clicking the stat tab no longer also fires a bullet. The original click handler did both.
- **Fixed source bug:** the hazard checks used `item.opacity`, a leftover loop variable from another item. The port checks the hazard's own opacity and on-map state.

## Device support (honest)

- **Menu:** mouse, keyboard and touch. Buttons are at least 44 px and the card list scrolls, so it works in phone portrait. Not yet checked on a real phone.
- **Dark Moon:** keyboard only. There are no touch controls.
- **Take Flight!:** keyboard to fly; touch can fire but not steer.

## Tests run (observed evidence)

All tests ran in Roblox Studio on Complex's machine, in **Edit mode, via the Studio MCP, without Rojo**. Nothing was synced into the shared place. The temporary test UI was mounted under CoreGui, which is not saved with the place, and was removed afterwards. A scan of the place found no leftovers.

**Dark Moon `Sim`: 30/30 pass**
- With invincibility, stages are reached at 40/80/120/160/200/250/300/350/400 s. Victory happens at 7:26 (game time), the outcome is `victory`, the assisted marker is set, and no death sound plays. The full run lasts 453 s.
- An idle player dies with outcome `death` and a death-sound request.
- No obstacles appear in the first 5 s, and there are never more than 6.
- Checked: move +5, dash +85 with i-frames and 6 afterimages, jump −10 with a −70 target, landing on the floor, S gravity ×2 and its reset, leaving the world kills, roof clamp.
- Legacy route: the chord prompts within 5 s and is ignored after. The correct phrase gives invincibility. A wrong phrase or cancel kills with the message. The phrase is case-sensitive.
- A fresh `Sim` starts from a clean state.

**Take Flight! `Sim`: 46/50 on the first run, then the 4 failing cases passed after correcting the tests (7/7)**
- The failures came from test assumptions. An idle plane dies within 8 s, which the original also does. Random cloud-4 hits also lowered durability during one test. Both were rewritten to be deterministic.
- Checked:
  - starting stats and the 100/100 health readout
  - the clock and about 6 score per second
  - the requirement ladder and the intentional point-per-step above 2000
  - spending and refunding stat points, including the caps
  - `parseInteger` accepts and rejects the right inputs, including inf, nan, `3.5`, `1e5` and out-of-range values
  - the score code feeding the normal skill-point flow
  - durability 6 gives 9999 HP
  - durability 1000 gives 1,003,999 HP, stays unclamped, and runs 300 steps without error
  - each hazard's damage, healing, stat loss and goblin theft
  - i-frames blocking a repeat hit
  - out-of-bounds damage of 40
  - health reaching 0 ends the flight
  - firing, the all-bullets clear and the 600-bullet limit
  - no firing and no time passing while the stat window is open
  - bullets damaging items
  - forward flight, climbing, and levelling off
  - a 5-minute simulated run with no errors in which all 7 items appeared

**Compilation:** all 6 modules compile in Studio's Luau.

**UI and lifecycle smoke test** (stand-in launcher in CoreGui, Edit mode):
- The menu shows 3 cards: Number King (stand-in card), Dark Moon and Take Flight! (screenshot checked).
- Dark Moon runs at the original pace (89 steps in 3 s). The screenshot shows the gradient, obstacles and the death fade.
- Take Flight! renders. Codes through the real dialog: the game pauses (no steps while the prompt is open), `abc` shows feedback, and `50` gives Durability 50 and 53,999 max HP. The stat window renders with the cyan durability marker.
- 12 alternating switches, 4 of them exiting with a Codes dialog open: 0 leaked sessions, 50 GUI descendants before and after, no dialog left open, ended sessions inert, double `destroy` safe.
- A forced startup failure (missing `ui` folder) makes `start` error, `destroy` afterwards is safe, the menu shows the error with Back to menu, and returns to `menu`.

**Not yet tested (needs integration or a human):**
- real keyboard play in a Play-mode session
- clicking Play twice quickly through the real button. This is only checked by reading the code.
- a full real-time 7:33 Dark Moon run
- phone portrait
- two-player isolation
- the Rojo build and mappings (Codex)
- fidelity review by Complex

## Efficiency notes

- 22:01: task received. 22:24: both ports and the UI were written and tested headlessly, about 23 minutes after reading the uploads.
- Human coordination so far: one folder-access approval and two computer-use approvals. There have been no interface revisions yet, because the contract is still pending.
- No model usage or cost figures are exposed to me.
