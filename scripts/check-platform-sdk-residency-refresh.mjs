#!/usr/bin/env node
// Explicit private SDK metadata composition. Optional Core-only device/refresh
// constructor check; no model/stream creation or array evaluation,
// installation, negative-counter campaign or native authority assertion.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdtempSync,lstatSync,realpathSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {createHash} from 'node:crypto';
const args=process.argv.slice(2),root=resolve(import.meta.dirname,'..');
const realMetadata=args.at(-1)==='--metal-metadata';if(realMetadata)args.pop();
assert(process.platform==='darwin'&&process.arch==='arm64'&&process.getuid()>0);
assert(args.length===9&&args[0]==='--isolated'&&args[1]==='--source'&&args[3]==='--prefix'&&args[5]==='--build-review'&&args[7]==='--sha256');
const [source,prefix,document]=[args[2],args[4],args[6]].map(value=>{
 assert(value.startsWith('/private/tmp/')&&realpathSync(value)===value);return value;
});
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
assert(/^[a-f0-9]{64}$/.test(args[8]));
assert(lstatSync(document).size>0&&lstatSync(document).size<=1<<20);
const documentBytes=readFileSync(document);assert.equal(sha(documentBytes),args[8]);const review=JSON.parse(documentBytes);
assert.equal(review.scope,'fresh_selected_MLX_CPP_SDK_component_not_MLXC_native_or_model_acceptance');
assert.equal(review.inputs_unchanged,true);for(const flag of ['installed','native_authority','whole_native_provenance'])assert.equal(review[flag],false);
assert.equal(review.model_requests,0);assert(review.records.length===2&&review.records.every(record=>record.status===0));
const directory=mkdtempSync('/private/tmp/fios-009-residency-check-');
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
function run(name,program,argv,timeout=120000){
 const result=spawnSync(program,argv,{env,encoding:'utf8',timeout,maxBuffer:2<<20});
 writeFileSync(join(directory,name+'.log'),(result.stdout??'')+(result.stderr??''),{mode:0o600});
 assert(!result.error&&result.status===0,name+' failed; retain '+directory);return result.stdout;
}
const git=(...argv)=>run('source-'+argv[0],'/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,...argv],15000);
if(realMetadata){
 assert.equal(run('host','/usr/sbin/scutil',['--get','LocalHostName'],2000).trim(),'fios-core');
 assert.equal(run('physical','/usr/sbin/sysctl',['-n','hw.memsize'],2000).trim(),String(24*2**30));
 assert.match(run('cpu','/usr/sbin/sysctl',['-n','machdep.cpu.brand_string'],2000),/^Apple M4/);
}
assert.equal(git('rev-parse','HEAD').trim(),'c69303b00f5f61860436e832f23fa8c34b96f93a');
const modified=['mlx/backend/cpu/eval.cpp','mlx/backend/metal/device.cpp','mlx/backend/metal/device.h','mlx/backend/metal/eval.cpp','mlx/backend/metal/event.cpp','mlx/backend/metal/resident.cpp','mlx/scheduler.cpp','mlx/stream.cpp','mlx/stream.h'];
assert.deepEqual(git('status','--porcelain','--untracked-files=all','--ignored=matching').trimEnd().split('\n'),modified.map(name=>' M '+name));
const patch=readFileSync(join(root,'platform/studio/native/mlx-c69303b-residency-refresh-refusal.patch'));
assert.equal(git('diff','--no-ext-diff','--no-textconv','HEAD'),patch.toString());
const beforePath=join(resolve(document,'..'),'build-before.json');assert(lstatSync(beforePath).size>0&&lstatSync(beforePath).size<=1<<20);
const beforeBytes=readFileSync(beforePath);assert.equal(sha(beforeBytes),review.before_sha256);
const before=JSON.parse(beforeBytes),paths=Object.keys(before.source);assert.equal(paths.length,review.source_files);
assert(paths.length>0&&paths.length<=4096);
const safe=value=>typeof value==='string'&&!value.startsWith('/')&&!value.split('/').some(part=>!part||part==='.'||part==='..');
function sourceCapture(){let total=0;return Object.fromEntries(paths.map(name=>{
 assert(safe(name));const file=join(source,name),info=lstatSync(file);assert(info.isFile()&&!info.isSymbolicLink()&&info.size>=0&&info.size<=8<<20);
 total+=info.size;assert(total<=512<<20);return [name,sha(readFileSync(file))];
}));}
assert.deepEqual(sourceCapture(),before.source);
const fixture=join(root,'platform/studio/native/mlx_residency_refresh_refusal_test.cpp');
const libraries=['libmlx.dylib','libjaccl.dylib','mlx.metallib'].map(name=>join(prefix,'lib',name));
function capture(){return Object.fromEntries([fixture,...libraries].map(file=>{
 const info=lstatSync(file);assert(info.isFile()&&!info.isSymbolicLink()&&info.nlink===1&&info.size>0&&info.size<=256<<20);return [file,sha(readFileSync(file))];
}));}
const checkerSHA256=sha(readFileSync(join(root,'scripts/check-platform-sdk-residency-refresh.mjs')));
const inputs=capture();assert.equal(inputs[libraries[0]],review.library_sha256);const records=[];
for(const [mode,flags]of [['debug',['-O0']],['optimized',['-O2']]]){
 const binary=join(directory,mode);
 run(mode+'-compile','/usr/bin/clang++',['-std=c++20','-Wall','-Wextra','-Werror',...flags,'-mmacosx-version-min=26.2','-I'+source,fixture,'-L'+join(prefix,'lib'),'-Wl,-rpath,'+join(prefix,'lib'),'-lmlx','-o',binary]);
 for(const scenario of ['unused','before-enrollment','after-enrollment']){
  assert.match(run(mode+'-'+scenario,binary,[scenario],5000),/^PASS:/);records.push({mode,scenario,status:0});
 }
 if(realMetadata){
  const physical=join(directory,mode+'-metal-metadata');
  run(mode+'-metal-compile','/usr/bin/clang++',['-std=c++20','-Wall','-Wextra','-Werror',...flags,'-DFIOS_REAL_RESIDENCY_METADATA=1','-mmacosx-version-min=26.2','-I'+source,fixture,'-L'+join(prefix,'lib'),'-Wl,-rpath,'+join(prefix,'lib'),'-lmlx','-o',physical]);
  assert.match(run(mode+'-real-refresh',physical,['real-refresh-metadata'],5000),/^PASS:/);records.push({mode,scenario:'real-refresh-metadata',status:0});
 }
}
assert.deepEqual(sourceCapture(),before.source);assert.deepEqual(capture(),inputs);assert.equal(sha(readFileSync(document)),args[8]);
assert.equal(sha(readFileSync(join(root,'scripts/check-platform-sdk-residency-refresh.mjs'))),checkerSHA256);
const result={scope:realMetadata?'genuine_Core_only_refresh_worker_device_metadata_not_model_acceptance':'genuine_SDK_metadata_and_compiled_residency_hook_not_live_refresh_acceptance',build_review_sha256:args[8],patch_sha256:sha(patch),checker_sha256:checkerSHA256,inputs,records,source_files:paths.length,inputs_unchanged:true,models:0,device_metadata_exercised:realMetadata,refresh_constructor_exercised:realMetadata,whole_native_provenance:false,all_client_coverage:false,native_authority:false,installed:false,activation:false};
const bytes=Buffer.from(JSON.stringify(result,null,2)+'\n');writeFileSync(join(directory,'receipt.json'),bytes,{mode:0o600});console.log(JSON.stringify({directory,receipt_sha256:sha(bytes),stages:records.length,native_authority:false}));
