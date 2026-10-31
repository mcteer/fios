#!/usr/bin/env node
// Reproducible linked SOURCE FIXTURE, not an upstream staged/installed release.
// Uses pinned, READ-ONLY installed bundle dependencies copied into development
// state, genuine headers and the actual native executable/test roots. No model
// weights/backend stubs, forged stamps, host dependency installs or inference.
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { copyFileSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, realpathSync, rmSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {stageNativeReview,finishNativeReview} from './lib/platform-native-review.mjs';
import {verifyMlxSourceReview} from './lib/platform-mlx-source-review.mjs';
import {verifyDs4SourceBuild,bindDs4SourceBuildGraph} from './lib/platform-ds4-source-review.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const args=process.argv.slice(2);
// Ordinary compilation/packaging mode, without the historical test matrices.
const functionalBuildOnly=args.at(-1)==='--functional-build-only';
if(functionalBuildOnly)args.pop();
// Checked DS4 ABI is explicitly composed from a hash-bound private build.
let ds4DependencyConfig;
const ds4Index=args.indexOf('--ds4-build');
if(ds4Index!==-1){
 assert.equal(ds4Index,8);assert(args[ds4Index+2]==='--ds4-sha256');
 ds4DependencyConfig={document:args[ds4Index+1],expected:args[ds4Index+3],root};args.splice(ds4Index,4);
}
assert(ds4DependencyConfig,'Checked native DS4 ABI requires explicit --ds4-build ABS_JSON --ds4-sha256 HEX');
const ds4Dependency=verifyDs4SourceBuild(ds4DependencyConfig);
// Optional genuine source-built MLX dependency. No installed paths change.
let mlxDependencyConfig;
const mlxIndex=args.indexOf('--mlx-dependency');
if(mlxIndex!==-1){
 assert([8,10].includes(mlxIndex)&&args[mlxIndex+2]==='--mlx-sha256'&&args[mlxIndex+4]==='--mlx-source');
 mlxDependencyConfig=[args[mlxIndex+1],args[mlxIndex+3],args[mlxIndex+5]];
 args.splice(mlxIndex,6);
}
// Optional data-only source-review output. No model or inference input.
let reviewOutput;
const reviewIndex=args.indexOf('--review-output');
if(reviewIndex!==-1){assert([8,10].includes(reviewIndex)&&path.isAbsolute(args[reviewIndex+1]??''));reviewOutput=args[reviewIndex+1];args.splice(reviewIndex,2);}
if(functionalBuildOnly)assert(reviewOutput,'Functional build requires a private review output');
// Optional explicit dependency composition; canonical submodules stay clean.
let mimoSource;
const mimoIndex=args.indexOf('--mimo-source');
if(mimoIndex!==-1){
 assert.equal(mimoIndex,8,'MIMO candidate follows the four fixed input pairs');
 assert(path.isAbsolute(args[9]??''),'absolute candidate source required');
 mimoSource=realpathSync(args[9]);args.splice(8,2);
}
assert(process.platform==='darwin' && process.getuid()!==0);
assert((args.length===8 || (args.length===9 && ['--empty-gpu','--root-tests-only','--mutation-request-eviction-guard','--mutation-load-preparation-guard','--mutation-actor-load-preparation','--mutation-encoder-active-owner','--mutation-generation-origin','--mutation-text-origin','--mutation-native-refusal-response','--mutation-drop-model-pins','--mutation-drop-parked-pins','--mutation-access-foreign-release','--mutation-drop-registry-preparation','--mutation-clear-registry-preparation','--mutation-registry-stub-frontdoor','--mutation-registry-path-frontdoor','--mutation-registry-scan-frontdoor','--mutation-registry-teardown','--mutation-loaded-model-teardown','--mutation-retained-cpu-cleanup','--mutation-resident-unload','--mutation-ds4-snapshot-free','--mutation-llama-trim-status'].includes(args[8]))) && args[0]==='--source' && args[2]==='--zig' && args[4]==='--webp-source' && args[6]==='--metal-cpp-zip' && [args[1],args[3],args[5],args[7]].every(path.isAbsolute),
 'usage: check-platform-native-fixture.mjs --source ABS_CHECKOUT --zig ABS_ZIG --webp-source ABS_WEBP_1_6_0 --metal-cpp-zip ABS_APPLE_METAL_CPP_26_ZIP --ds4-build ABS_JSON --ds4-sha256 HEX [--mimo-source ABS_REVIEWED_CANDIDATE] [--mlx-dependency ABS_JSON --mlx-sha256 HEX --mlx-source ABS] [--mutation-native-refusal-response|--mutation-load-preparation-guard|--mutation-actor-load-preparation|--mutation-encoder-active-owner|--mutation-generation-origin|--mutation-text-origin|--mutation-request-eviction-guard|--empty-gpu|--root-tests-only|--mutation-drop-model-pins|--mutation-drop-parked-pins|--mutation-access-foreign-release|--mutation-drop-registry-preparation|--mutation-clear-registry-preparation|--mutation-registry-stub-frontdoor|--mutation-registry-path-frontdoor|--mutation-registry-scan-frontdoor|--mutation-registry-teardown|--mutation-loaded-model-teardown|--mutation-retained-cpu-cleanup|--mutation-resident-unload|--mutation-ds4-snapshot-free|--mutation-llama-trim-status]');
if(functionalBuildOnly)assert.equal(args.length,8,'Functional build cannot select a test/mutation mode');
const trimMutation=args[8]==='--mutation-llama-trim-status';
const snapshotMutation=args[8]==='--mutation-ds4-snapshot-free';
const residentUnloadMutation=args[8]==='--mutation-resident-unload';
const retainedCpuMutation=args[8]==='--mutation-retained-cpu-cleanup';
const loadedTeardownMutation=args[8]==='--mutation-loaded-model-teardown';
const teardownMutation=args[8]==='--mutation-registry-teardown';
const parkedMutation=args[8]==='--mutation-drop-parked-pins',accessMutation=args[8]==='--mutation-access-foreign-release';
const preparationMutation=args[8]==='--mutation-drop-registry-preparation',clearPreparationMutation=args[8]==='--mutation-clear-registry-preparation';
const frontdoorKind=['stub','path','scan'].find(kind=>args[8]===`--mutation-registry-${kind}-frontdoor`);
const textOriginMutation=args[8]==='--mutation-text-origin';
const generationOriginMutation=args[8]==='--mutation-generation-origin';
const encoderActiveMutation=args[8]==='--mutation-encoder-active-owner';
const actorLoadMutation=args[8]==='--mutation-actor-load-preparation';
const nativeRefusalMutation=args[8]==='--mutation-native-refusal-response';
const evictionMutation=args[8]==='--mutation-request-eviction-guard',loadPreparationMutation=args[8]==='--mutation-load-preparation-guard';
const registryMutation=residentUnloadMutation||retainedCpuMutation||loadedTeardownMutation||teardownMutation||evictionMutation||accessMutation||clearPreparationMutation||!!frontdoorKind;
const mutation=trimMutation||snapshotMutation||residentUnloadMutation||retainedCpuMutation||loadedTeardownMutation||teardownMutation ||textOriginMutation || nativeRefusalMutation||generationOriginMutation||encoderActiveMutation||actorLoadMutation||loadPreparationMutation||evictionMutation||parkedMutation||accessMutation||preparationMutation||clearPreparationMutation||!!frontdoorKind||args[8]==='--mutation-drop-model-pins',rootOnly=mutation||args[8]==='--root-tests-only';
assert(!mlxDependencyConfig||reviewOutput&&!rootOnly,'Source dependency requires a full private review output');
const mlxDependency=mlxDependencyConfig?verifyMlxSourceReview(...mlxDependencyConfig):null;
const [source,zig,webp,metalZip]=[args[1],args[3],args[5],args[7]].map(filename=>realpathSync(filename));
assert(source.startsWith('/private/tmp/'),'only a disposable source checkout is permitted');
assert.equal(lstatSync(source).uid,process.getuid());assert.equal(lstatSync(source).mode&0o022,0);
const sha=file=>{assert(lstatSync(file).isFile()&&!lstatSync(file).isSymbolicLink());return createHash('sha256').update(readFileSync(file)).digest('hex');};
assert.equal(sha(zig),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
assert.equal(sha(metalZip),'4df3c078b9aadcb516212e9cb03004cbc5ce9a3e9c068fa3144d021db585a3a4');
const bundle='/Applications/MLX-Serve.app/Contents/Frameworks';
const runtime={
 'libmlx.dylib':'6a5ee820afed9ce9421297260b4a9fd593749052d582c65deeca428fce61c76e',
 'libmlxc.dylib':'6b4c9224691c2857cf7d386e75c1247cc6b0a4ae17d6ec6d1b455ec177e9929f',
 'libjaccl.dylib':'5c6f3819b3555902ba1ab3a49550643994b49860f09e323fe42dfd6121103282',
 'mlx.metallib':'95974b7de464ec2be7833a914ca5a53d283a70789470fd84218738fc8fcea3e1',
 'libwebp.dylib':'46205547256c4f44ad1bbbdb97cfdb5a5e6a11c85467517e6bd9f2126c1bba99',
 'libsharpyuv.dylib':'a6ebdb5a016fa6f546553db9c524f3cf396b623b134bf30ac8a3695a6fb1af5a',
};
for(const [name,digest]of Object.entries(runtime))assert.equal(sha(path.join(bundle,name)),digest,`unreviewed bundle input ${name}`);
assert.equal(sha(path.join(source,'lib/llama/lib/libllama.dylib')),'10f39f1688515e851c79e111a18a2a852923c4edb20f950061f6d7356ef8987b');
assert.equal(readFileSync(path.join(source,'lib/llama/.version'),'utf8').trim(),'b11429','run the genuine pinned upstream fetch-llama.sh first');
const llamaHeaders=path.join(source,'lib/llama/include');
const headerRows=readdirSync(llamaHeaders).sort().map(name=>[name,sha(path.join(llamaHeaders,name))]);
assert.equal(createHash('sha256').update(JSON.stringify(headerRows)).digest('hex'),'81835fcd030ba92eb6e68e948eea0cf906d773f1676a80babe78de7b731a99dc');
const scratch=mkdtempSync('/tmp/f9-linked-native-');
const mlxLibraries=mlxDependency?path.join(scratch,'mlx'):path.join(source,'lib/mlx/lib');
const participantFile=path.join(root,'platform/studio/native/source_mlx_participants.cpp'),participantBytes=mlxDependency?readFileSync(participantFile,'utf8'):null;
const env={DEVELOPER_DIR:'/Applications/Xcode.app/Contents/Developer',PATH:'/usr/bin:/bin',HOME:scratch,LANG:'C',LC_ALL:'C',TMPDIR:scratch,ZIG_GLOBAL_CACHE_DIR:path.join(homedir(),'.cache/zig')};
const run=(file,argv,options={})=>execFileSync(file,argv,{encoding:'utf8',env,timeout:600000,maxBuffer:16*1024*1024,...options});
assert.equal(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim(),'27.2');
const filename=`fios-linked-${randomUUID()}.zig`,generated=path.join(source,filename);
const schedulerFile=path.join(source,'src/scheduler.zig'),registryFile=path.join(source,'src/model_registry.zig'),serverFile=path.join(source,'src/server.zig');
const ds4File=path.join(source,'src/arch/ds4.zig'),llamaFile=path.join(source,'src/arch/llama.zig');
const mutationFile=trimMutation?llamaFile:snapshotMutation?ds4File:nativeRefusalMutation?serverFile:registryMutation?registryFile:schedulerFile;
let written=false,mutated=false,schedulerOriginal,registryOriginal,serverOriginal,ds4Original,mutationOriginal;
let mimoReceipt=null;
function verifyMimo(){
 if(!mimoSource)return null;
 const info=lstatSync(mimoSource);
 assert(mimoSource.startsWith('/private/tmp/')&&info.isDirectory()&&info.uid===process.getuid()&&(info.mode&0o022)===0,'private disposable MIMO checkout required');
 const git=(...argv)=>run('/usr/bin/git',['--no-replace-objects','-C',mimoSource,...argv]);
 const revision='fcb4011347ff80eeeb19e2a1f0180e13199c7c8b',file='src/arch/mimo_v2/gpu_warm.zig';
 assert.equal(git('rev-parse','HEAD').trim(),revision);
 assert.equal(git('diff','--cached','--name-only').trim(),'','no staged candidate changes');
 const candidateFiles=['gpu_warm','module','root','source'].map(name=>`src/arch/mimo_v2/${name}.zig`);
 assert.deepEqual(git('diff','--name-only').trim().split('\n'),candidateFiles,'only reviewed candidate paths may differ');
 const patchFile=path.join(root,'platform/studio/native/mlx-stream-fcb4011-retirement.patch');
 assert.equal(git('diff','--no-ext-diff','--no-textconv','--',...candidateFiles),readFileSync(patchFile,'utf8'),'candidate must exactly match reviewed retirement patch');
 return {revision,patch_sha256:sha(patchFile),source_sha256:sha(path.join(mimoSource,file)),files:candidateFiles.map(file=>({path:file,sha256:sha(path.join(mimoSource,file))})),source_fixture_only:true};
}

// Refuse to replace an existing differing input, or follow a link. Development
// staging is intentionally unstamped and cannot satisfy upstream release gates.
function stage(from,to){
 const info=lstatSync(from);assert(!info.isSymbolicLink());
 if(info.isDirectory()){
  if(existsSync(to))assert(lstatSync(to).isDirectory()&&!lstatSync(to).isSymbolicLink());else mkdirSync(to,{recursive:true,mode:0o700});
  for(const name of readdirSync(from))stage(path.join(from,name),path.join(to,name));
 }else{
  assert(info.isFile());
  if(existsSync(to))assert.equal(sha(to),sha(from),`different existing development input ${to}`);
  else{mkdirSync(path.dirname(to),{recursive:true,mode:0o700});copyFileSync(from,to);}
 }
}
try{
 mimoReceipt=verifyMimo();
 // Fail cheap on integration-script syntax before expensive native codegen.
 run(process.execPath,['--check',path.join(root,'scripts/check-platform-native-http.mjs')]);
 // Before staging: verifies commits/submodules, exact reviewed fixed-file
 // build/roots/llama-context bridge patch and companions, preserved staging
 // guards and real Zig-root Sema.
 if(functionalBuildOnly){
  const gitArgs=['--no-replace-objects','-c','core.fsmonitor=false','-C',source];
  const gitEnv={...env,GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
  assert.equal(run('/usr/bin/git',[...gitArgs,'rev-parse','HEAD'],{env:gitEnv}).trim(),'046b647686419df06c6c7132fb1d15d76185c3e5');
  assert.equal(run('/usr/bin/git',['--no-replace-objects','-C',webp,'rev-parse','HEAD'],{env:gitEnv}).trim(),'4fa21912338357f89e4fd51cf2368325b59e9bd9');
  assert.equal(run('/usr/bin/git',['--no-replace-objects','-C',webp,'status','--porcelain'],{env:gitEnv}).trim(),'');
  const patch=readFileSync(path.join(root,'platform/studio/native/mlx-serve-26.10.3.patch'),'utf8');
  const paths=[...patch.matchAll(/^diff --git a\/(.+) b\/.+$/gm)].map(match=>match[1]);
  assert(paths.length>0);
  assert.equal(run('/usr/bin/git',[...gitArgs,'diff','--no-ext-diff','HEAD','--',...paths],{env:gitEnv}),patch,'Native source differs from declared patch');
  assert.deepEqual(run('/usr/bin/git',[...gitArgs,'diff','--name-only','HEAD'],{env:gitEnv}).trim().split('\n').sort(),[...paths].sort());
  for(const name of ['backend_lifetime.zig','request_ownership.zig','control_protocol.zig','control_transport.zig','device_owner.zig','startup_guard.zig'])copyFileSync(path.join(root,'platform/studio/native',name),path.join(source,'src',name));
  for(const name of ['device_owner_barrier.cpp','device_owner_barrier.h'])copyFileSync(path.join(root,'platform/studio/native',name),path.join(source,'lib',name));
 }else{
  run(process.execPath,[path.join(root,'scripts/check-platform-native-sema.mjs'),'--source',source,'--zig',zig,'--webp-source',webp]);
 }
 const prefix=path.join(scratch,'webp'),lib=path.join(prefix,'lib');
 mkdirSync(lib,{recursive:true,mode:0o700});
 for(const name of ['libwebp.dylib','libsharpyuv.dylib'])copyFileSync(path.join(bundle,name),path.join(lib,name));
 for(const name of readdirSync(path.join(webp,'src/webp')).filter(name=>/^[a-z_]+\.h$/.test(name))){
  mkdirSync(path.join(prefix,'include/webp'),{recursive:true,mode:0o700});
  copyFileSync(path.join(webp,'src/webp',name),path.join(prefix,'include/webp',name));
 }
 // The original copied library's ID is an unavailable Homebrew pathname.
 // Change/sign ONLY this disposable copy, never the installed framework.
 run('/usr/bin/install_name_tool',['-id','@rpath/libwebp.dylib',path.join(lib,'libwebp.dylib')]);
 run('/usr/bin/codesign',['--force','--sign','-',path.join(lib,'libwebp.dylib')]);
 const metal=path.join(scratch,'apple-metal');mkdirSync(metal);
 run('/usr/bin/unzip',['-q',metalZip,'-d',metal]); // Exact reviewed archive hash above.
 for(const name of ['libmlx.dylib','libmlxc.dylib','libjaccl.dylib','mlx.metallib'])stage(path.join(bundle,name),path.join(source,'lib/mlx/lib',name));
 if(mlxDependency){
  mkdirSync(mlxLibraries,{mode:0o700});
  for(const name of ['libmlx.dylib','mlx.metallib','libjaccl.dylib'])stage(mlxDependency.libraries[name],path.join(mlxLibraries,name));
  stage(path.join(bundle,'libmlxc.dylib'),path.join(mlxLibraries,'libmlxc.dylib'));
 }
 stage(path.join(source,'lib/mlx-src/mlx'),path.join(source,'lib/mlx/include/mlx'));
 stage(path.join(source,'lib/mlxc-src/mlx/c'),path.join(source,'lib/mlx/include/mlx/c'));
 stage(path.join(metal,'metal-cpp'),path.join(source,'lib/mlx/include/metal_cpp'));
 let ownerLog='';
 if(!functionalBuildOnly){
 // Independent genuine C++/MLX ABI primitive, CPU by default. Optional
 // --empty-gpu creates/syncs one empty GPU stream, never arrays/kernels/models.
 // This does not modify the upstream graph or claim device-terminal authority.
 const ownerProbe=path.join(scratch,'owner-stream-probe');
 run(zig,['c++','-std=c++20','-O2','-UNDEBUG','-I',path.join(source,'lib/mlx/include'),'-I',path.join(source,'lib/mlxc-src'),
  path.join(root,'platform/studio/native/device_owner_barrier.cpp'),path.join(root,'platform/studio/native/device_owner_barrier_test.cpp'),
  '-L',mlxLibraries,'-lmlxc','-lmlx','-Wl,-rpath,'+mlxLibraries,'-o',ownerProbe]);
 const negative=spawnSync(ownerProbe,['--prove-failure'],{encoding:'utf8',timeout:5000,maxBuffer:4096});
 assert.equal(negative.status,77,'optimized C++ fixture checks became inert');
 ownerLog=run(ownerProbe,[])+run(ownerProbe,['--assigned-global-default'])+run(ownerProbe,['--two-owners'])+run(ownerProbe,['--c-api-handle'])+run(ownerProbe,['--c-api-defaults'])+run(ownerProbe,['--registry-hold']);
 const ownerEpochProbe=path.join(scratch,'owner-epoch-probe');
 run(zig,['c++','-std=c++20','-O2','-UNDEBUG','-I',path.join(source,'lib/mlx/include'),'-I',path.join(source,'lib/mlxc-src'),
  path.join(root,'platform/studio/native/device_owner_epoch_test.cpp'),'-L',mlxLibraries,'-lmlxc','-lmlx','-Wl,-rpath,'+mlxLibraries,'-o',ownerEpochProbe]);
 ownerLog+=run(ownerEpochProbe,[]);
 if(args[8]==='--empty-gpu') {
  const gpuLog=run(ownerProbe,['--gpu-empty'],{env:{...env,FIOS_NATIVE_EMPTY_GPU_FIXTURE:'isolated-source-fixture'}});
  assert(gpuLog.includes('PASS: genuine empty GPU stream'),'Explicit empty-GPU run did not execute');
  ownerLog+=gpuLog;
 }
 }
 const reviewedGraph=readFileSync(path.join(source,'build.zig'),'utf8');
 let graph=bindDs4SourceBuildGraph(reviewedGraph,ds4Dependency);
 const guards='    if (target.result.os.tag == .macos) {\n        if (webp_prefix) |dir| verifyCopiedDeps(b, dir) else verifyBrewDeps(b);\n        verifyMlxStage(b);\n    }\n';
 assert.equal(graph.split(guards).length,2);
 graph=graph.replace(guards,'    // SOURCE FIXTURE ONLY: real copied deps, NO upstream staging/release attestation.\n');
 if(mlxDependency){
  const libraryEdge='module.addLibraryPath(b.path("lib/mlx/lib"));';assert.equal(graph.split(libraryEdge).length,2);
  graph=graph.replace(libraryEdge,'module.addLibraryPath(.{ .cwd_relative = '+JSON.stringify(mlxLibraries)+' });');
  const participant=path.join(scratch,'source-mlx-participants.cpp');
  writeFileSync(participant,'#include '+JSON.stringify(path.join(mlxDependency.source,'mlx/stream.h'))+'\n#include '+JSON.stringify(path.join(root,'platform/studio/native/device_owner_barrier.h'))+'\n'+participantBytes,{mode:0o600});
  const first='    const exe = b.addExecutable(.{';assert.equal(graph.split(first).length,3);
  graph=graph.replace(first,'    mod.addCSourceFile(.{ .file = .{ .cwd_relative = '+JSON.stringify(participant)+' }, .flags = &.{"-std=c++20"} });\n'+first);
 }
 const exe='    const exe = b.addExecutable(.{';
 assert.equal(graph.split(exe).length,3);
 graph=graph.replace(exe,['mlx','llama'].map(name=>`    mod.addRPath(.{ .cwd_relative = ${JSON.stringify(name==='mlx'?mlxLibraries:path.join(source,'lib',name,'lib'))} });`).join('\n')+'\n'+exe);
 const install='    b.installArtifact(exe);';
 graph=graph.replace(install,install+'\n    b.step("fios-linked-build", "Disposable linked native source fixture").dependOn(&b.addInstallArtifact(exe, .{}).step);');
 const tests='    const unit_tests = b.addTest(.{\n        .root_module = test_mod,\n        .filters = if (test_filter) |f| &.{f} else &.{},\n    });';
 assert.equal(graph.split(tests).length,2);
 graph=graph.replace(tests,tests.replace('.filters = if (test_filter) |f| &.{f} else &.{},','.filters = &.{"fios native cleanup", "fios native admission refusal", "the route-existence 404", "each connection thread handle", "fios registry teardown", "fios loaded model teardown", "fios retained CPU cleanup", "fios resident unload", "fios ds4 snapshot", "fios llama operations", "fios ds4 engine operations", "fios ds4 checked close refusal", "fios ds4 checked session refusal"},'));
 const runner='    const run_unit_tests = b.addRunArtifact(unit_tests);\n    // A filtered run is a targeted one';
 assert.equal(graph.split(runner).length,2);
 graph=graph.replace(runner,'    const run_unit_tests = b.addRunArtifact(unit_tests);\n    run_unit_tests.has_side_effects = true;\n    b.step("fios-linked-test", "Only CPU native ownership cleanup test").dependOn(&run_unit_tests.step);\n    // A filtered run is a targeted one');
 writeFileSync(generated,graph,{flag:'wx',mode:0o600});written=true;
 schedulerOriginal=readFileSync(schedulerFile,'utf8');registryOriginal=readFileSync(registryFile,'utf8');serverOriginal=readFileSync(serverFile,'utf8');
 ds4Original=readFileSync(ds4File,'utf8');
 mutationOriginal=trimMutation?readFileSync(llamaFile,'utf8'):snapshotMutation?ds4Original:nativeRefusalMutation?serverOriginal:registryMutation?registryOriginal:schedulerOriginal;
 if(mutation){
  assert.equal(readdirSync(source).filter(name=>/^fios-linked-[0-9a-f-]+\.zig$/.test(name)).length,1,'Mutation requires exclusive disposable source use');
  let variant=mutationOriginal,pin,replacement;
  if(trimMutation){
   pin='fn trimCleared(status: i32) Error!bool {\n    return switch (status) {\n        0 => false,\n        1 => true,\n        else => Error.LifetimeUnavailable,\n    };\n}';
   replacement=pin.replace('else => Error.LifetimeUnavailable','else => false');
  }else if(snapshotMutation){
   pin='    pub fn tryFree(self: *Ds4Snapshot) bool {\n        const closing = self.fios_lifetime.beginClose(null) catch return false;\n        if (!self.fios_lifetime.commitClose(closing)) return false;';
   replacement='    pub fn tryFree(self: *Ds4Snapshot) bool { // Deliberate live-buffer custody bypass.';
  }else if(residentUnloadMutation){
   pin='    pub fn fiosCanUnloadResident(self: *LoadedModel) bool {\n        return !self.fios_pending_load_reader.load(.acquire) and self.fiosMayDeinit();';
   replacement='    pub fn fiosCanUnloadResident(self: *LoadedModel) bool {\n        if (self.fios_pending_load_reader.load(.acquire)) return false;\n        _ = self.fiosMayDeinit(); return true; // Deliberate resident-custody bypass.';
  }else if(retainedCpuMutation){
   pin='    pub fn releaseRetainedCpuState(self: *LoadedModel) bool {\n        if (!self.fiosCanReplaceCpuState()) return false;';
   replacement='    pub fn releaseRetainedCpuState(self: *LoadedModel) bool {\n        _ = self.fiosCanReplaceCpuState(); // Deliberate borrowed CPU-state cleanup bypass.';
  }else if(loadedTeardownMutation){
   pin='    pub fn deinit(self: *LoadedModel) bool {\n        if (!self.fiosPrepareDestruction()) return false;';
   replacement='    pub fn deinit(self: *LoadedModel) bool {\n        _ = self.fiosPrepareDestruction(); // Deliberate borrowed-model destruction bypass.';
  }else if(teardownMutation){
   pin='        if (!self.fiosBeginTeardown()) return;';
   replacement='        _ = self.fiosBeginTeardown(); // Deliberate held-registry destruction bypass.';
  }else if(nativeRefusalMutation){
   pin='        error.ModelConflict => try sendErrorResponse(allocator, stream, "409 Conflict", "native_model_conflict", "Conflicting native model work is still owned", 409),';
   replacement='        error.ModelConflict => return false, // Deliberately omit structured native refusal.';
  }else if(textOriginMutation){
   pin='self.held = try source.retainTokens(sch.io, tokens[0..count]);';
   replacement='self.held = try source.retainTokens(sch.io, tokens[0..1]); // Deliberately omit other text origins.';
  }else if(generationOriginMutation){
   pin='fn runGenJobs(reqs: []*GenRequest) void {\n    const had_error = mlx.errorPending();';
   replacement=pin+'\n    if (fios_ownership.current_group) |tokens| fios_ownership.current_group = tokens[0..1]; // Deliberately lose other merged origins.';
  }else if(encoderActiveMutation){
   pin='        if (scope.token) |token| try scope.tracker.?.active(sch.io, token);';
   replacement='        if (scope.token) |token| _ = token; // Deliberately omit active encoder ownership.';
  }else if(actorLoadMutation){
   pin='            const token = try source.reservePreparation(sch.io, parent, model);';
   replacement='            const token = try source.enter(sch.io); _ = parent; _ = model; // Deliberate actor preparation guard bypass.';
  }else if(loadPreparationMutation){
   pin='        const fios_preparation = if (fios_tracker) |tracker| try tracker.reservePreparation(self.io, fios_ownership.current, entry.id) else null;';
   replacement='        const fios_preparation: ?fios_ownership.Token = null; // Deliberate real load/preparation bypass.';
  }else if(evictionMutation){
   pin='            entry.fios_request_eviction = tracker.beginModelMutation(self.io, entry.id) catch return false;';
   replacement='            _ = tracker; // Deliberate request-owner eviction bypass.';
  }else if(frontdoorKind==='stub'){
   pin='        // Caller holds mutex, or single-threaded initialization.\n        if (self.fios_access_ticket != 0) return error.RegistryHeld;';replacement='        // Deliberately bypass the real stub frontdoor guard.';
  }else if(frontdoorKind==='path'||frontdoorKind==='scan'){
   const signature=frontdoorKind==='path'?'    pub fn registerByPath(self: *ModelRegistry, io: std.Io, abs_path: []const u8, id: ?[]const u8) ![]const u8 {':'    pub fn rescan(self: *ModelRegistry) !u32 {';
   const call=frontdoorKind==='path'?'self.registerByPathPrepared(io, abs_path, id)':'self.rescanPrepared()';
   pin=signature+'\n        const preparing = try self.fiosBeginMutation();\n        defer _ = preparing.finish();\n        return '+call+' catch |err| { preparing.failed(err); return err; };';
   replacement=signature+'\n        return '+call+'; // Deliberate real preparation/frontdoor bypass.';
  }else if(clearPreparationMutation){
   const clear='        self.fios_mutation_slots[lease.slot] = .{};';assert.equal(variant.split(clear).length,2);
   variant=variant.replace(clear,'        // Deliberately cleared before the exhaustion preflight instead.');
   pin='        if (!self.fiosMutationMatchesLocked(lease)) return false;';replacement=pin+'\n'+clear;
  }else{
   pin=preparationMutation?'sch.registry.fios_mutation_count != 0 or ':accessMutation?'        if (owner == 0 or owner != fios_pin_owner or ticket == 0 or self.fios_access_ticket != ticket or\n':parkedMutation?'    sch.fios_model_pins.adopt(&model_pins) catch { finishFiosOwnerProbe(sch, .{}); return; };':'        _ = entry.refcount.fetchAdd(1, .acq_rel);\n        sch.registry.fiosProbeChangedLocked();';
   replacement=preparationMutation?'':accessMutation?pin.replace('owner != fios_pin_owner or ',''):parkedMutation?pin+'\n    defer sch.fios_model_pins.release(sch); // Deliberate premature parked-reference release.':'        // Negative fixture: deliberately omit the model reference.\n        _ = entry;\n        sch.registry.fiosProbeChangedLocked();';
  }
  if(residentUnloadMutation){
   const actual='    pub fn unloadResident(self: *LoadedModel) bool {\n        if (!self.fiosPrepareDestruction()) return false;';
   assert.equal(variant.split(actual).length,2);
   variant=variant.replace(actual,'    pub fn unloadResident(self: *LoadedModel) bool {\n        _ = self.fiosPrepareDestruction(); // Deliberate actual-unload refusal bypass.');
  }
  assert.equal(variant.split(pin).length,2);mutated=true;
  writeFileSync(mutationFile,variant.replace(pin,replacement));
 }
 const options=['-j2','--build-file',filename,'--prefix',path.join(scratch,'output'),'-Dmas=true','-Dversion=26.10.3-fios-source-fixture',`-Dwebp-prefix=${prefix}`,...(mimoSource?[`-Dmlx-stream-dir=${mimoSource}`]:[]),'--summary','all'];
 // No C/object/library inputs removed. Root-only deliberately omits the
 // executable/HTTP/manager claim; its genuine test root still executes.
 const buildLog=rootOnly?'':run('/usr/bin/nice',['-n','10',zig,'build','fios-linked-build','-Doptimize=ReleaseFast',...options],{cwd:source});
 let testLog;
 const testArgs=['-n','10',zig,'build','fios-linked-test','-Doptimize=ReleaseSafe',...options];
 if(functionalBuildOnly){
  testLog='FUNCTIONAL BUILD ONLY: prior probe, runtime-test and HTTP matrices not executed.\n';
 }else if(mutation){
  const result=spawnSync('/usr/bin/nice',testArgs,{cwd:source,env,encoding:'utf8',timeout:600000,maxBuffer:16*1024*1024});
  testLog=(result.stdout??'')+(result.stderr??'');
  assert.equal(result.status,1,'Deliberate boundary mutation must fail actual optimized runtime tests');
  assert.match(testLog,loadedTeardownMutation?/15 pass, 2 fail \(17 total\)/:/16 pass, 1 fail \(17 total\)/,'Compilation/linkage failures are not mutation evidence');
  assert.match(testLog,trimMutation?/arch\.llama\.test\.fios llama operations refuse unavailable lifetime before any backend access/:snapshotMutation?/arch\.ds4\.test\.fios ds4 snapshot refuses destruction while its CPU buffer is borrowed/:residentUnloadMutation?/scheduler\.test\.fios resident unload refuses borrowed model without accounting success/:retainedCpuMutation?/scheduler\.test\.fios retained CPU cleanup preserves borrowed configuration/:loadedTeardownMutation?/scheduler\.test\.fios loaded model teardown preserves borrowed metadata/:teardownMutation?/scheduler\.test\.fios registry teardown preserves held metadata before any destruction/:nativeRefusalMutation?/server\.test\.fios native admission refusal writes a bounded structured response/:/scheduler\.test\.fios native cleanup retains request and model after connection release/);
  const failureMarker=trimMutation?/FIO_LLAMA_TRIM_REFUSAL_ACCEPTED/:snapshotMutation?/FIO_DS4_SNAPSHOT_DROPPED_BORROWED_BUFFER/:residentUnloadMutation?/FIO_RESIDENT_REFUSAL_REPORTED_MEMORY_FREE/:retainedCpuMutation?/FIO_RETAINED_CPU_STATE_DROPPED_BORROW/:loadedTeardownMutation?/FIO_LOADED_MODEL_TEARDOWN_DROPPED_BORROW/:teardownMutation?/FIO_REGISTRY_TEARDOWN_DROPPED_HELD_STATE/:textOriginMutation?/FIO_TEXT_BATCH_OWNER_LOST/:generationOriginMutation?/FIO_MERGED_GENERATION_OWNER_LOST/:encoderActiveMutation?/FIO_ENCODER_ACTOR_NOT_ACTIVE/:actorLoadMutation?/FIO_ACTOR_LOAD_PREPARATION_BYPASS/:nativeRefusalMutation?/FIO_NATIVE_REFUSAL_NOT_STRUCTURED/:loadPreparationMutation?/FIO_CONFLICTING_LOAD_PREPARATION_ACCEPTED/:evictionMutation?/FIO_REQUEST_OWNER_EVICTED/:frontdoorKind?new RegExp(`FIO_REGISTRY_${frontdoorKind.toUpperCase()}_FRONTDOOR_BYPASS`):preparationMutation?/FIO_REGISTRY_ACTIVE_PREPARATION_ACCEPTED/:clearPreparationMutation?/FIO_REGISTRY_PREPARATION_RECORD_CLEARED_ON_EXHAUSTION/:accessMutation?/expected false, found true/:/expected 1, found 0/;
  assert.match(testLog,failureMarker,'Mutation must fail its exact actual runtime boundary assertion');
  if(loadedTeardownMutation){
   assert.match(testLog,/model_registry\.test\.fios loaded model teardown preserves partial registry map on refusal/);
   assert.match(testLog,/FIO_PARTIAL_REGISTRY_TEARDOWN_DROPPED_BORROW/);
  }
  writeFileSync(mutationFile,mutationOriginal);mutated=false;
  testLog+=trimMutation?'\nPASS: optimized native trim-status refusal omission reaches its exact CPU runtime witness; source restored; no model or terminal authority.\n':snapshotMutation?'\nPASS: borrowed snapshot destruction bypass fails its allocator-observed CPU-buffer witness; source restored; no model or terminal authority.\n':residentUnloadMutation?'\nPASS: optimized resident unload bypass fails its exact accounting assertion; source restored; no model or terminal authority.\n':retainedCpuMutation?'\nPASS: actual borrowed CPU-state cleanup bypass fails its allocator-observed runtime witness; exact source restored; no model/terminal authority.\n':loadedTeardownMutation?'\nPASS: actual borrowed LoadedModel destructor bypass fails the allocator-observed runtime witness; exact source restored; no backend/terminal authority.\n':teardownMutation?'\nPASS: actual held-registry teardown bypass fails its allocator-observed runtime witness; exact source restored; metadata only, no terminal authority.\n':textOriginMutation?'\nPASS: text batch origin omission fails its precise runtime assertion; exact source restored; no model/terminal authority.\n':generationOriginMutation?'\nPASS: actual merged callback origin omission fails its precise runtime assertion; exact source restored; no model/terminal authority.\n':encoderActiveMutation?'\nPASS: actual encoder actor active-transition omission fails its precise runtime assertion; exact source restored; no model/terminal authority.\n':actorLoadMutation?'\nPASS: actual actor preparation guard bypass fails its precise runtime assertion; exact source restored; no backend/model/terminal authority.\n':nativeRefusalMutation?'\nPASS: optimized actual socket-response omission fails its exact runtime assertion; exact server bytes restored; no terminal authority.\n':loadPreparationMutation?'\nPASS: optimized actual scheduler load/preparation bypass fails its exact runtime assertion; exact source bytes restored; no terminal authority.\n':evictionMutation?'\nPASS: optimized actual registry eviction bypass fails its exact request-owner runtime assertion; exact source bytes restored; no terminal authority.\n':(frontdoorKind||preparationMutation||clearPreparationMutation)?`\nPASS: optimized actual registry ${frontdoorKind??(preparationMutation?'active preparation visibility':'exhaustion-before-record-clear')} boundary fails its precise runtime marker; exact scheduler/registry bytes restored; no terminal authority.\n`:accessMutation?'\nPASS: optimized copied-ticket foreign-owner guard removal fails the actual registry-release assertion; exact source bytes restored; no terminal authority.\n':parkedMutation?'\nPASS: optimized premature parked-reference release fails the actual parked-model refcount assertion; source bytes restored; no terminal authority.\n':'\nPASS: optimized dropped-model-ref mutation fails the actual registry-borrow fixture; source bytes restored; no terminal authority.\n';
 }else {
  const result=spawnSync('/usr/bin/nice',testArgs,{cwd:source,env,encoding:'utf8',timeout:600000,maxBuffer:16*1024*1024});
  testLog=(result.stdout??'')+(result.stderr??'');
  if(result.status!==0)process.stderr.write(testLog);
  if(result.error)throw result.error;
  assert.equal(result.status,0,'Genuine native root validation failed');
  assert.match(testLog,/17\/17 tests passed/,'Every declared root case must execute; a compiled but filtered-out test is not evidence');
 }
 let binary=path.join(scratch,'output/bin/mlx-serve'),digest=rootOnly?null:sha(binary),review;
 if(reviewOutput){
  assert(!rootOnly,'Review output requires an actual executable build');
  const libraries=Object.fromEntries(Object.keys(runtime).map(name=>[name,path.join(name==='libwebp.dylib'||name==='libsharpyuv.dylib'?lib:bundle,name)]));
  libraries['libllama.dylib']=path.join(source,'lib/llama/lib/libllama.dylib');
  if(mlxDependency)for(const name of ['libmlx.dylib','mlx.metallib','libjaccl.dylib'])libraries[name]=mlxDependency.libraries[name];
  review=stageNativeReview({directory:reviewOutput,binary,libraries,inputs:{verification_mode:functionalBuildOnly?'functional_build_only':'full_source_fixture',root_tests_rerun:!functionalBuildOnly,http_checks_rerun:!functionalBuildOnly,native_control_protocol_versions:[2,3],companion_sources:Object.fromEntries(['backend_lifetime.zig','request_ownership.zig','control_protocol.zig','control_transport.zig','device_owner.zig','startup_guard.zig','device_owner_barrier.cpp','device_owner_barrier.h'].map(name=>[name,sha(path.join(root,'platform/studio/native',name))])),native_base:'046b647686419df06c6c7132fb1d15d76185c3e5',root_patch_sha256:sha(path.join(root,'platform/studio/native/mlx-serve-26.10.3.patch')),runtime_inputs:runtime,runtime_input_scope:mlxDependency?'readonly_installed_bundle_bracket_not_selected_runtime_provenance':'declared_installed_bundle_inputs_only',mimo_candidate:mimoReceipt,ds4_source_dependency:ds4Dependency,mlx_source_dependency:mlxDependency,source_component_diagnostics:!!mlxDependency,mlx_participant_source_sha256:participantBytes?createHash('sha256').update(participantBytes).digest('hex'):null}});
  binary=review.binary;digest=review.sha256;
 }
 const httpLog=rootOnly||functionalBuildOnly?'':run(process.execPath,[path.join(root,'scripts/check-platform-native-http.mjs'),'--isolated','--binary',binary,'--sha256',digest]);
 if(mlxDependency&&!functionalBuildOnly)assert(httpLog.includes('SOURCE_COMPONENT_PROVIDER_AVAILABLE'),'Private component metadata was not actually available');
 if(mlxDependency){assert.deepEqual(verifyMlxSourceReview(...mlxDependencyConfig),mlxDependency);assert.equal(readFileSync(participantFile,'utf8'),participantBytes);}
 for(const [name,expected]of Object.entries(runtime))assert.equal(sha(path.join(bundle,name)),expected,'installed dependency changed');
 assert.equal(readFileSync(path.join(source,'build.zig'),'utf8'),reviewedGraph,'fixture changed reviewed build graph');
 assert.equal(readFileSync(schedulerFile,'utf8'),schedulerOriginal,'fixture changed reviewed scheduler source');
 assert.equal(readFileSync(registryFile,'utf8'),registryOriginal,'fixture changed reviewed registry source');
 assert.equal(readFileSync(serverFile,'utf8'),serverOriginal,'fixture changed reviewed server source');
 assert.equal(readFileSync(ds4File,'utf8'),ds4Original,'fixture changed reviewed DS4 source');
 assert.deepEqual(verifyMimo(),mimoReceipt,'candidate input changed during combined fixture');
 const reviewReceipt=review?finishNativeReview(review,{emptyModelValidation:functionalBuildOnly?'not_run':'passed'}):null;
 console.log(ownerLog+buildLog+testLog+httpLog);
 assert.deepEqual(verifyDs4SourceBuild(ds4DependencyConfig),ds4Dependency);
 console.log(JSON.stringify({source_fixture_only:true,verification_mode:functionalBuildOnly?'functional_build_only':'full_source_fixture',root_tests_rerun:!functionalBuildOnly,http_checks_rerun:!functionalBuildOnly,root_tests_only:rootOnly,expected_runtime_mutation:mutation,request_eviction_mutation:evictionMutation,load_preparation_mutation:loadPreparationMutation,actor_load_preparation_mutation:actorLoadMutation,encoder_active_mutation:encoderActiveMutation,generation_origin_mutation:generationOriginMutation,text_origin_mutation:textOriginMutation,native_refusal_mutation:nativeRefusalMutation,parked_reference_mutation:parkedMutation,foreign_access_release_mutation:accessMutation,preparation_visibility_mutation:preparationMutation,preparation_clear_mutation:clearPreparationMutation,registry_frontdoor_mutation:frontdoorKind??null,registry_teardown_mutation:teardownMutation,loaded_model_teardown_mutation:loadedTeardownMutation,retained_cpu_cleanup_mutation:retainedCpuMutation,resident_unload_mutation:residentUnloadMutation,ds4_snapshot_mutation:snapshotMutation,llama_trim_status_mutation:trimMutation,upstream_release_attestation:false,native_inference:false,coverage:'unknown',fixture_sha256:digest,private_review:reviewReceipt,mimo_candidate:mimoReceipt,ds4_source_dependency:ds4Dependency,mlx_source_dependency:mlxDependency,runtime_inputs:runtime,runtime_input_scope:mlxDependency?'readonly_installed_bundle_bracket_not_selected_runtime_provenance':'declared_installed_bundle_inputs_only'}));
}finally{
 if(mutated)writeFileSync(mutationFile,mutationOriginal);
 if(written)rmSync(generated);
 rmSync(scratch,{recursive:true,force:true});
}
