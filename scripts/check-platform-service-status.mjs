#!/usr/bin/env node
// Ordinary real-manager/CLI status integration with synthetic observations.
// No native service, runtime daemon, model or installed state is contacted.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,readdirSync,copyFileSync,writeFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
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
const expected=(mode,service)=>mode==='unconfigured'?'unknown':mode==='loading' ? (service==='mlx'?'starting':'ready'):mode==='mixed' ? (service==='mlx'?'ready':'degraded'):mode;
let child;
try{
 for(const mode of ['unconfigured','unknown','waiting_session','waiting_credentials','stopped','ready','degraded','mixed','loading']){
  const state=join(directory,mode);
  child=spawn('/usr/bin/sandbox-exec',['-f',profile,binary,state,mode],{cwd:root,env:{PATH:'/usr/bin:/bin',LANG:'C',LC_ALL:'C',HOME:'/var/empty'},stdio:'ignore'});
  await until(()=>{assert(!exited(child),'Status manager exited early');const observed=status(state);return observed&&['mlx','orbstack'].every(service=>observed.services[service].observed===expected(mode,service))&&(mode!=='unconfigured'||['native_health_source','orbstack_health_source','vm_resource_source'].every(key=>observed[key]==='unconfigured'));});
  const combined=status(state);
  if(mode==='unconfigured'){
   assert.equal(combined.native_health_source,'unconfigured');assert.equal(combined.orbstack_health_source,'unconfigured');
   assert.equal(combined.vm_resource_source,'unconfigured');
   assert.equal(combined.native_admissions,'unsupported');assert.equal(combined.native_ingress_admissions,'unconfigured');assert.equal(combined.service_recovery,'disabled');assert.equal(combined.sandbox_admission,'disabled');
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
   if(mode==='unknown'||mode==='unconfigured'){assert.equal(selected.sampled_at,null);assert.equal(selected.age_ms,null);}
   else{assert(Number.isSafeInteger(selected.sampled_at));assert(selected.age_ms>=0&&selected.age_ms<=5000);}
  }
  if(mode==='ready'){
   // Ordinary passage of time must age the observation without changing intent.
   await delay(5200);
   for(const service of ['mlx','orbstack']){
    const aged=status(state,['service',service,'status']);
    assert.equal(aged.observed,'unknown');assert.equal(aged.desired,'running');
    assert.equal(aged.message,messages.unknown);
    assert.equal(aged.sampled_at,combined.services[service].sampled_at);
    assert(aged.age_ms>5000);assert.equal(aged.launch_pending,false);
   }
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
 }
 const state=join(directory,'storage-continuity');
 child=spawn('/usr/bin/sandbox-exec',['-f',profile,binary,state,'storage_continuity'],{cwd:root,env:{PATH:'/usr/bin:/bin',LANG:'C',LC_ALL:'C',HOME:'/var/empty'},stdio:'inherit'});
 const held=await until(()=>{assert(!exited(child),'Cleanup-status manager exited early');const s=status(state);return s?.runtime_cleanup?.storage_continuity_unknown===1 ? s:null;});
 assert.equal(held.runtime_cleanup.pending_sandboxes,1);
 assert.equal(held.runtime_cleanup.waiting_over_60s,false);
 child.kill('SIGTERM');await until(()=>exited(child));assert.equal(child.exitCode,0);child=null;
 console.log(JSON.stringify({ok:true,states:9,service_views:18,aged_service_views:2,storage_continuity_refusal:1,native_actions:0,review_directory:directory}));
}finally{
 if(child&&!exited(child)){child.kill('SIGTERM');try{await until(()=>exited(child),3000);}catch{child.kill('SIGKILL');await until(()=>exited(child),3000);}}
 // Retain the private development states; no database cleanup or native work.
}
