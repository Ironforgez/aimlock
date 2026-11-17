script_name('AimLock')
script_author('IronForgez | Arvin_Inc')
script_version('1.4.0')
script_description('Aim tracking, weighted aim points, passive telemetry, configuration and log GUI.')

local active_telemetry
local active_gui

function onExitScript()
    if active_gui then pcall(active_gui.close,active_gui) end
    if active_telemetry then pcall(active_telemetry.close,active_telemetry) end
end

local function message(text)
    sampAddChatMessage('[AimLock] ' .. text, 0xA9D6FFFF)
end

function main()
    local required = {
        'isSampLoaded', 'isSampfuncsLoaded', 'isSampAvailable', 'sampAddChatMessage',
        'getWorkingDirectory', 'wait', 'isKeyDown', 'isPauseMenuActive',
        'isGameWindowForeground', 'sampIsChatInputActive', 'sampIsDialogActive',
        'isSampfuncsConsoleActive', 'doesCharExist', 'isCharDead', 'isCharOnFoot',
        'getCurrentCharWeapon', 'getAllChars', 'sampGetPlayerIdByCharHandle',
        'sampIsPlayerNpc', 'sampIsLocalPlayerSpawned',
        'getCharCoordinates', 'convert3DCoordsToScreenEx', 'getScreenResolution',
        'getActiveCameraCoordinates', 'getActiveCameraPointAt',
        'getOffsetFromCharInWorldCoords', 'getGameTimer',
        'convertScreenCoordsToWorld3D', 'isLineOfSightClear', 'setCameraPositionUnfixed'
    }
    for _, name in ipairs(required) do
        if type(_G[name]) ~= 'function' then
            print('[AimLock] API tidak tersedia: ' .. name)
            return
        end
    end
    if not isSampLoaded() or not isSampfuncsLoaded() then
        print('[AimLock] SA-MP dan SAMPFUNCS diperlukan.')
        return
    end
    local ok, modules = pcall(function()
        return { settings = require 'AimLockDistribution.settings',
            controller = require 'AimLockDistribution.controller', world = require 'AimLockDistribution.world',
            telemetry_runtime = require 'AimLockDistribution.telemetry_runtime',
            gui_runtime = require 'AimLockDistribution.gui_runtime' }
    end)
    if not ok then print('[AimLock] ' .. tostring(modules)); return end
    local config_path=getWorkingDirectory() .. '/config/AimLock1.4.0.ini'
    local settings, err = modules.settings.load(config_path)
    if not settings then print('[AimLock] ' .. tostring(err)); return end
    while not isSampAvailable() do wait(100) end
    local world = modules.world.new(settings, _G)
    local controller = modules.controller.new(settings, {
        validate_target = function(target) return world:validate_target(target) end,
        find_target = function() return world:find_target() end,
        point_at = function(target) return world:point_at(target) end,
        on_toggle = function(enabled) message(enabled and 'ON' or 'OFF') end
    })
    active_telemetry=modules.telemetry_runtime.manager(_G,function()
        local snapshot=world:telemetry_snapshot()
        snapshot.aimlock_enabled=controller.enabled
        snapshot.locked_player_id=controller.target and controller.target.id or nil
        return snapshot
    end)
    local telemetry,telemetry_error=active_telemetry:configure(settings)
    local gui_ok,gui,gui_error=pcall(modules.gui_runtime.start,settings,_G,{
        path=config_path,message=message,
        enabled=function() return controller.enabled end,
        load=function() return modules.settings.load(config_path) end,
        log_path=function()
            local current=active_telemetry.current
            return current and current.log_path or nil
        end,
        telemetry_status=function()
            local current=active_telemetry.current
            return current and current:is_active() and 'Telemetry ON | '..current.log_path
                or 'Telemetry OFF | '..tostring(active_telemetry.last_error or 'Sesi tidak aktif')
        end,
        apply=function(values)
            local validated,validation_error=modules.settings.validate(values)
            if not validated then return nil,validation_error end
            local new_world=modules.world.new(validated,_G)
            settings,world=validated,new_world
            controller.target=nil
            active_telemetry:configure(settings)
            return true
        end
    })
    if gui_ok then active_gui=gui else gui_error=gui end
    if active_gui then
        message('GUI: '..(#active_gui.commands>0 and table.concat(active_gui.commands,' | ') or 'Command belum tersedia; periksa INI.'))
    elseif settings.gui_enabled then print('[AimLock] GUI OFF: '..tostring(gui_error)) end
    message('Siap | Ctrl + X: ON/OFF | Tahan klik kanan untuk lock | Status: '
        .. (controller.enabled and 'ON' or 'OFF'))
    message(settings.random_aim and ('Random aim: ON | Interval: ' .. settings.random_interval_ms .. ' ms')
        or 'Random aim: OFF | Titik tetap')
    if telemetry then
        message('Telemetry: ON | Log: logs/'..telemetry.session_id..'.jsonl')
    elseif settings.telemetry_enabled then
        print('[AimLock] Telemetry OFF: '..tostring(telemetry_error))
        message('Telemetry: OFF | Periksa moonloader.log. Aim tracking tetap tersedia.')
    else
        message('Telemetry: OFF (konfigurasi)')
    end
    while true do
        wait(0)
        local ready = isSampAvailable()
        local blocked = not ready or not isGameWindowForeground() or isPauseMenuActive()
        if not blocked then
            blocked = sampIsChatInputActive() or sampIsDialogActive() or isSampfuncsConsoleActive()
                or not sampIsLocalPlayerSpawned()
        end
        if active_gui then
            active_gui:poll(getGameTimer(),not blocked)
            blocked=blocked or active_gui:is_open()
        end
        local aiming = false
        if not blocked and type(PLAYER_PED) == 'number' and doesCharExist(PLAYER_PED)
            and not isCharDead(PLAYER_PED) and isCharOnFoot(PLAYER_PED) and isKeyDown(0x02) then
            local weapon = getCurrentCharWeapon(PLAYER_PED)
            aiming = weapon >= 22 and weapon <= 32
        end
        local updated, update_error = pcall(controller.step, controller, {
            ctrl = isKeyDown(0x11), x = isKeyDown(0x58), blocked = blocked, aiming = aiming
        })
        if not updated then
            controller.enabled, controller.target = false, nil
            print('[AimLock] Dinonaktifkan setelah error: ' .. tostring(update_error))
            if ready then message('OFF: error runtime. Periksa moonloader.log.') end
        end
        if not controller.target then world:reset_aim() end
        if active_telemetry then active_telemetry:poll(getGameTimer()) end
    end
end
