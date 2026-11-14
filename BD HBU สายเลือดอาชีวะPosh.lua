--[[
=====================================================================
    BD HBU v10   (Background / Silent / No UI)
    ---------------------------------------------------------------
    - Damage  : start 190  ->  max 8000  (auto scale)
    - Bullet  : free curved / arc trajectory
    - Bypass  : anti-detect (jitter, random pattern, silent)
    - Map     : auto map detection (background scan)
    - Modular : แต่ละ module แยก task ทำงานเบื้องหลัง
    - No GUI  : ไม่มี interface ใด ๆ
=====================================================================
--]]

-- ===================================================================
-- [MODULE 1] CONFIG
-- ===================================================================
local CONFIG = {
    DAMAGE_START   = 190,
    DAMAGE_MAX     = 8000,
    DAMAGE_STEP    = 190,          -- +190 ต่อ hit
    CURVE_ENABLED  = true,
    CURVE_STRENGTH = 0.35,         -- ความโค้งของกระสุน
    BULLET_SPEED   = 2,            -- step ต่อเฟรม
    BULLET_LIFE    = 200,          -- เฟรมสูงสุดก่อนลบ
    JITTER_MIN     = 0.010,
    JITTER_MAX     = 0.045,
    MAP_SCAN_TIME  = 2,            -- วินาทีต่อการสแกน map
    SILENT         = true,
}

local function log(...)
    if not CONFIG.SILENT then print("[BD HBU v10]", ...) end
end

local function jitter()
    return math.random() * (CONFIG.JITTER_MAX - CONFIG.JITTER_MIN) + CONFIG.JITTER_MIN
end

-- ===================================================================
-- [MODULE 2] DAMAGE CONTROLLER   (190 -> 8000 auto-scale)
-- ===================================================================
local Damage = {}
Damage.current = CONFIG.DAMAGE_START

function Damage.apply(hum)
    if not hum or hum.Health <= 0 then return end
    local dmg = math.clamp(Damage.current, CONFIG.DAMAGE_START, CONFIG.DAMAGE_MAX)
    pcall(function() hum:TakeDamage(dmg) end)
    Damage.current = math.min(Damage.current + CONFIG.DAMAGE_STEP, CONFIG.DAMAGE_MAX)
    log("DMG:", dmg, "| next:", Damage.current)
end

function Damage.reset()
    Damage.current = CONFIG.DAMAGE_START
end

-- ===================================================================
-- [MODULE 3] CURVED BULLET ENGINE  (free arc trajectory)
-- ===================================================================
local Bullet = {}
Bullet.list = {}

function Bullet.fire(originPos, dirVector, onHit)
    if not CONFIG.CURVE_ENABLED then
        local ray = Ray.new(originPos, dirVector * 500)
        local part, pos = workspace:FindPartOnRay(ray)
        if onHit then pcall(onHit, part, pos) end
        return
    end
    table.insert(Bullet.list, {
        origin = originPos,
        pos    = originPos,
        dir    = dirVector.Unit,
        t      = 0,
        curve  = CONFIG.CURVE_STRENGTH,
        onHit  = onHit,
    })
end

-- background updater
task.spawn(function()
    while task.wait(1/60) do
        for i = #Bullet.list, 1, -1 do
            local b = Bullet.list[i]
            if not b then continue end
            b.t = b.t + 1

            -- perpendicular bend (free curve)
            local right = b.dir:Cross(Vector3.new(0,1,0))
            if right.Magnitude < 0.001 then right = Vector3.new(1,0,0) end
            local bend = right.Unit * math.sin(b.t * 0.15) * b.curve

            local step    = b.dir * CONFIG.BULLET_SPEED + bend
            local nextPos = b.pos + step

            local ray = Ray.new(b.pos, nextPos - b.pos)
            local hitPart, hitPos = workspace:FindPartOnRay(ray)

            if hitPart then
                if b.onHit then pcall(b.onHit, hitPart, hitPos) end
                table.remove(Bullet.list, i)
            else
                b.pos = nextPos
                if b.t > CONFIG.BULLET_LIFE then table.remove(Bullet.list, i) end
            end
        end
    end
end)

-- ===================================================================
-- [MODULE 4] TARGET AUTO-DETECT
-- ===================================================================
local Target = {}
Target.active = {}

function Target.scan()
    for _, plr in ipairs(game.Players:GetPlayers()) do
        local char = plr.Character
        if char then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health > 0 then
                Target.active[char] = hum
            end
        end
    end
end

task.spawn(function()
    while task.wait(CONFIG.MAP_SCAN_TIME) do pcall(Target.scan) end
end)

-- ===================================================================
-- [MODULE 5] MAP DETECTION  (silent background scan)
-- ===================================================================
local Map = {}
Map.list = {}
Map.lastScan = 0

function Map.scan()
    local now = tick()
    if now - Map.lastScan < CONFIG.MAP_SCAN_TIME then return end
    Map.lastScan = now
    for _, obj in ipairs(workspace:GetDescendants()) do
        if obj:IsA("Model") or obj:IsA("Folder") then
            local n = obj.Name
            if n:match("Map") or n:match("Arena") or n:match("Zone")
            or n:match("Stage") or n:match("Level") then
                Map.list[obj] = true
            end
        end
    end
    log("Maps detected:", (function() local c=0 for _ in pairs(Map.list) do c=c+1 end return c end)())
end

task.spawn(function()
    while task.wait(CONFIG.MAP_SCAN_TIME) do pcall(Map.scan) end
end)

-- ===================================================================
-- [MODULE 6] ANTI-DETECT / BYPASS
-- ===================================================================
local Bypass = {}

function Bypass.safeDamage(hum, amount)
    task.delay(jitter(), function()
        pcall(function()
            if hum and hum.Parent and hum.Health > 0 then
                hum:TakeDamage(amount)
            end
        end)
    end)
end

-- ===================================================================
-- [MODULE 7] DAMAGE WATCHER (auto scale on hit)
-- ===================================================================
local function hookHum(hum)
    if not hum or hum:GetAttribute("BDHBU_Hooked") then return end
    hum:SetAttribute("BDHBU_Hooked", true)
    hum.HealthChanged:Connect(function(newHealth)
        if newHealth > 0 and newHealth < hum.MaxHealth then
            if Damage.current < CONFIG.DAMAGE_MAX then
                Damage.current = math.min(Damage.current + CONFIG.DAMAGE_STEP, CONFIG.DAMAGE_MAX)
            end
        end
    end)
end

task.spawn(function()
    while task.wait(1) do
        pcall(function()
            for _, plr in ipairs(game.Players:GetPlayers()) do
                if plr.Character then
                    local hum = plr.Character:FindFirstChildOfClass("Humanoid")
                    if hum then hookHum(hum) end
                end
            end
        end)
    end
end)

-- ===================================================================
-- [MODULE 8] PUBLIC API (silent)
-- ===================================================================
_G.BDHBUv10 = {
    Fire          = function(o, d, cb) Bullet.fire(o, d, cb) end,
    Damage        = function(hum) Damage.apply(hum) end,
    SafeDamage    = function(hum, amt) Bypass.safeDamage(hum, amt or Damage.current) end,
    GetBaseDamage = function() return Damage.current end,
    ResetDamage   = function() Damage.reset() end,
    ScanMap       = function() Map.scan() end,
    ScanPlayers   = function() Target.scan() end,
    Version       = "v10",
}

log("Loaded. Background modules running. Base DMG:", Damage.current)
return _G.BDHBUv10
