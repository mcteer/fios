#!/usr/bin/env node
// Ordinary idle engine/control lifecycle over the genuine host/plugin SDK.
// No historical mutation/fault/counter matrix, model or backend dispatch.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {createHash,randomUUID} from 'node:crypto';
import {readFileSync,writeFileSync,mkdtempSync,realpathSync,lstatSync,unlinkSync} from 'node:fs';
import {resolve,join} from 'node:path';
const root=resolve(import.meta.dirname,'..'),args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===7&&args[0]==='--isolated'&&args[1]==='--source'&&args[3]==='--mimo-source'&&args[5]==='--zig');
const [source,mimo,zig]=[2,4,6].map(i=>{assert(args[i].startsWith('/'));return realpathSync(args[i]);});
const directory=mkdtempSync('/private/tmp/fios-009-mimo-source-fence-');
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',DEVELOPER_DIR:'/Applications/Xcode.app/Contents/Developer',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1'};
const run=(file,argv,options={})=>execFileSync(file,argv,{env,encoding:'utf8',timeout:300000,maxBuffer:2<<20,...options});
const sha=path=>createHash('sha256').update(readFileSync(path)).digest('hex');
const git=(where,...argv)=>run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',where,...argv]);
for(const path of [source,mimo]){const info=lstatSync(path);assert(path.startsWith('/private/tmp/')&&info.isDirectory()&&info.uid===process.getuid()&&(info.mode&0o022)===0);}
assert.equal(sha(zig),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
assert.equal(git(source,'rev-parse','HEAD').trim(),'046b647686419df06c6c7132fb1d15d76185c3e5');
const paths=['gpu_warm','module','root','source'].map(name=>`src/arch/mimo_v2/${name}.zig`);
const patchFile=join(root,'platform/studio/native/mlx-stream-fcb4011-retirement.patch'),patch=readFileSync(patchFile,'utf8'),patchSHA=sha(patchFile);
function checkCandidate(){assert.equal(git(mimo,'rev-parse','HEAD').trim(),'fcb4011347ff80eeeb19e2a1f0180e13199c7c8b');assert.equal(git(mimo,'diff','--cached','--name-only').trim(),'');assert.deepEqual(git(mimo,'diff','--name-only').trim().split('\n'),paths);assert.equal(git(mimo,'diff','--no-ext-diff','--no-textconv','--',...paths),patch);}
checkCandidate();
const libraries={'libmlx.dylib':'6a5ee820afed9ce9421297260b4a9fd593749052d582c65deeca428fce61c76e','libmlxc.dylib':'6b4c9224691c2857cf7d386e75c1247cc6b0a4ae17d6ec6d1b455ec177e9929f','libjaccl.dylib':'5c6f3819b3555902ba1ab3a49550643994b49860f09e323fe42dfd6121103282','mlx.metallib':'95974b7de464ec2be7833a914ca5a53d283a70789470fd84218738fc8fcea3e1'};
for(const [name,digest] of Object.entries(libraries))assert.equal(sha(join(source,'lib/mlx/lib',name)),digest);
const frameworks=run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-path']).trim()+'/System/Library/Frameworks';
const original=readFileSync(join(source,'build.zig'),'utf8');
const guards='    if (target.result.os.tag == .macos) {\n        if (webp_prefix) |dir| verifyCopiedDeps(b, dir) else verifyBrewDeps(b);\n        verifyMlxStage(b);\n    }\n';
assert.equal(original.split(guards).length,2);
let graph=original.replace(guards,'    // Private CPU control fixture, no staging/release attestation.\n');
const factory=`
fn fiosSourceFence(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
 const host=b.createModule(.{ .root_source_file=b.path("src/plugin_host.zig"), .target=target, .optimize=optimize, .link_libc=true, .link_libcpp=true });
 const options=b.addOptions();options.addOption([]const u8,"version","26.10.3-fios-source-fixture");options.addOption(bool,"plugin_profile",false);host.addOptions("build_options",options);
 host.addFrameworkPath(.{ .cwd_relative=${JSON.stringify(frameworks)} });
 addMlxLib(b,host);addExl3Module(b,host,target,optimize);
 for ([_][]const u8{"IOKit","CoreFoundation","Foundation","Metal","IOSurface"}) |name| host.linkFramework(name,.{});
 host.addRPath(.{ .cwd_relative=${JSON.stringify(join(source,'lib/mlx/lib'))} });
 const module=mlxStreamPkg(b,host,${JSON.stringify(mimo)},"src/FIOS_SOURCE_FILE",target,optimize,false);
 const exe=b.addExecutable(.{ .name="fios-source-fence", .root_module=module });
 b.step("fios-source-fence","Private ordinary CPU control fixture").dependOn(&b.addInstallArtifact(exe,.{}).step);
}
`;
const fixtureFile=join(root,'platform/studio/native/mimo_source_fence.zig.fixture'),fixtureOriginal=readFileSync(fixtureFile),fixtureSHA=createHash('sha256').update(fixtureOriginal).digest('hex'),fixture=fixtureOriginal.toString('utf8').replace('const warm = @import("warm");','const warm = @import("arch/mimo_v2/gpu_warm.zig");');
const nonce=randomUUID(),helperName=`fios-source-fence-${nonce}.zig`,helper=join(mimo,'src',helperName),build=join(source,`fios-source-fence-${nonce}.zig`);
const anchor='    const exe = b.addExecutable(.{';assert.equal(graph.split(anchor).length,3);
graph=graph.replace(anchor,'    fiosSourceFence(b,target,optimize);\n'+anchor)+factory.replace('FIOS_SOURCE_FILE',helperName);
console.log(JSON.stringify({retained_directory:directory,scope:'ordinary_cpu_control_only',native_authority:false}));
writeFileSync(helper,fixture,{mode:0o600,flag:'wx'});writeFileSync(build,graph,{mode:0o600,flag:'wx'});
try {
 for(const mode of ['Debug','ReleaseSafe']){
  const prefix=join(directory,mode);
  run(zig,['build','fios-source-fence','--build-file',build,'--prefix',prefix,'-Doptimize='+mode,'-Dmlx-stream-dir='+mimo,'-j2']);
  const result=spawnSync('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',join(prefix,'bin/fios-source-fence')],{env,encoding:'utf8',timeout:10000,maxBuffer:4096});
  assert(!result.error&&!result.signal);assert.equal(result.status,0,result.stderr);
  const log=(result.stdout??'')+(result.stderr??'');
  assert(log.includes('PASS: actual idle warm control retains process source uncertainty'));console.log(mode+': '+log.trim());
 }
 checkCandidate();assert.equal(readFileSync(join(source,'build.zig'),'utf8'),original);assert.equal(sha(patchFile),patchSHA);assert(readFileSync(fixtureFile).equals(fixtureOriginal));
 for(const [name,digest] of Object.entries(libraries))assert.equal(sha(join(source,'lib/mlx/lib',name)),digest);
 const receipt={ok:true,directory,scope:'declared_mimo_control_and_genuine_sdk_inputs_only',patch_sha256:patchSHA,fixture_sha256:fixtureSHA,declared_sources:Object.fromEntries(paths.map(path=>[path,sha(join(mimo,path))])),libraries,modes:['Debug','ReleaseSafe'],native_authority:false,installed:false,native_inference:false,backend_dispatches:0};
 writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt)+'\n',{mode:0o600,flag:'wx'});console.log(JSON.stringify(receipt));
} finally {
 // Only exact nonce-bound generated text; retain outputs and all other data.
 if(readFileSync(helper,'utf8')===fixture)unlinkSync(helper);
 if(readFileSync(build,'utf8')===graph)unlinkSync(build);
}
