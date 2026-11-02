"""Exercise the production shared filter with real Lua 5.1 and protobuf on host."""
import ctypes, json, os, subprocess
from pathlib import Path
root=Path(__file__).resolve().parents[2];fixture=root.parent/'work/native-host'
gcc=Path('C:/Users/yskzc/tools/mingw64/bin/g++.exe');out=root/'minimal-root/build/compat_test.dll'
out.parent.mkdir(parents=True,exist_ok=True)
subprocess.run([str(gcc),'-std=c++17','-shared','-O2','-Wall','-Wextra','-Werror','-static-libgcc','-static-libstdc++','-I'+str(fixture/'lua-5.1.5/src'),str(root/'tests/native_core_adapter.cpp'),str(root/'app/src/main/cpp/login_filter.cpp'),str(root/'app/src/main/cpp/binary_guard.cpp'),'-L'+str(fixture),'-llua51','-o',str(out)],check=True)
with os.add_dll_directory(str(fixture)),os.add_dll_directory(str(gcc.parent)):
    native=ctypes.CDLL(str(out));native.verify_game_note.argtypes=[ctypes.c_char_p,ctypes.c_size_t]
    note=bytes.fromhex(json.loads((root/'minimal-root/src/generated/profile.json').read_text())['note'])
    assert native.verify_game_note(note,len(note))==1
    for bad in [note[:-1],note[:8],note[:-1]+bytes([note[-1]^1]),b'\xff'*12+note[12:]]:
        assert native.verify_game_note(bad,len(bad))==0
    lua=ctypes.CDLL(str(fixture/'lua51.dll'));lua.luaL_newstate.restype=ctypes.c_void_p
    lua.luaL_openlibs.argtypes=[ctypes.c_void_p];lua.luaL_loadstring.argtypes=[ctypes.c_void_p,ctypes.c_char_p]
    lua.lua_pcall.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int]
    lua.lua_tolstring.argtypes=[ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p];lua.lua_tolstring.restype=ctypes.c_char_p
    lua.lua_tointeger.argtypes=[ctypes.c_void_p,ctypes.c_int];lua.lua_tointeger.restype=ctypes.c_ssize_t;lua.lua_close.argtypes=[ctypes.c_void_p]
    state=lua.luaL_newstate();assert state
    try:
        lua.luaL_openlibs(state)
        chunk='\n'.join(key+'='+json.dumps(path.as_posix()) for key,path in [('PB_DLL',fixture/'pb.dll'),('FILTER_DLL',out),('DESCRIPTOR',fixture/'md-descriptor.bytes')])
        chunk+='\n'+(root/'tests/native_core_cases.lua').read_text('utf8')
        if lua.luaL_loadstring(state,chunk.encode()) or lua.lua_pcall(state,0,1,0): raise AssertionError(lua.lua_tolstring(state,-1,None))
        print('real Lua/protobuf filter cases passed:',lua.lua_tointeger(state,-1));print('binary build-ID guard cases passed: 5')
    finally: lua.lua_close(state)
