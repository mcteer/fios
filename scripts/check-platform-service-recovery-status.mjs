#!/usr/bin/env node
// Ordinary real manager/session/CLI flow with a counter-only application port.
// Runs only the single-completion functional scenario; no native app action.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,copyFileSync,readdirSync,readFileSync,existsSync,writeFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
assert.deepEqual(process.argv.slice(2),['--isolated']);assert.equal(process.platform,'darwin');assert.notEqual(process.getuid(),0);
const root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/tmp/fios009-session-driver-'),children=[];
let state=join(directory,'ordinary-recovery');mkdirSync(state,{mode:0o700});
const fixture=join(directory,'Driver.swift'),binary=join(directory,'driver'),core=join(root,'platform/studio/Sources/StudioCore');
copyFileSync(join(root,'platform/studio/Tests/StudioCoreTests/SessionDriver.swift.fixture'),fixture);
function run(program,args,timeout=180000){const r=spawnSync(program,args,{encoding:'utf8',timeout,maxBuffer:2<<20});assert.equal(r.status,0,r.stderr);return r.stdout.trim();}
run('swiftc',['-swift-version','6','-warnings-as-errors','-I',join(root,'platform/studio/Sources/CSQLite'),...readdirSync(core).filter(n=>n.endsWith('.swift')).sort().map(n=>join(core,n)),fixture,'-o',binary]);
run('swift',['build','--package-path',join(root,'platform/studio'),'--product','studioctl','--disable-automatic-resolution']);
const cli=join(run('swift',['build','--package-path',join(root,'platform/studio'),'--show-bin-path']),'studioctl');
const policy='(version 1)(allow default)(deny network*)(allow network* (local unix-socket) (remote unix-socket))';
const exited=p=>p.exitCode!==null||p.signalCode!==null;
async function until(check,timeout=12000){const end=performance.now()+timeout;while(performance.now()<end){const value=check();if(value)return value;await delay(25);}throw Error('Ordinary recovery status deadline');}
function start(mode,scenario){const p=spawn('/usr/bin/sandbox-exec',['-p',policy,binary,mode,state,scenario],{stdio:'ignore'});children.push(p);return p;}
function status(){const r=spawnSync(cli,['--state',state,'service','mlx','status'],{encoding:'utf8',timeout:2000});return r.status===0 ? JSON.parse(r.stdout):null;}
try{
 const helper=start('server','functional');await until(()=>existsSync(join(state,'session-control.json')));
 const manager=start('manager','known');
 await until(()=>{assert(!exited(helper)&&!exited(manager));return existsSync(join(state,'validation-entered'));});
 const pending=status();assert.equal(pending.observed,'starting');assert.equal(pending.recovery.budget_state,'pending');assert.equal(pending.recovery.budget_wait_ms,null);
 writeFileSync(join(state,'release-validation'),'release');
 const ready=await until(()=>{const s=status();return s?.observed==='ready'&&s.recovery.budget_state==='rate_limited' ? s:null;});
 assert.equal(ready.recovery.starts_in_window,1);assert(ready.recovery.budget_wait_ms>0&&ready.recovery.budget_wait_ms<=10000);
 const available=await until(()=>{const s=status();return s?.recovery.budget_state==='available' ? s:null;});
 assert.equal(available.observed,'ready');assert.equal(available.recovery.starts_in_window,1);assert.equal(available.recovery.budget_wait_ms,0);
 assert.equal(Number(readFileSync(join(state,'calls'),'utf8')),1);
 manager.kill('SIGTERM');await until(()=>exited(manager));assert.equal(manager.exitCode,0);
 helper.kill('SIGTERM');await until(()=>exited(helper));assert.equal(helper.exitCode,0);
 // A later operator maintenance intent revokes a launch which is still
 // performing read-only validation. The actual application port stays counter-only.
 state=join(directory,'maintenance-during-validation');mkdirSync(state,{mode:0o700});
 const heldHelper=start('server','functional');await until(()=>existsSync(join(state,'session-control.json')));
 let heldManager=start('manager','known');
 await until(()=>{assert(!exited(heldHelper)&&!exited(heldManager));return existsSync(join(state,'validation-entered'));});
 const intent=JSON.parse(run(cli,['--state',state,'service','mlx','maintenance'],3000));assert.equal(intent.applied,false);
 writeFileSync(join(directory,'revocation-before-release.json'),JSON.stringify(status())+'\n',{mode:0o600});
 await until(()=>{const s=status();return s?.desired==='maintenance'&&!s.launch_pending ? s:null;},5000);
 assert.equal(Number(readFileSync(join(state,'calls'),'utf8')),0);
 const second=run('/usr/bin/sandbox-exec',['-p',policy,binary,'client',state,'orbstack','launch','00000000-0000-4000-8000-000000000001'],4000);
 assert.equal(second,'not_sent','Revocation released a validator slot before its actual return');
 writeFileSync(join(state,'release-validation'),'release');
 await until(()=>existsSync(join(state,'validation-returned')));await delay(250);
 assert.equal(Number(readFileSync(join(state,'calls'),'utf8')),0,'Revoked validation later opened the application');
 assert.equal(status().desired,'maintenance');assert.equal(status().launch_pending,false);
 heldManager.kill('SIGTERM');await until(()=>exited(heldManager));assert.equal(heldManager.exitCode,0);
 heldManager=start('manager','known');
 await until(()=>status()?.desired==='maintenance');await delay(2200);
 assert.equal(status().desired,'maintenance');assert.equal(status().launch_pending,false);
 assert.equal(Number(readFileSync(join(state,'calls'),'utf8')),0,'Manager restart replayed the revoked launch');
 const resumed=JSON.parse(run(cli,['--state',state,'service','mlx','running'],3000));assert.equal(resumed.applied,false);
 await until(()=>{const s=status();return s?.observed==='ready'&&!s.launch_pending ? s:null;},12000);
 assert.equal(Number(readFileSync(join(state,'calls'),'utf8')),1,'Explicit later running intent did not perform exactly one new launch');
 heldManager.kill('SIGTERM');await until(()=>exited(heldManager));assert.equal(heldManager.exitCode,0);
 heldHelper.kill('SIGTERM');await until(()=>exited(heldHelper));assert.equal(heldHelper.exitCode,0);
 console.log(JSON.stringify({ok:true,actual_manager:true,actual_session:true,application_port:'counter_only',application_calls:2,revoked_validation_calls:0,actual_validator_slot_retained:true,maintenance_survives_manager_restart:true,native_actions:0,review_directory:directory}));
}catch(error){console.error('RETAINED ordinary service recovery fixture:',directory);throw error;}finally{
 for(const child of children.reverse())if(!exited(child)){child.kill('SIGTERM');try{await until(()=>exited(child),3000);}catch{child.kill('SIGKILL');await until(()=>exited(child),3000);}}
}
