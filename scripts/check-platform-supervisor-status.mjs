// Ordinary self-process status and macOS path aliases; no service operation.
import assert from 'node:assert/strict';
import {mkdtempSync,readdirSync,writeFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {spawn,spawnSync} from 'node:child_process';
import {setTimeout as delay} from 'node:timers/promises';
import {validatePlatformRelease} from './lib/platform-release.mjs';
const args=process.argv.slice(2),healthIndex=args.indexOf('--native-health-source'),withNativeHealth=healthIndex>=0;
if(withNativeHealth){assert.equal(args.lastIndexOf('--native-health-source'),healthIndex);args.splice(healthIndex,1);assert.equal(args.length,5);}

assert.ok(args.length===1||args.length===5,'Usage: --isolated [--release ABS_RELEASE --sha256 MANIFEST_SHA256]');
assert.equal(args[0],'--isolated');
if(args.length===5){
  assert.equal(args[1],'--release');assert.equal(args[3],'--sha256');
  const verified=validatePlatformRelease(args[2],args[4]);
  const directory=mkdtempSync('/private/tmp/fios-009-supervisor-package-status-'),state=join(directory,'state');
  const child=spawn(join(args[2],'bin/studio-supervisor'),['--state',state],{stdio:'ignore'});
  const exited=new Promise((resolve,reject)=>{child.once('exit',resolve);child.once('error',reject)});
  const status=release=>{
    const result=spawnSync(join(release,'bin/studioctl'),['--state',state,'supervisor'],{encoding:'utf8',timeout:3000});
    return result.status===0 ? JSON.parse(result.stdout):null;
  };
  const managerStatus=release=>{
    const result=spawnSync(join(release,'bin/studioctl'),['--state',state,'status'],{encoding:'utf8',timeout:3000});
    return result.status===0 ? JSON.parse(result.stdout):null;
  };
  function checkNativeHealth(release){
    const value=managerStatus(release);
    assert.equal(value?.native_health_source,'unconfigured');assert.equal(value.native_admissions,'unsupported');
    assert.equal(value.service_recovery,'disabled');assert.equal(value.services.mlx.observed,'unknown');assert.equal(value.services.mlx.health,undefined);
  }
  try{
    const deadline=Date.now()+12000;let value;
    while(Date.now()<deadline){value=status(args[2]);if(value?.supervisor?.state==='running'&&(!withNativeHealth||managerStatus(args[2])?.native_health_source==='unconfigured'))break;await delay(100)}
    assert.equal(value?.supervisor?.state,'running');
    const aliases=[args[2],args[2].replace(/^\/private\/tmp\//,'/tmp/')];
    for(const release of aliases){const read=status(release);assert.equal(read?.ok,true);assert.equal(read.supervisor.pid,child.pid);if(withNativeHealth)checkNativeHealth(release)}
    console.log(JSON.stringify({ok:true,manifest_sha256:verified.manifestSHA256,packaged_supervisor:true,...(withNativeHealth?{native_health_source:'unconfigured'}:{}),path_spellings:aliases.length,native_actions:0,model_posts:0,review_directory:directory}));
  }finally{
    if(child.exitCode===null&&child.signalCode===null)child.kill('SIGTERM');
    let timer;
    try{await Promise.race([exited,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error('Own supervisor shutdown deadline')),10000)})])}
    finally{clearTimeout(timer)}
    assert.equal(child.exitCode,0,'Own supervisor must shut down normally');
  }
  process.exit(0);
}
const root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/private/tmp/fios-009-supervisor-status-');
const core=join(root,'platform/studio/Sources/StudioCore'),entry=join(directory,'StatusMain.swift'),binary=join(directory,'status-live');
writeFileSync(entry,'@main struct StatusMain { static func main() throws { try runSupervisorStatusAliasTests() } }\n');
const sources=readdirSync(core).filter(name=>name.endsWith('.swift')).sort().map(name=>join(core,name));
const build=spawnSync('swiftc',['-swift-version','6','-warnings-as-errors','-I',join(root,'platform/studio/Sources/CSQLite'),...sources,join(root,'platform/studio/Tests/StudioCoreTests/SupervisorStatusAliasTests.swift'),entry,'-o',binary],{encoding:'utf8',timeout:180000,maxBuffer:2<<20});
assert.equal(build.status,0,build.stderr);
const result=spawnSync(binary,[],{encoding:'utf8',timeout:15000,maxBuffer:65536});
assert.equal(result.status,0,result.stderr);process.stdout.write(result.stdout);
console.log(JSON.stringify({ok:true,genuine_kernel_identity:true,native_actions:0,review_directory:directory}));
