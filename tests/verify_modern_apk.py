import sys, zipfile, io
from pathlib import Path
from loguru import logger
logger.remove()
from androguard.core.apk import APK
from androguard.core.dex import DEX
from elftools.elf.elffile import ELFFile

path=Path(sys.argv[1]); apk=APK(str(path))
with zipfile.ZipFile(path) as archive:
    assert 'META-INF/xposed/java_init.list' in archive.namelist(), 'Modern module entry is missing'
    assert archive.read('META-INF/xposed/java_init.list').decode().strip()=='com.codex.minifire.compatlab.HookEntry'
    assert archive.read('META-INF/xposed/native_init.list').decode().strip()=='libminifire_login.so'
    assert archive.read('META-INF/xposed/scope.list').decode().strip()=='com.miniworldroyale.sparkgame'
    props=archive.read('META-INF/xposed/module.prop').decode()
    assert 'minApiVersion=101' in props and 'targetApiVersion=101' in props and 'staticScope=true' in props
    assert 'assets/xposed_init' not in archive.namelist() and 'assets/native_init' not in archive.namelist()
    classes={c.get_name():c for name in archive.namelist() if name.endswith('.dex') for c in DEX(archive.read(name)).get_classes()}
    assert not any(name.startswith('Lde/robv/') or name.startswith('Lio/github/libxposed/api/') for name in classes)
    assert classes['Lcom/codex/minifire/compatlab/HookEntry;'].get_superclassname()=='Lio/github/libxposed/api/XposedModule;'
    native_names=[n for n in archive.namelist() if n.endswith('.so')]
    assert native_names==['lib/arm64-v8a/libminifire_login.so']
    native=ELFFile(io.BytesIO(archive.read(native_names[0])))
    assert native['e_machine']=='EM_AARCH64'
    assert all(s['p_align']>=16384 for s in native.iter_segments() if s['p_type']=='PT_LOAD')
    exports={s.name for s in native.get_section_by_name('.dynsym').iter_symbols() if s['st_shndx']!='SHN_UNDEF'}
    assert {'native_init','Java_com_codex_minifire_compatlab_NativeBridge_configure','Java_com_codex_minifire_compatlab_NativeBridge_snapshot'}<=exports
manifest=apk.get_android_manifest_xml(); ns='{http://schemas.android.com/apk/res/android}'
assert not any((n.get(ns+'name') or '').startswith('xposed') for n in manifest.findall('application/meta-data'))
assert apk.get_permissions()==[]
assert manifest.find('application').get(ns+'name')=='com.codex.minifire.compatlab.CompatApplication'
providers=manifest.findall('application/provider')
assert any(p.get(ns+'name')=='io.github.libxposed.service.XposedProvider' for p in providers)
print('PASS: modern entry, fixed game scope, remote service, no legacy metadata or API packaging, ARM64 native entry and 16KB alignment')
