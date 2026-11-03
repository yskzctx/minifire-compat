"""Read-only ADB diagnosis: no preference contents, credentials or raw key names leave the phone."""
import argparse, datetime, json, re, shutil, subprocess
from pathlib import Path

def build_script(package,android_user):
    if not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+',package) or len(package)>255:
        raise ValueError('invalid package')
    if not isinstance(android_user,int) or not 0<=android_user<=999:raise ValueError('invalid Android user')
    path=f'/data/user/{android_user}/{package}/shared_prefs/{package}.v2.playerprefs.xml'
    return '''set -u
if [ "$(id -u)" != 0 ]; then printf 'probe_error=root_required\n'; exit 1; fi
probe_file='''+repr(path)+'''
if [ ! -f "$probe_file" ]; then printf 'prefs_file=missing\n'; exit 0; fi
if [ -L "$probe_file" ]; then printf 'probe_error=symlink_refused\n'; exit 1; fi
printf 'prefs_file=present\n'
stat -c 'file_uid=%u\nfile_gid=%g\nfile_mode=%a\nfile_bytes=%s\nmtime_unix=%Y' "$probe_file" || exit 1
if [ -f "$probe_file.bak" ]; then printf 'backup_file=present\n'; else printf 'backup_file=missing\n'; fi
# Select individual XML string elements, never entire lines: Android XML may put
# credentials and settings on the same line. Never echo the selected contents.
probe_names=$(grep -Eo 'name="[^"<]*BattleSet[^"<]*"' "$probe_file" | wc -l)
probe_nodes=$(grep -Eo '<string[[:space:]]+name="[^"<]*BattleSet[^"<]*">[^<]*</string>' "$probe_file" || :)
probe_matched=$(printf '%s\n' "$probe_nodes" | grep -c '^<string' || :)
printf 'settings_key_count=%s\nsettings_element_count=%s\n' "$probe_names" "$probe_matched"
if [ "$probe_names" -gt 0 ] && [ "$probe_names" = "$probe_matched" ]; then
    probe_digest=$(printf '%s\n' "$probe_nodes" | sha256sum)
    printf 'settings_digest=%s\n' "${probe_digest%% *}"
else printf 'settings_digest=unavailable\n'; fi
'''

def parse_report(text):
    result={}
    for line in text.splitlines():
        key,separator,value=line.partition('=')
        if not separator:continue
        if key in {'file_uid','file_gid','file_mode','file_bytes','mtime_unix','settings_key_count','settings_element_count'} and value.strip().isdigit():result[key]=int(value)
        if key in {'prefs_file','backup_file'} and value in {'present','missing'}:result[key]=value
        if key=='settings_digest' and (value=='unavailable' or re.fullmatch('[0-9a-f]{64}',value)):result[key]=value
        if key=='probe_error' and value in {'root_required','symlink_refused'}:result[key]=value
    return result

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--package',default='com.miniworldroyale.sparkgame');parser.add_argument('--android-user',type=int,default=0)
    parser.add_argument('--phase',required=True,choices=['after_adjust','after_close','before_reopen','after_reopen'])
    parser.add_argument('--adb',default=shutil.which('adb') or str(Path.home()/'Android/Sdk/platform-tools/adb.exe'));args=parser.parse_args()
    script=build_script(args.package,args.android_user)
    devices=subprocess.run([args.adb,'devices'],capture_output=True,text=True,encoding='utf8',check=True).stdout
    ready=[line.split()[0] for line in devices.splitlines() if line.endswith('\tdevice')]
    if len(ready)!=1:raise SystemExit('Exactly one authorized ADB device is required; no phone state was changed.')
    response=subprocess.run([args.adb,'-s',ready[0],'exec-out','su','-c','sh'],input=script,capture_output=True,text=True,encoding='utf8',timeout=20)
    record=parse_report(response.stdout);record.update(phase=args.phase,time=datetime.datetime.now(datetime.timezone.utc).isoformat(),package=args.package,android_user=args.android_user,command_exit=response.returncode)
    if not record.get('prefs_file') and not record.get('probe_error'):record['probe_error']='metadata_unavailable'
    destination=Path(__file__).resolve().parents[1]/'device-data/settings-probes';destination.mkdir(parents=True,exist_ok=True)
    path=destination/(datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%d-%H%M%S')+'-'+args.phase+'.json')
    path.write_text(json.dumps(record,indent=2,ensure_ascii=False)+'\n',encoding='utf8')
    print(json.dumps(record,indent=2,ensure_ascii=False));print('Saved private diagnostic:',path)
if __name__=='__main__':main()
