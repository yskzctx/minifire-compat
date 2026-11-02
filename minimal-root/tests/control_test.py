import json, mmap, os, pathlib, shutil, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
BASH=pathlib.Path('C:/Program Files/Git/bin/bash.exe')
class ControlTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='minifire-minimal-');self.addCleanup(self.temp.cleanup)
        self.dir=pathlib.Path(self.temp.name);(self.dir/'state').mkdir();(self.dir/'bin').mkdir()
        for name in ['config.sh','game_enabled','target_package','module.prop']:
            shutil.copyfile(ROOT/name,self.dir/name)
        (self.dir/'packages.list').write_text('com.miniworldroyale.sparkgame 10240 0 /data/user/0/game\ncom.example.channel 10456 0 /data/user/0/channel\n')
        source=(ROOT/'control.sh').read_text('utf8').replace('/data/system/packages.list',"'"+(self.dir/'packages.list').as_posix()+"'")
        (self.dir/'control.sh').write_text(source,encoding='utf8',newline='\n')
        (self.dir/'bin/logcat').write_text('#!/bin/sh\nprintf \'fixture_module_system_log\\n\'\n',newline='\n')
        (self.dir/'bin/pidof').write_text('#!/bin/sh\nprintf \'16585\\n\'\n',newline='\n')
    def call(self,*args):
        env=os.environ.copy();env['PATH']=str(self.dir/'bin')+os.pathsep+env['PATH']
        # MSYS must see the mock directory before its own system commands.
        return subprocess.run([str(BASH),(self.dir/'control.sh').as_posix(),*args],env=env,text=True,encoding="utf8",capture_output=True)
    def test_toggle_preserves_readonly_mapping_inode_and_size(self):
        flag=self.dir/'game_enabled';identity=flag.stat().st_ino
        with flag.open('r+b') as stream, mmap.mmap(stream.fileno(),0,access=mmap.ACCESS_READ) as page:
            self.assertEqual(self.call('game','1').stdout.strip(),'1');self.assertEqual(page[:1],b'1')
            self.assertEqual(self.call('game','0').stdout.strip(),'0');self.assertEqual(page[:1],b'0')
        self.assertEqual(flag.stat().st_ino,identity);self.assertEqual(flag.stat().st_size,2)
    def test_select_target_disables_and_rejects_uninstalled_or_injection(self):
        self.call('game','1');result=self.call('target','com.example.channel')
        self.assertEqual(result.returncode,0,result.stderr);self.assertEqual(result.stdout.strip(),'com.example.channel')
        self.assertTrue((self.dir/'game_enabled').read_text().startswith('0'))
        for bad in ['com.invalid.game','com.game;id','../bad']:
            self.assertNotEqual(self.call('target',bad).returncode,0)
        self.assertEqual((self.dir/'target_package').read_text().strip(),'com.example.channel')
    def test_apps_and_persistent_logs(self):
        self.assertEqual(len(json.loads(self.call('apps').stdout)),2)
        (self.dir/'state/hooks.jsonl').write_text('{"pid":16585,"stage":"terminal_login_rewritten"}\n')
        self.call('game','1')
        self.assertIn('stage=login_rewritten',self.call('status').stdout)
        first=self.call('logs').stdout;second=self.call('logs').stdout
        self.assertIn('terminal_login_rewritten',first);self.assertIn('terminal_login_rewritten',second)
        self.assertIn('fixture_module_system_log',first)
    def test_root_collector_fallback_and_failure_stages(self):
        self.call('game','1')
        (self.dir/'state/hooks.jsonl').write_text('{"pid":16585,"stage":"target_selected"}\n')
        file=self.dir/'state/system-module.log'
        file.write_text('prefix {"pid":16585,"stage":"hook_installed"}\n')
        self.assertIn('stage=hook_installed',self.call('status').stdout)
        file.write_text('prefix {"pid":16585,"stage":"client_build_id_rejected"}\n')
        self.assertIn('stage=hook_failed',self.call('status').stdout)
    def test_running_game_without_module_evidence_is_not_waiting_game(self):
        self.call('game','1')
        self.assertIn('stage=module_not_observed',self.call('status').stdout)
        (self.dir/'state/hooks.jsonl').write_text('{"pid":16585,"stage":"app_config_received"}\n')
        self.assertIn('stage=module_startup_incomplete',self.call('status').stdout)
    def test_collector_recovers_from_unexpected_eof(self):
        shutil.copyfile(ROOT/'collector.sh',self.dir/'collector.sh')
        (self.dir/'bin/logcat').write_text('''#!/bin/sh
dir=${0%/*}/..
case "$*" in *'-b main'*) ;; *) exit 8;; esac
count=$(cat "$dir/state/mock-count" 2>/dev/null || printf 0)
count=$((count+1)); printf '%s' "$count" > "$dir/state/mock-count"
if [ "$count" = 1 ]; then printf 'logcat: Unexpected EOF!\\n' >&2; exit 1; fi
printf '{"pid":16585,"stage":"hook_installed"}\\n' >> "$dir/state/system-module.log"
touch "$dir/disable"
''',newline='\n')
        env=os.environ.copy();env['PATH']=str(self.dir/'bin')+os.pathsep+env['PATH']
        result=subprocess.run([str(BASH),(self.dir/'collector.sh').as_posix()],env=env,text=True,encoding='utf8',capture_output=True,timeout=20)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual((self.dir/'state/mock-count').read_text(),'2')
        self.assertIn('Unexpected EOF',(self.dir/'state/collector-error.txt').read_text())
        self.assertIn('hook_installed',(self.dir/'state/system-module.log').read_text())
    def test_migration_cleanup_preserves_switch_and_aborts_on_failure(self):
        installed=self.dir/'old';installed.mkdir()
        (installed/'module.prop').write_text('versionCode=1006\n');(installed/'game_enabled').write_text('1\n')
        (installed/'target_package').write_text('com.example.channel\n')
        (installed/'controller.sh').write_text('#!/bin/sh\nprintf 0 > "${0%/*}/game_enabled"\nprintf cleanup_ok\\n\n',newline='\n')
        source=(ROOT/'customize.sh').read_text('utf8').replace('INSTALLED=/data/adb/modules/minifire_compat_zygisk',"INSTALLED='"+installed.as_posix()+"'")
        path=self.dir/'customize.sh';path.write_text(source,encoding='utf8',newline='\n')
        wrapper=self.dir/'install-test.sh'
        wrapper.write_text("#!/bin/sh\nMODPATH='"+self.dir.as_posix()+"'\nARCH=arm64\nabort(){ echo \"$*\"; exit 7; }\nui_print(){ :; }\nset_perm(){ :; }\n. \"$MODPATH/customize.sh\"\n",newline='\n')
        result=subprocess.run([str(BASH),str(wrapper)],text=True,encoding="utf8",capture_output=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        self.assertTrue((self.dir/'game_enabled').read_text().startswith('1'))
        self.assertEqual((self.dir/'target_package').read_text().strip(),'com.example.channel')
        self.assertIn('external_proxy_cleanup_success',(self.dir/'state/migration.txt').read_text())
        (installed/'controller.sh').write_text('#!/bin/sh\nexit 1\n',newline='\n')
        self.assertEqual(subprocess.run([str(BASH),str(wrapper)],capture_output=True).returncode,7)
if __name__=='__main__': unittest.main(verbosity=2)
