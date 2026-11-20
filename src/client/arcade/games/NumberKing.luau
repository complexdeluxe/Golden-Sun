local Chrome = require(script.Parent.Parent.ui.GameChrome)
local Codes = require(script.Parent.Parent.ui.CodesDialog)
local NumberKing = {}

local function integer(text)
    if not text:match("^%s*[+-]?%d+%s*$") then return nil end
    local n = tonumber(text)
    if n and math.abs(n) <= 9007199254740991 then return n end
end
local function grade(n, hard)
    if n == 1 then return hard and "X · The Chosen One" or "SS" end
    if n < 5 then return hard and "SSS · Titan of Titaninum" or "S" end
    if n < 15 then return hard and "SS · The Platinum Paladin" or "A" end
    if n < (hard and 40 or 35) then return hard and "S · Gilded-in-Gold Gladitor" or "B" end
    if n < 60 then return hard and "A · Savage in Sliver" or "C" end
    if n <= 100 then return hard and "B · Bronze Barbarian" or "D" end
    return hard and "[IRRELIVENT]" or "F"
end

function NumberKing.new(ctx)
    local session = {}
    local chrome, dialog
    function session:start()
        local phase, dev, hard = "mode", false, false
        local target, turn = 0, 1
        local rng = Random.new()
        local label, box, submit
        local function display(message)
            label.Text = message
            if dev and phase ~= "mode" then
                label.Text ..= string.format("\nDeveloper · Target %s · Guess %d", tostring(target), turn)
            end
        end
        local function chooseTarget(shift)
            target = rng:NextInteger(1, hard and 100000 or 100)
            phase = dev and "override" or "guess"
            submit.Text = dev and "Set target / Skip" or "Guess"
            box.PlaceholderText = dev and "Optional integer override" or "Whole number"
            local message = shift and "The number has shifted." or ("Find the number from 1 to " .. (hard and "100000." or "100."))
            display(message .. (dev and " Enter a target, or skip." or ""))
        end
        local function accept(value, codeOnly)
            if phase == "mode" then
                if value == "its me" then
                    dev = true
                    display("Developer mode enabled. Choose a mode.")
                elseif not codeOnly or value == "complex" then
                    hard = value == "complex"
                    chooseTarget(false)
                else return false end
            elseif phase == "override" and not codeOnly then
                target = integer(value) or target
                phase = "guess"
                submit.Text = "Guess"
                box.PlaceholderText = "Whole number"
                display("Make your guess.")
            elseif phase == "guess" and not codeOnly then
                local n = integer(value)
                if not n then display("Enter a whole number.") return true end
                if n == target then
                    phase = "won"
                    submit.Visible = false
                    box.Visible = false
                    local reward = not hard and turn < 35 and " · Hard key: complex" or ""
                    display(string.format("Correct in %d! Grade: %s%s", turn, grade(turn, hard), reward))
                else
                    local distance = math.abs(n - target)
                    local hint = n > target and "Go lower." or "Go higher."
                    if turn > 1 then
                        local near = hard and rng:NextInteger(900, 3000) or 15
                        hint = (distance <= (hard and 50 or 5) and "Hot! " or distance <= near and "Warm. " or "Cold. ") .. hint
                    end
                    turn += 1
                    if hard and turn <= 80 and turn % 20 == 0 then chooseTarget(true)
                    else
                        if hard and turn < 80 then hint ..= string.format(" Shift in %d guesses.", 20 - turn % 20) end
                        display(hint)
                    end
                end
            else return false end
            return true
        end
        chrome = Chrome.new(ctx.root, {title="Number King", controls={"Enter a number and press Guess or Enter.", "Use Codes before choosing your mode."}, onCodes=function()
            if dialog and dialog:isOpen() then return end
            dialog = Codes.open(ctx.root, {title="Number King codes", prompt="Enter a mode code", onSubmit=function(value, d)
                if accept(value, true) then d:close()
                else d:setFeedback(phase == "mode" and "Unknown code." or "Codes apply at mode selection. Exit and restart to choose again.", true) end
            end})
        end})
        local function widget(class, name, y, height)
            local item = Instance.new(class)
            item.Name = name
            item.Position = UDim2.fromScale(0.07, y)
            item.Size = UDim2.fromScale(0.86, height)
            item.BackgroundColor3 = Color3.fromRGB(40, 44, 62)
            item.TextColor3 = Color3.new(1,1,1)
            item.Font = Enum.Font.GothamMedium
            item.TextWrapped = true
            item.TextSize = 18
            item.Parent = chrome.playArea
            return item
        end
        label = widget("TextLabel", "Prompt", 0.05, 0.35)
        box = widget("TextBox", "Entry", 0.46, 0.17)
        box.Text = ""
        box.PlaceholderText = "Mode choice (optional)"
        submit = widget("TextButton", "Submit", 0.69, 0.17)
        submit.Text = "Choose mode"
        display("Easy or hard? Leave blank for easy, or enter a mode key.")
        local function send()
            if not ctx.isActive() or Codes.isAnyOpen() then return end
            local value = box.Text
            box.Text = ""
            accept(value, false)
        end
        submit.Activated:Connect(send)
        box.FocusLost:Connect(function(enter) if enter then send() end end)
    end
    function session:destroy()
        if dialog then dialog:close() end
        if chrome then chrome:destroy() end
    end
    return session
end
return NumberKing
