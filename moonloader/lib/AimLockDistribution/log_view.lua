local View={}
View.__index=View
local limit,line_limit,budget,byte_limit=1000,65536,65536,2097152
function View.new(decode,files)
    return setmetatable({decode=decode,files=files or io,rows={},offset=0,tail='',
        skipped=0,dropped=0,bytes=0,serial=0,status='Pilih log untuk membaca event.',filter='',event='all',target=''},View)
end
function View:select(path)
    self.path=path; self:clear(); self.offset=0; self.tail=''; self.skipping=false
    self.status='Memuat log...'
end
function View:clear()
    self.rows={}; self.selected=nil; self.skipped=0; self.dropped=0; self.bytes=0
end
function View:line(raw)
    raw=raw:gsub('\r$','')
    if raw=='' then return end
    if #raw>line_limit then self.skipped=self.skipped+1; return end
    local ok,event=pcall(self.decode,raw)
    if not ok or type(event)~='table' or type(event.event)~='string' then
        self.skipped=self.skipped+1; return
    end
    self.serial=self.serial+1
    local row={id=self.serial,data=event,raw=raw,
        search=(raw):lower(),target=tostring(event.reported_hit_id or event.damaged_player_id
            or event.locked_player_id or event.player_id or '')}
    while #self.rows>=limit or self.bytes+#raw>byte_limit do
        local old=table.remove(self.rows,1); self.dropped=self.dropped+1
        self.bytes=self.bytes-#old.raw
        if self.selected==old then self.selected=nil end
    end
    self.rows[#self.rows+1]=row
    self.bytes=self.bytes+#raw
end
function View:poll()
    if not self.path then return end
    if type(self.decode)~='function' then self.status='decodeJson tidak tersedia; periksa MoonLoader.'; return end
    local file,err=self.files.open(self.path,'rb')
    if not file then self.status='Log belum dapat dibaca. Coba Refresh: '..tostring(err); return end
    local ok,result=pcall(function()
        local size=assert(file:seek('end'))
        if size<self.offset then self.offset=0; self.tail=''; self.skipping=false; self:clear() end
        assert(file:seek('set',self.offset))
        local chunk,read_error=file:read(budget)
        if read_error then error(read_error) end
        if not chunk then self.status=#self.rows==0 and 'Belum ada event. Tunggu tembakan / flush telemetry.' or 'Log terkini.'; return end
        self.offset=self.offset+#chunk
        local start=1
        while start<=#chunk do
            local finish=chunk:find('\n',start,true)
            local piece=chunk:sub(start,finish and finish-1 or #chunk)
            if not self.skipping then
                if #self.tail+#piece>line_limit then
                    self.tail=''; self.skipping=true; self.skipped=self.skipped+1
                else self.tail=self.tail..piece end
            end
            if finish then
                if not self.skipping then self:line(self.tail) end
                self.tail=''; self.skipping=false; start=finish+1
            else break end
        end
        self.status=self.offset<size and 'Memuat log bertahap...' or 'Log terkini.'
    end)
    file:close()
    if not ok then self.status='Gagal membaca log. Coba Refresh: '..tostring(result) end
end
function View:visible()
    local result={}; local needle=self.filter:lower()
    for _,row in ipairs(self.rows) do
        if (self.event=='all' or row.data.event==self.event)
            and (self.target=='' or row.target==self.target)
            and (needle=='' or row.search:find(needle,1,true)) then result[#result+1]=row end
    end
    return result
end
return View
