"""Offline behavioral comparison with the version-controlled legacy filter.

Uses only local Lua/protobuf fixtures and synthetic data; no phone/network.
The reference source comes from v0.4.1, whose native library is byte-identical
to the preserved 0.4.0 APK (artifact equality is checked when both are present).
"""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT.parent / 'work/native-host'
BUILD = ROOT / 'minimal-root/build/legacy-parity'
GCC = Path('C:/Users/yskzc/tools/mingw64/bin/g++.exe')


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    old = subprocess.run(
        ['git', 'show', 'v0.4.1:app/src/main/cpp/login_filter.cpp'],
        cwd=ROOT, check=True, capture_output=True).stdout
    (BUILD / 'legacy_filter.cpp').write_bytes(old)
    libraries = {}
    for label, source in [('legacy', BUILD / 'legacy_filter.cpp'),
                          ('current', ROOT / 'app/src/main/cpp/login_filter.cpp')]:
        output = BUILD / (label + '.dll')
        subprocess.run([
            str(GCC), '-std=c++17', '-shared', '-O2', '-Wall', '-Wextra', '-Werror',
            '-static-libgcc', '-static-libstdc++',
            '-I' + str(FIXTURE / 'lua-5.1.5/src'),
            '-I' + str(ROOT / 'app/src/main/cpp'),
            str(ROOT / 'tests/native_core_adapter.cpp'), str(source),
            str(ROOT / 'app/src/main/cpp/binary_guard.cpp'),
            '-L' + str(FIXTURE), '-llua51', '-o', str(output)], check=True)
        libraries[label] = output
    artifact_hashes = {}
    for version in ['0.4.0', '0.4.1']:
        apk = ROOT.parent / ('outputs/Minifire-Compat-' + version + '.apk')
        if apk.exists():
            with zipfile.ZipFile(apk) as archive:
                artifact_hashes[version] = hashlib.sha256(archive.read(
                    'lib/arm64-v8a/libminifire_login.so')).hexdigest()
    if len(artifact_hashes) == 2:
        assert len(set(artifact_hashes.values())) == 1, 'Legacy native APK libraries differ'
    with os.add_dll_directory(str(FIXTURE)), os.add_dll_directory(str(GCC.parent)):
        lua = ctypes.CDLL(str(FIXTURE / 'lua51.dll'))
        lua.luaL_newstate.restype = ctypes.c_void_p
        lua.luaL_openlibs.argtypes = [ctypes.c_void_p]
        lua.luaL_loadstring.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        lua.lua_pcall.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_int, ctypes.c_int]
        lua.lua_tolstring.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_void_p]
        lua.lua_tolstring.restype = ctypes.c_char_p
        lua.lua_tointeger.argtypes = [ctypes.c_void_p, ctypes.c_int]
        lua.lua_tointeger.restype = ctypes.c_ssize_t
        lua.lua_close.argtypes = [ctypes.c_void_p]
        state = lua.luaL_newstate()
        assert state, 'Lua allocation failed'
        try:
            lua.luaL_openlibs(state)
            paths = {'LEGACY_DLL': libraries['legacy'], 'CURRENT_DLL': libraries['current'],
                     'PB_DLL': FIXTURE / 'pb.dll', 'DESCRIPTOR': FIXTURE / 'md-descriptor.bytes'}
            chunk = '\n'.join(k + '=' + json.dumps(v.as_posix()) for k, v in paths.items())
            chunk += '\n' + (ROOT / 'tests/legacy_parity_cases.lua').read_text('utf-8')
            if lua.luaL_loadstring(state, chunk.encode()) or lua.lua_pcall(state, 0, 1, 0):
                raise AssertionError(lua.lua_tolstring(state, -1, None))
            report = {'reference': 'v0.4.1', 'legacy_native_artifacts_sha256': artifact_hashes,
                      'behavior_cases_passed': lua.lua_tointeger(state, -1),
                      'intentional_differences': ['login version 1.0.78 -> 1.0.79',
                                                  'accept known 1.0.79 cached versions'],
                      'device_settings_persistence_verified': False}
            (BUILD / 'result.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
            print(json.dumps(report, indent=2))
        finally:
            lua.lua_close(state)


if __name__ == '__main__':
    main()
