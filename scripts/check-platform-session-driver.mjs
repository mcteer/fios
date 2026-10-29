#!/usr/bin/env node
// Real coordinator/Unix/kernel identities, trusted counter-only fake app ports.
// Never calls the production enrolled factory or NSWorkspace application API.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,copyFileSync,readdirSync,readFileSync,existsSync,writeFileSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {randomUUID} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
assert.equal(process.platform,'darwin');assert.notEqual(process.getuid(),0);assert.deepEqual(process.argv.slice(2),['--isolated']);
const root=fileURLToPath(new URL('../',import.meta.url)),temporary=mkdtempSync('/tmp/fios009-session-driver-'),children=[];
const exited=child=>child.exitCode!==null||child.signalCode!==null;
async function until(check,timeout=5000){const end=performance.now()+timeout;while(performance.now()<end){const value=check();if(value)return value;await delay(20);}throw Error('Finite session driver fixture deadline');}
const policy='(version 1)(allow default)(deny network*)(allow network* (local unix-socket) (remote unix-socket))';
try {
 const fixture=join(temporary,'DriverFixture.swift'),binary=join(temporary,'driver-fixture'),core=join(root,'platform/studio/Sources/StudioCore');
 copyFileSync(join(root,'platform/studio/Tests/StudioCoreTests/SessionDriver.swift.fixture'),fixture);
 const sources=readdirSync(core).filter(n=>n.endsWith('.swift')).sort().map(n=>join(core,n));
 const built=spawnSync('swiftc',['-swift-version','6','-warnings-as-errors','-I',join(root,'platform/studio/Sources/CSQLite'),...sources,fixture,'-o',binary],{cwd:root,encoding:'utf8',timeout:180000,maxBuffer:65536});
 assert.equal(built.status,0,built.stderr);
 for(const [scenario,expected,calls] of [['success','started',1],['validation','not_sent',0],['console','not_sent',0],['running','not_sent',0],['error','uncertain',1],['wrong-process','uncertain',1],['clock','uncertain',0],['expired','not_sent',0],['shutdown',null,0]]) {
  const state=join(temporary,scenario);mkdirSync(state,{mode:0o700});
  const child=spawn('/usr/bin/sandbox-exec',['-p',policy,binary,'server',state,scenario],{stdio:'ignore'});children.push(child);
  await until(()=>existsSync(join(state,'session-control.json')));
  const invoke=(operation,id,service='mlx')=>{
   const result=spawnSync('/usr/bin/sandbox-exec',['-p',policy,binary,'client',state,service,operation,id],{encoding:'utf8',timeout:4000,maxBuffer:4096});
   assert.equal(result.status,0,result.stderr);return result.stdout.trim();
  };
  const id=randomUUID();assert.equal(invoke('launch',id),'uncertain');
  await until(()=>existsSync(join(state,'validation-entered')));
  assert.equal(invoke('lookup',id),'uncertain','Read-only validation blocked or prematurely acknowledged');
  if(scenario==='success')assert.equal(invoke('launch',randomUUID(),'orbstack'),'not_sent','Second validation queued instead of finite non-dispatch');
  if(scenario==='shutdown'){writeFileSync(join(state,'shutdown'),'stop');await delay(50);}
  if(scenario==='expired')await delay(10_100);
  writeFileSync(join(state,'release-validation'),'release');
  if(expected==='uncertain'||expected===null)await delay(300);
  else await until(()=>invoke('lookup',id)===expected);
  if(expected!==null){assert.equal(invoke('lookup',id),expected);assert.equal(invoke('launch',id),expected,'Same-ID launch replayed after callback');}
  assert.equal(Number(readFileSync(join(state,'calls'),'utf8')),calls,scenario+' dispatched an unexpected fake effect');
  child.kill('SIGTERM');await until(()=>exited(child));
 }
 console.log('PASS: actual async session driver, authenticated RPC, one validator/no queue, delayed/duplicate completion, validation/session/presence/expiry refusal, post-dispatch error/wrong-process uncertainty, shutdown/clock fencing and no replay; counter-only fake app API.');
}finally {
 for(const child of children)if(!exited(child))child.kill('SIGTERM');
 await until(()=>children.every(exited),10000);
 rmSync(temporary,{recursive:true,force:true});
}
