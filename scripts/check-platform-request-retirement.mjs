#!/usr/bin/env node
// Actual source tracker -> authenticated Unix transport -> Swift client/journal.
// All work is CPU metadata. No MLX engine/model, device, installed or terminal API.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,copyFileSync,readFileSync,writeFileSync,readdirSync,chmodSync} from 'node:fs';
import {createHash,randomUUID} from 'node:crypto';
import path from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
const args=process.argv.slice(2),root=path.resolve(import.meta.dirname,'..');
assert(process.platform==='darwin'&&process.arch==='arm64'&&process.getuid()>0);
assert(args.length===3&&args[0]==='--isolated'&&args[1]==='--zig'&&path.isAbsolute(args[2]));
const zig=args[2],sha=p=>createHash('sha256').update(readFileSync(p)).digest('hex');
assert.equal(sha(zig),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
const directory=mkdtempSync('/private/tmp/f9-retire-');chmodSync(directory,0o700);
const core='platform/studio/Sources/StudioCore',native='platform/studio/native';
const files=[...readdirSync(path.join(root,core)).filter(n=>n.endsWith('.swift')).sort().map(n=>core+'/'+n),
 ...['request_ownership.zig','device_owner.zig','control_protocol.zig','control_transport.zig','request_retirement_bridge.zig.fixture'].map(n=>native+'/'+n),
 'platform/studio/Sources/CSQLite/shim.h','platform/studio/Sources/CSQLite/module.modulemap',
 'platform/studio/Tests/StudioCoreTests/NativeRetirementClient.swift.fixture','scripts/check-platform-request-retirement.mjs'];
const capture=()=>Object.fromEntries(files.map(file=>[file,sha(path.join(root,file))])),inputs=capture(),records=[];
const environment={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C'};
function run(name,program,argv,timeout=180000,env=environment){
 const r=spawnSync(program,argv,{env,encoding:'utf8',timeout,maxBuffer:2<<20});
 writeFileSync(path.join(directory,name+'.log'),(r.stdout??'')+(r.stderr??''),{mode:0o600});
 records.push({name,status:r.status,signal:r.signal,log_sha256:sha(path.join(directory,name+'.log'))});
 assert(!r.error&&r.status===0,name+' failed; retain '+directory);return r.stdout.trim();
}
for(const file of files.filter(n=>n.startsWith(native+'/')))copyFileSync(path.join(root,file),path.join(directory,path.basename(file)));
const entry=path.join(directory,'bridge.zig');copyFileSync(path.join(root,native+'/request_retirement_bridge.zig.fixture'),entry);
const bridge=path.join(directory,'bridge'),client=path.join(directory,'client'),swift=path.join(directory,'Client.swift');
copyFileSync(path.join(root,'platform/studio/Tests/StudioCoreTests/NativeRetirementClient.swift.fixture'),swift);
run('zig-build',zig,['build-exe',entry,'-lc','-O','ReleaseSafe','-femit-bin='+bridge]);
run('swift-build','/usr/bin/swiftc',['-swift-version','6','-warnings-as-errors','-j2','-I',path.join(root,'platform/studio/Sources/CSQLite'),
 ...files.filter(n=>n.startsWith(core+'/')).map(n=>path.join(root,n)),swift,'-o',client]);
const state=path.join(directory,'state'),socket=path.join(directory,'.fios-native-control/control.sock'),job=randomUUID();
const prefix=[state,String(process.pid),bridge,socket,job];
const correlation=run('correlation',client,[...prefix,'correlation'],8000);assert.match(correlation,/^[a-f0-9]{64}$/);
const policy='(version 1)(allow default)(deny network*)(allow network* (local unix-socket) (remote unix-socket))';
const child=spawn('/usr/bin/sandbox-exec',['-p',policy,bridge],{cwd:directory,env:{...environment,FIOS_NATIVE_CONTROL:'isolated-source-fixture',FIOS_TEST_CORRELATION:correlation},stdio:['pipe','pipe','pipe']});
let output='',diagnostics='',failure;child.once('error',e=>{failure=e});child.stdin.on('error',e=>{failure=e});
child.stdout.on('data',b=>{output+=b.toString();if(output.length>8192)failure=Error('Source output bound')});
child.stderr.on('data',b=>{diagnostics+=b.toString();if(diagnostics.length>8192)failure=Error('Source diagnostics bound')});
const exited=()=>child.exitCode!==null||child.signalCode!==null,deadline=performance.now()+30000;
async function until(test,limit=deadline){while(performance.now()<limit){if(failure)throw failure;if(test())return;assert(!exited(),'Source exited early');await delay(10)}throw Error('Finite source deadline')}
function observe(step){assert(performance.now()<deadline);run(step,'/usr/bin/sandbox-exec',['-p',policy,client,state,String(child.pid),bridge,socket,job,step],8000)}
try {
 await until(()=>output==='ready\n');observe('initial');
 for(const [index,command,step]of [[1,'r','retained'],[2,'d','retired'],[3,'f','fenced']]){
  child.stdin.write(command);await until(()=>output==='ready\n'+'ok\n'.repeat(index));observe(step);
 }
 child.stdin.end('q');await until(exited);assert.equal(child.exitCode,0);
 assert.deepEqual(capture(),inputs);assert.equal(sha(zig),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
 const receipt={scope:'actual_local_reference_retirement_Unix_Swift_journal_not_native_terminal_authority',inputs,records,
  source_sha256:sha(bridge),client_sha256:sha(client),stages:4,inference_claims_retained:1,models:0,inference:false,
  device_work:false,native_authority:false,installed:false,activation:false,inputs_unchanged:true};
 writeFileSync(path.join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});
 console.log(JSON.stringify({directory,receipt_sha256:sha(path.join(directory,'receipt.json')),stages:4,native_authority:false}));
} finally {
 child.stdin.end();const end=performance.now()+3000;while(!exited()&&performance.now()<end)await delay(10);
 writeFileSync(path.join(directory,'source.log'),output+diagnostics,{mode:0o600});
 if(!exited()){child.unref();child.stdout.destroy();child.stderr.destroy();throw Error('Source local exit unknown; retained '+directory)}
}
