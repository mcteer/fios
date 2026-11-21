#!/usr/bin/env node
// CPU-only renderer/source-input check. No inference, installation or authority.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,lstatSync,realpathSync} from 'node:fs';
import {createHash} from 'node:crypto';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),args=process.argv.slice(2);
assert(args.length===5&&args[0]==='--isolated'&&args[1]==='--source'&&args[3]==='--zig',
 'Use --isolated --source ABS_CURRENT_NATIVE_SOURCE --zig ABS_PINNED_ZIG');
assert(process.platform==='darwin'&&process.arch==='arm64'&&process.getuid()>0);
const sha=b=>createHash('sha256').update(b).digest('hex');
function bytes(file,max,system=false){const s=lstatSync(file);assert(s.isFile()&&!s.isSymbolicLink()&&s.nlink===1&&(s.uid===process.getuid()||(system&&s.uid===0))&&(s.mode&0o022)===0&&s.size>0&&s.size<=max);return readFileSync(file);}
const [source,zig]=[args[2],args[4]].map(file=>{assert(path.isAbsolute(file)&&realpathSync(file)===file&&file.startsWith('/private/tmp/'));const s=lstatSync(file);assert(s.uid===process.getuid()&&(s.mode&0o022)===0);return file;});
assert.equal(sha(bytes(zig,512<<20)),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
const directory=mkdtempSync('/private/tmp/fios-009-current-jinja-check-');
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',DEVELOPER_DIR:'/Applications/Xcode.app/Contents/Developer',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const run=(program,argv)=>execFileSync(program,argv,{env,encoding:'utf8',timeout:15000,maxBuffer:4<<20});
const git=(...argv)=>run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,...argv]);
const base='4e231ceebe63308cc038117d40b9f9b64bd0372e';
const names=['LICENSE','caps.cpp','caps.h','jinja_string.cpp','jinja_string.h','jinja_wrapper.cpp','jinja_wrapper.h','lexer.cpp','lexer.h','log.h','nlohmann/json.hpp','parser.cpp','parser.h','runtime.cpp','runtime.h','utils.h','value.cpp','value.h'];
const inputs={};const original={};
for(const name of names){const file=path.join(source,'lib/jinja_cpp',name),data=bytes(file,8<<20);assert.equal(sha(data),sha(Buffer.from(git('show',base+':lib/jinja_cpp/'+name))),'Vendored Jinja source differs from current reviewed base');original[name]=data;inputs[name]=sha(data);}
const archive=path.join(source,'lib/jinja_cpp/libjinja.a'),archiveSHA=sha(bytes(archive,64<<20));
const helper=bytes(path.join(source,'build/fios_jinja.zig'),1<<20),reviewed=bytes(path.join(root,'platform/studio/native/current_jinja_source_build.zig'),1<<20);assert(helper.equals(reviewed));
const config=bytes(path.join(source,'build/config.zig'),1<<20),cxx=bytes(path.join(root,'platform/studio/native/current_system_cxx_build.zig.fixture'),1<<20),suffix=Buffer.concat([Buffer.from('\n'),cxx]);assert(config.subarray(-suffix.length).equals(suffix));assert.equal(sha(config.subarray(0,config.length-suffix.length)),'7756357b2f736100c874ff38bb8a817484141c7a86189212f2164040c65ba511');
assert.equal(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim(),'27.2');
const sdk=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-path']).trim());
const selectedSDK=Object.fromEntries(['usr/lib/libc++.1.tbd',...['__config','__config_site','cstdint','memory','functional','optional','stdexcept','typeinfo','exception'].map(n=>'usr/include/c++/v1/'+n)].map(n=>[path.join(sdk,n),sha(bytes(path.join(sdk,n),64<<20,true))]));
const fixture=bytes(path.join(root,'platform/studio/native/jinja_source_control.cpp'),1<<20),marker='\nextern "C" int fios_jinja_source_marker() { return 37; }\n';
mkdirSync(path.join(directory,'jinja'),{mode:0o700});mkdirSync(path.join(directory,'jinja/nlohmann'),{mode:0o700});
for(const [name,data]of Object.entries(original))writeFileSync(path.join(directory,'jinja',name),name==='jinja_wrapper.cpp'?Buffer.concat([data,Buffer.from(marker)]):data,{flag:'wx',mode:0o400});
for(const [name,data]of Object.entries({'fios_jinja.zig':helper,'config.zig':config,'control.cpp':fixture}))writeFileSync(path.join(directory,name),data,{flag:'wx',mode:0o400});
writeFileSync(path.join(directory,'root.zig'),'extern fn fios_jinja_control() c_int;\nextern fn fios_jinja_source_marker() c_int;\npub fn main() void {if(fios_jinja_control()!=0 or fios_jinja_source_marker()!=37) @panic("Jinja source control failed");}\n',{flag:'wx',mode:0o400});
writeFileSync(path.join(directory,'build.zig'),`const std=@import("std");const config=@import("config.zig");const jinja=@import("fios_jinja.zig");
pub fn build(b:*std.Build) void {
 const target=b.standardTargetOptions(.{});const optimize=b.standardOptimizeOption(.{});
 const module=b.createModule(.{.root_source_file=b.path("root.zig"),.target=target,.optimize=optimize,.link_libcpp=true});
 module.addIncludePath(b.path("jinja"));module.addCSourceFile(.{.file=b.path("control.cpp"),.flags=&.{"-std=c++17","-DNDEBUG"}});
 const host:config.Host=.{.frameworks=${JSON.stringify(sdk+'/System/Library/Frameworks')},.webp_prefix=null,.brew_prefix="/unused"};
 if(b.option(bool,"original-archive","Original archive control") orelse false) module.addObjectFile(.{.cwd_relative=${JSON.stringify(archive)}})
 else {const library=jinja.create(b,target,optimize,host,b.path("jinja"));module.linkLibrary(library);b.installArtifact(library);}
 config.sourceSystemCxx(b,module,host);b.installArtifact(b.addExecutable(.{.name="jinja-control",.root_module=module}));
}
`,{flag:'wx',mode:0o400});
const receipt={version:1,scope:'actual_Jinja_build_helper_CPU_controls_selected_inputs_not_native_authority',source,source_revision:git('rev-parse','HEAD').trim(),native_base:base,declared_jinja_sources:inputs,original_archive_sha256:archiveSHA,helper_sha256:sha(helper),config_sha256:sha(config),fixture_sha256:sha(fixture),runner_sha256:sha(readFileSync(fileURLToPath(import.meta.url))),zig_sha256:sha(bytes(zig,512<<20)),sdk:'27.2',selected_sdk_inputs:selectedSDK,sdk_input_scope:'selected_headers_and_runtime_stub_not_transitive_SDK_or_mapped_OS_attestation',private_marker_added:true,source_fixture_only:true,models:0,inference:false,installed:false,activation:false,native_authority:false,whole_native_provenance:false,results:[]};
const save=()=>writeFileSync(path.join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n');save();
for(const [label,mode,old]of [['archive-missing-source-marker','ReleaseFast',true],['source-debug','Debug',false],['source-fast','ReleaseFast',false]]){
 const argv=['build','--sysroot',sdk,'-Dcpu=apple_m1','-Doptimize='+mode,'-j2','--summary','all',...(old?['-Doriginal-archive=true']:[])];
 const result=spawnSync(zig,argv,{cwd:directory,env,encoding:'utf8',timeout:240000,maxBuffer:4<<20});
 const log=(result.stdout??'')+(result.stderr??'');writeFileSync(path.join(directory,label+'-build.log'),log);
 const item={label,mode,build_status:result.status,build_signal:result.signal};
 if(old){const missing=log.split('\n').filter(line=>line.includes('undefined symbol:'));item.expected_missing_source_symbol=result.status===1&&JSON.stringify(missing)===JSON.stringify(['error: undefined symbol: _fios_jinja_source_marker']);}
 else if(result.status===0){const execution=spawnSync('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',path.join(directory,'zig-out/bin/jinja-control')],{cwd:directory,env,encoding:'utf8',timeout:10000,maxBuffer:65536});writeFileSync(path.join(directory,label+'-run.log'),(execution.stdout??'')+(execution.stderr??''));item.run_status=execution.status;item.run_signal=execution.signal;item.passed=execution.status===0&&execution.stdout.includes('PASS: byte-exact Jinja render, structured context, NUL, errors and thread-local reset');item.archive_sha256=sha(bytes(path.join(directory,'zig-out/lib/libfios-jinja-source.a'),256<<20));}
 receipt.results.push(item);save();assert(old?item.expected_missing_source_symbol:item.passed,`Jinja source check failed; retain ${directory}`);
}
receipt.declared_inputs_unchanged=Object.entries(inputs).every(([name,hash])=>sha(bytes(path.join(source,'lib/jinja_cpp',name),8<<20))===hash)&&sha(bytes(archive,64<<20))===archiveSHA&&bytes(path.join(source,'build/fios_jinja.zig'),1<<20).equals(helper)&&bytes(path.join(source,'build/config.zig'),1<<20).equals(config)&&bytes(path.join(root,'platform/studio/native/current_jinja_source_build.zig'),1<<20).equals(helper)&&bytes(path.join(root,'platform/studio/native/jinja_source_control.cpp'),1<<20).equals(fixture)&&Object.entries(selectedSDK).every(([file,hash])=>sha(bytes(file,64<<20,true))===hash)&&sha(readFileSync(fileURLToPath(import.meta.url)))===receipt.runner_sha256;
save();assert(receipt.declared_inputs_unchanged);
console.log(JSON.stringify({directory,receipt_sha256:sha(readFileSync(path.join(directory,'receipt.json'))),source_modes_passed:2,expected_archive_failure:true,models:0,inference:false,native_authority:false}));
