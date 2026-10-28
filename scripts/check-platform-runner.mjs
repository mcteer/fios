import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,copyFileSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {createHash,randomUUID} from 'node:crypto';
import {fileURLToPath} from 'node:url';
if(process.argv.length!==3||process.argv[2]!=='--isolated')throw Error('Use --isolated');
const directory=mkdtempSync(join(tmpdir(),'fios-runner-'));
let image,container;
const workers=[],workerResults=[];
const jobID=randomUUID(),epoch=randomUUID();
let host=[];
const environment={PATH:process.env.PATH,HOME:'/var/empty',LANG:'C',DOCKER_CONFIG:'/var/empty',DOCKER_BUILDKIT:'0'};
function docker(args){const p=spawnSync('docker',[...host,...args],{encoding:'utf8',timeout:120000,maxBuffer:1<<20,env:environment});assert.equal(p.status,0,p.stderr);return p.stdout.trim();}
function frame(value){const body=Buffer.from(JSON.stringify(value));assert.ok(body.length<=65536);const header=Buffer.alloc(4);header.writeUInt32BE(body.length);return Buffer.concat([header,body]);}
try{
 const context=spawnSync('docker',['context','inspect','--format','{{.Endpoints.docker.Host}}'],{encoding:'utf8',timeout:10000,maxBuffer:8192});
 assert.equal(context.status,0,'Local runtime context unavailable');const socket=context.stdout.trim();
 assert.ok(socket.startsWith('unix:///'),'Fixture requires a local Unix runtime');host=['--host',socket];
 const requested=process.env.FIOS_PLATFORM_TEST_BASE_IMAGE??'fios:current';
 assert.ok(requested==='fios:current'||/^sha256:[a-f0-9]{64}$/.test(requested),'Fixture base must be an existing immutable ID');
 const base=docker(['image','inspect',requested,'--format','{{.Id}}']);assert.match(base,/^sha256:[a-f0-9]{64}$/);
 copyFileSync(new URL('../platform/studio/sandbox/runner.py',import.meta.url),join(directory,'runner.py'));
 writeFileSync(join(directory,'Dockerfile'),`FROM ${base}\nUSER 65532:65532\nWORKDIR /workspace\nCOPY runner.py /runner.py\nENTRYPOINT ["/opt/venv/bin/python","-I","-B","/runner.py"]\n`);
 image=docker(['build','--quiet','--pull=false','--network=none',directory]);assert.match(image,/^sha256:[a-f0-9]{64}$/);
 const create=()=>docker(['create','--name','fios-runner-'+randomUUID(),'--pull=never','--network=none','--read-only','--user=65532:65532','--cap-drop=ALL','--security-opt=no-new-privileges:true','--pids-limit=64','--memory=536870912','--memory-swap=536870912','--cpus=1','--tmpfs=/workspace:rw,nosuid,nodev,size=134217728,mode=0700,uid=65532,gid=65532','--tmpfs=/tmp:rw,noexec,nosuid,nodev,size=67108864,mode=1777','--log-driver=none','--interactive',image]);
 container=create();
 const source=readFileSync(new URL('../tests/fixtures/platform/sandbox-task.py',import.meta.url));
 const child=spawn('docker',[...host,'start','--attach','--interactive',container],{stdio:['pipe','pipe','pipe'],env:environment});
 let buffer=Buffer.alloc(0),events=[],errors=0,artifact;
 child.stdin.on('error',()=>child.kill('SIGKILL'));
 function model(request){
  const attempt=workers.length;assert.ok(attempt<4);
  const native=spawn(fileURLToPath(new URL('../.venv/bin/python',import.meta.url)),['-I','-B',fileURLToPath(new URL('../tests/fixtures/platform/mock-worker.py',import.meta.url))],
   {stdio:['pipe','pipe','pipe'],env:{PATH:process.env.PATH,LANG:'C',MLX_BASE_URL:'http://127.0.0.1:1/v1',FIOS_WEB_SEARCH:'off',PYDANTIC_AI_NO_BANNER:'1'}});
  workers.push(native);let bytes=Buffer.alloc(0),dispatched=false,usage=false,terminal=false,failure;
  const fail=()=>{failure='private_worker_fixture_failed';native.kill('SIGKILL');child.kill('SIGKILL');};
  workerResults.push(new Promise(resolve=>{native.on('error',fail);native.on('close',code=>resolve({code,failure,terminal}));}));
  native.stderr.on('data',fail);native.stdin.on('error',fail);
  native.stdout.on('data',block=>{try{
   bytes=Buffer.concat([bytes,block]);assert.ok(bytes.length<=524288);
   while(bytes.length>=4){const size=bytes.readUInt32BE();assert.ok(size>0&&size<=262144);if(bytes.length<size+4)break;
    const event=JSON.parse(bytes.subarray(4,size+4));bytes=bytes.subarray(size+4);
    assert.equal(event.v,1);assert.equal(event.job_id,jobID);assert.equal(terminal,false);
    if(event.type==='dispatched'){assert.equal(dispatched,false);assert.equal(event.attempt,attempt);dispatched=true;}
    else if(event.type==='delta'){assert.ok(dispatched&&typeof event.content==='string'&&event.content.length<=8192);child.stdin.write(frame({version:1,type:'model.delta',id:request.id,content:event.content}));}
    else if(event.type==='usage'){assert.equal(usage,false);assert.equal(event.attempt,attempt);assert.equal(event.posts,1);assert.equal(event.output_units,9);usage=true;}
    else if(event.type==='done'){assert.ok(dispatched&&usage);assert.equal(event.status,'complete');terminal=true;child.stdin.write(frame({version:1,type:'model.done',id:request.id,status:'complete'}));}
    else assert.equal(event.type,'activity');
   }
  }catch{fail();}});
  native.stdin.write(frame({v:1,type:'run',job_id:jobID,attempt,epoch,model:'fixture/model',
   endpoint_hash:createHash('sha256').update('http://127.0.0.1:1/v1').digest('hex'),expires_at:Date.now()+5000,
   context:[{role:'user',content:request.prompt}]}));
 }
 child.stderr.on('data',b=>{errors+=b.length;if(errors>8192)child.kill('SIGKILL');});
 const exit=new Promise((resolve,reject)=>{
  child.on('error',reject);child.on('close',code=>resolve(code));
  child.stdout.on('data',b=>{try{
   buffer=Buffer.concat([buffer,b]);assert.ok(buffer.length<=131072);
   while(buffer.length>=4){const n=buffer.readUInt32BE();assert.ok(n>0&&n<=65536);if(buffer.length<n+4)break;
    const event=JSON.parse(buffer.subarray(4,n+4));buffer=buffer.subarray(n+4);events.push(event);
    assert.ok(events.length<256);
    if(event.type==='model.request'){
     assert.ok(event.prompt==='fixture only','Unexpected fixture request');assert.equal(event.endpoint,undefined);
     model(event);
    }else if(event.type==='artifact.begin'){
     assert.equal(artifact,undefined);assert.ok(event.length<=16*1024*1024);artifact={...event,chunks:[],index:0};
    }else if(event.type==='artifact.chunk'){
     assert.equal(event.id,artifact.id);assert.equal(event.index,artifact.index++);const bytes=Buffer.from(event.data,'base64');assert.ok(bytes.length<=32768);artifact.chunks.push(bytes);
    }else if(event.type==='artifact.end'){
     assert.equal(event.id,artifact.id);const data=Buffer.concat(artifact.chunks);assert.equal(data.length,artifact.length);
     assert.equal(createHash('sha256').update(data).digest('hex'),artifact.sha256);assert.ok(data.toString()==='EXPLICIT_ARTIFACT_ONLY','Unexpected fixture artifact');
     child.stdin.write(frame({version:1,type:'artifact.saved',id:event.id,artifact_id:randomUUID()}));artifact=undefined;
    }
   }
  }catch(error){child.kill('SIGKILL');reject(error);}});
 });
 child.stdin.write(frame({version:1,type:'input.begin',length:source.length,sha256:createHash('sha256').update(source).digest('hex'),deadline:Date.now()+30000}));
 child.stdin.write(frame({version:1,type:'input.chunk',index:0,data:source.toString('base64')}));
 child.stdin.write(frame({version:1,type:'input.end'}));
 const timer=setTimeout(()=>child.kill('SIGKILL'),20000);
 try{assert.equal(await exit,0,JSON.stringify({codes:events.filter(e=>e.type==='error').map(e=>e.code),types:events.map(e=>e.type)}));}finally{clearTimeout(timer);child.stdin.destroy();}
 const output=events.filter(e=>e.type==='output').map(e=>Buffer.from(e.data,'base64').toString()).join('');
 for(const result of await Promise.all(workerResults)){assert.equal(result.code,0);assert.equal(result.failure,undefined);assert.equal(result.terminal,true);}
 assert.equal(workers.length,1);
 assert.ok(/SANDBOX_TASK_PASS/.test(output),'Task fixture marker missing');assert.ok(/service.force/.test(output),'Frame-looking output missing');assert.ok(!events.some(e=>e.type==='service.force'));assert.equal(events.at(-1).type,'done');assert.equal(events.at(-1).status,'complete');assert.equal(events.at(-1).exit_code,0);
 docker(['rm','--force',container]);container=undefined;
 const over=Buffer.alloc(4);over.writeUInt32BE(65537);
 const duplicate=Buffer.from('{"version":1,"version":1,"type":"input.begin"}');const dupeHeader=Buffer.alloc(4);dupeHeader.writeUInt32BE(duplicate.length);
 const bad=Buffer.from('print("MUST_NOT_RUN")\n');
 const badHash=Buffer.concat([frame({version:1,type:'input.begin',length:bad.length,sha256:'0'.repeat(64),deadline:Date.now()+30000}),frame({version:1,type:'input.chunk',index:0,data:bad.toString('base64')}),frame({version:1,type:'input.end'})]);
 for(const [input,expected] of [[over,'invalid_frame'],[Buffer.concat([dupeHeader,duplicate]),'invalid_frame'],[badHash,'input_hash']]){
  container=create();
  const failed=spawnSync('docker',[...host,'start','--attach','--interactive',container],{input,timeout:10000,maxBuffer:1<<20,env:environment});
  assert.notEqual(failed.signal,'SIGTERM','Malformed input hung runner');
  const output=failed.stdout??Buffer.alloc(0);assert.ok(output.length>=4);const size=output.readUInt32BE();
  const event=JSON.parse(output.subarray(4,4+size));assert.equal(event.type,'error');assert.equal(event.code,expected);assert.equal(output.length,size+4);
  assert.ok(!output.includes(Buffer.from('MUST_NOT_RUN')));
  docker(['rm','--force',container]);container=undefined;
 }
 console.log('PASS: isolated task → installed private Pydantic worker → mocked model → task; explicit artifacts and hostile frames; no live inference');
}finally{
 for(const worker of workers)if(worker.exitCode===null)worker.kill('SIGKILL');
 try{if(container)docker(['rm','--force',container]);}finally{try{if(image)docker(['image','rm',image]);}finally{rmSync(directory,{recursive:true,force:true});}}
}
