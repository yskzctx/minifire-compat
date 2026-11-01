import ctypes
import argparse
import json
import os
import subprocess
from pathlib import Path
import UnityPy
from elftools.elf.elffile import ELFFile

root = Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser()
parser.add_argument('--game-bundle',type=Path,default=root/'work/apk-files/assets/AssetBundles/android/pb_32_64.ab')
args=parser.parse_args()
host = root / 'work/native-host'
module = root / 'minifire-compat'
gcc = Path('C:/Users/yskzc/tools/mingw64/bin/g++.exe')
subprocess.run([str(gcc), '-std=c++17', '-shared', '-O2', '-Wall', '-Wextra', '-Werror',
    '-static-libgcc', '-static-libstdc++', '-I', str(host/'lua-5.1.5/src'),
    str(module/'tests/native_core_adapter.cpp'), str(module/'zygisk-root/src/login_filter.cpp'),
    str(module/'zygisk-root/src/binary_guard.cpp'),
    '-L'+str(host), '-llua51', '-o', str(host/'compat_test.dll')], check=True)
descriptor = host/'md-descriptor.bytes'
for obj in UnityPy.load(str(args.game_bundle)).objects:
    if obj.type.name == 'TextAsset':
        asset = obj.read()
        if asset.m_Name == 'md':
            data = asset.m_Script
            descriptor.write_bytes(data.encode('utf8','surrogateescape') if isinstance(data,str) else data)
            break
else:
    raise RuntimeError('Game descriptor missing')
with os.add_dll_directory(str(host)), os.add_dll_directory(str(gcc.parent)):
    filter_lib = ctypes.CDLL(str(host/'compat_test.dll'))
    filter_lib.verify_game_note.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
    with (root/'work/apk-files/lib/arm64-v8a/libtolua.so').open('rb') as stream:
        note = ELFFile(stream).get_section_by_name('.note.gnu.build-id').data()
    assert filter_lib.verify_game_note(note,len(note)) == 1, 'Official binary must be recognized'
    for corrupted in [note[:-1], note[:8], note[:-1]+bytes([note[-1]^1]), b'\xff'*12+note[12:]]:
        assert filter_lib.verify_game_note(corrupted,len(corrupted)) == 0, 'Unknown/truncated binary must be rejected'
    lib = ctypes.CDLL(str(host/'lua51.dll'))
    lib.luaL_newstate.restype = ctypes.c_void_p
    lib.luaL_openlibs.argtypes = [ctypes.c_void_p]
    lib.luaL_loadstring.argtypes = [ctypes.c_void_p,ctypes.c_char_p]
    lib.lua_pcall.argtypes = [ctypes.c_void_p,ctypes.c_int,ctypes.c_int,ctypes.c_int]
    lib.lua_tolstring.argtypes = [ctypes.c_void_p,ctypes.c_int,ctypes.c_void_p]
    lib.lua_tolstring.restype = ctypes.c_char_p
    lib.lua_tointeger.argtypes = [ctypes.c_void_p,ctypes.c_int]
    lib.lua_tointeger.restype = ctypes.c_ssize_t
    lib.lua_close.argtypes = [ctypes.c_void_p]
    state = lib.luaL_newstate()
    assert state
    try:
        lib.luaL_openlibs(state)
        chunk = '\n'.join(f'{key}={json.dumps(path.as_posix())}' for key,path in
            [('PB_DLL',host/'pb.dll'),('FILTER_DLL',host/'compat_test.dll'),('DESCRIPTOR',descriptor)])
        chunk += '\n' + (module/'tests/native_core_cases.lua').read_text('utf8')
        if lib.luaL_loadstring(state,chunk.encode()) or lib.lua_pcall(state,0,1,0):
            raise AssertionError(lib.lua_tolstring(state,-1,None).decode('utf8','replace'))
        count = lib.lua_tointeger(state,-1)
    finally:
        lib.lua_close(state)
result = {'native_filter_cases_passed':count, 'real_lua_runtime':'Lua 5.1.5 on Windows',
    'binary_guard_cases_passed':5,
    'real_protobuf_encoder':'upstream lua-protobuf on Windows', 'descriptor_source':str(args.game_bundle),
    'android_hook_execution_test':False, 'account_login_test':False}
(root/'work/native-host-validation.json').write_text(json.dumps(result,indent=2)+'\n','utf8')
print(json.dumps(result,indent=2))
