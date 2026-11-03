-- Compare the real legacy/current C++ filters through Lua, including the
-- resulting protobuf bytes. All credentials and preferences are synthetic.
local old = assert(package.loadlib(LEGACY_DLL, 'luaopen_compat_test'))()
local current = assert(package.loadlib(CURRENT_DLL, 'luaopen_compat_test'))()
local pb = assert(package.loadlib(PB_DLL, 'luaopen_pb'))()
local descriptor = assert(io.open(DESCRIPTOR, 'rb'))
assert(pb.load(descriptor:read('*a'))); descriptor:close()
pb.option('enum_as_value')
local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}; for k,v in pairs(value) do result[k] = copy(v) end
    return result
end
local function same(a,b)
    assert(type(a)==type(b), 'value type changed')
    if type(a)~='table' then assert(a==b, 'value changed'); return end
    for k,v in pairs(a) do same(v,b[k]) end
    for k,v in pairs(b) do same(v,a[k]) end
end
local count=0
for _,message in ipairs({'md.ApiLoginRequest','md.Login','md.ApiVersionRequest','other.ApiLoginRequest'}) do
 for mode=0,5 do
  for _,os in ipairs({1,2,3}) do
   for _,channel in ipairs({23,888,999}) do
    for _,versions in ipairs({{'1.0.77','1.0.77'},{'1.0.78','1.0.77'},{'1.0.77','1.0.78'},{'1.0.76','1.0.77'}}) do
     local data={PhoneOs=os,Phone_Os=os,ChannelID=channel,Version=versions[1],VersionName=versions[2],
       OpenID='SYNTHETIC-ID',OpenToken='SYNTHETIC-TOKEN',Token='SYNTHETIC-LOBBY-TOKEN',
       BattleSet='SYNTHETIC-SETTINGS',BattleSetWithUID={['synthetic-user']='SYNTHETIC-PREFERENCES'}}
     local a,b=copy(data),copy(data)
     old(message,a,mode); current(message,b,mode)
     -- The intentional profile change is the sole expected difference on
     -- inputs supported by both versions. Normalize the legacy OUTPUT only.
     if a.Version=='1.0.78' and mode==5 and a.PhoneOs~=3 and channel~=999 and
        (message=='md.ApiLoginRequest' or message=='md.Login') and versions[1]~='1.0.76' then
       a.Version='1.0.79'
       if message=='md.ApiLoginRequest' then a.VersionName='1.0.79' end
     end
     same(a,b)
     -- Compare decoded wire payloads: protobuf field order is not semantic.
     if message=='md.ApiLoginRequest' or message=='md.Login' then
       same(assert(pb.decode(message,pb.encode(message,a))),assert(pb.decode(message,pb.encode(message,b))))
     end
     same(b.BattleSet,data.BattleSet); same(b.BattleSetWithUID,data.BattleSetWithUID)
     assert(b.OpenID==data.OpenID and b.OpenToken==data.OpenToken and b.Token==data.Token)
     count=count+1
    end
   end
  end
 end
end
-- New cached 1.0.79 declarations deliberately extend the accepted domain;
-- compare against the corresponding supported legacy cache, not its rejection.
for _,message in ipairs({'md.ApiLoginRequest','md.Login'}) do
 for _,versions in ipairs({{'1.0.79','1.0.77'},{'1.0.77','1.0.79'},{'1.0.79','1.0.79'}}) do
  local a={PhoneOs=1,Phone_Os=1,ChannelID=23,Version='1.0.78',VersionName='1.0.77',Token='SYNTHETIC'}
  local b=copy(a); b.Version=versions[1]; b.VersionName=versions[2]
  old(message,a,5); current(message,b,5)
  a.Version='1.0.79'
  if message=='md.ApiLoginRequest' then a.VersionName='1.0.79'
  else a.VersionName=versions[2] end -- lobby never changes VersionName
  same(a,b)
  same(assert(pb.decode(message,pb.encode(message,a))),assert(pb.decode(message,pb.encode(message,b))))
  count=count+1
 end
end
return count
