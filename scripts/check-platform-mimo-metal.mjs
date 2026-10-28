#!/usr/bin/env node
// Actual Engine(Metal), original warm implementation and genuine native SDK.
// Tiny event-gated warm chunks only; no model/inference/production enrollment.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {createHash,randomUUID} from 'node:crypto';
import {lstatSync,mkdtempSync,readFileSync,realpathSync,rmSync,writeFileSync} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url)),args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.getuid()!==0);
assert(args.length===8&&args[0]==='--source'&&args[2]==='--zig'&&args[4]==='--mimo-source'&&args[6]==='--developer-dir'&&[1,3,5,7].every(i=>path.isAbsolute(args[i])),
 'Use --source ABS_NATIVE --zig ABS_ZIG --mimo-source ABS_SEPARATE_PINNED_PLUGIN --developer-dir ABS');
const [source,zig,mimo,developer]=[1,3,5,7].map(i=>realpathSync(args[i]));
for(const directory of [source,mimo]){const info=lstatSync(directory);assert(directory.startsWith('/private/tmp/')&&info.isDirectory()&&info.uid===process.getuid()&&(info.mode&0o022)===0);}
const env={PATH:'/usr/bin:/bin:/usr/sbin:/sbin',HOME:os.homedir(),TMPDIR:'/tmp',LC_ALL:'C',DEVELOPER_DIR:developer,GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const run=(file,argv,options={})=>execFileSync(file,argv,{env,encoding:'utf8',timeout:600000,maxBuffer:16<<20,...options});
const git=(directory,...argv)=>run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',directory,...argv]);
const sha=file=>{const info=lstatSync(file);assert(info.isFile()&&!info.isSymbolicLink());return createHash('sha256').update(readFileSync(file)).digest('hex');};
assert.equal(sha(zig),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
assert.equal(git(mimo,'rev-parse','HEAD').trim(),'fcb4011347ff80eeeb19e2a1f0180e13199c7c8b');
const patchFile=path.join(root,'platform/studio/native/mlx-stream-fcb4011-retirement.patch'),patch=readFileSync(patchFile,'utf8'),patchSHA=sha(patchFile);
assert.equal(git(mimo,'diff','--','src/arch/mimo_v2/gpu_warm.zig'),patch);assert.equal(git(mimo,'diff','--name-only').trim(),'src/arch/mimo_v2/gpu_warm.zig');
const metal=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--find','metal']).trim());run('/usr/bin/codesign',['--verify','--strict','--test-requirement','=anchor apple',metal]);
assert(run('/usr/bin/xcrun',['--sdk','macosx','metal','--version']).startsWith('Apple metal version 32023.921 '));assert.equal(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim(),'27.0');
run(process.execPath,[path.join(root,'scripts/check-platform-native.mjs'),'--source',source,'--zig',zig]);
const libraries={'libmlx.dylib':'6a5ee820afed9ce9421297260b4a9fd593749052d582c65deeca428fce61c76e','libmlxc.dylib':'6b4c9224691c2857cf7d386e75c1247cc6b0a4ae17d6ec6d1b455ec177e9929f','libjaccl.dylib':'5c6f3819b3555902ba1ab3a49550643994b49860f09e323fe42dfd6121103282','mlx.metallib':'95974b7de464ec2be7833a914ca5a53d283a70789470fd84218738fc8fcea3e1'};
const verifyLibraries=()=>{for(const [name,digest] of Object.entries(libraries)){assert.equal(sha(path.join(source,'lib/mlx/lib',name)),digest);assert.equal(sha(path.join('/Applications/MLX-Serve.app/Contents/Frameworks',name)),digest);}};
verifyLibraries();
const originalGraph=readFileSync(path.join(source,'build.zig'),'utf8');
const temporary=mkdtempSync(path.join(os.tmpdir(),'fios-009-real-mimo-')),plugin=path.join(temporary,'plugin');env.TMPDIR=temporary;
const generatedName=`fios-real-mimo-${randomUUID()}.zig`,generated=path.join(source,generatedName);
const fixtureFile=path.join(root,'platform/studio/native/mimo_real_metal_test.zig.fixture'),fixture=readFileSync(fixtureFile,'utf8');
const helperFile=path.join(root,'platform/studio/native/mimo_warm_metal_fixture_helpers.inc'),helpers=readFileSync(helperFile,'utf8');
const fixtureSHA=sha(fixtureFile),helperSHA=sha(helperFile);
const replace=(text,before,after)=>{assert.equal(text.split(before).length,2,before);return text.replace(before,after);};
try{
 run('/usr/bin/git',['clone','--quiet','--no-hardlinks','--no-checkout',mimo,plugin]);git(plugin,'checkout','--quiet','--detach','fcb4011347ff80eeeb19e2a1f0180e13199c7c8b');git(plugin,'apply',patchFile);
 const warmFile=path.join(plugin,'src/arch/mimo_v2/gpu_warm.zig'),warmOriginal=readFileSync(warmFile,'utf8');
 const cppFile=path.join(plugin,'csrc/mimo_gpu_warm.inc'),cppOriginal=readFileSync(cppFile,'utf8');assert.equal(cppOriginal,git(mimo,'show','HEAD:csrc/mimo_gpu_warm.inc'));
 let cpp=replace(cppOriginal,'#include <string>','#include <string>\n#include <atomic>');
 cpp=replace(cpp,'thread_local std::string g_error;','thread_local std::string g_error;\nstd::atomic<uint64_t> fixture_retire_calls{0};');
 cpp=replace(cpp,'struct Warm {','struct Warm {\n  MTL::SharedEvent* fixture_second = nullptr;\n  uint64_t fixture_commits = 0;\n  std::atomic<MTL::CommandBuffer*> fixture_last{nullptr};');
 cpp=replace(cpp,'  if (w == nullptr) return;','  if (w == nullptr) return;\n  if(auto* last=w->fixture_last.load())last->release();');
 cpp=replace(cpp,'  MTL::CommandBuffer* buf = w->queue->commandBufferWithUnretainedReferences();','  ++w->fixture_commits;\n  if(w->fixture_commits==2&&w->fixture_second){auto* gate=w->queue->commandBuffer();gate->encodeWait(w->fixture_second,1);gate->commit();}\n  MTL::CommandBuffer* buf = w->queue->commandBufferWithUnretainedReferences();');
 cpp=replace(cpp,'  buf->commit();\n  *cb = buf;','  buf->commit();\n  if(w->fixture_commits==2){buf->retain();w->fixture_last.store(buf);}\n  *cb = buf;');
 cpp=replace(cpp,'  buf->waitUntilCompleted();','  ++fixture_retire_calls;\n  buf->waitUntilCompleted();');
 cpp+='\n'+helpers;writeFileSync(cppFile,cpp);
 const testFile=path.join(plugin,'src/fios_real_metal.zig');writeFileSync(testFile,fixture);
 let graph=replace(originalGraph,'    if (target.result.os.tag == .macos) {\n        if (webp_prefix) |dir| verifyCopiedDeps(b, dir) else verifyBrewDeps(b);\n        verifyMlxStage(b);\n    }\n','    // SOURCE METAL FIXTURE ONLY, never a release-stage attestation.\n');
 graph=replace(graph,'    addMlxLib(b, host);\n','    addMlxLib(b, host);\n    host.addRPath(.{ .cwd_relative = '+JSON.stringify(path.join(source,'lib/mlx/lib'))+' });\n');
 graph=replace(graph,'    const m = mlxStreamPkg(b, host, mlxStreamDir(b), root, target, optimize, true);','    const m = mlxStreamPkg(b, host, mlxStreamDir(b), root, target, optimize, true);\n    m.addCMacro("FIOS_GENUINE_WARM_ENGINE_FIXTURE", "1");');
 graph=replace(graph,'macos_sdk_frameworks, "src/tests.zig", "mlx-stream-test"','macos_sdk_frameworks, "src/fios_real_metal.zig", "mlx-stream-test"');
 graph=replace(graph,'        const run = b.addRunArtifact(t);\n        test_step.dependOn(&run.step);','        const run = b.addRunArtifact(t);\n        run.has_side_effects = true;\n        test_step.dependOn(&run.step);');
 writeFileSync(generated,graph,{flag:'wx',mode:0o600});
 const execute=(optimize,expected=0,early=false)=>{const result=spawnSync('/usr/bin/nice',['-n','10',zig,'build','mlx-stream-test','--build-file',generatedName,`-Doptimize=${optimize}`,'-Dmas=true',`-Dmlx-stream-dir=${plugin}`,'-Dtest-filter=fios real metal','--summary','all'],{cwd:source,env,encoding:'utf8',timeout:600000,maxBuffer:16<<20});const output=(result.stdout??'')+(result.stderr??'');console.log(output);assert.equal(result.error,undefined);assert.equal(result.signal,null);assert.equal(result.status,expected);if(early){assert.match(output,/expected \.pending, found \.retired/);assert.match(output,/1 fail \(1 total\)/);}else{assert.match(output,/1 pass \(1 total\)/);assert(output.includes('GENUINE_MIMO_METAL chunks=2'));}};
 execute('ReleaseSafe');execute('Debug');
 const checkpoint='            self.drain();\n            _ = std.c.pthread_mutex_lock(&self.mu);\n            if (self.fios_closed.load(.seq_cst) and !self.quit.load(.seq_cst)) self.fios_ack = self.fios_sequence;\n            _ = std.c.pthread_mutex_unlock(&self.mu);\n            self.park();';
 const broken=checkpoint.replace('            self.drain();\n','').replace('            self.park();','            self.drain();\n            self.park();');
 writeFileSync(warmFile,replace(warmOriginal,checkpoint,broken));execute('ReleaseSafe',1,true);writeFileSync(warmFile,warmOriginal);
 writeFileSync(cppFile,replace(cpp,'  if (st != MTL::CommandBufferStatusCompleted) return fail("a warm chunk completed with an error");','  if (st != MTL::CommandBufferStatusCompleted) return fail("a warm chunk completed with an error");\n  return fail("FIOS injected retirement API error AFTER genuine successful GPU completion/release");'));
 writeFileSync(testFile,replace(fixture,'const injected_retire_failure = false;','const injected_retire_failure = true;'));execute('ReleaseSafe');
 writeFileSync(cppFile,cpp);writeFileSync(testFile,fixture);execute('ReleaseSafe');
 assert.equal(readFileSync(path.join(source,'build.zig'),'utf8'),originalGraph);assert.equal(git(mimo,'diff','--','src/arch/mimo_v2/gpu_warm.zig'),patch);assert.equal(git(mimo,'diff','--name-only').trim(),'src/arch/mimo_v2/gpu_warm.zig');assert.equal(sha(patchFile),patchSHA);assert.equal(sha(fixtureFile),fixtureSHA);assert.equal(sha(helperFile),helperSHA);verifyLibraries();
 console.log(JSON.stringify({scope:'actual_event_gated_Engine_Metal_pause_and_retire_only',all_backend_terminality:false,activation:false,mimo_commit:'fcb4011347ff80eeeb19e2a1f0180e13199c7c8b',patch_sha256:patchSHA,fixture_sha256:fixtureSHA,helper_sha256:helperSHA,original_warm_cpp_sha256:createHash('sha256').update(cppOriginal).digest('hex'),metal_executable_sha256:sha(metal),libraries}));
 console.log('PASS: genuine MIMO Engine(Metal) pause/drain in ReleaseSafe/Debug, actual optimized premature-ack failure and injected API-error-after-real-completion remains unknown; original source restored, no model/inference/all-context/lifecycle authority. Test gates/counters/timer are explicit instrumentation, never enrollment.');
}finally{rmSync(generated,{force:true});rmSync(temporary,{recursive:true,force:true});}
