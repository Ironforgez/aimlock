return function()
    local state={clicks={},edits={},seen={},texts={},headers={},depth=0,flags={ConfigFlags=0},style={Colors={}}}
    local function pointer(value) return {[0]=value} end
    local chars=setmetatable({},{__index=function() return function(value) return {value=value or ''} end end})
    local ui={new={bool=pointer,int=pointer,float=pointer,char=chars},
        Cond={FirstUseEver=1},WindowFlags={HorizontalScrollbar=1},SelectableFlags={SpanAllColumns=2},
        ConfigFlags={NavEnableKeyboard=1},Key={Escape=27},Col=setmetatable({},{__index=function(_,key) return key end})}
    local function action(label,buffer)
        state.seen[label]=true
        local value=state.edits[label]
        if value~=nil then
            state.edits[label]=nil
            if buffer.value~=nil then buffer.value=value else buffer[0]=value end
            return true
        end
        local clicked=state.clicks[label]; state.clicks[label]=nil; return clicked or false
    end
    for _,name in ipairs({'Button','Selectable'}) do ui[name]=function(label) return action(label) end end
    for _,name in ipairs({'Checkbox','InputInt','InputFloat','InputText','SliderFloat'}) do ui[name]=action end
    ui.ImVec2=function(x,y) return {x=x,y=y} end
    ui.ImVec4=function(r,g,b,a) return {r,g,b,a} end
    ui.GetIO=function() return state.flags end
    ui.GetStyle=function() return state.style end
    ui.GetContentRegionAvail=function() return {x=700,y=500} end
    ui.GetCursorPosX=function() return 150 end
    ui.GetWindowContentRegionMax=function() return {x=840,y=560} end
    ui.CalcTextSize=function(text) return {x=#text*7,y=14} end
    ui.SetCursorPosX=function(x) state.author_x=x end
    ui.CollapsingHeader=function(label)
        state.seen[label]=true
        if state.clicks[label] then state.headers[label]=not state.headers[label]; state.clicks[label]=nil end
        return state.headers[label] or false
    end
    ui.GetKeyIndex=function(key) return key end
    ui.IsKeyPressed=function() local value=state.escape; state.escape=false; return value or false end
    ui.Begin=function(title,opened)
        state.title=title; state.depth=state.depth+1
        if state.close_window then opened[0]=false; state.close_window=false end
        return true
    end
    for _,name in ipairs({'BeginChild','BeginCombo','PushItemWidth'}) do
        ui[name]=function() state.depth=state.depth+1; return true end
    end
    for _,name in ipairs({'End','EndChild','EndCombo','PopItemWidth'}) do
        ui[name]=function() state.depth=state.depth-1; assert(state.depth>=0,'Unbalanced UI scopes') end
    end
    for _,name in ipairs({'SetNextWindowSize','SetNextWindowSizeConstraints','SetWindowFontScale',
        'Separator','SameLine','Columns','SetColumnWidth','NextColumn','StyleColorsDark'}) do ui[name]=function() end end
    ui.SetNextWindowPos=function(pos) state.window_pos=pos end
    ui.SetNextWindowSize=function(size) state.window_size=size end
    ui.TextUnformatted=function(value) state.texts[#state.texts+1]=value end
    ui.TextWrapped=function(format,...) state.texts[#state.texts+1]=string.format(format,...) end
    ui.OnInitialize=function(callback) state.initialize=callback; return {Unsubscribe=function() state.initialize=nil end} end
    ui.OnFrame=function(condition,draw)
        state.condition=condition; state.draw=draw
        return {Unsubscribe=function() state.draw=nil end}
    end
    state.ui=ui
    state.ffi={string=function(buffer) return buffer.value end,cdef=function() end,
        load=function() return {MoveFileExA=function() return 0 end,GetLastError=function() return 5 end} end}
    state.render=function()
        if state.initialize then local init=state.initialize; state.initialize=nil; init() end
        if state.condition() then state.draw() end
        assert(state.depth==0,'UI scopes leaked')
    end
    return state
end
