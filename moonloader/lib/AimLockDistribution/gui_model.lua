local Settings = require 'AimLockDistribution.settings'
local Store = require 'AimLockDistribution.config_store'
local Model = {}
Model.__index=Model

local function copy(value)
    if type(value)~='table' then return value end
    local result={}; for key,item in pairs(value) do result[key]=copy(item) end; return result
end
function Model.new(settings,bridge)
    return setmetatable({draft=copy(settings),current=copy(settings),saved=copy(settings),
        bridge=bridge,pending=nil,revision=0,message='Konfigurasi dimuat dari INI.'},Model)
end
function Model:replace(values,message)
    self.draft=copy(values); self.revision=self.revision+1; self.message=message
end
function Model:validate() return Settings.validate(self.draft) end
function Model:total()
    local sum=0
    for _,key in ipairs(Store.parts) do sum=sum+(tonumber(self.draft.distribution[key]) or 0) end
    return sum
end
function Model:state()
    local draft=Store.serialize(self.draft)
    return draft~=Store.serialize(self.current),Store.serialize(self.current)~=Store.serialize(self.saved)
end
function Model:request(action)
    if self.pending then return false end
    self.pending=action; return true
end
function Model:poll()
    local action=self.pending; self.pending=nil
    if not action then return end
    if action=='discard' then self:replace(self.current,'Draft dikembalikan ke konfigurasi aktif.'); return end
    if action=='defaults' then self:replace(assert(Settings.validate({})),'Default dimuat ke draft; belum diterapkan.'); return end
    if action=='reload' then
        local values,err=self.bridge.load()
        if values then self.saved=copy(values); self:replace(values,'INI dimuat ke draft; belum diterapkan.')
        else self.message='Gagal memuat INI: '..tostring(err) end
        return
    end
    if action~='apply' and action~='save' then return end
    local values,err=self:validate()
    if not values then self.message='Konfigurasi ditolak: '..tostring(err); return end
    if action=='save' then
        local ok; ok,err=self.bridge.save(values)
        if not ok then self.message='Gagal menyimpan: '..tostring(err); return end
        self.saved=copy(values)
    end
    local ok; ok,err=self.bridge.apply(values)
    if not ok then self.message='Gagal menerapkan: '..tostring(err); return end
    self.current=copy(values)
    self:replace(values,action=='save' and 'Tersimpan dan diterapkan. Backup: INI.bak.'
        or 'Diterapkan untuk sesi ini; gunakan Simpan & Terapkan untuk menyimpan INI.')
end

return Model
