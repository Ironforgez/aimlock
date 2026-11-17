local Model = require 'AimLockDistribution.gui_model'
local Store = require 'AimLockDistribution.config_store'
local View = require 'AimLockDistribution.log_view'
local Gui = require 'AimLockDistribution.gui'
local Identity = require 'AimLockDistribution.identity'
local Runtime={}
local Session={}
Session.__index=Session

local function guarded(ui)
    local stack={}
    local proxy=setmetatable({},{__index=ui})
    for first,last in pairs({Begin='End',BeginChild='EndChild',BeginCombo='EndCombo',PushItemWidth='PopItemWidth'}) do
        local begin,finish=first,last
        proxy[first]=function(...)
            local result=ui[begin](...)
            if begin~='BeginCombo' or result then stack[#stack+1]=finish end
            return result
        end
        proxy[last]=function(...)
            local result=ui[finish](...); stack[#stack]=nil; return result
        end
    end
    return proxy,function()
        for index=#stack,1,-1 do pcall(ui[stack[index]]); stack[index]=nil end
    end
end

function Runtime.replace_file(ffi)
    ffi.cdef([[int __stdcall MoveFileExA(const char *existing_path, const char *new_path, unsigned long flags);
        unsigned long __stdcall GetLastError(void);]])
    local kernel=ffi.load('kernel32')
    return function(from,to)
        if kernel.MoveFileExA(from,to,9)==0 then return nil,'MoveFileExA error '..tonumber(kernel.GetLastError()) end
        return true
    end
end

function Runtime.start(settings,api,bridge)
    if not settings.gui_enabled then return nil,'disabled_by_config' end
    for _,name in ipairs({'require','sampIsChatCommandDefined','sampRegisterChatCommand'}) do
        if type(api[name])~='function' then return nil,'API GUI tidak tersedia: '..name end
    end
    local ok,imgui=pcall(api.require,'mimgui')
    if not ok then return nil,'mimgui belum tersedia. Pasang mimgui resmi di moonloader/lib/mimgui. '..tostring(imgui) end
    local ffi_ok,ffi=pcall(api.require,'ffi')
    if not ffi_ok then return nil,'LuaJIT ffi tidak tersedia: '..tostring(ffi) end
    local self=setmetatable({api=api,bridge=bridge,requests={},last_poll=nil,commands={}},Session)
    local replace_ok,replace=pcall(Runtime.replace_file,ffi)
    self.model=Model.new(settings,{
        load=bridge.load,apply=bridge.apply,
        save=function(values)
            if not replace_ok then return nil,'Penyimpanan atomik tidak tersedia: '..tostring(replace) end
            return Store.save(bridge.path,values,replace)
        end
    })
    self.logs=View.new(api.decodeJson)
    local ui,unwind=guarded(imgui)
    self.gui=Gui.new(ui,ffi,self.model,self.logs,{
        enabled=bridge.enabled,telemetry_status=bridge.telemetry_status,
        request=function(action,path)
            if #self.requests<8 then self.requests[#self.requests+1]={action,path} end
        end
    })
    local function fail(err)
        self.failed=true; self.gui.opened[0]=false; unwind()
        api.print(Identity.message('GUI OFF: '..tostring(err)))
    end
    self.initializer=imgui.OnInitialize(function()
        local initialized,err=pcall(self.gui.initialize,self.gui)
        if not initialized then fail(err) end
    end)
    self.frame=imgui.OnFrame(function() return not self.failed and self.gui:is_open() and self.visible~=false end,function()
        local drawn,err=pcall(self.gui.draw,self.gui)
        if not drawn then fail(err) end
    end)
    self.frame.LockPlayer=true
    local function register(name)
        local command_ok,result=pcall(function()
            if api.sampIsChatCommandDefined(name) then return nil end
            return api.sampRegisterChatCommand(name,function()
                if self.failed then bridge.message('GUI OFF: periksa moonloader.log dan reload script.'); return end
                self.gui:open()
                self.requests[#self.requests+1]={'files'}
                if not self.logs.path then self.requests[#self.requests+1]={'current'} end
            end)
        end)
        if command_ok and result==true then
            self.commands[#self.commands+1]='/'..name
        else bridge.message('Command /'..name..' tidak didaftarkan (bentrok / gagal). Ubah nama di INI lalu reload.') end
    end
    register(settings.gui_command)
    return self
end
function Session:is_open() return not self.failed and self.gui:is_open() end
function Session:list_files()
    local directory=self.api.getWorkingDirectory()..'/logs/'
    local files,seen={},{}
    local function add(path)
        if path and not seen[path] then seen[path]=true; files[#files+1]=path end
    end
    add(self.bridge.log_path())
    local api=self.api
    if type(api.findFirstFile)=='function' and type(api.findNextFile)=='function' and type(api.findClose)=='function' then
        local handle
        local ok,err=pcall(function()
            local name; handle,name=api.findFirstFile(directory..'AimLock*.jsonl')
            if not handle then return end
            for _=1,256 do
                if not name then break end
                if name:match('^AimLock[%w%.%-_]+%.jsonl$') then add(directory..name) end
                name=api.findNextFile(handle)
            end
        end)
        if handle then pcall(api.findClose,handle) end
        if not ok then self.logs.status='Daftar log gagal: '..tostring(err) end
    end
    table.sort(files,function(a,b) return a>b end)
    while #files>64 do table.remove(files) end
    self.gui.files=files
end
function Session:poll(now,visible)
    self.visible=visible
    if self.failed then return end
    local ok,err=pcall(function()
        self.model:poll()
        local requests=self.requests; self.requests={}
        local refresh=false
        for _,request in ipairs(requests) do
            local action,path=request[1],request[2]
            if action=='files' then self:list_files()
            elseif action=='select' then self.logs:select(path); refresh=true
            elseif action=='current' then
                local current=self.bridge.log_path()
                if current then self.logs:select(current); refresh=true
                else self.logs.status='Tidak ada sesi aktif. Aktifkan telemetry lalu Terapkan.' end
            elseif action=='clear' then self.logs:clear()
            elseif action=='refresh' then refresh=true end
        end
        if refresh or self:is_open() and self.gui.page==2 and self.gui.auto[0]
            and (not self.last_poll or (now-self.last_poll)%4294967296>=500) then
            self.logs:poll(); self.last_poll=now
        end
    end)
    if not ok then self.model.message='Operasi GUI gagal: '..tostring(err); self.api.print(Identity.message(self.model.message)) end
end
function Session:close()
    self.gui.opened[0]=false
    if self.frame then self.frame:Unsubscribe() end
    if self.initializer then self.initializer:Unsubscribe() end
end
return Runtime
