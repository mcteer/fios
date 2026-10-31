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
command('swift',['build','--package-path','platform/studio','--disable-automatic-resolution','--product','studioctl']);
const bin=command('swift',['build','--package-path','platform/studio','--show-bin-path']).trim(),cli=join(bin,'studioctl');
const exited=child=>child.exitCode!==null||child.signalCode!==null;
async function until(check,timeout=8000){const end=performance.now()+timeout;while(performance.now()<end){const value=await check();if(value)return value;await delay(25);}throw Error('Service status integration deadline');}
const status=(state,args=['status'])=>{
 const result=spawnSync(cli,['--state',state,...args],{cwd:root,encoding:'utf8',timeout:3000});
 return result.status===0 ? JSON.parse(result.stdout):null;
};
let child;
try{
 for(const mode of ['unknown','waiting_session','waiting_credentials','stopped','ready','degraded']){
  const state=join(directory,mode);
  child=spawn('/usr/bin/sandbox-exec',['-f',profile,binary,state,mode],{cwd:root,env:{PATH:'/usr/bin:/bin',LANG:'C',LC_ALL:'C',HOME:'/var/empty'},stdio:'ignore'});
  await until(()=>{assert(!exited(child),'Status manager exited early');return status(state);});
  const combined=status(state);
  for(const service of ['mlx','orbstack']){
   const selected=status(state,['service',service,'status']);
   assert.equal(selected.observed,mode);assert.equal(selected.desired,'running');assert.equal(selected.launch_pending,false);
   assert.equal(selected.observed,combined.services[service].observed);
   if(mode==='unknown'){assert.equal(selected.sampled_at,null);assert.equal(selected.age_ms,null);}
   else{assert(Number.isSafeInteger(selected.sampled_at));assert(selected.age_ms>=0&&selected.age_ms<=5000);}
  }
  const maintenance=status(state,['service','mlx','maintenance']);assert.equal(maintenance.applied,false);
  assert.equal(status(state,['service','mlx','status']).desired,'maintenance');
  assert.equal(status(state,['service','orbstack','status']).desired,'running');
  child.kill('SIGTERM');await until(()=>exited(child));assert.equal(child.exitCode,0);child=null;
 }
 console.log(JSON.stringify({ok:true,states:6,service_views:12,native_actions:0,review_directory:directory}));
}finally{
 if(child&&!exited(child)){child.kill('SIGTERM');try{await until(()=>exited(child),3000);}catch{child.kill('SIGKILL');await until(()=>exited(child),3000);}}
 // Retain the private development states; no database cleanup or native work.
}
