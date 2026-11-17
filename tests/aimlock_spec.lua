package.path = './moonloader/lib/?.lua;' .. package.path
local release = arg and arg[1]
local entrypoint = release or './moonloader/AimLock.lua'
local function load_entry(env)
    env.script_name = function(value) env.name = value end
    env.script_author = function() end
    env.script_version = function(value) env.version = value end
    env.script_description = function() end
    env._G = env
    local chunk = assert(loadfile(entrypoint))
    setfenv(chunk, env)
    return chunk()
end
local loader = require
if release then
    local env = setmetatable({ require = function() error('External module loaded') end }, { __index = _G })
    loader = assert(load_entry(env))
end
local Settings = loader('AimLockDistribution.settings')
local Camera = loader('AimLockDistribution.camera')
local Controller = loader('AimLockDistribution.controller')
local World = loader('AimLockDistribution.world')
local passed, failed = 0, 0
local function equal(a, b) assert(a == b, tostring(a) .. ' ~= ' .. tostring(b)) end
local function near(a, b) assert(math.abs(a - b) < 1e-8, tostring(a) .. ' != ' .. tostring(b)) end
local function test(name, callback)
    local ok, err = pcall(callback)
    if ok then passed = passed + 1; print('PASS ' .. name)
    else failed = failed + 1; print('FAIL ' .. name .. ': ' .. tostring(err)) end
end
local function vec(x, y, z) return { x = x, y = y, z = z } end
local origin = vec(0, 0, 0)

test('settings start OFF and copies do not mutate defaults', function()
    local settings = assert(Settings.validate({}))
    equal(settings.enabled, false)
    settings.max_distance = 1
    equal(Settings.validate({}).max_distance, 60)
end)
test('settings reject invalid bounds, unknown keys, nonfinite values and wrong types', function()
    for _, values in ipairs({ {enabled=1}, {max_distance=0}, {max_distance=301},
        {fov_radius=0}, {target_height=2}, {crosshair_x=2}, {crosshair_y=-1},
        {max_distance=0/0}, {max_distance=math.huge}, {unknown=1} }) do
        local value, err = Settings.validate(values)
        equal(value, nil); assert(type(err) == 'string')
    end
end)
test('INI accepts BOM CRLF comments and shipped configuration', function()
    local settings = assert(Settings.parse('\239\187\191[aimlock]\r\nenabled=false ; off\r\nmax_distance=75\r\n'))
    equal(settings.enabled, false); equal(settings.max_distance, 75)
    equal(assert(Settings.load('./moonloader/config/AimLock1.1.0.ini')).enabled, false)
end)
test('INI rejects missing section, duplicates, invalid booleans and damaged lines', function()
    for _, text in ipairs({ '', 'enabled=false', '[bad]', '[aimlock]\nenabled=1',
        '[aimlock]\nenabled=false\nenabled=true', '[aimlock]\n[aimlock]', '[aimlock]\nmax_distance=oops' }) do
        equal(Settings.parse(text), nil)
    end
end)
test('camera solves cardinal directions in GTA radians', function()
    for _, item in ipairs({ {vec(1,0,0), -math.pi}, {vec(0,1,0), -math.pi/2},
        {vec(-1,0,0), 0}, {vec(0,-1,0), math.pi/2} }) do
        local pitch, yaw = Camera.solve(origin, vec(1,0,0), vec(1,0,0), item[1])
        near(pitch, 0); near(yaw, item[2])
    end
end)
test('camera compensates crosshair offset and wraps around pi', function()
    local pitch, yaw = Camera.solve(origin, vec(1,0,0), vec(1,0.1,0.1), vec(1,0.1,0.1))
    near(pitch, 0); near(yaw, -math.pi)
    near(Camera.wrap(math.pi + 0.1), -math.pi + 0.1)
end)
test('camera clamps pitch and rejects zero or nonfinite vectors', function()
    local pitch = Camera.solve(origin, vec(1,0,0), vec(1,0,0), vec(0,0,10))
    near(pitch, math.rad(60))
    equal(Camera.solve(origin, origin, vec(1,0,0), vec(1,0,0)), nil)
    equal(Camera.solve(origin, vec(1,0,0), vec(1,0,0), vec(0/0,0,0)), nil)
end)

local function controls()
    local state = { writes=0, searches=0, toggles=0, valid=true, found=true }
    state.controller = Controller.new(assert(Settings.validate({})), {
        find_target=function() state.searches=state.searches+1; return state.found and {ped=2} or nil end,
        validate_target=function(target) return state.valid and target or nil end,
        point_at=function() state.writes=state.writes+1; return true end,
        on_toggle=function() state.toggles=state.toggles+1 end
    })
    state.step = function(ctrl, x, aiming, blocked)
        return state.controller:step({ctrl=ctrl, x=x, aiming=aiming, blocked=blocked})
    end
    return state
end
test('Ctrl X toggles once per chord and OFF never writes camera', function()
    local s=controls()
    s.step(false,false,true,false); equal(s.writes,0)
    s.step(true,true,true,false); s.step(true,true,true,false)
    equal(s.toggles,1); equal(s.writes,2); equal(s.searches,1)
    s.step(false,false,true,false); s.step(true,true,true,false)
    equal(s.toggles,2); equal(s.writes,3); equal(s.controller.enabled,false)
end)
test('X alone does not toggle and Ctrl pressed after X toggles', function()
    local s=controls(); s.step(false,true,true,false); equal(s.toggles,0)
    s.step(true,true,true,false); equal(s.toggles,1)
end)
test('blocked input cannot toggle or activate later while chord stays held', function()
    local s=controls(); s.step(true,true,true,true); s.step(true,true,true,false)
    equal(s.toggles,0); equal(s.writes,0)
    s.step(false,false,false,false); s.step(true,true,false,false)
    equal(s.controller.enabled,true); equal(s.writes,0)
end)
test('releasing aim clears target and target loss reacquires without stale handles', function()
    local s=controls(); s.step(true,true,true,false)
    s.step(false,false,false,false); equal(s.controller.target,nil)
    s.step(false,false,true,false); equal(s.searches,2)
    s.valid=false; s.found=false; s.step(false,false,true,false)
    equal(s.controller.target,nil); equal(s.writes,2)
end)

local function scene()
    local state={dead={},gone={},npc={},bots={},hidden={},walls={},positions={[1]={0,0,0},[2]={10,0,0},[3]={20,0,0}},
        screen={[2]={530,400},[3]={540,400}},writes={},messages={},logs={},keys={},ready=true,weapon=24}
    local api={PLAYER_PED=1}
    state.api=api
    api.doesCharExist=function(ped) return not state.gone[ped] end
    api.isCharDead=function(ped) return state.dead[ped] or false end
    api.sampGetPlayerIdByCharHandle=function(ped) return not state.npc[ped], ped+100 end
    api.sampIsPlayerNpc=function(id) return state.bots[id] or false end
    api.getCharCoordinates=function(ped) return unpack(assert(state.positions[ped])) end
    api.getAllChars=function() return {1,2,3} end
    api.convert3DCoordsToScreenEx=function(x) local id=x==10 and 2 or 3; return not state.hidden[id], unpack(state.screen[id]) end
    api.getScreenResolution=function() return 1000,1000 end
    api.getActiveCameraCoordinates=function() return 0,0,0 end
    api.getActiveCameraPointAt=function() return 1,0,0 end
    api.convertScreenCoordsToWorld3D=function() return 100,0,0 end
    api.isLineOfSightClear=function(_,_,_,x,_,_,buildings,vehicles,actors,objects,particles)
        equal(buildings,true); equal(vehicles,true); equal(actors,false); equal(objects,true); equal(particles,false)
        return not state.walls[x]
    end
    api.setCameraPositionUnfixed=function(pitch,yaw) state.writes[#state.writes+1]={pitch,yaw} end
    state.world=World.new(assert(Settings.validate({})),api)
    return state
end
test('world selects nearest crosshair player and writes actual camera API', function()
    local s=scene(); local target=assert(s.world:find_target())
    equal(target.ped,2); equal(target.id,102); near(target.point.z,0.3)
    assert(s.world:point_at(target)); equal(#s.writes,1)
    near(s.writes[1][1],math.atan(0.3/10)); near(s.writes[1][2],-math.pi)
end)
test('world excludes self, NPC, dead, missing and changed player identities', function()
    local s=scene(); equal(s.world:validate_target({ped=1}),nil)
    equal(s.world:validate_target({ped=2,id=999}),nil)
    for _, field in ipairs({'npc','dead','gone'}) do
        s[field][2]=true; equal(s.world:validate_target({ped=2}),nil); s[field][2]=nil
    end
    s.bots[102]=true; equal(s.world:validate_target({ped=2}),nil)
end)
test('world rejects walls, out of range, offscreen and out of FOV targets', function()
    local s=scene(); s.walls[10]=true; equal(s.world:validate_target({ped=2}),nil); s.walls[10]=nil
    s.positions[2]={100,0,0}; equal(s.world:validate_target({ped=2}),nil); s.positions[2]={10,0,0}
    s.hidden[2]=true; equal(s.world:validate_target({ped=2}),nil); s.hidden[2]=nil
    s.screen[2]={900,900}; equal(s.world:validate_target({ped=2}),nil)
end)

local function entry()
    local s=scene()
    local env=setmetatable(s.api,{__index=_G})
    env.print=function(text) s.logs[#s.logs+1]=text end
    env.isSampLoaded=function() return true end
    env.isSampfuncsLoaded=function() return true end
    env.isSampAvailable=function() return s.ready end
    env.sampAddChatMessage=function(text) s.messages[#s.messages+1]=text end
    env.getWorkingDirectory=function() return './moonloader' end
    env.isKeyDown=function(key) return s.keys[key] or false end
    env.isPauseMenuActive=function() return s.pause or false end
    env.isGameWindowForeground=function() return not s.background end
    env.sampIsChatInputActive=function() assert(s.ready); return s.chat or false end
    env.sampIsDialogActive=function() return s.dialog or false end
    env.sampIsLocalPlayerSpawned=function() return not s.unspawned end
    env.isSampfuncsConsoleActive=function() return s.console or false end
    env.isCharOnFoot=function() return not s.vehicle end
    env.getCurrentCharWeapon=function() return s.weapon end
    env.wait=function(ms) coroutine.yield(ms) end
    load_entry(env)
    s.thread=coroutine.create(env.main)
    s.tick=function() local ok,err=coroutine.resume(s.thread); assert(ok,err) end
    s.env=env
    return s
end
test('entrypoint starts OFF, Ctrl X enables real camera writes and disables again', function()
    local s=entry(); s.tick(); equal(s.env.version,'1.1.0'); equal(#s.writes,0)
    s.keys={[17]=true,[88]=true,[2]=true}; s.tick(); equal(#s.writes,1)
    s.tick(); equal(#s.writes,2)
    s.keys={[2]=true}; s.tick(); equal(#s.writes,3)
    s.keys={[17]=true,[88]=true,[2]=true}; s.tick(); equal(#s.writes,3)
    assert(table.concat(s.messages,'\n'):find('OFF',1,true))
end)
test('entrypoint releases camera for chat dialog pause console and lost focus', function()
    for _, field in ipairs({'chat','dialog','pause','console','background'}) do
        local s=entry(); s.tick(); s.keys={[17]=true,[88]=true,[2]=true}; s.tick()
        s.keys={[2]=true}; s[field]=true; s.tick(); equal(#s.writes,1)
        s[field]=false; s.tick(); equal(#s.writes,2)
    end
end)
test('entrypoint suppresses camera when not aiming, dead, in vehicle, wrong weapon or disconnected', function()
    for _, field in ipairs({'release','dead','vehicle','weapon','ready','unspawned'}) do
        local s=entry(); s.tick(); s.keys={[17]=true,[88]=true,[2]=true}; s.tick()
        s.keys={[2]=true}
        if field=='release' then s.keys={} elseif field=='dead' then s.dead[1]=true
        elseif field=='vehicle' then s.vehicle=true elseif field=='weapon' then s.weapon=34
        elseif field=='unspawned' then s.unspawned=true else s.ready=false end
        s.tick(); equal(#s.writes,1)
    end
end)
test('entrypoint reports missing APIs and missing INI without camera access', function()
    local s=entry(); s.env.setCameraPositionUnfixed=false; s.tick()
    equal(coroutine.status(s.thread),'dead'); assert(#s.logs>0)
    s=entry(); s.env.getWorkingDirectory=function() return './tests/missing-directory' end; s.tick()
    equal(coroutine.status(s.thread),'dead'); equal(#s.writes,0); assert(#s.logs>0)
end)

print(string.format('\n%d passed; %d failed',passed,failed))
if failed>0 then os.exit(1) end
