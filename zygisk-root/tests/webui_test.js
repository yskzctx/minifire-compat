const fs=require('node:fs');
const vm=require('node:vm');
const assert=require('node:assert/strict');
const html=fs.readFileSync('zygisk-root/webroot/index.html','utf8');
const script=html.match(/<script>([\s\S]*?)<\/script>/)?.[1];
assert(script,'inline UI script');
const elements=Object.fromEntries(['game','hunter','logs','status','refresh'].map(id=>[id,{
  id,checked:false,disabled:true,textContent:'',handlers:{},
  addEventListener(event,handler){this.handlers[event]=handler;}
}]));
const flags={game:'1',hunter:'0'};
const calls=[];
const context={document:{getElementById:id=>elements[id]},window:{ksu:{exec(command){
  calls.push(command);
  if(command.includes('logcat'))return 'native_stage=3\n';
  assert(command.startsWith('sh /data/adb/modules/minifire_compat_zygisk/control.sh '));
  const args=command.split(' ').slice(-2);
  if(args[1]==='status')return `game=${flags.game}\nhunter=${flags.hunter}\n`;
  assert(['game','hunter'].includes(args[0]));
  assert(['0','1'].includes(args[1]));
  flags[args[0]]=args[1];return args[1]+'\n';
}}}};
vm.runInNewContext(script,context);
assert.equal(elements.game.checked,true);
assert.equal(elements.hunter.checked,false);
assert.equal(elements.game.disabled,false);
assert.equal(elements.logs.textContent,'native_stage=3');
elements.hunter.checked=true;
elements.hunter.handlers.change();
assert.equal(flags.hunter,'1');
assert.equal(elements.hunter.disabled,false);
assert.match(elements.status.textContent,/已保存/);
elements.game.checked=false;
elements.game.handlers.change();
assert.equal(flags.game,'0');
assert(calls.every(x=>!x.includes('com.bank')));
console.log('webui switches and log display ok');

const pendingElements=Object.fromEntries(['game','hunter','logs','status','refresh'].map(id=>[id,{
  id,checked:false,disabled:true,textContent:'',handlers:{},
  addEventListener(event,handler){this.handlers[event]=handler;}
}]));
const pendingCalls=[];
const pendingContext={document:{getElementById:id=>pendingElements[id]},window:{ksu:{
  moduleInfo:()=>JSON.stringify({id:'minifire_compat_zygisk',moduleDir:'/data/adb/modules_update/minifire_compat_zygisk'}),
  exec(command){
    pendingCalls.push(command);
    if(command.includes('logcat'))return 'target=1 loader_hooks=2\n';
    if(command.startsWith('sh /data/adb/modules/minifire_compat_zygisk/control.sh '))return '';
    assert(command.startsWith('sh /data/adb/modules_update/minifire_compat_zygisk/control.sh '));
    if(command.endsWith(' status'))return 'game=1\nhunter=0\n';
    return '1\n';
  }
}}};
vm.runInNewContext(script,pendingContext);
assert.equal(pendingElements.game.disabled,false);
assert.equal(pendingElements.hunter.disabled,false);
assert.equal(pendingElements.game.checked,true);
assert.match(pendingElements.logs.textContent,/loader_hooks=2/);
assert(pendingCalls.length>=2);
console.log('pending-update module path ok');

// The manager can serve webroot while control.sh is absent from its module path.
// The UI must still read the packaged flags and fetch logs independently.
const directElements=Object.fromEntries(['game','hunter','logs','status','refresh'].map(id=>[id,{
  id,checked:false,disabled:true,textContent:'',handlers:{},
  addEventListener(event,handler){this.handlers[event]=handler;}
}]));
const directCalls=[];
const directFlags={game:'0',hunter:'0'};
const directContext={document:{getElementById:id=>directElements[id]},window:{ksu:{
  moduleInfo:()=>JSON.stringify({id:'minifire_compat_zygisk',moduleDir:'/data/adb/custom_modules/minifire_compat_zygisk'}),
  exec(command){
    directCalls.push(command);
    if(command.includes('control.sh'))return '';
    if(command.includes('logcat'))return 'target=2 loader_hooks=2\n';
    if((command.includes('game_enabled')||command.includes('hunter_enabled')) &&
       !command.includes('/data/adb/custom_modules/minifire_compat_zygisk/')) return 'No such file or directory\n';
    if(command.includes('game_enabled')&&command.includes('hunter_enabled'))return `${directFlags.game}\n${directFlags.hunter}\n`;
    if(command.includes('hunter_enabled')&&command.includes('printf')){
      directFlags.hunter='1';return '1\n';
    }
    return '';
  }
}}};
vm.runInNewContext(script,directContext);
assert.equal(directElements.game.disabled,false,'game switch must not require control.sh');
assert.equal(directElements.hunter.disabled,false,'hunter switch must not require control.sh');
assert.match(directElements.logs.textContent,/loader_hooks=2/,'log reading must not require control.sh');
directElements.hunter.checked=true;
directElements.hunter.handlers.change();
assert.equal(directFlags.hunter,'1');
console.log('direct-config fallback and independent logs ok');

const missingElements=Object.fromEntries(['game','hunter','logs','status','refresh'].map(id=>[id,{
  id,checked:false,disabled:true,textContent:'',handlers:{},
  addEventListener(event,handler){this.handlers[event]=handler;}
}]));
vm.runInNewContext(script,{document:{getElementById:id=>missingElements[id]},window:{ksu:{
  moduleInfo:()=>JSON.stringify({id:'minifire_compat_zygisk',moduleDir:'/data/adb/custom_modules/minifire_compat_zygisk'}),
  exec(command){
    if(command==='id -u 2>&1')return '0\n';
    if(command.includes('logcat'))return 'target=1 loader_hooks=0\n';
    return 'No such file or directory\n';
  }
}}});
assert.match(missingElements.status.textContent,/UID=0/);
assert.match(missingElements.status.textContent,/custom_modules/);
assert.match(missingElements.logs.textContent,/loader_hooks=0/);
console.log('missing-config diagnostics ok');
