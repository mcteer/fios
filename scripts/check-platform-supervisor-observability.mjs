// Ordinary supervisor→real SDK and manager-child integration; no native app.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,cpSync,copyFileSync,readFileSync,writeFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
assert.deepEqual(process.argv.slice(2),['--isolated']);assert.equal(process.platform,'darwin');assert.notEqual(process.getuid(),0);
const root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/private/tmp/fios-009-otel-supervisor-'),pkg=join(directory,'package');
mkdirSync(pkg,{mode:0o700});cpSync(join(root,'platform/studio/Sources'),join(pkg,'Sources'),{recursive:true});
cpSync(join(root,'platform/studio/Tests/StudioObservabilityTests'),join(pkg,'Tests/StudioObservabilityTests'),{recursive:true});
copyFileSync(join(root,'platform/studio/Package.resolved'),join(pkg,'Package.resolved'));
const manifest=readFileSync(join(root,'platform/studio/Package.swift'),'utf8');
writeFileSync(join(pkg,'Package.swift'),manifest
 .replace('    products: [\n','    products: [\n        .executable(name:"supervisor-telemetry-live",targets:["SupervisorTelemetryLive"]),\n')
 .replace('    targets: [\n','    targets: [\n        .executableTarget(name:"SupervisorTelemetryLive",dependencies:["StudioCore","StudioObservability",.product(name:"OpenTelemetrySdk",package:"opentelemetry-swift-core")]),\n'));
mkdirSync(join(pkg,'Sources/SupervisorTelemetryLive'),{mode:0o700});
const shared=readFileSync(join(root,'platform/studio/Tests/StudioObservabilityFixtures/TelemetryLive.swift.fixture'),'utf8');
assert.equal(shared.split('@main struct TelemetryLive {').length,2);
writeFileSync(join(pkg,'Sources/SupervisorTelemetryLive/SupervisorTelemetryLive.swift'),shared.split('@main struct TelemetryLive {')[0]+readFileSync(join(root,'platform/studio/Tests/StudioObservabilityFixtures/SupervisorTelemetryLive.swift.fixture'),'utf8'));
function run(program,args,timeout=180000){const r=spawnSync(program,args,{encoding:'utf8',timeout,maxBuffer:2<<20});assert.equal(r.status,0,r.stderr);return r.stdout.trim();}
run('swift',['build','--package-path',pkg,'--product','supervisor-telemetry-live','--disable-automatic-resolution']);
run('swift',['build','--package-path',pkg,'--product','studio-manager','--disable-automatic-resolution']);
run('swift',['build','--package-path',pkg,'--product','studioctl','--disable-automatic-resolution']);
assert.deepEqual(JSON.parse(readFileSync(join(pkg,'Package.resolved'))).pins,JSON.parse(readFileSync(join(root,'platform/studio/Package.resolved'))).pins);
const bin=run('swift',['build','--package-path',pkg,'--show-bin-path']),state=join(directory,'state'),capture=join(directory,'sdk.json');
const profile=join(directory,'network.sb');writeFileSync(profile,'(version 1)(allow default)(deny network*)(allow network* (local unix-socket) (remote unix-socket))');
const child=spawn('/usr/bin/sandbox-exec',['-f',profile,join(bin,'supervisor-telemetry-live'),state,capture,join(bin,'studio-manager')],{env:{PATH:'/usr/bin:/bin',HOME:'/var/empty',LANG:'C',LC_ALL:'C'},stdio:['ignore','ignore','pipe']});
let stderr='';child.stderr.on('data',part=>{stderr+=part.toString();});
const exited=()=>child.exitCode!==null||child.signalCode!==null;
async function until(check,timeout=10000){const end=performance.now()+timeout;while(performance.now()<end){const value=check();if(value)return value;await delay(25);}throw Error('Supervisor SDK deadline');}
function snapshot(){try{return JSON.parse(readFileSync(capture));}catch(error){if(error.code==='ENOENT')return null;throw error;}}
function points(value,name){return value?.metrics[name]?.points??[];}
try{
 const first=await until(()=>{assert(!exited(),stderr);const value=snapshot();return points(value,'fios.platform.supervisor.state')[0]?.attributes['fios.supervisor.state']==='running' ? value:null;});
 const resource=first.metrics['fios.platform.supervisor.state'].resource;
 assert.equal(resource['service.name'],'fios-studio-supervisor');
 for(const metric of Object.values(first.metrics))assert.deepEqual(metric.resource,resource);
 assert(first.logs.includes('fios.platform.started')&&first.logs.includes('fios.platform.reconciled'));
 assert.equal(points(first,'fios.platform.supervisor.starts')[0].value,1);
 const time=points(first,'fios.platform.supervisor.sample.time')[0].value;
 await until(()=>{assert(!exited(),stderr);return points(snapshot(),'fios.platform.supervisor.sample.time')[0]?.value>time;});
 const status=JSON.parse(run(join(bin,'studioctl'),['--state',state,'status'],3000));
 assert.equal(status.observability.instrumentation,'opentelemetry-swift');assert.equal(status.native_control.state,'unconfigured');
 assert.equal(status.sandbox_admission,'disabled');assert.equal(status.unresolved_requests,0);
 child.kill('SIGTERM');await until(exited,5000);assert.equal(child.exitCode,0);assert.equal(stderr,'');
 const stopped=snapshot();assert(stopped.logs.includes('fios.platform.stopped'));
 assert.equal(points(stopped,'fios.platform.supervisor.state').length,0);
 for(const resourceValue of stopped.log_resources)assert.deepEqual(resourceValue,resource);
 assert.equal(points(stopped,'fios.platform.events').reduce((sum,p)=>sum+p.value,0),3);
 console.log(JSON.stringify({ok:true,actual_sdk:true,events:3,starts:1,source_clock_advanced:true,native_actions:0,review_directory:directory}));
}finally{
 if(!exited()){child.kill('SIGTERM');try{await until(exited,5000);}catch{child.kill('SIGKILL');await until(exited,3000);}}
 // Retain private state/build/capture; supervisor owns its manager's cleanup.
}
