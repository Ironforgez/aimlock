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
local AimPoint = loader('AimLockDistribution.aim_point')
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
    equal(assert(Settings.load('./moonloader/config/AimLock1.2.0.ini')).enabled, false)
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
        screen={[2]={530,400},[3]={540,400}},writes={},messages={},logs={},keys={},ready=true,weapon=24,time=0}
    local api={PLAYER_PED=1}
    state.api=api
    api.doesCharExist=function(ped) return not state.gone[ped] end
    api.isCharDead=function(ped) return state.dead[ped] or false end
    api.sampGetPlayerIdByCharHandle=function(ped) return not state.npc[ped], ped+100 end
    api.sampIsPlayerNpc=function(id) return state.bots[id] or false end
    api.getCharCoordinates=function(ped) return unpack(assert(state.positions[ped])) end
    api.getAllChars=function() return {1,2,3} end
    api.convert3DCoordsToScreenEx=function(x)
        local id=math.abs(x-10)<1 and 2 or 3
        return not state.hidden[id], unpack(state.screen[id])
    end
    api.getGameTimer=function() return state.time end
    api.getOffsetFromCharInWorldCoords=function(ped,x,y,z)
        local position=state.positions[ped]
        state.last_offset={ped=ped,x=x,y=y,z=z}
        return position[1]+x,position[2]+y,position[3]+z
    end
    api.getScreenResolution=function() return 1000,1000 end
    api.getActiveCameraCoordinates=function() return 0,0,0 end
    api.getActiveCameraPointAt=function() return 1,0,0 end
    api.convertScreenCoordsToWorld3D=function() return 100,0,0 end
    api.isLineOfSightClear=function(_,_,_,x,_,_,buildings,vehicles,actors,objects,particles)
        equal(buildings,true); equal(vehicles,true); equal(actors,false); equal(objects,true); equal(particles,false)
        return not state.walls[x]
    end
    api.setCameraPositionUnfixed=function(pitch,yaw) state.writes[#state.writes+1]={pitch,yaw} end
    state.world=World.new(assert(Settings.validate({random_aim=false})),api)
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
    local s=entry(); s.tick(); equal(s.env.version,'1.2.0'); equal(#s.writes,0)
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

local function point_settings(values)
    values=values or {}
    values.random_seed=12345
    return assert(Settings.validate(values))
end
test('random defaults match legacy INI weights and distribution snapshots are independent', function()
    local settings=assert(Settings.load('./moonloader/config/AimLock1.2.0.ini'))
    equal(settings.random_aim,true); equal(settings.random_interval_ms,300)
    local expected={torso=20,left_arm=20,right_arm=20,left_leg=15,right_leg=15,head=10}
    for key,value in pairs(expected) do equal(settings.distribution[key],value) end
    settings.distribution.head=100
    equal(Settings.validate({}).distribution.head,10)
end)
test('random settings reject invalid weights intervals seeds and unknown sections', function()
    local bad=point_settings(); bad.distribution.head=0
    equal(Settings.validate(bad),nil)
    bad=point_settings(); bad.distribution.left_arm=-1; equal(Settings.validate(bad),nil)
    for _,value in ipairs({0,99,5001,100.5,math.huge,0/0}) do
        equal(Settings.validate({random_interval_ms=value}),nil)
    end
    equal(Settings.validate({random_aim='true'}),nil)
    equal(Settings.validate({random_seed=0}),nil)
    equal(Settings.parse('[aimlock]\ndistribution=1'),nil)
    equal(Settings.parse('[aimlock]\n[distribution]\nhead=100'),nil)
    equal(Settings.parse('[aimlock]\n[distribution]\n[distribution]'),nil)
end)
test('INI loads complete distribution and reproducible random seed', function()
    local settings=assert(Settings.parse('[aimlock]\nrandom_seed=12345\nrandom_interval_ms=500\n'
        ..'[distribution]\ntorso=0\nleft_arm=0\nright_arm=0\nleft_leg=0\nright_leg=0\nhead=100'))
    equal(settings.distribution.head,100); equal(settings.random_seed,12345)
    equal(settings.random_interval_ms,500)
end)
test('body selections follow weighted boundaries and exclude zero weights', function()
    local expected={{0,'torso'},{0.19999,'torso'},{0.2,'left_arm'},{0.4,'right_arm'},
        {0.6,'left_leg'},{0.75,'right_leg'},{0.9,'head'},{0.99999,'head'}}
    for _,item in ipairs(expected) do
        local sampler=assert(AimPoint.new(point_settings(),function() return item[1] end))
        equal(assert(sampler:select({ped=2,id=102},0)).key,item[2])
    end
    local settings=point_settings()
    for key in pairs(settings.distribution) do settings.distribution[key]=key=='head' and 100 or 0 end
    local sampler=assert(AimPoint.new(settings,function() return 0 end))
    for time=0,1000,100 do equal(assert(sampler:select({ped=2,id=102},time)).key,'head') end
end)
test('same player stays locked while body point changes only when interval expires', function()
    local calls=0
    local sampler=assert(AimPoint.new(point_settings(),function()
        calls=calls+1; return calls==1 and 0 or 0.99
    end))
    for _,time in ipairs({0,1,100,299}) do
        equal(assert(sampler:select({ped=2,id=102},time)).key,'torso')
    end
    equal(calls,1)
    equal(assert(sampler:select({ped=2,id=102},300)).key,'head'); equal(calls,2)
end)
test('target identity change reset and unsigned timer rollover resample correctly', function()
    local calls=0
    local sampler=assert(AimPoint.new(point_settings(),function() calls=calls+1; return 0 end))
    assert(sampler:select({ped=2,id=102},4294967200))
    assert(sampler:select({ped=2,id=102},199)); equal(calls,1)
    assert(sampler:select({ped=2,id=102},204)); equal(calls,2)
    assert(sampler:select({ped=2,id=103},205)); equal(calls,3)
    sampler:reset(); assert(sampler:select({ped=2,id=103},206)); equal(calls,4)
    equal(sampler:select({ped=2,id=103},math.huge),nil)
end)
test('random body points alter actual camera pitch without switching player', function()
    local s=scene(); local calls=0
    s.world=World.new(point_settings(),s.api,function() calls=calls+1; return calls==1 and 0 or 0.99 end)
    local target=assert(s.world:find_target())
    assert(s.world:point_at(target)); equal(target.body_part,'torso')
    s.time=300; target=assert(s.world:validate_target(target))
    assert(s.world:point_at(target)); equal(target.body_part,'head'); equal(target.ped,2)
    near(s.writes[1][1],math.atan(0.3/10)); near(s.writes[2][1],math.atan(0.8/10))
    s.screen[2]={900,900}
    assert(s.world:validate_target(target),'Locked target must survive random aim moving the anchor out of acquisition FOV')
    equal(s.world:validate_target({ped=2}),nil)
end)
test('left and right body points use ped-local offsets and stay stable between draws', function()
    for _,item in ipairs({{0.2,-0.28},{0.4,0.28},{0.6,-0.15},{0.75,0.15}}) do
        local s=scene(); s.world=World.new(point_settings(),s.api,function() return item[1] end)
        local target=assert(s.world:find_target()); assert(s.world:point_at(target))
        near(s.last_offset.x,item[2]); equal(s.last_offset.ped,2)
    end
end)
test('an occluded selected body point does not release the locked player', function()
    local s=scene(); s.world=World.new(point_settings(),s.api,function() return 0.99 end)
    local controller=Controller.new({enabled=true},{on_toggle=function() end,
        find_target=function() return s.world:find_target() end,
        validate_target=function(target) return s.world:validate_target(target) end,
        point_at=function(target) return s.world:point_at(target) end})
    local line_of_sight=s.api.isLineOfSightClear
    s.api.isLineOfSightClear=function(a,b,c,x,y,z,...)
        if z>0.7 then return false end
        return line_of_sight(a,b,c,x,y,z,...)
    end
    equal(controller:step({aiming=true,blocked=false,ctrl=false,x=false}),false)
    equal(assert(controller.target).ped,2); equal(#s.writes,0)
    equal(controller:step({aiming=true,blocked=false,ctrl=false,x=false}),false)
    equal(controller.target.ped,2)
end)
test('entrypoint resets selection after release and OFF stops writes with random aim active', function()
    local s=entry(); s.tick(); s.keys={[17]=true,[88]=true,[2]=true}; s.tick()
    equal(#s.writes,1); assert(s.last_offset)
    s.keys={}; s.tick(); equal(#s.writes,1)
    s.time=1000; s.keys={[2]=true}; s.tick(); equal(#s.writes,2)
    s.keys={[17]=true,[88]=true,[2]=true}; s.tick(); equal(#s.writes,2)
    assert(table.concat(s.messages,'\n'):find('Random aim: ON',1,true))
end)

print(string.format('\n%d passed; %d failed',passed,failed))
if failed>0 then os.exit(1) end
