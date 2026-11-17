local Config = require 'AimLockDistribution.config'
local Engine = require 'AimLockDistribution.engine'
local Statistics = require 'AimLockDistribution.statistics'

local Simulation = {}
Simulation.__index = Simulation

local allowed_trials = { [100] = true, [500] = true, [1000] = true }

function Simulation.new(config, random_unit)
    local normalized, err = Config.validate(config)
    if not normalized then return nil, err end
    local engine, engine_error = Engine.new(normalized.distribution, random_unit, normalized.general.seed)
    if not engine then return nil, engine_error end
    local statistics = assert(Statistics.new(normalized.distribution))
    return setmetatable({ config = normalized, engine = engine, statistics = statistics }, Simulation)
end

function Simulation:run(trials)
    if not allowed_trials[trials] then
        return nil, 'Jumlah simulasi harus 100, 500, atau 1000.'
    end
    if self.statistics.total > 9007199254740991 - trials then
        return nil, 'Statistik mencapai batas integer; reset sebelum melanjutkan.'
    end

    local batch = assert(Statistics.new(self.config.distribution))
    for _ = 1, trials do
        local key, err = self.engine:pick()
        if not key then return nil, err end
        assert(batch:record(key))
    end
    local snapshot = batch:snapshot()
    -- Commit statistik hanya setelah seluruh batch berhasil.
    for _, row in ipairs(snapshot.rows) do
        assert(self.statistics:record(row.key, row.count))
    end
    return {
        trials = trials,
        seed = self.engine.seed,
        batch = snapshot,
        cumulative = self.statistics:snapshot()
    }
end

function Simulation:snapshot()
    return self.statistics:snapshot()
end

function Simulation:reset()
    self.statistics:reset()
end

function Simulation:configuration()
    return Config.validate(self.config)
end

return Simulation
