local Engine = require 'AimLockDistribution.engine'
local AimPoint = {}
AimPoint.__index = AimPoint

-- Offset lokal relatif terhadap target_height; sumbu X mengikuti arah kanan ped.
local offsets = {
    torso = { x=0, y=0, z=0 },
    left_arm = { x=-0.28, y=0, z=-0.05 },
    right_arm = { x=0.28, y=0, z=-0.05 },
    left_leg = { x=-0.15, y=0, z=-0.9 },
    right_leg = { x=0.15, y=0, z=-0.9 },
    head = { x=0, y=0, z=0.5 }
}

function AimPoint.new(settings, random_unit)
    local engine, err = Engine.new(settings.distribution, random_unit, settings.random_seed)
    if not engine then return nil, err end
    return setmetatable({ engine=engine, interval=settings.random_interval_ms }, AimPoint)
end

function AimPoint:reset()
    self.ped, self.id, self.part, self.last_ms = nil, nil, nil, nil
end

function AimPoint:select(target, now_ms)
    if type(now_ms) ~= 'number' or now_ms ~= now_ms or math.abs(now_ms) == math.huge
        or now_ms ~= math.floor(now_ms) then
        return nil, 'Timer aim harus berupa integer finite.'
    end
    now_ms = now_ms % 4294967296
    local changed = self.ped ~= target.ped or self.id ~= target.id
    local elapsed = self.last_ms and (now_ms - self.last_ms) % 4294967296 or 0
    if not self.part or changed or elapsed >= self.interval then
        local part, err = self.engine:pick()
        if not part then return nil, err end
        self.part, self.last_ms, self.ped, self.id = part, now_ms, target.ped, target.id
    end
    local offset = offsets[self.part]
    return { key=self.part, x=offset.x, y=offset.y, z=offset.z }
end

return AimPoint
