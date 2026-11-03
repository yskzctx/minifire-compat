import hashlib, importlib.util, json, os, pathlib, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('settings_probe',ROOT/'tools/settings_probe.py');probe=importlib.util.module_from_spec(spec);spec.loader.exec_module(probe)
class SettingsProbeTests(unittest.TestCase):
    def test_invalid_packages_are_rejected(self):
        for package in ['com.game;id','../../other','com..game']:
            with self.assertRaises(ValueError):probe.build_script(package,0)
    def test_parser_never_exports_unknown_or_credential_fields(self):
        report=probe.parse_report('prefs_file=present\nfile_bytes=72\nOpenToken=SECRET\nmobile=PRIVATE\nsettings_digest=bad\n')
        self.assertEqual(report,{'prefs_file':'present','file_bytes':72})
    def test_single_line_xml_does_not_hash_neighboring_credentials(self):
        with tempfile.TemporaryDirectory() as temp:
            directory=pathlib.Path(temp);file=directory/'prefs.xml'
            element='<string name="BattleSetWithUID_test">{&quot;5001&quot;:50}</string>'
            content='<map><string name="OpenToken">DO_NOT_EXPORT</string>'+element+'<string name="mobile">DO_NOT_EXPORT_NUMBER</string></map>'
            file.write_text(content,encoding='utf8');before=file.read_bytes()
            script=probe.build_script('com.test.game',0).replace('/data/user/0/com.test.game/shared_prefs/com.test.game.v2.playerprefs.xml',file.as_posix()).replace('$(id -u)','0')
            result=subprocess.run(['C:/Program Files/Git/bin/bash.exe','-c',script],capture_output=True,text=True,encoding='utf8',check=True)
            parsed=probe.parse_report(result.stdout)
            self.assertEqual(parsed['settings_digest'],hashlib.sha256((element+'\n').encode()).hexdigest())
            self.assertNotIn('DO_NOT_EXPORT',result.stdout);self.assertNotIn('5001',result.stdout)
            self.assertEqual(file.read_bytes(),before)
if __name__=='__main__':unittest.main(verbosity=2)
