#!/usr/bin/env node
// Disposable local-runtime fixture only. No pulls, production config or mounts.
import {spawnSync} from 'node:child_process';
import {mkdtempSync,writeFileSync,readFileSync,realpathSync,rmSync,copyFileSync,chmodSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {randomUUID,createHash} from 'node:crypto';
if(![3,4].includes(process.argv.length)||process.argv[2]!=='--isolated'||(process.argv.length===4&&!['--resource-limits','--isolation-matrix'].includes(process.argv[3])))throw Error('Use --isolated [--resource-limits|--isolation-matrix] for disposable runtime tests');
const matrix=process.argv[3]==='--isolation-matrix';
const limits=matrix||process.argv[3]==='--resource-limits';
const root=resolve(import.meta.dirname,'..');
const directory=mkdtempSync(join(tmpdir(),'fios-platform-sandbox-'));
let image,sentinel,siblingIP;
let resourcesPossible=false,verified=false;
function run(command,args,timeout=120000){
  const result=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout,maxBuffer:1<<20,env:{...process.env,DOCKER_BUILDKIT:'0'}});
  if(result.status!==0&&command===join(directory,'sandbox-live'))for(const line of (result.stdout??'').split('\n').filter(line=>line.startsWith('METRIC: ')))console.error(line);
  if(result.status!==0)throw Error(`Fixture subprocess failed: ${command} (${result.status??result.signal})\n${result.stderr??''}`);
  return result.stdout.trim();
}
// OrbStack's signed CLI is a basename-dispatched multicall binary. Keep
// the fixed docker basename without accepting a mutable symlink at exec time.
const docker=join(directory,'docker');
let socketURL;
const runtime=(args,timeout)=>run(docker,['--host',socketURL,...args],timeout);
try{
  copyFileSync(realpathSync(run('/usr/bin/which',['docker'])),docker);chmodSync(docker,0o700);
  socketURL=run(docker,['context','inspect','--format','{{.Endpoints.docker.Host}}']);
  if(!socketURL.startsWith('unix:///'))throw Error('Fixture requires a local Unix runtime');
  const base=runtime(['image','inspect','fios:current','--format','{{.Id}}']);
  if(!/^sha256:[a-f0-9]{64}$/.test(base))throw Error('Expected existing immutable local baseline; no pull permitted');
  const marker=randomUUID(),hostMarker=join(directory,'host-only-'+marker);
  if(matrix){
    writeFileSync(hostMarker,marker,{mode:0o600});
    const sentinelName='fios-isolation-sibling-'+randomUUID();
    writeFileSync(join(directory,'fixture-receipt.json'),JSON.stringify({base,sentinelName,phase:'before-sibling-create'})+'\n',{mode:0o600});
    resourcesPossible=true;
    const code="require('http').createServer((q,r)=>r.end("+JSON.stringify(marker)+")).listen(18080,'0.0.0.0');setTimeout(()=>process.exit(0),180000)";
    sentinel=runtime(['create','--name',sentinelName,'--pull=never','--network=bridge','--read-only','--user=65532:65532','--cap-drop=ALL','--security-opt=no-new-privileges:true','--memory=67108864','--memory-swap=67108864','--cpus=0.25','--pids-limit=16','--log-driver=none','--entrypoint=node',base,'-e',code]);
    if(!/^[a-f0-9]{64}$/.test(sentinel))throw Error('Uncertain sibling create');
    writeFileSync(join(directory,'fixture-receipt.json'),JSON.stringify({base,sentinelName,sentinel,phase:'before-sibling-start'})+'\n',{mode:0o600});
    runtime(['start',sentinel]);
    siblingIP=runtime(['inspect','--format','{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}',sentinel]);
    if(!/^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)[0-9.]+$/.test(siblingIP))throw Error('Expected private sibling address');
    const check="const c=require('http').get('http://127.0.0.1:18080',r=>{let s='';r.on('data',x=>s+=x);r.on('end',()=>{if(s!=="+JSON.stringify(marker)+")process.exit(1);else console.log('LIVE_SIBLING_READY')})});c.setTimeout(1000,()=>{c.destroy();process.exit(1)});c.on('error',()=>process.exit(1))";
    if(runtime(['exec',sentinel,'node','-e',check])!=='LIVE_SIBLING_READY')throw Error('Sibling positive control failed');
  }
  writeFileSync(join(directory,'Dockerfile'),`FROM ${base}\nUSER 65532:65532\nWORKDIR /workspace\nCOPY fixture.mjs /fixture.mjs\n${limits?'COPY limits.py /limits.py\n':''}ENTRYPOINT ["node","/fixture.mjs"]\n`);
  if(limits)writeFileSync(join(directory,'limits.py'),readFileSync(join(root,'platform/studio/Tests/StudioCoreTests/SandboxLimits.py.fixture')));
  writeFileSync(join(directory,'fixture.mjs'),`
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import net from 'node:net';
import dns from 'node:dns';
import {spawnSync} from 'node:child_process';
const status=fs.readFileSync('/proc/self/status','utf8');
assert.match(status,/CapBnd:\\s+0+\\n/);assert.match(status,/CapEff:\\s+0+\\n/);assert.match(status,/NoNewPrivs:\\s+1/);
assert.equal(process.getuid(),65532);
assert.equal(fs.existsSync('/var/run/docker.sock'),false);
assert.equal(fs.existsSync('/root/.ssh'),false);
assert.equal(Object.keys(process.env).some(k=>/MLX_API_KEY|FIOS_PASSWORD|DOCKER_HOST/.test(k)),false);
assert.deepEqual(Object.keys(os.networkInterfaces()),['lo']);
assert.throws(()=>fs.writeFileSync('/forbidden-root-file','x'));
fs.writeFileSync('/workspace/owned','bounded');assert.equal(fs.readFileSync('/workspace/owned','utf8'),'bounded');
await new Promise((resolve,reject)=>{const c=net.connect({host:'1.1.1.1',port:443});c.setTimeout(1000);c.once('connect',()=>{c.destroy();reject(Error('External network reachable'));});c.once('error',()=>resolve());c.once('timeout',()=>{c.destroy();resolve();});});
if(${matrix}) {
 const denied=async(host,port)=>new Promise((resolve,reject)=>{
   const c=net.connect({host,port});c.setTimeout(750);
   c.once('connect',()=>{c.destroy();reject(Error('Denied target reachable'));});
   c.once('error',()=>resolve());c.once('timeout',()=>{c.destroy();resolve();});
 });
 for(const host of ['1.1.1.1','10.0.0.1','192.168.1.1','169.254.169.254',${JSON.stringify(siblingIP??'192.0.2.1')}])await denied(host,host===${JSON.stringify(siblingIP??'192.0.2.1')}?18080:443);
 for(const explicit of [false,true]) {
  const resolver=new dns.Resolver({timeout:250,tries:1});if(explicit)resolver.setServers(['1.1.1.1']);
  await new Promise((resolve,reject)=>{const timer=setTimeout(()=>{resolver.cancel();resolve();},1000);resolver.resolve4('example.com',(error,addresses)=>{clearTimeout(timer);if(!error||addresses?.length)reject(Error('DNS unexpectedly resolved'));else resolve();});});
 }

 assert.equal(fs.existsSync(${JSON.stringify(hostMarker)}),false);
 assert.equal(fs.existsSync('/run/docker.sock'),false);
 assert.equal(fs.existsSync('/proc/1/root'+${JSON.stringify(hostMarker)}),false);
 const mount=spawnSync('/opt/venv/bin/python',['-I','-B','-c',"import ctypes,errno; c=ctypes.CDLL(None,use_errno=True); r=c.mount(b'none',b'/workspace',b'tmpfs',0,None); assert r==-1 and ctypes.get_errno()==errno.EPERM"],{encoding:'utf8',timeout:1000});
 assert.equal(mount.status,0,'Sandbox gained mount authority');
 console.log('METRIC: MATRIX_PASS: public/private/metadata/live-sibling TCP denied; DNS fails closed; host file/control socket absent; mount syscall denied');
}
console.log('ISOLATION_PASS');
if(${limits}) {
 const result=spawnSync('/opt/venv/bin/python',['-I','-B','/limits.py'],{encoding:'utf8',timeout:9000,maxBuffer:16384,env:{PATH:'/usr/bin:/bin',LANG:'C',LC_ALL:'C'}});
 process.stdout.write(result.stdout??'');
 console.log('METRIC: trusted limits child status='+String(result.status)+' signal='+String(result.signal)+' error='+String(result.error?.code??'none'));
 assert.equal(result.error,undefined);assert.equal(result.signal,null);assert.equal(result.status,0,result.stderr);assert.match(result.stdout,/LIMITS_PASS/);
 assert.match(result.stdout,/actual memory ceiling=536870912 child_sigkill=true oom_kill_delta=[1-9][0-9]*/);
}
`);
  // A timed-out build/create is not proof that no resource was created.
  resourcesPossible=true;
  image=runtime(['build','--quiet','--pull=false','--network=none',directory]);
  if(!/^sha256:[a-f0-9]{64}$/.test(image))throw Error('Invalid fixture image identity');
  if(limits)console.log(`METRIC: source_base=${base} fixture_image=${image} limits_source_sha256=${createHash('sha256').update(readFileSync(join(directory,'limits.py'))).digest('hex')}`);
  if(!sentinel)sentinel=runtime(['create','--pull=never','--network=none','--name','fios-platform-sentinel-'+randomUUID(),image]);
  if(!/^[a-f0-9]{64}$/.test(sentinel))throw Error('Uncertain sentinel create result');
  const source=join(directory,'SandboxLive.swift');
  writeFileSync(source,readFileSync(join(root,'platform/studio/Tests/StudioCoreTests/SandboxLive.swift.fixture')));
  const binary=join(directory,'sandbox-live');
  run('/usr/bin/env',['swiftc','-swift-version','6','-warnings-as-errors','-I',join(root,'platform/studio/Sources/CSQLite'),
    ...run('/usr/bin/find',[join(root,'platform/studio/Sources/StudioCore'),'-name','*.swift']).split('\n').sort(),source,'-o',binary]);
  const hash=createHash('sha256').update(readFileSync(docker)).digest('hex');
  const result=run(binary,[docker,hash,socketURL.slice(7),image,sentinel,...(matrix?['matrix']:limits?['limits']:[])]);
  console.log(result);
  if(!result.includes('one known full-ID owned sandbox acknowledged removal and successful empty exact-ID query'))throw Error('Missing owned sandbox removal receipt');
  if(runtime(['inspect','--format','{{.Id}}',sentinel])!==sentinel)throw Error('Unrelated sentinel was removed');
  if(matrix){
    if(readFileSync(hostMarker,'utf8')!==marker)throw Error('Host sentinel changed');
    if(runtime(['inspect','--format','{{.State.Running}}',sentinel])!=='true')throw Error('Sibling stopped during rehearsal');
    console.log('PASS: live sibling and private host sentinel unchanged through isolated denial/limit rehearsal');
  }
  verified=true;
}finally{
  if(verified){
    try{
      runtime(['rm','--force',sentinel]); // Only this driver's exact created sentinel.
      if(runtime(['ps','--all','--no-trunc','--filter','id='+sentinel,'--format','{{.ID}}'])!=='')throw Error('Sentinel absence not verified');
      runtime(['image','rm',image]); // No force: never remove referencing objects.
      rmSync(directory,{recursive:true,force:true});
    }catch(error){console.error('RETAINED: fixture directory after incomplete cleanup: '+directory);throw error;}
  }else if(resourcesPossible){
    console.error('RETAINED: uncertain isolated runtime fixture; no parent cleanup attempted: '+directory);
  }else rmSync(directory,{recursive:true,force:true});
}
