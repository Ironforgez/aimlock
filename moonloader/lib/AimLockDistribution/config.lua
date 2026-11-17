local Config = {}

Config.BODY_PARTS = {
    { key = 'torso', label = 'Torso' },
    { key = 'left_arm', label = 'Left Arm' },
    { key = 'right_arm', label = 'Right Arm' },
    { key = 'left_leg', label = 'Left Leg' },
    { key = 'right_leg', label = 'Right Leg' },
    { key = 'head', label = 'Head' }
}

local default_weights = { 40, 15, 15, 10, 10, 10 }
local total_tolerance = 0.0000001

local function is_finite(value)
    return type(value) == 'number' and value == value
        and value ~= math.huge and value ~= -math.huge
end

local function trim(value)
    return value:match('^%s*(.-)%s*$')
end

function Config.defaults()
    local result = { general = { command = 'hitdist', seed = 'auto' }, distribution = {} }
    for index, part in ipairs(Config.BODY_PARTS) do
        result.distribution[part.key] = default_weights[index]
    end
    return result
end

function Config.validate_distribution(distribution)
    if type(distribution) ~= 'table' then
        return nil, 'Section [distribution] harus berupa tabel.'
    end

    local weights, total = {}, 0
    for _, part in ipairs(Config.BODY_PARTS) do
        local weight = distribution[part.key]
        if not is_finite(weight) or weight < 0 or weight > 100 then
            return nil, part.key .. ' harus berupa angka finite antara 0 dan 100.'
        end
        weights[part.key] = weight
        total = total + weight
    end
    for key in pairs(distribution) do
        if weights[key] == nil then
            return nil, 'Body part tidak dikenal: ' .. tostring(key)
        end
    end
    if math.abs(total - 100) > total_tolerance then
        return nil, string.format('Total probabilitas harus 100%%; saat ini %.10g%%.', total)
    end
    return weights, total
end

function Config.validate(config)
    if type(config) ~= 'table' then
        return nil, 'Konfigurasi harus berupa tabel.'
    end
    for key in pairs(config) do
        if key ~= 'general' and key ~= 'distribution' then
            return nil, 'Section tidak dikenal: ' .. tostring(key)
        end
    end

    local weights, err = Config.validate_distribution(config.distribution)
    if not weights then
        return nil, err
    end

    local general = config.general
    if general == nil then general = {} end
    if type(general) ~= 'table' then
        return nil, 'Section [general] harus berupa tabel.'
    end
    for key in pairs(general) do
        if key ~= 'command' and key ~= 'seed' then
            return nil, 'Pengaturan general tidak dikenal: ' .. tostring(key)
        end
    end

    local command = general.command
    if command == nil then command = 'hitdist' end
    if type(command) ~= 'string' or #command > 20
        or not command:match('^[a-zA-Z][a-zA-Z0-9_]*$') then
        return nil, 'Command harus 1-20 karakter ASCII, diawali huruf, tanpa slash/spasi.'
    end

    local seed = general.seed
    if seed == nil then seed = 'auto' end
    if seed ~= 'auto' and (not is_finite(seed) or seed ~= math.floor(seed)
        or seed < 1 or seed > 2147483646) then
        return nil, 'Seed harus auto atau bilangan bulat 1..2147483646.'
    end

    return {
        general = { command = command:lower(), seed = seed },
        distribution = weights
    }
end

function Config.parse(text)
    if type(text) ~= 'string' then
        return nil, 'Isi INI harus berupa string.'
    end
    text = text:gsub('^\239\187\191', '')
    local config, seen_sections = {}, {}
    local section, line_number = nil, 0
    for line in (text .. '\n'):gmatch('(.-)\n') do
        line_number = line_number + 1
        line = trim(line:gsub('[;#].*$', ''))
        if line ~= '' then
            local section_name = line:match('^%[([a-z_]+)%]$')
            if section_name then
                if (section_name ~= 'general' and section_name ~= 'distribution')
                    or seen_sections[section_name] then
                    return nil, 'Section tidak dikenal/duplikat pada baris ' .. line_number
                end
                section = section_name
                seen_sections[section] = true
                config[section] = {}
            else
                local key, value = line:match('^([a-z_]+)%s*=%s*(.-)$')
                if not section or not key or value == '' then
                    return nil, 'Format INI tidak valid pada baris ' .. line_number
                end
                if config[section][key] ~= nil then
                    return nil, 'Key duplikat pada baris ' .. line_number .. ': ' .. key
                end
                if section == 'distribution' or key == 'seed' then
                    if not (section == 'general' and key == 'seed' and value == 'auto') then
                        value = tonumber(value)
                        if value == nil then
                            return nil, 'Angka tidak valid pada baris ' .. line_number
                        end
                    end
                end
                config[section][key] = value
            end
        end
    end
    return Config.validate(config)
end

function Config.load(path)
    if type(path) ~= 'string' or path == '' then
        return nil, 'Path konfigurasi tidak valid.'
    end
    local file, open_error = io.open(path, 'rb')
    if not file then
        return nil, 'Tidak dapat membaca INI: ' .. tostring(open_error)
    end
    local text, read_error = file:read('*a')
    file:close()
    if not text then
        return nil, 'Gagal membaca INI: ' .. tostring(read_error)
    end
    return Config.parse(text)
end

return Config
