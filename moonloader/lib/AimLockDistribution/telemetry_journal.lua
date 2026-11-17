local Journal = {}
Journal.__index = Journal
local sequence=0

function Journal.new(api, version, file_api)
    for _,name in ipairs({'doesDirectoryExist','createDirectory','encodeJson','getWorkingDirectory','getGameTimer'}) do
        if type(api[name])~='function' then return nil,'API log tidak tersedia: '..name end
    end
    local directory=api.getWorkingDirectory()..'/logs'
    if not api.doesDirectoryExist(directory) then
        api.createDirectory(directory)
        if not api.doesDirectoryExist(directory) then return nil,'Tidak dapat membuat folder log: '..directory end
    end
    sequence=sequence+1
    local session='AimLock'..version..'-'..os.date('%Y%m%d-%H%M%S')..'-'
        ..string.format('%.0f',api.getGameTimer()%4294967296)..'-'..sequence
    return setmetatable({path=directory..'/'..session..'.jsonl',session_id=session,
        encode=api.encodeJson,files=file_api or io},Journal)
end

function Journal:append(events)
    local lines={}
    for index,event in ipairs(events) do
        local ok,encoded=pcall(self.encode,event)
        if not ok or type(encoded)~='string' or encoded:find('[\r\n]') then
            return nil,'encodeJson gagal menghasilkan satu baris JSON.'
        end
        lines[index]=encoded
    end
    local file,err=self.files.open(self.path,'ab')
    if not file then return nil,tostring(err) end
    local write_ok,written,write_error=pcall(file.write,file,table.concat(lines,'\n')..'\n')
    local close_ok,closed,close_error=pcall(file.close,file)
    if not write_ok then return nil,tostring(written) end
    if not close_ok then return nil,tostring(closed) end
    if not written or not closed then return nil,tostring(write_error or close_error) end
    return true
end

return Journal
