from pathlib import Path
import hashlib, struct, sys, zipfile
root=Path(__file__).resolve().parents[1]
binary=root/'build/libminifire_minimal.release.so'; data=binary.read_bytes()
assert data[:5]==b'\x7fELF\x02' and struct.unpack_from('<H',data,18)[0]==183
offset=struct.unpack_from('<Q',data,32)[0]; size,count=struct.unpack_from('<HH',data,54)
for index in range(count):
    at=offset+index*size
    if struct.unpack_from('<I',data,at)[0]==1: assert struct.unpack_from('<Q',data,at+48)[0]>=16384
names=['module.prop','game_enabled','target_package','config.sh','customize.sh','service.sh','collector.sh','control.sh','uninstall.sh','webroot/index.html','README.md','COMPARISON.md']
files=[(name,root/name) for name in names]
files += [('zygisk/arm64-v8a.so',binary),('LICENSES/Apache-2.0.txt',root/'../zygisk-root/LICENSE-APACHE-2.0.txt'),('LICENSES/Zygisk-ISC.txt',root/'../zygisk-root/LICENSE-ZYGISK-ISC.txt')]
out=Path(sys.argv[1]).resolve();out.parent.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
    for name,path in files:
        info=zipfile.ZipInfo(name);info.create_system=3;info.external_attr=((0o100755 if name.endswith('.sh') else 0o100644)<<16);info.compress_type=zipfile.ZIP_DEFLATED
        archive.writestr(info,path.read_bytes())
with zipfile.ZipFile(out) as archive:
    assert archive.testzip() is None
    assert set(archive.namelist())=={name for name,_ in files}
    assert sum(name.endswith('.so') for name in archive.namelist())==1
    assert not any(name.startswith(('state/','bin/','lib/')) or name.endswith(('.pem','.key')) for name in archive.namelist())
digest=hashlib.sha256(out.read_bytes()).hexdigest()
out.with_suffix('.zip.sha256').write_text(digest+'  '+out.name+'\n',encoding='ascii')
print('module_zip=',out);print('sha256=',digest)
