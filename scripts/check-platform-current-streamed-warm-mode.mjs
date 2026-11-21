#!/usr/bin/env node
// Actual constructor/getter bodies with a CPU-only substituted C boundary.
// No Metal allocation, warm kernel, model, installed service or native proof.
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
const constructor='src/sdk/weights/streamed/mimo/gpu_warm.zig',server='src/host/http/server.zig',marker='src/sdk/util/streamed_warm_source_uncertainty.zig';
const parents={[constructor]:'0f0a179f4ec4c5ea6ae3aa8d2ab8ca6964c9f7d8c8ad04b4b38da186577703c0',[server]:'f583fdce776ae646e32549faecb5612f7a3a2c7b23ac82425e8b96254e8d9000'},names=[constructor,server,marker];
const directory=mkdtempSync('/private/tmp/fios-009-streamed-warm-mode-check-'),review=join(directory,'parent'),unit=join(directory,'unit');
for(const p of [review,unit])mkdirSync(p,{mode:0o700});
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1'};
const run=(p,a,cwd=directory)=>execFileSync(p,a,{cwd,env,encoding:'utf8',timeout:30000,maxBuffer:4<<20});
assert.equal(run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,'rev-parse','HEAD']).trim(),'3736ed55f81c6cf0966a0f0dc7265e783655d244');
const patchPath=join(root,'platform/studio/native/mlx-serve-current-streamed-warm-mode.patch'),patch=bytes(patchPath);
assert.deepEqual([...patch.toString().matchAll(/^\+\+\+ b\/([^\r\n]+)$/gm)].map(m=>m[1]),names);
const candidates={},baseline={};
for(const name of names){const data=bytes(join(source,name));candidates[name]=data;const p=join(review,name);mkdirSync(dirname(p),{recursive:true,mode:0o700});writeFileSync(p,data,{mode:0o600});run('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',zig,'ast-check',join(source,name)]);}
const patchCopy=join(directory,'source.patch');writeFileSync(patchCopy,patch,{mode:0o600});run('/usr/bin/git',['apply','--reverse',patchCopy],review);assert(!existsSync(join(review,marker)));
for(const [name,digest]of Object.entries(parents)){baseline[name]=bytes(join(review,name));assert.equal(hash(baseline[name]),digest);}
run('/usr/bin/git',['apply',patchCopy],review);for(const name of names)assert.equal(hash(bytes(join(review,name))),hash(candidates[name]));
const insertion='        @import("mlx_host").shared.Shared(std.atomic.Value(bool), "fios_current_streamed_warm_source_uncertainty", .init(false)).get().store(true, .release);\n';
assert.equal(candidates[constructor].toString().split(insertion).length,2);
assert.equal(candidates[constructor].toString().replace(insertion,''),baseline[constructor].toString());
assert.equal(candidates[server].toString().replace('        @import("../../sdk/util/streamed_warm_source_uncertainty.zig").known() or\n',''),baseline[server].toString());
const declared=Object.fromEntries(names.map(n=>[n,hash(candidates[n])])),pending=['fios/request_ownership.zig','fios/current_ane_native_backend_uncertainty.zig','fios/current_distributed_mode_uncertainty.zig',marker.slice(4)],copied=new Set();
while(pending.length){const name=pending.pop();if(copied.has(name))continue;copied.add(name);const p=join(source,'src',name),data=bytes(p);declared['src/'+name]=hash(data);const out=join(unit,name);mkdirSync(dirname(out),{recursive:true,mode:0o700});writeFileSync(out,data,{mode:0o600});for(const m of data.toString().matchAll(/@import\("([^"\n]+\.zig)"\)/g)){const p=resolve(dirname(join(source,'src',name)),m[1]),n=relative(join(source,'src'),p);assert(!n.startsWith('..')&&!isAbsolute(n));if(existsSync(p))pending.push(n);}}
const fixturePath=join(root,'platform/studio/native/current_streamed_warm_mode_test.zig.fixture'),fixture=bytes(fixturePath),cases=[...fixture.toString().matchAll(/^test "(streamed warm[^"\n]+)"/gm)].map(m=>m[1]);assert.equal(cases.length,8);
const markers=['WARM_CONSTRUCTION_NOT_FENCED','WARM_FAILED_CONSTRUCTION_NOT_FENCED','WARM_MODE_CLAIM_ACCEPTED','WARM_EPOCH_OR_DESTROY_CLEARED','WARM_JOIN_CLEARED'];
const receipt={version:1,scope:'actual_Metal_constructor_and_server_getter_CPU_substituted_C_boundary_only',directory,source,parent_projection:parents,declared_inputs:declared,patch_sha256:hash(patch),fixture_sha256:hash(fixture),runner_sha256:hash(bytes(import.meta.filename)),baseline_marker_module_injected:true,fixture_primary_guard:true,serving_primary_guard:false,results:[],models:0,metal_allocations:0,warm_kernels:0,inference:false,installed:false,native_authority:false};
const save=()=>writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});save();
mkdirSync(join(unit,'host/http'),{recursive:true,mode:0o700});mkdirSync(join(unit,'sdk/weights/streamed/mimo'),{recursive:true,mode:0o700});writeFileSync(join(unit,'main.zig'),fixture,{mode:0o600});
writeFileSync(join(unit,'options.zig'),'pub const fios_source_sdk=false;\npub const fios_source_ane=false;\npub const fios_source_ds4=false;\npub const llama_engine=false;\npub const mlx_stream=false;\n',{mode:0o600});
function method(text,name){const start=text.indexOf('    pub fn '+name+'(');assert(start>=0&&text.indexOf('    pub fn '+name+'(',start+1)<0);let depth=0,opened=false;for(let i=text.indexOf('{',start);i<text.length;i++){if(text[i]==='{'){depth++;opened=true;}else if(text[i]==='}'&&--depth===0&&opened)return text.slice(start,i+1);}throw Error('Unbalanced actual constructor');}
for(const mode of ['Debug','ReleaseSafe'])for(const variant of ['constructor-parent','getter-parent','candidate']){
 const getter=(variant==='getter-parent'?baseline:candidates)[server].toString(),functions=[...getter.matchAll(/^fn fiosKnownBackendUncertain\(\) bool \{\n[\s\S]*?^\}/gm)];assert.equal(functions.length,1);
 writeFileSync(join(unit,'host/http/server_guard.zig'),functions[0][0]+'\npub const known=fiosKnownBackendUncertain;\n',{mode:0o600});
 const metal=(variant==='constructor-parent'?baseline:candidates)[constructor].toString();
 const body=`const std=@import("std"); const marker=@import("mlx_host").warm_marker; const threads:u32=32;
const log=struct {fn warn(comptime format:[]const u8,arguments:anytype) void {_=format;_=arguments;}};
const c=struct {var status:c_int=0;var fenced=false;fn mimo_warm_create(_:u32,_:u32,out:*?*anyopaque)c_int {fenced=marker.known();out.*=@ptrFromInt(4096);return status;}fn mimo_warm_destroy(_: ?*anyopaque)void {}fn mimo_warm_last_error()[*:0]const u8{return "CPU substitute";}};
pub fn boundaryWasFenced()bool{return c.fenced;}pub fn failConstruction()void{c.status=-1;}
pub const Metal=struct {h:?*anyopaque=null,event:u64,
${method(metal,'init')}
${method(metal,'deinit')}
};\n`;
 writeFileSync(join(unit,'sdk/weights/streamed/mimo/warm_constructor.zig'),body,{mode:0o600});
 for(const [index,name]of cases.entries()){
  const argv=['-p','(version 1)(allow default)(deny network*)',zig,'test','--test-filter',name,'-O'+mode,'--dep','build_options','--dep','warm_constructor','-Mroot='+join(unit,'main.zig'),'--dep','mlx_host=root','-Mwarm_constructor='+join(unit,'sdk/weights/streamed/mimo/warm_constructor.zig'),'-Mbuild_options='+join(unit,'options.zig'),'-lc'];
  const r=spawnSync('/usr/bin/sandbox-exec',argv,{cwd:directory,env,encoding:'utf8',timeout:120000,maxBuffer:4<<20}),log=(r.stdout||'')+(r.stderr||'');writeFileSync(join(directory,'case-'+receipt.results.length+'.log'),log,{mode:0o600});
  const negative=(variant==='constructor-parent'&&index<4)||(variant==='getter-parent'&&index<5);
  const expected=negative?r.status===1&&log.includes(markers[index])&&log.includes('FAIL (TestUnexpectedResult)')&&/^[01] passed; 0 skipped; 1 failed\.$/m.test(log)&&!log.includes('panic:'):r.status===0&&/^All [12] tests passed\./m.test(log);
  receipt.results.push({mode,variant,name,status:r.status,signal:r.signal,negative,expected,log_sha256:hash(Buffer.from(log))});save();assert(expected,'Retain failed streamed warm check '+directory);
 }
}
receipt.unchanged=Object.entries(declared).every(([n,h])=>hash(bytes(join(source,n)))===h)&&hash(bytes(patchPath))===receipt.patch_sha256&&hash(bytes(fixturePath))===receipt.fixture_sha256&&hash(bytes(import.meta.filename))===receipt.runner_sha256;save();assert(receipt.unchanged);
console.log(JSON.stringify({directory,receipt_sha256:hash(bytes(join(directory,'receipt.json'))),parent_failures:18,parent_controls:14,candidate_cases:16,models:0,metal_allocations:0,native_authority:false}));
