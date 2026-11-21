import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,mkdirSync,copyFileSync,writeFileSync,readFileSync,rmSync,realpathSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join,dirname,relative,resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {platformPackagingInputs,capturePlatformSources} from '../scripts/lib/platform-source.mjs';
import {reviewPlatformReleaseSource} from '../scripts/lib/platform-source-review.mjs';

function fixture(run) {
 const actual=resolve(import.meta.dirname,'..'),root=realpathSync(mkdtempSync(join(tmpdir(),'fios-release-source-')));
 const git=args=>{
  const result=spawnSync('/usr/bin/git',['-c','user.name=Fixture','-c','user.email=fixture@invalid','-c','core.hooksPath=/dev/null',...args],
   {cwd:root,encoding:'utf8',timeout:10000,env:{PATH:'/usr/bin:/bin',HOME:root,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null'}});
  assert.equal(result.status,0,result.stderr);return result.stdout.trim();
 };
 try {
  for(const input of platformPackagingInputs(actual)){
   const destination=join(root,relative(actual,input));mkdirSync(dirname(destination),{recursive:true});copyFileSync(input,destination);
  }
  git(['init','-q']);git(['add','.']);git(['commit','-qm','Fixture source']);
  const manifest={source_revision:git(['rev-parse','HEAD']),source_tree_sha256:capturePlatformSources(root,platformPackagingInputs(root)).digest};
  run(root,manifest,git);
 }finally{rmSync(root,{recursive:true,force:true});}
}

test('clean exact revision and declared source survive an unchanged recheck',()=>fixture((root,manifest)=>{
 const proof=reviewPlatformReleaseSource(root,manifest);
 assert.equal(proof.records.length,platformPackagingInputs(root).length);
 assert.equal(reviewPlatformReleaseSource(root,manifest,proof),proof);
}));
test('clean checkout refuses wrong revision or declared projection',()=>fixture((root,manifest)=>{
 assert.throws(()=>reviewPlatformReleaseSource(root,{...manifest,source_revision:'0'.repeat(40)}));
 assert.throws(()=>reviewPlatformReleaseSource(root,{...manifest,source_tree_sha256:'0'.repeat(64)}),/Declared source projection/);
}));
test('changed or newly untracked source refuses qualification',()=>fixture((root,manifest)=>{
 const file=join(root,'scripts/check-platform-composition.py'),original=readFileSync(file);
 writeFileSync(file,'changed reviewer');assert.throws(()=>reviewPlatformReleaseSource(root,manifest),/checkout must be clean/);
 writeFileSync(file,original);writeFileSync(join(root,'untracked-review.py'),'new code');
 assert.throws(()=>reviewPlatformReleaseSource(root,manifest),/checkout must be clean/);
}));
test('restoring source bytes cannot conceal mutation during a retained qualification',()=>fixture((root,manifest,git)=>{
 const proof=reviewPlatformReleaseSource(root,manifest),file=join(root,'scripts/check-platform-composition.py'),original=readFileSync(file);
 writeFileSync(file,'changed');writeFileSync(file,original);assert.equal(git(['status','--porcelain']),'');
 assert.throws(()=>reviewPlatformReleaseSource(root,manifest,proof),/Platform build sources changed/);
}));
