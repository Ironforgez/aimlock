local Random = {}
Random.__index = Random

local modulus = 2147483647
local multiplier = 16807

local function automatic_seed()
    local value = os.time() % (modulus - 1)
    local entropy = tostring({}) .. ':' .. tostring(os.clock())
    for index = 1, #entropy do
        value = (value * 131 + entropy:byte(index)) % (modulus - 1)
    end
    return value + 1
end

function Random.new(seed)
    if seed == nil or seed == 'auto' then
        seed = automatic_seed()
    end
    if type(seed) ~= 'number' or seed ~= seed or seed ~= math.floor(seed)
        or seed < 1 or seed > modulus - 1 then
        return nil, 'Seed harus bilangan bulat 1..2147483646.'
    end
    return setmetatable({ seed = seed, state = seed }, Random)
end

function Random:next()
    -- Produk maksimum < 2^53, sehingga perkalian tetap tepat pada number LuaJIT.
    self.state = (self.state * multiplier) % modulus
    return (self.state - 1) / (modulus - 1)
end

return Random
