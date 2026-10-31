#!/usr/bin/env node
// Ordinary empty-model source-server/manager integration. Only health/status
// and normal private ingress maintenance/running intent are exercised.
// No installed service, model request, RDMA or adversarial exercise.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,readdirSync,readFileSync,copyFileSync,writeFileSync} from 'node:fs';
import {createServer} from 'node:net';
import {request} from 'node:http';
import {join,resolve} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {verifyNativeReview} from './lib/platform-native-review.mjs';
const args=process.argv.slice(2);
assert(args.length===5&&args[0]==='--isolated'&&args[1]==='--capsule'&&args[3]==='--sha256');
assert.equal(process.platform,'darwin');assert.notEqual(process.getuid(),0);
const capsule=verifyNativeReview(args[2],args[4]),binary=capsule.binary;
const binarySHA=capsule.receipt.files['bin/mlx-serve'].sha256;
const root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/private/tmp/f9-native-status-');
const models=join(directory,'empty-models'),state=join(directory,'manager');mkdirSync(models,{mode:0o700});
const core=join(root,'platform/studio/Sources/StudioCore'),source=join(directory,'NativeControlLive.swift'),fixture=join(directory,'native-manager');
copyFileSync(join(root,'platform/studio/Tests/StudioCoreTests/NativeControlLive.swift.fixture'),source);
function run(program,arguments_,timeout=180000){
 const result=spawnSync(program,arguments_,{cwd:root,encoding:'utf8',timeout,maxBuffer:2<<20});
 assert.equal(result.status,0,`Native status fixture command failed: ${result.stderr}`);return result.stdout.trim();
}
run('swiftc',['-swift-version','6','-warnings-as-errors','-I',join(root,'platform/studio/Sources/CSQLite'),
 ...readdirSync(core).filter(name=>name.endsWith('.swift')).sort().map(name=>join(core,name)),source,'-o',fixture]);
run('swift',['build','--package-path','platform/studio','--disable-automatic-resolution','--product','studioctl']);
const bin=run('swift',['build','--package-path','platform/studio','--show-bin-path']),cli=join(bin,'studioctl');
const reservation=createServer();await new Promise((accept,reject)=>{reservation.once('error',reject);reservation.listen(0,'127.0.0.1',accept);});
const port=reservation.address().port;await new Promise(accept=>reservation.close(accept));
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',XDG_CACHE_HOME:join(directory,'cache'),
 FIOS_NATIVE_CONTROL:'isolated-source-fixture',FIOS_NATIVE_STARTUP:'isolated-source-fixture'};
const children=[];
const exited=child=>child.exitCode!==null||child.signalCode!==null;
async function until(check,timeout=15000){const end=performance.now()+timeout;while(performance.now()<end){const value=await check();if(value)return value;await delay(25);}throw Error('Ordinary native status deadline');}
function health(){return new Promise((accept,reject)=>{
 const req=request({host:'127.0.0.1',port,path:'/health',method:'GET',agent:false,timeout:2000},res=>{
  let size=0;res.on('data',part=>{size+=part.length;if(size>16384)res.destroy(Error('Native health response limit'));});
  res.once('error',reject);res.once('end',()=>accept(res.statusCode===200));
 });req.once('error',reject);req.once('timeout',()=>req.destroy(Error('Native health deadline')));req.end();
});}
function command(arguments_){const result=spawnSync(cli,['--state',state,...arguments_],{cwd:root,env,encoding:'utf8',timeout:3000});return result.status===0 ? JSON.parse(result.stdout):null;}
try{
 const native=spawn(binary,['serve','--host','127.0.0.1','--port',String(port),'--model-dir',models,'--no-warmup-eager'],{cwd:directory,env,stdio:['ignore','ignore','pipe']});children.push(native);
 let logBytes=0;native.stderr.on('data',part=>{logBytes+=part.length;if(logBytes>128*1024)native.kill('SIGTERM');});
 await until(async()=>{assert(!exited(native),'Empty-model native server exited');try{return await health();}catch(error){if(['ECONNREFUSED','ECONNRESET'].includes(error.code))return false;throw error;}});
 const control=join(directory,'.fios-native-control/control.sock');
 const manager=spawn(fixture,['--isolated-manager',state,control,binary,binarySHA,'source-fixture-only',String(native.pid)],{cwd:root,env,stdio:['ignore','ignore','pipe']});children.push(manager);
 let managerErrors='';manager.stderr.on('data',part=>{managerErrors+=part.toString();});
 const initial=await until(()=>{assert(!exited(manager),`Private manager exited: ${managerErrors}`);return command(['status']);});
 assert.equal(initial.native_control.state,'waiting');assert.equal(initial.native_control.authoritative,false);
 assert.equal(command(['service','mlx','running']).applied,false);
 const opened=await until(()=>{const value=command(['status']);return value?.native_control.state==='received'&&value.native_admissions==='admissionsOpen' ? value:null;});
 const diagnostic=opened.native_control;
 assert.equal(diagnostic.scope,'native_ingress_tracker');assert.equal(diagnostic.authoritative,false);
 assert.equal(diagnostic.source_sampled_at,null);assert.equal(diagnostic.source_sequence,null);
 assert.equal(diagnostic.reported_counts.owners,0);assert.equal(diagnostic.ingress_closed,false);
 assert(diagnostic.receipt_age_ms>=0&&diagnostic.receipt_age_ms<=5000);
 assert.equal(opened.native_activity,'unknown');
 const activity=command(['activity']);assert.equal(activity.coverage,'unknown');
 assert.equal(activity.observation.coverage,'unknown');assert.equal(activity.observation.outstanding_owners,null);
 assert.equal(command(['service','mlx','maintenance']).applied,false);
 const paused=await until(()=>{const value=command(['status']);return value?.native_control.state==='received'&&value.native_control.ingress_closed===true&&value.native_admissions==='admissionsClosed' ? value:null;});
 assert.equal(paused.native_control.source_instance,diagnostic.source_instance);
 assert.equal(command(['service','mlx','running']).applied,false);
 const resumed=await until(()=>{const value=command(['status']);return value?.native_control.state==='received'&&value.native_control.ingress_closed===false&&value.native_admissions==='admissionsOpen' ? value:null;});
 assert.equal(resumed.native_control.source_instance,diagnostic.source_instance);
 assert.equal(resumed.native_control.authoritative,false);assert.deepEqual(readdirSync(models),[]);
 writeFileSync(join(directory,'status-receipts.json'),JSON.stringify({initial,opened,paused,resumed},null,2)+'\n',{mode:0o600});
 manager.kill('SIGTERM');await until(()=>exited(manager),5000);assert.equal(manager.exitCode,0);assert.equal(managerErrors,'');
 native.kill('SIGTERM');await until(()=>exited(native),7000);
 console.log(JSON.stringify({ok:true,source_ingress_roundtrip:true,model_requests:0,installed_service_actions:0,authoritative:false,review_directory:directory}));
}finally{
 for(const child of [...children].reverse())if(!exited(child)){child.kill('SIGTERM');try{await until(()=>exited(child),7000);}catch{child.kill('SIGKILL');await until(()=>exited(child),3000);}}
 // Retain only private source-test data; process exit grants no native proof.
}
