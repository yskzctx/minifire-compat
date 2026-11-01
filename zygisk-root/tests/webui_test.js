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
  assert(command.startsWith('sh /data/adb/modules/minifire_compat_zygisk/control.sh '));
  const args=command.split(' ').slice(-2);
  if(args[1]==='status')return `game=${flags.game}\nhunter=${flags.hunter}\n`;
  if(args[1]==='logs')return 'native_stage=3\n';
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
