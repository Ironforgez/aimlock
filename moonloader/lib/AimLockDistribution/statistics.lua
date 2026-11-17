local Config = require 'AimLockDistribution.config'

local Statistics = {}
Statistics.__index = Statistics

function Statistics.new(distribution)
    local weights, err = Config.validate_distribution(distribution)
    if not weights then return nil, err end
    local self = setmetatable({ weights = weights }, Statistics)
    self:reset()
    return self
end

function Statistics:reset()
    self.total, self.counts = 0, {}
    for _, part in ipairs(Config.BODY_PARTS) do
        self.counts[part.key] = 0
    end
end

function Statistics:record(key, count)
    if self.counts[key] == nil then
        return nil, 'Body part tidak dikenal: ' .. tostring(key)
    end
    if count == nil then count = 1 end
    if type(count) ~= 'number' or count ~= count or count ~= math.floor(count)
        or count < 0 or count == math.huge
        or count > 9007199254740991 - self.total then
        return nil, 'Jumlah harus bilangan bulat non-negatif dalam rentang tepat Lua number.'
    end
    self.counts[key] = self.counts[key] + count
    self.total = self.total + count
    return true
end

function Statistics:snapshot()
    local result = { total = self.total, rows = {} }
    for _, part in ipairs(Config.BODY_PARTS) do
        local count = self.counts[part.key]
        local actual = self.total > 0 and count / self.total * 100 or 0
        result.rows[#result.rows + 1] = {
            key = part.key,
            label = part.label,
            count = count,
            target_percent = self.weights[part.key],
            actual_percent = actual,
            delta_pp = actual - self.weights[part.key]
        }
    end
    return result
end

return Statistics
