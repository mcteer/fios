// Scoped offline source fixture. Only the pinned script is copied; all compiler
// and binary-inspection commands are private stubs. Never run the source tree.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {isAbsolute,join} from 'node:path';
import {fileURLToPath} from 'node:url';

const args=process.argv.slice(2);
if(args.length!==2||args[0]!=='--source-script'||!isAbsolute(args[1]))throw Error('usage: --source-script /absolute/path/to/stock/scripts/build-mlx.sh');
const stock=readFileSync(args[1]);
assert.equal(createHash('sha256').update(stock).digest('hex'),'29dd74594c9c6b6f6cd04072c163a371175044daedf3c33bd2174dd9e4b8f195');
const patch=fileURLToPath(new URL('../platform/studio/native/mlx-serve-26.11.3-build-input-preservation.patch',import.meta.url));
const root=mkdtempSync(join(tmpdir(),'fios-26113-build-inputs-'));
const write=(path,data,mode=0o600)=>writeFileSync(join(root,path),data,{mode});
const env={PATH:`${root}/bin:/usr/bin:/bin`,HOME:root,GIT_CONFIG_NOSYSTEM:'1',GIT_CONFIG_GLOBAL:'/dev/null',MOCK_CMAKE_LOG:join(root,'calls')};
function run(exe,args,{status=0,extra={}}={}){
 const result=spawnSync(exe,args,{cwd:root,env:{...env,...extra},timeout:5000,encoding:'utf8'});
 if(result.error)throw result.error;
 assert.equal(result.status,status,result.stdout+result.stderr);
 return result.stdout+result.stderr;
}
try{
 for(const d of ['scripts','patches','bin','lib/mlx-src','lib/mlxc-src','lib/mlx/lib'])mkdirSync(join(root,d),{recursive:true,mode:0o700});
 const script='scripts/build-mlx.sh';
 write(script,stock);run('git',['apply','--check',patch]);run('git',['apply',patch]);
 run('/bin/bash',['-n',script]);
 const listing='scripts/build-mlx-patches.txt';
 write(listing,'lib/mlxc-src patches/mlxc-gather-qmm-global-scale.patch\n');
 for(const d of ['lib/mlx-src','lib/mlxc-src']){
  run('git',['-C',d,'init','-q']);write(`${d}/CMakeLists.txt`,'original\n');write(`${d}/overlay`,'base\n');
  run('git',['-C',d,'add','.']);run('git',['-C',d,'-c','user.email=fixture@example.invalid','-c','user.name=Fixture','commit','-qm','base']);
 }
 write('patches/mlxc-gather-qmm-global-scale.patch','diff --git a/CMakeLists.txt b/CMakeLists.txt\n--- a/CMakeLists.txt\n+++ b/CMakeLists.txt\n@@ -1 +1 @@\n-original\n+patched\n');
 write('bin/xcrun','#!/bin/sh\ncase "$*" in *show-sdk-version*) echo 27.2;; esac\n',0o700);
 write('bin/cmake','#!/bin/sh\nprintf "%s\\n" "$*" >> "$MOCK_CMAKE_LOG"\n',0o700);
 write('bin/otool','#!/bin/sh\nprintf "LC_BUILD_VERSION\\nminos 26.2\\n"\n',0o700);
 for(const f of ['libmlx.dylib','libmlxc.dylib','mlx.metallib'])write(`lib/mlx/lib/${f}`,'fixture_nax\n');
 const overlay='lib/mlxc-src/overlay',input='lib/mlxc-src/CMakeLists.txt';
 write(overlay,'retained overlay\n');write('calls','');
 const text=p=>readFileSync(join(root,p),'utf8');
 const build=(options={})=>run('/bin/bash',[script],options);
 assert.match(build({status:1,extra:{MLX_BUILD_JOBS:'3'}}),/must be 1 or 2/);
 assert.equal(text(input),'original\n');assert.equal(text('calls'),'');
 build();build({extra:{MLX_BUILD_JOBS:'1'}});
 const calls=text('calls');assert.equal((calls.match(/^--build .* -j 2$/gm)||[]).length,2);
 assert.equal((calls.match(/^--build .* -j 1$/gm)||[]).length,2);
 assert.equal(text(input),'patched\n');assert.equal(text(overlay),'retained overlay\n');
 write(input,'conflict\n');
 assert.match(build({status:1}),/no files were reset/);
 assert.equal(text(input),'conflict\n');assert.equal(text('calls'),calls);
 write(listing,'# disabled\n');assert.match(build({status:1}),/unreviewed dependency patch list/);
 assert.equal(text('calls'),calls);
 // Contrast the exact stock script using the same fake repos and tool stubs.
 // Force a rebuild: stock's matching stamp would mask the tracked-file reset.
 write(script,stock);write(listing,'lib/mlxc-src patches/mlxc-gather-qmm-global-scale.patch\n');
 rmSync(join(root,'lib/mlx/.version'));
 write('bin/sysctl','#!/bin/sh\necho 2\n',0o700);
 build();assert.equal(text(input),'patched\n','stock red control did not overwrite conflict');
 console.log('PASS: pinned source, overlay preservation, stamp rebuild, bounded jobs, conflict and list-drift refusal; stock red control overwrote conflict; stub tools only');
}finally{rmSync(root,{recursive:true,force:true});}
