-- Run with Windows LuaJIT; this exercises kernel32 and real temporary files.
local ok,ffi=pcall(require,'ffi')
if not ok or ffi.os~='Windows' then print('SKIP: Windows LuaJIT ffi required.'); return end
package.path='./moonloader/lib/?.lua;'..package.path
local loader=require
if arg and arg[1] then
    local env=setmetatable({},{__index=_G}); env._G=env
    for _,name in ipairs({'script_name','script_author','script_version','script_description'}) do env[name]=function() end end
    local chunk=assert(loadfile(arg[1])); setfenv(chunk,env); loader=assert(chunk())
end
local Store=loader('AimLockDistribution.config_store')
local Runtime=loader('AimLockDistribution.gui_runtime')
local Settings=loader('AimLockDistribution.settings')
local replace=Runtime.replace_file(ffi)
ffi.cdef([[void *__stdcall CreateFileA(const char *path, unsigned long access, unsigned long share,
    void *security, unsigned long creation, unsigned long attributes, void *template_file);
    int __stdcall CloseHandle(void *handle);]])
local kernel=ffi.load('kernel32')
local path=assert(os.getenv('TEMP'))..'/AimLock-io-'..os.time()..'-'..tostring({}):gsub('%W','')..'.ini'
local function read(name) local file=assert(io.open(name,'rb')); local text=assert(file:read('*a')); assert(file:close()); return text end
local handle
local tested,err=pcall(function()
    local original=assert(Store.serialize({}))
    local file=assert(io.open(path,'wb')); assert(file:write(original)); assert(file:close())
    assert(Store.save(path,{max_distance=75},replace))
    assert(read(path..'.bak')==original)
    assert(assert(Settings.parse(read(path))).max_distance==75)
    local current=read(path)
    handle=kernel.CreateFileA(path,2147483648,1,nil,3,128,nil)
    assert(handle~=ffi.cast('void *',-1),'Cannot lock test INI')
    local saved,message=Store.save(path,{max_distance=90},replace)
    assert(not saved and message:find('MoveFileExA error',1,true),tostring(message))
    assert(read(path)==current,'Locked INI changed')
    assert(kernel.CloseHandle(handle)~=0); handle=nil
    assert(Store.save(path,{max_distance=90},replace))
    assert(assert(Settings.parse(read(path))).max_distance==90)
end)
if handle and handle~=ffi.cast('void *',-1) then kernel.CloseHandle(handle) end
for _,suffix in ipairs({'','.bak','.tmp','.bak.tmp'}) do os.remove(path..suffix) end
assert(tested,err)
print('PASS: Windows kernel32 replacement, backup, locked-file failure and retry with real Lua io.')
