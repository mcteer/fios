#!/usr/bin/env node
// Configured-mode negative evidence only. No RDMA call, model, service or
// positive coverage/admission test. Baseline gets only the candidate marker
// module to isolate the missing composition in the genuine old server getter.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,mkdtempSync,lstatSync,realpathSync,existsSync} from 'node:fs';
import {resolve,join,dirname,relative,isAbsolute} from 'node:path';
import {createHash} from 'node:crypto';
const root=resolve(import.meta.dirname,'..'),args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.arch==='arm64'&&process.getuid()>0);
assert(args.length===5&&args[0]==='--isolated'&&args[1]==='--source'&&args[3]==='--zig');
const [source,zig]=[args[2],args[4]].map(p=>{assert(isAbsolute(p)&&p.startsWith('/private/tmp/')&&realpathSync(p)===p);return p;});
const hash=data=>createHash('sha256').update(data).digest('hex');
const bytes=(p,max=64<<20)=>{const s=lstatSync(p);assert(s.isFile()&&!s.isSymbolicLink()&&s.nlink===1&&s.uid===process.getuid()&&(s.mode&0o022)===0&&s.size>0&&s.size<max);return readFileSync(p);};
assert.equal(hash(bytes(zig,512<<20)),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
const parents={'src/main.zig':'42c0152f238a0c6c1ecb4c0bbb7f531d254506c898e1352e3c8c5a5b1611ae0f','src/host/http/server.zig':'58433593e4321ea9a3d49b6ba02774d8f2196a9888c9c5ccf7119d2ac2b0d97c'};
const marker='src/fios/current_distributed_mode_uncertainty.zig',names=[...Object.keys(parents),marker];
const directory=mkdtempSync('/private/tmp/fios-009-distributed-mode-check-'),review=join(directory,'parent'),unit=join(directory,'unit');
for(const p of [review,unit])mkdirSync(p,{mode:0o700});
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1'};
const run=(p,a,cwd=directory)=>execFileSync(p,a,{cwd,env,encoding:'utf8',timeout:30000,maxBuffer:4<<20});
assert.equal(run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,'rev-parse','HEAD']).trim(),'3736ed55f81c6cf0966a0f0dc7265e783655d244');
const patchPath=join(root,'platform/studio/native/mlx-serve-current-distributed-mode-fence.patch'),patch=bytes(patchPath);
assert.deepEqual([...patch.toString().matchAll(/^\+\+\+ b\/([^\r\n]+)$/gm)].map(m=>m[1]),names);
const candidates={},baseline={};
for(const name of names){const data=bytes(join(source,name));candidates[name]=data;const p=join(review,name);mkdirSync(dirname(p),{recursive:true,mode:0o700});writeFileSync(p,data,{mode:0o600});run('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',zig,'ast-check',join(source,name)]);}
const patchCopy=join(directory,'source.patch');writeFileSync(patchCopy,patch,{mode:0o600});run('/usr/bin/git',['apply','--reverse',patchCopy],review);
assert(!existsSync(join(review,marker)));
for(const [name,digest]of Object.entries(parents)){baseline[name]=bytes(join(review,name));assert.equal(hash(baseline[name]),digest);}
run('/usr/bin/git',['apply',patchCopy],review);for(const name of names)assert.equal(hash(bytes(join(review,name))),hash(candidates[name]));
// Exact insertions before the three existing CLI branch bodies. No distributed
// implementation file/argument/order is replaced by the candidate patch.
const mark='@import("fios/current_distributed_mode_uncertainty.zig").markConfigured();';
assert.equal(candidates['src/main.zig'].toString().split(mark).length-1,3);
assert.equal(candidates['src/main.zig'].toString().replaceAll('            '+mark+'\n','').replaceAll('        '+mark+'\n',''),baseline['src/main.zig'].toString());
for(const prefix of ['        } else if (std.mem.eql(u8, cmd, "worker")) {\n            ','        } else if (std.mem.eql(u8, cmd, "dist-probe")) {\n            ','    if (dist_mode) |mode| {\n        '])assert(candidates['src/main.zig'].toString().includes(prefix+mark));
assert.equal(candidates['src/host/http/server.zig'].toString().match(/primary_guard = false;/g)?.length,baseline['src/host/http/server.zig'].toString().match(/primary_guard = false;/g)?.length);
const declared=Object.fromEntries(names.map(n=>[n,hash(candidates[n])])),pending=['fios/request_ownership.zig','fios/current_ane_native_backend_uncertainty.zig',marker.slice(4)],copied=new Set();
while(pending.length){const name=pending.pop();if(copied.has(name))continue;copied.add(name);const p=join(source,'src',name),data=bytes(p);declared['src/'+name]=hash(data);const out=join(unit,name);mkdirSync(dirname(out),{recursive:true,mode:0o700});writeFileSync(out,data,{mode:0o600});for(const m of data.toString().matchAll(/@import\("([^"\n]+\.zig)"\)/g)){const p=resolve(dirname(join(source,'src',name)),m[1]),n=relative(join(source,'src'),p);assert(!n.startsWith('..')&&!isAbsolute(n));if(existsSync(p))pending.push(n);}}
const fixturePath=join(root,'platform/studio/native/current_distributed_mode_test.zig.fixture'),fixture=bytes(fixturePath),cases=[...fixture.toString().matchAll(/^test "(distributed mode[^"\n]+)"/gm)].map(m=>m[1]);assert.equal(cases.length,8);
const markers=['DIST_MODE_EARLY_NOT_COMPOSED','DIST_MODE_LATE_CLAIM_ACCEPTED','DIST_MODE_EPOCH_CLEARED','DIST_MODE_LOCAL_ZERO_CLEARED','DIST_MODE_JOIN_CLEARED'];
const receipt={version:1,scope:'actual_server_negative_getter_and_tracker_candidate_marker_injected_in_baseline_CPU_only_no_distributed_runtime',directory,source,parent_projection:parents,declared_inputs:declared,patch_sha256:hash(patch),fixture_sha256:hash(fixture),runner_sha256:hash(bytes(import.meta.filename)),main_order:'exact_insertions_plus_full_file_AST_not_distributed_execution',fixture_primary_guard:true,serving_primary_guard:false,results:[],models:0,inference:false,rdma_calls:0,installed:false,native_authority:false};
const save=()=>writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});save();
mkdirSync(join(unit,'host/http'),{recursive:true,mode:0o700});writeFileSync(join(unit,'main.zig'),fixture,{mode:0o600});writeFileSync(join(unit,'options.zig'),'pub const fios_source_sdk=false;\npub const fios_source_ane=false;\npub const fios_source_ds4=false;\npub const llama_engine=false;\npub const mlx_stream=false;\n',{mode:0o600});
for(const mode of ['Debug','ReleaseSafe'])for(const parent of [true,false]){
 const server=(parent?baseline:candidates)['src/host/http/server.zig'].toString(),functions=[...server.matchAll(/^fn fiosKnownBackendUncertain\(\) bool \{\n[\s\S]*?^\}/gm)];assert.equal(functions.length,1);
 writeFileSync(join(unit,'host/http/server_guard.zig'),functions[0][0]+'\npub const known=fiosKnownBackendUncertain;\n',{mode:0o600});
 for(const [index,name]of cases.entries()){
  const argv=['-p','(version 1)(allow default)(deny network*)',zig,'test','--test-filter',name,'-O'+mode,'--dep','build_options','-Mroot='+join(unit,'main.zig'),'-Mbuild_options='+join(unit,'options.zig'),'-lc'];
  const r=spawnSync('/usr/bin/sandbox-exec',argv,{cwd:directory,env,encoding:'utf8',timeout:120000,maxBuffer:4<<20}),log=(r.stdout||'')+(r.stderr||'');writeFileSync(join(directory,'case-'+receipt.results.length+'.log'),log,{mode:0o600});
  const expected=parent&&index<markers.length?r.status===1&&log.includes(markers[index])&&!log.includes('panic:'):r.status===0&&/^All [12] tests passed\./m.test(log);
  receipt.results.push({mode,parent,name,status:r.status,signal:r.signal,expected,log_sha256:hash(Buffer.from(log))});save();assert(expected,'Retain failed mode check '+directory);
 }
}
receipt.unchanged=Object.entries(declared).every(([n,h])=>hash(bytes(join(source,n)))===h)&&hash(bytes(patchPath))===receipt.patch_sha256&&hash(bytes(fixturePath))===receipt.fixture_sha256&&hash(bytes(import.meta.filename))===receipt.runner_sha256;save();assert(receipt.unchanged);
console.log(JSON.stringify({directory,receipt_sha256:hash(bytes(join(directory,'receipt.json'))),parent_failures:10,parent_controls:6,candidate_cases:16,models:0,rdma_calls:0,native_authority:false}));
