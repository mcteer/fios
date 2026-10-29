#!/usr/bin/env node
// Explicit disposable runtime fixture only; no pulls/native services/models.
import {spawnSync} from 'node:child_process';
import {mkdtempSync,writeFileSync,readFileSync,realpathSync,rmSync,copyFileSync,chmodSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,resolve} from 'node:path';
import {createHash,randomUUID,randomBytes} from 'node:crypto';
import {validatePlatformRelease} from './lib/platform-release.mjs';
const options=process.argv.slice(2);
if(options[0]!=='--isolated'||![1,2,3,7].includes(options.length)||(options.length>=2&&options[1]!=='--release')||(options.length>=3&&options[2]!=='--vm-shared-300')||(options.length===7&&(options[3]!=='--observation-release'||options[5]!=='--observation-sha256'||!options[4].startsWith('/')||!/^[a-f0-9]{64}$/.test(options[6]))))throw Error('Use --isolated [--release [--vm-shared-300 [--observation-release ABS --observation-sha256 SHA]]]');
const optimized=options[1]==='--release',longVM=options[2]==='--vm-shared-300';
let observerSupervisor;
if(options.length===7){const verified=validatePlatformRelease(options[4],options[6]);if(verified.activation||verified.manifest.package_complete)throw Error('Only incomplete observation-only source payload permitted');observerSupervisor=join(resolve(options[4]),'bin/studio-supervisor');}
const root=resolve(import.meta.dirname,'..'),directory=mkdtempSync(join(tmpdir(),'fios-platform-attach-'));
let image,socketURL,possible=false,success=false;
const job=randomUUID(),nonce=randomBytes(32).toString('hex'),name='fios-sandbox-'+job;
const docker=join(directory,'docker');
const state=()=>writeFileSync(join(directory,'fixture-state.json'),JSON.stringify({version:1,image,job,nonce,name,success},null,2)+'\n',{mode:0o600});
function run(command,args,timeout=120000){
  const result=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout,maxBuffer:1<<20,env:{...process.env,DOCKER_BUILDKIT:'0'}});
  if(result.status!==0){
    if(command===join(directory,'attach-live'))for(const line of (result.stdout??'').split('\n').filter(line=>line.startsWith('METRIC: ')||line.startsWith('RETAINED: ')))console.error(line);
    throw Error(`Fixture subprocess failed (${result.status??result.signal}): ${result.stderr??''}`);
  }
  return result.stdout.trim();
}
const runtime=args=>run(docker,['--host',socketURL,...args]);
try{
  copyFileSync(realpathSync(run('/usr/bin/which',['docker'])),docker);chmodSync(docker,0o700);
  socketURL=run(docker,['context','inspect','--format','{{.Endpoints.docker.Host}}']);
  if(!socketURL.startsWith('unix:///'))throw Error('Only local private Unix runtime accepted');
  const base=runtime(['image','inspect','fios:current','--format','{{.Id}}']);
  if(!/^sha256:[a-f0-9]{64}$/.test(base))throw Error('Existing immutable baseline required; no pulls');
  writeFileSync(join(directory,'Dockerfile'),`FROM ${base}\nUSER 65532:65532\nWORKDIR /workspace\nCOPY fixture.mjs /fixture.mjs\nENTRYPOINT ["node","/fixture.mjs"]\n`);
  writeFileSync(join(directory,'fixture.mjs'),`
import fs from 'node:fs';
if(process.getuid()!==65532)process.exit(2);
const bytes=Buffer.alloc(65540);let total=0,length;
while(total<4||(length!==undefined&&total<4+length)){
  const n=fs.readSync(0,bytes,total,length===undefined?4-total:4+length-total,null);
  if(n===0)process.exit(3);total+=n;
  if(total>=4&&length===undefined){length=bytes.readUInt32BE(0);if(length<1||length>65536)process.exit(4);}
}
const data=bytes.subarray(0,total);let written=0;
while(written<data.length)written+=fs.writeSync(1,data,written,data.length-written);
`);
  possible=true;state();
  image=runtime(['build','--quiet','--pull=false','--network=none',directory]);
  if(!/^sha256:[a-f0-9]{64}$/.test(image))throw Error('Invalid immutable image ID');
  const source=join(directory,'DockerAttachLive.swift'),binary=join(directory,'attach-live');
  writeFileSync(source,readFileSync(join(root,'platform/studio/Tests/StudioCoreTests/DockerAttachLive.swift.fixture')));
  const companion=join(directory,'ObservationCompanion.swift');
  writeFileSync(companion,readFileSync(join(root,'platform/studio/Tests/StudioCoreTests/ObservationCompanion.swift.fixture')));
  run('/usr/bin/env',['swiftc',...(optimized?['-O']:[]),'-swift-version','6','-warnings-as-errors','-I',join(root,'platform/studio/Sources/CSQLite'),...run('/usr/bin/find',[join(root,'platform/studio/Sources/StudioCore'),'-name','*.swift']).split('\n').sort(),companion,source,'-o',binary]);
  console.log(run(binary,[docker,createHash('sha256').update(readFileSync(docker)).digest('hex'),socketURL.slice(7),image,job,nonce,'echo'],30000));
  runtime(['image','rm',image]);image=undefined;
  writeFileSync(join(directory,'Dockerfile'),readFileSync(join(root,'platform/studio/sandbox/Dockerfile')));
  writeFileSync(join(directory,'runner.py'),readFileSync(join(root,'platform/studio/sandbox/runner.py')));
  possible=true;state();
  image=runtime(['build','--quiet','--pull=false','--network=none','--build-arg',`APPROVED_BASE=${base}`,directory]);
  if(!/^sha256:[a-f0-9]{64}$/.test(image))throw Error('Invalid immutable runner image ID');
  console.log(run(binary,[docker,createHash('sha256').update(readFileSync(docker)).digest('hex'),socketURL.slice(7),image,job,nonce,'runner'],30000));
  console.log(run(binary,[docker,createHash('sha256').update(readFileSync(docker)).digest('hex'),socketURL.slice(7),image,job,nonce,'runner-shared'],30000));
  if(longVM)console.log(run(binary,[docker,createHash('sha256').update(readFileSync(docker)).digest('hex'),socketURL.slice(7),image,job,nonce,'runner-shared-300',...(observerSupervisor?[observerSupervisor]:[])],340000));
  console.log(run(binary,[docker,createHash('sha256').update(readFileSync(docker)).digest('hex'),socketURL.slice(7),image,job,nonce,'probe'],35000));
  console.log(run(binary,[docker,createHash('sha256').update(readFileSync(docker)).digest('hex'),socketURL.slice(7),image,job,nonce,'controller',join(root,'.venv/bin/python')],40000));
  console.log(run(binary,[docker,createHash('sha256').update(readFileSync(docker)).digest('hex'),socketURL.slice(7),image,job,nonce,'controller-model',join(root,'.venv/bin/python')],40000));
  if(runtime(['container','ls','--all','--no-trunc','--filter','name=^/'+name+'$','--format','{{.ID}}'])!=='')throw Error('Successful helper left its owned resource present');
  success=true;state();
}finally{
  if(success){
    try{if(image)runtime(['image','rm',image]);rmSync(directory,{recursive:true,force:true});}
    catch(error){console.error('RETAINED: incomplete attach fixture teardown: '+directory);throw error;}
  }else if(possible){state();console.error('RETAINED: uncertain attach fixture; no parent cleanup attempted: '+directory);}
  else rmSync(directory,{recursive:true,force:true});
}
