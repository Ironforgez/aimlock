local Camera = require 'AimLockDistribution.camera'
local AimPoint = require 'AimLockDistribution.aim_point'
local World = {}
World.__index = World

local function vector(x, y, z) return { x = x, y = y, z = z } end

function World.new(settings, api, random_unit)
    local aim_point = assert(AimPoint.new(settings, random_unit))
    return setmetatable({ settings = settings, api = api, aim_point = aim_point }, World)
end

function World:reset_aim()
    self.aim_point:reset()
    self.last_aim=nil
end

function World:telemetry_snapshot()
    local last=self.last_aim
    if not last then return {} end
    return {snapshot_target_id=last.target_id,selected_body_part=last.body_part,
        selected_point=vector(last.point.x,last.point.y,last.point.z),
        context_game_ms=last.time,aim_applied=last.applied}
end

function World:validate_target(target)
    local api, settings, ped = self.api, self.settings, target.ped
    if ped == api.PLAYER_PED or not api.doesCharExist(ped) or api.isCharDead(ped) then return nil end
    local connected, player_id = api.sampGetPlayerIdByCharHandle(ped)
    if not connected or api.sampIsPlayerNpc(player_id)
        or (target.id ~= nil and target.id ~= player_id) then return nil end
    local x, y, z = api.getCharCoordinates(ped)
    local px, py, pz = api.getCharCoordinates(api.PLAYER_PED)
    if (x - px)^2 + (y - py)^2 + (z - pz)^2 > settings.max_distance^2 then return nil end
    z = z + settings.target_height
    local visible, sx, sy = api.convert3DCoordsToScreenEx(x, y, z, true, true)
    if not visible then return nil end
    local width, height = api.getScreenResolution()
    if width <= 0 or height <= 0 then return nil end
    local distance = (sx - width * settings.crosshair_x)^2 + (sy - height * settings.crosshair_y)^2
    if (target.id == nil or not settings.random_aim)
        and distance > (height * settings.fov_radius)^2 then return nil end
    local cx, cy, cz = api.getActiveCameraCoordinates()
    if not api.isLineOfSightClear(cx, cy, cz, x, y, z, true, true, false, true, false) then return nil end
    return { ped = ped, id = player_id, point = vector(x, y, z), screen_distance = distance }
end

function World:find_target()
    local best
    for _, ped in ipairs(self.api.getAllChars()) do
        local candidate = self:validate_target({ ped = ped })
        if candidate and (not best or candidate.screen_distance < best.screen_distance) then best = candidate end
    end
    return best
end

function World:point_at(target)
    local api, settings = self.api, self.settings
    local point = target.point
    local frame_time=api.getGameTimer()
    local body_part='torso'
    if settings.random_aim then
        local part, err = self.aim_point:select(target, frame_time)
        if not part then error(err) end
        point = vector(api.getOffsetFromCharInWorldCoords(target.ped,
            part.x, part.y, settings.target_height + part.z))
        target.body_part = part.key
        body_part=part.key
    end
    self.last_aim={target_id=target.id,body_part=body_part,time=frame_time,
        point=vector(point.x,point.y,point.z),applied=false}
    local visible = api.convert3DCoordsToScreenEx(point.x, point.y, point.z, true, true)
    if not visible then return false end
    local origin = vector(api.getActiveCameraCoordinates())
    if not api.isLineOfSightClear(origin.x, origin.y, origin.z, point.x, point.y, point.z,
        true, true, false, true, false) then return false end
    local forward = vector(api.getActiveCameraPointAt())
    local width, height = api.getScreenResolution()
    local ray = vector(api.convertScreenCoordsToWorld3D(width * settings.crosshair_x,
        height * settings.crosshair_y, 100))
    local pitch, yaw = Camera.solve(origin, forward, ray, point)
    if pitch == nil then return false end
    api.setCameraPositionUnfixed(pitch, yaw)
    self.last_aim.applied=true
    return true
end

return World
