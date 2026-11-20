# Golden-Sun
# X

# Golden Sun: connection test only

No game concept is selected. This setup syncs one harmless server print script under ServerScriptService/GoldenSunSyncTest. Existing unknown instances are preserved. It does not manage Workspace, animation assets, lighting, UI, or other existing scripts.

The connection is limited to Light of the Golden Sun, place ID 78369564991843. Review the preview before accepting a sync; only the new test folder and script should be added.

Run your installed Rojo 7.7.1 executable with `serve default.project.json` from this directory. Keep it running. In this place's Rojo plugin, connect to localhost port 34872, review the preview, and accept the expected additions. Start a Studio playtest and check server Output for `[Golden Sun] Rojo connection test v1: server script is running.`

## Start on your computer

1. In GitHub Desktop, select Golden-Sun, click Fetch origin, then Pull origin if offered.
2. Choose Repository > Show in Explorer. In Explorer's address bar, type `powershell` and press Enter.
3. Run `rojo serve default.project.json`. If PowerShell cannot find rojo, use `& "C:\path\to\rojo.exe" serve default.project.json`, replacing the executable path with your installed copy.
4. Leave that PowerShell window open. In Studio, open Light of the Golden Sun, then Plugins > Rojo and connect to localhost port 34872.
5. Review the sync preview. Only ServerScriptService/GoldenSunSyncTest and its ConnectionTest script should be added. Accept those additions, start a playtest, and check server Output for the v1 message above.

Each developer runs their own local server only when syncing their files. To view or play a shared Team Create place, you do not need to run Rojo. Agree who owns syncing before connecting to the same shared place: an older local copy can overwrite another person's synced script. For simultaneous development, use separate branches and separate test places; this configuration currently permits only the shared place ID above.

Pull changes before starting work. Commit and push your edits so the other developer can pull them. GitHub exchanges files; Rojo applies your local files to Studio. Keep edits to Rojo-managed scripts in the repository, since Studio edits do not automatically write back to these files.

After the first sync works, change the local message to v2 and confirm Studio source updates, then restart the test to check the new output. Save/publish only when explicitly requested; setup has not published the experience.
