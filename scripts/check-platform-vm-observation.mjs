#!/usr/bin/env node
// Finite ordinary local telemetry integration. One owned512MiB/1CPU
// network-none container with a fixed20s metadata-only lifetime; no app, model,
// root policy, daemon lifecycle, host mount, image pull or installed action.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,copyFileSync,chmodSync,readdirSync,realpathSync} from 'node:fs';
import {homedir} from 'node:os';
import {join,resolve} from 'node:path';
import {createHash,randomUUID,randomBytes} from 'node:crypto';
assert.deepEqual(process.argv.slice(2),['--isolated']);assert.equal(process.platform,'darwin');assert.notEqual(process.getuid(),0);
const root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/private/tmp/fios-009-vm-observation-live-');
const owner=randomUUID(),job=randomUUID(),nonce=randomBytes(32).toString('hex'),name='fios-sandbox-'+job;
const docker=join(directory,'docker'),socket=join(homedir(),'.orbstack/run/docker.sock');
const env={PATH:'/usr/bin:/bin',HOME:homedir(),LANG:'C',LC_ALL:'C',DOCKER_CONFIG:'/var/empty',DOCKER_CLI_HINTS:'false',DOCKER_BUILDKIT:'0'};
const hash=file=>createHash('sha256').update(readFileSync(file)).digest('hex');
let image,id,passed=false,createIssued=false;
function record(phase){writeFileSync(join(directory,'state.json'),JSON.stringify({phase,owner,job,nonce,name,image,id,createIssued,installed:false,native_authority:false},null,2)+'\n',{mode:0o600});}
function command(program,args,{timeout=10000}={}) {
 const result=spawnSync(program,args,{cwd:root,env,encoding:'utf8',timeout,maxBuffer:1<<20});
 if(result.status!==0){writeFileSync(join(directory,'failure.stderr'),result.stderr??'',{mode:0o600});throw Error('Finite VM observation command failed; retain original fixture state');}
 return result.stdout.trim();
}
const runtime=(args,options)=>command(docker,['--host','unix://'+socket,...args],options);
function owned(){
 const values=JSON.parse(runtime(['inspect','--type=container',id]));assert.equal(values.length,1);
 const value=values[0];assert.equal(value.Id,id);assert.equal(value.Name,'/'+name);assert.equal(value.Image,image);
 assert.equal(value.Config.Labels['fios.platform.job'],job);assert.equal(value.Config.Labels['fios.platform.nonce'],nonce);return value;
}
try {
 const installed=realpathSync('/Applications/OrbStack.app/Contents/MacOS/xbin/docker-tools');
 copyFileSync(installed,docker);chmodSync(docker,0o700);
 const orbctl=realpathSync('/Applications/OrbStack.app/Contents/MacOS/scli.app/Contents/MacOS/scli');
 assert.equal(command(orbctl,['status']),'Running','Existing running local runtime required; no start fallback');
 const base=runtime(['image','inspect','fios:current','--format','{{.Id}}']);assert.match(base,/^sha256:[a-f0-9]{64}$/);
 const source=join(directory,'ReadOnlyVMResourceLive.swift'),binary=join(directory,'collector');
 copyFileSync(join(root,'platform/studio/Tests/StudioCoreTests/ReadOnlyVMResourceLive.swift.fixture'),source);
 const core=join(root,'platform/studio/Sources/StudioCore');
 command('/usr/bin/swiftc',['-swift-version','6','-warnings-as-errors','-j2','-I',join(root,'platform/studio/Sources/CSQLite'),
  ...readdirSync(core).filter(n=>n.endsWith('.swift')).sort().map(n=>join(core,n)),source,'-o',binary],{timeout:180000});
 // All executable/runtime bytes come from one existing immutable base. The
 // image changes only fixed metadata, not app data or application startup.
 const context=join(directory,'context');mkdirSync(context,{mode:0o700});
 writeFileSync(join(context,'Dockerfile'),`FROM ${base}\nUSER 65532:65532\nWORKDIR /workspace\nENTRYPOINT ["/opt/venv/bin/python","-I","-S","-B","-c","import time; time.sleep(20)"]\n`,{mode:0o600});
 image=runtime(['build','--quiet','--pull=false','--network=none','--label','lab.fios.vm-observation.owner='+owner,context],{timeout:120000});
 assert.match(image,/^sha256:[a-f0-9]{64}$/);record('before-create');
 createIssued=true;record('create-intent');
 id=runtime(['create','--pull=never','--name',name,'--network=none','--read-only','--user=65532:65532','--cap-drop=ALL',
  '--security-opt=no-new-privileges:true','--pids-limit=64','--memory=536870912','--memory-swap=536870912','--cpus=1',
  '--tmpfs=/workspace:rw,nosuid,nodev,size=134217728,mode=0700,uid=65532,gid=65532',
  '--tmpfs=/tmp:rw,noexec,nosuid,nodev,size=67108864,mode=1777','--log-driver=none',
  '--label','fios.platform.job='+job,'--label','fios.platform.nonce='+nonce,'--interactive',image]);
 assert.match(id,/^[a-f0-9]{64}$/);record('before-start');owned();runtime(['start',id]);
 const result=JSON.parse(command(binary,[docker,hash(docker),socket,orbctl,hash(orbctl),image,job,nonce,id],{timeout:15000}));
 assert.equal(result.ok,true);assert.equal(result.samples,3);assert.equal(result.native_authority,false);assert.equal(result.model_requests,0);
 const end=performance.now()+25000;
 while(owned().State.Running&&performance.now()<end)await new Promise(r=>setTimeout(r,100));
 assert.equal(owned().State.Running,false,'Finite original fixture still running; retain it');
 runtime(['rm',id]);
 assert.equal(runtime(['container','ls','--all','--no-trunc','--filter','id='+id,'--format','{{.ID}}']),'');
 const metadata=JSON.parse(runtime(['image','inspect',image]))[0];assert.equal(metadata.Id,image);
 assert.equal(metadata.Config.Labels['lab.fios.vm-observation.owner'],owner);runtime(['image','rm',image]);
 passed=true;record('verified-owned-removal');
 const receipt={...result,base_image:base,fixture_sha256:hash(source),docker_sha256:hash(docker),orbctl_sha256:hash(orbctl),
  verified_owned_container_removal:true,fixture_image_removed:true,review_directory:directory};
 writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});console.log(JSON.stringify(receipt));
} finally {
 // Failure is not removal/absence proof. The fixed container self-exits; do
 // not force-remove, retry create or erase diagnostic/ownership metadata.
 if(!passed){record('incomplete-retained');console.error('VM observation fixture retained for review: '+directory);}
}
