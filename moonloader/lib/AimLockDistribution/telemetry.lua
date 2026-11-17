local Identity = require 'AimLockDistribution.identity'
local Telemetry = {}
Telemetry.__index = Telemetry
local modulus = 4294967296
local queue_limit, pending_limit = 256, 128
local body_parts = { [3]='torso', [4]='groin', [5]='left_arm', [6]='right_arm',
    [7]='left_leg', [8]='right_leg', [9]='head' }

local function finite(value)
    return type(value)=='number' and value==value and math.abs(value)~=math.huge
end
local function integer(value, maximum)
    return finite(value) and value>=0 and value<=maximum and value==math.floor(value)
end
local function clock(value)
    assert(finite(value) and value==math.floor(value), 'Invalid telemetry timer')
    return value % modulus
end
local function vector(value)
    if type(value)=='table' and finite(value.x) and finite(value.y) and finite(value.z) then
        return {x=value.x,y=value.y,z=value.z}
    end
end
local function delta(first, second)
    local distance=(first-second)%modulus
    return math.min(distance,modulus-distance)
end

function Telemetry.new(settings, options)
    local self=setmetatable({ active=true, closed=false, queue={}, shots={}, reports={},
        shot_id=0, report_id=0, event_id=0, dropped=0, total_dropped=0,
        now_ms=clock(options.start_ms), last_flush=clock(options.start_ms),
        window=settings.telemetry_match_window_ms, flush_interval=settings.telemetry_flush_interval_ms,
        session_id=options.session_id, writer=options.write_batch, on_error=options.on_error },Telemetry)
    local distribution={}
    for key,value in pairs(settings.distribution) do distribution[key]=value end
    self:emit('session_start',{version=options.version or Identity.version,random_aim=settings.random_aim,
        random_interval_ms=settings.random_interval_ms,distribution=distribution,
        match_window_ms=self.window,observation='client_outgoing_only'})
    return self
end

function Telemetry:is_active() return self.active and not self.closed end

function Telemetry:emit(kind, fields)
    if not self:is_active() then return end
    self.event_id=self.event_id+1
    if #self.queue>=queue_limit then
        self.dropped=self.dropped+1; self.total_dropped=self.total_dropped+1
        return
    end
    fields.event=kind
    fields.schema_version=1
    fields.event_id=self.event_id
    fields.session_id=self.session_id
    fields.game_ms=self.now_ms
    fields.unix_time=os.time()
    fields.server_status='unknown'
    self.queue[#self.queue+1]=fields
end

function Telemetry:record_error(source, message, now_ms)
    if not self:is_active() then return end
    self.now_ms=clock(now_ms)
    self:emit('observer_error',{source=source,message=tostring(message):sub(1,500)})
end

function Telemetry:associate(shot, report)
    if shot.target_type~=1 or shot.target_id==65535 or shot.target_id~=report.player_id
        or shot.weapon_id~=report.weapon_id or delta(shot.time,report.time)>self.window
        or report.candidate_set[shot.id] then return end
    if #report.candidates>=pending_limit then
        if not report.candidates_truncated then
            report.candidates_truncated=true
            self:emit('correlation_update',{report_id=report.id,candidate_count=#report.candidates,
                candidates_truncated=true,association='ambiguous',evidence='player_id_weapon_time_window'})
        end
        return
    end
    report.candidate_set[shot.id]=true
    report.candidates[#report.candidates+1]=shot.id
    if #shot.report_ids<pending_limit then shot.report_ids[#shot.report_ids+1]=report.id
    elseif not shot.reports_truncated then
        shot.reports_truncated=true
        self:emit('shot_candidates_truncated',{shot_id=shot.id,candidate_report_count=#shot.report_ids})
    end
    local ids={}
    for index,id in ipairs(report.candidates) do ids[index]=id end
    self:emit('correlation_update',{report_id=report.id,candidate_shot_ids=ids,
        candidate_count=#ids,candidates_truncated=false,association=#ids==1 and 'temporal_candidate' or 'ambiguous',
        evidence='player_id_weapon_time_window',report_game_ms=report.time})
end

function Telemetry:retire_shot(index, reason)
    local shot=table.remove(self.shots,index)
    local ids={}
    for position,id in ipairs(shot.report_ids) do ids[position]=id end
    self:emit('shot_window_closed',{shot_id=shot.id,reason=reason,
        candidate_report_count=#ids,candidate_report_ids=#ids>0 and ids or nil,
        candidates_truncated=shot.reports_truncated or false,
        result=#ids>0 and 'client_damage_report_candidate' or 'no_correlated_damage_report'})
end

function Telemetry:retire_report(index, reason)
    local report=table.remove(self.reports,index)
    self:emit('damage_window_closed',{report_id=report.id,reason=reason,
        candidate_count=#report.candidates,candidates_truncated=report.candidates_truncated or false,
        association=#report.candidates==0 and 'unmatched' or
            (#report.candidates==1 and 'temporal_candidate' or 'ambiguous')})
end

function Telemetry:expire(now_ms)
    self.now_ms=clock(now_ms)
    for index=#self.shots,1,-1 do
        if (self.now_ms-self.shots[index].time)%modulus>self.window then
            self:retire_shot(index,'window_expired')
        end
    end
    for index=#self.reports,1,-1 do
        if (self.now_ms-self.reports[index].time)%modulus>self.window then
            self:retire_report(index,'window_expired')
        end
    end
end

function Telemetry:record_shot(data, context, now_ms)
    if not self:is_active() then return end
    if type(data)~='table' or not integer(data.weapon_id,255)
        or not integer(data.target_type,255) or not integer(data.target_id,65535) then
        return nil,'Invalid bullet report'
    end
    self:expire(now_ms)
    context=type(context)=='table' and context or {}
    self.shot_id=self.shot_id+1
    local shot={id=self.shot_id,time=self.now_ms,weapon_id=data.weapon_id,
        target_type=data.target_type,target_id=data.target_id,report_ids={}}
    local snapshot_valid=integer(context.locked_player_id,65534)
        and context.snapshot_target_id==context.locked_player_id
    local snapshot_ms=finite(context.context_game_ms) and clock(context.context_game_ms) or nil
    self:emit('shot',{shot_id=shot.id,source='outgoing_bullet_sync',
        weapon_id=data.weapon_id,reported_hit_type=data.target_type,reported_hit_id=data.target_id,
        origin=vector(data.origin),reported_hit_position=vector(data.hit_position),
        reported_hit_offset=vector(data.offset),aimlock_enabled=context.aimlock_enabled==true,
        locked_player_id=integer(context.locked_player_id,65534) and context.locked_player_id or nil,
        selected_body_part=snapshot_valid and type(context.selected_body_part)=='string'
            and context.selected_body_part or 'unknown',
        selected_point=snapshot_valid and vector(context.selected_point) or nil,
        aim_applied=snapshot_valid and context.aim_applied==true or false,
        context_game_ms=snapshot_valid and snapshot_ms or nil,
        context_age_ms=snapshot_valid and snapshot_ms and (self.now_ms-snapshot_ms)%modulus or nil})
    if #self.shots>=pending_limit then self:retire_shot(1,'buffer_limit') end
    self.shots[#self.shots+1]=shot
    for _,report in ipairs(self.reports) do self:associate(shot,report) end
    return shot.id
end

function Telemetry:record_damage(data, now_ms)
    if not self:is_active() then return end
    if type(data)~='table' or not integer(data.player_id,65535)
        or not integer(data.weapon_id,4294967295) or not integer(data.body_part,4294967295)
        or not finite(data.amount) or data.amount<0 then return nil,'Invalid damage report' end
    self:expire(now_ms)
    self.report_id=self.report_id+1
    local report={id=self.report_id,time=self.now_ms,player_id=data.player_id,
        weapon_id=data.weapon_id,candidates={},candidate_set={}}
    self:emit('damage_report',{report_id=report.id,source='outgoing_give_damage_rpc',
        damaged_player_id=data.player_id,weapon_id=data.weapon_id,reported_amount=data.amount,
        reported_body_part_id=data.body_part,reported_body_part=body_parts[data.body_part] or 'unknown'})
    if #self.reports>=pending_limit then self:retire_report(1,'buffer_limit') end
    self.reports[#self.reports+1]=report
    for _,shot in ipairs(self.shots) do self:associate(shot,report) end
    return report.id
end

function Telemetry:flush()
    if not self.active then return nil,'Telemetry inactive' end
    if #self.queue==0 and self.dropped==0 then return true end
    local batch={}
    for index,event in ipairs(self.queue) do batch[index]=event end
    if self.dropped>0 then
        batch[#batch+1]={event='telemetry_overflow',schema_version=1,session_id=self.session_id,
            game_ms=self.now_ms,unix_time=os.time(),dropped_events=self.dropped,server_status='unknown'}
    end
    local ok,written,err=pcall(self.writer,batch)
    if not ok or written~=true then
        self.active=false
        if self.on_error then pcall(self.on_error,tostring(ok and err or written)) end
        return nil,tostring(ok and err or written)
    end
    self.queue,self.dropped={},0
    self.last_flush=self.now_ms
    return true
end

function Telemetry:poll(now_ms)
    if not self:is_active() then return end
    self:expire(now_ms)
    if (self.now_ms-self.last_flush)%modulus>=self.flush_interval or #self.queue>=128 then self:flush() end
end

function Telemetry:close()
    if self.closed then return end
    if self.active then
        while #self.shots>0 do self:retire_shot(1,'session_ended') end
        while #self.reports>0 do self:retire_report(1,'session_ended') end
        self:emit('session_end',{shots_observed=self.shot_id,damage_reports_observed=self.report_id,
            dropped_events=self.total_dropped})
        self:flush()
    end
    self.closed=true
end

return Telemetry
