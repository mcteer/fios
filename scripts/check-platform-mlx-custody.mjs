#!/usr/bin/env node
// Full genuine CPU-only MLX source build. No Metal, arrays, models or inference.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {lstatSync,mkdtempSync,readFileSync,realpathSync,rmSync,writeFileSync} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url)),args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.getuid()!==0);
assert(args.length===9&&args[0]==='--isolated'&&args[1]==='--source'&&args[3]==='--cmake'&&args[5]==='--json-source'&&args[7]==='--fmt-source'&&[args[2],args[4],args[6],args[8]].every(path.isAbsolute),
 'Usage: check-platform-mlx-custody.mjs --isolated --source ABS_PINNED_MLX --cmake ABS_PINNED_CMAKE --json-source ABS_PINNED_JSON --fmt-source ABS_PINNED_FMT');
const [source,cmake,json,fmt]=[args[2],args[4],args[6],args[8]].map(value=>realpathSync(value));
for(const directory of [source,json,fmt]) {const info=lstatSync(directory);assert(directory.startsWith('/private/tmp/')&&info.isDirectory()&&info.uid===process.getuid()&&(info.mode&0o022)===0);}
const env={PATH:'/usr/bin:/bin:/usr/sbin:/sbin',HOME:os.homedir(),TMPDIR:os.tmpdir(),LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const run=(file,argv,options={})=>execFileSync(file,argv,{env,encoding:'utf8',timeout:600000,maxBuffer:16*1024*1024,...options});
const git=(directory,...argv)=>run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',directory,...argv]);
const sha=file=>{const info=lstatSync(file);assert(info.isFile()&&!info.isSymbolicLink());return createHash('sha256').update(readFileSync(file)).digest('hex');};
const pins={mlx:'64ea011cb65f14d9ce2737e60db9a4ae91ed7441',json:'9cca280a4d0ccf0c08f47a99aa71d1b0e52f8d03',fmt:'407c905e45ad75fc29bf0f9bb7c5c2fd3475976f'};
assert.equal(sha(cmake),'08f1530c0d3afa6ab48860b10cf0e5c0a86ca93fe0fa901e0edef62204227490');
assert.equal(git(source,'rev-parse','HEAD').trim(),pins.mlx);
const cleanDependency=(directory,pin)=>{assert.equal(git(directory,'rev-parse','HEAD').trim(),pin);assert.equal(git(directory,'status','--porcelain','--untracked-files=all','--ignored=matching').trim(),'');};
cleanDependency(json,pins.json);cleanDependency(fmt,pins.fmt);
const patchFile=path.join(root,'platform/studio/native/mlx-64ea011-stream-custody.patch'),patch=readFileSync(patchFile,'utf8'),patchHash=sha(patchFile);
const testFile=path.join(root,'platform/studio/native/mlx_stream_custody_test.cpp'),testHash=sha(testFile);
const pendingFile=path.join(root,'platform/studio/native/mlx_stream_custody_pending_test.cpp'),pendingHash=sha(pendingFile);
const temporary=mkdtempSync(path.join(os.tmpdir(),'fios-009-mlx-custody-'));
env.TMPDIR=temporary;
const checkout=path.join(temporary,'source'),build=path.join(temporary,'build'),binary=path.join(temporary,'fixture');
let cpp,original;
try {
 run('/usr/bin/git',['clone','--quiet','--no-hardlinks','--no-checkout',source,checkout]);
 git(checkout,'checkout','--quiet','--detach',pins.mlx);
 assert.equal(git(checkout,'status','--porcelain','--untracked-files=all','--ignored=matching').trim(),'');
 git(checkout,'apply','--check',patchFile);git(checkout,'apply',patchFile);
 assert.equal(git(checkout,'diff','--','mlx/stream.cpp','mlx/stream.h'),patch);
 cpp=path.join(checkout,'mlx/stream.cpp');original=readFileSync(cpp,'utf8');
 console.log(run(cmake,['-S',checkout,'-B',build,'-DCMAKE_BUILD_TYPE=Release','-DCMAKE_CXX_COMPILER=/usr/bin/clang++','-DCMAKE_CXX_FLAGS=','-DBUILD_SHARED_LIBS=ON','-DMLX_BUILD_CPU=ON','-DMLX_BUILD_METAL=OFF','-DMLX_BUILD_CUDA=OFF','-DMLX_BUILD_TESTS=OFF','-DMLX_BUILD_EXAMPLES=OFF','-DMLX_BUILD_BENCHMARKS=OFF','-DMLX_BUILD_PYTHON_BINDINGS=OFF','-DMLX_BUILD_GGUF=OFF','-DMLX_BUILD_SAFETENSORS=OFF','-DMLX_USE_CCACHE=OFF','-DFETCHCONTENT_FULLY_DISCONNECTED=ON',`-DFETCHCONTENT_SOURCE_DIR_JSON=${json}`,`-DFETCHCONTENT_SOURCE_DIR_FMT=${fmt}`,'-DJSON_BuildTests=OFF','-DJSON_Install=OFF','-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF']));
 const compile=()=>{
  // Apple Make may compare whole seconds; every source variant must compile.
  rmSync(path.join(build,'CMakeFiles/mlx.dir/mlx/stream.cpp.o'),{force:true});
  console.log(run(cmake,['--build',build,'--target','mlx','--parallel','2']));
 };
 compile();
 run('/usr/bin/clang++',['-std=c++20','-O2','-UNDEBUG','-I',checkout,testFile,'-L',build,'-lmlx',`-Wl,-rpath,${build}`,'-o',binary]);
 const execute=(mode,expected=0,file=binary)=>{
  const result=spawnSync(file,[mode],{env,encoding:'utf8',timeout:15000,maxBuffer:1024*1024});
  assert.equal(result.error,undefined);assert.equal(result.signal,null);assert.equal(result.status,expected,`${mode}: ${result.stdout??''}${result.stderr??''}`);
  console.log((result.stdout??'')+(result.stderr??''));
 };
 const ordinary=()=>{for(const mode of ['--late','--raw','--owners','--owner-exit','--shared','--backend-failure'])execute(mode);execute('--assertion-negative',77);};
 ordinary();
 const library=path.join(build,'libmlx.dylib'),libraryHash=sha(library);
 const release='  if (!fios_bump()) return false;\n  fios_registry.held = 0;\n  fios_registry.held_owner = 0;\n  return true;';
 assert.equal(original.split(release).length,2);
 const inject='  fios_registry.epoch = std::numeric_limits<uint64_t>::max(); // Private boundary injector.\n';
 // Counter boundary stress changes only metadata in this private clone.
 writeFileSync(cpp,original.replace(release,inject+'  fios_registry.held = 0;\n  fios_registry.held_owner = 0;\n  return fios_bump();'));
 compile();execute('--exhausted-release',77);
 writeFileSync(cpp,original.replace(release,inject+release));
 compile();execute('--exhausted-release');
 const guard='    if (fios_registry.held) throw std::runtime_error("Stream creation held");\n';
 assert.equal(original.split(guard).length,2);
 writeFileSync(cpp,original.replace(guard,''));
 compile();execute('--raw',77);
 const checkpoint=`
static std::atomic<bool> fios_fixture_released{false};
MLX_API void fios_fixture_release_pending() { fios_fixture_released.store(true); }
static void fios_fixture_pending_checkpoint() {
  const auto until=std::chrono::steady_clock::now()+std::chrono::seconds(5);
  while (!fios_fixture_released.load()) {
    if (std::chrono::steady_clock::now()>=until) throw std::runtime_error("Private checkpoint timeout");
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
}
`;
 const site='Stream new_stream(Device d) {\n  FiosCreation creation;\n';
 assert.equal(original.split(site).length,2);
 const pendingSource=original.replace('#include <stdexcept>','#include <stdexcept>\n#include <atomic>\n#include <chrono>\n#include <thread>').replace('namespace mlx::core {','namespace mlx::core {\n'+checkpoint).replace(site,site+'  fios_fixture_pending_checkpoint();\n');
 const pendingGuard='  if (!fios_registry.enabled || fios_registry.uncertain || fios_registry.pending ||\n      fios_registry.held || !fios_owner || fios_registry.epoch != expected_epoch)';
 assert.equal(pendingSource.split(pendingGuard).length,2);
 writeFileSync(cpp,pendingSource);compile();
 const pendingBinary=path.join(temporary,'pending-fixture');
 run('/usr/bin/clang++',['-std=c++20','-O2','-UNDEBUG','-I',checkout,pendingFile,'-L',build,'-lmlx',`-Wl,-rpath,${build}`,'-o',pendingBinary]);
 execute('--pending-creation',0,pendingBinary);
 writeFileSync(cpp,pendingSource.replace(pendingGuard,pendingGuard.replace(' || fios_registry.pending','')));
 compile();execute('--pending-creation',77,pendingBinary);
 writeFileSync(cpp,pendingSource);compile();execute('--pending-creation',0,pendingBinary);
 writeFileSync(cpp,original);compile();ordinary();
 assert.equal(sha(library),libraryHash,'restored full source artifact must match its pre-witness bytes');
 assert.equal(git(checkout,'diff','--','mlx/stream.cpp','mlx/stream.h'),patch);
 assert.equal(sha(patchFile),patchHash);assert.equal(sha(testFile),testHash);assert.equal(sha(pendingFile),pendingHash);
 cleanDependency(json,pins.json);cleanDependency(fmt,pins.fmt);
 assert.equal(sha(cmake),'08f1530c0d3afa6ab48860b10cf0e5c0a86ca93fe0fa901e0edef62204227490');
 console.log(JSON.stringify({scope:'genuine_cpu_only_stream_creation',activation:false,all_backend_terminality:false,pins,patch_sha256:patchHash,library_sha256:libraryHash,test_sha256:testHash,pending_test_sha256:pendingHash}));
 console.log('PASS: full genuine CPU-only MLX source build, six creation fixtures, actual pending-creation checkpoint/refusal, forced epoch red/green, always-enabled check and creation/pending-gate mutation witnesses; NOT GPU/encoder/model/lifecycle acceptance.');
} finally {
 // Only this checker-created directory is removed; no manager state or input tree.
 rmSync(temporary,{recursive:true,force:true});
}
