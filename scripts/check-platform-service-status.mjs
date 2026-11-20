#!/usr/bin/env node
// Ordinary real-manager/CLI status integration with synthetic observations.
// No native service, runtime daemon, model or installed state is contacted.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,readdirSync,copyFileSync,writeFileSync,readFileSync,unlinkSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {randomBytes,randomUUID} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
assert.deepEqual(process.argv.slice(2),['--isolated']);assert.equal(process.platform,'darwin');assert.notEqual(process.getuid(),0);
const root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/private/tmp/fios-009-service-status-');
const source=join(directory,'ServiceStatusLive.swift'),binary=join(directory,'status-manager'),profile=join(directory,'network.sb');
copyFileSync(join(root,'platform/studio/Tests/StudioCoreTests/ServiceStatusLive.swift.fixture'),source);
writeFileSync(profile,'(version 1)\n(allow default)\n(deny network*)\n(allow network* (local unix-socket) (remote unix-socket))\n',{mode:0o600});
function command(program,args,timeout=180000){
 const result=spawnSync(program,args,{cwd:root,encoding:'utf8',timeout,maxBuffer:2<<20});
 assert.equal(result.status,0,`Ordinary service status command failed: ${result.stderr}`);return result.stdout;
}
const core=join(root,'platform/studio/Sources/StudioCore');
command('swiftc',['-swift-version','6','-warnings-as-errors','-I',join(root,'platform/studio/Sources/CSQLite'),
 ...readdirSync(core).filter(name=>name.endsWith('.swift')).sort().map(name=>join(core,name)),source,'-o',binary]);
command('swift',['build','--package-path','platform/studio','--disable-automatic-resolution','--product','studioctl','-j','2']);
const bin=command('swift',['build','--package-path','platform/studio','--show-bin-path']).trim(),cli=join(bin,'studioctl');
const exited=child=>child.exitCode!==null||child.signalCode!==null;
async function until(check,timeout=8000){const end=performance.now()+timeout;while(performance.now()<end){const value=await check();if(value)return value;await delay(25);}throw Error('Service status integration deadline');}
const status=(state,args=['status'])=>{
 const result=spawnSync(cli,['--state',state,...args],{cwd:root,encoding:'utf8',timeout:3000});
 return result.status===0 ? JSON.parse(result.stdout):null;
};
const messages={unknown:'Service status is unavailable.',starting:'Service is loading.',waiting_session:'Waiting for a user session.',waiting_credentials:'Waiting for service credentials.',stopped:'Service is stopped; running is requested.',ready:'Service is running.',degraded:'Service is present but not responding.'};
const expected=(mode,service)=>mode==='held'?'stopped':['unconfigured','native_source_gap','future'].includes(mode)?'unknown':mode==='loading' ? (service==='mlx'?'starting':'ready'):mode==='mixed' ? (service==='mlx'?'ready':'degraded'):mode;
const modes=['unconfigured','native_source_gap','unknown','future','waiting_session','waiting_credentials','stopped','ready','degraded','mixed','loading','held'];
let child;
try{
 for(const mode of modes){
  const state=join(directory,mode);
  child=spawn('/usr/bin/sandbox-exec',['-f',profile,binary,state,mode],{cwd:root,env:{PATH:'/usr/bin:/bin',LANG:'C',LC_ALL:'C',HOME:'/var/empty'},stdio:'ignore'});
  await until(()=>{assert(!exited(child),'Status manager exited early');const observed=status(state);return observed&&['mlx','orbstack'].every(service=>observed.services[service].observed===expected(mode,service))&&(mode!=='unconfigured'||['native_health_source','orbstack_health_source','vm_resource_source'].every(key=>observed[key]==='unconfigured'));});
  const combined=mode==='native_source_gap'?await until(()=>{const frame=status(state);return frame?.native_control.state==='unavailable'&&frame;}):status(state);
  if(mode==='native_source_gap'){
   assert.equal(combined.native_control_mode,'observation_only');assert.equal(combined.native_admissions,'unsupported');
   const diagnostics=combined.native_control;
   assert.equal(diagnostics.authoritative,false);assert.equal(diagnostics.source_sequence,null);assert.equal(diagnostics.reported_counts,null);
   for(const key of ['primary_activity','backend_fences']){
    assert.equal(diagnostics[key].state,'unavailable');assert.equal(diagnostics[key].authority,false);
   }
  }
  assert.equal(combined.migration_maintenance,mode==='held');
  if(mode==='held'){
   assert.equal(combined.service_recovery,'disabled');
   assert.equal(combined.sandbox_admission,'disabled');
   assert.equal(combined.native_admissions,'unsupported');
  }
  if(mode==='unconfigured'){
   assert.equal(combined.native_health_source,'unconfigured');assert.equal(combined.orbstack_health_source,'unconfigured');
   assert.equal(combined.vm_resource_source,'unconfigured');
   assert.equal(combined.native_admissions,'unsupported');assert.equal(combined.native_ingress_admissions,'unconfigured');assert.equal(combined.service_recovery,'disabled');assert.equal(combined.sandbox_admission,'disabled');
   const diagnostics=combined.native_control;
   assert.equal(diagnostics.state,'unconfigured');assert.equal(diagnostics.authoritative,false);
   for(const key of ['received_at','source_sampled_at','source_sequence','reported_counts'])assert.equal(diagnostics[key],null);
   for(const key of ['primary_activity','backend_fences'])assert(!Object.hasOwn(diagnostics,key));
  }

  assert.equal(combined.runtime_cleanup.scope,'owned_runtime_cleanup');
  assert.equal(combined.runtime_cleanup.pending_sandboxes,0);assert.equal(combined.runtime_cleanup.waiting_over_60s,false);
  assert.equal(combined.runtime_cleanup.storage_continuity_unknown,0);
  for(const service of ['mlx','orbstack']){
   const selected=status(state,['service',service,'status']);
   assert.equal(selected.observed,expected(mode,service));assert.equal(selected.desired,'running');assert.equal(selected.launch_pending,false);
   assert.equal(selected.observed,combined.services[service].observed);
   assert.equal(selected.message,messages[expected(mode,service)]);
   assert.equal(selected.message,combined.services[service].message);
   if(['unknown','unconfigured','native_source_gap'].includes(mode)){assert.equal(selected.sampled_at,null);assert.equal(selected.age_ms,null);}
   else if(mode==='future'){assert(Number.isSafeInteger(selected.sampled_at));assert(selected.age_ms < -1000);assert.equal(selected.sampled_at,combined.services[service].sampled_at);}
   else{assert(Number.isSafeInteger(selected.sampled_at));assert(selected.age_ms>=0&&selected.age_ms<=5000);}
  }
  if(mode==='ready'){
   // Ordinary passage of time must age the observation without changing intent.
   await delay(5200);
   const combinedAged=status(state,['status']);
   const agedProjectionClocks=[];
   for(const service of ['mlx','orbstack']){
    const aged=status(state,['service',service,'status']);
    assert.equal(aged.observed,'unknown');assert.equal(aged.desired,'running');
    assert.equal(aged.message,messages.unknown);
    assert.equal(aged.sampled_at,combined.services[service].sampled_at);
    assert(aged.age_ms>5000);assert.equal(aged.launch_pending,false);
    const combinedView=combinedAged.services[service];
    assert.equal(combinedView.observed,'unknown');assert.equal(combinedView.desired,'running');
    assert.equal(combinedView.sampled_at,aged.sampled_at);assert(combinedView.age_ms>5000);
    assert.equal(combinedView.health,undefined);
    agedProjectionClocks.push(combinedView.sampled_at+combinedView.age_ms);
   }
   assert.equal(agedProjectionClocks[0],agedProjectionClocks[1]);
  }
  const maintenance=status(state,['service','mlx','maintenance']);assert.equal(maintenance.applied,false);
  const held=status(state,['service','mlx','status']);assert.equal(held.desired,'maintenance');
  if(held.observed==='ready')assert.equal(held.message,'Service is running; maintenance is requested.');
  assert.equal(status(state,['service','orbstack','status']).desired,'running');
  const stop=status(state,['service','orbstack','stopped']);assert.equal(stop.applied,false);
  const stopped=status(state,['service','orbstack','status']);assert.equal(stopped.desired,'stopped');
  if(stopped.observed==='ready')assert.equal(stopped.message,'Service is still running; stop is requested.');
  assert.equal(status(state,['service','mlx','status']).desired,'maintenance');
  child.kill('SIGTERM');await until(()=>exited(child));assert.equal(child.exitCode,0);child=null;
  if(['held','unconfigured','native_source_gap'].includes(mode)){
   child=spawn('/usr/bin/sandbox-exec',['-f',profile,binary,state,mode],{cwd:root,env:{PATH:'/usr/bin:/bin',LANG:'C',LC_ALL:'C',HOME:'/var/empty'},stdio:'ignore'});
   const restarted=await until(()=>{
    assert(!exited(child),'Restarted status manager exited early');const s=status(state);
    return s&&s.epoch!==combined.epoch&&(mode!=='native_source_gap'||s.native_control.state==='unavailable')?s:null;
   });
   assert.equal(restarted.migration_maintenance,mode==='held');
   assert.equal(restarted.native_admissions,'unsupported');
   assert.equal(restarted.service_recovery,'disabled');
   assert.equal(restarted.services.mlx.desired,'maintenance');
   assert.equal(restarted.services.orbstack.desired,'stopped');
   for(const service of ['mlx','orbstack']){
    assert.equal(restarted.services[service].launch_pending,false);
    assert.equal(restarted.services[service].observed,expected(mode,service));
    for(const action of [['drain'],['force','prepare']]){
     const denied=spawnSync(cli,['--state',state,'service',service,...action],{cwd:root,encoding:'utf8',timeout:3000});
     assert.equal(denied.status,1);
     const refusal=JSON.parse(denied.stdout);
     assert.equal(refusal.error,'native_unsupported');assert.equal(refusal.applied,false);
    }
   }
   const afterRefusals=status(state);
   assert.equal(afterRefusals.epoch,restarted.epoch);
   assert.equal(afterRefusals.native_control.state,restarted.native_control.state);
   assert.equal(afterRefusals.native_control.authoritative,false);
   for(const service of ['mlx','orbstack']){
    const selected=status(state,['service',service,'status']);
    for(const key of ['desired','observed','launch_pending','sampled_at','message']){
     assert.equal(afterRefusals.services[service][key],restarted.services[service][key],`${mode} ${service} refusal changed ${key}`);
     assert.equal(selected[key],afterRefusals.services[service][key],`${mode} ${service} status disagrees on ${key}`);
    }
   }
   child.kill('SIGTERM');await until(()=>exited(child));assert.equal(child.exitCode,0);child=null;
  }
 }
 const state=join(directory,'storage-continuity');
 child=spawn('/usr/bin/sandbox-exec',['-f',profile,binary,state,'storage_continuity'],{cwd:root,env:{PATH:'/usr/bin:/bin',LANG:'C',LC_ALL:'C',HOME:'/var/empty'},stdio:'inherit'});
 const held=await until(()=>{assert(!exited(child),'Cleanup-status manager exited early');const s=status(state);return s?.runtime_cleanup?.storage_continuity_unknown===2 ? s:null;});
 assert.equal(held.runtime_cleanup.pending_sandboxes,2);
 assert.equal(held.native_admissions,'unsupported');assert.equal(held.native_control.authoritative,false);
 assert.equal(held.unresolved_requests,1);assert.equal(held.worker_reservations,0);
 assert.equal(held.runtime_cleanup.waiting_over_60s,false);
 assert(Number.isSafeInteger(held.runtime_cleanup.manager_observation_age_ms)&&held.runtime_cleanup.manager_observation_age_ms>=0);
 const publications=join(state,'fixture-resource-publications');
 const twoPublications=()=>{try{return readFileSync(publications,'utf8')==='2';}catch(error){if(error.code==='ENOENT')return false;throw error;}};
 await until(()=>{assert(!exited(child));return twoPublications();});
 child.kill('SIGTERM');await until(()=>exited(child));assert.equal(child.exitCode,0);child=null;
 unlinkSync(publications);
 child=spawn('/usr/bin/sandbox-exec',['-f',profile,binary,state,'storage_continuity_reopen'],{cwd:root,env:{PATH:'/usr/bin:/bin',LANG:'C',LC_ALL:'C',HOME:'/var/empty'},stdio:'inherit'});
 const reopened=await until(()=>{assert(!exited(child),'Reopened cleanup-status manager exited early');const s=status(state);return s?.epoch!==held.epoch&&s?.runtime_cleanup?.storage_continuity_unknown===2 ? s:null;});
 assert.equal(reopened.runtime_cleanup.pending_sandboxes,2);
 assert.equal(reopened.native_admissions,'unsupported');assert.equal(reopened.native_control.authoritative,false);
 assert.equal(reopened.unresolved_requests,1);assert.equal(reopened.worker_reservations,0);
 await until(()=>{assert(!exited(child));return twoPublications();});
 const cleanupResources=await until(()=>{
  assert(!exited(child),'Reopened cleanup manager exited before resource read');
  return status(state,['resources']);
 });
 assert.equal(cleanupResources.resource_observation.vm_coverage,'unknown');
 assert.equal(cleanupResources.resource_observation.vm_epoch,null);
 assert.equal(cleanupResources.resource_observation.signals.vm_available.availability,'unknown');
 assert.equal(cleanupResources.resources.vmAvailable,null);
 assert.equal(cleanupResources.resources.vmSampledAt,null,'Unbound synthetic VM timestamp became public evidence');
 assert.equal(cleanupResources.resource_observation.vm_sampled_at,null);
 assert.equal(cleanupResources.resource_observation.signals.vm_available.sampled_at,null);
 assert.equal(cleanupResources.resources.cpu,0);
 assert.equal(cleanupResources.resource_observation.signals.cpu.availability,'observed');
 const readonly=await until(()=>status(state,['export']));
 assert.equal(readonly.manager_epoch,reopened.epoch);
 assert.equal(readonly.coverage,'unsupported');
 assert.equal(readonly.outstanding_owners,null);
 assert.deepEqual(Object.keys(readonly.resources).sort(),['pressure','sampled_at','thermal']);
 for(const key of ['vmAvailable','vm_epoch','resource_observation'])assert(!Object.hasOwn(readonly,key));
 const afterResources=await until(()=>status(state));
 assert.equal(afterResources.epoch,reopened.epoch);
 assert.equal(afterResources.runtime_cleanup.pending_sandboxes,2);
 assert.equal(afterResources.runtime_cleanup.storage_continuity_unknown,2);
 assert.equal(afterResources.unresolved_requests,1);
 assert.equal(reopened.runtime_cleanup.waiting_over_60s,false);
 assert(Number.isSafeInteger(reopened.runtime_cleanup.manager_observation_age_ms)&&reopened.runtime_cleanup.manager_observation_age_ms>=0);
 child.kill('SIGTERM');await until(()=>exited(child));assert.equal(child.exitCode,0);child=null;
 const workerState=join(directory,'unknown-worker');
 let priorEpoch=null;
 for(let launch=0;launch<2;launch++){
  child=spawn('/usr/bin/sandbox-exec',['-f',profile,binary,workerState,'unknown_worker_reopen'],{cwd:root,env:{PATH:'/usr/bin:/bin',LANG:'C',LC_ALL:'C',HOME:'/var/empty'},stdio:'inherit'});
  const current=await until(()=>{assert(!exited(child),'Unknown-worker manager exited early');const s=status(workerState);return s&&s.epoch!==priorEpoch?s:null;});
  priorEpoch=current.epoch;
  assert.equal(current.unresolved_requests,1);assert.equal(current.worker_reservations,1);
  const identity=JSON.parse(readFileSync(join(workerState,'fixture-owner.json'),'utf8'));
  function ownerStatus(owner,exit,operation='job.status'){
   const id=randomUUID();
   const result=spawnSync(cli,['--state',workerState,'task'],{cwd:root,encoding:'utf8',timeout:3000,input:JSON.stringify({version:1,id,operation,payload:{job:identity.job,owner}})});
   assert.equal(result.status,exit);
   const response=JSON.parse(result.stdout);
   assert.equal(response.id,id);assert.equal(response.ok,exit===0);
   return response.ok?response.result:response;
  }
  const foreign=randomBytes(32).toString('base64');
  assert.equal(ownerStatus(foreign,1).error,'unauthorized');
  assert.equal(ownerStatus(foreign,1,'job.renew').error,'unauthorized');
  assert.equal(ownerStatus(identity.owner,1,'job.renew').error,'job_conflict');
  for(let read=0;read<2;read++){
   const owner=ownerStatus(identity.owner,0);
   assert.equal(owner.state,'reconciling');assert.equal(owner.unresolved_managed_requests,1);
   for(const key of ['event','exit_verified','code_complete'])assert(!Object.hasOwn(owner,key));
  }
  const afterRenewal=status(workerState);
  assert.equal(afterRenewal.epoch,current.epoch);
  assert.equal(afterRenewal.unresolved_requests,1);assert.equal(afterRenewal.worker_reservations,1);
  child.kill('SIGTERM');await until(()=>exited(child));assert.equal(child.exitCode,0);child=null;
 }
 console.log(JSON.stringify({ok:true,unknown_worker_custody_survived_restart:true,states:modes.length,service_views:2*modes.length,aged_service_views:2,aged_combined_views:2,restarted_intent_scenarios:3,storage_continuity_refusal:2,storage_custody_survived_restart:true,native_actions:0,review_directory:directory}));
}finally{
 if(child&&!exited(child)){child.kill('SIGTERM');try{await until(()=>exited(child),3000);}catch{child.kill('SIGKILL');await until(()=>exited(child),3000);}}
 // Retain the private development states; no database cleanup or native work.
}
