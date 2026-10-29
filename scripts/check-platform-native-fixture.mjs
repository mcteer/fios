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
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const args=process.argv.slice(2);
assert(process.platform==='darwin' && process.getuid()!==0);
assert((args.length===8 || (args.length===9 && ['--empty-gpu','--root-tests-only','--mutation-request-eviction-guard','--mutation-drop-model-pins','--mutation-drop-parked-pins','--mutation-access-foreign-release','--mutation-drop-registry-preparation','--mutation-clear-registry-preparation','--mutation-registry-stub-frontdoor','--mutation-registry-path-frontdoor','--mutation-registry-scan-frontdoor'].includes(args[8]))) && args[0]==='--source' && args[2]==='--zig' && args[4]==='--webp-source' && args[6]==='--metal-cpp-zip' && [args[1],args[3],args[5],args[7]].every(path.isAbsolute),
 'usage: check-platform-native-fixture.mjs --source ABS_CHECKOUT --zig ABS_ZIG --webp-source ABS_WEBP_1_6_0 --metal-cpp-zip ABS_APPLE_METAL_CPP_26_ZIP [--mutation-request-eviction-guard|--empty-gpu|--root-tests-only|--mutation-drop-model-pins|--mutation-drop-parked-pins|--mutation-access-foreign-release|--mutation-drop-registry-preparation|--mutation-clear-registry-preparation|--mutation-registry-stub-frontdoor|--mutation-registry-path-frontdoor|--mutation-registry-scan-frontdoor]');
const parkedMutation=args[8]==='--mutation-drop-parked-pins',accessMutation=args[8]==='--mutation-access-foreign-release';
const preparationMutation=args[8]==='--mutation-drop-registry-preparation',clearPreparationMutation=args[8]==='--mutation-clear-registry-preparation';
const frontdoorKind=['stub','path','scan'].find(kind=>args[8]===`--mutation-registry-${kind}-frontdoor`);
const evictionMutation=args[8]==='--mutation-request-eviction-guard';
const registryMutation=evictionMutation||accessMutation||clearPreparationMutation||!!frontdoorKind;
const mutation=evictionMutation||parkedMutation||accessMutation||preparationMutation||clearPreparationMutation||!!frontdoorKind||args[8]==='--mutation-drop-model-pins',rootOnly=mutation||args[8]==='--root-tests-only';
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
const env={PATH:'/usr/bin:/bin',HOME:scratch,LANG:'C',LC_ALL:'C',TMPDIR:scratch,ZIG_GLOBAL_CACHE_DIR:path.join(homedir(),'.cache/zig')};
const run=(file,argv,options={})=>execFileSync(file,argv,{encoding:'utf8',env,timeout:600000,maxBuffer:16*1024*1024,...options});
const filename=`fios-linked-${randomUUID()}.zig`,generated=path.join(source,filename);
const schedulerFile=path.join(source,'src/scheduler.zig'),registryFile=path.join(source,'src/model_registry.zig');
const mutationFile=registryMutation?registryFile:schedulerFile;
let written=false,mutated=false,schedulerOriginal,registryOriginal,mutationOriginal;
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
 // Fail cheap on integration-script syntax before expensive native codegen.
 run(process.execPath,['--check',path.join(root,'scripts/check-platform-native-http.mjs')]);
 // Before staging: verifies commits/submodules, exact reviewed fixed-file
 // build/roots/llama-context bridge patch and companions, preserved staging
 // guards and real Zig-root Sema.
 run(process.execPath,[path.join(root,'scripts/check-platform-native-sema.mjs'),'--source',source,'--zig',zig,'--webp-source',webp]);
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
 stage(path.join(source,'lib/mlx-src/mlx'),path.join(source,'lib/mlx/include/mlx'));
 stage(path.join(source,'lib/mlxc-src/mlx/c'),path.join(source,'lib/mlx/include/mlx/c'));
 stage(path.join(metal,'metal-cpp'),path.join(source,'lib/mlx/include/metal_cpp'));
 // Independent genuine C++/MLX ABI primitive, CPU by default. Optional
 // --empty-gpu creates/syncs one empty GPU stream, never arrays/kernels/models.
 // This does not modify the upstream graph or claim device-terminal authority.
 const ownerProbe=path.join(scratch,'owner-stream-probe');
 run(zig,['c++','-std=c++20','-O2','-UNDEBUG','-I',path.join(source,'lib/mlx/include'),'-I',path.join(source,'lib/mlxc-src'),
  path.join(root,'platform/studio/native/device_owner_barrier.cpp'),path.join(root,'platform/studio/native/device_owner_barrier_test.cpp'),
  '-L',path.join(source,'lib/mlx/lib'),'-lmlxc','-lmlx','-Wl,-rpath,'+path.join(source,'lib/mlx/lib'),'-o',ownerProbe]);
 const negative=spawnSync(ownerProbe,['--prove-failure'],{encoding:'utf8',timeout:5000,maxBuffer:4096});
 assert.equal(negative.status,77,'optimized C++ fixture checks became inert');
 let ownerLog=run(ownerProbe,[])+run(ownerProbe,['--assigned-global-default'])+run(ownerProbe,['--two-owners'])+run(ownerProbe,['--c-api-handle'])+run(ownerProbe,['--c-api-defaults'])+run(ownerProbe,['--registry-hold']);
 const ownerEpochProbe=path.join(scratch,'owner-epoch-probe');
 run(zig,['c++','-std=c++20','-O2','-UNDEBUG','-I',path.join(source,'lib/mlx/include'),'-I',path.join(source,'lib/mlxc-src'),
  path.join(root,'platform/studio/native/device_owner_epoch_test.cpp'),'-L',path.join(source,'lib/mlx/lib'),'-lmlxc','-lmlx','-Wl,-rpath,'+path.join(source,'lib/mlx/lib'),'-o',ownerEpochProbe]);
 ownerLog+=run(ownerEpochProbe,[]);
 if(args[8]==='--empty-gpu') {
  const gpuLog=run(ownerProbe,['--gpu-empty'],{env:{...env,FIOS_NATIVE_EMPTY_GPU_FIXTURE:'isolated-source-fixture'}});
  assert(gpuLog.includes('PASS: genuine empty GPU stream'),'Explicit empty-GPU run did not execute');
  ownerLog+=gpuLog;
 }
 const reviewedGraph=readFileSync(path.join(source,'build.zig'),'utf8');
 let graph=reviewedGraph;
 const guards='    if (target.result.os.tag == .macos) {\n        if (webp_prefix) |dir| verifyCopiedDeps(b, dir) else verifyBrewDeps(b);\n        verifyMlxStage(b);\n    }\n';
 assert.equal(graph.split(guards).length,2);
 graph=graph.replace(guards,'    // SOURCE FIXTURE ONLY: real copied deps, NO upstream staging/release attestation.\n');
 const exe='    const exe = b.addExecutable(.{';
 assert.equal(graph.split(exe).length,3);
 graph=graph.replace(exe,['mlx','llama'].map(name=>`    mod.addRPath(.{ .cwd_relative = ${JSON.stringify(path.join(source,'lib',name,'lib'))} });`).join('\n')+'\n'+exe);
 const install='    b.installArtifact(exe);';
 graph=graph.replace(install,install+'\n    b.step("fios-linked-build", "Disposable linked native source fixture").dependOn(&b.addInstallArtifact(exe, .{}).step);');
 const tests='    const unit_tests = b.addTest(.{\n        .root_module = test_mod,\n        .filters = if (test_filter) |f| &.{f} else &.{},\n    });';
 assert.equal(graph.split(tests).length,2);
 graph=graph.replace(tests,tests.replace('.filters = if (test_filter) |f| &.{f} else &.{},','.filters = &.{"fios native cleanup", "the route-existence 404", "each connection thread handle"},'));
 const runner='    const run_unit_tests = b.addRunArtifact(unit_tests);\n    // A filtered run is a targeted one';
 assert.equal(graph.split(runner).length,2);
 graph=graph.replace(runner,'    const run_unit_tests = b.addRunArtifact(unit_tests);\n    run_unit_tests.has_side_effects = true;\n    b.step("fios-linked-test", "Only CPU native ownership cleanup test").dependOn(&run_unit_tests.step);\n    // A filtered run is a targeted one');
 writeFileSync(generated,graph,{flag:'wx',mode:0o600});written=true;
 schedulerOriginal=readFileSync(schedulerFile,'utf8');registryOriginal=readFileSync(registryFile,'utf8');
 mutationOriginal=registryMutation?registryOriginal:schedulerOriginal;
 if(mutation){
  assert.equal(readdirSync(source).filter(name=>/^fios-linked-[0-9a-f-]+\.zig$/.test(name)).length,1,'Mutation requires exclusive disposable source use');
  let variant=mutationOriginal,pin,replacement;
  if(evictionMutation){
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
  assert.equal(variant.split(pin).length,2);mutated=true;
  writeFileSync(mutationFile,variant.replace(pin,replacement));
 }
 const options=['--build-file',filename,'--prefix',path.join(scratch,'output'),'-Dmas=true','-Dversion=26.10.3-fios-source-fixture',`-Dwebp-prefix=${prefix}`,'--summary','all'];
 // No C/object/library inputs removed. Root-only deliberately omits the
 // executable/HTTP/manager claim; its genuine test root still executes.
 const buildLog=rootOnly?'':run('/usr/bin/nice',['-n','10',zig,'build','fios-linked-build','-Doptimize=ReleaseFast',...options],{cwd:source});
 let testLog;
 const testArgs=['-n','10',zig,'build','fios-linked-test','-Doptimize=ReleaseSafe',...options];
 if(mutation){
  const result=spawnSync('/usr/bin/nice',testArgs,{cwd:source,env,encoding:'utf8',timeout:600000,maxBuffer:16*1024*1024});
  testLog=(result.stdout??'')+(result.stderr??'');
  assert.equal(result.status,1,'Deliberate boundary mutation must fail actual optimized runtime tests');
  assert.match(testLog,/5 pass, 1 fail \(6 total\)/,'Compilation/linkage failures are not mutation evidence');
  assert.match(testLog,/scheduler\.test\.fios native cleanup retains request and model after connection release/);
  const failureMarker=evictionMutation?/FIO_REQUEST_OWNER_EVICTED/:frontdoorKind?new RegExp(`FIO_REGISTRY_${frontdoorKind.toUpperCase()}_FRONTDOOR_BYPASS`):preparationMutation?/FIO_REGISTRY_ACTIVE_PREPARATION_ACCEPTED/:clearPreparationMutation?/FIO_REGISTRY_PREPARATION_RECORD_CLEARED_ON_EXHAUSTION/:accessMutation?/expected false, found true/:/expected 1, found 0/;
  assert.match(testLog,failureMarker,'Mutation must fail its exact actual runtime boundary assertion');
  writeFileSync(mutationFile,mutationOriginal);mutated=false;
  testLog+=evictionMutation?'\nPASS: optimized actual registry eviction bypass fails its exact request-owner runtime assertion; exact source bytes restored; no terminal authority.\n':(frontdoorKind||preparationMutation||clearPreparationMutation)?`\nPASS: optimized actual registry ${frontdoorKind??(preparationMutation?'active preparation visibility':'exhaustion-before-record-clear')} boundary fails its precise runtime marker; exact scheduler/registry bytes restored; no terminal authority.\n`:accessMutation?'\nPASS: optimized copied-ticket foreign-owner guard removal fails the actual registry-release assertion; exact source bytes restored; no terminal authority.\n':parkedMutation?'\nPASS: optimized premature parked-reference release fails the actual parked-model refcount assertion; source bytes restored; no terminal authority.\n':'\nPASS: optimized dropped-model-ref mutation fails the actual registry-borrow fixture; source bytes restored; no terminal authority.\n';
 }else testLog=run('/usr/bin/nice',testArgs,{cwd:source});
 const binary=path.join(scratch,'output/bin/mlx-serve'),digest=rootOnly?null:sha(binary);
 const httpLog=rootOnly?'':run(process.execPath,[path.join(root,'scripts/check-platform-native-http.mjs'),'--isolated','--binary',binary,'--sha256',digest]);
 for(const [name,expected]of Object.entries(runtime))assert.equal(sha(path.join(bundle,name)),expected,'installed dependency changed');
 assert.equal(readFileSync(path.join(source,'build.zig'),'utf8'),reviewedGraph,'fixture changed reviewed build graph');
 assert.equal(readFileSync(schedulerFile,'utf8'),schedulerOriginal,'fixture changed reviewed scheduler source');
 assert.equal(readFileSync(registryFile,'utf8'),registryOriginal,'fixture changed reviewed registry source');
 console.log(ownerLog+buildLog+testLog+httpLog);
 console.log(JSON.stringify({source_fixture_only:true,root_tests_only:rootOnly,expected_runtime_mutation:mutation,request_eviction_mutation:evictionMutation,parked_reference_mutation:parkedMutation,foreign_access_release_mutation:accessMutation,preparation_visibility_mutation:preparationMutation,preparation_clear_mutation:clearPreparationMutation,registry_frontdoor_mutation:frontdoorKind??null,upstream_release_attestation:false,native_inference:false,coverage:'unknown',fixture_sha256:digest,runtime_inputs:runtime}));
}finally{
 if(mutated)writeFileSync(mutationFile,mutationOriginal);
 if(written)rmSync(generated);
 rmSync(scratch,{recursive:true,force:true});
}
