#!/usr/bin/env node
// Ordinary empty-model source-server/manager integration. Only health/status
// and normal private ingress maintenance/running intent are exercised.
// No installed service, model request, RDMA or adversarial exercise.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,readdirSync,readFileSync,copyFileSync,writeFileSync,existsSync} from 'node:fs';
import {createServer} from 'node:net';
import {request} from 'node:http';
import {createHash} from 'node:crypto';
import {join,resolve} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {verifyNativeReview} from './lib/platform-native-review.mjs';
const args=process.argv.slice(2);
let protocolVersion=2;
function option(flag){const index=args.indexOf(flag);assert.equal(args.filter(value=>value===flag).length,index<0?0:1);if(index>=0)args.splice(index,1);return index>=0;}
const withLineage=option('--lineage'),withBackendFences=option('--backend-fences'),withPrimaryActivity=option('--primary-activity'),withSDKBackground=option('--sdk-background'),withSlowIngress=option('--slow-ingress'),readOnly=option('--read-only'),dynamicObserver=option('--dynamic-observer');
assert(!dynamicObserver||readOnly);
assert(!readOnly||(withBackendFences&&withPrimaryActivity&&withSDKBackground));
assert(!withSDKBackground||withBackendFences);
assert(!withSlowIngress||withPrimaryActivity);
if(args.length===7){assert.equal(args[5],'--protocol-version');assert.equal(args[6],'3');protocolVersion=3;args.splice(5,2);}
assert(args.length===5&&args[0]==='--isolated'&&args[1]==='--capsule'&&args[3]==='--sha256');
assert.equal(process.platform,'darwin');assert.notEqual(process.getuid(),0);
const capsule=verifyNativeReview(args[2],args[4]),binary=capsule.binary;
if(withBackendFences){assert.equal(protocolVersion,3);assert.equal(capsule.receipt.declared_inputs.native_backend_fences_version,2);}
if(withSDKBackground)assert.equal(capsule.receipt.declared_inputs.native_background_coverage_version,1);
if(withPrimaryActivity){assert.equal(protocolVersion,3);assert.equal(capsule.receipt.declared_inputs.native_primary_activity_version,3);}
const binarySHA=capsule.receipt.files['bin/mlx-serve'].sha256;
const root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/private/tmp/f9-native-status-');
const slowInputs=()=>Object.fromEntries(['scripts/check-platform-native-status.mjs','tests/fixtures/platform/native-slow-ingress.py'].map(name=>[name,createHash('sha256').update(readFileSync(join(root,name))).digest('hex')]));
const slowSource=withSlowIngress?slowInputs():null;
const models=join(directory,'empty-models'),state=join(directory,'manager');mkdirSync(models,{mode:0o700});
const core=join(root,'platform/studio/Sources/StudioCore'),source=join(directory,'NativeControlLive.swift'),fixture=join(directory,'native-manager');
copyFileSync(join(root,'platform/studio/Tests/StudioCoreTests/NativeControlLive.swift.fixture'),source);
function run(program,arguments_,timeout=180000){
 const result=spawnSync(program,arguments_,{cwd:root,encoding:'utf8',timeout,maxBuffer:2<<20});
 assert.equal(result.status,0,`Native status fixture command failed: ${result.stderr}`);return result.stdout.trim();
}
if(withSDKBackground){
 assert.equal(run('/usr/sbin/scutil',['--get','LocalHostName'],2000),'fios-core');
 assert.equal(run('/usr/sbin/sysctl',['-n','hw.memsize'],2000),String(24*2**30));
 assert.match(run('/usr/sbin/sysctl',['-n','machdep.cpu.brand_string'],2000),/^Apple M4/);
}
run('swiftc',['-swift-version','6','-warnings-as-errors','-j2','-I',join(root,'platform/studio/Sources/CSQLite'),
 ...readdirSync(core).filter(name=>name.endsWith('.swift')).sort().map(name=>join(core,name)),source,'-o',fixture]);
run('swift',['build','-j','2','--package-path','platform/studio','--disable-automatic-resolution','--product','studioctl']);
const bin=run('swift',['build','-j','2','--package-path','platform/studio','--show-bin-path']),cli=join(bin,'studioctl');
const reservation=createServer();await new Promise((accept,reject)=>{reservation.once('error',reject);reservation.listen(0,'127.0.0.1',accept);});
const port=reservation.address().port;await new Promise(accept=>reservation.close(accept));
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',XDG_CACHE_HOME:join(directory,'cache'),
 FIOS_NATIVE_CONTROL:'isolated-source-fixture',FIOS_NATIVE_STARTUP:'isolated-source-fixture'};
if(withSDKBackground)env.MLX_METAL_RESIDENCY_REFRESH_INTERVAL_MS='25';
const children=[];
const exited=child=>child.exitCode!==null||child.signalCode!==null;
async function until(check,timeout=15000){const end=performance.now()+timeout;while(performance.now()<end){const value=await check();if(value)return value;await delay(25);}throw Error('Ordinary native status deadline');}
function health(){return new Promise((accept,reject)=>{
 const req=request({host:'127.0.0.1',port,path:'/health',method:'GET',agent:false,timeout:2000},res=>{
  let size=0;res.on('data',part=>{size+=part.length;if(size>16384)res.destroy(Error('Native health response limit'));});
  res.once('error',reject);res.once('end',()=>accept(res.statusCode===200));
 });req.once('error',reject);req.once('timeout',()=>req.destroy(Error('Native health deadline')));req.end();
});}
function command(arguments_){const result=spawnSync(cli,['--state',state,...arguments_],{cwd:root,env,encoding:'utf8',timeout:3000});const value=result.status===0 ? JSON.parse(result.stdout):null;if(arguments_[0]==='status'&&value)writeFileSync(join(directory,'last-status.json'),JSON.stringify(value)+'\n',{mode:0o600});return value;}
try{
 const native=spawn(binary,['serve','--host','127.0.0.1','--port',String(port),'--model-dir',models,'--no-warmup-eager'],{cwd:directory,env,stdio:['ignore','ignore','pipe']});children.push(native);
 let logBytes=0;native.stderr.on('data',part=>{logBytes+=part.length;if(logBytes>128*1024)native.kill('SIGTERM');});
 await until(async()=>{assert(!exited(native),'Empty-model native server exited');try{return await health();}catch(error){if(['ECONNREFUSED','ECONNRESET'].includes(error.code))return false;throw error;}});
 const sourceHealth=JSON.parse(run(fixture,['--isolated-health',String(port)],5000));
 assert.deepEqual(sourceHealth,{healthy:true,identity_proven:false,native_idle_proven:false});
 const control=join(directory,'.fios-native-control/control.sock');
 await until(()=>existsSync(control));
 const lineageSeed=withLineage?JSON.parse(run(fixture,['--isolated-seed-lineage',state,control,binary,binarySHA,'source-fixture-only',String(native.pid)],5000)):null;
 if(withLineage)assert.deepEqual(lineageSeed,{seeded_unit_scope:true,model_requests:0,native_authority:false});
 if(readOnly)assert.deepEqual(JSON.parse(run(fixture,['--isolated-seed-maintenance',state],5000)),{durable_desired_verified:true,native_action:false});
 const mode=dynamicObserver?'--isolated-manager-observation-source':readOnly?'--isolated-manager-observation':withSDKBackground?(withPrimaryActivity?'--isolated-manager-background-primary':'--isolated-manager-background'):withPrimaryActivity?(withBackendFences?'--isolated-manager-primary':'--isolated-manager-primary-only'):withBackendFences?'--isolated-manager-fences':protocolVersion===3?'--isolated-manager-v3':'--isolated-manager';
 const manager=spawn(fixture,[mode,state,control,binary,binarySHA,'source-fixture-only',String(native.pid)],{cwd:root,env,stdio:['ignore','ignore','pipe']});children.push(manager);
 let managerErrors='';manager.stderr.on('data',part=>{managerErrors+=part.toString();});
 const initial=await until(()=>{assert(!exited(manager),`Private manager exited: ${managerErrors}`);return command(['status']);});
 assert(['waiting','received'].includes(initial.native_control.state));assert.equal(initial.native_control.authoritative,false);
 assert.equal(command(['service','mlx','running']).applied,false);
 const opened=await until(()=>{const value=command(['status']);return value?.native_control.state==='received'&&(value.native_ingress_admissions??value.native_admissions)===(readOnly?'unknown':'admissionsOpen')&&(!withBackendFences||value.native_control.backend_fences?.state==='received')&&(!withPrimaryActivity||value.native_control.primary_activity?.state==='received') ? value:null;});
 assert.equal(opened.native_admissions,'unsupported','FIO_INGRESS_ACK_EXPOSED_NATIVE_ADMISSION');
 assert.equal(opened.native_ingress_admissions,readOnly?'unknown':'admissionsOpen');if(readOnly)assert.equal(opened.native_control_mode,'observation_only');
 const diagnostic=opened.native_control;
 if(withBackendFences){
  const fences=diagnostic.backend_fences;assert.equal(fences.scope,'independent_partial_backend_fences');assert.equal(fences.frame_version,withSDKBackground?3:2);assert.equal(Object.keys(fences.current_sources).length,7);assert(Object.values(fences.current_sources).some(value=>typeof value==='boolean'));assert(Object.values(fences.current_sources).every(value=>value===null||value===false));assert.equal(fences.coverage,'unknown');assert.equal(fences.authority,false);assert.equal(fences.source_instance,diagnostic.source_instance);
  if(withSDKBackground){assert.equal(fences.source_background?.sdk_residency_refresh_untracked,true);assert.equal(fences.retained_coverage_gap,true);assert.equal(fences.retained_uncertainty,false);}
  else assert(!Object.hasOwn(fences,'source_background'));
  assert.equal(fences.mimo_warm_uncertain,null);assert.equal(fences.ds4_metal_uncertainty,null);assert.equal(fences.ds4_host_uncertainty,null);assert.equal(fences.retained_uncertainty,false);
  assert(fences.source_sequence>0&&fences.source_age_ms>=-1000&&fences.source_age_ms<=5000);
 }
 if(withPrimaryActivity){
  const primary=diagnostic.primary_activity;assert.equal(primary.scope,'primary_request_ownership');assert.equal(primary.coverage,'unknown');assert.equal(primary.authority,false);assert.equal(primary.source_instance,diagnostic.source_instance);
  assert.equal(primary.model_identities,0);assert.equal(primary.tracker_uncertain,false);assert.equal(primary.retained_uncertainty,false);
  assert.equal(primary.reported_counts.owners,primary.reported_counts.ingress);assert.equal(primary.phase_version,4);assert.equal(primary.registry_model_identities,0);assert.equal(primary.registry_ready_declared,0);assert.equal(primary.registry_transitioning,false);assert.equal(primary.coherent_activity,'unknown');assert(Number.isSafeInteger(primary.registry_generation)&&primary.registry_generation>=0);assert.equal(primary.reported_counts.queued,0);assert.equal(primary.reported_counts.preparing,0);assert.equal(primary.reported_counts.active,0);assert.equal(primary.reported_counts.responding,0);
  assert(primary.source_sequence>diagnostic.source_sequence);assert(primary.source_age_ms>=-1000&&primary.source_age_ms<=5000);
 }
 assert.equal(diagnostic.scope,'native_ingress_tracker');assert.equal(diagnostic.authoritative,false);
 if(protocolVersion===3){
  assert(Number.isSafeInteger(diagnostic.source_sampled_at)&&diagnostic.source_sampled_at>0);
  assert(Number.isSafeInteger(diagnostic.source_sequence)&&diagnostic.source_sequence>0);
  assert(diagnostic.source_age_ms>=0&&diagnostic.source_age_ms<=5000);
 }else{assert.equal(diagnostic.source_sampled_at,null);assert.equal(diagnostic.source_sequence,null);}
 assert.equal(diagnostic.reported_counts.owners,0);assert.equal(diagnostic.ingress_closed,false);
 assert(diagnostic.receipt_age_ms>=0&&diagnostic.receipt_age_ms<=5000);
 assert.equal(opened.native_activity,'unknown');
 const activity=command(['activity']);assert.equal(activity.coverage,'unknown');
 assert.equal(activity.observation.coverage,'unknown');assert.equal(activity.observation.outstanding_owners,null);
 if(withLineage){assert.equal(activity.observation.local_ownership.unresolved_count,1);assert.equal(activity.observation.local_ownership.blocked,true);}
 if(withSlowIngress)for(const ending of ['release','drain']){
  const reader=spawn(join(root,'.venv/bin/python'),['-I',join(root,'tests/fixtures/platform/native-slow-ingress.py'),String(port)],{cwd:directory,env,stdio:['pipe','pipe','pipe']});children.push(reader);
  let output='',errors='';reader.stdout.on('data',part=>{output+=part.toString();assert(output.length<4096);});reader.stderr.on('data',part=>{errors+=part.toString();assert(errors.length<4096);});
  await until(()=>{assert(!exited(reader),`Slow ingress reader exited: ${errors}`);return output.includes('\n');},5000);
  const ready=JSON.parse(output);assert.equal(ready.ready,true);assert.equal(ready.model_requests,0);
  const held=await until(()=>{const value=command(['status']);return value?.native_control.reported_counts.owners===1&&value.native_control.primary_activity?.reported_counts.owners===1?value:null;},4000);
  const retained=await until(()=>{const value=command(['status']);return value?.native_control.source_sequence>held.native_control.source_sequence&&value.native_control.primary_activity?.source_sequence>held.native_control.primary_activity.source_sequence?value:null;},4000);
  assert.equal(retained.native_control.reported_counts.owners,1);assert.equal(retained.native_control.source_instance,diagnostic.source_instance);
  assert.equal(retained.native_control.primary_activity.reported_counts.owners,1);assert.equal(retained.native_control.primary_activity.model_identities,0);assert.equal(retained.native_activity,'unknown');assert.equal(retained.native_control.authoritative,false);
  reader.stdin.end(ending+'\n');await until(()=>exited(reader),5000);assert.equal(reader.exitCode,0);assert.equal(errors,'');
  const lines=output.trim().split('\n');assert.equal(lines.length,ending==='drain'?2:1);
  if(ending==='drain'){const completion=JSON.parse(lines[1]);assert.equal(completion.complete,true);assert(completion.body_bytes>256*1024&&completion.body_bytes<=2*1024*1024);}
  const released=await until(()=>{const value=command(['status']);return value?.native_control.reported_counts.owners===0&&value.native_control.primary_activity?.reported_counts.owners===0?value:null;},4000);
  assert.equal(released.native_control.source_instance,diagnostic.source_instance);assert.equal(released.native_activity,'unknown');
  writeFileSync(join(directory,'slow-ingress-'+ending+'-receipt.json'),JSON.stringify({ending,ready,held,retained,released,models:0,native_authority:false},null,2)+'\n',{mode:0o600});
 }
 if(protocolVersion===3){
  assert.equal(activity.observation.native_epoch,diagnostic.source_instance);
  assert.equal(activity.observation.native_sequence,diagnostic.source_sequence);
  assert.equal(activity.observation.native_sampled_at,diagnostic.source_sampled_at);
  assert(activity.observation.sampled_at>=diagnostic.received_at,'Activity publication time predates the native reply it includes');
  await delay(1100);
  const repeated=command(['activity']).observation;
  assert(repeated.sequence>activity.observation.sequence);
  assert(repeated.native_sequence>=activity.observation.native_sequence);
  if(repeated.native_sequence===activity.observation.native_sequence){
   assert.equal(repeated.native_sampled_at,activity.observation.native_sampled_at);
   assert(repeated.source_age_ms>=activity.observation.source_age_ms+1000);
  }else{
   // The existing automatic observation cycle may complete between reads.
   assert(repeated.native_sampled_at>=activity.observation.native_sampled_at);
   assert(repeated.source_age_ms>=0&&repeated.source_age_ms<=5000);
  }

 }
 if(withBackendFences){
  const firstFences=diagnostic.backend_fences;
  const refreshed=await until(()=>{const next=command(['status'])?.native_control.backend_fences;return next?.state==='received'&&next.source_sequence>firstFences.source_sequence?next:null;});
  assert.equal(refreshed.source_instance,firstFences.source_instance);assert(refreshed.source_sampled_at>=firstFences.source_sampled_at);
 }
 if(withPrimaryActivity){
  const first=diagnostic.primary_activity;
  const refreshed=await until(()=>{const next=command(['status'])?.native_control.primary_activity;return next?.state==='received'&&next.source_sequence>first.source_sequence?next:null;});
  assert.equal(refreshed.source_instance,first.source_instance);assert(refreshed.source_sampled_at>=first.source_sampled_at);
 }
 assert.equal(command(['service','mlx','maintenance']).applied,false);
 const paused=await until(()=>{const value=command(['status']);return value?.native_control.state==='received'&&(protocolVersion!==3||value.native_control.source_sequence>diagnostic.source_sequence)&&value.native_control.ingress_closed===!readOnly&&value.native_ingress_admissions===(readOnly?'unknown':'admissionsClosed') ? value:null;});
 assert.equal(paused.native_control.source_instance,diagnostic.source_instance);
 assert.equal(command(['service','mlx','running']).applied,false);
 const resumed=await until(()=>{const value=command(['status']);return value?.native_control.state==='received'&&(protocolVersion!==3||value.native_control.source_sequence>paused.native_control.source_sequence)&&value.native_control.ingress_closed===false&&value.native_ingress_admissions===(readOnly?'unknown':'admissionsOpen') ? value:null;});
 assert.equal(resumed.native_control.source_instance,diagnostic.source_instance);
 if(protocolVersion===3)assert(resumed.native_control.source_sequence>paused.native_control.source_sequence&&paused.native_control.source_sequence>diagnostic.source_sequence);
 assert.equal(resumed.native_control.authoritative,false);assert.deepEqual(readdirSync(models),[]);
 writeFileSync(join(directory,'status-receipts.json'),JSON.stringify({sourceHealth,initial,opened,paused,resumed},null,2)+'\n',{mode:0o600});
 manager.kill('SIGTERM');await until(()=>exited(manager),5000);assert.equal(manager.exitCode,0);assert.equal(managerErrors,'');
 if(readOnly)assert.deepEqual(JSON.parse(run(fixture,['--isolated-check-running',state],5000)),{durable_desired_verified:true,native_action:false});
 const lineageReceipt=withLineage?JSON.parse(run(fixture,['--isolated-check-lineage',state,diagnostic.source_instance],5000)):null;
 if(withLineage){assert.equal(lineageReceipt.persisted_source_sample,true);assert.equal(lineageReceipt.unresolved_uncertainty_retained,true);writeFileSync(join(directory,'lineage-receipt.json'),JSON.stringify(lineageReceipt)+'\n',{mode:0o600});}
 native.kill('SIGTERM');await until(()=>exited(native),7000);
 if(withSlowIngress){assert.deepEqual(slowInputs(),slowSource);writeFileSync(join(directory,'slow-ingress-inputs.json'),JSON.stringify({scope:'runner_and_fixture_bytes_not_whole_native_provenance',files:slowSource,native_review_sha256:args[4],models:0,native_authority:false},null,2)+'\n',{mode:0o600});}
 console.log(JSON.stringify({ok:true,protocol_version:protocolVersion,source_health_probe:true,source_ingress_roundtrip:true,automatic_lineage_checkpoint:withLineage,automatic_backend_fences:withBackendFences,automatic_primary_activity:withPrimaryActivity,automatic_sdk_background:withSDKBackground,slow_ingress_owner_retained:withSlowIngress,observation_only:readOnly,dynamic_observer:dynamicObserver,model_requests:0,installed_service_actions:0,authoritative:false,review_directory:directory}));
}finally{
 for(const child of [...children].reverse())if(!exited(child)){child.kill('SIGTERM');try{await until(()=>exited(child),7000);}catch{child.kill('SIGKILL');await until(()=>exited(child),3000);}}
 // Retain only private source-test data; process exit grants no native proof.
}
