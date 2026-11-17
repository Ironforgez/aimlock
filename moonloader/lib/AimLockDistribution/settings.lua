local Config = require 'AimLockDistribution.config'
local Settings = {}
local defaults = {
    enabled = false, max_distance = 60, fov_radius = 0.12,
    target_height = 0.3, crosshair_x = 0.53, crosshair_y = 0.4,
    random_aim = true, random_interval_ms = 300, random_seed = 'auto',
    telemetry_enabled = true, telemetry_match_window_ms = 750, telemetry_flush_interval_ms = 1000,
    gui_enabled = true, gui_command = 'aimlock', gui_log_command = 'aimlog'
}
local default_distribution = { torso=20, left_arm=20, right_arm=20, left_leg=15, right_leg=15, head=10 }
local bounds = {
    max_distance = { 1, 300 }, fov_radius = { 0.01, 0.5 },
    target_height = { -1, 1 }, crosshair_x = { 0, 1 }, crosshair_y = { 0, 1 },
    random_interval_ms = { 100, 5000 }, telemetry_match_window_ms = { 50, 3000 },
    telemetry_flush_interval_ms = { 100, 10000 }
}
local booleans = { enabled=true, random_aim=true, telemetry_enabled=true, gui_enabled=true }
local strings = { gui_command=true, gui_log_command=true }

function Settings.validate(values)
    if type(values) ~= 'table' then return nil, 'Pengaturan harus berupa tabel.' end
    local result = {}
    for key, value in pairs(defaults) do result[key] = value end
    for key, value in pairs(values) do
        if key ~= 'distribution' then
            if defaults[key] == nil then return nil, 'Pengaturan tidak dikenal: ' .. tostring(key) end
            if booleans[key] then
                if type(value) ~= 'boolean' then return nil, key .. ' harus true atau false.' end
            elseif strings[key] then
                if type(value) ~= 'string' or #value > 20 or not value:match('^[a-z][a-z0-9_]*$') then
                    return nil, key .. ' harus 1..20 karakter a-z, 0-9, underscore; diawali huruf.'
                end
            elseif key ~= 'random_seed' then
                local range = bounds[key]
                if type(value) ~= 'number' or value ~= value or value < range[1] or value > range[2] then
                    return nil, key .. ' di luar rentang ' .. range[1] .. '..' .. range[2]
                end
                if (key == 'random_interval_ms' or key == 'telemetry_match_window_ms'
                    or key == 'telemetry_flush_interval_ms') and value ~= math.floor(value) then
                    return nil, key .. ' harus bilangan bulat.'
                end
            end
            result[key] = value
        end
    end
    if result.gui_command == result.gui_log_command then return nil, 'Command GUI dan log harus berbeda.' end
    local distribution = values.distribution
    if distribution == nil then distribution = default_distribution end
    local normalized, err = Config.validate({
        general = { seed = result.random_seed }, distribution = distribution
    })
    if not normalized then return nil, err end
    result.distribution = normalized.distribution
    result.random_seed = normalized.general.seed
    return result
end

function Settings.parse(text)
    if type(text) ~= 'string' then return nil, 'Isi INI tidak valid.' end
    local sections, section = {}, nil
    text = text:gsub('^\239\187\191', '')
    for line in (text .. '\n'):gmatch('(.-)\n') do
        line = line:gsub('[;#].*$', ''):match('^%s*(.-)%s*$')
        if line ~= '' then
            local name = line:match('^%[([a-z_]+)%]$')
            if name then
                if (name ~= 'aimlock' and name ~= 'distribution') or sections[name] then
                    return nil, 'Section INI tidak dikenal atau duplikat: ' .. name
                end
                sections[name], section = {}, name
            else
                local key, value = line:match('^([a-z_]+)%s*=%s*(.-)$')
                if not section or not key or sections[section][key] ~= nil then
                    return nil, 'Baris INI salah atau duplikat: ' .. line
                end
                if section == 'aimlock' and key == 'distribution' then
                    return nil, 'Gunakan section [distribution] untuk bobot probabilitas.'
                end
                if section == 'aimlock' and booleans[key] then
                    if value ~= 'true' and value ~= 'false' then return nil, key .. ' harus true/false.' end
                    value = value == 'true'
                elseif not (section == 'aimlock' and (strings[key] or key == 'random_seed' and value == 'auto')) then
                    value = tonumber(value)
                    if value == nil then return nil, 'Nilai bukan angka: ' .. key end
                end
                sections[section][key] = value
            end
        end
    end
    if not sections.aimlock then return nil, 'Section [aimlock] tidak ditemukan.' end
    sections.aimlock.distribution = sections.distribution
    return Settings.validate(sections.aimlock)
end

function Settings.load(path)
    local file, err = io.open(path, 'rb')
    if not file then return nil, 'Gagal membaca konfigurasi: ' .. tostring(err) end
    local text, read_error = file:read('*a')
    file:close()
    if not text then return nil, tostring(read_error) end
    return Settings.parse(text)
end

return Settings
