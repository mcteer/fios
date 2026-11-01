#!/usr/bin/env node
// Finite actual owned-process lifecycle only; no native MLX app/model/runtime.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';
import {mkdtempSync,readFileSync,writeFileSync,readdirSync,copyFileSync,mkdirSync,openSync,closeSync,unlinkSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {createHash} from 'node:crypto';
assert.deepEqual(process.argv.slice(2),['--isolated']);assert.equal(process.platform,'darwin');assert(process.getuid()>0);
const root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/private/tmp/fios-009-serving-runtime-');
const hash=b=>createHash('sha256').update(b).digest('hex');
const helper=join(directory,'serving-helper'),c=join(directory,'helper.c');
const helperSource='#include <unistd.h>\n#include <signal.h>\n#include <string.h>\n#include <stdlib.h>\n#include <stdio.h>\n#include <fcntl.h>\nint main(int n,char**v){signal(SIGALRM,SIG_DFL);if(n==2&&strcmp(v[1],"ignore-term")==0){signal(SIGTERM,SIG_IGN);alarm(5);char p[8192];const char*h=getenv("HOME");if(!h||snprintf(p,sizeof(p),"%s/ignore-term-ready",h)>=(int)sizeof(p))return 70;int f=open(p,O_WRONLY|O_CREAT|O_EXCL,0600);if(f<0)return 71;close(f);}else if(n==2&&strcmp(v[1],"exit-once")==0){char p[8192];const char*h=getenv("HOME");if(!h||snprintf(p,sizeof(p),"%s/first-exit-claimed",h)>=(int)sizeof(p))return 72;int f=open(p,O_WRONLY|O_CREAT|O_EXCL,0600);if(f>=0){close(f);alarm(3);}else{alarm(30);}}else if(n==2&&strcmp(v[1],"cwd-proof")==0){alarm(30);char p[8192];const char*q="/private/tmp/fios-009-serving-runtime-";if(!getcwd(p,sizeof(p))||strncmp(p,q,strlen(q))!=0)return 73;int f=open("cwd-proof",O_WRONLY|O_CREAT|O_EXCL,0600);if(f<0)return 74;if(write(f,p,strlen(p))!=(ssize_t)strlen(p))return 75;close(f);}else{alarm(30);}for(;;)pause();}\n';
writeFileSync(c,helperSource,{mode:0o600});
function run(program,args,timeout=120000){const r=spawnSync(program,args,{encoding:'utf8',timeout,maxBuffer:2<<20});assert(!r.error&&!r.signal,JSON.stringify({error:r.error?.code,signal:r.signal,directory,diagnostic:r.stderr?.slice(0,2000)}));assert.equal(r.status,0,r.stderr);return r.stdout;}
run('/usr/bin/clang',[c,'-O2','-o',helper],30000);
const core=join(root,'platform/studio/Sources/StudioCore'),name='MLXServingProcessRuntime.swift';
const implementation=readFileSync(join(core,name)),fixture=readFileSync(join(root,'platform/studio/Tests/NativeFixtures/MLXServingProcessRuntime.swift.fixture'));
const integrationNames=['Supervisor.swift','SupervisorRestartBudget.swift','Watchdog.swift','Termination.swift','ServingCustodyServer.swift','ServingCustodyClient.swift','PrivateWriterLock.swift','PendingControl.swift','ControlIPC.swift','ServingCustodyGate.swift','ServingProcessControlling.swift','ServingCustodyCodec.swift','NativeServingReviewedConfiguration.swift','NativeServingLaunchDocument.swift','NativeServingLaunchInputs.swift','SessionControl.swift','NativeServingRecoveryTransport.swift','AsyncSessionControl.swift','AsyncServingStop.swift','ServingLifecyclePorts.swift','Manager.swift','ServiceRecovery.swift','RecordedServiceProcessProbe.swift','ServingOwnedProcess.swift'];
const integration=Object.fromEntries(integrationNames.map(n=>[n,readFileSync(join(core,n))]));
const unit=join(directory,'RuntimeFixture.swift');writeFileSync(unit,Buffer.concat([implementation,Buffer.from('\n'),fixture]));
for(const mode of ['debug','release']){
 const binary=join(directory,mode),state=join(directory,mode+'-state');
 run('swiftc',['-parse-as-library','-swift-version','6','-warnings-as-errors',...(mode==='release'?['-O']:[]),'-I',join(root,'platform/studio/Sources/CSQLite'),...readdirSync(core).filter(n=>n.endsWith('.swift')&&n!==name).sort().map(n=>join(core,n)),unit,'-o',binary]);
 const output=run(binary,[helper,hash(readFileSync(helper)),state,hash(readFileSync(binary))],30000);writeFileSync(join(directory,mode+'.log'),output,{mode:0o600});
 assert(output.includes('PASS: actual private serving-role process launch/identity/local reap/relaunch'));
 assert(output.includes('PASS: native server transport through actual manager recovery queue'));
 assert(output.includes('PASS: POSIX owned-child reap preserves a separate live Foundation child'));
 assert(output.includes('PASS: guarded private serving stop, pre-signal revocation with retained slot'));
 assert(output.includes('PASS: ignored SIGTERM retains stop uncertainty/capacity'));
 assert(output.includes('PASS: durable stop reservation before dispatch'));
 assert(output.includes('PASS: missing actuator stop history stays unknown'));
 assert(output.includes('PASS: distinct native/session profiles preserve authenticated OrbStack Unix RPC'));
 assert(output.includes('PASS: unexpected owned-child exit retires local custody off-loop before replacement'));
 assert(output.includes('PASS: explicit native working directory preserves relative-path behavior'));
 assert(output.includes('PASS: changed native launch configuration refuses old pending history unchanged'));
 assert(output.includes('PASS: native stop result/cancellation bind original launch receipt'));
 assert(output.includes('PASS: private serving child survives actual client death'));
 const managerState=mkdtempSync('/private/tmp/f9-mlx-manager-');
 const policy='(version 1)(allow default)(deny network*)(allow network* (local unix-socket) (remote unix-socket))';
 const managerLog=openSync(join(managerState,'manager.log'),'wx',0o600);
 const manager=spawn('/usr/bin/sandbox-exec',['-p',policy,binary,'manager',helper,hash(readFileSync(helper)),managerState],{stdio:['ignore',managerLog,managerLog]});closeSync(managerLog);
 const exited=()=>manager.exitCode!==null||manager.signalCode!==null;
 async function until(check,timeout=6000){const end=performance.now()+timeout;while(performance.now()<end){const value=check();if(value)return value;await delay(20);}throw Error('Private native manager fixture deadline');}
 function status(){const r=spawnSync(binary,['control',managerState,'status'],{encoding:'utf8',timeout:2500});const s=r.status===0?JSON.parse(r.stdout):null;if(s)writeFileSync(join(managerState,'last-status.json'),JSON.stringify(s)+'\n',{mode:0o600});return s;}
 try {
  const pending=await until(()=>{assert(!exited());const s=status();return s?.launch_pending?s:null;});
  // The fixture intentionally publishes unknown during validating/spawning.
  // Pending intent cannot manufacture a current absence/presence observation.
  assert(['starting','unknown'].includes(pending.observed));
  assert.equal(pending.recovery.starts_in_window,1);
  writeFileSync(join(managerState,'release-validation'),'release',{mode:0o600});
  const ready=await until(()=>{assert(!exited());const s=status();return s?.observed==='ready'&&!s.launch_pending?s:null;});
  assert.equal(ready.recovery.starts_in_window,1);
  const maintenance=JSON.parse(run(binary,['control',managerState,'maintenance'],3000));assert.equal(maintenance.applied,false);
  const maintained=await until(()=>{const s=status();return s?.desired==='maintenance'?s:null;});
  assert.equal(maintained.recovery.starts_in_window,1);
  const stopIntent=JSON.parse(run(binary,['control',managerState,'stopped'],3000));assert.equal(stopIntent.applied,false);
  const stopped=await until(()=>{assert(!exited());const s=status();return s?.observed==='stopped'&&!s.stop_pending&&!s.launch_pending?s:null;});
  assert.equal(stopped.desired,'stopped');assert.equal(stopped.recovery.starts_in_window,1);
  const resumeIntent=JSON.parse(run(binary,['control',managerState,'running'],3000));assert.equal(resumeIntent.applied,false);
  const resumed=await until(()=>{assert(!exited());const s=status();return s?.observed==='ready'&&!s.stop_pending&&!s.launch_pending?s:null;},12000);
  assert.equal(resumed.desired,'running');assert.equal(resumed.recovery.starts_in_window,2);
  writeFileSync(join(managerState,'fixture-loading'),'loading',{mode:0o600});
  const loading=await until(()=>{const s=status();return s?.observed==='starting'&&!s.stop_pending&&!s.launch_pending?s:null;});
  await delay(4200);assert.equal(status().recovery.starts_in_window,2);assert.equal(status().stop_pending,false);
  unlinkSync(join(managerState,'fixture-loading'));await until(()=>status()?.observed==='ready');
  writeFileSync(join(managerState,'fixture-unavailable'),'unavailable original process',{mode:0o600});
  const recovered=await until(()=>{assert(!exited());const s=status();return s?.observed==='ready'&&!s.stop_pending&&!s.launch_pending&&s.recovery.starts_in_window===3?s:null;},16000);
  assert.equal(recovered.desired,'running');
  manager.kill('SIGTERM');await until(exited,4000);assert.equal(manager.exitCode,0);
  writeFileSync(join(directory,mode+'-manager.json'),JSON.stringify({pending,ready,maintained,stopped,resumed,loading,recovered,state:managerState,identity:'actual_private_helper',readiness:'synthetic',native_authority:false})+'\n',{mode:0o600});
 }catch(error){console.error('RETAINED private native manager fixture:',managerState);throw error;}finally {
  if(!exited()){manager.kill('SIGTERM');try{await until(exited,3000);}catch{manager.kill('SIGKILL');await until(exited,3000);}}
 }
 const unexpectedState=mkdtempSync('/private/tmp/f9-mlx-manager-');
 const unexpectedLog=openSync(join(unexpectedState,'manager.log'),'wx',0o600);
 const unexpected=spawn('/usr/bin/sandbox-exec',['-p',policy,binary,'manager',helper,hash(readFileSync(helper)),unexpectedState,'unexpected'],{stdio:['ignore',unexpectedLog,unexpectedLog]});closeSync(unexpectedLog);
 const unexpectedExited=()=>unexpected.exitCode!==null||unexpected.signalCode!==null;
 function unexpectedStatus(){const r=spawnSync(binary,['control',unexpectedState,'status'],{encoding:'utf8',timeout:2500});const s=r.status===0?JSON.parse(r.stdout):null;if(s)writeFileSync(join(unexpectedState,'last-status.json'),JSON.stringify(s)+'\n',{mode:0o600});return s;}
 try {
  await until(()=>{assert(!unexpectedExited());return unexpectedStatus()?.launch_pending;});
  writeFileSync(join(unexpectedState,'release-validation'),'release',{mode:0o600});
  const ready=await until(()=>{const s=unexpectedStatus();return s?.observed==='ready'&&!s.launch_pending?s:null;});assert.equal(ready.recovery.starts_in_window,1);
  const lost=await until(()=>{assert(!unexpectedExited());const s=unexpectedStatus();return s?.observed==='stopped'&&!s.launch_pending?s:null;});
  assert.equal(lost.desired,'running');assert.equal(lost.recovery.starts_in_window,1);assert(lost.recovery.budget_wait_ms>0);
  const recovered=await until(()=>{assert(!unexpectedExited());const s=unexpectedStatus();return s?.observed==='ready'&&!s.launch_pending&&s.recovery.starts_in_window===2?s:null;},12000);
  assert.equal(recovered.desired,'running');assert.equal(recovered.stop_pending,false);
  unexpected.kill('SIGTERM');await until(unexpectedExited,4000);assert.equal(unexpected.exitCode,0);
  writeFileSync(join(directory,mode+'-manager-unexpected.json'),JSON.stringify({ready,lost,recovered,state:unexpectedState,identity:'actual_self_expiring_private_helper',readiness:'synthetic',native_authority:false})+'\n',{mode:0o600});
 }catch(error){console.error('RETAINED unexpected private child fixture:',unexpectedState);throw error;}finally {
  if(!unexpectedExited()){unexpected.kill('SIGTERM');try{await until(unexpectedExited,3000);}catch{unexpected.kill('SIGKILL');await until(unexpectedExited,3000);}}
 }
 const custodyState=mkdtempSync('/private/tmp/f9-mlx-supervisor-'),managerDirectory=join(directory,mode+'-custody-manager');
 mkdirSync(managerDirectory,{mode:0o700});const managerImage=join(managerDirectory,'studio-manager');copyFileSync(binary,managerImage);
 const custodyLog=openSync(join(custodyState,'fixture-supervisor.log'),'wx',0o600);
 const custodian=spawn('/usr/bin/sandbox-exec',['-p',policy,binary,'custody-supervisor',helper,hash(readFileSync(helper)),custodyState,hash(readFileSync(binary)),managerImage],{stdio:['ignore',custodyLog,custodyLog]});closeSync(custodyLog);
 const custodyExited=()=>custodian.exitCode!==null||custodian.signalCode!==null;
 function custodyStatus(){const r=spawnSync(binary,['observe',custodyState],{encoding:'utf8',timeout:2500});const s=r.status===0?JSON.parse(r.stdout):null;if(s)writeFileSync(join(custodyState,'last-status.json'),JSON.stringify(s)+'\n',{mode:0o600});return s;}
 function custodyJSON(name){try{return JSON.parse(readFileSync(join(custodyState,name),'utf8'));}catch{return null;}}
 try {
  const first=await until(()=>{assert(!custodyExited());const s=custodyStatus(),mlx=s?.services?.mlx;return mlx?.observed==='ready'&&!mlx.launch_pending?s:null;},9000);
  assert.equal(first.unresolved_requests,1);assert.equal(first.services.mlx.recovery.starts_in_window,1);
  const original=custodyJSON('fixture-native-health.json'),before=custodyJSON('progress.json');assert.equal(original.state,'present');assert(original.pid>1);assert(original.launch_id);
  writeFileSync(join(custodyState,'fixture-exit-request'),'exit exactly one private manager',{mode:0o600,flag:'wx'});
  const second=await until(()=>{assert(!custodyExited());const progress=custodyJSON('progress.json'),supervisor=custodyJSON('supervisor.json');if(progress?.pid===before.pid||supervisor?.starts!==2)return null;const s=custodyStatus();return s?.services?.mlx?.observed==='ready'&&!s.services.mlx.launch_pending?s:null;},9000);
  const retained=custodyJSON('fixture-native-health.json');assert.equal(retained.pid,original.pid);assert.equal(retained.process_start,original.process_start);assert.equal(retained.launch_id,original.launch_id);
  assert.equal(second.unresolved_requests,1);assert.equal(second.services.mlx.recovery.starts_in_window,1);assert.equal(custodyJSON('supervisor.json').state,'running');
  const requested=JSON.parse(run(binary,['control',custodyState,'stopped'],2500));assert.equal(requested.applied,false);
  const stopped=await until(()=>{assert(!custodyExited());const s=custodyStatus(),mlx=s?.services?.mlx;return mlx?.observed==='stopped'&&!mlx.stop_pending?s:null;},9000);
  assert.equal(stopped.unresolved_requests,1);assert.equal(stopped.services.mlx.desired,'stopped');
  custodian.kill('SIGTERM');await until(custodyExited,5000);assert.equal(custodian.exitCode,0);
  assert.deepEqual(custodyJSON('custody-supervisor-receipt.json'),{start_validations:1,stop_validations:1,uncertain:1,native_authority:false});
  writeFileSync(join(directory,mode+'-custody-supervisor.json'),JSON.stringify({first,second,stopped,original,state:custodyState,identity:'actual_private_helper',readiness:'synthetic',native_authority:false})+'\n',{mode:0o600});
 }catch(error){console.error('RETAINED actual supervisor custody fixture:',custodyState);throw error;}finally{
  if(!custodyExited()){custodian.kill('SIGTERM');try{await until(custodyExited,4000);}catch{custodian.kill('SIGKILL');await until(custodyExited,3000);}}
 }
}
assert(implementation.equals(readFileSync(join(core,name))));
for(const [n,bytes] of Object.entries(integration))assert(bytes.equals(readFileSync(join(core,n))));
const receipt={ok:true,directory,provenance_scope:'declared_runtime_integration_and_fixture_only',modes:['debug','release'],source_sha256:hash(implementation),integration_sha256:Object.fromEntries(Object.entries(integration).map(([n,b])=>[n,hash(b)])),fixture_sha256:hash(fixture),helper_source_sha256:hash(helperSource),actual_private_child_starts:30,actual_owned_serving_child_starts:28,actual_unrelated_private_children:2,explicit_working_directory_checks:2,actual_guarded_private_stops:12,guarded_private_stop_timeouts:2,self_expiring_private_helpers:4,pre_signal_revocations:2,denied_stop_validations:2,fresh_start_validations_per_queue_scenario:5,unexpected_exit_recoveries:4,durable_stop_reservation:true,restored_stop_dispatch:false,missing_stop_history:'unknown',distinct_native_session_profiles:true,actual_counter_only_orbstack_session_calls:2,mlx_gui_calls:0,actual_manager_processes:8,actual_private_custody_client_processes:4,actual_private_custody_client_terminations:2,private_custody_reconnect_scenarios:2,actual_supervisor_custody_processes:2,actual_supervisor_manager_replacements:2,actual_manager_stop_resume_cycles:2,actual_manager_unavailable_recoveries:2,actual_manager_unexpected_exit_recoveries:2,loading_without_restart_checks:2,manager_readiness:'synthetic',native_mlx_actions:0,native_inference:false,native_authority:false,installed:false};
writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt)+'\n',{mode:0o600});console.log(JSON.stringify(receipt));
