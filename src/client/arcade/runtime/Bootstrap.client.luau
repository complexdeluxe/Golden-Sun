local Players = game:GetService("Players")
local player = Players.LocalPlayer
local scripts = script.Parent.Parent
local entries = require(game.ReplicatedStorage:WaitForChild("GoldenSunArcade"):WaitForChild("Registry"))
local menu = require(scripts.ui.Menu)
local gui = Instance.new("ScreenGui")
gui.Name = "GoldenSunArcade"
gui.ResetOnSpawn = false
gui.DisplayOrder = 10
gui.Parent = player:WaitForChild("PlayerGui")

local function frame(name, top)
    local f = Instance.new("Frame")
    f.Name = name
    f.Position = UDim2.fromOffset(0, top)
    f.Size = UDim2.new(1, 0, 1, -top)
    f.BackgroundColor3 = Color3.fromRGB(20, 20, 32)
    f.Parent = gui
    return f
end
local home = frame("Selection", 0)
local header = Instance.new("TextButton")
header.Size = UDim2.new(1, 0, 0, 44)
header.BackgroundColor3 = Color3.fromRGB(35, 38, 56)
header.TextColor3 = Color3.new(1, 1, 1)
header.TextSize = 18
header.TextWrapped = true
header.Visible = false
header.Parent = gui

local current, unmount, launch
local closed = false
local function showMenu(message)
    header.Visible = message ~= nil
    header.Text = message or ""
    local top = message and 44 or 0
    home.Position = UDim2.fromOffset(0, top)
    home.Size = UDim2.new(1, 0, 1, -top)
    home.Visible = true
    unmount = menu.mount(home, entries, launch)
end
local function safely(fn)
    local ok, err = pcall(fn)
    if not ok then warn(err) end
end
local function stop(run, message)
    if current ~= run or run.stopping then return end
    run.stopping = true
    if run.session then safely(function() run.session:destroy() end) end
    for i = #run.cleanups, 1, -1 do safely(run.cleanups[i]) end
    run.root:Destroy()
    current = nil
    if not closed then showMenu(message) end
end
launch = function(id)
    if closed or current then return end
    local entry
    for _, item in entries do
        if item.id == id then entry = item break end
    end
    if not entry then return end
    local run = {root = frame("Session", 44), cleanups = {}}
    current = run
    unmount()
    unmount = nil
    home.Visible = false
    header.Text = "‹  Back to arcade     |     " .. entry.displayName
    header.Visible = true
    local function active() return current == run and not run.stopping end
    local ctx = {root = run.root, isActive = active, requestExit = function() stop(run) end}
    function ctx.onCleanup(fn)
        if active() then table.insert(run.cleanups, fn) else safely(fn) end
    end
    local ok, err = pcall(function()
        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            local speed = humanoid.WalkSpeed
            local jumpProperty = humanoid.UseJumpPower and "JumpPower" or "JumpHeight"
            local jump = humanoid[jumpProperty]
            ctx.onCleanup(function()
                if humanoid.Parent then
                    if humanoid.WalkSpeed == 0 then humanoid.WalkSpeed = speed end
                    if humanoid[jumpProperty] == 0 then humanoid[jumpProperty] = jump end
                end
            end)
            humanoid.WalkSpeed = 0
            humanoid[jumpProperty] = 0
        end
        local adapter = require(assert(scripts.games:FindFirstChild(entry.adapterName), "Missing game module"))
        if not active() then return end
        run.session = adapter.new(ctx)
        if active() then run.session:start() else run.session:destroy() end
    end)
    if not ok then
        warn("[Golden Sun Arcade]", err)
        stop(run, entry.displayName .. " could not start. Choose a game to try again.")
    end
end
header.Activated:Connect(function() if current then stop(current) end end)
local respawn = player.CharacterAdded:Connect(function() if current then stop(current) end end)
script.Destroying:Connect(function()
    closed = true
    respawn:Disconnect()
    if current then stop(current) end
    if unmount then unmount() end
    gui:Destroy()
end)
showMenu()
