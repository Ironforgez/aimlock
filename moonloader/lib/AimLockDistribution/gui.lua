local Store = require 'AimLockDistribution.config_store'
local Gui={}
Gui.__index=Gui
local pages={'Konfigurasi','Distribusi','Telemetry','Log'}
local part_labels={torso='Torso',left_arm='Lengan kiri',right_arm='Lengan kanan',
    left_leg='Kaki kiri',right_leg='Kaki kanan',head='Kepala'}
local event_names={'all','shot','damage_report','correlation_update','shot_window_closed',
    'damage_window_closed','observer_error','session_start','session_end','telemetry_overflow',
    'shot_candidates_truncated'}

function Gui.new(imgui,ffi,model,logs,bridge)
    return setmetatable({ui=imgui,ffi=ffi,model=model,logs=logs,bridge=bridge,opened=imgui.new.bool(false),
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
    end
    if description then ui.TextWrapped('%s',description) end
end
function Gui:configuration()
    local ui=self.ui
    ui.TextUnformatted('Konfigurasi tracking')
    ui.TextWrapped('%s','Status aim sekarang: '..(self.bridge.enabled() and 'ON' or 'OFF')..'. Ctrl + X mengubah status saat panel ditutup.')
    self:field('enabled','Aktif saat script dimuat','bool')
    self:field('max_distance','Jarak maksimum (1..300)','float')
    self:field('fov_radius','Radius FOV (0.01..0.5)','float')
    self:field('target_height','Offset tinggi (-1..1)','float')
    self:field('crosshair_x','Crosshair X (0..1)','float')
    self:field('crosshair_y','Crosshair Y (0..1)','float')
    ui.Separator()
    ui.TextUnformatted('GUI dan command (berlaku setelah reload script)')
    self:field('gui_enabled','Aktifkan GUI saat startup','bool')
    self:field('gui_command','Command panel tanpa /','text')
    self:field('gui_log_command','Command log tanpa /','text')
end
function Gui:distribution()
    local ui=self.ui
    ui.TextUnformatted('Distribusi titik aim')
    self:field('random_aim','Random aim','bool')
    self:field('random_interval_ms','Interval ms (100..5000)','int')
    self:field('random_seed','Seed: auto atau integer','text','Seed tetap mengulang urutan acak setelah penerapan / reload.')
    ui.Separator()
    for _,key in ipairs(Store.parts) do self:field(key,part_labels[key]..' (%)','float',nil,self.model.draft.distribution) end
    ui.TextUnformatted(string.format('Total bobot: %.4f%% / 100%%',self.model:total()))
    ui.TextWrapped('%s','Bobot nol diizinkan. Total harus 100%. Bobot mengatur titik aim dan tidak menjamin hasil hit.')
end
function Gui:telemetry()
    local ui=self.ui
    ui.TextUnformatted('Pencatatan tembakan')
    self:field('telemetry_enabled','Rekam telemetry','bool')
    self:field('telemetry_match_window_ms','Jendela korelasi ms (50..3000)','int')
    self:field('telemetry_flush_interval_ms','Interval tulis ms (100..10000)','int')
    ui.Separator()
    ui.TextWrapped('%s',self.bridge.telemetry_status())
    ui.TextWrapped('%s','Laporan berasal dari client. Status server tetap unknown. Kandidat korelasi bukan bukti hit server.')
    ui.TextWrapped('%s','Menerapkan konfigurasi memulai sesi log baru dan menutup sesi lama. Pencatatan terpisah dari Ctrl + X.')
    if ui.Button('Lihat log sesi aktif') then self.page=4; self.bridge.request('current') end
end
function Gui:log_page()
    local ui,logs=self.ui,self.logs
    ui.TextUnformatted('Log tembakan | laporan client, server unknown')
    if ui.Button('Daftar ulang file') then self.bridge.request('files') end
    ui.SameLine(); if ui.Button('Sesi aktif') then self.bridge.request('current') end
    if ui.BeginCombo('File log',logs.path and logs.path:match('[^/\\]+$') or 'Pilih file') then
        for _,path in ipairs(self.files) do
            if ui.Selectable(path:match('[^/\\]+$'),path==logs.path) then self.bridge.request('select',path) end
        end
        if #self.files==0 then ui.TextUnformatted('Belum ada file log. Aktifkan telemetry dan tunggu flush.') end
        ui.EndCombo()
    end
    ui.Checkbox('Refresh otomatis',self.auto)
    if ui.Button('Refresh') then self.bridge.request('refresh') end
    ui.SameLine(); if ui.Button('Bersihkan tampilan') then self.bridge.request('clear') end
    ui.TextWrapped('%s','Bersihkan tampilan hanya mengosongkan panel; file log tetap tersimpan.')
    ui.PushItemWidth(160)
    if ui.InputText('Cari isi log',self.search,128) then logs.filter=self.ffi.string(self.search) end
    if ui.InputText('ID target',self.target,12) then logs.target=self.ffi.string(self.target) end
    if ui.BeginCombo('Event',logs.event) then
        for _,name in ipairs(event_names) do if ui.Selectable(name,logs.event==name) then logs.event=name end end
        ui.EndCombo()
    end
    ui.PopItemWidth()
    ui.TextWrapped('%s',logs.status)
    local rows=logs:visible()
    ui.TextUnformatted(string.format('%d terlihat / %d dimuat | %d baris rusak dilewati | %d event lama dilepas',
        #rows,#logs.rows,logs.skipped,logs.dropped))
    local height=math.max(90,ui.GetContentRegionAvail().y*0.55)
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
    if #rows==0 then ui.TextWrapped('%s',#logs.rows==0 and 'Belum ada event. Pilih sesi log atau tunggu telemetry menulis data.' or 'Tidak ada event sesuai filter. Kosongkan pencarian / ID atau pilih all.') end
    ui.TextUnformatted('Detail event (JSON asli)')
    ui.BeginChild('event_detail',ui.ImVec2(0,0),true)
    ui.SetWindowFontScale(self.scale[0])
    ui.TextWrapped('%s',logs.selected and logs.selected.raw or 'Pilih baris untuk melihat waktu, senjata, titik, dan kandidat korelasi.')
    ui.EndChild()
end
function Gui:draw()
    self:sync()
    local ui=self.ui
    local display=ui.GetIO().DisplaySize or ui.ImVec2(1280,720)
    local width,height=math.max(320,display.x-24),math.max(240,display.y-24)
    ui.SetNextWindowPos(ui.ImVec2(display.x/2,display.y/2),ui.Cond.FirstUseEver,ui.ImVec2(0.5,0.5))
    ui.SetNextWindowSize(ui.ImVec2(math.min(1000,width),math.min(700,height)),ui.Cond.FirstUseEver)
    ui.SetNextWindowSizeConstraints(ui.ImVec2(math.min(620,width),math.min(460,height)),ui.ImVec2(width,height))
    local visible=ui.Begin('AimLock 1.4.0 | Konfigurasi dan Log',self.opened)
    if visible then
        ui.SetWindowFontScale(self.scale[0])
        if ui.IsKeyPressed(ui.GetKeyIndex(ui.Key.Escape),false) then self.opened[0]=false end
        ui.BeginChild('sidebar',ui.ImVec2(140,0),true,ui.WindowFlags.HorizontalScrollbar)
        ui.SetWindowFontScale(self.scale[0])
        ui.TextUnformatted('AimLock 1.4.0'); ui.Separator()
        for index,name in ipairs(pages) do if ui.Selectable(name,self.page==index) then self.page=index end end
        ui.Separator(); ui.TextWrapped('%s','Tutup panel untuk memakai Ctrl + X.')
        ui.PushItemWidth(100); ui.SliderFloat('Ukuran teks',self.scale,1,2,'%.1fx'); ui.PopItemWidth()
        if ui.Button('Tutup panel') then self.opened[0]=false end
        ui.EndChild(); ui.SameLine()
        ui.BeginChild('content',ui.ImVec2(0,0),false,ui.WindowFlags.HorizontalScrollbar)
        ui.SetWindowFontScale(self.scale[0])
        if self.page~=4 then
            local dirty,unsaved=self.model:state()
            ui.TextWrapped('%s',dirty and 'Draft belum diterapkan.' or unsaved and 'Konfigurasi aktif belum tersimpan di INI.' or 'Konfigurasi aktif sesuai INI.')
            for index,button in ipairs({{'Terapkan','apply'},{'Simpan & Terapkan','save'},{'Muat INI','reload'},
                {'Default','defaults'},{'Batalkan draft','discard'}}) do
                if index==2 and ui.GetContentRegionAvail().x>420*self.scale[0] then ui.SameLine() end
                if ui.Button(button[1]) then self.model:request(button[2]) end
            end
            ui.TextWrapped('%s',self.model.message)
            local valid,err=self.model:validate()
            if not valid then ui.TextWrapped('Perlu diperbaiki: %s',err) end
            ui.Separator()
        end
        if self.page==1 then self:configuration() elseif self.page==2 then self:distribution()
        elseif self.page==3 then self:telemetry() else self:log_page() end
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
