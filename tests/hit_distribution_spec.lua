package.path = './moonloader/lib/?.lua;./moonloader/lib/?/init.lua;' .. package.path

local release_path = arg and arg[1]
local entrypoint_path = release_path or './moonloader/AimLock.lua'
local load_module = require
if release_path then
    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.script_name = function() end
    env.script_author = function() end
    env.script_version = function() end
    env.script_description = function() end
    env.require = function() error('Release must not load external Lua modules') end
    local chunk = assert(loadfile(release_path))
    setfenv(chunk, env)
    load_module = chunk()
    assert(type(load_module) == 'function', 'Expected private bundled module accessor')
end

local Config = load_module('arfie_hit_distribution.config')
local Random = load_module('arfie_hit_distribution.random')
local Engine = load_module('arfie_hit_distribution.engine')
local Statistics = load_module('arfie_hit_distribution.statistics')
local Simulation = load_module('arfie_hit_distribution.simulation')
local Integration = load_module('arfie_hit_distribution.integration')

local passed, failed = 0, 0
local keys = { 'torso', 'left_arm', 'right_arm', 'left_leg', 'right_leg', 'head' }
local labels = { 'Torso', 'Left Arm', 'Right Arm', 'Left Leg', 'Right Leg', 'Head' }

local function equal(actual, expected, message)
    if actual ~= expected then
        error((message or 'Unexpected value') .. ': expected ' .. tostring(expected)
            .. ', got ' .. tostring(actual), 2)
    end
end

local function near(actual, expected, tolerance)
    assert(type(actual) == 'number', 'Expected a numeric result')
    assert(actual == actual, 'Result must not be NaN')
    if math.abs(actual - expected) > (tolerance or 1e-9) then
        error('Expected approximately ' .. tostring(expected) .. ', got ' .. tostring(actual), 2)
    end
end

local function rejected(value, message)
    equal(value, nil, 'Invalid input must be rejected')
    assert(type(message) == 'string' and #message > 0, 'Expected an actionable error')
end

local function test(name, callback)
    local ok, err = pcall(callback)
    if ok then
        passed = passed + 1
        io.write('PASS ' .. name .. '\n')
    else
        failed = failed + 1
        io.write('FAIL ' .. name .. ': ' .. tostring(err) .. '\n')
    end
end

local function distribution_for(key)
    local weights = {}
    for _, body_part in ipairs(keys) do
        weights[body_part] = body_part == key and 100 or 0
    end
    return weights
end

local function find_row(snapshot, key)
    for _, row in ipairs(snapshot.rows) do
        if row.key == key then
            return row
        end
    end
    error('Missing statistics row: ' .. tostring(key))
end

local function verify_snapshot(snapshot, expected_total)
    equal(snapshot.total, expected_total)
    equal(#snapshot.rows, 6)
    local count_sum, percent_sum, target_sum, delta_sum = 0, 0, 0, 0
    for index, row in ipairs(snapshot.rows) do
        equal(row.key, keys[index], 'Body parts must have a stable order')
        equal(row.label, labels[index])
        assert(row.count >= 0 and row.count % 1 == 0, 'Counts must be nonnegative integers')
        local actual = expected_total == 0 and 0 or row.count / expected_total * 100
        near(row.actual_percent, actual)
        near(row.delta_pp, row.actual_percent - row.target_percent)
        count_sum = count_sum + row.count
        percent_sum = percent_sum + row.actual_percent
        target_sum = target_sum + row.target_percent
        delta_sum = delta_sum + row.delta_pp
    end
    equal(count_sum, expected_total, 'Counts must sum to the total')
    near(percent_sum, expected_total == 0 and 0 or 100)
    near(target_sum, 100)
    near(delta_sum, expected_total == 0 and -100 or 0)
end

local function config_text(extra_general)
    return '[general]\ncommand=hitdist\nseed=auto\n' .. (extra_general or '')
        .. '[distribution]\ntorso=40\nleft_arm=15\nright_arm=15\n'
        .. 'left_leg=10\nright_leg=10\nhead=10\n'
end

test('default distribution is valid and totals 100 percent', function()
    local config = assert(Config.validate(Config.defaults()))
    equal(config.general.command, 'hitdist')
    equal(config.general.seed, 'auto')
    local weights, total = Config.validate_distribution(config.distribution)
    assert(weights)
    near(total, 100)
    local expected = { 40, 15, 15, 10, 10, 10 }
    for index, key in ipairs(keys) do
        equal(weights[key], expected[index])
    end
end)

test('configuration defaults and validation return independent copies', function()
    local first = Config.defaults()
    first.distribution.torso = 0
    equal(Config.defaults().distribution.torso, 40)
    local original = Config.defaults()
    local validated = assert(Config.validate(original))
    original.distribution.torso = 99
    original.general.command = 'changed'
    equal(validated.distribution.torso, 40)
    equal(validated.general.command, 'hitdist')
end)

test('totals below or above 100 and all-zero distributions are rejected', function()
    for _, value in ipairs({ 39, 41 }) do
        local config = Config.defaults()
        config.distribution.torso = value
        rejected(Config.validate(config))
    end
    local empty_weights = distribution_for('missing')
    rejected(Config.validate_distribution(empty_weights))
end)

test('negative, nonnumeric and nonfinite probabilities are rejected', function()
    local invalid = { -1, '40', true, 0 / 0, math.huge, -math.huge, {} }
    for _, value in ipairs(invalid) do
        local config = Config.defaults()
        config.distribution.torso = value
        rejected(Config.validate(config))
    end
end)

test('missing and misspelled body parts are rejected', function()
    local missing = Config.defaults()
    missing.distribution.head = nil
    rejected(Config.validate(missing))
    local unknown = Config.defaults()
    unknown.distribution.hed = 0
    rejected(Config.validate(unknown))
    rejected(Config.validate_distribution(nil))
    rejected(Config.validate_distribution('invalid'))
end)

test('zero weights and decimal probabilities are accepted when total is 100', function()
    local config = Config.defaults()
    config.distribution = distribution_for('head')
    assert(Config.validate(config))
    config.distribution = {
        torso = 40.5, left_arm = 14.5, right_arm = 15,
        left_leg = 10, right_leg = 10, head = 10
    }
    assert(Config.validate(config))
end)

test('INI parser accepts defaults, whitespace, comments and a UTF-8 BOM', function()
    local text = '\239\187\191; local simulator\r\n# no network hooks\r\n'
        .. config_text():gsub('torso=40', ' torso = 40 ')
    local config = assert(Config.parse(text))
    equal(config.distribution.torso, 40)
    equal(config.general.command, 'hitdist')
    equal(config.general.seed, 'auto')
end)

test('INI parser accepts a custom command and deterministic seed', function()
    local text = config_text():gsub('command=hitdist', 'command=arfiehit')
        :gsub('seed=auto', 'seed=12345')
    local config = assert(Config.parse(text))
    equal(config.general.command, 'arfiehit')
    equal(config.general.seed, 12345)
end)

test('INI parser rejects malformed lines, duplicate keys and unknown settings', function()
    local samples = {
        config_text() .. 'this is not a setting\n',
        config_text() .. 'head=10\n',
        config_text() .. 'unknown=0\n',
        config_text() .. '[unknown]\nvalue=1\n',
        config_text() .. '[distribution]\nhead=10\n',
        config_text('unknown=1\n'),
        config_text():gsub('head=10\n', ''),
        config_text():gsub('head=10', 'head=bad'),
        'torso=40\n' .. config_text()
    }
    for _, text in ipairs(samples) do
        rejected(Config.parse(text))
    end
end)

test('command and seed validation reject invalid settings', function()
    for _, command in ipairs({ '', '/hitdist', 'hit dist', 'a;b', string.rep('x', 100) }) do
        local config = Config.defaults()
        config.general.command = command
        rejected(Config.validate(config))
    end
    for _, seed in ipairs({ 0, -1, 1.5, 2147483647, math.huge, 'bad' }) do
        local config = Config.defaults()
        config.general.seed = seed
        rejected(Config.validate(config))
    end
end)

test('configuration loads the shipped INI and reports missing files', function()
    local config = assert(Config.load('./moonloader/config/AimLock.ini'))
    local expected = { 20, 20, 20, 15, 15, 10 }
    for index, key in ipairs(keys) do
        equal(config.distribution[key], expected[index])
    end
    local value, err = Config.load('./tests/does-not-exist-hitdist.ini')
    rejected(value, err)
end)

test('equal seeds reproduce a stream and different seeds change it', function()
    local first = assert(Random.new(12345))
    local second = assert(Random.new(12345))
    local different = assert(Random.new(54321))
    equal(first.seed, 12345)
    local changed = false
    for _ = 1, 1000 do
        local a, b, c = first:next(), second:next(), different:next()
        equal(a, b)
        assert(a >= 0 and a < 1, 'Random unit must be in [0,1)')
        if a ~= c then
            changed = true
        end
    end
    assert(changed, 'Different seeds must not produce the same tested stream')
end)

test('RNG accepts seed endpoints and rejects invalid seeds', function()
    for _, seed in ipairs({ 1, 2147483646 }) do
        local random = assert(Random.new(seed))
        for _ = 1, 100 do
            local value = random:next()
            assert(value >= 0 and value < 1)
        end
    end
    for _, seed in ipairs({ 0, -1, 0.5, 2147483647, 0 / 0, math.huge, 'bad', {} }) do
        rejected(Random.new(seed))
    end
end)

test('auto seed is valid and RNG does not use shared math.random state', function()
    local old_random, old_seed = math.random, math.randomseed
    math.random = function() error('Shared random generator must not be used') end
    math.randomseed = function() error('Shared random generator must not be reseeded') end
    local ok, err = pcall(function()
        for _, make in ipairs({ function() return Random.new() end,
            function() return Random.new('auto') end }) do
            local random = assert(make())
            assert(random.seed >= 1 and random.seed <= 2147483646)
            equal(random.seed % 1, 0)
            assert(random:next() >= 0)
        end
    end)
    math.random, math.randomseed = old_random, old_seed
    assert(ok, err)
end)

test('weighted intervals select every default body part at its boundaries', function()
    local samples = {
        { 0, 'torso' }, { 0.399999, 'torso' },
        { 0.40, 'left_arm' }, { 0.549999, 'left_arm' },
        { 0.55, 'right_arm' }, { 0.699999, 'right_arm' },
        { 0.70, 'left_leg' }, { 0.799999, 'left_leg' },
        { 0.80, 'right_leg' }, { 0.899999, 'right_leg' },
        { 0.90, 'head' }, { 0.999999999, 'head' }
    }
    for _, sample in ipairs(samples) do
        local value = sample[1]
        local engine = assert(Engine.new(Config.defaults().distribution, function() return value end))
        equal(assert(engine:pick()), sample[2])
    end
end)

test('weighted selection is not a uniform split across body parts', function()
    local index = -1
    local engine = assert(Engine.new(Config.defaults().distribution, function()
        index = index + 1
        return index / 100
    end))
    local counts = {}
    for _, key in ipairs(keys) do counts[key] = 0 end
    for _ = 1, 100 do
        local result = assert(engine:pick())
        counts[result] = counts[result] + 1
    end
    local expected = { 40, 15, 15, 10, 10, 10 }
    for i, key in ipairs(keys) do equal(counts[key], expected[i]) end
end)

test('each 100 percent body part excludes all zero-weight parts', function()
    for _, key in ipairs(keys) do
        for _, value in ipairs({ 0, 0.25, 0.5, 0.999999999 }) do
            local engine = assert(Engine.new(distribution_for(key), function() return value end))
            equal(assert(engine:pick()), key)
        end
    end
end)

test('engine rejects invalid weights and invalid random results', function()
    rejected(Engine.new(distribution_for('missing')))
    for _, value in ipairs({ -0.1, 1, 2, 0 / 0, math.huge, '0.5', false }) do
        local engine = assert(Engine.new(Config.defaults().distribution, function() return value end))
        rejected(engine:pick())
    end
    local engine = assert(Engine.new(Config.defaults().distribution, function() return nil end))
    rejected(engine:pick())
    local throwing = assert(Engine.new(Config.defaults().distribution, function()
        error('Injected failure')
    end))
    rejected(throwing:pick())
end)

test('engine uses a validated copy of weights', function()
    local weights = Config.defaults().distribution
    local engine = assert(Engine.new(weights, function() return 0.5 end))
    weights.torso, weights.left_arm = 100, 0
    equal(assert(engine:pick()), 'left_arm')
end)

test('empty statistics are finite and preserve target probabilities', function()
    local stats = assert(Statistics.new(Config.defaults().distribution))
    verify_snapshot(stats:snapshot(), 0)
end)

test('statistics count outcomes and compute actual percentages and deltas', function()
    local stats = assert(Statistics.new(Config.defaults().distribution))
    assert(stats:record('torso', 2))
    assert(stats:record('head'))
    local snapshot = stats:snapshot()
    verify_snapshot(snapshot, 3)
    near(find_row(snapshot, 'torso').actual_percent, 200 / 3)
    near(find_row(snapshot, 'head').actual_percent, 100 / 3)
    near(find_row(snapshot, 'torso').delta_pp, 200 / 3 - 40)
    near(find_row(snapshot, 'left_arm').delta_pp, -15)
end)

test('target-sized counts calculate exactly the configured distribution', function()
    local weights = Config.defaults().distribution
    local stats = assert(Statistics.new(weights))
    for _, key in ipairs(keys) do assert(stats:record(key, weights[key])) end
    local snapshot = stats:snapshot()
    verify_snapshot(snapshot, 100)
    for _, row in ipairs(snapshot.rows) do
        near(row.actual_percent, row.target_percent)
        near(row.delta_pp, 0)
    end
end)

test('invalid statistics updates do not alter accumulated counts', function()
    local stats = assert(Statistics.new(Config.defaults().distribution))
    assert(stats:record('head', 4))
    rejected(stats:record('unknown'))
    for _, amount in ipairs({ -1, 0.5, 0 / 0, math.huge, '2', false }) do
        rejected(stats:record('torso', amount))
    end
    assert(stats:record('torso', 0))
    verify_snapshot(stats:snapshot(), 4)
    equal(find_row(stats:snapshot(), 'head').count, 4)
end)

test('statistics snapshots are copies and reset clears all results', function()
    local stats = assert(Statistics.new(Config.defaults().distribution))
    assert(stats:record('torso', 100))
    local snapshot = stats:snapshot()
    snapshot.total = 0
    snapshot.rows[1].count = 0
    snapshot.rows[1].target_percent = 0
    local unchanged = stats:snapshot()
    equal(unchanged.total, 100)
    equal(unchanged.rows[1].count, 100)
    equal(unchanged.rows[1].target_percent, 40)
    stats:reset()
    verify_snapshot(stats:snapshot(), 0)
end)

test('100, 500 and 1000 trials produce independent batches and cumulative statistics', function()
    local config = Config.defaults()
    config.general.seed = 12345
    local simulation = assert(Simulation.new(config))
    local cumulative = 0
    for _, count in ipairs({ 100, 500, 1000 }) do
        local result = assert(simulation:run(count))
        cumulative = cumulative + count
        equal(result.trials, count)
        verify_snapshot(result.batch, count)
        verify_snapshot(result.cumulative, cumulative)
        verify_snapshot(simulation:snapshot(), cumulative)
    end
end)

test('simulation handles a 100 percent distribution at each requested batch size', function()
    local config = Config.defaults()
    config.distribution = distribution_for('head')
    config.general.seed = 111
    local simulation = assert(Simulation.new(config))
    for _, count in ipairs({ 100, 500, 1000 }) do
        local result = assert(simulation:run(count))
        equal(find_row(result.batch, 'head').count, count)
        equal(find_row(result.batch, 'head').actual_percent, 100)
        for _, row in ipairs(result.batch.rows) do
            if row.key ~= 'head' then equal(row.count, 0) end
        end
    end
end)

test('simulation rejects invalid trial counts without changing statistics', function()
    local simulation = assert(Simulation.new(Config.defaults()))
    for _, count in ipairs({ 0, -100, 1, 99, 101, 100.5, 1001, '100', math.huge, 0 / 0 }) do
        rejected(simulation:run(count))
    end
    rejected(simulation:run(nil))
    verify_snapshot(simulation:snapshot(), 0)
end)

test('simulation reset clears counters and configuration is a defensive copy', function()
    local config = Config.defaults()
    local simulation = assert(Simulation.new(config, function() return 0 end))
    config.distribution.torso = 1
    local exposed = simulation:configuration()
    equal(exposed.distribution.torso, 40)
    exposed.distribution.torso = 99
    exposed.general.command = 'changed'
    equal(simulation:configuration().distribution.torso, 40)
    equal(simulation:configuration().general.command, 'hitdist')
    assert(simulation:run(100))
    simulation:reset()
    verify_snapshot(simulation:snapshot(), 0)
end)

test('failed random generation cannot leave partial simulation statistics', function()
    local calls = 0
    local simulation = assert(Simulation.new(Config.defaults(), function()
        calls = calls + 1
        if calls == 120 then return 1 end
        return 0
    end))
    assert(simulation:run(100))
    rejected(simulation:run(100))
    local snapshot = simulation:snapshot()
    verify_snapshot(snapshot, 100)
    equal(find_row(snapshot, 'torso').count, 100)
end)

local function integration_fixture(command, occupied, registration_result)
    local config = Config.defaults()
    if command then config.general.command = command end
    local simulation = assert(Simulation.new(config, function() return 0 end))
    local fixture = { messages = {}, registration_calls = 0, collision_calls = 0 }
    fixture.api = {
        is_command_defined = function(name)
            fixture.collision_calls = fixture.collision_calls + 1
            fixture.checked_name = name
            return occupied or false
        end,
        register_command = function(name, callback)
            fixture.registration_calls = fixture.registration_calls + 1
            fixture.registered_name = name
            fixture.callback = callback
            if registration_result == nil then return true end
            return registration_result
        end,
        add_chat_message = function(text, color)
            assert(type(text) == 'string' and #text > 0)
            assert(type(color) == 'number')
            fixture.messages[#fixture.messages + 1] = text
        end
    }
    fixture.simulation = simulation
    fixture.integration = assert(Integration.new(simulation, fixture.api))
    return fixture
end

test('integration registers the configurable command only after a collision check', function()
    local fixture = integration_fixture('arfiehit')
    assert(fixture.integration:register())
    equal(fixture.collision_calls, 1)
    equal(fixture.checked_name, 'arfiehit')
    equal(fixture.registered_name, 'arfiehit')
    equal(fixture.registration_calls, 1)
    assert(type(fixture.callback) == 'function')
end)

test('occupied command and registration failure leave existing commands alone', function()
    local occupied = integration_fixture(nil, true)
    rejected(occupied.integration:register())
    equal(occupied.registration_calls, 0)
    local failure = integration_fixture(nil, false, false)
    rejected(failure.integration:register())
    equal(failure.registration_calls, 1)
    verify_snapshot(failure.simulation:snapshot(), 0)
end)

test('missing integration APIs prevent unsafe registration', function()
    for _, name in ipairs({ 'is_command_defined', 'register_command', 'add_chat_message' }) do
        local fixture = integration_fixture()
        fixture.api[name] = nil
        rejected(fixture.integration:register())
        equal(fixture.registration_calls, 0)
    end
end)

test('configuration and statistics commands show all body parts without simulating', function()
    local fixture = integration_fixture()
    assert(fixture.integration:register())
    fixture.callback('')
    fixture.callback('stats')
    local text = table.concat(fixture.messages, '\n')
    for _, label in ipairs(labels) do
        assert(text:find(label, 1, true), 'Missing body part from local output: ' .. label)
    end
    assert(text:find('40', 1, true), 'Expected target probability in output')
    assert(text:find('|', 1, true), 'Expected readable table column delimiters')
    verify_snapshot(fixture.simulation:snapshot(), 0)
end)

test('simulate commands update statistics and reset clears them', function()
    local fixture = integration_fixture()
    assert(fixture.integration:register())
    fixture.callback('  simulate 100  ')
    verify_snapshot(fixture.simulation:snapshot(), 100)
    fixture.callback('simulate 500')
    verify_snapshot(fixture.simulation:snapshot(), 600)
    fixture.callback('simulate 1000')
    verify_snapshot(fixture.simulation:snapshot(), 1600)
    fixture.callback('stats')
    verify_snapshot(fixture.simulation:snapshot(), 1600)
    fixture.callback('reset')
    verify_snapshot(fixture.simulation:snapshot(), 0)
    assert(#fixture.messages > 0, 'Expected local chat feedback')
end)

test('unknown or malformed commands display feedback without simulating', function()
    local fixture = integration_fixture()
    assert(fixture.integration:register())
    for _, command in ipairs({ 'simulate', 'simulate 1', 'simulate 100.0',
        'simulate 100 extra', 'simulate -100', 'simulate 0100',
        'stats extra', 'reset extra', 'unknown' }) do
        local before = #fixture.messages
        fixture.callback(command)
        assert(#fixture.messages > before, 'Invalid commands need usage feedback')
        verify_snapshot(fixture.simulation:snapshot(), 0)
    end
end)

test('integration rejects repeated registration and failed registry queries', function()
    local registered = integration_fixture()
    assert(registered.integration:register())
    rejected(registered.integration:register())
    equal(registered.registration_calls, 1)

    for _, value in ipairs({ 'false', 0 }) do
        local fixture = integration_fixture()
        fixture.api.is_command_defined = function() return value end
        rejected(fixture.integration:register())
        equal(fixture.registration_calls, 0)
    end
    local throwing = integration_fixture()
    throwing.api.is_command_defined = function() error('Registry unavailable') end
    rejected(throwing.integration:register())
    equal(throwing.registration_calls, 0)
end)

local function entrypoint_fixture()
    local fixture = { messages = {}, logs = {}, waits = {}, registrations = 0 }
    local env = setmetatable({}, { __index = _G })
    fixture.env = env
    env._G = env
    env.script_name = function(name) fixture.name = name end
    env.script_author = function() end
    env.script_version = function() end
    env.script_description = function() end
    env.print = function(message) fixture.logs[#fixture.logs + 1] = message end
    env.isSampLoaded = function() return true end
    env.isSampfuncsLoaded = function() return true end
    env.isSampAvailable = function() return true end
    env.sampIsChatCommandDefined = function() return false end
    env.sampRegisterChatCommand = function(name, callback)
        fixture.registrations = fixture.registrations + 1
        fixture.command, fixture.callback = name, callback
        return true
    end
    env.sampAddChatMessage = function(text) fixture.messages[#fixture.messages + 1] = text end
    env.getWorkingDirectory = function() return './moonloader' end
    env.wait = function(milliseconds)
        fixture.waits[#fixture.waits + 1] = milliseconds
        assert(#fixture.waits < 20, 'Unexpected infinite readiness loop')
    end
    fixture.run = function()
        local chunk = assert(loadfile(entrypoint_path))
        setfenv(chunk, env)
        local bundled_require = chunk()
        if fixture.on_load then fixture.on_load(bundled_require) end
        assert(type(env.main) == 'function', 'MoonLoader main entrypoint must exist')
        env.main()
    end
    return fixture
end

test('entrypoint registers once and keeps the callback alive after SA-MP is ready', function()
    local fixture = entrypoint_fixture()
    local availability_checks = 0
    fixture.env.isSampAvailable = function()
        availability_checks = availability_checks + 1
        return availability_checks >= 3
    end
    fixture.run()
    equal(fixture.name, 'AimLock')
    equal(fixture.registrations, 1)
    equal(fixture.command, 'hitdist')
    equal(fixture.waits[1], 100)
    equal(fixture.waits[2], 100)
    equal(fixture.waits[3], -1)
    equal(#fixture.logs, 0)
    fixture.callback('simulate 100')
    assert(table.concat(fixture.messages, '\n'):find('100', 1, true))
end)

test('entrypoint disables integration when SA-MP or SAMPFUNCS is unavailable', function()
    for _, name in ipairs({ 'isSampLoaded', 'isSampfuncsLoaded' }) do
        local fixture = entrypoint_fixture()
        fixture.env[name] = function() return false end
        fixture.run()
        equal(fixture.registrations, 0)
        equal(#fixture.waits, 0)
        assert(#fixture.logs > 0, 'Missing dependency needs an actionable log entry')
    end
end)

test('entrypoint reports each missing required API before registering anything', function()
    for _, name in ipairs({ 'isSampLoaded', 'isSampfuncsLoaded', 'isSampAvailable',
        'sampIsChatCommandDefined', 'sampRegisterChatCommand', 'sampAddChatMessage',
        'getWorkingDirectory', 'wait' }) do
        local fixture = entrypoint_fixture()
        fixture.env[name] = false
        fixture.run()
        equal(fixture.registrations, 0)
        equal(#fixture.waits, 0)
        local logs = table.concat(fixture.logs, '\n')
        assert(logs:find(name, 1, true), 'Missing API name must be included in logs')
    end
end)

test('entrypoint resolves bundled modules and reports missing configuration', function()
    local missing_module = entrypoint_fixture()
    missing_module.env.require = function() error('Module file missing') end
    missing_module.run()
    if release_path then
        equal(missing_module.registrations, 1)
        equal(#missing_module.logs, 0)
    else
        equal(missing_module.registrations, 0)
        assert(#missing_module.logs > 0)
    end

    local missing_ini = entrypoint_fixture()
    missing_ini.env.getWorkingDirectory = function() return './tests/no-such-Moonloader-directory' end
    missing_ini.run()
    equal(missing_ini.registrations, 0)
    assert(#missing_ini.logs > 0)
    equal(#missing_ini.waits, 0)

    local invalid_ini = entrypoint_fixture()
    invalid_ini.on_load = function(bundled_require)
        if bundled_require then
            bundled_require('arfie_hit_distribution.config').load = function()
                return nil, 'Invalid total probability'
            end
        end
    end
    invalid_ini.env.require = function(name)
        if name == 'arfie_hit_distribution.config' then
            return { load = function() return nil, 'Invalid total probability' end }
        end
        return require(name)
    end
    invalid_ini.run()
    equal(invalid_ini.registrations, 0)
    assert(table.concat(invalid_ini.logs, '\n'):find('Invalid total probability', 1, true))
end)

test('entrypoint respects an occupied client command', function()
    local fixture = entrypoint_fixture()
    fixture.env.sampIsChatCommandDefined = function() return true end
    fixture.run()
    equal(fixture.registrations, 0)
    assert(#fixture.logs > 0)
    assert(#fixture.messages > 0)
    equal(#fixture.waits, 0)
end)

io.write(string.format('\n%d passed; %d failed\n', passed, failed))
if failed > 0 then os.exit(1) end
