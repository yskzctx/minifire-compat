const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync('external-root/webroot/index.html','utf8');
const script=html.match(/<script>([\s\S]*?)<\/script>/)[1];
const elements=Object.fromEntries(['game','status','notice','logs','refresh','copy','export'].map(id=>[id,{checked:false,disabled:true,textContent:'',handlers:{},addEventListener(event,fn){this.handlers[event]=fn;}}]));
let enabled='1',copied='';const commands=[];
const context={atob:v=>Buffer.from(v,'base64').toString('binary'),TextDecoder,setInterval(){},
 document:{getElementById:id=>elements[id]},navigator:{clipboard:{writeText(value){copied=value;return Promise.resolve();}}},window:{ksu:{
 moduleInfo:()=>JSON.stringify({id:'minifire_compat_zygisk',moduleDir:'/data/adb/modules/minifire_compat_zygisk'}),
 exec(wrapped){assert(wrapped.includes('base64'));const command=wrapped.match(/^\( ([\s\S]*) \) 2>&1/)[1];commands.push(command);
 let result='';if(command.endsWith(' status'))result=`game=${enabled}\nstage=running\n`;
 else if(command.endsWith(' game 0')){enabled='0';result='0\n';}
 else if(command.endsWith(' logs'))result='{"stage":"signature_or_profile_unverified","request_id":"fixture"}\n';
 else if(command.endsWith(' export'))result='/sdcard/Download/MinifireExternal-20261102-123456-123.txt\n';
 return Buffer.from(result).toString('base64');
 }}}};
vm.runInNewContext(script,context);
assert.equal(elements.game.checked,true);assert.equal(elements.game.disabled,false);
elements.game.checked=false;elements.game.handlers.change();assert.equal(enabled,'0');
elements.refresh.handlers.click();assert.match(elements.logs.textContent,/signature_or_profile_unverified/);
elements.export.handlers.click();assert.match(elements.notice.textContent,/Download\/MinifireExternal/);
elements.copy.handlers.click();assert.match(copied,/signature_or_profile_unverified/);
assert(commands.every(command=>command.startsWith('sh /data/adb/modules/minifire_compat_zygisk/control.sh ')));
console.log('external WebUI switch, full bridge output, copy and export ok');
