#!/usr/bin/env node
// Finite CPU-only source compatibility check. No model, installed operation,
// native admission, lifecycle permission or whole-native provenance is issued.
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,lstatSync,realpathSync} from 'node:fs';
import {execFileSync,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const args=process.argv.slice(2);
const commandStatus=args.length===13&&args[12]==='--metal-command-status';
if(commandStatus)args.pop();
const callbackFence=args.length===12&&args[7]==='--metal-callback-fence'&&args[8]==='--sdk-source'&&args[10]==='--sdk-library';
assert((args.length===7||callbackFence)&&(!commandStatus||callbackFence)&&args[0]==='--isolated'&&args[1]==='--source'&&args[3]==='--zig'&&args[5]==='--mlx-sha256',
  'Use --isolated --source ABS_CURRENT_NATIVE_SOURCE --zig ABS_PINNED_ZIG --mlx-sha256 REVIEWED_MLX_SHA256 [--metal-callback-fence --sdk-source ABS_SDK_SOURCE --sdk-library ABS_LIBRARY [--metal-command-status]]');
assert(process.platform==='darwin'&&process.arch==='arm64'&&process.getuid()>0);
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const [source,zig]=[args[2],args[4]].map(value=>{
  assert(path.isAbsolute(value)&&realpathSync(value)===value&&value.startsWith('/private/tmp/'));
  const info=lstatSync(value);assert(info.uid===process.getuid()&&(info.mode&0o022)===0);return value;
});
function bytes(file,maximum){
  const info=lstatSync(file);assert(info.isFile()&&!info.isSymbolicLink()&&info.nlink===1&&info.size>0&&info.size<=maximum);
  return readFileSync(file);
}
assert.equal(sha(bytes(zig,512<<20)),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
assert(/^[0-9a-f]{64}$/.test(args[6]));
function privateInput(value){
  assert(path.isAbsolute(value)&&realpathSync(value)===value&&value.startsWith('/private/tmp/'));
  const info=lstatSync(value);assert(info.uid===process.getuid()&&(info.mode&0o022)===0);return value;
}
const library=callbackFence?privateInput(args[11]):path.join(source,'lib/mlx/lib/libmlx.dylib');
assert.equal(sha(bytes(library,256<<20)),args[6]);
const helper=readFileSync(path.join(root,'platform/studio/native/current_system_cxx_build.zig.fixture'),'utf8');
const config=bytes(path.join(source,'build/config.zig'),1<<20),suffix=Buffer.from('\n'+helper);
assert(config.subarray(config.length-suffix.length).equals(suffix),'Current build helper differs from reviewed source');
assert.equal(sha(config.subarray(0,config.length-suffix.length)),'7756357b2f736100c874ff38bb8a817484141c7a86189212f2164040c65ba511');
const directory=mkdtempSync('/private/tmp/fios-009-current-cxx-check-');
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',DEVELOPER_DIR:'/Applications/Xcode.app/Contents/Developer',
  GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const run=(program,argv)=>execFileSync(program,argv,{env,encoding:'utf8',timeout:15000,maxBuffer:4<<20});
const mlx=callbackFence?privateInput(args[9]):path.join(source,'lib/mlx-src');
const git=(...argv)=>run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',mlx,...argv]);
assert.equal(git('rev-parse','HEAD').trim(),'c69303b00f5f61860436e832f23fa8c34b96f93a');
const sourcePatch=readFileSync(path.join(root,'platform/studio/native/mlx-c69303b-owner-uncertainty.patch'),'utf8');
const observedPatch=git('diff','--no-ext-diff','--no-textconv','HEAD');
const paths=['mlx/backend/cpu/eval.cpp','mlx/backend/metal/device.cpp','mlx/backend/metal/device.h','mlx/backend/metal/eval.cpp','mlx/scheduler.cpp','mlx/stream.cpp','mlx/stream.h'];
assert.deepEqual(git('status','--porcelain','--untracked-files=all','--ignored=matching').trimEnd().split('\n'),paths.map(name=>' M '+name));
let incrementalPatch=null;
const statusPatch=commandStatus?readFileSync(path.join(root,'platform/studio/native/mlx-c69303b-metal-callback-status.patch'),'utf8'):null;
if(callbackFence){
  incrementalPatch=readFileSync(path.join(root,'platform/studio/native/mlx-c69303b-metal-callback-fence.patch'),'utf8');
  const composed=path.join(directory,'reviewed-sdk-source');mkdirSync(composed);
  for(const name of paths){
    const destination=path.join(composed,name);mkdirSync(path.dirname(destination),{recursive:true});
    writeFileSync(destination,execFileSync('/usr/bin/git',['--no-replace-objects','-C',mlx,'show','HEAD:'+name],{env,timeout:15000,maxBuffer:4<<20}));
  }
  for(const [name,patch] of [['base.patch',sourcePatch],['increment.patch',incrementalPatch],...(commandStatus?[['status.patch',statusPatch]]:[])]){
    const file=path.join(directory,name);writeFileSync(file,patch);
    execFileSync('/usr/bin/git',['apply',file],{cwd:composed,env,timeout:15000,maxBuffer:4<<20});
  }
  for(const name of paths)assert(readFileSync(path.join(composed,name)).equals(bytes(path.join(mlx,name),4<<20)),'SDK differs from exact reviewed patch composition');
}else assert.equal(observedPatch,sourcePatch);
assert.equal(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim(),'27.2');
const sdk=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-path']).trim());
assert(path.isAbsolute(sdk));
const selectedSDK=Object.fromEntries(['usr/lib/libc++.1.tbd',...['__config','__config_site','cstdint','memory','functional','optional','stdexcept','typeinfo','exception'].map(name=>'usr/include/c++/v1/'+name)].map(name=>[path.join(sdk,name),sha(bytes(path.join(sdk,name),64<<20))]));
const fixture=readFileSync(path.join(root,'platform/studio/native/mlx_cxx_callback_error_test.cpp'),'utf8');
assert.equal(fixture.split('int main()').length,2);
writeFileSync(path.join(directory,'callback.cpp'),fixture.replace('int main()','extern "C" int fios_cxx_control()'));
writeFileSync(path.join(directory,'root.zig'),'extern fn fios_cxx_control() c_int;\npub fn main() void {if(fios_cxx_control()!=0) @panic("callback control failed");}\n');
writeFileSync(path.join(directory,'child.zig'),'pub const fixture = true;\n');
writeFileSync(path.join(directory,'config.zig'),config);
writeFileSync(path.join(directory,'build.zig'),`const std=@import("std");const config=@import("config.zig");
pub fn build(b:*std.Build) void {
 const target=b.standardTargetOptions(.{});const optimize=b.standardOptimizeOption(.{});
 const module=b.createModule(.{.root_source_file=b.path("root.zig"),.target=target,.optimize=optimize,.link_libcpp=true});
 const child=b.createModule(.{.root_source_file=b.path("child.zig"),.target=target,.optimize=optimize,.link_libcpp=true});
 module.addImport("child",child);child.addImport("parent",module);
 module.addIncludePath(.{.cwd_relative=${JSON.stringify(mlx)}});
 module.addObjectFile(.{.cwd_relative=${JSON.stringify(library)}});
 module.addRPath(.{.cwd_relative=${JSON.stringify(path.dirname(library))}});
 module.addCSourceFile(.{.file=b.path("callback.cpp"),.flags=&.{"-std=c++20","-O2"}});
 const host:config.Host=.{.frameworks=${JSON.stringify(sdk+'/System/Library/Frameworks')},.webp_prefix=null,.brew_prefix="/unused"};
 config.sourceSystemCxx(b,module,host);config.sourceSystemCxx(b,module,host);
 if(module.link_libcpp!=false or child.link_libcpp!=false or module.link_libc!=true or child.link_libc!=true) @panic("ABI module traversal omitted an import");
 b.installArtifact(b.addExecutable(.{.name="cxx-control",.root_module=module}));
}
`);
const receipt={version:1,scope:'current_build_helper_CPU_callback_compatibility_not_native_authority',
  source,library_sha256:args[6],config_sha256:sha(config),helper_sha256:sha(helper),fixture_sha256:sha(fixture),
  runner_sha256:sha(readFileSync(fileURLToPath(import.meta.url))),sdk:'27.2',selected_sdk_inputs:selectedSDK,source_patch_sha256:sha(sourcePatch),
  ...(callbackFence?{sdk_source:mlx,sdk_library:library,incremental_patch_sha256:sha(incrementalPatch),observed_source_patch_sha256:sha(observedPatch)}:{}),results:[],models:0,inference:false,
  ...(commandStatus?{command_status_patch_sha256:sha(statusPatch)}:{}),
  source_fixture_only:true,installed:false,activation:false,native_authority:false,whole_native_provenance:false};
function save(){writeFileSync(path.join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n');}
save();
for(const mode of ['Debug','ReleaseFast']){
  const build=spawnSync(zig,['build','--sysroot',sdk,'-Dcpu=apple_m1','-Doptimize='+mode,'-j2'],{cwd:directory,env,encoding:'utf8',timeout:180000,maxBuffer:4<<20});
  writeFileSync(path.join(directory,mode+'-build.log'),(build.stdout??'')+(build.stderr??''));
  let execution;
  if(build.status===0)execution=spawnSync('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',path.join(directory,'zig-out/bin/cxx-control')],{env,encoding:'utf8',timeout:10000,maxBuffer:65536});
  if(execution)writeFileSync(path.join(directory,mode+'-run.log'),(execution.stdout??'')+(execution.stderr??''));
  receipt.results.push({mode,build_status:build.status,build_signal:build.signal,run_status:execution?.status??null,
    run_signal:execution?.signal??null,passed:build.status===0&&execution?.status===0&&execution.stdout.includes('PASS: actual system C++ SDK callback error channel and completed CPU cleanup')});
  save();
}
receipt.declared_inputs_unchanged=bytes(path.join(source,'build/config.zig'),1<<20).equals(config)&&sha(bytes(library,256<<20))===args[6]&&git('diff','--no-ext-diff','--no-textconv','HEAD')===observedPatch&&
  readFileSync(path.join(root,'platform/studio/native/mlx-c69303b-owner-uncertainty.patch'),'utf8')===sourcePatch&&
  (incrementalPatch===null||readFileSync(path.join(root,'platform/studio/native/mlx-c69303b-metal-callback-fence.patch'),'utf8')===incrementalPatch)&&
  (statusPatch===null||readFileSync(path.join(root,'platform/studio/native/mlx-c69303b-metal-callback-status.patch'),'utf8')===statusPatch)&&
  Object.entries(selectedSDK).every(([file,expected])=>sha(bytes(file,64<<20))===expected)&&
  sha(readFileSync(fileURLToPath(import.meta.url)))===receipt.runner_sha256&&
  sha(readFileSync(path.join(root,'platform/studio/native/current_system_cxx_build.zig.fixture')))===receipt.helper_sha256&&
  sha(readFileSync(path.join(root,'platform/studio/native/mlx_cxx_callback_error_test.cpp')))===receipt.fixture_sha256;
save();
assert(receipt.declared_inputs_unchanged&&receipt.results.length===2&&receipt.results.every(result=>result.passed),`Current C++ compatibility check failed; retain ${directory}`);
console.log(JSON.stringify({directory,receipt_sha256:sha(readFileSync(path.join(directory,'receipt.json'))),passed:2,models:0,inference:false,native_authority:false}));
