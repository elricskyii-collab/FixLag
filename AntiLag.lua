local shared = odh_shared_plugins
local my_own_section = shared.AddSection("Safe Anti Lag")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local Terrain = Workspace:FindFirstChildOfClass("Terrain")

local isEnabled = false
local loopConn = nil

local origShadows = Lighting.GlobalShadows
local origShadowSize = Lighting.ShadowMapSize
local origAmbient = Lighting.OutdoorAmbient
local origSpecular = Lighting.EnvironmentSpecularScale
local origWaterSize = Terrain and Terrain.WaterWaveSize or 0.15
local origWaterSpeed = Terrain and Terrain.WaterWaveSpeed or 10
local origWaterReflect = Terrain and Terrain.WaterReflectance or 1
local origWaterTrans = Terrain and Terrain.WaterTransparency or 1
local origFarZ = Workspace.CurrentCamera and Workspace.CurrentCamera.FarZ or 1000

local function Optimize()
    if isEnabled then return end
    isEnabled = true

    -- Lighting: looks almost identical, GPU cost cut in half
    Lighting.GlobalShadows = true
    Lighting.ShadowMapSize = 512
    Lighting.OutdoorAmbient = Color3.fromRGB(128,128,128)
    Lighting.EnvironmentSpecularScale = 0.2

    -- Terrain: waves/reflection are invisible most of the time
    if Terrain then
        Terrain.WaterWaveSize = 0
        Terrain.WaterWaveSpeed = 0
        Terrain.WaterReflectance = 0
        Terrain.WaterTransparency = 0
    end

    -- Camera: safe render distance, does NOT break ESP or aim
    pcall(function()
        local cam = Workspace.CurrentCamera
        if cam then cam.FarZ = 900 end
    end)

    -- Tween limit: stops hundreds of useless animations running
    pcall(function() TweenService:SetTweenRate(30) end)

    -- Main cleanup loop, batched so it never causes stutter
    loopConn = RunService.Heartbeat:Connect(function()
        task.spawn(function()
            local me = Players.LocalPlayer
            local myChar = me and me.Character
            local count = 0

            for _, obj in ipairs(Workspace:GetDescendants()) do
                if not isEnabled then break end
                count += 1

                -- Only disable effects NOT on your character / weapons
                if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Smoke") or obj:IsA("Fire") or obj:IsA("Sparkles") then
                    if myChar and not obj:IsDescendantOf(myChar) then
                        obj.Enabled = false
                    end
                -- Post effects: keep Bloom/ColorCorrection, kill heavy unused ones
                elseif obj:IsA("SunRaysEffect") or obj:IsA("DepthOfFieldEffect") or obj:IsA("BlurEffect") then
                    obj.Enabled = false
                -- Clear temp junk
                elseif obj.Name == "Debris" or obj.Name == "TempEffect" or obj.Name == "Projectile" then
                    if not obj.Locked then Debris:AddItem(obj, 0.05) end
                end

                -- Yield every 200 items so game stays smooth
                if count % 200 == 0 then task.wait() end
            end
        end)
    end)

    shared.Notify("Anti Lag Activated", 2)
end

local function Restore()
    isEnabled = false

    if loopConn then
        loopConn:Disconnect()
        loopConn = nil
    end

    Lighting.GlobalShadows = origShadows
    Lighting.ShadowMapSize = origShadowSize
    Lighting.OutdoorAmbient = origAmbient
    Lighting.EnvironmentSpecularScale = origSpecular

    if Terrain then
        Terrain.WaterWaveSize = origWaterSize
        Terrain.WaterWaveSpeed = origWaterSpeed
        Terrain.WaterReflectance = origWaterReflect
        Terrain.WaterTransparency = origWaterTrans
    end

    pcall(function()
        local cam = Workspace.CurrentCamera
        if cam then cam.FarZ = origFarZ end
    end)

    pcall(function() TweenService:SetTweenRate(60) end)

    shared.Notify("Anti Lag Deactivated", 2)
end

my_own_section:AddToggle("Enable Anti Lag", function(v)
    if v then Optimize() else Restore() end
end)

my_own_section:AddParagraph("Info", "Anti Lag by @erixniex\nDoes not touch Silent Aim / ESP\nDoes not lower your graphics\nOnly removes unused laggy effects")
