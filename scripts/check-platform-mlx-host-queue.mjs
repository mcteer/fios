#!/usr/bin/env node
// Separate genuine CPU-only MLX host-queue source candidate; no inference.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {lstatSync,mkdtempSync,readFileSync,realpathSync,rmSync,writeFileSync} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url)),args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.getuid()!==0);
const privateCPU=args.length===10&&args[9]==='--static-backend-clear';
assert((args.length===9||privateCPU)&&args[0]==='--isolated'&&args[1]==='--source'&&args[3]==='--cmake'&&args[5]==='--json-source'&&args[7]==='--fmt-source'&&[args[2],args[4],args[6],args[8]].every(path.isAbsolute),
 'Usage: check-platform-mlx-host-queue.mjs --isolated --source ABS_PINNED_MLX --cmake ABS_PINNED_CMAKE --json-source ABS_PINNED_JSON --fmt-source ABS_PINNED_FMT [--static-backend-clear]');
const [source,cmake,json,fmt]=[args[2],args[4],args[6],args[8]].map(value=>realpathSync(value));
for(const directory of [source,json,fmt]){const info=lstatSync(directory);assert(directory.startsWith('/private/tmp/')&&info.isDirectory()&&info.uid===process.getuid()&&(info.mode&0o022)===0);}
const env={PATH:'/usr/bin:/bin:/usr/sbin:/sbin',HOME:os.homedir(),LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1',ZERO_AR_DATE:'1'};
const run=(file,argv,options={})=>execFileSync(file,argv,{env,encoding:'utf8',timeout:600000,maxBuffer:16*1024*1024,...options});
const git=(directory,...argv)=>run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',directory,...argv]);
const sha=file=>{const info=lstatSync(file);assert(info.isFile()&&!info.isSymbolicLink());return createHash('sha256').update(readFileSync(file)).digest('hex');};
const pins={mlx:'64ea011cb65f14d9ce2737e60db9a4ae91ed7441',json:'9cca280a4d0ccf0c08f47a99aa71d1b0e52f8d03',fmt:'407c905e45ad75fc29bf0f9bb7c5c2fd3475976f'};
const cmakeSHA='08f1530c0d3afa6ab48860b10cf0e5c0a86ca93fe0fa901e0edef62204227490';assert.equal(sha(cmake),cmakeSHA);
assert.equal(git(source,'rev-parse','HEAD').trim(),pins.mlx);
const clean=(directory,pin)=>{assert.equal(git(directory,'rev-parse','HEAD').trim(),pin);assert.equal(git(directory,'status','--porcelain','--untracked-files=all','--ignored=matching').trim(),'');};
clean(json,pins.json);clean(fmt,pins.fmt);
const paths=['mlx/backend/cpu/eval.cpp','mlx/scheduler.cpp','mlx/stream.cpp','mlx/stream.h'];
const patchFile=path.join(root,'platform/studio/native/mlx-64ea011-host-queue-custody.patch'),patch=readFileSync(patchFile,'utf8'),patchSHA=sha(patchFile);
assert.equal(git(source,'diff','--',...paths),patch);
assert.deepEqual(git(source,'diff','--name-only').trim().split('\n').sort(),paths);
const fixture=path.join(root,'platform/studio/native/mlx_host_queue_custody_test.cpp'),fixtureSHA=sha(fixture);
const temporary=mkdtempSync(path.join(os.tmpdir(),'fios-009-mlx-host-queue-'));env.TMPDIR=temporary;
const checkout=path.join(temporary,'source'),build=path.join(temporary,'build'),binary=path.join(temporary,'fixture');
try{
 run('/usr/bin/git',['clone','--quiet','--no-hardlinks','--no-checkout',source,checkout]);git(checkout,'checkout','--quiet','--detach',pins.mlx);
 git(checkout,'apply','--check',patchFile);git(checkout,'apply',patchFile);assert.equal(git(checkout,'diff','--',...paths),patch);
 console.log(run(cmake,['-S',checkout,'-B',build,'-DCMAKE_BUILD_TYPE=Release','-DCMAKE_CXX_COMPILER=/usr/bin/clang++','-DCMAKE_CXX_FLAGS=',`-DBUILD_SHARED_LIBS=${privateCPU?'OFF':'ON'}`,'-DMLX_BUILD_CPU=ON','-DMLX_BUILD_METAL=OFF','-DMLX_BUILD_CUDA=OFF','-DMLX_BUILD_TESTS=OFF','-DMLX_BUILD_EXAMPLES=OFF','-DMLX_BUILD_BENCHMARKS=OFF','-DMLX_BUILD_PYTHON_BINDINGS=OFF','-DMLX_BUILD_GGUF=OFF','-DMLX_BUILD_SAFETENSORS=OFF','-DMLX_USE_CCACHE=OFF','-DFETCHCONTENT_FULLY_DISCONNECTED=ON',`-DFETCHCONTENT_SOURCE_DIR_JSON=${json}`,`-DFETCHCONTENT_SOURCE_DIR_FMT=${fmt}`,'-DJSON_BuildTests=OFF','-DJSON_Install=OFF','-DCMAKE_FIND_USE_PACKAGE_REGISTRY=OFF']));
 const library=path.join(build,privateCPU?'libmlx.a':'libmlx.dylib');
 const link=()=>run('/usr/bin/clang++',['-std=c++20','-O2','-UNDEBUG',...(privateCPU?['-DFIOS_CPU_PRIVATE_FIXTURE']:[]),'-I',checkout,fixture,library,...(privateCPU?['-framework','Accelerate','-framework','Foundation']:[`-Wl,-rpath,${build}`]),'-o',binary]);
 const compile=()=>{for(const file of ['stream','scheduler','backend/cpu/eval'])rmSync(path.join(build,`CMakeFiles/mlx.dir/mlx/${file}.cpp.o`),{force:true});console.log(run(cmake,['--build',build,'--target','mlx','--parallel','2']));if(privateCPU)link();};
 compile();if(!privateCPU)link();
 const execute=(mode,expected=0)=>{const result=spawnSync(binary,[mode],{env,encoding:'utf8',timeout:15000,maxBuffer:1<<20});assert.equal(result.error,undefined);assert.equal(result.signal,null);const log=(result.stdout??'')+(result.stderr??'');assert.equal(result.status,expected,mode+': '+log);console.log(mode+': '+log);return log;};
 const ordinary=()=>{for(const mode of ['--default-off','--pending','--capture-retire','--foreign','--failure','--exact-release','--owner-exit','--clear-held','--clear-unheld','--clear-before-enable',...(privateCPU?['--cpu-clear-held','--cpu-clear-unheld','--cpu-clear-before-enable']:[])])execute(mode);execute('--assertion-negative',77);};
 ordinary();const librarySHA=sha(library);
 const file=path.join(checkout,'mlx/scheduler.cpp'),original=readFileSync(file,'utf8');
 const retirement='        task = nullptr;\n        fios_finish_host_task(custody, error.valid());';assert.equal(original.split(retirement).length,2);
 writeFileSync(file,original.replace(retirement,'        fios_finish_host_task(custody, error.valid());\n        task = nullptr;'));
 compile();assert(execute('--capture-retire',77).includes('EARLY_HOST_TASK_RETIREMENT'),'Premature-completion variant must fail the captured-payload retirement assertion');
 writeFileSync(file,original);compile();ordinary();
 const streamFile=path.join(checkout,'mlx/stream.cpp'),streamOriginal=readFileSync(streamFile,'utf8');
 const guard='  if (fios_registry.host_held) throw std::runtime_error("Host queues held");\n';assert.equal(streamOriginal.split(guard).length,2);
 writeFileSync(streamFile,streamOriginal.replace(guard,''));compile();
 assert(execute('--pending',77).includes('HOST_GATE_ALLOWED_SUBMISSION'),'Removing the actual submission gate must fail runtime refusal');
 const clearGuard='  if (fios_registry.enabled && (fios_registry.held || fios_registry.host_held))\n    throw std::runtime_error("Stream teardown held");\n';assert.equal(streamOriginal.split(clearGuard).length,2);
 writeFileSync(streamFile,streamOriginal.replace(clearGuard,''));compile();
 assert(execute('--clear-held',77).includes('STREAM_TEARDOWN_ALLOWED_WHILE_HELD'),'Removing actual pre-teardown hold refusal must fail real clear_streams');
 if(privateCPU){
  writeFileSync(streamFile,streamOriginal);
  const cpuFile=path.join(checkout,'mlx/backend/cpu/eval.cpp'),cpuOriginal=readFileSync(cpuFile,'utf8'),hook='  fios_before_clear_streams();\n';
  assert.equal(cpuOriginal.split(hook).length,2);writeFileSync(cpuFile,cpuOriginal.replace(hook,''));compile();
  assert(execute('--cpu-clear-held',77).includes('CPU_STREAM_TEARDOWN_ALLOWED_WHILE_HELD'),'Removing the actual backend hook must fail direct CPU encoder destruction refusal');
  writeFileSync(cpuFile,cpuOriginal);compile();ordinary();
 }
 const release='  if (!fios_bump()) return false;\n  fios_registry.host_held = fios_registry.host_owner = fios_registry.host_creation = 0;\n  fios_registry.held = fios_registry.held_owner = 0;\n  return true;';assert.equal(streamOriginal.split(release).length,2);
 const boundary='  fios_registry.epoch = std::numeric_limits<uint64_t>::max(); // Private boundary injector.\n';
 const cleared='  fios_registry.host_held = fios_registry.host_owner = fios_registry.host_creation = 0;\n  fios_registry.held = fios_registry.held_owner = 0;\n  return fios_bump();';
 writeFileSync(streamFile,streamOriginal.replace(release,boundary+cleared));compile();
 assert(execute('--exhausted-host-release',77).includes('HOST_RELEASE_CLEARED_ON_EXHAUSTION'),'Premature gate clearing must fail actual exhaustion retention');
 writeFileSync(streamFile,streamOriginal.replace(release,boundary+release));compile();execute('--exhausted-host-release');
 writeFileSync(streamFile,streamOriginal);compile();ordinary();
 assert.equal(sha(library),librarySHA,'Restored actual library differs');assert.equal(git(checkout,'diff','--',...paths),patch);
 assert.equal(sha(patchFile),patchSHA);assert.equal(sha(fixture),fixtureSHA);assert.equal(sha(cmake),cmakeSHA);clean(json,pins.json);clean(fmt,pins.fmt);
 console.log(JSON.stringify({scope:'genuine_cpu_only_mlx_host_scheduler_tasks',all_backend_terminality:false,activation:false,private_cpu_clear:privateCPU,pins,patch_sha256:patchSHA,library_sha256:librarySHA,fixture_sha256:fixtureSHA}));
 console.log('PASS: genuine MLX host-queue pending/active/payload-destruction custody, optional real static/private CPU clear-hook causal boundary, sticky failure/foreign use and exact joined re-arm; actual raw clear_streams refusal/uncertainty/late-enable boundaries and optimized early-retirement/submission-gate/raw-teardown/exhausted-release mutations and byte-identical library restoration; NOT Metal/device/model/lifecycle authority.');
}finally{rmSync(temporary,{recursive:true,force:true});}
