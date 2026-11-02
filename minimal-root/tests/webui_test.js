const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const html=fs.readFileSync('minimal-root/webroot/index.html','utf8');
const script=html.match(/<script>([\s\S]*?)<\/script>/)[1];
const elements=Object.fromEntries(['game','status','notice','logs','refresh','copy','export','target','filter','apps','save-target'].map(id=>[id,{value:'',checked:false,disabled:true,textContent:'',handlers:{},replaceChildren(...children){this.children=children;},addEventListener(event,fn){this.handlers[event]=fn;}}]));
let enabled='1',selected='com.miniworldroyale.sparkgame',copied='';const commands=[];
const context={atob:v=>Buffer.from(v,'base64').toString('binary'),TextDecoder,setInterval(){},
 document:{getElementById:id=>elements[id],createElement:()=>({value:'',textContent:''})},navigator:{clipboard:{writeText(value){copied=value;return Promise.resolve();}}},window:{ksu:{
 moduleInfo:()=>JSON.stringify({id:'minifire_compat_zygisk',moduleDir:'/data/adb/modules/minifire_compat_zygisk'}),
 exec(wrapped){assert(wrapped.includes('base64'));const command=wrapped.match(/^\( ([\s\S]*) \) 2>&1/)[1];commands.push(command);
 let result='';if(command.endsWith(' status'))result=`target=${selected}\ngame=${enabled}\nstage=hook_installed\n`;
 else if(command.endsWith(' apps'))result=JSON.stringify([{package:selected,uid:10240},{package:'com.example.minifire.channel',uid:10456}]);
 else if(command.endsWith(' target com.example.minifire.channel')){selected='com.example.minifire.channel';enabled='0';result=selected+'\n';}
 else if(command.endsWith(' game 0')){enabled='0';result='0\n';}
 else if(command.endsWith(' logs'))result='{"stage":"terminal_login_rewritten","request_id":"fixture"}\n';
 else if(command.endsWith(' export'))result='/sdcard/Download/MinifireMinimal-20261102-123456-123.txt\n';
 return Buffer.from(result).toString('base64');
 }}}};
vm.runInNewContext(script,context);
assert.equal(elements.game.checked,true);assert.equal(elements.game.disabled,false);
elements.game.checked=false;elements.game.handlers.change();assert.equal(enabled,'0');
elements.refresh.handlers.click();assert.match(elements.logs.textContent,/terminal_login_rewritten/);
elements.export.handlers.click();assert.match(elements.notice.textContent,/Download\/MinifireMinimal/);
elements.copy.handlers.click();assert.match(copied,/terminal_login_rewritten/);
assert(elements.target.children.some(option=>option.value==='com.example.minifire.channel'));
elements.target.value='com.example.minifire.channel';elements['save-target'].handlers.click();assert.equal(selected,'com.example.minifire.channel');assert.equal(elements.game.checked,false);
const count=commands.length;elements.target.value='com.evil;id';elements['save-target'].handlers.click();assert.equal(commands.filter(command=>command.includes('target com.evil')).length,0);
assert(commands.every(command=>command.startsWith('sh /data/adb/modules/minifire_compat_zygisk/control.sh ')));
console.log('minimal Hook WebUI switch, full bridge output, copy and export ok');
