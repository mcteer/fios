#!/usr/bin/env node
// Actual serving warm request origin handoff behind a normal private event.
// No model, fault injection, production-body rewrite or replacement SDK objects.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {createHash,randomUUID} from 'node:crypto';
import {readFileSync,writeFileSync,mkdtempSync,realpathSync,lstatSync,unlinkSync} from 'node:fs';
import {resolve,join} from 'node:path';
const root=resolve(import.meta.dirname,'..'),args=process.argv.slice(2),priorIndex=args.indexOf('--prior'),prior=priorIndex>=0;
if(prior){assert.equal(args.lastIndexOf('--prior'),priorIndex);args.splice(priorIndex,1);}
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===7&&args[0]==='--isolated'&&args[1]==='--source'&&args[3]==='--mimo-source'&&args[5]==='--zig');
const [source,mimo,zig]=[2,4,6].map(i=>realpathSync(args[i]));
const directory=mkdtempSync('/private/tmp/fios-009-mimo-request-origins-'),plugin=join(directory,'plugin');
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',DEVELOPER_DIR:'/Applications/Xcode.app/Contents/Developer',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const run=(file,argv,options={})=>execFileSync(file,argv,{env,encoding:'utf8',timeout:300000,maxBuffer:2<<20,...options});
const hash=bytes=>createHash('sha256').update(bytes).digest('hex'),sha=file=>hash(readFileSync(file));
const git=(where,...argv)=>run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',where,...argv]);
for(const path of [source,mimo]){const s=lstatSync(path);assert(path.startsWith('/private/tmp/')&&s.isDirectory()&&s.uid===process.getuid()&&(s.mode&0o022)===0);}
assert.equal(sha(zig),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
assert.equal(git(source,'rev-parse','HEAD').trim(),'046b647686419df06c6c7132fb1d15d76185c3e5');
const paths=['gpu_warm','module','root','source'].map(name=>`src/arch/mimo_v2/${name}.zig`),patchFile=join(root,prior?'platform/studio/native/mlx-stream-fcb4011-serving-join.patch':'platform/studio/native/mlx-stream-fcb4011-request-origins.patch'),patch=readFileSync(patchFile,'utf8'),patchSHA=sha(patchFile);
function checkCandidate(){assert.equal(git(mimo,'rev-parse','HEAD').trim(),'fcb4011347ff80eeeb19e2a1f0180e13199c7c8b');assert.equal(git(mimo,'diff','--cached','--name-only').trim(),'');assert.deepEqual(git(mimo,'diff','--name-only').trim().split('\n'),paths);assert.equal(git(mimo,'diff','--no-ext-diff','--no-textconv','--',...paths),patch);}
checkCandidate();
const libraries={'libmlx.dylib':'6a5ee820afed9ce9421297260b4a9fd593749052d582c65deeca428fce61c76e','libmlxc.dylib':'6b4c9224691c2857cf7d386e75c1247cc6b0a4ae17d6ec6d1b455ec177e9929f','libjaccl.dylib':'5c6f3819b3555902ba1ab3a49550643994b49860f09e323fe42dfd6121103282','mlx.metallib':'95974b7de464ec2be7833a914ca5a53d283a70789470fd84218738fc8fcea3e1'};
for(const [name,digest] of Object.entries(libraries))assert.equal(sha(join(source,'lib/mlx/lib',name)),digest);
assert.equal(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim(),'27.2');
const frameworks=run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-path']).trim()+'/System/Library/Frameworks';
run('/usr/bin/git',['clone','--quiet','--no-hardlinks','--no-checkout',mimo,plugin]);git(plugin,'checkout','--quiet','--detach','fcb4011347ff80eeeb19e2a1f0180e13199c7c8b');git(plugin,'apply',patchFile);
const cppFile=join(plugin,'csrc/mimo_gpu_warm.inc'),cppOriginal=readFileSync(cppFile),helperFile=join(root,'platform/studio/native/mimo_join_gate_helpers.inc'),helper=readFileSync(helperFile),composed=Buffer.concat([cppOriginal,Buffer.from('\n'),helper]);
assert.equal(cppOriginal.toString(),git(mimo,'show','HEAD:csrc/mimo_gpu_warm.inc'));
// Append fixture entry points; every original implementation byte is unchanged.
writeFileSync(cppFile,composed);
const nativeNames=['request_ownership.zig','sdk_request_ownership.zig'];
const nativeInputs=Object.fromEntries(nativeNames.map(name=>[name,sha(join(root,'platform/studio/native',name))]));
for(const name of nativeNames)assert.equal(sha(join(source,'src',name)),nativeInputs[name],'Use the reviewed current native companions');
const hostFile=join(source,'src/plugin_host.zig'),hostOriginal=readFileSync(hostFile,'utf8');
const hostComposed=hostOriginal+'\npub const fios_warm_request_owners = @import("sdk_request_ownership.zig");\npub const fios_warm_request_tracker = @import("request_ownership.zig");\n';
const hostPath=join(source,'src',`fios-warm-origin-host-${randomUUID()}.zig`);
const fixtureFile=join(root,'platform/studio/native/mimo_request_origins.zig.fixture'),fixture=readFileSync(fixtureFile),fixturePath=join(plugin,'src/fios-bounded-join.zig');writeFileSync(fixturePath,fixture,{mode:0o600,flag:'wx'});
const original=readFileSync(join(source,'build.zig'),'utf8'),guards='    if (target.result.os.tag == .macos) {\n        if (webp_prefix) |dir| verifyCopiedDeps(b, dir) else verifyBrewDeps(b);\n        verifyMlxStage(b);\n    }\n';assert.equal(original.split(guards).length,2);
let graph=original.replace(guards,'    // Private genuine warm retirement fixture, not staging/release attestation.\n');
const factory=`
fn fiosBoundedJoin(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
 const host=b.createModule(.{ .root_source_file=.{ .cwd_relative=${JSON.stringify(hostPath)} }, .target=target, .optimize=optimize, .link_libc=true, .link_libcpp=true });
 const options=b.addOptions();options.addOption([]const u8,"version","26.10.3-fios-source-fixture");options.addOption(bool,"plugin_profile",false);host.addOptions("build_options",options);
 host.addFrameworkPath(.{ .cwd_relative=${JSON.stringify(frameworks)} });addMlxLib(b,host);addExl3Module(b,host,target,optimize);
 for ([_][]const u8{"IOKit","CoreFoundation","Foundation","Metal","IOSurface"}) |name| host.linkFramework(name,.{});
 host.addRPath(.{ .cwd_relative=${JSON.stringify(join(source,'lib/mlx/lib'))} });
 const module=mlxStreamPkg(b,host,${JSON.stringify(plugin)},"src/fios-bounded-join.zig",target,optimize,false);
 const test_exe=b.addTest(.{ .name="fios-bounded-join", .root_module=module, .filters=&.{"fios ordinary serving warm request origins"} });
 b.step("fios-bounded-join","Private original-worker retirement fixture").dependOn(&b.addInstallArtifact(test_exe,.{}).step);
}
`;
const anchor='    const exe = b.addExecutable(.{';assert.equal(graph.split(anchor).length,3);graph=graph.replace(anchor,'    fiosBoundedJoin(b,target,optimize);\n'+anchor)+factory;
const build=join(source,`fios-bounded-join-${randomUUID()}.zig`);writeFileSync(build,graph,{mode:0o600,flag:'wx'});writeFileSync(hostPath,hostComposed,{mode:0o600,flag:'wx'});
console.log(JSON.stringify({directory,model_posts:0,work_chunks:2,event_delay_ms:3000,fixture_helpers:'additive_only',native_authority:false}));
try {
 for(const mode of ['Debug','ReleaseSafe']){
  const prefix=join(directory,mode);run(zig,['build','fios-bounded-join','--build-file',build,'--prefix',prefix,'-Doptimize='+mode,'-Dmlx-stream-dir='+plugin,'-j2']);
  for(const scenario of ['healthy','cached','missing']){
  const result=spawnSync('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',join(prefix,'bin/fios-bounded-join')],{env:{...env,FIOS_WARM_ORIGIN_SCENARIO:scenario},encoding:'utf8',timeout:20000,maxBuffer:8192});
  const log=(result.stdout??'')+(result.stderr??'');writeFileSync(join(directory,mode+'-'+scenario+'-run.log'),log,{mode:0o600});
  assert(!result.error&&!result.signal);assert.equal(result.status,0,log);
  assert(log.includes(scenario==='missing'?'PASS: serving warm missing origin refuses before chunk submission':'PASS: serving warm actual request origins survive caller release'));assert(log.includes('All 1 tests passed.'));console.log(mode+'/'+scenario+': '+log.trim());
  }
 }
 checkCandidate();assert.equal(readFileSync(join(source,'build.zig'),'utf8'),original);assert.equal(sha(patchFile),patchSHA);assert(readFileSync(cppFile).equals(composed));assert(readFileSync(fixtureFile).equals(fixture));assert(readFileSync(helperFile).equals(helper));
 for(const [name,digest] of Object.entries(libraries))assert.equal(sha(join(source,'lib/mlx/lib',name)),digest);
 for(const name of nativeNames)assert.equal(sha(join(source,'src',name)),nativeInputs[name]);
 assert.equal(readFileSync(hostFile,'utf8'),hostOriginal);assert.equal(readFileSync(hostPath,'utf8'),hostComposed);
 const receipt={ok:true,directory,prior_serving_candidate:prior,scope:'declared_original_warm_source_native_owner_contexts_additive_fixture_entries_and_sdk_inputs_only',native_inputs:nativeInputs,host_original_sha256:hash(hostOriginal),host_composed_sha256:hash(hostComposed),patch_sha256:patchSHA,fixture_sha256:hash(fixture),helper_sha256:hash(helper),original_warm_cpp_sha256:hash(cppOriginal),composed_warm_cpp_sha256:hash(composed),declared_sources:Object.fromEntries(paths.map(p=>[p,sha(join(mimo,p))])),libraries,modes:['Debug','ReleaseSafe'],scenarios:['healthy','cached','missing'],model_posts:0,work_chunks_per_healthy_or_cached_process:2,source_body_rewritten:false,fault_injection:false,native_authority:false,installed:false,native_inference:false};
 writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt)+'\n',{mode:0o600,flag:'wx'});console.log(JSON.stringify(receipt));
} finally {if(readFileSync(build,'utf8')===graph)unlinkSync(build);if(readFileSync(hostPath,'utf8')===hostComposed)unlinkSync(hostPath);}
