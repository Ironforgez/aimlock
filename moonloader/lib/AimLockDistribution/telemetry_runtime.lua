local Telemetry = require 'AimLockDistribution.telemetry'
local Observer = require 'AimLockDistribution.telemetry_observer'
local Journal = require 'AimLockDistribution.telemetry_journal'
local Identity = require 'AimLockDistribution.identity'
local Runtime = {}
local Manager={}
Manager.__index=Manager

function Runtime.manager(api,get_context,file_api)
    local self=setmetatable({api=api,context=get_context,files=file_api},Manager)
    local proxy={}
    function proxy:is_active() return self.owner.current and self.owner.current:is_active() or false end
    for _,name in ipairs({'record_shot','record_damage','record_error'}) do
        local method=name
        proxy[method]=function(_,...) if self.current then return self.current[method](self.current,...) end end
    end
    proxy.owner=self; self.proxy=proxy
    return self
end
function Manager:configure(settings)
    if self.current then self.current:close(); self.current=nil end
    self.last_error=nil
    if not settings.telemetry_enabled then self.last_error='disabled_by_config'; return nil,self.last_error end
    local ok,instance,err=pcall(function()
        local available,api_error=Observer.available(self.api)
        if not available then return nil,api_error end
        local journal,journal_error=Journal.new(self.api,Identity.version,self.files)
        if not journal then return nil,journal_error end
        if not self.observer then
            if self.attach_attempted then return nil,'Observer gagal terpasang; reload script diperlukan.' end
            self.attach_attempted=true
            local observer,observer_error=Observer.attach(self.api,self.proxy,self.context)
            if not observer then return nil,observer_error end
            self.observer=observer
        end
        if not self.observer.active then return nil,'Observer nonaktif; reload script diperlukan.' end
        local telemetry=Telemetry.new(settings,{
            start_ms=self.api.getGameTimer(),session_id=journal.session_id,version=Identity.version,
            write_batch=function(events) return journal:append(events) end,
            on_error=function(message)
                self.last_error=message; self.api.print(Identity.message('Telemetry OFF: '..message))
            end
        })
        telemetry.log_path=journal.path
        return telemetry
    end)
    if not ok then self.last_error=tostring(instance); return nil,self.last_error end
    self.current=instance; self.last_error=err
    return instance,err
end
function Manager:poll(now) if self.current then self.current:poll(now) end end
function Manager:close() if self.current then self.current:close(); self.current=nil end end
function Runtime.start(settings,api,get_context,file_api)
    local manager=Runtime.manager(api,get_context,file_api)
    return manager:configure(settings)
end
return Runtime
