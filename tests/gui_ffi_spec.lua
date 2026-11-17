local ok,ffi=pcall(require,'ffi')
if not ok then print('SKIP: LuaJIT ffi required.'); return end
package.path='./moonloader/lib/?.lua;'..package.path
local loader=require
if arg and arg[1] then
    local env=setmetatable({},{__index=_G}); env._G=env
    for _,name in ipairs({'script_name','script_author','script_version','script_description'}) do env[name]=function() end end
    local chunk=assert(loadfile(arg[1])); setfenv(chunk,env); loader=assert(chunk())
end
local Identity=loader('AimLockDistribution.identity')
local Gui=loader('AimLockDistribution.gui')
local Model=loader('AimLockDistribution.gui_model')
local View=loader('AimLockDistribution.log_view')
local Settings=loader('AimLockDistribution.settings')
local seen=0
local native=ffi.cast('void (*)(const char *, const char *)',function(text,text_end)
    assert(text_end==nil,'Unexpected text_end pointer')
    assert(type(ffi.string(text))=='string'); seen=seen+1
end)
local tested,err=pcall(function()
    local converted,conversion_error=pcall(native,'text',1)
    assert(not converted and tostring(conversion_error):find('const char',1,true),'FFI must reject a numeric text_end')
    local fake=assert(loadfile('tests/gui_fixture.lua'))()()
    -- Same optional-argument contract as mimgui v1.7.1's TextUnformatted wrapper.
    fake.ui.TextUnformatted=function(text,text_end) return native(text,text_end or nil) end
    local model=Model.new(assert(Settings.validate({})),{})
    local view=View.new(function() return {event='shot'} end)
    local gui=Gui.new(fake.ui,fake.ffi,model,view,{
        enabled=function() return false end,telemetry_status=function() return 'Telemetry ON' end,
        request=function() end})
    gui:initialize(); gui:open()
    for _,value in ipairs({'plain text','AimLock','AimLock AimLock','aimlock_enabled'}) do
        assert(select('#',Identity.display(value))==1)
        gui.ui.TextUnformatted(value)
    end
    fake.headers.Distribusi=true; fake.headers.Lanjutan=true
    gui:draw(); assert(fake.depth==0)
    view:line('sample'); view.selected=view.rows[1]
    view.rows[1].raw='AimLock 100%'; gui.page=2
    fake.headers['Filter & berkas']=true; fake.headers.Detail=true
    gui:draw(); assert(fake.depth==0)
    assert(seen>10,'Native text boundary was not exercised')
end)
native:free()
assert(tested,err)
print('PASS: numeric text_end reproduces the failure; source/bundle GUI text passes real LuaJIT FFI conversion.')
