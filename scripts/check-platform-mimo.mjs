#!/usr/bin/env node
// CPU state-machine proof over the genuine pinned plugin/SDK. No model,
// Metal execution, production patch enrollment, release staging or activation.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {createHash,randomUUID} from 'node:crypto';
import {lstatSync,readFileSync,realpathSync,rmSync,writeFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=fileURLToPath(new URL('../',import.meta.url)),args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.getuid()!==0);
assert((args.length===6||(args.length===7&&['--debug','--mutation-early-ack'].includes(args[6])))&&args[0]==='--source'&&args[2]==='--zig'&&args[4]==='--mimo-source'&&[args[1],args[3],args[5]].every(path.isAbsolute),
 'Usage: check-platform-mimo.mjs --source ABS_NATIVE --zig ABS_ZIG --mimo-source ABS_DISPOSABLE_PINNED_PLUGIN [--debug|--mutation-early-ack]');
const optimize=args[6]==='--debug'?'Debug':'ReleaseSafe',mutation=args[6]==='--mutation-early-ack';
const [source,zig,mimo]=[args[1],args[3],args[5]].map(value=>realpathSync(value));
for(const directory of [source,mimo]) {const info=lstatSync(directory);assert(directory.startsWith('/private/tmp/')&&info.isDirectory()&&info.uid===process.getuid()&&(info.mode&0o022)===0);}
const run=(file,argv,options={})=>execFileSync(file,argv,{encoding:'utf8',timeout:600000,maxBuffer:16*1024*1024,...options});
const git=(directory,...argv)=>run('git',['--no-replace-objects','-C',directory,...argv]);
const sha=file=>{const info=lstatSync(file);assert(info.isFile()&&!info.isSymbolicLink());return createHash('sha256').update(readFileSync(file)).digest('hex');};
assert.equal(sha(zig),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
assert.equal(git(mimo,'rev-parse','HEAD').trim(),'fcb4011347ff80eeeb19e2a1f0180e13199c7c8b');
assert.equal(git(mimo,'diff','--cached','--name-only').trim(),'','staged plugin changes are not allowed');
assert.equal(git(mimo,'diff','--name-only').trim(),'src/arch/mimo_v2/gpu_warm.zig');
const pluginPatch=readFileSync(path.join(root,'platform/studio/native/mlx-stream-fcb4011-retirement.patch'),'utf8');
const pluginSource=path.join(mimo,'src/arch/mimo_v2/gpu_warm.zig'),pluginOriginal=readFileSync(pluginSource,'utf8');
assert.equal(git(mimo,'diff','--','src/arch/mimo_v2/gpu_warm.zig'),pluginPatch);
run(process.execPath,[path.join(root,'scripts/check-platform-native.mjs'),'--source',source,'--zig',zig]);
// The earlier linked fixture stages these REAL header/library inputs in this
// disposable checkout. Never substitute a fake SDK or touch installed inputs.
const libraries={'libmlx.dylib':'6a5ee820afed9ce9421297260b4a9fd593749052d582c65deeca428fce61c76e','libmlxc.dylib':'6b4c9224691c2857cf7d386e75c1247cc6b0a4ae17d6ec6d1b455ec177e9929f','libjaccl.dylib':'5c6f3819b3555902ba1ab3a49550643994b49860f09e323fe42dfd6121103282','mlx.metallib':'95974b7de464ec2be7833a914ca5a53d283a70789470fd84218738fc8fcea3e1'};
for(const [name,digest]of Object.entries(libraries)) {assert.equal(sha(path.join(source,'lib/mlx/lib',name)),digest);assert.equal(sha(path.join('/Applications/MLX-Serve.app/Contents/Frameworks',name)),digest);}
const original=readFileSync(path.join(source,'build.zig'),'utf8');
const guards='    if (target.result.os.tag == .macos) {\n        if (webp_prefix) |dir| verifyCopiedDeps(b, dir) else verifyBrewDeps(b);\n        verifyMlxStage(b);\n    }\n';
assert.equal(original.split(guards).length,2);
let graph=original.replace(guards,'    // CPU SOURCE FIXTURE ONLY, never upstream release attestation.\n');
const host='    addMlxLib(b, host);\n';
assert.equal(graph.split(host).length,2);
graph=graph.replace(host,host+`    host.addRPath(.{ .cwd_relative = ${JSON.stringify(path.join(source,'lib/mlx/lib'))} });\n`);
const runner='        const run = b.addRunArtifact(t);\n        test_step.dependOn(&run.step);';
assert.equal(graph.split(runner).length,2);
graph=graph.replace(runner,'        const run = b.addRunArtifact(t);\n        run.has_side_effects = true;\n        run.setEnvironmentVariable("MLX_DEFAULT_DEVICE", "cpu");\n        test_step.dependOn(&run.step);');
const filename=`fios-mimo-${randomUUID()}.zig`,generated=path.join(source,filename);
try {
 writeFileSync(generated,graph,{flag:'wx',mode:0o600});
 if(mutation) {
  const checkpoint='            self.drain();\n            _ = std.c.pthread_mutex_lock(&self.mu);\n            if (self.fios_closed.load(.seq_cst) and !self.quit.load(.seq_cst)) self.fios_ack = self.fios_sequence;\n            _ = std.c.pthread_mutex_unlock(&self.mu);\n            self.park();';
  assert.equal(pluginOriginal.split(checkpoint).length,2);
  const broken=checkpoint.replace('            self.drain();\n','').replace('            self.park();','            self.drain();\n            self.park();');
  writeFileSync(pluginSource,pluginOriginal.replace(checkpoint,broken));
 }
 const cases=mutation?[['fios mimo retirement',/8 pass, 1 fail \(9 total\)/]]:[['fios mimo retirement',/9 pass \(9 total\)/],['mimo gpu warm',/13 pass, 1 skip \(14 total\)/]];
 for(const [filter,summary]of cases) {
  const result=spawnSync('/usr/bin/nice',['-n','10',zig,'build','mlx-stream-test','--build-file',filename,`-Doptimize=${optimize}`,'-Dmas=true',`-Dmlx-stream-dir=${mimo}`,`-Dtest-filter=${filter}`,'--summary','all'],{cwd:source,env:{PATH:'/usr/bin:/bin:/usr/sbin:/sbin',HOME:process.env.HOME,TMPDIR:process.env.TMPDIR??'/tmp'},encoding:'utf8',timeout:600000,maxBuffer:16*1024*1024});
  const output=(result.stdout??'')+(result.stderr??'');console.log(output);
  assert.equal(result.status,mutation?1:0,'MIMO CPU retirement/default-policy fixture or expected mutation witness failed');
  if(mutation)assert.match(output,/expected \.pending, found \.retired/,'early acknowledgement must fail the actual blocked-retire assertion, not merely compilation/linkage');
  assert.match(output,summary,'expected every selected CPU test and import discovery; GPU-window test remains skipped, not forged enabled');
 }
 if(mutation)writeFileSync(pluginSource,pluginOriginal);
 assert.equal(readFileSync(path.join(source,'build.zig'),'utf8'),original);
 assert.equal(git(mimo,'diff','--','src/arch/mimo_v2/gpu_warm.zig'),pluginPatch,'plugin input changed during proof');
 assert.equal(git(mimo,'diff','--cached','--name-only').trim(),'');
 for(const [name,digest]of Object.entries(libraries))assert.equal(sha(path.join('/Applications/MLX-Serve.app/Contents/Frameworks',name)),digest);
 console.log(mutation?'PASS: optimized early-ack mutation fails the actual blocked-retire assertion; exact source restored; no Metal/model/terminal authority.':'PASS: pinned MIMO CPU drain failure and explicit fixture pause/rearm proof over genuine SDK; NOT Metal/model/all-backend terminal or production enrollment acceptance.');
}finally {if(mutation)writeFileSync(pluginSource,pluginOriginal);rmSync(generated,{force:true});}
