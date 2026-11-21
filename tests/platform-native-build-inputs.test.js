import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,rmSync,existsSync} from 'node:fs';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {execFileSync,spawnSync} from 'node:child_process';

// Execute the real upstream recipe plus the reviewed build-only patch. All
// compiler/SDK commands are inert fixtures; no library/model/daemon is loaded.
const baseline=readFileSync('tests/fixtures/platform/current-upstream-build-mlx.sh.fixture');
const patch=readFileSync('platform/studio/native/mlx-serve-26.11.2-build-input-preservation.patch');
assert.equal(createHash('sha256').update(baseline).digest('hex'),'04b78c2aa1c27ae9141b6b9ce48ac5664c79770e67ad9a9f44ce844d88707df3');
function fixture(t,{patched=true,applied=false,conflict=false,dirty=false,stamp=false,jobs='2',metal=true}={}) {
  const root=mkdtempSync(path.join(tmpdir(),'fios-native-build-inputs-'));
  t.after(()=>rmSync(root,{recursive:true,force:true}));
  const git=(cwd,...args)=>execFileSync('git',['-c','core.hooksPath=/dev/null','-c','commit.gpgsign=false','-c','user.name=Fixture','-c','user.email=fixture@invalid','-C',cwd,...args],{stdio:['pipe','pipe','pipe'],timeout:5000,maxBuffer:1<<20});
  for(const dir of ['scripts','patches','lib/mlx-src','lib/mlxc-src','lib/mlx/lib','bin'])mkdirSync(path.join(root,dir),{recursive:true});
  writeFileSync(path.join(root,'scripts/build-mlx.sh'),baseline);
  git(root,'init','-q');
  if(patched)execFileSync('git',['-C',root,'apply','-'],{input:patch,stdio:['pipe','pipe','pipe'],timeout:5000,maxBuffer:1<<20});
  for(const dir of ['mlx-src','mlxc-src']){
    const cwd=path.join(root,'lib',dir);git(cwd,'init','-q');
    writeFileSync(path.join(cwd,'CMakeLists.txt'),'# fixture\n');
    writeFileSync(path.join(cwd,'tracked.txt'),'before\n');
    writeFileSync(path.join(cwd,'overlay.txt'),'original\n');
    git(cwd,'add','.');git(cwd,'commit','-qm','baseline');
  }
  const mlxc=path.join(root,'lib/mlxc-src');
  writeFileSync(path.join(mlxc,'tracked.txt'),'after\n');
  const gather=git(mlxc,'diff','--','tracked.txt');
  writeFileSync(path.join(root,'patches/mlxc-gather-qmm-global-scale.patch'),gather);
  writeFileSync(path.join(mlxc,'tracked.txt'),conflict?'unrelated operator change\n':applied?'after\n':'before\n');
  if(dirty)for(const dir of ['mlx-src','mlxc-src'])writeFileSync(path.join(root,'lib',dir,'overlay.txt'),'reviewed local overlay\n');
  const bin=path.join(root,'bin');
  const stub=(name,body)=>writeFileSync(path.join(bin,name),'#!/bin/sh\n'+body+'\n',{mode:0o700});
  stub('xcrun',metal?'case "$*" in *--show-sdk-version*) echo 27.2;; esac':'exit 1');
  stub('sysctl','echo 2');
  stub('cmake','printf "%s\\n" "$*" >> "$FIXTURE_ROOT/cmake.log"\nmkdir -p "$FIXTURE_ROOT/lib/mlx/lib"\nfor name in libmlx.dylib libmlxc.dylib mlx.metallib; do echo fixture > "$FIXTURE_ROOT/lib/mlx/lib/$name"; done');
  stub('strings','echo fixture_nax');stub('otool','printf "LC_BUILD_VERSION\\n minos 26.2\\n"');
  if(stamp){
    const rev=dir=>git(path.join(root,'lib',dir),'rev-parse','--short=12','HEAD').toString().trim();
    const hash=createHash('sha1').update(gather).digest('hex').slice(0,12);
    writeFileSync(path.join(root,'lib/mlx/.version'),`mlx=${rev('mlx-src')} mlxc=${rev('mlxc-src')} patch=${hash} target=26.2\n`);
    for(const file of ['libmlx.dylib','libmlxc.dylib','mlx.metallib'])writeFileSync(path.join(root,'lib/mlx/lib',file),'stale\n');
  }
  const run=()=>spawnSync('/bin/bash',[path.join(root,'scripts/build-mlx.sh')],{env:{PATH:bin+path.delimiter+process.env.PATH,HOME:root,LANG:'C',LC_ALL:'C',FIXTURE_ROOT:root,MLX_BUILD_JOBS:jobs},encoding:'utf8',timeout:10000,maxBuffer:1<<20});
  return {root,mlxc,run};
}

test('build recipe preserves source overlays on an already-applied patch',t=>{
  const f=fixture(t,{applied:true,dirty:true});const result=f.run();
  assert.equal(result.status,0,result.stderr);
  assert.equal(readFileSync(path.join(f.mlxc,'tracked.txt'),'utf8'),'after\n');
  for(const dir of ['mlx-src','mlxc-src'])assert.equal(readFileSync(path.join(f.root,'lib',dir,'overlay.txt'),'utf8'),'reviewed local overlay\n');
});
test('build recipe applies a missing patch without dropping adjacent overlays',t=>{
  const f=fixture(t,{dirty:true});const result=f.run();assert.equal(result.status,0,result.stderr);
  assert.equal(readFileSync(path.join(f.mlxc,'tracked.txt'),'utf8'),'after\n');
  assert.equal(readFileSync(path.join(f.mlxc,'overlay.txt'),'utf8'),'reviewed local overlay\n');
});
test('conflicting operator edits fail before build and remain intact',t=>{
  const f=fixture(t,{conflict:true,dirty:true});const result=f.run();assert.notEqual(result.status,0);
  assert.match(result.stderr,/no files were reset/);
  assert.equal(readFileSync(path.join(f.mlxc,'tracked.txt'),'utf8'),'unrelated operator change\n');
  assert(!existsSync(path.join(f.root,'cmake.log')));
});
test('matching historical stamps cannot skip dirty source builds',t=>{
  const f=fixture(t,{applied:true,dirty:true,stamp:true});const result=f.run();assert.equal(result.status,0,result.stderr);
  assert(existsSync(path.join(f.root,'cmake.log')));
  assert.equal(readFileSync(path.join(f.root,'lib/mlx/lib/libmlx.dylib'),'utf8'),'fixture\n');
});
test('matching historical stamps cannot bypass missing Metal tooling',t=>{
  const f=fixture(t,{applied:true,stamp:true,metal:false});const result=f.run();assert.notEqual(result.status,0);
  assert.match(result.stderr,/Metal compiler unavailable/);assert(!existsSync(path.join(f.root,'cmake.log')));
});
test('compile concurrency is bounded before changing source',t=>{
  const f=fixture(t,{jobs:'3'});const result=f.run();assert.notEqual(result.status,0);
  assert.match(result.stderr,/MLX_BUILD_JOBS must be 1 or 2/);
  assert.equal(readFileSync(path.join(f.mlxc,'tracked.txt'),'utf8'),'before\n');
  assert(!existsSync(path.join(f.root,'cmake.log')));
});
test('upstream control reproduces lost conflicting source edits',t=>{
  const f=fixture(t,{patched:false,conflict:true});const result=f.run();assert.equal(result.status,0,result.stderr);
  assert.equal(readFileSync(path.join(f.mlxc,'tracked.txt'),'utf8'),'after\n');
});
test('upstream control reproduces stale cache bypassing toolchain checks',t=>{
  const f=fixture(t,{patched:false,applied:true,dirty:true,stamp:true,metal:false});const result=f.run();
  assert.equal(result.status,0,result.stderr);assert.match(result.stdout,/nothing to do/);
  assert(!existsSync(path.join(f.root,'cmake.log')));
  assert.equal(readFileSync(path.join(f.root,'lib/mlx/lib/libmlx.dylib'),'utf8'),'stale\n');
});
