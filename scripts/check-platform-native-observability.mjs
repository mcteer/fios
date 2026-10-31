#!/usr/bin/env node
// Real SDK/manager/private native control. Normal observations only; no model.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,cpSync,copyFileSync,readFileSync,writeFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {createServer} from 'node:net';
import {randomBytes} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {verifyNativeReview} from './lib/platform-native-review.mjs';
const args=process.argv.slice(2),root=resolve(import.meta.dirname,'..');
assert(args.length===5&&args[0]==='--isolated'&&args[1]==='--capsule'&&args[3]==='--sha256');
const capsule=verifyNativeReview(args[2],args[4]);assert(capsule.receipt.declared_inputs.native_control_protocol_versions.includes(3));
const directory=mkdtempSync('/private/tmp/f9-otel-native-'),pkg=join(directory,'package'),state=join(directory,'state'),capture=join(directory,'sdk.json');
mkdirSync(pkg,{mode:0o700});cpSync(join(root,'platform/studio/Sources'),join(pkg,'Sources'),{recursive:true});
cpSync(join(root,'platform/studio/Tests/StudioObservabilityTests'),join(pkg,'Tests/StudioObservabilityTests'),{recursive:true});
copyFileSync(join(root,'platform/studio/Package.resolved'),join(pkg,'Package.resolved'));
copyFileSync(join(root,'platform/studio/Tests/StudioObservabilityFixtures/NativeTelemetryBridge.swift.fixture'),join(pkg,'Sources/StudioCore/NativeTelemetryBridge.swift'));
const packageText=readFileSync(join(root,'platform/studio/Package.swift'),'utf8');
writeFileSync(join(pkg,'Package.swift'),packageText.replace('    products: [\n','    products: [\n        .executable(name:"telemetry-live",targets:["TelemetryLive"]),\n').replace('    targets: [\n','    targets: [\n        .executableTarget(name:"TelemetryLive",dependencies:["StudioCore","StudioObservability",.product(name:"OpenTelemetrySdk",package:"opentelemetry-swift-core")]),\n'));
mkdirSync(join(pkg,'Sources/TelemetryLive'),{mode:0o700});
const original=readFileSync(join(root,'platform/studio/Tests/StudioObservabilityFixtures/TelemetryLive.swift.fixture'),'utf8');
assert(original.includes('args.count==3')&&original.includes('try ManagerRuntime.run(directory:URL(fileURLWithPath:args[1]),telemetry:'));
writeFileSync(join(pkg,'Sources/TelemetryLive/TelemetryLive.swift'),original.replace('args.count==3','args.count==7').replace('try ManagerRuntime.run(directory:URL(fileURLWithPath:args[1]),telemetry:','try NativeTelemetryBridge.run(directory:URL(fileURLWithPath:args[1]),socket:args[3],binary:args[4],sha256:args[5],pid:Int32(args[6])!,telemetry:'));
function run(program,args,timeout=180000){const r=spawnSync(program,args,{encoding:'utf8',timeout,maxBuffer:2<<20});assert.equal(r.status,0,r.stderr);return r.stdout.trim();}
run('swift',['build','--package-path',pkg,'--product','telemetry-live','--disable-automatic-resolution']);
run('swift',['build','--package-path',pkg,'--product','studioctl','--disable-automatic-resolution']);
assert.deepEqual(JSON.parse(readFileSync(join(pkg,'Package.resolved'))).pins,JSON.parse(readFileSync(join(root,'platform/studio/Package.resolved'))).pins);
const bin=run('swift',['build','--package-path',pkg,'--show-bin-path']);
const home=join(directory,'native'),models=join(directory,'empty-models');mkdirSync(home,{mode:0o700});mkdirSync(models,{mode:0o700});
const listener=createServer();await new Promise(ok=>listener.listen(0,'127.0.0.1',ok));const port=listener.address().port;await new Promise(ok=>listener.close(ok));
const key=randomBytes(32).toString('hex'),children=[];
const exited=p=>p.exitCode!==null||p.signalCode!==null;
async function until(check,timeout=12000){const end=performance.now()+timeout;while(performance.now()<end){const value=await check();if(value)return value;await delay(25);}throw Error('Native observability deadline');}
function snapshot(){try{return JSON.parse(readFileSync(capture));}catch(error){if(error.code==='ENOENT')return null;throw error;}}
function point(value,name){const points=value?.metrics['fios.platform.native.ingress.'+name]?.points;return points?.length===1 ? points[0]:null;}
function command(...args){const r=spawnSync(join(bin,'studioctl'),['--state',state,...args],{encoding:'utf8',timeout:3000});return r.status===0 ? JSON.parse(r.stdout):null;}
try{
 const native=spawn(capsule.binary,['serve','--host','127.0.0.1','--port',String(port),'--model-dir',models,'--no-warmup-eager','--api-key-env','FIOS_SOURCE_MODEL_KEY','--api-key-strict'],{env:{PATH:'/usr/bin:/bin',HOME:home,LANG:'C',LC_ALL:'C',XDG_CACHE_HOME:join(home,'cache'),FIOS_NATIVE_CONTROL:'isolated-source-fixture',FIOS_NATIVE_STARTUP:'isolated-source-fixture',FIOS_SOURCE_MODEL_KEY:key},stdio:['ignore','ignore','pipe']});children.push(native);
 let nativeBytes=0;native.stderr.on('data',part=>{nativeBytes+=part.length;if(nativeBytes>128*1024)native.kill('SIGTERM');});
 await until(async()=>{assert(!exited(native));try{return (await fetch('http://127.0.0.1:'+port+'/health',{headers:{Authorization:'Bearer '+key},signal:AbortSignal.timeout(500)})).ok;}catch{return false;}});
 const profile=join(directory,'network.sb');writeFileSync(profile,'(version 1)(allow default)(deny network*)(allow network* (local unix-socket) (remote unix-socket))');
 const manager=spawn('/usr/bin/sandbox-exec',['-f',profile,join(bin,'telemetry-live'),state,capture,join(home,'.fios-native-control/control.sock'),capsule.binary,capsule.receipt.files['bin/mlx-serve'].sha256,String(native.pid)],{env:{PATH:'/usr/bin:/bin',HOME:'/var/empty',LANG:'C'},stdio:['ignore','ignore','pipe']});children.push(manager);
 let managerErrors='';manager.stderr.on('data',part=>{managerErrors+=part.toString();});
 await until(()=>{assert(!exited(manager),managerErrors);return command('status');});
 assert.equal(command('service','mlx','running').applied,false);
 const first=await until(()=>{const value=snapshot();return point(value,'owners') ? value:null;});
 const owners=point(first,'owners');assert.equal(owners.value,0);assert.equal(owners.attributes['fios.scope'],'native_ingress_tracker');assert.equal(owners.attributes['fios.sample.clock'],'source_and_receipt');
 const receiptTime=point(first,'receipt.time').value,sourceTime=point(first,'source.time').value;assert(sourceTime<=receiptTime);
 const status=command('status');assert.equal(status.native_control.authoritative,false);assert.equal(status.native_activity,'unknown');
 assert.equal(sourceTime,status.native_control.source_sampled_at/1000);assert.equal(receiptTime,status.native_control.received_at/1000);
 await until(()=>{const value=snapshot();return value&&!point(value,'owners');},10000);
 assert.equal(command('status').native_control.state,'stale');
 assert.equal(command('service','mlx','running').applied,false);
 await until(()=>{const value=snapshot();return point(value,'source.time')?.value>sourceTime;});
 manager.kill('SIGTERM');await until(()=>exited(manager));assert.equal(manager.exitCode,0);assert.equal(managerErrors,'');
 native.kill('SIGTERM');await until(()=>exited(native));assert.equal(native.exitCode,0);
 console.log(JSON.stringify({ok:true,actual_sdk:true,actual_native_control:true,protocol:3,clock_values_preserved:true,expired_sample_omitted:true,normal_refresh:true,model_posts:0,native_authority:false,review_directory:directory}));
}finally{
 for(const child of children.reverse())if(!exited(child)){child.kill('SIGTERM');try{await until(()=>exited(child),5000);}catch{child.kill('SIGKILL');await until(()=>exited(child),2000);}}
}
