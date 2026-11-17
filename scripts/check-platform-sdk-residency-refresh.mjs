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
const constructorOrder=args.includes('--constructor-order');
if(constructorOrder){assert.equal(args.filter(value=>value==='--constructor-order').length,1);args.splice(args.indexOf('--constructor-order'),1);}
const nativeBridge=args.at(-2)==='--native-bridge'?args.splice(-2)[1]:null;
const sealedMetadata=args.at(-1)==='--sealed-metal-metadata';if(sealedMetadata)args.pop();
const participantSeal=args.at(-1)==='--participant-seal';if(participantSeal)args.pop();
const realMetadata=args.at(-1)==='--metal-metadata';if(realMetadata)args.pop();
assert(!(participantSeal&&realMetadata));
assert(!constructorOrder||participantSeal);
assert(!nativeBridge||participantSeal);
assert(!sealedMetadata||participantSeal);
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
if(realMetadata||sealedMetadata){
 assert.equal(run('host','/usr/sbin/scutil',['--get','LocalHostName'],2000).trim(),'fios-core');
 assert.equal(run('physical','/usr/sbin/sysctl',['-n','hw.memsize'],2000).trim(),String(24*2**30));
 assert.match(run('cpu','/usr/sbin/sysctl',['-n','machdep.cpu.brand_string'],2000),/^Apple M4/);
}
assert.equal(git('rev-parse','HEAD').trim(),'c69303b00f5f61860436e832f23fa8c34b96f93a');
const modified=['mlx/backend/cpu/eval.cpp','mlx/backend/metal/device.cpp','mlx/backend/metal/device.h','mlx/backend/metal/eval.cpp','mlx/backend/metal/event.cpp','mlx/backend/metal/resident.cpp','mlx/scheduler.cpp','mlx/stream.cpp','mlx/stream.h'];
assert.deepEqual(git('status','--porcelain','--untracked-files=all','--ignored=matching').trimEnd().split('\n'),modified.map(name=>' M '+name));
const patch=readFileSync(join(root,participantSeal?'platform/studio/native/mlx-c69303b-participant-seal.patch':'platform/studio/native/mlx-c69303b-residency-refresh-refusal.patch'));
const orderInputs=constructorOrder?['mlx-residency-constructor-refusal-order.patch','residency_constructor_order_parents.json'].map(name=>join(root,'platform/studio/native',name)):[];
if(constructorOrder){
 const {mkdirSync}=await import('node:fs');
 const reviewDirectory=join(directory,'constructor-order'),relative='mlx/backend/metal/resident.cpp';
 const target=join(reviewDirectory,relative);mkdirSync(resolve(target,'..'),{recursive:true,mode:0o700});
 const candidate=readFileSync(join(source,relative));writeFileSync(target,candidate,{mode:0o600});
 const parents=JSON.parse(readFileSync(orderInputs[1]));assert.deepEqual(Object.keys(parents),[relative]);
 run('order-reverse','/usr/bin/git',['-C',reviewDirectory,'apply','--reverse',orderInputs[0]],5000);
 assert.equal(sha(readFileSync(target)),parents[relative]);
 run('order-forward','/usr/bin/git',['-C',reviewDirectory,'apply',orderInputs[0]],5000);
 assert.equal(sha(readFileSync(target)),sha(candidate));
 const withoutResident=text=>text.split(/(?=^diff --git )/m).filter(block=>!block.startsWith('diff --git a/'+relative+' ')).join('');
 assert.equal(withoutResident(git('diff','--no-ext-diff','--no-textconv','HEAD')),withoutResident(patch.toString()));
}else assert.equal(git('diff','--no-ext-diff','--no-textconv','HEAD'),patch.toString());
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
const fixture=join(root,participantSeal?'platform/studio/native/mlx_background_participant_seal_test.cpp':'platform/studio/native/mlx_residency_refresh_refusal_test.cpp');
const bridgeInputs=nativeBridge?[nativeBridge,join(root,'platform/studio/native/sdk_background_seal_parents.json'),join(root,'platform/studio/native/mlx-serve-sdk-background-seal.patch'),join(root,'platform/studio/native/mlx_background_startup_seal_test.cpp')]:[];
if(nativeBridge)assert(nativeBridge.startsWith('/private/tmp/')&&realpathSync(nativeBridge)===nativeBridge);
const libraries=['libmlx.dylib','libjaccl.dylib','mlx.metallib'].map(name=>join(prefix,'lib',name));
function capture(){return Object.fromEntries([fixture,...libraries,...bridgeInputs,...orderInputs].map(file=>{
 const info=lstatSync(file);assert(info.isFile()&&!info.isSymbolicLink()&&info.nlink===1&&info.size>0&&info.size<=256<<20);return [file,sha(readFileSync(file))];
}));}
const checkerSHA256=sha(readFileSync(join(root,'scripts/check-platform-sdk-residency-refresh.mjs')));
const inputs=capture();assert.equal(inputs[libraries[0]],review.library_sha256);const records=[];
for(const [mode,flags]of [['debug',['-O0']],['optimized',['-O2']]]){
 const binary=join(directory,mode);
 run(mode+'-compile','/usr/bin/clang++',['-std=c++20','-Wall','-Wextra','-Werror',...flags,'-mmacosx-version-min=26.2','-I'+source,fixture,'-L'+join(prefix,'lib'),'-Wl,-rpath,'+join(prefix,'lib'),'-lmlx','-o',binary]);
 for(const scenario of (participantSeal?['before-enrollment','existing-participant','sealed','race']:['unused','before-enrollment','after-enrollment'])){
  assert.match(run(mode+'-'+scenario,binary,[scenario],5000),/^PASS:/);records.push({mode,scenario,status:0});
 }
 if(sealedMetadata){
  const physical=join(directory,mode+'-sealed-metal-metadata');
  run(mode+'-sealed-metal-compile','/usr/bin/clang++',['-std=c++20','-Wall','-Wextra','-Werror',...flags,'-DFIOS_REAL_RESIDENCY_METADATA=1','-mmacosx-version-min=26.2','-I'+source,fixture,'-L'+join(prefix,'lib'),'-Wl,-rpath,'+join(prefix,'lib'),'-lmlx','-o',physical]);
  assert.match(run(mode+'-real-refresh-sealed',physical,['real-refresh-sealed'],5000),/^PASS:/);records.push({mode,scenario:'real-refresh-sealed',status:0});
 }
 if(realMetadata){
  const physical=join(directory,mode+'-metal-metadata');
  run(mode+'-metal-compile','/usr/bin/clang++',['-std=c++20','-Wall','-Wextra','-Werror',...flags,'-DFIOS_REAL_RESIDENCY_METADATA=1','-mmacosx-version-min=26.2','-I'+source,fixture,'-L'+join(prefix,'lib'),'-Wl,-rpath,'+join(prefix,'lib'),'-lmlx','-o',physical]);
  assert.match(run(mode+'-real-refresh',physical,['real-refresh-metadata'],5000),/^PASS:/);records.push({mode,scenario:'real-refresh-metadata',status:0});
 }
}
if(nativeBridge){
 const [original,parentsFile,bridgePatch,startupFixture]=bridgeInputs;
 const parents=JSON.parse(readFileSync(parentsFile));
 assert.deepEqual(Object.keys(parents.native_source),['src/fios/current_sdk_owners.cpp']);
 assert.equal(sha(readFileSync(original)),parents.native_source['src/fios/current_sdk_owners.cpp']);
 const parent=join(directory,'parent-bridge.cpp'),candidate=join(directory,'bridge-review/src/fios/current_sdk_owners.cpp');
 const {mkdirSync}=await import('node:fs');
 mkdirSync(resolve(candidate,'..'),{recursive:true,mode:0o700});
 writeFileSync(parent,readFileSync(original));writeFileSync(candidate,readFileSync(original));
 const applied=spawnSync('/usr/bin/git',['apply',bridgePatch],{cwd:join(directory,'bridge-review'),env,encoding:'utf8',timeout:5000,maxBuffer:65536});
 assert(!applied.error&&applied.status===0);
 const declaration='#define MLX_FIOS_BACKGROUND_PARTICIPANT_SEAL 1\n// One-way source-fixture exclusion only; not all-client/device authority.\nMLX_API bool fios_seal_background_participants_fixture();\n';
 const currentHeader=readFileSync(join(source,'mlx/stream.h'),'utf8');assert(currentHeader.includes(declaration));
 const legacyHeader=currentHeader.replace(declaration,'');assert.equal(sha(Buffer.from(legacyHeader)),parents.legacy_sdk_header_sha256);
 const legacy=join(directory,'legacy-headers');mkdirSync(join(legacy,'mlx'),{recursive:true,mode:0o700});
 writeFileSync(join(legacy,'mlx/stream.h'),legacyHeader);
 for(const [mode,flags]of [['debug',['-O0']],['optimized',['-O2']]]){
  for(const [scenario,bridge,headers,expectedExit,expectation,strict]of [
   ['baseline_missing_seal',parent,source,1,'sealed',true],
   ['actual_startup_seal',candidate,source,0,'sealed',true],
   ['default_startup_unchanged',candidate,source,0,'unsealed',false],
   ['prior_header_unchanged',candidate,legacy,0,'unsealed',false],
   ['prior_header_strict_refusal',candidate,legacy,78,'sealed',true]]){
   const binary=join(directory,mode+'-'+scenario);
   run(mode+'-'+scenario+'-compile','/usr/bin/clang++',['-std=c++20','-Wall','-Wextra','-Werror',...flags,...(strict?['-DFIOS_REQUIRE_BACKGROUND_PARTICIPANT_SEAL=1']:[]),'-mmacosx-version-min=26.2','-I'+headers,'-I'+source,bridge,startupFixture,'-L'+join(prefix,'lib'),'-Wl,-rpath,'+join(prefix,'lib'),'-lmlx','-o',binary]);
   const executed=spawnSync(binary,[expectation],{env,encoding:'utf8',timeout:5000,maxBuffer:65536});
   writeFileSync(join(directory,mode+'-'+scenario+'.log'),(executed.stdout??'')+(executed.stderr??''),{mode:0o600});
   assert(!executed.error&&executed.status===expectedExit);
   if(expectedExit===78)assert.equal(executed.stdout,'');else assert.match(executed.stdout,expectedExit===0?/^PASS:/ : /^FAIL: startup did not/);
   if(scenario.startsWith('prior_header_'))assert(!run(mode+'-legacy-symbols','/usr/bin/nm',['-u',binary]).includes('fios_seal_background_participants_fixture'));
   records.push({mode,scenario,status:0,actual_exit:executed.status,binary_sha256:sha(readFileSync(binary))});
  }
 }
}
assert.deepEqual(sourceCapture(),before.source);assert.deepEqual(capture(),inputs);assert.equal(sha(readFileSync(document)),args[8]);
assert.equal(sha(readFileSync(join(root,'scripts/check-platform-sdk-residency-refresh.mjs'))),checkerSHA256);
const result={scope:sealedMetadata?'genuine_Core_only_sealed_refresh_constructor_not_model_or_native_authority':participantSeal?'genuine_SDK_atomic_background_start_exclusion_CPU_metadata_not_native_authority':realMetadata?'genuine_Core_only_refresh_worker_device_metadata_not_model_acceptance':'genuine_SDK_metadata_and_compiled_residency_hook_not_live_refresh_acceptance',build_review_sha256:args[8],patch_sha256:sha(patch),checker_sha256:checkerSHA256,constructor_refusal_order_patch_checked:constructorOrder,inputs,records,source_files:paths.length,inputs_unchanged:true,models:0,background_participant_seal_exercised:participantSeal,actual_native_startup_seal_exercised:!!nativeBridge,synthetic_native_callbacks:!!nativeBridge,device_metadata_exercised:realMetadata||sealedMetadata,refresh_constructor_exercised:realMetadata||sealedMetadata,refresh_worker_start_refused:sealedMetadata,whole_native_provenance:false,all_client_coverage:false,native_authority:false,installed:false,activation:false};
const bytes=Buffer.from(JSON.stringify(result,null,2)+'\n');writeFileSync(join(directory,'receipt.json'),bytes,{mode:0o600});console.log(JSON.stringify({directory,receipt_sha256:sha(bytes),stages:records.length,native_authority:false}));
