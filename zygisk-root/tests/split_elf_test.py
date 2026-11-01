from pathlib import Path
import subprocess

root = Path(__file__).resolve().parents[1]
nm = Path('C:/Users/yskzc/Android/Sdk/ndk/26.3.11579264/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-nm.exe')
front = root / 'build/libminifire_zygisk.so'
core = root / 'build/libminifire_core.so'

def exports(path):
    return subprocess.check_output([str(nm), '-D', str(path)], text=True)

assert front.is_file()
assert core.is_file(), 'native core must be a separate library loaded after specialization'
front_symbols = exports(front)
core_symbols = exports(core)
assert 'zygisk_module_entry' in front_symbols
assert 'minifire_core_start' in core_symbols
assert 'DobbyHook' not in front_symbols
assert '__cxa_throw' not in front_symbols
assert front.stat().st_size < 100_000, 'Zygote entry must stay small'
print('small Zygisk entry and app-process core verified')
