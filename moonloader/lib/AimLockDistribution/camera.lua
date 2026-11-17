local Camera = {}

function Camera.wrap(angle)
    return (angle + math.pi) % (2 * math.pi) - math.pi
end

local function atan2(y, x)
    if x > 0 then return math.atan(y / x) end
    if x < 0 then return math.atan(y / x) + (y >= 0 and math.pi or -math.pi) end
    if y > 0 then return math.pi / 2 end
    if y < 0 then return -math.pi / 2 end
    return 0
end

local function angles(origin, point)
    for _, item in ipairs({ origin, point }) do
        for _, key in ipairs({ 'x', 'y', 'z' }) do
            local value = item[key]
            if type(value) ~= 'number' or value ~= value or math.abs(value) == math.huge then return nil end
        end
    end
    local x, y, z = point.x - origin.x, point.y - origin.y, point.z - origin.z
    local flat = math.sqrt(x * x + y * y)
    if flat * flat + z * z < 0.00000001 then return nil end
    return atan2(z, flat), atan2(y, x)
end

function Camera.solve(origin, forward, crosshair_ray, target)
    local front_pitch, front_yaw = angles(origin, forward)
    local ray_pitch, ray_yaw = angles(origin, crosshair_ray)
    local target_pitch, target_yaw = angles(origin, target)
    if not front_pitch or not ray_pitch or not target_pitch then return nil, 'Vektor kamera tidak valid.' end
    local pitch = front_pitch + Camera.wrap(target_pitch - ray_pitch)
    pitch = math.max(math.rad(-85), math.min(math.rad(60), pitch))
    -- GTA menyimpan beta berlawanan arah dengan vektor depan kamera.
    local yaw = Camera.wrap(front_yaw + math.pi + Camera.wrap(target_yaw - ray_yaw))
    return pitch, yaw
end

return Camera
