local Controller = {}
Controller.__index = Controller

function Controller.new(settings, api)
    return setmetatable({ enabled = settings.enabled, chord_down = false, target = nil, api = api }, Controller)
end

function Controller:step(input)
    local chord = input.ctrl and input.x
    local pressed = chord and not self.chord_down
    self.chord_down = chord
    if input.blocked then self.target = nil; return false end
    if pressed then
        self.enabled = not self.enabled
        self.target = nil
        self.api.on_toggle(self.enabled)
    end
    if not self.enabled or not input.aiming then self.target = nil; return false end
    if self.target then self.target = self.api.validate_target(self.target) end
    if not self.target then self.target = self.api.find_target() end
    if not self.target then return false end
    -- Titik tubuh yang terhalang tidak mengganti pemain yang sedang dikunci.
    if not self.api.point_at(self.target) then return false end
    return true
end

return Controller
