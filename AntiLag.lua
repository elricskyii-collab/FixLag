local shared = odh_shared_plugins
local section = shared.AddSection("Anti Lag")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local antiLagEnabled = false
local shiftLockFixEnabled = true
local movementFixEnabled = true
local freezeFixEnabled = true

local shiftLockConn = nil
local movementConn = nil
local freezeConn = nil
local charAddedConn = nil

local originalWalkSpeed = 16
local lastMouseBehavior = nil
local frameStutterCount = 0
local lastFrameTime = 0

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
    if not antiLagEnabled or not shiftLockFixEnabled then return end
    
    lastMouseBehavior = UserInputService.MouseBehavior
    
    shiftLockConn = RunService.Heartbeat:Connect(function()
        if not antiLagEnabled or not shiftLockFixEnabled then return end
        local current = UserInputService.MouseBehavior
        if current ~= lastMouseBehavior then
            lastMouseBehavior = current
            local h, r = getCharacter()
            if h and r then
                if h.WalkSpeed ~= originalWalkSpeed and h.WalkSpeed ~= 0 then
                    h.WalkSpeed = originalWalkSpeed
                end
                local vel = r.AssemblyLinearVelocity
                if vel.Magnitude < 200 then
                    r.AssemblyLinearVelocity = vel
                end
            end
        end
    end)
end

local function setupMovementSmoothing()
    if movementConn then
        if typeof(movementConn) == "table" then
            for _, conn in ipairs(movementConn) do
                if typeof(conn) == "RBXScriptConnection" then conn:Disconnect() end
            end
        elseif typeof(movementConn) == "RBXScriptConnection" then
            movementConn:Disconnect()
        end
        movementConn = nil
    end
    
    if not antiLagEnabled or not movementFixEnabled then return end
    
    local jumpPressed = false
    
    local moveTask = RunService.Heartbeat:Connect(function(delta)
        if not antiLagEnabled or not movementFixEnabled then return end
        local h, r = getCharacter()
        if not h or not r then return end
        
        local moveVector = UserInputService:GetMoveVector()
        local isMoving = moveVector.Magnitude > 0.1
        
        if isMoving then
            local cam = workspace.CurrentCamera
            if cam then
                local right = cam.CFrame.RightVector
                local look = cam.CFrame.LookVector
                
                local worldMove = (right * moveVector.X) + (look * moveVector.Y)
                worldMove = Vector3.new(worldMove.X, 0, worldMove.Z)
                
                if worldMove.Magnitude > 0.01 then
                    worldMove = worldMove.Unit
                    
                    local currentVel = r.AssemblyLinearVelocity
                    local targetVel = worldMove * h.WalkSpeed
                    local smoothFactor = 0.4
                    
                    local newVel = currentVel:Lerp(
                        Vector3.new(targetVel.X, currentVel.Y, targetVel.Z),
                        smoothFactor
                    )
                    
                    r.AssemblyLinearVelocity = newVel
                    h.MoveDirection = worldMove
                end
            end
        else
            local currentVel = r.AssemblyLinearVelocity
            local decelFactor = 0.9
            
            r.AssemblyLinearVelocity = Vector3.new(
                currentVel.X * decelFactor,
                currentVel.Y,
                currentVel.Z * decelFactor
            )
            
            if currentVel.Magnitude < 0.3 then
                h.MoveDirection = Vector3.new()
            end
        end
    end)
    
    local jumpTask = RunService.RenderStepped:Connect(function()
        if not antiLagEnabled or not movementFixEnabled then return end
        local h, r = getCharacter()
        if not h then return end
        
        if jumpPressed then
            local state = h:GetState()
            if state == Enum.HumanoidStateType.Landed or 
               state == Enum.HumanoidStateType.Running or
               state == Enum.HumanoidStateType.GettingUp then
                h:ChangeState(Enum.HumanoidStateType.Jumping)
                jumpPressed = false
            end
        end
        
        local state = h:GetState()
        if state == Enum.HumanoidStateType.Jumping or state == Enum.HumanoidStateType.Freefall then
            h.AirControl = 0.3
        else
            h.AirControl = 0.2
        end
    end)
    
    local jumpHook = UserInputService.JumpRequest:Connect(function()
        if antiLagEnabled and movementFixEnabled then
            jumpPressed = true
        end
    end)
    
    movementConn = {moveTask, jumpTask, jumpHook}
end

local function setupFreezeFix()
    if freezeConn then
        freezeConn:Disconnect()
        freezeConn = nil
    end
    if not antiLagEnabled or not freezeFixEnabled then return end
    
    lastFrameTime = tick()
    frameStutterCount = 0
    
    freezeConn = RunService.RenderStepped:Connect(function()
        if not antiLagEnabled or not freezeFixEnabled then return end
        
        local currentTime = tick()
        local delta = currentTime - lastFrameTime
        
        if delta > 0.05 then
            frameStutterCount = frameStutterCount + 1
            if frameStutterCount > 3 then
                local h, r = getCharacter()
                if h and r then
                    -- Force physics refresh on stutter
                    local vel = r.AssemblyLinearVelocity
                    r.AssemblyLinearVelocity = vel
                    
                    -- Reset humanoid state if frozen
                    if h:GetState() == Enum.HumanoidStateType.Freefall then
                        h:ChangeState(Enum.HumanoidStateType.Landed)
                    end
                end
                frameStutterCount = 0
            end
        else
            frameStutterCount = 0
        end
        
        -- Force smooth frame timing
        if delta > 0.033 then
            local h, r = getCharacter()
            if h and r then
                local moveVector = UserInputService:GetMoveVector()
                if moveVector.Magnitude < 0.1 then
                    local vel = r.AssemblyLinearVelocity
                    if vel.Magnitude > 1 then
                        r.AssemblyLinearVelocity = vel * 0.95
                    end
                end
            end
        end
        
        lastFrameTime = currentTime
    end)
end

local function onCharacterAdded()
    if antiLagEnabled then
        if shiftLockFixEnabled then setupShiftLockFix() end
        if movementFixEnabled then setupMovementSmoothing() end
        if freezeFixEnabled then setupFreezeFix() end
    end
end

local function cleanup()
    if shiftLockConn then
        shiftLockConn:Disconnect()
        shiftLockConn = nil
    end
    if movementConn then
        if typeof(movementConn) == "table" then
            for _, conn in ipairs(movementConn) do
                if typeof(conn) == "RBXScriptConnection" then conn:Disconnect() end
            end
        elseif typeof(movementConn) == "RBXScriptConnection" then
            movementConn:Disconnect()
        end
        movementConn = nil
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

section:AddParagraph("Anti Lag", "Zero stutter shiftlock, buttery smooth movement, and anti-freeze tech.\ncredit @erixniex")

section:AddToggle("Enable Anti Lag", function(enabled)
    antiLagEnabled = enabled
    if enabled then
        if shiftLockFixEnabled then setupShiftLockFix() end
        if movementFixEnabled then setupMovementSmoothing() end
        if freezeFixEnabled then setupFreezeFix() end
        shared.Notify("Anti Lag enabled", 2)
    else
        cleanup()
        charAddedConn = LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
        shared.Notify("Anti Lag disabled", 2)
    end
end)

section:AddToggle("Fix ShiftLock Stutter", function(enabled)
    shiftLockFixEnabled = enabled
    if enabled and antiLagEnabled then
        setupShiftLockFix()
    elseif shiftLockConn then
        shiftLockConn:Disconnect()
        shiftLockConn = nil
    end
end)

section:AddToggle("Fix Movement Stiffness", function(enabled)
    movementFixEnabled = enabled
    if enabled and antiLagEnabled then
        setupMovementSmoothing()
    elseif movementConn then
        if typeof(movementConn) == "table" then
            for _, conn in ipairs(movementConn) do
                if typeof(conn) == "RBXScriptConnection" then conn:Disconnect() end
            end
        elseif typeof(movementConn) == "RBXScriptConnection" then
            movementConn:Disconnect()
        end
        movementConn = nil
        local h = getCharacter()
        if h then h.WalkSpeed = originalWalkSpeed end
    end
end)

section:AddToggle("Barely Lagging", function(enabled)
    freezeFixEnabled = enabled
    if enabled and antiLagEnabled then
        setupFreezeFix()
    elseif freezeConn then
        freezeConn:Disconnect()
        freezeConn = nil
    end
end)

LocalPlayer.CharacterRemoving:Connect(function()
    local h = getCharacter()
    if h then h.WalkSpeed = originalWalkSpeed end
end)

return {
    enabled = function() return antiLagEnabled end,
    toggle = function(state)
        antiLagEnabled = state
        if state then
            if shiftLockFixEnabled then setupShiftLockFix() end
            if movementFixEnabled then setupMovementSmoothing() end
            if freezeFixEnabled then setupFreezeFix() end
        else
            cleanup()
        end
    end
}
