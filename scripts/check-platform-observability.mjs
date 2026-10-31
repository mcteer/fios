#!/usr/bin/env node
// Ordinary manager→real OTel SDK integration. Copies actual package sources
// into a private fixture build; no SDK stubs, model requests or installation.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,cpSync,copyFileSync,readFileSync,writeFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
assert.deepEqual(process.argv.slice(2),['--isolated']);assert.equal(process.platform,'darwin');assert.notEqual(process.getuid(),0);
const root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/private/tmp/fios-009-otel-live-'),pkg=join(directory,'package');
mkdirSync(pkg,{mode:0o700});
cpSync(join(root,'platform/studio/Sources'),join(pkg,'Sources'),{recursive:true});
cpSync(join(root,'platform/studio/Tests/StudioObservabilityTests'),join(pkg,'Tests/StudioObservabilityTests'),{recursive:true});
const original=readFileSync(join(root,'platform/studio/Package.swift'),'utf8');
assert(original.includes('    products: [\n')&&original.includes('    targets: [\n'));
writeFileSync(join(pkg,'Package.swift'),original
 .replace('    products: [\n','    products: [\n        .executable(name:"telemetry-live",targets:["TelemetryLive"]),\n')
 .replace('    targets: [\n','    targets: [\n        .executableTarget(name:"TelemetryLive",dependencies:["StudioCore","StudioObservability",.product(name:"OpenTelemetrySdk",package:"opentelemetry-swift-core")]),\n'));
copyFileSync(join(root,'platform/studio/Package.resolved'),join(pkg,'Package.resolved'));
mkdirSync(join(pkg,'Sources/TelemetryLive'),{mode:0o700});
copyFileSync(join(root,'platform/studio/Tests/StudioObservabilityFixtures/TelemetryLive.swift.fixture'),join(pkg,'Sources/TelemetryLive/TelemetryLive.swift'));
function run(program,args,timeout=180000){
 const result=spawnSync(program,args,{cwd:root,encoding:'utf8',timeout,maxBuffer:2<<20});
 assert.equal(result.status,0,`Observability fixture command failed: ${result.stderr}`);return result.stdout.trim();
}
run('swift',['build','--package-path',pkg,'--product','telemetry-live']);
run('swift',['build','--package-path',pkg,'--product','studioctl']);
assert.deepEqual(JSON.parse(readFileSync(join(pkg,'Package.resolved'))).pins,JSON.parse(readFileSync(join(root,'platform/studio/Package.resolved'))).pins,'Fixture dependency pins changed');
const bin=run('swift',['build','--package-path',pkg,'--show-bin-path']),state=join(directory,'state'),capture=join(directory,'sdk-capture.json');
const profile=join(directory,'network.sb');
writeFileSync(profile,'(version 1)\n(allow default)\n(deny network*)\n(allow network* (local unix-socket) (remote unix-socket))\n',{mode:0o600});
const child=spawn('/usr/bin/sandbox-exec',['-f',profile,join(bin,'telemetry-live'),state,capture],{cwd:root,env:{PATH:'/usr/bin:/bin',LANG:'C',LC_ALL:'C',HOME:'/var/empty'},stdio:['ignore','ignore','pipe']});
let stderr='';child.stderr.on('data',part=>{stderr+=part.toString();});
const exited=()=>child.exitCode!==null||child.signalCode!==null;
async function until(check,timeout=10000){const end=performance.now()+timeout;while(performance.now()<end){const value=check();if(value)return value;await delay(25);}throw Error('Observability fixture deadline');}
function snapshot(){try{return JSON.parse(readFileSync(capture,'utf8'));}catch(error){if(error.code==='ENOENT')return null;throw error;}}
function scalar(snapshot,name){const points=snapshot.metrics[name]?.points;assert.equal(points?.length,1,`Missing ${name}`);return points[0].value;}
try{
 const first=await until(()=>{assert(!exited(),`Telemetry manager failed: ${stderr}`);const value=snapshot();return value?.metrics['fios.platform.jobs']&&value?.metrics['fios.platform.service.state']?.points.length===2 ? value:null;});
 assert(first.logs.includes('fios.platform.started'));
 assert.equal(first.metrics['fios.platform.jobs'].points.length,8);
 assert.equal(first.metrics['fios.platform.jobs'].points.reduce((sum,point)=>sum+point.value,0),0);
 for(const name of ['fios.platform.inference.unresolved_records','fios.platform.inference.uncertain_records','fios.platform.workers.reservations','fios.platform.artifacts.size','fios.platform.sandbox.cleanup.pending','fios.platform.sandbox.cleanup.wait'])assert.equal(scalar(first,name),0);
 assert(scalar(first,'fios.platform.host.memory.physical')>0);
 const services=first.metrics['fios.platform.service.state'].points;
 assert.deepEqual(services.map(p=>p.attributes['fios.service']).sort(),['mlx','orbstack']);
 for(const point of services){assert.equal(point.value,1);assert.equal(point.attributes['fios.service.desired'],'running');assert.equal(point.attributes['fios.service.observed'],'unknown');}
 const result=JSON.parse(run(join(bin,'studioctl'),['--state',state,'service','mlx','maintenance'],3000));assert.equal(result.applied,false);
 const changed=await until(()=>{const value=snapshot();return value?.logs.includes('fios.platform.desiredChanged') ? value:null;});
 assert.equal(changed.metrics['fios.platform.events'].points.reduce((sum,point)=>sum+point.value,0),2);
 await until(()=>{const value=snapshot();return value?.metrics['fios.platform.service.state']?.points.some(p=>p.attributes['fios.service']==='mlx'&&p.attributes['fios.service.desired']==='maintenance'&&p.attributes['fios.service.observed']==='unknown');});
 child.kill('SIGTERM');await until(exited,5000);assert.equal(child.exitCode,0);assert.equal(stderr,'');
 const stopped=snapshot();assert(stopped.logs.includes('fios.platform.stopped'));
 assert.equal(stopped.metrics['fios.platform.events'].points.reduce((sum,point)=>sum+point.value,0),3);
 console.log(JSON.stringify({ok:true,events:3,job_state_series:8,service_state_series:2,actual_sdk:true,native_actions:0,review_directory:directory}));
}finally{
 if(!exited()){child.kill('SIGTERM');try{await until(exited,3000);}catch{child.kill('SIGKILL');await until(exited,3000);}}
 // Retain private build/capture/state for review, never touch installed state.
}
