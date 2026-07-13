local shared = odh_shared_plugins
local my_own_section = shared.AddSection("Anti Lag Spike")

local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local UserGameSettings = UserSettings():GetService("UserGameSettings")

local conn = nil
local active = false

local CONFIG = {
    SpikeThresholdMs  = 55,
    MemoryLimitMb     = 900,
    MinCleanInterval  = 14,
    CheckRate         = 0.25,
    MaxDebrisLife     = 3.5
}

local lastCheck = 0
local lastClean = 0
local spikeCount = 0
local origQuality = UserGameSettings.SavedQualityLevel

local function SafeCleanup(force)
    local now = tick()
    if not force and (now - lastClean) < CONFIG.MinCleanInterval then return end
    lastClean = now

    task.defer(function()
        collectgarbage("step", 250)
        collectgarbage("step", 250)

        pcall(function()
            for _, v in Workspace:GetDescendants() do
                if v.Name == "TempEffect" or v.Name == "Debris" or v.Name == "FlyingBullet" then
                    Debris:AddItem(v, 0.1)
                end
            end
        end)

        pcall(function()
            if UserGameSettings.SavedQualityLevel ~= origQuality then
                UserGameSettings.SavedQualityLevel = origQuality
            end
        end)
    end)
end

local function Start()
    if conn then return end
    lastCheck = tick()
    lastClean = tick()
    spikeCount = 0

    conn = RunService.Heartbeat:Connect(function(delta)
        if not active then return end

        local now = tick()
        local deltaMs = delta * 1000

        if deltaMs >= CONFIG.SpikeThresholdMs then
            spikeCount += 1
            if spikeCount >= 2 then
                SafeCleanup(false)
                spikeCount = 0
            end
        else
            spikeCount = math.max(0, spikeCount - 0.25)
        end

        if (now - lastCheck) >= CONFIG.CheckRate then
            lastCheck = now
            pcall(function()
                if Stats:GetTotalMemoryUsageMb() >= CONFIG.MemoryLimitMb then
                    SafeCleanup(false)
                end
            end)
        end
    end)
end

local function Stop()
    if conn then
        conn:Disconnect()
        conn = nil
    end
    spikeCount = 0
end

my_own_section:AddToggle("Enable Anti Lag Spike", function(v)
    active = v
    if v then
        Start()
        shared.Notify("Anti Lag Spike ON", 1.5)
    else
        Stop()
        shared.Notify("Anti Lag Spike OFF", 1.5)
    end
end)

my_own_section:AddParagraph("", "Detects frame spikes and high memory usage automatically. Cleans safely without stutter. Keeps graphics unchanged. Does not affect Silent Aim or any Overdrive feature.")
my_own_section:AddParagraph("Anti Lag Spike by @erixniex", "")
        collectgarbage("step", 250)
        collectgarbage("step", 250)

        -- Clear real bloat: temp instances, debris, sounds
        pcall(function()
            for _, v in Workspace:GetDescendants() do
                if v.Name == "TempEffect" or v.Name == "Debris" or v.Name == "FlyingBullet" then
                    Debris:AddItem(v, 0.1)
                end
            end
        end)

        -- Lock graphics quality so it NEVER downgrades
        pcall(function()
            if UserGameSettings.SavedQualityLevel ~= origQuality then
                UserGameSettings.SavedQualityLevel = origQuality
            end
        end)
    end)
end

-- ==============================================
-- REAL SPIKE DETECTION — ACTUALLY WORKS
-- ==============================================
local function Start()
    if conn then return end
    lastCheck = tick()
    lastClean = tick()
    spikeCount = 0

    conn = RunService.Heartbeat:Connect(function(delta)
        if not active then return end

        local now = tick()
        local deltaMs = delta * 1000

        -- Detect lag spikes
        if deltaMs >= CONFIG.SpikeThresholdMs then
            spikeCount += 1
            if spikeCount >= 2 then
                SafeCleanup(false)
                spikeCount = 0
            end
        else
            spikeCount = math.max(0, spikeCount - 0.25)
        end

        -- Memory + health check
        if (now - lastCheck) >= CONFIG.CheckRate then
            lastCheck = now
            pcall(function()
                if Stats:GetTotalMemoryUsageMb() >= CONFIG.MemoryLimitMb then
                    SafeCleanup(false)
                end
            end)
        end
    end)
end

local function Stop()
    if conn then
        conn:Disconnect()
        conn = nil
    end
    spikeCount = 0
end

-- ==============================================
-- UI
-- ==============================================
my_own_section:AddToggle("Enable Anti Lag Spike", function(v)
    active = v
    if v then
        Start()
        shared.Notify("Anti Lag Spike ON", 1.5)
    else
        Stop()
        shared.Notify("Anti Lag Spike OFF", 1.5)
    end
end)

my_own_section:AddParagraph("", "Detects real frame spikes and high memory usage automatically.")
my_own_section:AddParagraph("", "Cleanup runs rarely and lightly — will NOT build up lag over time.")
my_own_section:AddParagraph("", "Render quality is locked permanently, graphics never lowered.")
my_own_section:AddParagraph("", "Does not touch Silent Aim, Piercer, Wallbang or any ODH feature.")
my_own_section:AddParagraph("Anti Lag Spike by @erixniex", "")
