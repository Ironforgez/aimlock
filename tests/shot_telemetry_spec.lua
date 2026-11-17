package.path='./moonloader/lib/?.lua;'..package.path
local release=arg and arg[1]
local expected_version=release and release:match('AimLock(%d+%.%d+%.%d+)%.lua') or '1.5.0'
local entrypoint=release or './moonloader/AimLock.lua'
local function load_entry(env)
    env._G=env
    env.script_name=function() end; env.script_author=function() end
    env.script_version=function(version) env.version=version end; env.script_description=function() end
    local chunk=assert(loadfile(entrypoint)); setfenv(chunk,env); return chunk()
end
local loader=require
if release then
    loader=assert(load_entry(setmetatable({require=function() error('External module requested') end},{__index=_G})))
end
local Settings=loader('AimLockDistribution.settings')
local Telemetry=loader('AimLockDistribution.telemetry')
local Observer=loader('AimLockDistribution.telemetry_observer')
local Journal=loader('AimLockDistribution.telemetry_journal')
local Runtime=loader('AimLockDistribution.telemetry_runtime')
local World=loader('AimLockDistribution.world')
local passed,failed=0,0
local function equal(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local function near(a,b) assert(math.abs(a-b)<0.00001,tostring(a)..' != '..tostring(b)) end
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passed=passed+1; print('PASS '..name)
    else failed=failed+1; print('FAIL '..name..': '..tostring(err)) end
end
local function copy(value)
    if type(value)~='table' then return value end
    local result={}; for key,item in pairs(value) do result[key]=copy(item) end; return result
end
local function fixture(options)
    options=options or {}
    local state={events={},writes=0,errors=0}
    state.settings=assert(Settings.validate({telemetry_match_window_ms=300,telemetry_flush_interval_ms=100}))
    state.telemetry=Telemetry.new(state.settings,{start_ms=options.start_ms or 0,session_id='test-session',
        write_batch=options.writer or function(events)
            state.writes=state.writes+1
            for _,event in ipairs(events) do state.events[#state.events+1]=copy(event) end
            return true
        end,on_error=function() state.errors=state.errors+1 end})
    state.flush=function() assert(state.telemetry:flush()) end
    return state
end
local function events(state,name)
    local result={}; for _,event in ipairs(state.events) do if event.event==name then result[#result+1]=event end end
    return result
end
local function bullet(id,weapon,kind)
    return {target_type=kind or 1,target_id=id or 7,weapon_id=weapon or 24,
        origin={x=0,y=0,z=1},hit_position={x=10,y=0,z=0.8},offset={x=0,y=0,z=0.5}}
end
local function context()
    return {locked_player_id=7,snapshot_target_id=7,selected_body_part='left_arm',
        selected_point={x=9.72,y=0,z=0.25},aim_applied=true,context_game_ms=90,aimlock_enabled=true}
end
local function damage(id,weapon,part)
    return {player_id=id or 7,weapon_id=weapon or 24,body_part=part or 9,amount=46.2}
end

test('telemetry configuration defaults and bounds are validated',function()
    local settings=assert(Settings.validate({})); equal(settings.telemetry_enabled,true)
    equal(settings.telemetry_match_window_ms,750); equal(settings.telemetry_flush_interval_ms,1000)
    for _,values in ipairs({{telemetry_enabled=1},{telemetry_match_window_ms=49},
        {telemetry_match_window_ms=3001},{telemetry_match_window_ms=100.5},
        {telemetry_flush_interval_ms=99},{telemetry_flush_interval_ms=10001},
        {telemetry_flush_interval_ms=0/0}}) do equal(Settings.validate(values),nil) end
    equal(assert(Settings.parse('[aimlock]\ntelemetry_enabled=false')).telemetry_enabled,false)
end)
test('shot preserves immutable selected point separately from reported hit fields',function()
    local s=fixture(); local planned=context(); local report=bullet()
    equal(s.telemetry:record_shot(report,planned,100),1)
    planned.selected_point.x=99; report.hit_position.x=99; s.flush()
    local row=events(s,'shot')[1]
    equal(row.selected_body_part,'left_arm'); near(row.selected_point.x,9.72)
    equal(row.reported_hit_position.x,10); equal(row.locked_player_id,7)
    equal(row.reported_hit_id,7); equal(row.context_age_ms,10)
    equal(row.server_status,'unknown'); equal(row.reported_body_part,nil)
end)
test('OFF and stale target snapshots log unknown selection rather than invent a result',function()
    local s=fixture(); s.telemetry:record_shot(bullet(),{aimlock_enabled=false},10)
    local stale=context(); stale.snapshot_target_id=8
    s.telemetry:record_shot(bullet(),stale,20); s.flush()
    for _,row in ipairs(events(s,'shot')) do equal(row.selected_body_part,'unknown'); equal(row.aim_applied,false) end
end)
test('damage bodypart is client evidence and unique matching remains a temporal candidate',function()
    local s=fixture(); s.telemetry:record_shot(bullet(),context(),100)
    s.telemetry:record_damage(damage(),110); s.flush()
    local row=events(s,'damage_report')[1]
    equal(row.reported_body_part,'head'); equal(row.reported_body_part_id,9)
    equal(row.source,'outgoing_give_damage_rpc'); equal(row.server_status,'unknown')
    local link=events(s,'correlation_update')[1]
    equal(link.association,'temporal_candidate'); equal(link.candidate_shot_ids[1],1)
    equal(events(s,'shot')[1].selected_body_part,'left_arm')
end)
test('reverse event order is retained and associated when bullet arrives later',function()
    local s=fixture(); s.telemetry:record_damage(damage(),100)
    s.telemetry:record_shot(bullet(),context(),105); s.flush()
    equal(#events(s,'damage_report'),1); equal(events(s,'correlation_update')[1].candidate_count,1)
end)
test('rapid fire retains ambiguity and later candidates cannot erase previous candidates',function()
    local s=fixture(); s.telemetry:record_shot(bullet(),context(),100)
    s.telemetry:record_damage(damage(),110)
    s.telemetry:record_shot(bullet(),context(),120); s.flush()
    local links=events(s,'correlation_update'); equal(#links,2)
    equal(links[2].association,'ambiguous'); equal(links[2].candidate_count,2)
    equal(links[2].candidate_shot_ids[1],1); equal(links[2].candidate_shot_ids[2],2)
end)
test('wrong target weapon vehicle hit and no-hit do not acquire a damage association',function()
    local s=fixture()
    s.telemetry:record_shot(bullet(8),context(),100)
    s.telemetry:record_shot(bullet(7,22),context(),101)
    s.telemetry:record_shot(bullet(7,24,2),context(),102)
    s.telemetry:record_shot(bullet(7,24,0),context(),103)
    s.telemetry:record_damage(damage(),110); s.flush()
    equal(#events(s,'correlation_update'),0)
end)
test('timeout means no correlated report and never a confirmed miss',function()
    local s=fixture(); s.telemetry:record_shot(bullet(),context(),0)
    s.telemetry:poll(301)
    equal(events(s,'shot_window_closed')[1].result,'no_correlated_damage_report')
    equal(events(s,'shot_window_closed')[1].server_status,'unknown')
    s.telemetry:record_damage(damage(),302); s.telemetry:close()
    equal(events(s,'damage_window_closed')[1].association,'unmatched')
end)
test('game timer rollover preserves time-window matching and context age',function()
    local s=fixture({start_ms=4294967290}); local planned=context(); planned.context_game_ms=-10
    s.telemetry:record_shot(bullet(),planned,-6); s.telemetry:record_damage(damage(),10); s.flush()
    equal(events(s,'shot')[1].context_age_ms,4); equal(#events(s,'correlation_update'),1)
end)
test('invalid reports are rejected before appending diagnostic events',function()
    local s=fixture(); local bad=damage(); bad.amount=math.huge
    equal(s.telemetry:record_damage(bad,0),nil)
    bad=bullet(); bad.weapon_id=-1; equal(s.telemetry:record_shot(bad,{},0),nil)
    s.flush(); equal(#events(s,'shot'),0); equal(#events(s,'damage_report'),0)
end)
test('event and pending buffers are bounded and overflow is visible',function()
    local s=fixture()
    for _=1,400 do assert(s.telemetry:record_shot(bullet(),context(),0)) end
    for _=1,150 do assert(s.telemetry:record_damage(damage(99),0)) end
    assert(#s.telemetry.queue<=256); assert(#s.telemetry.shots<=128); assert(#s.telemetry.reports<=128)
    s.flush(); assert(events(s,'telemetry_overflow')[1].dropped_events>0)
end)
test('network recording performs no file writes and poll flushes buffered batches',function()
    local s=fixture(); s.telemetry:record_shot(bullet(),context(),10)
    s.telemetry:record_damage(damage(),11); equal(s.writes,0)
    s.telemetry:poll(99); equal(s.writes,0)
    s.telemetry:poll(100); equal(s.writes,1)
end)
test('candidate histories remain bounded across repeated pending-buffer eviction',function()
    local s=fixture(); s.telemetry:record_shot(bullet(),context(),0)
    for _=1,400 do assert(s.telemetry:record_damage(damage(),0)) end
    local first_shot=s.telemetry.shots[1]
    equal(#first_shot.report_ids,128); equal(first_shot.reports_truncated,true)
    for _=1,400 do assert(s.telemetry:record_shot(bullet(),context(),0)) end
    for _,report in ipairs(s.telemetry.reports) do
        equal(#report.candidates,128); equal(report.candidates_truncated,true)
        local keys=0; for _ in pairs(report.candidate_set) do keys=keys+1 end; equal(keys,128)
    end
    for _,shot in ipairs(s.telemetry.shots) do assert(#shot.report_ids<=128) end
end)
test('writer failure disables only telemetry and is reported once',function()
    local calls=0; local s=fixture({writer=function() calls=calls+1; return nil,'disk full' end})
    equal(s.telemetry:flush(),nil); equal(s.telemetry:is_active(),false)
    s.telemetry:poll(1000); s.telemetry:record_shot(bullet(),{},1001)
    equal(calls,1); equal(s.errors,1)
end)
test('shutdown flushes pending windows and is idempotent',function()
    local s=fixture(); s.telemetry:record_shot(bullet(),context(),0)
    s.telemetry:close(); s.telemetry:close()
    equal(#events(s,'session_end'),1); equal(s.writes,1)
    equal(events(s,'shot_window_closed')[1].reason,'session_ended')
end)

-- This fixture serializes real little-endian bytes and bit-aligned RPC fields.
local function bitstream()
    local bs={bits={},read_offset=0,write_offset=0}
    bs.bit=function(value) bs.bits[#bs.bits+1]=value and 1 or 0; bs.write_offset=#bs.bits end
    bs.byte=function(value) for power=7,0,-1 do bs.bit(math.floor(value/2^power)%2==1) end end
    bs.uint=function(value,size) for _=1,size do bs.byte(value%256); value=math.floor(value/256) end end
    bs.float=function(value)
        if value==0 then bs.uint(0,4); return end
        local sign=value<0 and 2147483648 or 0; value=math.abs(value)
        local mantissa,exponent=math.frexp(value)
        local fraction=math.floor((mantissa*2-1)*8388608+0.5)
        bs.uint(sign+(exponent+126)*8388608+fraction,4)
    end
    return bs
end
local function bullet_stream()
    local bs=bitstream(); bs.uint(206,1); bs.uint(1,1); bs.uint(7,2)
    for _,value in ipairs({0,0,1,10,0,0.8,0,0,0.5}) do bs.float(value) end
    bs.uint(24,1); return bs
end
local function damage_stream(taking)
    local bs=bitstream(); bs.bit(taking); bs.uint(7,2); bs.float(46.2)
    bs.uint(24,4); bs.uint(9,4); return bs
end
local function native_fixture()
    local state={handlers={},time=100,reads=0,opened=0,output={},encoded={},logs={}}
    local function read_unsigned(bs,count)
        local value=0
        for index=0,count-1 do
            local byte=0
            for _=1,8 do
                assert(bs.read_offset<#bs.bits,'Read past payload')
                bs.read_offset=bs.read_offset+1; byte=byte*2+bs.bits[bs.read_offset]
            end
            value=value+byte*256^index
        end
        state.reads=state.reads+1; return value
    end
    local function signed(value,bits) return value>=2^(bits-1) and value-2^bits or value end
    local api={}
    api.addEventHandler=function(name,fn) state.handlers[name]=fn end
    api.getGameTimer=function() return state.time end
    api.raknetBitStreamGetReadOffset=function(bs) return bs.read_offset end
    api.raknetBitStreamSetReadOffset=function(bs,value) bs.read_offset=value end
    api.raknetBitStreamGetNumberOfBitsUsed=function(bs) return #bs.bits end
    api.raknetBitStreamReadBool=function(bs) bs.read_offset=bs.read_offset+1; return bs.bits[bs.read_offset]==1 end
    api.raknetBitStreamReadInt8=function(bs) return signed(read_unsigned(bs,1),8) end
    api.raknetBitStreamReadInt16=function(bs) return signed(read_unsigned(bs,2),16) end
    api.raknetBitStreamReadInt32=function(bs) return signed(read_unsigned(bs,4),32) end
    api.raknetBitStreamReadFloat=function(bs)
        local value=read_unsigned(bs,4); local sign=value>=2147483648 and -1 or 1
        local exponent=math.floor(value/8388608)%256; local fraction=value%8388608
        if exponent==0 then return sign*fraction*2^-149 end
        if exponent==255 then return fraction==0 and sign*math.huge or 0/0 end
        return sign*(1+fraction/8388608)*2^(exponent-127)
    end
    api.getWorkingDirectory=function() return './moonloader' end
    api.doesDirectoryExist=function() return true end
    api.createDirectory=function() error('Existing directory must not be recreated') end
    api.encodeJson=function(event)
        state.encoded[#state.encoded+1]=copy(event)
        return '{"event":"'..event.event..'"}'
    end
    api.print=function(text) state.logs[#state.logs+1]=text end
    state.files={open=function(path,mode)
        equal(mode,'ab'); assert(path:find('/logs/AimLock1.',1,true)); state.opened=state.opened+1
        return {write=function(self,value) state.output[#state.output+1]=value; return self end,
            close=function() return true end}
    end}
    state.api=api
    return state
end
local function assert_unchanged(bs,original,offset)
    equal(table.concat(bs.bits,''),original); equal(bs.read_offset,offset); equal(bs.write_offset,#bs.bits)
end
test('native BulletSync observer decodes bytes and restores cursor without network return values',function()
    local native=native_fixture(); local s=fixture()
    assert(Observer.attach(native.api,s.telemetry,context))
    local bs=bullet_stream(); bs.read_offset=17; local original=table.concat(bs.bits,'')
    equal(native.handlers.onSendPacket(206,bs),nil); assert_unchanged(bs,original,17)
    s.flush(); local row=events(s,'shot')[1]
    equal(row.weapon_id,24); equal(row.reported_hit_id,7); near(row.reported_hit_position.z,0.8)
    equal(native.opened,0)
end)
test('unaligned GiveDamage observer reads bodypart and ignores TakeDamage',function()
    local native=native_fixture(); local s=fixture(); assert(Observer.attach(native.api,s.telemetry,context))
    local bs=damage_stream(false); equal(#bs.bits,113); bs.read_offset=9
    local original=table.concat(bs.bits,'')
    equal(native.handlers.onSendRpc(115,bs),nil); assert_unchanged(bs,original,9)
    bs=damage_stream(true); equal(native.handlers.onSendRpc(115,bs),nil); equal(bs.read_offset,0)
    s.flush(); equal(#events(s,'damage_report'),1)
    local row=events(s,'damage_report')[1]; equal(row.reported_body_part_id,9); near(row.reported_amount,46.2)
end)
test('malformed payload and decode failure preserve cursor and never suppress packets',function()
    local native=native_fixture(); local s=fixture(); assert(Observer.attach(native.api,s.telemetry,context))
    local bs=bullet_stream(); table.remove(bs.bits); bs.write_offset=#bs.bits; bs.read_offset=7
    local original=table.concat(bs.bits,''); equal(native.handlers.onSendPacket(206,bs),nil)
    assert_unchanged(bs,original,7)
    bs=bullet_stream(); bs.read_offset=5; original=table.concat(bs.bits,'')
    native.api.raknetBitStreamReadFloat=function() error('Injected decoder failure') end
    equal(native.handlers.onSendPacket(206,bs),nil); assert_unchanged(bs,original,5)
    s.flush(); equal(#events(s,'observer_error'),2); equal(#events(s,'shot'),0)
end)
test('unrelated traffic and closed telemetry do not read bitstream data',function()
    local native=native_fixture(); local s=fixture(); assert(Observer.attach(native.api,s.telemetry,context))
    equal(native.handlers.onSendPacket(207,bullet_stream()),nil)
    equal(native.handlers.onSendRpc(101,damage_stream(false)),nil); equal(native.reads,0)
    s.telemetry:close(); equal(native.handlers.onSendPacket(206,bullet_stream()),nil); equal(native.reads,0)
end)
test('missing APIs and partial event registration do not activate an observer',function()
    local native=native_fixture(); local s=fixture(); native.api.raknetBitStreamReadBool=nil
    equal(Observer.attach(native.api,s.telemetry,context),nil); equal(next(native.handlers),nil)
    native=native_fixture(); local first
    native.api.addEventHandler=function(name,fn) if name=='onSendPacket' then first=fn else error('Cannot attach') end end
    equal(Observer.attach(native.api,s.telemetry,context),nil)
    equal(first(206,bullet_stream()),nil); equal(native.reads,0)
end)
test('journal appends JSON Lines and serializer failure occurs before opening a file',function()
    local native=native_fixture(); local journal=assert(Journal.new(native.api,'1.3.0',native.files))
    assert(journal:append({{event='one'},{event='two'}}))
    equal(native.output[1],'{"event":"one"}\n{"event":"two"}\n')
    equal(native.opened,1)
    journal.encode=function() error('Bad JSON') end
    equal(journal:append({{event='bad'}}),nil); equal(native.opened,1)
end)
test('journal closes file even after a thrown write error',function()
    local native=native_fixture(); local closed=0
    local files={open=function() return {write=function() error('Disk failure') end,
        close=function() closed=closed+1; return true end} end}
    local journal=assert(Journal.new(native.api,'1.3.0',files))
    equal(journal:append({{event='one'}}),nil); equal(closed,1)
end)
test('runtime requires no external library and disabled or unavailable telemetry performs no I/O',function()
    local native=native_fixture(); local settings=assert(Settings.validate({telemetry_enabled=false}))
    equal(Runtime.start(settings,native.api,context,native.files),nil); equal(native.opened,0)
    settings=assert(Settings.validate({})); native.api.encodeJson=nil
    equal(Runtime.start(settings,native.api,context,native.files),nil); equal(native.opened,0)
    equal(next(native.handlers),nil)
end)
test('runtime buffers native events until poll and cleans up on close',function()
    local native=native_fixture()
    local runtime=assert(Runtime.start(assert(Settings.validate({})),native.api,context,native.files))
    equal(native.handlers.onSendPacket(206,bullet_stream()),nil)
    equal(native.handlers.onSendRpc(115,damage_stream(false)),nil); equal(native.opened,0)
    runtime:poll(1200); equal(native.opened,1)
    runtime:close(); equal(native.opened,2); equal(runtime:is_active(),false)
end)

test('reconfiguring telemetry reuses observers and separates journal sessions',function()
    local native=native_fixture(); local registrations=0; local register=native.api.addEventHandler
    native.api.addEventHandler=function(...) registrations=registrations+1; return register(...) end
    local manager=Runtime.manager(native.api,context,native.files)
    local settings=assert(Settings.validate({}))
    local first=assert(manager:configure(settings)); local packet=native.handlers.onSendPacket
    local rpc=native.handlers.onSendRpc
    native.handlers.onSendPacket(206,bullet_stream()); manager:poll(1500)
    local second=assert(manager:configure(settings))
    equal(first.closed,true); assert(first.log_path~=second.log_path)
    equal(native.handlers.onSendPacket,packet); equal(native.handlers.onSendRpc,rpc); equal(registrations,2)
    native.handlers.onSendPacket(206,bullet_stream()); equal(second.shot_id,1)
    settings.telemetry_enabled=false; manager:configure(settings); equal(second.closed,true)
    local reads=native.reads; native.handlers.onSendPacket(206,bullet_stream()); equal(native.reads,reads)
    settings.telemetry_enabled=true; local third=assert(manager:configure(settings))
    equal(registrations,2); native.handlers.onSendPacket(206,bullet_stream()); equal(third.shot_id,1)
    manager:close(); manager:close(); equal(third.closed,true)
end)

test('main connects tracking distribution and telemetry and records baseline shots after Alt X OFF',function()
    local native=native_fixture(); local api=native.api; local camera_writes=0; native.keys={}
    api.getWorkingDirectory=function() return './releases/'..expected_version end
    api.PLAYER_PED=1
    for _,name in ipairs({'isSampLoaded','isSampfuncsLoaded','isSampAvailable','isGameWindowForeground',
        'sampIsLocalPlayerSpawned','doesCharExist','isCharOnFoot','isLineOfSightClear'}) do api[name]=function() return true end end
    for _,name in ipairs({'isPauseMenuActive','sampIsChatInputActive','sampIsDialogActive',
        'isSampfuncsConsoleActive','isCharDead'}) do api[name]=function() return false end end
    api.isKeyDown=function(key) return native.keys[key] or false end
    api.getCurrentCharWeapon=function() return 24 end
    api.sampGetPlayerIdByCharHandle=function(ped) return ped==2,7 end
    api.sampIsPlayerNpc=function() return false end
    api.getAllChars=function() return {1,2} end
    api.getCharCoordinates=function(ped) return ped==1 and 0 or 10,0,0 end
    api.getOffsetFromCharInWorldCoords=function(_,x,y,z) return 10+x,y,z end
    api.convert3DCoordsToScreenEx=function() return true,530,400 end
    api.getScreenResolution=function() return 1000,1000 end
    api.getActiveCameraCoordinates=function() return 0,0,0 end
    api.getActiveCameraPointAt=function() return 1,0,0 end
    api.convertScreenCoordsToWorld3D=function() return 100,0,0 end
    api.setCameraPositionUnfixed=function() camera_writes=camera_writes+1 end
    api.sampAddChatMessage=function() end
    api.wait=function(ms) coroutine.yield(ms) end
    setmetatable(api,{__index=_G}); load_entry(api)
    local original_open=io.open
    io.open=function(path,mode) if mode=='rb' then return original_open(path,mode) end return native.files.open(path,mode) end
    local ok,err=pcall(function()
        local thread=coroutine.create(api.main)
        local function tick() local resumed,message=coroutine.resume(thread); assert(resumed,message) end
        tick(); equal(api.version,expected_version); equal(native.opened,0)
        native.keys={[18]=true,[88]=true,[2]=true}; native.time=110; tick(); equal(camera_writes,1)
        equal(native.handlers.onSendPacket(206,bullet_stream()),nil)
        native.keys={}; native.time=120; tick()
        native.keys={[18]=true,[88]=true,[2]=true}; native.time=130; tick(); equal(camera_writes,1)
        equal(native.handlers.onSendPacket(206,bullet_stream()),nil)
        native.time=1500; tick(); api.onExitScript()
        local shots={}
        for _,event in ipairs(native.encoded) do if event.event=='shot' then shots[#shots+1]=event end end
        equal(#shots,2); equal(shots[1].aimlock_enabled,true); equal(shots[1].locked_player_id,7)
        assert(shots[1].selected_body_part~='unknown'); equal(shots[1].aim_applied,true)
        equal(shots[2].aimlock_enabled,false); equal(shots[2].selected_body_part,'unknown')
    end)
    io.open=original_open; assert(ok,err)
end)

print(string.format('\n%d passed; %d failed',passed,failed))
if failed>0 then os.exit(1) end
