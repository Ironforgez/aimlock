local Settings = require 'AimLockDistribution.settings'
local Store = {}
local keys = {'enabled','max_distance','fov_radius','target_height','crosshair_x','crosshair_y',
    'random_aim','random_interval_ms','random_seed','telemetry_enabled','telemetry_match_window_ms',
    'telemetry_flush_interval_ms','gui_enabled','gui_command'}
Store.parts = {'torso','left_arm','right_arm','left_leg','right_leg','head'}

function Store.serialize(values)
    local config,err=Settings.validate(values)
    if not config then return nil,err end
    local lines={'[aimlock]'}
    local function text(value)
        if type(value)=='number' then return string.format('%.17g',value) end
        return tostring(value)
    end
    for _,key in ipairs(keys) do lines[#lines+1]=key..'='..text(config[key]) end
    lines[#lines+1]=''; lines[#lines+1]='[distribution]'
    for _,key in ipairs(Store.parts) do lines[#lines+1]=key..'='..text(config.distribution[key]) end
    return table.concat(lines,'\r\n')..'\r\n'
end

local function write_file(files,path,content)
    local file,err=files.open(path,'wb')
    if not file then return nil,tostring(err) end
    local ok,written,write_error=pcall(file.write,file,content)
    local closed_ok,closed,close_error=pcall(file.close,file)
    if not ok or not written or not closed_ok or not closed then
        return nil,tostring(not ok and written or write_error or not closed_ok and closed or close_error)
    end
    return true
end

function Store.save(path,values,replace_file,files,remove_file)
    local content,err=Store.serialize(values)
    if not content then return nil,err end
    if type(replace_file)~='function' then return nil,'Penggantian file atomik tidak tersedia.' end
    files,remove_file=files or io,remove_file or os.remove
    local original,open_error=files.open(path,'rb')
    if not original then return nil,'INI asli tidak dapat dibaca: '..tostring(open_error) end
    local old,read_error=original:read('*a'); original:close()
    if not old then return nil,'INI asli tidak dapat dibaca: '..tostring(read_error) end
    local temp,backup=path..'.tmp',path..'.bak'
    local ok
    ok,err=write_file(files,temp,content)
    if not ok then remove_file(temp); return nil,'Gagal menulis INI sementara: '..tostring(err) end
    ok,err=write_file(files,backup..'.tmp',old)
    if ok then ok,err=replace_file(backup..'.tmp',backup) end
    if not ok then
        remove_file(temp); remove_file(backup..'.tmp')
        return nil,'Backup gagal; INI asli dipertahankan: '..tostring(err)
    end
    ok,err=replace_file(temp,path)
    if not ok then remove_file(temp); return nil,'INI asli dipertahankan: '..tostring(err) end
    return true
end

return Store
