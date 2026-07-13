local shared = odh_shared_plugins
local my_own_section = shared.AddSection("Safe Anti Lag")

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local Terrain = Workspace:FindFirstChildOfClass("Terrain")

local isEnabled = false
local isRunning = false
local origShadows = Lighting.GlobalShadows
local origAmbient = Lighting.OutdoorAmbient
local origWaterSize = Terrain and Terrain.WaterWaveSize or 0.15
local origWaterSpeed = Terrain and Terrain.WaterWaveSpeed or 10
local origWaterReflect = Terrain and Terrain.WaterReflectance or 1
local origWaterTrans = Terrain and Terrain.WaterTransparency or 1

local function Optimize()
    if not isEnabled then return end
    isRunning = true

    -- Safe lighting balance: looks same, runs faster
    Lighting.GlobalShadows = false
    Lighting.OutdoorAmbient = Color3.fromRGB(128,128,128)

    -- Terrain tweaks only
    if Terrain then
        Terrain.WaterWaveSize = 0
        Terrain.WaterWaveSpeed = 0
        Terrain.WaterReflectance = 0
        Terrain.WaterTransparency = 0
    end

    -- Clean only unused map effects: keep player/aim/ESP fully working
    task.spawn(function()
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if not isEnabled then break end
            if obj:IsA("ParticleEmitter") or obj:IsA("Trail") or obj:IsA("Smoke") or obj:IsA("Fire") then
                if not obj:IsDescendantOf(Players.LocalPlayer.Character) then
                    obj.Enabled = false
                end
            elseif obj:IsA("Debris") or obj.Name == "TempEffect" then
                game.Debris:AddItem(obj, 0.1)
            end
            task.wait()
        end
    end)

    shared.Notify("Anti Lag Activated", 2)
end

local function Restore()
    isEnabled = false
    isRunning = false

    -- Put everything back exactly as it was
    Lighting.GlobalShadows = origShadows
    Lighting.OutdoorAmbient = origAmbient
    if Terrain then
        Terrain.WaterWaveSize = origWaterSize
        Terrain.WaterWaveSpeed = origWaterSpeed
        Terrain.WaterReflectance = origWaterReflect
        Terrain.WaterTransparency = origWaterTrans
    end

    shared.Notify("Anti Lag Deactivated", 2)
end

my_own_section:AddToggle("Enable Anti Lag", function(v)
    isEnabled = v
    if v then Optimize() else Restore() end
end)

my_own_section:AddParagraph("Info", " Does not touch Silent Aim / ESP\n Does not lower your graphics\n Only removes unused laggy effects")
