#!/usr/bin/env node
// Fresh genuine upstream build, data-only result. Never execute/install it.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync,mkdtempSync,mkdirSync,lstatSync,realpathSync,readdirSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..'),args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===5&&args[0]==='--isolated'&&args[1]==='--source'&&args[3]==='--developer-dir');
const source=realpathSync(args[2]),developer=realpathSync(args[4]),info=lstatSync(source);
assert(source.startsWith('/private/tmp/')&&info.isDirectory()&&info.uid===process.getuid()&&(info.mode&0o022)===0);
assert.equal(developer,'/Applications/Xcode.app/Contents/Developer');
const directory=mkdtempSync('/private/tmp/fios-ds4-build-'),checkout=path.join(directory,'source'),home=path.join(directory,'home');mkdirSync(home,{mode:0o700});
const env={PATH:'/usr/bin:/bin',HOME:home,TMPDIR:directory,LANG:'C',LC_ALL:'C',DEVELOPER_DIR:developer,GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const run=(file,argv,options={})=>execFileSync(file,argv,{env,encoding:'utf8',timeout:30000,maxBuffer:8<<20,...options});
const git=(dir,...argv)=>run('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',dir,...argv]);
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
try{
 const revision='9139e2ae58a41503968a500f36f75895c1ba63fc';
 assert.equal(git(source,'rev-parse','HEAD').trim(),revision);
 assert.equal(git(source,'diff','HEAD','--name-only').trim(),'ds4.c\nds4_gpu.h\nds4_gpu_tp.h\nds4_metal.m');
 const patchFile=path.join(root,'platform/studio/native/ds4-9139e2a-participant-retirement.patch'),patch=readFileSync(patchFile,'utf8');
 assert.equal(git(source,'diff','--no-ext-diff','HEAD','--','ds4.c','ds4_gpu.h','ds4_gpu_tp.h','ds4_metal.m'),patch);
 assert.equal(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim(),'27.2');
 const compiler=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--find','clang']).trim()),sdk=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-path']).trim());
 assert(compiler.startsWith(developer+'/Toolchains/')&&sdk.startsWith(developer+'/Platforms/'));
 assert([compiler,sdk].every(value=>/^[A-Za-z0-9_./+-]+$/.test(value)),'Make tool/SDK paths must be fixed safe words');
 run('/usr/bin/codesign',['--verify','--strict','--test-requirement','=anchor apple',compiler]);
 run('/usr/bin/git',['clone','--quiet','--no-hardlinks','--no-checkout',source,checkout]);git(checkout,'checkout','--quiet','--detach',revision);
 git(checkout,'apply','--check',patchFile);git(checkout,'apply',patchFile);
 const files=git(checkout,'ls-files','-z').split('\0').filter(name=>name==='Makefile'||/\.(?:c|m|h|inc|metal)$/.test(name)).sort();
 assert(files.length>10&&files.length<2000);
 const capture=()=>Object.fromEntries(files.map(name=>{
  assert(!path.isAbsolute(name)&&!name.split('/').includes('..'));
  const file=path.join(checkout,name),s=lstatSync(file);assert(s.isFile()&&!s.isSymbolicLink()&&s.nlink===1&&s.size<=32<<20);
  return [name,{bytes:s.size,sha256:sha(readFileSync(file)),inode:s.ino,mtime:s.mtimeMs,ctime:s.ctimeMs}];
 }));
 const before=capture();
 // Explicit trusted tool/flags. A fresh checkout avoids cached object reuse.
 const cflags=`-isysroot ${sdk} -O3 -ffast-math -g -mcpu=native -Wall -Wextra -std=c99`;
 const objcflags=`-isysroot ${sdk} -O3 -ffast-math -g -mcpu=native -Wall -Wextra -fobjc-arc`;
 const output=run('/usr/bin/make',['-j2',`CC=${compiler}`,`CFLAGS=${cflags}`,`OBJCFLAGS=${objcflags}`,'ds4-bench'],{cwd:checkout,timeout:180000});
 writeFileSync(path.join(directory,'build.log'),output,{mode:0o600});
 assert.deepEqual(capture(),before,'Declared source changed during build');
 assert.equal(git(checkout,'diff','--no-ext-diff','HEAD','--','ds4.c','ds4_gpu.h','ds4_gpu_tp.h','ds4_metal.m'),patch);
 assert.equal(git(checkout,'diff','HEAD','--name-only').trim(),'ds4.c\nds4_gpu.h\nds4_gpu_tp.h\nds4_metal.m');
 assert.equal(git(source,'diff','--no-ext-diff','HEAD','--','ds4.c','ds4_gpu.h','ds4_gpu_tp.h','ds4_metal.m'),patch);
 assert.equal(readFileSync(patchFile,'utf8'),patch);
 const artifact=path.join(checkout,'ds4-bench'),s=lstatSync(artifact);assert(s.isFile()&&s.nlink===1&&s.size>0&&s.size<64<<20);
 const objects=Object.fromEntries(readdirSync(checkout).filter(name=>name.endsWith('.o')).sort().map(name=>{const file=path.join(checkout,name),s=lstatSync(file);assert(s.isFile()&&!s.isSymbolicLink()&&s.nlink===1&&s.size>0&&s.size<64<<20);return [name,{bytes:s.size,sha256:sha(readFileSync(file))}];}));
 const receipt={version:1,purpose:'unapproved_ds4_native_source_build',activation:false,native_authority:false,executed:false,installed:false,native_inference:false,source_scope:'declared_tracked_sources_not_whole_native_provenance',revision,patch_sha256:sha(patch),compiler_sha256:sha(readFileSync(compiler)),sdk_version:'27.2',declared_sources:before,objects,artifact:{file:artifact,bytes:s.size,sha256:sha(readFileSync(artifact))}};
 const bytes=Buffer.from(JSON.stringify(receipt)+'\n');writeFileSync(path.join(directory,'candidate.json'),bytes,{mode:0o400,flag:'wx'});
 console.log(JSON.stringify({source_build_only:true,executed:false,installed:false,native_authority:false,declared_source_count:files.length,artifact:receipt.artifact,receipt_sha256:sha(bytes),directory}));
}catch(error){console.error('Build state retained:',directory);throw error;}
