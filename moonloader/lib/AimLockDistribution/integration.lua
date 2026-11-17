local Config = require 'AimLockDistribution.config'

local Integration = {}
Integration.__index = Integration

local chat_color = 0xA9D6FFFF
local trial_arguments = { ['100'] = 100, ['500'] = 500, ['1000'] = 1000 }

function Integration.new(simulation, api)
    return setmetatable({
        simulation = simulation,
        api = api or {},
        command = simulation:configuration().general.command,
        registered = false
    }, Integration)
end

function Integration:emit(line)
    self.api.add_chat_message('[HitDist] ' .. line, chat_color)
end

function Integration:help()
    self:emit('/' .. self.command .. ' [stats | reset | simulate 100/500/1000]')
end

function Integration:show_configuration()
    local config = self.simulation:configuration()
    self:emit('Distribusi lokal | seed: ' .. tostring(self.simulation.engine.seed))
    self:emit('Body Part | Target')
    for _, part in ipairs(Config.BODY_PARTS) do
        self:emit(string.format('%s | %.2f%%', part.label, config.distribution[part.key]))
    end
    self:help()
end

function Integration:show_statistics(snapshot, title)
    self:emit(title .. ' | Total: ' .. string.format('%.0f', snapshot.total))
    self:emit('Body Part | Count | Target | Actual | Delta (pp)')
    for _, row in ipairs(snapshot.rows) do
        self:emit(string.format('%s | %.0f | %.2f%% | %.2f%% | %+.2f',
            row.label, row.count, row.target_percent, row.actual_percent, row.delta_pp))
    end
    if snapshot.total == 0 then
        self:emit('Belum ada simulasi. Actual=0%; delta belum bermakna.')
    end
end

function Integration:handle(params)
    if params ~= nil and type(params) ~= 'string' then
        self:help()
        return
    end
    local tokens = {}
    for token in (params or ''):gmatch('%S+') do
        tokens[#tokens + 1] = token:lower()
    end

    if #tokens == 0 then
        self:show_configuration()
    elseif #tokens == 1 and tokens[1] == 'stats' then
        self:show_statistics(self.simulation:snapshot(), 'Statistik kumulatif sesi ini')
    elseif #tokens == 1 and tokens[1] == 'reset' then
        self.simulation:reset()
        self:emit('Statistik direset. Urutan random tetap berlanjut.')
    elseif #tokens == 2 and tokens[1] == 'simulate' and trial_arguments[tokens[2]] then
        local result, err = self.simulation:run(trial_arguments[tokens[2]])
        if not result then
            self:emit('Simulasi gagal: ' .. tostring(err))
            return
        end
        self:show_statistics(result.batch, 'Hasil batch ' .. result.trials)
        self:emit('Total kumulatif: ' .. string.format('%.0f', result.cumulative.total)
            .. '. Lihat /' .. self.command .. ' stats.')
    else
        self:help()
    end
end

function Integration:register()
    if self.registered then
        return nil, 'Command simulator sudah didaftarkan oleh instance ini.'
    end
    for _, name in ipairs({ 'is_command_defined', 'register_command', 'add_chat_message' }) do
        if type(self.api[name]) ~= 'function' then
            return nil, 'API MoonLoader tidak tersedia: ' .. name
        end
    end

    local checked, defined = pcall(self.api.is_command_defined, self.command)
    if not checked or type(defined) ~= 'boolean' then
        return nil, 'Gagal memeriksa registry command client.'
    end
    if defined then
        return nil, '/' .. self.command .. ' sudah terdaftar. Ubah general.command di INI.'
    end

    local ok, registered = pcall(self.api.register_command, self.command, function(params)
        self:handle(params)
    end)
    if not ok or registered ~= true then
        return nil, 'Registrasi /' .. self.command .. ' gagal: ' .. tostring(registered)
    end
    self.registered = true
    return true
end

return Integration
