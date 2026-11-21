#!/usr/bin/env node
// Exact CPU claim withdrawal only. No native object, lease, not-sent/terminal
// proof, transport, inference or installation authority.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,mkdtempSync,lstatSync,realpathSync} from 'node:fs';
import {resolve,join,dirname,relative,isAbsolute} from 'node:path';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'..'),args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.arch==='arm64'&&process.getuid()>0);
assert(args.length===5&&args[0]==='--isolated'&&args[1]==='--source'&&args[3]==='--zig');
const [source,zig]=[args[2],args[4]].map(p=>{assert(isAbsolute(p)&&p.startsWith('/private/tmp/')&&realpathSync(p)===p);return p;});
const hash=data=>createHash('sha256').update(data).digest('hex');
const bytes=(p,max=64<<20)=>{const s=lstatSync(p);assert(s.isFile()&&!s.isSymbolicLink()&&s.nlink===1&&s.uid===process.getuid()&&(s.mode&0o022)===0&&s.size>0&&s.size<max);return readFileSync(p);};
assert.equal(hash(bytes(zig,512<<20)),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
const file='src/fios/request_ownership.zig',parentSHA='019708f72c3621b1a9a16d9cd9323cea1ac258f9fdc4a898cd17f14a7f580eac';
const directory=mkdtempSync('/private/tmp/fios-009-preparation-withdrawal-check-'),review=join(directory,'parent'),unit=join(directory,'unit');
for(const p of [join(review,'src/fios'),join(unit,'fios')])mkdirSync(p,{recursive:true,mode:0o700});
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1'};
const run=(p,a,cwd=directory)=>execFileSync(p,a,{cwd,env,encoding:'utf8',timeout:30000,maxBuffer:4<<20});
assert.equal(run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,'rev-parse','HEAD']).trim(),'3736ed55f81c6cf0966a0f0dc7265e783655d244');
const patchPath=join(root,'platform/studio/native/mlx-serve-preparation-withdrawal.patch'),fixturePath=join(root,'platform/studio/native/preparation_withdrawal_test.zig.fixture'),patch=bytes(patchPath),fixture=bytes(fixturePath),candidate=bytes(join(source,file));
assert.deepEqual([...patch.toString().matchAll(/^\+\+\+ b\/([^\r\n]+)$/gm)].map(m=>m[1]),[file]);
run('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',zig,'ast-check',join(source,file)]);
writeFileSync(join(review,file),candidate,{mode:0o600});const patchCopy=join(directory,'source.patch');writeFileSync(patchCopy,patch,{mode:0o600});
run('/usr/bin/git',['apply','--reverse',patchCopy],review);const parent=bytes(join(review,file));assert.equal(hash(parent),parentSHA);
run('/usr/bin/git',['apply',patchCopy],review);assert.equal(hash(bytes(join(review,file))),hash(candidate));
const declared={},pending=['fios/request_ownership.zig'],copied=new Set();
while(pending.length){const name=pending.pop();if(copied.has(name))continue;copied.add(name);const p=join(source,'src',name),data=bytes(p);declared['src/'+name]=hash(data);const out=join(unit,name);mkdirSync(dirname(out),{recursive:true,mode:0o700});writeFileSync(out,data,{mode:0o600});for(const m of data.toString().matchAll(/@import\("([^"\n]+\.zig)"\)/g)){const p=resolve(dirname(join(source,'src',name)),m[1]),n=relative(join(source,'src'),p);assert(!n.startsWith('..')&&!isAbsolute(n));try{lstatSync(p);pending.push(n);}catch(error){if(error.code!=='ENOENT')throw error;}}}
writeFileSync(join(unit,'options.zig'),'pub const fios_source_sdk=false;\npub const fios_source_ane=false;\npub const fios_source_ds4=false;\npub const llama_engine=false;\npub const mlx_stream=false;\n',{mode:0o600});
const names=[...fixture.toString().matchAll(/^test "(preparation withdrawal[^"\n]+)"/gm)].map(m=>m[1]);assert.equal(names.length,20);
const controls=names.filter(n=>n.includes(' control '));assert.equal(controls.length,4);
const receipt={version:1,scope:'actual_complete_tracker_single_CPU_metadata_withdrawal_not_inference_or_native_proof',directory,source,parent_projection:{[file]:parentSHA},declared_inputs:declared,patch_sha256:hash(patch),fixture_sha256:hash(fixture),runner_sha256:hash(bytes(import.meta.filename)),fixture_primary_guard:true,serving_primary_guard:false,results:[],models:0,inference:false,native_authority:false,installed:false};
const save=()=>writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});save();
writeFileSync(join(unit,'main.zig'),fixture,{mode:0o600});
for(const mode of ['Debug','ReleaseSafe'])for(const baseline of [true,false]){
 writeFileSync(join(unit,'fios/request_ownership.zig'),baseline?parent:candidate,{mode:0o600});
 for(const name of baseline?[names[0],...controls]:names){
  const argv=['-p','(version 1)(allow default)(deny network*)',zig,'test','--test-filter',name,'-O'+mode,'--dep','build_options','-Mroot='+join(unit,'main.zig'),'-Mbuild_options='+join(unit,'options.zig'),'-lc'];
  const r=spawnSync('/usr/bin/sandbox-exec',argv,{cwd:directory,env,encoding:'utf8',timeout:120000,maxBuffer:4<<20}),log=(r.stdout||'')+(r.stderr||'');writeFileSync(join(directory,'case-'+receipt.results.length+'.log'),log,{mode:0o600});
  const missing=baseline&&name===names[0],expected=missing?r.status===1&&log.includes('PREPARATION_WITHDRAWAL_API_ABSENT')&&!log.includes('panic:'):r.status===0&&/^All [12] tests passed\./m.test(log);
  receipt.results.push({mode,baseline,name,scope:missing?'original_interface_absence_not_behavioral_failure':'CPU_functional_case',status:r.status,signal:r.signal,expected,log_sha256:hash(Buffer.from(log))});save();assert(expected,'Retain failed preparation withdrawal check '+directory);
 }
}
receipt.unchanged=Object.entries(declared).every(([n,h])=>hash(bytes(join(source,n)))===h)&&hash(bytes(patchPath))===receipt.patch_sha256&&hash(bytes(fixturePath))===receipt.fixture_sha256&&hash(bytes(import.meta.filename))===receipt.runner_sha256;save();assert(receipt.unchanged);
console.log(JSON.stringify({directory,receipt_sha256:hash(bytes(join(directory,'receipt.json'))),original_interface_absence_cases:2,parent_controls:8,candidate_cases:40,models:0,native_authority:false}));
