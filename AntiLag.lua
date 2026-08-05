local shared = odh_shared_plugins
local section = shared.AddSection("Anti Lag")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local shiftLockFixEnabled = false
local freezeFixEnabled = false

local shiftLockConn = nil
local freezeConn = nil
local charAddedConn = nil

local originalWalkSpeed = 16
local lastMouseBehavior = nil

local function getCharacter()
    local c = LocalPlayer.Character
    if not c then return nil, nil end
    local h = c:FindFirstChildOfClass("Humanoid")
    local r = c:FindFirstChild("HumanoidRootPart")
    return h, r
end

local function setupShiftLockFix()
    if shiftLockConn then
        shiftLockConn:Disconnect()
        shiftLockConn = nil
    end
    if not shiftLockFixEnabled then return end
    
    lastMouseBehavior = UserInputService.MouseBehavior
    
    shiftLockConn = RunService.Heartbeat:Connect(function()
        if not shiftLockFixEnabled then return end
        local current = UserInputService.MouseBehavior
        if current ~= lastMouseBehavior then
            lastMouseBehavior = current
            local h, r = getCharacter()
            if h and r then
                if h.WalkSpeed ~= originalWalkSpeed and h.WalkSpeed ~= 0 then
                    h.WalkSpeed = originalWalkSpeed
                end
            end
        end
    end)
end

local function setupFreezeFix()
    if freezeConn then
        freezeConn:Disconnect()
        freezeConn = nil
    end
    if not freezeFixEnabled then return end
    
    local lastTime = tick()
    
    freezeConn = RunService.RenderStepped:Connect(function()
        if not freezeFixEnabled then return end
        
        local currentTime = tick()
        local delta = currentTime - lastTime
        
        if delta > 0.1 then
            local h, r = getCharacter()
            if h and r then
                local state = h:GetState()
                if state == Enum.HumanoidStateType.Freefall then
                    h:ChangeState(Enum.HumanoidStateType.Landed)
                end
            end
        end
        
        lastTime = currentTime
    end)
end

local function onCharacterAdded()
    if shiftLockFixEnabled then setupShiftLockFix() end
    if freezeFixEnabled then setupFreezeFix() end
end

local function cleanup()
    if shiftLockConn then
        shiftLockConn:Disconnect()
        shiftLockConn = nil
    end
    if freezeConn then
        freezeConn:Disconnect()
        freezeConn = nil
    end
    if charAddedConn then
        charAddedConn:Disconnect()
        charAddedConn = nil
    end
    local h = getCharacter()
    if h then h.WalkSpeed = originalWalkSpeed end
end

charAddedConn = LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
if LocalPlayer.Character then onCharacterAdded() end

section:AddParagraph("Anti Lag", "Optimized for Mobile/Tablet.\nFix shiftlock stutter and freeze issues.\ncredit @erixniex")

section:AddToggle("Fix ShiftLock Stutter", function(enabled)
    shiftLockFixEnabled = enabled
    if enabled then
        setupShiftLockFix()
        shared.Notify("ShiftLock fix enabled", 2)
    else
        if shiftLockConn then
            shiftLockConn:Disconnect()
            shiftLockConn = nil
        end
        shared.Notify("ShiftLock fix disabled", 2)
    end
end)

section:AddToggle("Barely Lagging", function(enabled)
    freezeFixEnabled = enabled
    if enabled then
        setupFreezeFix()
        shared.Notify("Anti-freeze enabled", 2)
    else
        if freezeConn then
            freezeConn:Disconnect()
            freezeConn = nil
        end
        shared.Notify("Anti-freeze disabled", 2)
    end
end)

LocalPlayer.CharacterRemoving:Connect(function()
    local h = getCharacter()
    if h then h.WalkSpeed = originalWalkSpeed end
end)

return {
    shiftlock = function() return shiftLockFixEnabled end,
    freeze = function() return freezeFixEnabled end
}
