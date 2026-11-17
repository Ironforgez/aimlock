package.path='./moonloader/lib/?.lua;'..package.path
local release=arg and arg[1]
local loader=require
if release then
    local env=setmetatable({},{__index=_G}); env._G=env
    for _,name in ipairs({'script_name','script_author','script_version','script_description'}) do env[name]=function() end end
    local chunk=assert(loadfile(release)); setfenv(chunk,env); loader=assert(chunk())
end
local Settings=loader('AimLockDistribution.settings')
local Store=loader('AimLockDistribution.config_store')
local Model=loader('AimLockDistribution.gui_model')
local View=loader('AimLockDistribution.log_view')
local Gui=loader('AimLockDistribution.gui')
local Runtime=loader('AimLockDistribution.gui_runtime')
local Identity=loader('AimLockDistribution.identity')
local fake_gui=assert(loadfile('tests/gui_fixture.lua'))()
local passed,failed=0,0
local function equal(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local function test(name,fn)
    local ok,err=pcall(fn)
    if ok then passed=passed+1; print('PASS '..name) else failed=failed+1; print('FAIL '..name..': '..tostring(err)) end
end
local function memory_files(initial)
    local state={data=initial or {},writes=0,replaces=0,closed=0}
    state.files={open=function(path,mode)
        if state.fail_open==path then return nil,'denied' end
        if mode=='rb' and not state.data[path] then return nil,'missing' end
        if mode=='wb' then state.data[path]='' end
        local offset=0
        return {read=function(_,count)
            if count=='*a' then return state.data[path] end
            local result=state.data[path]:sub(offset+1,offset+count); offset=offset+#result
            if result=='' then return nil end; return result
        end,seek=function(_,kind,value)
            if kind=='end' then offset=#state.data[path] else offset=value end; return offset
        end,write=function(self,text)
            state.writes=state.writes+1
            if state.fail_write==path then error('disk full') end
            state.data[path]=text; return self
        end,close=function() state.closed=state.closed+1; return not state.fail_close end}
    end}
    state.replace=function(from,to)
        state.replaces=state.replaces+1
        if state.fail_replace==to then return nil,'locked' end
        state.data[to]=state.data[from]; state.data[from]=nil; return true
    end
    state.remove=function(path) state.data[path]=nil end
    return state
end
test('single panel command validates and legacy command settings migrate',function()
    local config=assert(Settings.validate({gui_command='arfie_cfg'}))
    local serialized=assert(Store.serialize(config)); local parsed=assert(Settings.parse(serialized))
    equal(parsed.gui_command,'arfie_cfg'); equal(parsed.gui_enabled,true)
    equal(Store.serialize(parsed),serialized)
    for _,values in ipairs({{gui_enabled=1},{gui_command='BAD'},{gui_command='/aim'},
        {gui_command=''},{gui_command=string.rep('a',21)}}) do equal(Settings.validate(values),nil) end
    local old=assert(Settings.parse('[aimlock]\ngui_command=aimlock\ngui_log_command=aimlog'))
    equal(old.gui_command,'apanel'); equal(old.gui_log_command,nil)
    assert(not Store.serialize(old):find('gui_log_command',1,true))
end)
test('atomic save writes a backup and never replaces original before complete writes',function()
    local fs=memory_files({['config.ini']='old-content'})
    assert(Store.save('config.ini',{},fs.replace,fs.files,fs.remove))
    equal(fs.data['config.ini.bak'],'old-content'); assert(Settings.parse(fs.data['config.ini']))
    equal(fs.data['config.ini.tmp'],nil); equal(fs.replaces,2); equal(fs.closed,3)
end)
test('save failures at temporary write backup and replacement preserve original',function()
    for _,failure in ipairs({'temp_open','temp_write','backup_write','backup_replace','replace','close'}) do
        local fs=memory_files({['config.ini']='original'})
        if failure=='temp_open' then fs.fail_open='config.ini.tmp'
        elseif failure=='temp_write' then fs.fail_write='config.ini.tmp'
        elseif failure=='backup_write' then fs.fail_write='config.ini.bak.tmp'
        elseif failure=='backup_replace' then fs.fail_replace='config.ini.bak'
        elseif failure=='replace' then fs.fail_replace='config.ini' else fs.fail_close=true end
        local ok,err=Store.save('config.ini',{},fs.replace,fs.files,fs.remove)
        equal(ok,nil); assert(type(err)=='string'); equal(fs.data['config.ini'],'original')
        equal(fs.data['config.ini.tmp'],nil)
    end
end)
test('invalid settings unavailable replacement and missing original perform no writes',function()
    local fs=memory_files()
    equal(Store.save('missing',{max_distance=-1},fs.replace,fs.files,fs.remove),nil)
    equal(Store.save('missing',{},nil,fs.files,fs.remove),nil)
    equal(Store.save('missing',{},fs.replace,fs.files,fs.remove),nil); equal(fs.writes,0)
end)
local function model_fixture()
    local state={applied=0,saves=0}
    state.model=Model.new(assert(Settings.validate({})),{
        load=function() if state.load_error then return nil,'bad INI' end return Settings.validate({max_distance=75}) end,
        save=function() state.saves=state.saves+1; if state.save_error then return nil,'locked' end return true end,
        apply=function(values) state.applied=state.applied+1; state.active=values; return true end})
    return state
end
test('draft apply and save keep current and saved states separate',function()
    local s=model_fixture(); local m=s.model
    m.draft.max_distance=80; equal(m:state(),true); equal(s.applied,0)
    m:request('apply'); m:poll(); equal(s.applied,1); equal(m.current.max_distance,80)
    local dirty,unsaved=m:state(); equal(dirty,false); equal(unsaved,true); equal(s.saves,0)
    m:request('save'); m:poll(); dirty,unsaved=m:state(); equal(dirty,false); equal(unsaved,false); equal(s.saves,1)
end)
test('invalid probabilities and save failure leave active configuration untouched',function()
    local s=model_fixture(); local m=s.model
    m.draft.distribution.head=-10; m:request('save'); m:poll(); equal(s.saves,0); equal(s.applied,0)
    m.draft=assert(Settings.validate({max_distance=80})); s.save_error=true
    m:request('save'); m:poll(); equal(s.applied,0); equal(m.current.max_distance,60)
    assert(m.message:find('Gagal menyimpan',1,true))
end)
test('reload defaults discard and failed load never silently apply',function()
    local s=model_fixture(); local m=s.model
    m:request('reload'); m:poll(); equal(m.draft.max_distance,75); equal(m.current.max_distance,60)
    m:request('defaults'); m:poll(); equal(m.draft.max_distance,60)
    m.draft.max_distance=90; m:request('discard'); m:poll(); equal(m.draft.max_distance,60)
    s.load_error=true; m:request('reload'); m:poll(); assert(m.message:find('bad INI',1,true)); equal(s.applied,0)
end)
local function decoder(raw)
    if raw=='bad' then error('invalid JSON') end
    if raw=='scalar' then return 1 end
    local event,id=raw:match('^(%a+):(%d+)$')
    if not event then error('invalid') end
    return {event=event,game_ms=10,reported_hit_id=tonumber(id),selected_body_part='torso',server_status='unknown'}
end
test('incremental log parsing waits for complete lines without duplicates',function()
    local fs=memory_files({log='shot:7\ndamage:'}); local view=View.new(decoder,fs.files)
    view:select('log'); view:poll(); equal(#view.rows,1); equal(view.tail,'damage:')
    fs.data.log=fs.data.log..'7\n'; view:poll(); equal(#view.rows,2); view:poll(); equal(#view.rows,2)
    equal(view.rows[2].data.event,'damage')
end)
test('log reader skips malformed scalar and oversized lines and bounds history',function()
    local fs=memory_files({log='bad\nscalar\n'..string.rep('x',70000)..'\n'..string.rep('shot:7\n',1100)})
    local view=View.new(decoder,fs.files); view:select('log')
    for _=1,4 do view:poll() end
    equal(view.skipped,3); equal(#view.rows,1000); equal(view.dropped,100)
    equal(view.tail,''); assert(#view.rows[1].raw<65536)
end)
test('filtering uses literal text event and exact target without changing raw events',function()
    local fs=memory_files({log='shot:7\nshot:17\ndamage:7\n'}); local view=View.new(decoder,fs.files)
    view:select('log'); view:poll(); view.target='7'; view.event='shot'; equal(#view:visible(),1)
    view.filter='SHOT'; equal(#view:visible(),1); view.filter='.*'; equal(#view:visible(),0)
    equal(#view.rows,3); equal(view.rows[1].raw,'shot:7')
end)
test('damage target mapping and total log memory limit follow actual telemetry schema',function()
    local view=View.new(function() return {event='damage_report',damaged_player_id=9} end)
    for _=1,50 do view:line(string.rep('x',60000)) end
    assert(view.bytes<=2097152); equal(view.rows[1].target,'9'); assert(view.dropped>0)
    view:clear(); equal(view.bytes,0)
end)
test('clear preserves file and cursor and truncation starts a fresh read',function()
    local fs=memory_files({log='shot:7\nshot:8\n'}); local view=View.new(decoder,fs.files)
    view:select('log'); view:poll(); local offset=view.offset
    view:clear(); equal(view.offset,offset); view:poll(); equal(#view.rows,0); equal(fs.data.log,'shot:7\nshot:8\n')
    fs.data.log='shot:9\n'; view:poll(); equal(#view.rows,1); equal(view.rows[1].target,'9')
end)
test('missing log and unavailable decoder produce actionable messages',function()
    local fs=memory_files(); local view=View.new(decoder,fs.files); view:select('missing'); view:poll()
    assert(view.status:find('Refresh',1,true)); view=View.new(nil,fs.files); view:select('x'); view:poll()
    assert(view.status:find('decodeJson',1,true))
end)
local function render_fixture()
    local fake=fake_gui(); local s=model_fixture(); local view=View.new(decoder)
    local requests={}
    local gui=Gui.new(fake.ui,fake.ffi,s.model,view,{enabled=function() return true end,
        telemetry_status=function() return 'Telemetry OFF' end,
        request=function(...) requests[#requests+1]={...} end})
    gui:initialize(); gui:open()
    local function draw() gui:draw(); equal(fake.depth,0) end
    return fake,s,view,gui,requests,draw
end
test('minimal settings and collapsed advanced fields edit every current setting',function()
    local fake,s,view,gui,requests,draw=render_fixture()
    draw(); assert(not fake.seen['Radius FOV']); assert(not fake.seen['Torso (%)'])
    local settings={{'Aktif saat masuk',true},{'Jarak',75},{'Radius FOV',0.2},
        {'Offset tinggi',0.4},{'Crosshair X',0.5},{'Crosshair Y',0.5},
        {'GUI saat mulai',false},{'Command','config'}}
    fake.clicks.Lanjutan=true
    for _,item in ipairs(settings) do fake.edits[item[1]]=item[2] end
    draw(); equal(s.model.draft.max_distance,75); equal(s.model.draft.gui_enabled,false)
    equal(s.model.draft.gui_command,'config'); equal(s.model.draft.enabled,true)
    fake.clicks.Distribusi=true; draw(); equal(gui.page,1)
    fake.edits['Acak titik']=false; fake.edits['Interval (ms)']=500
    fake.edits.Seed='123'
    for _,label in ipairs({'Torso','Lengan kiri','Lengan kanan','Kaki kiri','Kaki kanan','Kepala'}) do
        fake.edits[label..' (%)']=label=='Torso' and 100 or 0
    end
    draw(); equal(s.model:total(),100); equal(s.model.draft.random_seed,123); equal(s.model.draft.random_aim,false)
    fake.edits['Rekam log']=false; fake.edits['Korelasi (ms)']=500
    fake.edits['Tulis log (ms)']=200; draw()
    equal(s.model.draft.telemetry_enabled,false); equal(s.model.draft.telemetry_match_window_ms,500)
    fake.clicks.Log=true; draw(); equal(gui.page,2)
    fake.clicks.Pengaturan=true; draw(); equal(gui.page,1); equal(s.applied,0)
end)
test('all configuration toolbar actions have observable behavior and UI scopes balance',function()
    local fake,s,view,gui,requests,draw=render_fixture()
    fake.clicks.Lanjutan=true; draw()
    for label,action in pairs({Terapkan='apply',Simpan='save',['Muat INI']='reload',
        Default='defaults',Batalkan='discard'}) do
        fake.clicks[label]=true; draw(); equal(s.model.pending,action); s.model:poll()
    end
    fake.edits['Ukuran teks']=2; draw(); equal(gui.scale[0],2)
    fake.flags.DisplaySize={x=800,y=600}; draw()
    assert(fake.window_size.x<=800 and fake.window_size.y<=600)
    equal(fake.window_pos.x,400); equal(fake.window_pos.y,300)
    fake.close_window=true; draw(); equal(gui:is_open(),false)
    gui:open(); fake.escape=true; draw(); equal(gui:is_open(),false)
end)
test('log navigation file event search and row detail controls are connected',function()
    local fake,s,view,gui,requests,draw=render_fixture()
    gui.files={'/logs/AimLock1.4.0-test.jsonl'}; view:line('shot:7')
    fake.clicks.Log=true; draw(); equal(gui.page,2); equal(requests[1][1],'current')
    fake.clicks['Filter & berkas']=true; draw()
    for _,label in ipairs({'Cari berkas','Sesi aktif','Refresh','Kosongkan tampilan','Panel1.4.0-test.jsonl'}) do
        fake.clicks[label]=true; draw()
    end
    equal(#requests,6); equal(requests[6][1],'select')
    fake.edits['Refresh otomatis']=false; fake.edits.Cari='shot'; fake.edits['ID target']='7'
    fake.clicks.shot=true; fake.clicks['10##event_1']=true; draw()
    equal(gui.auto[0],false); equal(view.filter,'shot'); equal(view.target,'7'); equal(view.event,'shot')
    equal(view.selected,view.rows[1]); fake.clicks.Detail=true; draw()
    assert(table.concat(fake.texts,'\n'):find('shot:7',1,true))
end)
local function runtime_fixture(conflict)
    local fake=fake_gui(); local state={commands={},messages={},prints={},registrations=0,closed=0}
    local api={require=function(name) if name=='mimgui' then return fake.ui elseif name=='ffi' then return fake.ffi end error(name) end,
        sampIsChatCommandDefined=function(name) return name==conflict end,
        sampRegisterChatCommand=function(name,callback) state.commands[name]=callback; state.registrations=state.registrations+1; return true end,
        getWorkingDirectory=function() return './moonloader' end,decodeJson=decoder,
        print=function(text) state.prints[#state.prints+1]=text end}
    local bridge={path='never-write-real-config.ini',enabled=function() return false end,
        message=function(text) state.messages[#state.messages+1]=text end,
        telemetry_status=function() return 'OFF' end,log_path=function() return nil end,
        load=function() return Settings.validate({}) end,apply=function() return true end}
    state.api=api; state.bridge=bridge; state.fake=fake
    return state
end
test('optional GUI missing dependency disabled config and command conflict degrade independently',function()
    local s=runtime_fixture(); s.api.require=function() error('missing') end
    local result,err=Runtime.start(assert(Settings.validate({})),s.api,s.bridge)
    equal(result,nil); assert(err:find('mimgui',1,true)); equal(s.registrations,0)
    equal(Runtime.start(assert(Settings.validate({gui_enabled=false})),s.api,s.bridge),nil)
    s=runtime_fixture('apanel'); local runtime=assert(Runtime.start(assert(Settings.validate({})),s.api,s.bridge))
    equal(s.registrations,0); equal(s.commands.apanel,nil); equal(#s.messages,1)
    s=runtime_fixture(); runtime=assert(Runtime.start(assert(Settings.validate({})),s.api,s.bridge))
    equal(s.registrations,1); equal(s.commands.aimlock,nil); equal(s.commands.aimlog,nil)
    s.commands.apanel(); equal(runtime.gui.page,1); assert(runtime:is_open()); runtime:poll(100,true); s.fake.render()
    runtime:close(); equal(runtime:is_open(),false); equal(s.fake.draw,nil)
end)
test('runtime closes enumeration handle rejects traversal and caps log list',function()
    local s=runtime_fixture(); local count=0
    s.api.findFirstFile=function() return 7,'../escape.jsonl' end
    s.api.findNextFile=function() count=count+1; return count<100 and 'AimLock1.4.0-'..count..'.jsonl' or nil end
    s.api.findClose=function(handle) equal(handle,7); s.closed=s.closed+1 end
    local runtime=assert(Runtime.start(assert(Settings.validate({})),s.api,s.bridge))
    runtime:list_files(); equal(#runtime.gui.files,64); equal(s.closed,1)
    for _,path in ipairs(runtime.gui.files) do assert(not path:find('escape',1,true)) end
end)
test('render exception unwinds UI scopes and disables GUI without throwing into main',function()
    local s=runtime_fixture(); local runtime=assert(Runtime.start(assert(Settings.validate({})),s.api,s.bridge))
    s.commands.apanel(); s.fake.ui.InputFloat=function() error('Injected rendering failure') end
    s.fake.render(); equal(runtime:is_open(),false); equal(#s.prints,1); equal(s.fake.depth,0)
end)
test('identity display returns exactly one string with or without replacements',function()
    for _,value in ipairs({'plain text','AimLock','AimLock AimLock','aimlock_enabled','100% loaded'}) do
        equal(select('#',Identity.display(value)),1)
        equal(type(Identity.display(value)),'string')
        equal(select('#',Identity.log_label(value)),1)
    end
end)
test('GUI text boundaries ignore extra helper results before reaching native bindings',function()
    local fake,s,view,gui,requests,draw=render_fixture()
    local original=Identity.display
    Identity.display=function(value) return original(value),3 end
    local ok,err=pcall(draw)
    Identity.display=original
    assert(ok,err); assert(#fake.texts>0)
end)
test('author sits at upper right and visible UI omits script branding including old logs',function()
    local fake,s,view,gui,requests,draw=render_fixture()
    draw(); equal(fake.title,'Panel')
    equal(fake.author_x,840-#Identity.author*7)
    assert(table.concat(fake.texts,'\n'):find(Identity.author,1,true))
    fake.ui.GetCursorPosX=function() return 10 end
    fake.ui.GetWindowContentRegionMax=function() return {x=200,y=560} end
    draw(); equal(fake.author_x,200-#Identity.author*7)
    gui.files={'/logs/AimLock1.4.0-test.jsonl'}; view.path=gui.files[1]
    view.status='Gagal membaca /logs/AimLock1.4.0-test.jsonl'
    view:line('shot:7'); view.rows[1].raw='{"session_id":"AimLock1.4.0-test","aimlock_enabled":true}'
    view.selected=view.rows[1]; fake.headers['Filter & berkas']=true; fake.headers.Detail=true
    fake.clicks.Log=true; draw()
    for _,text in ipairs(fake.texts) do assert(not text:lower():find('aimlock',1,true),text) end
    for label in pairs(fake.seen) do assert(not label:lower():find('aimlock',1,true),label) end
    assert(view.rows[1].raw:find('AimLock',1,true),'Raw log must remain unchanged')
end)
print(string.format('\n%d passed; %d failed',passed,failed))
if failed>0 then os.exit(1) end
