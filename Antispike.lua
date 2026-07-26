local shared = odh_shared_plugins
if not shared then return end

-- ==============================================
-- 1. SERVICES + STATE (FIRST)
-- ==============================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local Stats = game:GetService("Stats")
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local Stepped = RunService.Stepped
local PreSimulation = RunService.PreSimulation
local RenderStepped = RunService.RenderStepped

local os_clock = os.clock
local math_clamp = math.clamp
local math_floor = math.floor
local table_create = table.create
local table_clear = table.clear
local table_insert = table.insert
local table_remove = table.remove
local task_defer = task.defer
local task_delay = task.delay
local task_wait = task.wait
local pcall = pcall
local gcinfo = gcinfo

-- CORE STATE
local cachedHumanoid = nil
local cachedRoot = nil
local runEnabled = false
local lastMoveMag = 0
local runConn = nil
local renderDist = 70
local visibleBulletsEnabled = false
local bulletParts = {}
local noFog = false
local noKnockback = false
local noPlayerAnims = false
local animConn = {}
local toolConns = {}

-- ANTI LAG STATE
local stopAutoGC = false
local autoRenderDist = false
local lockNetwork = false
local cleanIdleJunk = false
local cutUnusedStates = false
local cleanDeadLinks = false
local limitBackgroundWork = false
local blockLagOnHighPing = false
local reuseBulletParts = false
local removeLagOverTime = false

-- NEW FEATURES
local lightingOptLevel = 0
local lagOverTimeConn = nil
local lastMaintenance = 0
local DEFAULT_LIGHTING = {
    Brightness = 0.5, Contrast = 0.5, ExposureCompensation = 0,
    Saturation = 0, GlobalShadows = true, FogEnd = 500, FogStart = 0,
    OutdoorAmbient = Color3.new(0.5,0.5,0.5), Ambient = Color3.new(0.5,0.5,0.5),
    ColorShift_Bottom = Color3.new(0,0,0), ColorShift_Top = Color3.new(0,0,0)
}

local MAX_JOBS = 12
local MAX_FRAMES = 8
local jobQueue = table_create(MAX_JOBS)
local lagConns = table_create(48)
local frameTimes = table_create(MAX_FRAMES, 0.016)
local frameIdx = 1
local jobBudget = 0.0002
local spikeRecovery = 0
local busyUntil = 0
local lastGC = 0
local lastDebris = 0
local lastPrune = 0
local tracerPool = {}

-- ==============================================
-- 2. ALL FUNCTIONS (BEFORE UI — 100% NO NIL CALLS)
-- ==============================================
local function BusyFor(sec) busyUntil = math.max(busyUntil, os_clock() + sec) end
local function IsBusy() return os_clock() < busyUntil end

local function DisconnectAll(t)
    for i = #t, 1, -1 do local c = t[i] if c then pcall(function() c:Disconnect() end) end t[i] = nil end
end

local function QueueJob(fn) if #jobQueue < MAX_JOBS then table_insert(jobQueue, fn) end end

local function UpdateBudget()
    local avg = 0 local max = 0
    for i = 1, MAX_FRAMES do local f = frameTimes[i] avg += f if f > max then max = f end end
    avg /= MAX_FRAMES
    if max > 0.016 then jobBudget = 0 spikeRecovery = 6
    elseif max > 0.013 then jobBudget = 0.0001 spikeRecovery = 3
    elseif avg < 0.007 then jobBudget = 0.00035 spikeRecovery = 0
    else jobBudget = 0.0002 spikeRecovery = math.max(0, spikeRecovery - 1) end
end

local function RunJobs()
    if #jobQueue == 0 or IsBusy() or (limitBackgroundWork and spikeRecovery > 0) then return end
    local start = os_clock()
    while #jobQueue > 0 do
        if limitBackgroundWork and os_clock() - start > jobBudget then return end
        local fn = table_remove(jobQueue, 1) if fn then fn() end
    end
end

local function LockNetwork(enable)
    if not enable then pcall(function() LocalPlayer:SetNetworkOwnershipAuto(true) end) return end
    pcall(function() LocalPlayer:SetNetworkOwnershipAuto(false) end)
    local c = LocalPlayer.Character if not c then return end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") then pcall(function() p:SetNetworkOwner(LocalPlayer) end) end
    end
end

local function ApplyStateCull(h)
    if not h then return end
    for _, st in {
        Enum.HumanoidStateType.Ragdoll,
        Enum.HumanoidStateType.FallingDown,
        Enum.HumanoidStateType.Seated,
        Enum.HumanoidStateType.PlatformStanding,
        Enum.HumanoidStateType.Swimming,
        Enum.HumanoidStateType.Climbing
    } do pcall(function() h:SetStateEnabled(st, not cutUnusedStates) end) end
    h.JumpPower = 54
end

-- ALWAYS RUN
local function AlwaysRun(enable)
    if runConn then runConn:Disconnect() runConn = nil end
    if not enable then
        lastMoveMag = 0
        if cachedHumanoid then cachedHumanoid.WalkSpeed = 16 end
        return
    end
    runConn = Stepped:Connect(function()
        if not runEnabled then return end
        local md = UserInputService:GetMoveDirection()
        local m = md.Magnitude
        if m ~= lastMoveMag then
            lastMoveMag = m
            if m > 0.04 then pcall(function() UserInputService:SetMoveDirection(md.Unit) end) end
        end
        if cachedHumanoid and cachedHumanoid.WalkSpeed ~= 16 then cachedHumanoid.WalkSpeed = 16 end
    end)
    if cachedHumanoid then cachedHumanoid.WalkSpeed = 16 end
end

-- NO PLAYER ANIMS
local function StripAnims(char)
    if not char or char == LocalPlayer.Character then return end
    pcall(function()
        local animator = char:FindFirstChildWhichIsA("Animator", true)
        if animator then
            animator:AdjustSpeed(0)
            for _, track in ipairs(animator:GetPlayingAnimationTracks()) do pcall(function() track:Stop(0) end) end
            animator.AnimationPlayed:Connect(function(track) pcall(function() track:Stop(0) end) end)
        end
        for _, desc in ipairs(char:GetDescendants()) do
            if desc:IsA("Animation") then pcall(function() desc:Destroy() end) end
        end
    end)
end

local function ToggleNoPlayerAnims(enable)
    for _, c in ipairs(animConn) do pcall(function() c:Disconnect() end) end
    table_clear(animConn)
    if not enable then return end

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then StripAnims(p.Character) end
        table_insert(animConn, p.CharacterAdded:Connect(function(c) task_defer(function() StripAnims(c) end) end))
    end
    table_insert(animConn, Players.PlayerAdded:Connect(function(p)
        table_insert(animConn, p.CharacterAdded:Connect(function(c) task_defer(function() StripAnims(c) end) end))
    end))
end

-- REMOVE LAG OVER TIME
local function ToggleLagOverTime(enable)
    if lagOverTimeConn then lagOverTimeConn:Disconnect() lagOverTimeConn = nil end
    if not enable then return end

    lastMaintenance = os_clock()
    lagOverTimeConn = Stepped:Connect(function(_, dt)
        if not removeLagOverTime then return end
        local now = os_clock()
        if now - lastMaintenance < 45 then return end
        local moving = cachedRoot and cachedRoot.AssemblyLinearVelocity.Magnitude > 0.8
        if moving or IsBusy() or spikeRecovery > 0 then return end

        lastMaintenance = now
        QueueJob(function() table_clear(jobQueue) jobQueue = table_create(MAX_JOBS) end)
        QueueJob(function()
            for i = #lagConns, 1, -1 do
                local c = lagConns[i]
                if not c or not pcall(function() return c.Connected end) then
                    pcall(function() c:Disconnect() end) lagConns[i] = nil
                end
            end
        end)
        QueueJob(function() for _ = 1, 6 do pcall(function() collectgarbage("step", 2) end) end end)
        QueueJob(function() pcall(function() Debris:CleanUp() end) end)
        QueueJob(function() if #tracerPool > 30 then table_clear(tracerPool) end end)
    end)
end

-- OPTIMIZE LIGHTING
local function DisablePostEffects(level)
    for _, e in ipairs(Lighting:GetChildren()) do
        pcall(function()
            if e:IsA("BloomEffect") then e.Enabled = level < 25 end
            if e:IsA("ColorCorrectionEffect") then e.Enabled = level < 50 end
            if e:IsA("SunRaysEffect") then e.Enabled = level < 40 end
            if e:IsA("DepthOfFieldEffect") then e.Enabled = level < 60 end
            if e:IsA("BlurEffect") then e.Enabled = level < 30 end
        end)
    end
end

local function ApplyLightingOpt(level)
    pcall(function()
        Lighting.Brightness = DEFAULT_LIGHTING.Brightness
        Lighting.Contrast = DEFAULT_LIGHTING.Contrast
        Lighting.ExposureCompensation = DEFAULT_LIGHTING.ExposureCompensation
        Lighting.Saturation = DEFAULT_LIGHTING.Saturation
        Lighting.GlobalShadows = DEFAULT_LIGHTING.GlobalShadows
        Lighting.OutdoorAmbient = DEFAULT_LIGHTING.OutdoorAmbient
        Lighting.Ambient = DEFAULT_LIGHTING.Ambient
    end)
    DisablePostEffects(0)
    if noFog then pcall(function() Lighting.FogEnd = 10000 Lighting.FogStart = 10000 end) end
    if level <= 0 then return end

    pcall(function()
        if level >= 25 then Lighting.GlobalShadows = false end
        if level >= 40 then DisablePostEffects(level) end
        if level >= 50 then
            Lighting.Saturation = math_clamp(DEFAULT_LIGHTING.Saturation - (level/200), -0.2, 0.5)
            Lighting.Contrast = math_clamp(DEFAULT_LIGHTING.Contrast - (level/400), 0.3, 0.6)
        end
        if level >= 75 then
            Lighting.OutdoorAmbient = Color3.new(
                math_clamp(0.5 + (level/400), 0.5, 0.7),
                math_clamp(0.5 + (level/400), 0.5, 0.7),
                math_clamp(0.5 + (level/400), 0.5, 0.7)
            )
            Lighting.Ambient = Lighting.OutdoorAmbient
            Lighting.ExposureCompensation = math_clamp(level/500, 0, 0.2)
        end
        if level >= 100 then
            Lighting.Brightness = math_clamp(DEFAULT_LIGHTING.Brightness + 0.1, 0.5, 0.7)
            for _, e in ipairs(Lighting:GetChildren()) do
                if e:IsA("PostEffect") then pcall(function() e.Enabled = false end) end
            end
        end
    end)
    if noFog then pcall(function() Lighting.FogEnd = 10000 Lighting.FogStart = 10000 end) end
end

-- VISIBLE BULLETS
local function GetTracer()
    if reuseBulletParts and #tracerPool > 0 then local t = table_remove(tracerPool) if t then return t end end
    local t = Instance.new("Part")
    t.Shape = Enum.PartType.Cylinder
    t.Material = Enum.Material.Neon
    t.BrickColor = BrickColor.new("Bright yellow")
    t.Anchored = true
    t.CanCollide = false
    t.CanQuery = false
    t.CanTouch = false
    t.CastShadow = false
    return t
end

local function ReleaseTracer(t)
    if not t then return end
    t.Parent = nil
    if reuseBulletParts and #tracerPool < 30 then table_insert(tracerPool, t)
    else pcall(function() t:Destroy() end) end
end

local function DrawBulletTracer(startPos, endPos)
    if not visibleBulletsEnabled then return end
    local tracer = GetTracer()
    tracer.Transparency = 0.3
    local dist = (endPos - startPos).Magnitude
    tracer.Size = Vector3.new(0.05, dist, 0.05)
    tracer.CFrame = CFrame.new(startPos, endPos) * CFrame.Angles(0, math.rad(90), 0)
    tracer.Parent = workspace
    table_insert(bulletParts, tracer)
    task_delay(0.15, function()
        for i = #bulletParts, 1, -1 do if bulletParts[i] == tracer then table_remove(bulletParts, i) end end
        ReleaseTracer(tracer)
    end)
end

local function HookToolShots()
    for _, c in ipairs(toolConns) do pcall(function() c:Disconnect() end) end
    table_clear(toolConns)
    local char = LocalPlayer.Character if not char then return end

    table_insert(toolConns, char.ChildAdded:Connect(function(ch)
        if ch:IsA("Tool") then
            table_insert(toolConns, ch.Activated:Connect(function()
                if not visibleBulletsEnabled then return end
                local root = char:FindFirstChild("HumanoidRootPart") if not root then return end
                DrawBulletTracer(root.Position + Vector3.new(0,1.6,0), root.Position + Camera.CFrame.LookVector * 250)
            end))
        end
    end))

    for _, ch in ipairs(char:GetChildren()) do
        if ch:IsA("Tool") then
            table_insert(toolConns, ch.Activated:Connect(function()
                if not visibleBulletsEnabled then return end
                local root = char:FindFirstChild("HumanoidRootPart") if not root then return end
                DrawBulletTracer(root.Position + Vector3.new(0,1.6,0), root.Position + Camera.CFrame.LookVector * 250)
            end))
        end
    end
end

-- ==============================================
-- 3. UI (NOW AFTER ALL FUNCTIONS — NO NIL CALLS)
-- ==============================================
local AntiLagMatrix = shared.AddSection("Anti Lag Matrix")

AntiLagMatrix:AddToggle("Always Run", function(s)
    runEnabled = s
    AlwaysRun(s)
    shared.Notify("Always Run: "..(s and "ON" or "OFF"), 1)
end)

AntiLagMatrix:AddSlider("Render Distance", 30, 120, 70, function(v)
    renderDist = math_floor(v)
    pcall(function() workspace.StreamingTargetRadius = renderDist end)
    shared.Notify("Render: "..renderDist, 0.8)
end)

AntiLagMatrix:AddToggle("Visible Bullets", function(s)
    visibleBulletsEnabled = s
    if not s then
        for _, b in ipairs(bulletParts) do pcall(function() b:Destroy() end) end
        for _, c in ipairs(toolConns) do pcall(function() c:Disconnect() end) end
        table_clear(bulletParts) table_clear(toolConns) table_clear(tracerPool)
    else
        HookToolShots()
    end
    shared.Notify("Bullets: "..(s and "ON" or "OFF"), 1)
end)

AntiLagMatrix:AddToggle("No Fog", function(s)
    noFog = s
    if not s then pcall(function() Lighting.FogEnd = DEFAULT_LIGHTING.FogEnd Lighting.FogStart = DEFAULT_LIGHTING.FogStart end)
    else ApplyLightingOpt(lightingOptLevel) end
    shared.Notify("No Fog: "..(s and "ON" or "OFF"), 1)
end)

AntiLagMatrix:AddToggle("No Knockback", function(s)
    noKnockback = s
    shared.Notify("Knockback: "..(s and "OFF" or "ON"), 1)
end)

AntiLagMatrix:AddToggle("No Player Anims", function(s)
    noPlayerAnims = s
    ToggleNoPlayerAnims(s)
    shared.Notify("Player Anims: "..(s and "OFF" or "ON"), 1)
end)

AntiLagMatrix:AddToggle("Remove Lag Over Time", function(s)
    removeLagOverTime = s
    ToggleLagOverTime(s)
    shared.Notify("Lag Fix Over Time: "..(s and "ON" or "OFF"), 1)
end)

AntiLagMatrix:AddSlider("Optimize Lighting", 0, 100, 0, function(v)
    lightingOptLevel = math_floor(v)
    ApplyLightingOpt(lightingOptLevel)
    shared.Notify("Lighting Opt: "..lightingOptLevel.."%", 0.8)
end)

AntiLagMatrix:AddToggle("Stop Auto GC", function(s) stopAutoGC = s shared.Notify("Stop Auto GC: "..(s and "ON" or "OFF"), 0.8) end)
AntiLagMatrix:AddToggle("Auto Render Distance", function(s) autoRenderDist = s shared.Notify("Auto Render: "..(s and "ON" or "OFF"), 0.8) end)
AntiLagMatrix:AddToggle("Lock Network", function(s) lockNetwork = s LockNetwork(s) shared.Notify("Net Lock: "..(s and "ON" or "OFF"), 0.8) end)
AntiLagMatrix:AddToggle("Clean Idle Junk", function(s) cleanIdleJunk = s shared.Notify("Clean Junk: "..(s and "ON" or "OFF"), 0.8) end)
AntiLagMatrix:AddToggle("Cut Unused States", function(s) cutUnusedStates = s if cachedHumanoid then ApplyStateCull(cachedHumanoid) end shared.Notify("Cut States: "..(s and "ON" or "OFF"), 0.8) end)
AntiLagMatrix:AddToggle("Clean Dead Links", function(s) cleanDeadLinks = s shared.Notify("Clean Links: "..(s and "ON" or "OFF"), 0.8) end)
AntiLagMatrix:AddToggle("Limit Background Work", function(s) limitBackgroundWork = s shared.Notify("Limit Work: "..(s and "ON" or "OFF"), 0.8) end)
AntiLagMatrix:AddToggle("Block Lag On High Ping", function(s) blockLagOnHighPing = s shared.Notify("Ping Shield: "..(s and "ON" or "OFF"), 0.8) end)
AntiLagMatrix:AddToggle("Reuse Bullet Parts", function(s) reuseBulletParts = s shared.Notify("Reuse Parts: "..(s and "ON" or "OFF"), 0.8) end)

AntiLagMatrix:AddParagraph("Credits", "@erixniex --- Anti Lag Matrix")

-- ==============================================
-- 4. MAIN LOOPS + SETUP
-- ==============================================
Stepped:Connect(function(_, dt)
    frameIdx = (frameIdx % MAX_FRAMES) + 1
    frameTimes[frameIdx] = dt
    if limitBackgroundWork then UpdateBudget() end

    local moving = cachedRoot and cachedRoot.AssemblyLinearVelocity.Magnitude > 0.8

    if stopAutoGC then
        pcall(function() collectgarbage("stop") end)
        local now = os_clock()
        if not moving and not IsBusy() and spikeRecovery == 0 and now - lastGC > 1.2 then
            lastGC = now
            local heap = gcinfo()
            local step = heap > 1200 and 3 or heap > 900 and 2 or 1
            QueueJob(function() pcall(function() collectgarbage("step", step) end) end)
        end
    else
        pcall(function() collectgarbage("restart") end)
    end

    if autoRenderDist then
        local target = renderDist
        if spikeRecovery > 3 then target = math_clamp(renderDist - 25, 30, 120)
        elseif spikeRecovery > 0 then target = math_clamp(renderDist - 10, 30, 120) end
        pcall(function() if workspace.StreamingTargetRadius ~= target then workspace.StreamingTargetRadius = target end end)
    end

    if cleanIdleJunk and not moving and not IsBusy() then
        local now = os_clock()
        if now - lastDebris > 20 then lastDebris = now QueueJob(function() pcall(function() Debris:CleanUp() end) end) end
    end

    if cleanDeadLinks then
        local now = os_clock()
        if now - lastPrune > 30 then lastPrune = now
            QueueJob(function()
                for i = #lagConns, 1, -1 do
                    local c = lagConns[i]
                    if not c or not pcall(function() return c.Connected end) then
                        pcall(function() c:Disconnect() end) lagConns[i] = nil
                    end
                end
            end)
        end
    end

    if blockLagOnHighPing then
        local ok, ping = pcall(function() return Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
        if ok and ping and ping > 200 then BusyFor(0.25) end
    end

    RunJobs()
end)

PreSimulation:Connect(function()
    if not cachedRoot then
        local c = LocalPlayer.Character
        cachedRoot = c and c:FindFirstChild("HumanoidRootPart") or nil
    end
    if cachedRoot then
        cachedRoot.CustomPhysicalProperties = PhysicalProperties.new(10, 0.02, 0.15, 5000, 5000)
        cachedRoot.RootPriority = 255
        if lockNetwork then pcall(function() cachedRoot:SetNetworkOwner(LocalPlayer) end) end
        if noKnockback then
            local moveDir = UserInputService:GetMoveDirection()
            if moveDir.Magnitude < 0.05 then
                local v = cachedRoot.AssemblyLinearVelocity
                cachedRoot.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
            end
        end
    end
end)

RenderStepped:Connect(function()
    if noFog then pcall(function() Lighting.FogEnd = 10000 Lighting.FogStart = 10000 end) end
    for i = #bulletParts, 1, -1 do if not bulletParts[i] or bulletParts[i].Parent == nil then table_remove(bulletParts, i) end end
end)

LocalPlayer.CharacterAdded:Connect(function(c)
    cachedHumanoid = nil cachedRoot = nil
    task_wait(0.2)
    cachedHumanoid = c:FindFirstChildOfClass("Humanoid")
    cachedRoot = c:FindFirstChild("HumanoidRootPart")
    if runEnabled and cachedHumanoid then cachedHumanoid.WalkSpeed = 16 end
    if cutUnusedStates and cachedHumanoid then ApplyStateCull(cachedHumanoid) end
    if lockNetwork then LockNetwork(true) end
    if visibleBulletsEnabled then HookToolShots() end
    BusyFor(1.5)
end)

if LocalPlayer.Character then
    cachedHumanoid = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
    cachedRoot = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if cutUnusedStates and cachedHumanoid then ApplyStateCull(cachedHumanoid) end
    if visibleBulletsEnabled then HookToolShots() end
end

local function ShieldDeath(p)
    local function onChar(c)
        local h = c:WaitForChild("Humanoid", 3)
        if h then table_insert(lagConns, h.Died:Connect(function() BusyFor(1.2) end)) end
    end
    if p.Character then onChar(p.Character) end
    table_insert(lagConns, p.CharacterAdded:Connect(onChar))
end
for _, p in ipairs(Players:GetPlayers()) do ShieldDeath(p) end
table_insert(lagConns, Players.PlayerAdded:Connect(ShieldDeath))
table_insert(lagConns, workspace.ChildAdded:Connect(function(ch)
    if ch:IsA("Model") and ch.Name:lower():find("map") then BusyFor(6) end
end))

-- UNLOAD
getgenv().UnloadCore = function()
    AlwaysRun(false)
    ToggleNoPlayerAnims(false)
    ToggleLagOverTime(false)
    ApplyLightingOpt(0)
    DisconnectAll(lagConns)
    for _, c in ipairs(toolConns) do pcall(function() c:Disconnect() end) end
    stopAutoGC = false autoRenderDist = false lockNetwork = false
    cleanIdleJunk = false cutUnusedStates = false cleanDeadLinks = false limitBackgroundWork = false
    blockLagOnHighPing = false reuseBulletParts = false removeLagOverTime = false
    visibleBulletsEnabled = false noFog = false noKnockback = false noPlayerAnims = false lightingOptLevel = 0
    for _, b in ipairs(bulletParts) do pcall(function() b:Destroy() end) end
    table_clear(bulletParts) table_clear(tracerPool) table_clear(jobQueue) table_clear(toolConns)
    pcall(function()
        collectgarbage("restart")
        workspace.StreamingTargetRadius = 120
        Lighting.FogEnd = DEFAULT_LIGHTING.FogEnd Lighting.FogStart = DEFAULT_LIGHTING.FogStart
        LocalPlayer:SetNetworkOwnershipAuto(true)
    end)
    shared.Notify("Anti Lag Matrix unloaded", 1.2)
end

print("Anti Lag Matrix Loaded — Nil Call Error Fixed")
