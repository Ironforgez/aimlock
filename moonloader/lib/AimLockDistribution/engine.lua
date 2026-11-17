local Config = require 'AimLockDistribution.config'
local Random = require 'AimLockDistribution.random'

local Engine = {}
Engine.__index = Engine

function Engine.new(distribution, random_unit, seed)
    local weights, total = Config.validate_distribution(distribution)
    if not weights then
        return nil, total
    end
    if random_unit ~= nil and type(random_unit) ~= 'function' then
        return nil, 'Sumber random harus berupa fungsi.'
    end

    local generator, err = Random.new(seed)
    if not generator then return nil, err end
    local cumulative, intervals = 0, {}
    for _, part in ipairs(Config.BODY_PARTS) do
        if weights[part.key] > 0 then
            cumulative = cumulative + weights[part.key]
            intervals[#intervals + 1] = { key = part.key, upper = cumulative }
        end
    end

    return setmetatable({
        total = total,
        intervals = intervals,
        seed = generator.seed,
        random_unit = random_unit or function() return generator:next() end
    }, Engine)
end

function Engine:pick()
    local ok, unit = pcall(self.random_unit)
    if not ok then return nil, 'Sumber random gagal: ' .. tostring(unit) end
    if type(unit) ~= 'number' or unit ~= unit or unit < 0 or unit >= 1 then
        return nil, 'Sumber random harus menghasilkan angka finite pada [0, 1).'
    end

    local draw = unit * self.total
    for _, interval in ipairs(self.intervals) do
        if draw < interval.upper then
            return interval.key
        end
    end
    -- Pembulatan floating point dapat membuat draw sama dengan batas total.
    return self.intervals[#self.intervals].key
end

return Engine
