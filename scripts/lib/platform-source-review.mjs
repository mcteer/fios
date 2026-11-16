// Read-only development source qualification, never installation authority.
import assert from 'node:assert/strict';
import {lstatSync,realpathSync} from 'node:fs';
import {isAbsolute} from 'node:path';
import {spawnSync} from 'node:child_process';
import {platformPackagingInputs,capturePlatformSources,verifyPlatformSources} from './platform-source.mjs';

export function reviewPlatformReleaseSource(source,manifest,previous) {
 assert(isAbsolute(source)&&realpathSync(source)===source);
 const info=lstatSync(source);
 assert(info.isDirectory()&&info.uid===process.getuid()&&(info.mode&0o022)===0);
 const git=argv=>{
  const result=spawnSync('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,...argv],
   {encoding:'utf8',timeout:10000,maxBuffer:1<<20,env:{PATH:'/usr/bin:/bin',HOME:source,LANG:'C',LC_ALL:'C',
    GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'}});
  assert(!result.error&&result.status===0,'Source revision/cleanliness check failed');return result.stdout;
 };
 assert.equal(git(['rev-parse','HEAD']).trim(),manifest.source_revision);
 assert.equal(git(['status','--porcelain','--untracked-files=all']),'','Source checkout must be clean');
 const inputs=platformPackagingInputs(source);
 if(previous)verifyPlatformSources(previous,source,inputs);
 const proof=previous??capturePlatformSources(source,inputs);
 assert.equal(proof.digest,manifest.source_tree_sha256,'Declared source projection differs from packaged manifest');
 return proof;
}
