#!/usr/bin/env node
// Explicit one-shot local image producer, never a manager/app/PR authority.
// The output is an unapproved candidate; no runtime/native enrollment changes.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdirSync,writeFileSync,readFileSync,copyFileSync,chmodSync,lstatSync,realpathSync} from 'node:fs';
import {resolve,join,dirname} from 'node:path';
import {userInfo} from 'node:os';
import {randomUUID,createHash} from 'node:crypto';
import {readSandboxBaseReview,sandboxImageFile,validateSandboxImage,validateSandboxBase} from './lib/platform-sandbox-image.mjs';
import {capturePlatformSources,verifyPlatformSources} from './lib/platform-source.mjs';
const args=process.argv.slice(2),root=resolve(import.meta.dirname,'..');
const functionalOnly=args.at(-1)==='--functional-only';
if(functionalOnly)args.pop();
assert(process.platform==='darwin'&&process.getuid()!==0);
assert(args.length===6&&args[0]==='--review'&&args[2]==='--sha256'&&args[4]==='--output'&&args[1].startsWith('/')&&args[5].startsWith('/'));
const review=readSandboxBaseReview(args[1],args[3]),output=resolve(args[5]),parent=realpathSync.native(dirname(output)),parentInfo=lstatSync(parent);
assert(parentInfo.isDirectory()&&parentInfo.uid===process.getuid()&&(parentInfo.mode&0o7777)===0o700);
assert.equal(createHash('sha256').update(sandboxImageFile(join(root,'platform/studio/sandbox/Dockerfile'))).digest('hex'),review.dockerfile_sha256);
assert.equal(createHash('sha256').update(sandboxImageFile(join(root,'platform/studio/sandbox/runner.py'))).digest('hex'),review.runner_sha256);
const target=join(parent,output.split('/').at(-1));mkdirSync(target,{mode:0o700});
const sourceFiles=['platform/studio/sandbox/Dockerfile','platform/studio/sandbox/runner.py','scripts/package-platform-sandbox.mjs','scripts/lib/platform-sandbox-image.mjs','scripts/lib/platform-source.mjs'].map(p=>join(root,p));
const proof=capturePlatformSources(root,sourceFiles),hash=data=>createHash('sha256').update(data).digest('hex');
const socket=join(userInfo().homedir,'.orbstack/run/docker.sock'),docker=join(target,'docker'),nonce=randomUUID(),name='fios-image-probe-'+nonce;
let image,container,possible=false,finished=false;
function receipt(phase){writeFileSync(join(target,'build-state.json'),JSON.stringify({version:1,phase,name,nonce,image,container,review_sha256:args[3],activation:false},null,2)+'\n',{mode:0o600});}
const env={PATH:'/usr/bin:/bin',HOME:userInfo().homedir,LANG:'C',LC_ALL:'C',DOCKER_CONFIG:'/var/empty',DOCKER_CLI_HINTS:'false',DOCKER_BUILDKIT:'0'};
function command(program,argv,{input,timeout=10000}={}){
 const p=spawnSync(program,argv,{input,encoding:'utf8',timeout,maxBuffer:1<<20,env});
 if(p.error||p.status!==0)throw Error('Finite sandbox image operation failed; inspect retained build state');return p.stdout.trim();
}
async function attached(argv,input){
 return await new Promise(resolve=>{
  const child=spawn(docker,argv,{stdio:['pipe','pipe','pipe'],env});let stdout=[],stderr=[],out=0,err=0,failure,killTimer,stopping=false;
  const stop=()=>{if(stopping)return;stopping=true;child.kill('SIGTERM');killTimer=setTimeout(()=>child.kill('SIGKILL'),1000);};
  const timer=setTimeout(()=>{failure=Error('Probe attach deadline');stop();},15000);
  child.on('error',error=>{failure=error;});child.stdin.on('error',error=>{failure=error;stop();});
  child.stdout.on('data',b=>{out+=b.length;if(out>1<<20){failure=Error('Probe output bound');stop();}else stdout.push(b);});
  child.stderr.on('data',b=>{err+=b.length;if(err>1<<20){failure=Error('Probe error bound');stop();}else stderr.push(b);});
  child.on('close',code=>{clearTimeout(timer);clearTimeout(killTimer);child.stdin.destroy();resolve({error:failure,status:code,stdout:Buffer.concat(stdout),stderr:Buffer.concat(stderr)});});
  child.stdin.write(input); // Keep owner control alive until the child is reaped.
 });
}
const runtime=(argv,options)=>command(docker,['--host','unix://'+socket,...argv],options);
const inspect=id=>JSON.parse(runtime(['inspect','--type=container',id]))[0];
function owned(){const value=inspect(container);assert.equal(value.Id,container);assert.equal(value.Name,'/'+name);assert.equal(value.Image,image);assert.equal(value.Config.Labels?.['lab.fios.image-probe'],nonce);return value;}
function frame(value){const body=Buffer.from(JSON.stringify(value));assert(body.length<=65536);const header=Buffer.alloc(4);header.writeUInt32BE(body.length);return Buffer.concat([header,body]);}
try{
 const installed=realpathSync.native('/Applications/OrbStack.app/Contents/MacOS/xbin/docker-tools');const cli=sandboxImageFile(installed,512<<20);assert.equal(hash(cli),review.docker_cli_sha256);
 writeFileSync(docker,cli,{mode:0o700});assert.equal(hash(sandboxImageFile(docker,512<<20)),review.docker_cli_sha256);
 assert(lstatSync(socket).isSocket(),'Existing local OrbStack socket required');
 const base=JSON.parse(runtime(['image','inspect',review.base_image]))[0];validateSandboxBase(base,review.base_image);
 const context=join(target,'context');mkdirSync(context,{mode:0o700});
 for(const file of ['Dockerfile','runner.py']){copyFileSync(join(root,'platform/studio/sandbox',file),join(context,file));chmodSync(join(context,file),0o644);}
 writeFileSync(join(target,'base-review.json'),sandboxImageFile(args[1],4096),{mode:0o600});
 receipt('before-image-build');possible=true;
 image=runtime(['build','--quiet','--pull=false','--network=none','--label','lab.fios.sandbox.inputs='+proof.digest,'--label','lab.fios.sandbox.review='+args[3],'--build-arg','APPROVED_BASE='+review.base_image,context],{timeout:120000});assert.match(image,/^sha256:[a-f0-9]{64}$/);
 const imageInfo=JSON.parse(runtime(['image','inspect',image]))[0];validateSandboxImage(imageInfo,image);
 const probe=Buffer.from(functionalOnly ? `import os,sys,ssl,ctypes,json,importlib.util\nassert sys.version_info[:3]==(3,11,17) and os.uname().machine=='aarch64' and os.getuid()==65532\nassert importlib.util.find_spec('fios_agent') is None\nassert json.loads(json.dumps({'sum':sum(range(100))}))['sum']==4950\nprint('SANDBOX_IMAGE_PROBE_PASS')\n` : `import os,sys,ssl,ctypes,hashlib\nassert sys.version_info[:3]==(3,11,17) and os.uname().machine=='aarch64' and os.getuid()==65532\nassert not os.path.exists('/app') and not os.path.exists('/bin/sh') and not os.path.exists('/usr/bin/node')\nassert os.access('/bin/cat',os.X_OK)\nassert not os.path.exists('/var/run/docker.sock') and not os.path.exists('/run/docker.sock')\nassert hashlib.sha256(open('/runner.py','rb').read()).hexdigest()==${JSON.stringify(hash(readFileSync(join(context,'runner.py'))))}\ntry:\n fd=os.open('/proc/1/fd/0',os.O_WRONLY|os.O_NONBLOCK)\nexcept (PermissionError,FileNotFoundError):\n pass\nelse:\n os.close(fd);raise AssertionError('runner_control_descriptor_exposed')\nprint('SANDBOX_IMAGE_PROBE_PASS')\n`);
 writeFileSync(join(target,'probe.py'),probe,{mode:0o600});receipt('before-probe-create');
 container=runtime(['create','--name',name,'--pull=never','--network=none','--read-only','--user=65532:65532','--cap-drop=ALL','--security-opt=no-new-privileges:true','--pids-limit=64','--memory=536870912','--memory-swap=536870912','--cpus=1','--tmpfs=/workspace:rw,nosuid,nodev,size=134217728,mode=0700,uid=65532,gid=65532','--tmpfs=/tmp:rw,noexec,nosuid,nodev,size=67108864,mode=1777','--log-driver=none','--label','lab.fios.image-probe='+nonce,'--interactive',image]);assert.match(container,/^[a-f0-9]{64}$/);
 owned();receipt('before-probe-start');
 const input=Buffer.concat([frame({version:1,type:'input.begin',length:probe.length,sha256:hash(probe),deadline:Date.now()+10000}),frame({version:1,type:'input.chunk',index:0,data:probe.toString('base64')}),frame({version:1,type:'input.end'})]);
 // Raw framed bytes must not pass through UTF-8 trimming/decoding.
 const p=await attached(['--host','unix://'+socket,'start','--attach','--interactive',container],input);
 writeFileSync(join(target,'probe.stdout'),p.stdout??Buffer.alloc(0),{mode:0o600});writeFileSync(join(target,'probe.stderr'),p.stderr??Buffer.alloc(0),{mode:0o600});
 assert.equal(p.error,undefined);assert.equal(p.status,0);assert.equal(p.stderr.length,0);
 const events=[];let offset=0;
 while(offset<p.stdout.length){assert(offset+4<=p.stdout.length);const size=p.stdout.readUInt32BE(offset);offset+=4;assert(size>0&&size<=65536&&offset+size<=p.stdout.length);events.push(JSON.parse(p.stdout.subarray(offset,offset+size)));offset+=size;}
 assert(events.every(e=>e.version===1&&['output','done'].includes(e.type)));
 assert.equal(events.at(-1)?.type,'done');assert.equal(events.at(-1)?.status,'complete');assert.equal(events.at(-1)?.exit_code,0);
 assert.equal(events.filter(e=>e.type==='output').map(e=>Buffer.from(e.data,'base64').toString()).join(''),'SANDBOX_IMAGE_PROBE_PASS\n');
 assert.equal(owned().State.Running,false);receipt('before-probe-remove');runtime(['rm',container]);assert.equal(runtime(['container','ls','--all','--no-trunc','--filter','id='+container,'--format','{{.ID}}']),'');
 verifyPlatformSources(proof,root,sourceFiles);assert.equal(readSandboxBaseReview(args[1],args[3]).base_image,review.base_image);validateSandboxImage(JSON.parse(runtime(['image','inspect',image]))[0],image);
 const candidate={version:1,purpose:'sandbox_image_candidate',image,base_image:review.base_image,base_review_sha256:args[3],base_provenance_sha256:review.provenance_sha256,source_inputs_sha256:proof.digest,runner_sha256:hash(readFileSync(join(context,'runner.py'))),dockerfile_sha256:hash(readFileSync(join(context,'Dockerfile'))),python_version:'3.11.17',platform:'linux/arm64',probe:functionalOnly?'functional_stdlib_no_model_task':'hardened_no_model_task',approved:false,activation:false};
 const bytes=Buffer.from(JSON.stringify(candidate,null,2)+'\n');writeFileSync(join(target,'candidate.json'),bytes,{mode:0o600});receipt('candidate-ready');finished=true;
 console.log(JSON.stringify({candidate_sha256:hash(bytes),image,approved:false,activation:false}));
}catch(error){receipt('retained-after-failure');throw error;}
finally{if(!finished)console.error(possible?'RETAINED: uncertain image/container candidate; no parent cleanup attempted: '+target:'RETAINED: image review/preflight refused before runtime effects: '+target);}
