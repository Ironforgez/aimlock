local Store = require 'AimLockDistribution.config_store'
local Identity = require 'AimLockDistribution.identity'
local Gui={}
Gui.__index=Gui
local pages={'Pengaturan','Log'}
local part_labels={torso='Torso',left_arm='Lengan kiri',right_arm='Lengan kanan',
    left_leg='Kaki kiri',right_leg='Kaki kanan',head='Kepala'}
local event_names={'all','shot','damage_report','correlation_update','shot_window_closed',
    'damage_window_closed','observer_error','session_start','session_end','telemetry_overflow',
    'shot_candidates_truncated'}

function Gui.new(imgui,ffi,model,logs,bridge)
    local display=setmetatable({
        TextUnformatted=function(value)
            local text=Identity.display(value)
            return imgui.TextUnformatted(text,nil)
        end,
        TextWrapped=function(format,...)
            local text=Identity.display(string.format(format,...))
            return imgui.TextWrapped('%s',text)
        end
    },{__index=imgui})
    return setmetatable({ui=display,ffi=ffi,model=model,logs=logs,bridge=bridge,opened=imgui.new.bool(false),
        page=1,buffers={},revision=-1,auto=imgui.new.bool(true),scale=imgui.new.float(1),
        search=imgui.new.char[128](),target=imgui.new.char[12](),files={}},Gui)
end
function Gui:open(page) self.page=page or self.page; self.opened[0]=true end
function Gui:is_open() return self.opened[0] end
function Gui:sync()
    if self.revision==self.model.revision then return end
    self.buffers={}; self.revision=self.model.revision
end
function Gui:field(key,label,kind,description,values)
    local ui=self.ui; values=values or self.model.draft
    local id=(values==self.model.draft and '' or 'dist_')..key
    local buffer=self.buffers[id]
    if not buffer then
        if kind=='bool' then buffer=ui.new.bool(values[key])
        elseif kind=='int' then buffer=ui.new.int(values[key])
        elseif kind=='text' then buffer=ui.new.char[32](tostring(values[key]))
        else buffer=ui.new.float(values[key]) end
        self.buffers[id]=buffer
    end
    local changed
    ui.PushItemWidth(math.min(230,math.max(100,ui.GetContentRegionAvail().x*0.42)))
    if kind=='bool' then changed=ui.Checkbox(label,buffer)
    elseif kind=='int' then changed=ui.InputInt(label,buffer)
    elseif kind=='text' then changed=ui.InputText(label,buffer,32)
    else changed=ui.InputFloat(label,buffer,0,0,'%.4f') end
    ui.PopItemWidth()
    if changed then
        local value=kind=='text' and self.ffi.string(buffer) or buffer[0]
        if kind=='float' and value==value and math.abs(value)~=math.huge then
            value=tonumber(string.format('%.4f',value))
        end
        if key=='random_seed' and value~='auto' then value=tonumber(value) or value end
        values[key]=value
        self.model.message=''
    end
    if description then ui.TextWrapped('%s',description) end
end
function Gui:configuration()
    local ui=self.ui
    self:field('random_aim','Acak titik','bool')
    self:field('max_distance','Jarak','float')
    self:field('random_interval_ms','Interval (ms)','int')
    if ui.CollapsingHeader('Distribusi') then self:distribution() end
    if ui.CollapsingHeader('Lanjutan') then
        self:field('enabled','Aktif saat masuk','bool')
        self:field('fov_radius','Radius FOV','float')
        self:field('target_height','Offset tinggi','float')
        self:field('crosshair_x','Crosshair X','float')
        self:field('crosshair_y','Crosshair Y','float')
        self:field('random_seed','Seed','text')
        self:telemetry()
        self:field('gui_enabled','GUI saat mulai','bool')
        self:field('gui_command','Command','text')
        ui.TextWrapped('%s','GUI dan command berubah setelah reload.')
        ui.PushItemWidth(160); ui.SliderFloat('Ukuran teks',self.scale,1,2,'%.1fx'); ui.PopItemWidth()
        for _,action in ipairs({{'Muat INI','reload'},{'Default','defaults'},{'Batalkan','discard'}}) do
            if ui.Button(action[1]) then self.model:request(action[2]) end
        end
    end
end
function Gui:distribution()
    local ui=self.ui
    for _,key in ipairs(Store.parts) do self:field(key,part_labels[key]..' (%)','float',nil,self.model.draft.distribution) end
    ui.TextUnformatted(string.format('Total: %.4g / 100%%',self.model:total()))
end
function Gui:telemetry()
    local ui=self.ui
    self:field('telemetry_enabled','Rekam log','bool')
    self:field('telemetry_match_window_ms','Korelasi (ms)','int')
    self:field('telemetry_flush_interval_ms','Tulis log (ms)','int')
    ui.TextWrapped('%s',self.bridge.telemetry_status())
end
function Gui:log_page()
    local ui,logs=self.ui,self.logs
    if ui.Button('Sesi aktif') then self.bridge.request('current') end
    ui.SameLine()
    if ui.Button('Refresh') then self.bridge.request('refresh') end
    ui.PushItemWidth(math.max(120,ui.GetContentRegionAvail().x-80))
    if ui.InputText('Cari',self.search,128) then logs.filter=self.ffi.string(self.search) end
    ui.PopItemWidth()
    if ui.CollapsingHeader('Filter & berkas') then
        ui.PushItemWidth(160)
        if ui.BeginCombo('Berkas',Identity.log_label(logs.path)) then
            for _,path in ipairs(self.files) do
                if ui.Selectable(Identity.log_label(path),path==logs.path) then self.bridge.request('select',path) end
            end
            if #self.files==0 then ui.TextUnformatted('Belum ada log. Aktifkan rekaman lalu Refresh.') end
            ui.EndCombo()
        end
        if ui.InputText('ID target',self.target,12) then logs.target=self.ffi.string(self.target) end
        if ui.BeginCombo('Event',logs.event) then
            for _,name in ipairs(event_names) do if ui.Selectable(name,logs.event==name) then logs.event=name end end
            ui.EndCombo()
        end
        ui.PopItemWidth()
        ui.Checkbox('Refresh otomatis',self.auto)
        if ui.Button('Cari berkas') then self.bridge.request('files') end
        if ui.Button('Kosongkan tampilan') then self.bridge.request('clear') end
    end
    local rows=logs:visible()
    ui.TextWrapped('%s',string.format('%d / %d event | server: unknown',#rows,#logs.rows))
    if logs.skipped>0 or logs.dropped>0 then
        ui.TextUnformatted(string.format('Dilewati: %d | Event lama dilepas: %d',logs.skipped,logs.dropped))
    end
    if logs.status~='Log terkini.' then ui.TextWrapped('%s',logs.status) end
    local height=math.max(90,ui.GetContentRegionAvail().y-140*self.scale[0])
    ui.BeginChild('event_rows',ui.ImVec2(0,height),true,ui.WindowFlags.HorizontalScrollbar)
    ui.SetWindowFontScale(self.scale[0])
    ui.Columns(6,'events',true)
    for index,width in ipairs({80,180,70,120,120,100}) do ui.SetColumnWidth(index-1,width) end
    for _,title in ipairs({'Game ms','Event','Target','Titik aim','Body report','Server'}) do ui.TextUnformatted(title); ui.NextColumn() end
    ui.Separator()
    for _,row in ipairs(rows) do
        local event=row.data
        if ui.Selectable(tostring(event.game_ms or '-')..'##event_'..row.id,logs.selected==row,ui.SelectableFlags.SpanAllColumns) then logs.selected=row end
        ui.NextColumn()
        for _,value in ipairs({event.event,row.target~='' and row.target or '-',event.selected_body_part or '-',
            event.reported_body_part or '-',event.server_status or 'unknown'}) do
            ui.TextUnformatted(tostring(value)); ui.NextColumn()
        end
    end
    ui.Columns(1); ui.EndChild()
    if #rows==0 then ui.TextWrapped('%s',#logs.rows==0 and 'Belum ada event. Pilih Sesi aktif atau tunggu rekaman.' or 'Tidak ada hasil. Periksa filter.') end
    if ui.CollapsingHeader('Detail') then
        ui.TextWrapped('%s',logs.selected and logs.selected.raw or 'Pilih satu event.')
    end
end
function Gui:draw()
    self:sync()
    local ui=self.ui
    local display=ui.GetIO().DisplaySize or ui.ImVec2(1280,720)
    local width,height=math.max(320,display.x-24),math.max(240,display.y-24)
    ui.SetNextWindowPos(ui.ImVec2(display.x/2,display.y/2),ui.Cond.FirstUseEver,ui.ImVec2(0.5,0.5))
    ui.SetNextWindowSize(ui.ImVec2(math.min(860,width),math.min(580,height)),ui.Cond.FirstUseEver)
    ui.SetNextWindowSizeConstraints(ui.ImVec2(math.min(620,width),math.min(460,height)),ui.ImVec2(width,height))
    local visible=ui.Begin('Panel',self.opened)
    if visible then
        ui.SetWindowFontScale(self.scale[0])
        if ui.IsKeyPressed(ui.GetKeyIndex(ui.Key.Escape),false) then self.opened[0]=false end
        local status=(self.bridge.enabled() and 'ON' or 'OFF')..' | Alt + X'
        local left,right=ui.GetCursorPosX(),ui.GetWindowContentRegionMax().x
        local author_width=ui.CalcTextSize(Identity.author).x
        local shared_line=right-left>=author_width+ui.CalcTextSize(status).x+16
        if shared_line then ui.TextUnformatted(status); ui.SameLine() end
        ui.SetCursorPosX(math.max(left,right-author_width))
        ui.TextUnformatted(Identity.author)
        if not shared_line then ui.TextUnformatted(status) end
        ui.Separator()
        ui.BeginChild('sidebar',ui.ImVec2(110,0),false,ui.WindowFlags.HorizontalScrollbar)
        ui.SetWindowFontScale(self.scale[0])
        for index,name in ipairs(pages) do
            if ui.Selectable(name,self.page==index) then
                self.page=index
                if index==2 and not self.logs.path then self.bridge.request('current') end
            end
        end
        ui.EndChild(); ui.SameLine()
        ui.BeginChild('content',ui.ImVec2(0,0),false,ui.WindowFlags.HorizontalScrollbar)
        ui.SetWindowFontScale(self.scale[0])
        if self.page==1 then
            ui.BeginChild('settings',ui.ImVec2(0,-90*self.scale[0]),false,ui.WindowFlags.HorizontalScrollbar)
            ui.SetWindowFontScale(self.scale[0])
            self:configuration()
            ui.EndChild()
            ui.Separator()
            local dirty,unsaved=self.model:state()
            local valid,err=self.model:validate()
            ui.TextWrapped('%s',not valid and err or self.model.message~='' and self.model.message
                or dirty and 'Belum diterapkan.' or unsaved and 'Belum disimpan.' or 'Tersimpan.')
            if ui.Button('Simpan') then self.model:request('save') end
            ui.SameLine()
            if ui.Button('Terapkan') then self.model:request('apply') end
        else
            self:log_page()
        end
        ui.EndChild()
    end
    ui.End()
end
function Gui:initialize()
    local ui=self.ui
    local flags=ui.GetIO().ConfigFlags
    if math.floor(flags/ui.ConfigFlags.NavEnableKeyboard)%2==0 then
        ui.GetIO().ConfigFlags=flags+ui.ConfigFlags.NavEnableKeyboard
    end
    ui.StyleColorsDark()
    local style=ui.GetStyle()
    style.WindowRounding=2; style.FrameRounding=2; style.FrameBorderSize=1
    local function color(key,hex)
        style.Colors[ui.Col[key]]=ui.ImVec4(tonumber(hex:sub(1,2),16)/255,
            tonumber(hex:sub(3,4),16)/255,tonumber(hex:sub(5,6),16)/255,1)
    end
    for key,hex in pairs({Text='EDF2F7',TextDisabled='B8C4D0',WindowBg='18212B',ChildBg='18212B',
        PopupBg='18212B',FrameBg='263544',FrameBgHovered='34495E',FrameBgActive='34495E',
        Border='8CA3B8',Button='263544',ButtonHovered='34495E',ButtonActive='34495E',
        Header='536D84',HeaderHovered='536D84',HeaderActive='536D84',
        CheckMark='A9D6FF',SliderGrab='A9D6FF',SliderGrabActive='A9D6FF',NavHighlight='A9D6FF',
        TitleBg='18212B',TitleBgActive='263544'}) do color(key,hex) end
end
return Gui
