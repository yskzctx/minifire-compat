const fs=require('node:fs');
const vm=require('node:vm');
const assert=require('node:assert/strict');
const html=fs.readFileSync('zygisk-root/webroot/index.html','utf8');
const script=html.match(/<script>([\s\S]*?)<\/script>/)?.[1];
assert(script,'inline UI script');
function bridgeAdapter(context){
  context.atob=value=>Buffer.from(value,'base64').toString('binary');
  context.TextDecoder=TextDecoder;
  const original=context.window.ksu.exec;
  context.window.ksu.exec=wrapped=>{
    const match=/^\( ([\s\S]*) \) 2>&1 \| base64 \| tr -d "\\n"; printf "\\n"$/.exec(wrapped);
    assert(match,'all shell output must cross the bridge as a single encoded line');
    return Buffer.from(original(match[1])).toString('base64');
  };
  return context;
}
const elements=Object.fromEntries(['game','hunter','logs','status','loginfo','copyinfo','refresh','copy'].map(id=>[id,{
  id,checked:false,disabled:true,textContent:'',handlers:{},
  addEventListener(event,handler){this.handlers[event]=handler;}
}]));
const flags={game:'1',hunter:'0'};
const calls=[];
let copied='';
const context={navigator:{clipboard:{writeText(value){copied=value;return Promise.resolve();}}},document:{getElementById:id=>elements[id]},window:{ksu:{exec(command){
  calls.push(command);
  if(command.includes('logcat'))return 'native_stage=3\n';
  assert(command.startsWith('sh /data/adb/modules/minifire_compat_zygisk/control.sh '));
  const args=command.split(' ').slice(-2);
  if(args[1]==='status')return `game=${flags.game}\nhunter=${flags.hunter}\n`;
  assert(['game','hunter'].includes(args[0]));
  assert(['0','1'].includes(args[1]));
  flags[args[0]]=args[1];return args[1]+'\n';
}}}};
vm.runInNewContext(script,bridgeAdapter(context));
assert.equal(elements.game.checked,true);
assert.equal(elements.hunter.checked,false);
assert.equal(elements.game.disabled,false);
assert.equal(elements.logs.textContent,'native_stage=3');
assert(calls.some(command=>command.includes('logcat -d -b main -b system -b crash -v threadtime -t 1500')),
  'UI must display recent unfiltered system logs');
assert(calls.every(command=>!command.includes('MinifireCompatZ:V')),
  'UI log retrieval must not filter to module tag');
elements.copy.handlers.click();
assert.match(copied,/开关已读取/,'copy button must include configuration status');
assert(copied.endsWith(elements.logs.textContent),'copy button must include the full displayed log');
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

const pendingElements=Object.fromEntries(['game','hunter','logs','status','loginfo','copyinfo','refresh','copy'].map(id=>[id,{
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
vm.runInNewContext(script,bridgeAdapter(pendingContext));
assert.equal(pendingElements.game.disabled,false);
assert.equal(pendingElements.hunter.disabled,false);
assert.equal(pendingElements.game.checked,true);
assert.match(pendingElements.logs.textContent,/loader_hooks=2/);
assert(pendingCalls.length>=2);
console.log('pending-update module path ok');

// The manager can serve webroot while control.sh is absent from its module path.
// The UI must still read the packaged flags and fetch logs independently.
const directElements=Object.fromEntries(['game','hunter','logs','status','loginfo','copyinfo','refresh','copy'].map(id=>[id,{
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
vm.runInNewContext(script,bridgeAdapter(directContext));
assert.equal(directElements.game.disabled,false,'game switch must not require control.sh');
assert.equal(directElements.hunter.disabled,false,'hunter switch must not require control.sh');
assert.match(directElements.logs.textContent,/loader_hooks=2/,'log reading must not require control.sh');
directElements.hunter.checked=true;
directElements.hunter.handlers.change();
assert.equal(directFlags.hunter,'1');
console.log('direct-config fallback and independent logs ok');

const missingElements=Object.fromEntries(['game','hunter','logs','status','loginfo','copyinfo','refresh','copy'].map(id=>[id,{
  id,checked:false,disabled:true,textContent:'',handlers:{},
  addEventListener(event,handler){this.handlers[event]=handler;}
}]));
const missingContext={document:{getElementById:id=>missingElements[id]},window:{ksu:{
  moduleInfo:()=>JSON.stringify({id:'minifire_compat_zygisk',moduleDir:'/data/adb/custom_modules/minifire_compat_zygisk'}),
  exec(command){
    if(command==='id -u')return '0\n';
    if(command.includes('logcat'))return 'target=1 loader_hooks=0\n';
    return 'No such file or directory\n';
  }
}}};
let missingCopied='';
missingContext.navigator={clipboard:{writeText(value){missingCopied=value;return {then(success){success();}};}}};
vm.runInNewContext(script,bridgeAdapter(missingContext));
assert.match(missingElements.status.textContent,/UID=0/);
assert.match(missingElements.status.textContent,/custom_modules/);
assert.match(missingElements.logs.textContent,/loader_hooks=0/);
missingElements.copy.handlers.click();
assert.match(missingCopied,/配置读取失败/);
assert.match(missingCopied,/loader_hooks=0/);
assert.match(missingElements.status.textContent,/UID=0/,'copy feedback must not erase config failure');
console.log('missing-config diagnostics ok');

const repairElements=Object.fromEntries(['game','hunter','logs','status','loginfo','copyinfo','refresh','copy'].map(id=>[id,{
  id,checked:false,disabled:true,textContent:'',handlers:{},
  addEventListener(event,handler){this.handlers[event]=handler;}
}]));
const repairFlags={game:'1',hunter:null};
const repairCalls=[];
const repairContext={document:{getElementById:id=>repairElements[id]},window:{ksu:{
  moduleInfo:()=>JSON.stringify({id:'minifire_compat_zygisk',moduleDir:'/data/adb/modules/minifire_compat_zygisk'}),
  exec(command){
    repairCalls.push(command);
    if(command.includes('logcat'))return '';
    if(command.includes('control.sh'))return '';
    if(command.includes('/module.prop'))return 'id=minifire_compat_zygisk\nversionCode=504\n';
    if(command.includes('printf')&&command.includes('hunter_enabled')) repairFlags.hunter='0';
    if(command.includes('game_enabled')&&command.includes('hunter_enabled'))
      return repairFlags.hunter===null?'1\ncat: hunter_enabled: No such file or directory\n':`${repairFlags.game}\n${repairFlags.hunter}\n`;
    return '';
  }
}}};
vm.runInNewContext(script,bridgeAdapter(repairContext));
assert.equal(repairElements.game.disabled,false,'missing hunter flag should be repaired');
assert.equal(repairElements.hunter.disabled,false);
assert.equal(repairElements.game.checked,true,'existing game flag must be preserved');
assert.equal(repairElements.hunter.checked,false);
assert.equal(repairFlags.hunter,'0');
assert(repairCalls.some(command=>command.includes('printf')&&command.includes('hunter_enabled')));
console.log('missing flag repair preserves existing setting ok');

// KernelSU's synchronous WebView bridge uses ShellUtils.fastCmd, which returns
// only the last output line. Reproduce the real bridge instead of returning
// multiline strings as the older mocks above did.
const bridgeElements=Object.fromEntries(['game','hunter','logs','status','loginfo','copyinfo','refresh','copy'].map(id=>[id,{
  id,checked:false,disabled:true,textContent:'',handlers:{},
  addEventListener(event,handler){this.handlers[event]=handler;}
}]));
const systemLines=Array.from({length:1500},(_,index)=>`11-02 12:00:00.000  123  456 I Test: line ${index+1}`).join('\n');
const bridgeFlags={game:'1',hunter:'0'};
const bridgeCommands=[];
const bridgeContext={atob:value=>Buffer.from(value,'base64').toString('binary'),TextDecoder,
 document:{getElementById:id=>bridgeElements[id]},window:{ksu:{
  moduleInfo:()=>JSON.stringify({id:'minifire_compat_zygisk',moduleDir:'/data/adb/modules/minifire_compat_zygisk'}),
  exec(command){
    bridgeCommands.push(command);
    let output='';
    if(command.includes('logcat')) output=systemLines+'\n';
    else if(command.includes('control.sh') && command.includes('status'))
      output=`game=${bridgeFlags.game}\nhunter=${bridgeFlags.hunter}\n`;
    else if(command.includes('control.sh') && command.includes('game 0')){
      bridgeFlags.game='0';output='0\n';
    }
    else if(command.includes('id -u')) output='0\n';
    else output='No such file or directory\n';
    return command.includes('base64')
      ? Buffer.from(output).toString('base64')
      : output.trimEnd().split('\n').at(-1);
  }
}}};
vm.runInNewContext(script,bridgeContext);
assert.equal(bridgeElements.game.disabled,false,'last-line bridge must read both flags');
assert.equal(bridgeElements.game.checked,true);
assert.equal(bridgeElements.logs.textContent.split('\n').length,1500,'last-line bridge must deliver full log snapshot');
bridgeElements.game.checked=false;bridgeElements.game.handlers.change();
assert.equal(bridgeFlags.game,'0','switch must write through last-line bridge');
assert(bridgeCommands.some(command=>command.includes('base64')));
console.log('KernelSU last-line bridge keeps full status and log output ok');
