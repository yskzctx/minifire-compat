-- The tests catch changing the wrong message/field, stack leakage, credential
-- changes, and a partial switch when the game channel is unexpected.
local pb = assert(package.loadlib(PB_DLL, 'luaopen_pb'))()
local apply = assert(package.loadlib(FILTER_DLL, 'luaopen_compat_test'))()
local file = assert(io.open(DESCRIPTOR, 'rb'))
assert(pb.load(file:read('*a')))
file:close()
pb.option('enum_as_value')
local function request()
    return {PhoneOs=1, ChannelID=23, OpenID='LOCAL-FIXTURE', OpenToken='NOT-A-REAL-TOKEN', Version='1.0.77'}
end
local cases = 0
local function check(name, fn)
    fn(); cases = cases + 1
end
check('terminal platform without touching credentials or game channel', function()
    local data = request(); apply('md.ApiLoginRequest', data, 3)
    local decoded = assert(pb.decode('md.ApiLoginRequest', pb.encode('md.ApiLoginRequest', data)))
    assert(decoded.PhoneOs==2 and decoded.ChannelID==23)
    assert(decoded.OpenID=='LOCAL-FIXTURE' and decoded.OpenToken=='NOT-A-REAL-TOKEN')
    assert(decoded.Version=='1.0.77')
end)
check('game channel switch is independently encoded', function()
    local data = request(); apply('md.ApiLoginRequest', data, 4)
    local decoded = assert(pb.decode('md.ApiLoginRequest', pb.encode('md.ApiLoginRequest', data)))
    assert(decoded.PhoneOs==2 and decoded.ChannelID==888)
end)
check('lobby uses its own platform field', function()
    local data = {Phone_Os=1, ChannelID=23}; apply('md.Login', data, 4)
    local decoded = assert(pb.decode('md.Login', pb.encode('md.Login', data)))
    assert(decoded.Phone_Os==2 and decoded.ChannelID==888 and data.PhoneOs==nil)
end)
check('fresh lobby request can omit its channel field', function()
    local data={Phone_Os=1}; apply('md.Login',data,4)
    local decoded=assert(pb.decode('md.Login',pb.encode('md.Login',data)))
    assert(decoded.Phone_Os==2 and decoded.ChannelID==888)
end)
check('malformed lobby channel does not authorize a partial switch', function()
    local data={Phone_Os=1,ChannelID='unexpected'}; apply('md.Login',data,4)
    assert(data.Phone_Os==1 and data.ChannelID=='unexpected')
end)
check('disabled and Java modes preserve the complete request', function()
    for mode=0,2 do
        local data=request(); local before=pb.encode('md.ApiLoginRequest',data)
        apply('md.ApiLoginRequest',data,mode)
        assert(pb.encode('md.ApiLoginRequest',data)==before)
    end
end)
check('other protocol messages preserve all fields', function()
    for _,name in ipairs({'md.ApiVersionRequest','md.BindPhoneNO','other.ApiLoginRequest','ApiLoginRequest'}) do
        local data=request(); apply(name,data,4)
        assert(data.PhoneOs==1 and data.ChannelID==23)
    end
end)
check('unexpected channel prevents a partial switch', function()
    local data=request(); data.ChannelID=999; apply('md.ApiLoginRequest',data,4)
    assert(data.PhoneOs==1 and data.ChannelID==999)
end)
check('unknown platform preserves original input', function()
    for _,value in ipairs({0,3,4,5,1.5,'PHONE_OS_ANDROID'}) do
        local data=request(); data.PhoneOs=value; apply('md.ApiLoginRequest',data,3)
        assert(data.PhoneOs==value and data.ChannelID==23)
    end
end)
check('raw operations do not invoke table metamethods', function()
    local data=setmetatable(request(), {__index=function() error('read trap') end,__newindex=function() error('write trap') end})
    apply('md.ApiLoginRequest',data,4)
    assert(rawget(data,'PhoneOs')==2 and rawget(data,'ChannelID')==888)
end)
check('missing actual platform does not modify an alias', function()
    local data={Phone_Os=1,ChannelID=23}; apply('md.ApiLoginRequest',data,3)
    assert(data.PhoneOs==nil and data.Phone_Os==1)
end)
check('malformed arguments preserve caller stack and return normally', function()
    apply(nil,{},3); apply(7,{},3); apply('md.ApiLoginRequest',nil,3)
    local data=request(); apply('md.ApiLoginRequest',data,999)
    assert(data.PhoneOs==1 and data.ChannelID==23)
end)
check('repeated application remains stable', function()
    local data=request()
    for i=1,1000 do apply('md.ApiLoginRequest',data,4) end
    assert(data.PhoneOs==2 and data.ChannelID==888)
end)
check('version profile changes both terminal version fields before encoding', function()
    local data=request(); data.VersionName='1.0.77'; apply('md.ApiLoginRequest',data,5)
    local decoded=assert(pb.decode('md.ApiLoginRequest',pb.encode('md.ApiLoginRequest',data)))
    assert(decoded.PhoneOs==2 and decoded.ChannelID==888)
    assert(decoded.Version=='1.0.78' and decoded.VersionName=='1.0.78')
    assert(decoded.OpenID=='LOCAL-FIXTURE' and decoded.OpenToken=='NOT-A-REAL-TOKEN')
end)
check('version profile covers the lobby and its initially absent channel', function()
    local data={Phone_Os=1,Version='1.0.77',Token='LOCAL-FIXTURE-TOKEN'}; apply('md.Login',data,5)
    local decoded=assert(pb.decode('md.Login',pb.encode('md.Login',data)))
    assert(decoded.Phone_Os==2 and decoded.ChannelID==888 and decoded.Version=='1.0.78')
    assert(decoded.Token=='LOCAL-FIXTURE-TOKEN')
end)
check('cached compatible versions normalize before automatic relogin', function()
    for _,versions in ipairs({{'1.0.78','1.0.77'},{'1.0.77','1.0.78'}}) do
        local data=request(); data.ChannelID=888; data.Version=versions[1]; data.VersionName=versions[2]
        apply('md.ApiLoginRequest',data,5)
        local decoded=assert(pb.decode('md.ApiLoginRequest',pb.encode('md.ApiLoginRequest',data)))
        assert(decoded.PhoneOs==2 and decoded.ChannelID==888 and decoded.Version=='1.0.78' and decoded.VersionName=='1.0.78')
        assert(decoded.OpenID=='LOCAL-FIXTURE' and decoded.OpenToken=='NOT-A-REAL-TOKEN')
    end
end)
check('unrecognised versions cause no partial platform change', function()
    for _,versions in ipairs({{'1.0.76','1.0.76'},{42,'1.0.77'},{'1.0.77',false}}) do
        local data=request(); data.Version=versions[1]; data.VersionName=versions[2]
        apply('md.ApiLoginRequest',data,5)
        assert(data.PhoneOs==1 and data.ChannelID==23 and data.Version==versions[1] and data.VersionName==versions[2])
    end
end)
check('version profile rejects unexpected platform or channel without version changes', function()
    for _,changes in ipairs({{3,23},{1,999}}) do
        local data=request(); data.PhoneOs=changes[1]; data.ChannelID=changes[2]; data.VersionName='1.0.77'
        apply('md.ApiLoginRequest',data,5)
        assert(data.PhoneOs==changes[1] and data.ChannelID==changes[2])
        assert(data.Version=='1.0.77' and data.VersionName=='1.0.77')
    end
end)
check('resource update and other messages are unchanged by version profile', function()
    for _,name in ipairs({'md.ApiVersionRequest','md.BindPhoneNO','other.ApiLoginRequest'}) do
        local data=request(); data.VersionName='1.0.77'; apply(name,data,5)
        assert(data.PhoneOs==1 and data.ChannelID==23 and data.Version=='1.0.77' and data.VersionName=='1.0.77')
    end
end)
check('existing native modes do not change version fields', function()
    for mode=3,4 do
        local data=request(); data.VersionName='1.0.77'; apply('md.ApiLoginRequest',data,mode)
        assert(data.Version=='1.0.77' and data.VersionName=='1.0.77')
    end
end)
check('version profile remains stable and avoids metamethods', function()
    local data=setmetatable({Phone_Os=1,Version='1.0.77'}, {
        __index=function() error('read trap') end,__newindex=function() error('write trap') end})
    for i=1,1000 do apply('md.Login',data,5) end
    assert(rawget(data,'Phone_Os')==2 and rawget(data,'ChannelID')==888 and rawget(data,'Version')=='1.0.78')
end)
return cases
