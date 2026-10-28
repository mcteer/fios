#!/usr/bin/env node
// Disposable local-runtime fixture only. No pulls, production config or mounts.
import {spawnSync} from 'node:child_process';
import {mkdtempSync,writeFileSync,readFileSync,realpathSync,rmSync,copyFileSync,chmodSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {randomUUID,createHash} from 'node:crypto';
if(![3,4].includes(process.argv.length)||process.argv[2]!=='--isolated'||(process.argv.length===4&&process.argv[3]!=='--resource-limits'))throw Error('Use --isolated [--resource-limits] for disposable runtime tests');
const limits=process.argv[3]==='--resource-limits';
const root=resolve(import.meta.dirname,'..');
const directory=mkdtempSync(join(tmpdir(),'fios-platform-sandbox-'));
let image,sentinel;
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
  writeFileSync(join(directory,'Dockerfile'),`FROM ${base}\nUSER 65532:65532\nWORKDIR /workspace\nCOPY fixture.mjs /fixture.mjs\n${limits?'COPY limits.py /limits.py\n':''}ENTRYPOINT ["node","/fixture.mjs"]\n`);
  if(limits)writeFileSync(join(directory,'limits.py'),readFileSync(join(root,'platform/studio/Tests/StudioCoreTests/SandboxLimits.py.fixture')));
  writeFileSync(join(directory,'fixture.mjs'),`
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import net from 'node:net';
import {spawnSync} from 'node:child_process';
const status=fs.readFileSync('/proc/self/status','utf8');
assert.match(status,/CapEff:\\s+0+\\n/);assert.match(status,/NoNewPrivs:\\s+1/);
assert.equal(process.getuid(),65532);
assert.equal(fs.existsSync('/var/run/docker.sock'),false);
assert.equal(fs.existsSync('/root/.ssh'),false);
assert.equal(Object.keys(process.env).some(k=>/MLX_API_KEY|FIOS_PASSWORD|DOCKER_HOST/.test(k)),false);
assert.deepEqual(Object.keys(os.networkInterfaces()),['lo']);
assert.throws(()=>fs.writeFileSync('/forbidden-root-file','x'));
fs.writeFileSync('/workspace/owned','bounded');assert.equal(fs.readFileSync('/workspace/owned','utf8'),'bounded');
await new Promise((resolve,reject)=>{const c=net.connect({host:'1.1.1.1',port:443});c.setTimeout(1000);c.once('connect',()=>{c.destroy();reject(Error('External network reachable'));});c.once('error',()=>resolve());c.once('timeout',()=>{c.destroy();resolve();});});
console.log('ISOLATION_PASS');
if(${limits}) {
 const result=spawnSync('/opt/venv/bin/python',['-I','-B','/limits.py'],{encoding:'utf8',timeout:9000,maxBuffer:16384,env:{PATH:'/usr/bin:/bin',LANG:'C',LC_ALL:'C'}});
 process.stdout.write(result.stdout??'');
 console.log('METRIC: trusted limits child status='+String(result.status)+' signal='+String(result.signal)+' error='+String(result.error?.code??'none'));
 assert.equal(result.error,undefined);assert.equal(result.signal,null);assert.equal(result.status,0,result.stderr);assert.match(result.stdout,/LIMITS_PASS/);
 assert.match(result.stdout,/actual memory ceiling=536870912 child_sigkill=true oom_kill_delta=[1-9][0-9]*/);
}
`);
  image=runtime(['build','--quiet','--pull=false','--network=none',directory]);
  if(!/^sha256:[a-f0-9]{64}$/.test(image))throw Error('Invalid fixture image identity');
  if(limits)console.log(`METRIC: source_base=${base} fixture_image=${image} limits_source_sha256=${createHash('sha256').update(readFileSync(join(directory,'limits.py'))).digest('hex')}`);
  sentinel=runtime(['create','--pull=never','--network=none','--name','fios-platform-sentinel-'+randomUUID(),image]);
  const source=join(directory,'SandboxLive.swift');
  writeFileSync(source,readFileSync(join(root,'platform/studio/Tests/StudioCoreTests/SandboxLive.swift.fixture')));
  const binary=join(directory,'sandbox-live');
  run('/usr/bin/env',['swiftc','-swift-version','6','-warnings-as-errors','-I',join(root,'platform/studio/Sources/CSQLite'),
    ...run('/usr/bin/find',[join(root,'platform/studio/Sources/StudioCore'),'-name','*.swift']).split('\n').sort(),source,'-o',binary]);
  const hash=createHash('sha256').update(readFileSync(docker)).digest('hex');
  console.log(run(binary,[docker,hash,socketURL.slice(7),image,sentinel,...(limits?['limits']:[])]));
  if(runtime(['inspect','--format','{{.Id}}',sentinel])!==sentinel)throw Error('Unrelated sentinel was removed');
}finally{
  try{
    try{if(sentinel)runtime(['rm','--force',sentinel]);}
    finally{if(image)runtime(['image','rm',image]);}
  }finally{rmSync(directory,{recursive:true,force:true});}
}
