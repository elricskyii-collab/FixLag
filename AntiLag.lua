local shared = odh_shared_plugins
local section = shared.AddSection("Anti Lag")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local LocalPlayer = Players.LocalPlayer

-- State
local shiftLockFixEnabled = false
local freezeFixEnabled = false
local inputLagFixEnabled = false
local networkSmoothEnabled = false

local connections = {}
local networkHistory = {}
local originalWalkSpeed = 16
local lastMouseBehavior = nil

local function getCharacter()
    local c = LocalPlayer.Character
    if not c then return nil, nil end
    return c:FindFirstChildOfClass("Humanoid"), c:FindFirstChild("HumanoidRootPart")
end

local function safeDisconnect(name)
    if connections[name] then
        connections[name]:Disconnect()
        connections[name] = nil
    end
end

local function cleanupAll()
    for name in pairs(connections) do safeDisconnect(name) end
    networkHistory = {}
    local h = getCharacter()
    if h then h.WalkSpeed = originalWalkSpeed end
    ContextActionService:UnbindAction("AntiLagMoveOverride")
end

-- 1. SHIFTLOCK STUTTER FIX
local function setupShiftLockFix()
    safeDisconnect("ShiftLock")
    if not shiftLockFixEnabled then return end

    local h = getCharacter()
    if h then originalWalkSpeed = h.WalkSpeed end
    lastMouseBehavior = UserInputService.MouseBehavior

    connections.ShiftLock = RunService.Heartbeat:Connect(function()
        if not shiftLockFixEnabled then return end
        local current = UserInputService.MouseBehavior
        if current ~= lastMouseBehavior then
            lastMouseBehavior = current
            local h = getCharacter()
            if h and h.WalkSpeed ~= 0 and h.WalkSpeed ~= originalWalkSpeed then
                h.WalkSpeed = originalWalkSpeed
            end
        end
    end)
end

-- 2. FREEZE / STUTTER PROTECTION
local function setupFreezeFix()
    safeDisconnect("Freeze")
    if not freezeFixEnabled then return end

    local freezeCount = 0
    local lastTime = os.clock()

    connections.Freeze = RunService.Heartbeat:Connect(function(dt)
        if not freezeFixEnabled then return end

        if dt > 0.08 then -- big frame spike
            freezeCount += 1
            if freezeCount >= 2 then
                local h, r = getCharacter()
                if h and r then
                    if h:GetState() == Enum.HumanoidStateType.Freefall then
                        h:ChangeState(Enum.HumanoidStateType.Landed)
                    end
                    if r.AssemblyLinearVelocity.Magnitude > 60 then
                        r.AssemblyLinearVelocity *= 0.85 -- smooth damp instead of snap
                    end
                end
                freezeCount = 0
            end
        else
            freezeCount = math.max(0, freezeCount - 1)
        end
    end)
end

-- 3. INPUT LAG REDUCTION
local function handleMove(actionName, inputState, inputObject)
    if not inputLagFixEnabled then return Enum.ContextActionResult.Pass end
    local h = getCharacter()
    if not h then return Enum.ContextActionResult.Pass end

    local moveVector = Vector3.new(0,0,0)
    if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveVector += Vector3.new(0,0,-1) end
    if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveVector += Vector3.new(0,0,1) end
    if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveVector += Vector3.new(-1,0,0) end
    if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveVector += Vector3.new(1,0,0) end

    if moveVector.Magnitude > 0 then
        local cam = workspace.CurrentCamera
        if cam then
            local worldMove = (cam.CFrame.RightVector * moveVector.X) + (cam.CFrame.LookVector * moveVector.Z)
            h.MoveDirection = Vector3.new(worldMove.X, 0, worldMove.Z).Unit
        end
    end

    return Enum.ContextActionResult.Pass
end

local function setupInputLagFix()
    safeDisconnect("InputLag")
    ContextActionService:UnbindAction("AntiLagMoveOverride")
    if not inputLagFixEnabled then return end

    ContextActionService:BindAction("AntiLagMoveOverride", handleMove, false,
        Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D)
end

-- 4. NETWORK SMOOTHING
local function setupNetworkSmooth()
    safeDisconnect("Network")
    networkHistory = {}
    if not networkSmoothEnabled then return end

    connections.Network = RunService.Heartbeat:Connect(function()
        if not networkSmoothEnabled then return end

        local ping = LocalPlayer:GetNetworkPing()
        table.insert(networkHistory, ping)
        if #networkHistory > 15 then table.remove(networkHistory, 1) end

        local avgPing = 0
        for _, p in ipairs(networkHistory) do avgPing += p end
        avgPing /= #networkHistory

        if avgPing > 0.25 then -- 250ms+
            local _, r = getCharacter()
            if r and r.AssemblyLinearVelocity.Magnitude > 8 then
                r.AssemblyLinearVelocity = r.AssemblyLinearVelocity:Lerp(Vector3.zero, 0.02)
            end
        end
    end)
end

-- Character handling
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(0.5) -- let character load
    if shiftLockFixEnabled then setupShiftLockFix() end
    if freezeFixEnabled then setupFreezeFix() end
    if inputLagFixEnabled then setupInputLagFix() end
    if networkSmoothEnabled then setupNetworkSmooth() end
end)

LocalPlayer.CharacterRemoving:Connect(function()
    local h = getCharacter()
    if h then h.WalkSpeed = originalWalkSpeed end
end)

-- UI
section:AddParagraph("Anti Lag", "Credit @erixniex")

section:AddToggle("Fix ShiftLock Stutter", function(enabled)
    shiftLockFixEnabled = enabled
    setupShiftLockFix()
    shared.Notify(enabled and "ShiftLock fix enabled" or "ShiftLock fix disabled", 2)
end)

section:AddToggle("Anti Freeze", function(enabled)
    freezeFixEnabled = enabled
    setupFreezeFix()
    shared.Notify(enabled and "Anti-freeze enabled" or "Anti-freeze disabled", 2)
end)

section:AddToggle("Fix Input Lag", function(enabled)
    inputLagFixEnabled = enabled
    setupInputLagFix()
    shared.Notify(enabled and "Input lag fix enabled" or "Input lag fix disabled", 2)
end)

section:AddToggle("Network Smoothing", function(enabled)
    networkSmoothEnabled = enabled
    setupNetworkSmooth()
    shared.Notify(enabled and "Network smoothing enabled" or "Network smoothing disabled", 2)
end)

return {
    shiftlock = function() return shiftLockFixEnabled end,
    freeze = function() return freezeFixEnabled end,
    inputlag = function() return inputLagFixEnabled end,
    network = function() return networkSmoothEnabled end
}
