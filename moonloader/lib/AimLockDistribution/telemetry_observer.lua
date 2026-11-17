local Observer = {}
local bullet_packet, damage_rpc = 206, 115
local required = { 'addEventHandler','getGameTimer','raknetBitStreamGetReadOffset',
    'raknetBitStreamSetReadOffset','raknetBitStreamGetNumberOfBitsUsed',
    'raknetBitStreamReadBool','raknetBitStreamReadInt8','raknetBitStreamReadInt16',
    'raknetBitStreamReadInt32','raknetBitStreamReadFloat' }

function Observer.available(api)
    for _,name in ipairs(required) do
        if type(api[name])~='function' then return nil,'API telemetry tidak tersedia: '..name end
    end
    return true
end

local function finite(value)
    assert(type(value)=='number' and value==value and math.abs(value)~=math.huge,'Nonfinite packet field')
    return value
end

local function read_preserving(api, bs, read)
    assert(bs~=nil and bs~=0,'Null bitstream')
    local original=api.raknetBitStreamGetReadOffset(bs)
    local ok,value=pcall(function()
        api.raknetBitStreamSetReadOffset(bs,0)
        return read(api.raknetBitStreamGetNumberOfBitsUsed(bs))
    end)
    local restored,restore_error=pcall(api.raknetBitStreamSetReadOffset,bs,original)
    assert(restored,'Read cursor restore failed: '..tostring(restore_error))
    if not ok then error(value) end
    return value
end

local function read_bullet(api,bs)
    return read_preserving(api,bs,function(bits)
        assert(bits==328,'Unexpected outgoing BulletSync length')
        assert(api.raknetBitStreamReadInt8(bs)%256==bullet_packet,'Unexpected packet header')
        local data={target_type=api.raknetBitStreamReadInt8(bs)%256,
            target_id=api.raknetBitStreamReadInt16(bs)%65536}
        local function read_vector()
            return {x=finite(api.raknetBitStreamReadFloat(bs)),y=finite(api.raknetBitStreamReadFloat(bs)),
                z=finite(api.raknetBitStreamReadFloat(bs))}
        end
        data.origin=read_vector()
        data.hit_position=read_vector()
        data.offset=read_vector()
        data.weapon_id=api.raknetBitStreamReadInt8(bs)%256
        return data
    end)
end

local function read_damage(api,bs)
    return read_preserving(api,bs,function(bits)
        assert(bits>=113 and bits<=120,'Unexpected GiveTakeDamage length')
        local taking=api.raknetBitStreamReadBool(bs)
        if taking then return nil end
        return {player_id=api.raknetBitStreamReadInt16(bs)%65536,
            amount=finite(api.raknetBitStreamReadFloat(bs)),
            weapon_id=api.raknetBitStreamReadInt32(bs)%4294967296,
            body_part=api.raknetBitStreamReadInt32(bs)%4294967296}
    end)
end

function Observer.attach(api, telemetry, get_context)
    local available,err=Observer.available(api)
    if not available then return nil,err end
    local observer={active=false}
    local function observe(source,action)
        if not observer.active or not telemetry:is_active() then return end
        local ok,value,message=pcall(action)
        if not ok or (value==nil and message~=nil) then
            if not ok and tostring(value):find('Read cursor restore failed:',1,true) then observer.active=false end
            local clock_ok,now=pcall(api.getGameTimer)
            if clock_ok then pcall(telemetry.record_error,telemetry,source,
                tostring(ok and message or value),now) end
        end
    end
    local function on_packet(id,bs)
        if id==bullet_packet then
            observe('bullet_sync',function()
                local data=read_bullet(api,bs)
                return telemetry:record_shot(data,get_context(),api.getGameTimer())
            end)
        end
        -- Nil leaves processing and payload untouched.
    end
    local function on_rpc(id,bs)
        if id==damage_rpc then
            observe('give_damage',function()
                local data=read_damage(api,bs)
                if data then return telemetry:record_damage(data,api.getGameTimer()) end
            end)
        end
    end
    local ok,registration_error=pcall(function()
        assert(api.addEventHandler('onSendPacket',on_packet)~=false,'Cannot register packet observer')
        assert(api.addEventHandler('onSendRpc',on_rpc)~=false,'Cannot register RPC observer')
    end)
    if not ok then return nil,tostring(registration_error) end
    observer.active=true
    return observer
end

return Observer
