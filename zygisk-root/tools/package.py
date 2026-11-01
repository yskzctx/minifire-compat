from pathlib import Path
import zipfile, hashlib, sys
root=Path(__file__).resolve().parents[1]
binary=root/'build/libminifire_zygisk.so'
if not binary.is_file(): raise SystemExit('Build native library first')
out=Path(sys.argv[1]).resolve()
out.parent.mkdir(parents=True,exist_ok=True)
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED) as z:
    for name,path in [('module.prop',root/'module.prop'),('README.md',root/'README.md'),
                      ('game_enabled',root/'game_enabled'),('hunter_enabled',root/'hunter_enabled'),
                      ('control.sh',root/'control.sh'),('webroot/index.html',root/'webroot/index.html'),
                      ('LICENSES/Apache-2.0.txt',root/'LICENSE-APACHE-2.0.txt'),
                      ('LICENSES/Zygisk-ISC.txt',root/'LICENSE-ZYGISK-ISC.txt'),
                      ('zygisk/arm64-v8a.so',binary)]:
        z.write(path,name)
with zipfile.ZipFile(out) as z:
    assert z.testzip() is None
    assert set(z.namelist())=={'module.prop','README.md','game_enabled','hunter_enabled','control.sh',
                              'webroot/index.html','LICENSES/Apache-2.0.txt','LICENSES/Zygisk-ISC.txt','zygisk/arm64-v8a.so'}
    assert not any('xposed' in n.lower() or 'lsp' in n.lower() for n in z.namelist())
print('candidate_zip=',out)
print('sha256=',hashlib.sha256(out.read_bytes()).hexdigest())
