// Ordinary workspace writes using actual Core-generated container arguments.
// No exhaustion, network probes, model requests, image pulls or service actions.
import assert from 'node:assert/strict';
import {mkdtempSync,readdirSync,readFileSync,writeFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {homedir} from 'node:os';
import {spawn,spawnSync} from 'node:child_process';
import {createHash,randomUUID,randomBytes} from 'node:crypto';
import {validateSandboxImage} from './lib/platform-sandbox-image.mjs';

const args=process.argv.slice(2);
assert.equal(args.length,3,'Use --isolated --image EXISTING_IMMUTABLE_ID');
assert.equal(args[0],'--isolated');assert.equal(args[1],'--image');assert.match(args[2],/^sha256:[a-f0-9]{64}$/);
const image=args[2],root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/private/tmp/fios-009-workspace-runtime-');
const core=join(root,'platform/studio/Sources/StudioCore'),entry=join(directory,'WorkspaceArguments.swift'),binary=join(directory,'workspace-arguments');
const sources=readdirSync(core).filter(name=>name.endsWith('.swift')).sort().map(name=>join(core,name));
const sourceDigest=()=>{const hash=createHash('sha256');for(const path of sources)hash.update(path.slice(root.length)).update('\0').update(readFileSync(path));return hash.digest('hex')};
const sourceSHA=sourceDigest();
writeFileSync(entry,`import Foundation
@main struct WorkspaceArguments {
 static func main() throws {
  let a=CommandLine.arguments
  let config=try SandboxConfiguration(job:a[1],nonce:a[2],image:a[3],memory:512<<20,cpus:1,workspace:UInt64(a[4])!)
  FileHandle.standardOutput.write(try JSONEncoder().encode(config.createArguments))
 }
}
`,{mode:0o600});
function run(command,args,timeout=10000,env=process.env,input){
 const result=spawnSync(command,args,{encoding:'utf8',timeout,maxBuffer:1<<20,env,input});
 assert.equal(result.status,0,result.stderr||result.error?.message||'Workspace fixture subprocess failed');return result.stdout.trim();
}
run('swiftc',['-swift-version','6','-warnings-as-errors','-I',join(root,'platform/studio/Sources/CSQLite'),...sources,entry,'-o',binary],180000);
assert.equal(sourceDigest(),sourceSHA,'Core source changed during compilation');
const environment={PATH:process.env.PATH,HOME:'/var/empty',LANG:'C',DOCKER_CONFIG:'/var/empty'};
const host=['--host','unix://'+join(homedir(),'.orbstack/run/docker.sock')];
const docker=(arguments_,input)=>run('docker',[...host,...arguments_],10000,environment,input);
const dockerFrames=(arguments_,input)=>new Promise((resolve,reject)=>{
 const child=spawn('docker',[...host,...arguments_],{env:environment,stdio:['pipe','pipe','pipe']});
 let output=Buffer.alloc(0),errors=0;
 const timer=setTimeout(()=>child.kill('SIGTERM'),10000);
 child.on('error',reject);child.stdin.on('error',reject);
 child.stderr.on('data',bytes=>{errors+=bytes.length;if(errors>8192)child.kill('SIGTERM')});
 child.stdout.on('data',bytes=>{output=Buffer.concat([output,bytes]);if(output.length>1<<20)child.kill('SIGTERM')});
 child.on('close',code=>{clearTimeout(timer);child.stdin.destroy();if(code===0)resolve(output);else reject(Error('Own task runner exit '+code))});
 // Keep the control pipe open until the runner reports its ordinary exit.
 child.stdin.write(input);
});
function frame(value){const bytes=Buffer.from(JSON.stringify(value)),header=Buffer.alloc(4);header.writeUInt32BE(bytes.length);return Buffer.concat([header,bytes])}
validateSandboxImage(JSON.parse(docker(['image','inspect',image]))[0],image);
const records=[];
const persist=()=>writeFileSync(join(directory,'receipt.json'),JSON.stringify({version:1,image,core_source_sha256:sourceSHA,records,approved:false,activation:false,model_posts:0},null,2)+'\n',{mode:0o600});
for(const workspace of [128<<20,256<<20]){
 const record={job:randomUUID(),nonce:randomBytes(32).toString('hex'),workspace,id:null,removed:false};records.push(record);persist();
 const generated=JSON.parse(run(binary,[record.job,record.nonce,image,String(workspace)]));
 const program=Buffer.from("import os; p='/workspace/ordinary.txt'; open(p,'w').write('ordinary workspace'); assert open(p).read()=='ordinary workspace'; s=os.statvfs('/workspace'); print(s.f_blocks*s.f_frsize)\n");
 // Record exact deterministic ownership before issuing create; uncertainty retains it.
 record.name='fios-sandbox-'+record.job;persist();
 try{
  record.id=docker(generated);assert.match(record.id,/^[a-f0-9]{64}$/);persist();
  const inspect=()=>JSON.parse(docker(['inspect','--type=container',record.id]))[0];
  const before=inspect();
  assert.equal(before.Id,record.id);assert.equal(before.Name,'/'+record.name);assert.equal(before.Image,image);
  assert.equal(before.Config.Labels['fios.platform.job'],record.job);assert.equal(before.Config.Labels['fios.platform.nonce'],record.nonce);
  assert.ok(before.HostConfig.Tmpfs['/workspace'].includes('size='+workspace));
  const input=Buffer.concat([frame({version:1,type:'input.begin',length:program.length,sha256:createHash('sha256').update(program).digest('hex'),deadline:Date.now()+8000}),
    frame({version:1,type:'input.chunk',index:0,data:program.toString('base64')}),frame({version:1,type:'input.end'})]);
  let bytes=await dockerFrames(['start','--attach','--interactive',record.id],input);
  const events=[];
  while(bytes.length){assert.ok(bytes.length>=4);const size=bytes.readUInt32BE();assert.ok(size>0&&size<=65536&&bytes.length>=size+4);events.push(JSON.parse(bytes.subarray(4,size+4)));bytes=bytes.subarray(size+4)}
  const output=events.filter(event=>event.type==='output').map(event=>Buffer.from(event.data,'base64').toString()).join('');
  assert.equal(events.at(-1)?.type,'done');assert.equal(events.at(-1)?.status,'complete');assert.equal(events.at(-1)?.exit_code,0);
  assert.equal(Number(output),workspace);
  const after=inspect();assert.equal(after.State.Running,false);assert.equal(after.State.ExitCode,0);
  assert.equal(after.Id,record.id);assert.equal(after.Name,'/'+record.name);assert.equal(after.Image,image);
  assert.equal(after.Config.Labels['fios.platform.nonce'],record.nonce);
  docker(['rm',record.id]);
  assert.equal(docker(['container','ls','--all','--no-trunc','--filter','id='+record.id,'--format','{{.ID}}']),'');
  record.removed=true;record.observed_workspace_bytes=Number(output);persist();
 }catch(error){persist();console.error('RETAINED: own workspace fixture state '+directory);throw error}
}
console.log(JSON.stringify({ok:true,workspaces:records.map(r=>r.observed_workspace_bytes),core_source_sha256:sourceSHA,actual_core_arguments:true,model_posts:0,activation:false,review_directory:directory}));
