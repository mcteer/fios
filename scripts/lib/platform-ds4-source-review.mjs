// Data-only verification of a private DS4 source build. No execution/authority.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync,lstatSync,realpathSync,openSync,readSync,closeSync,fstatSync,constants} from 'node:fs';
import {createHash} from 'node:crypto';
import path from 'node:path';
const sha=b=>createHash('sha256').update(b).digest('hex');
export function verifyDs4DeclaredSource(file,record){
 const matches=s=>{
  assert(s.isFile()&&!s.isSymbolicLink()&&s.nlink===1&&s.size>0&&s.size<=32<<20);
  assert.equal(s.size,record.bytes);assert.equal(s.ino,record.inode);
  assert.equal(s.mtimeMs,record.mtime);assert.equal(s.ctimeMs,record.ctime);
 };
 const named=lstatSync(file);matches(named);
 const fd=openSync(file,constants.O_RDONLY|constants.O_NOFOLLOW|constants.O_NONBLOCK);
 try{
  const before=fstatSync(fd);matches(before);
  for(const key of ['dev','ino','mode','uid','gid','nlink','size','mtimeMs','ctimeMs'])assert.equal(before[key],named[key]);
  const bytes=Buffer.alloc(before.size+1);let count=0;
  while(count<bytes.length){const n=readSync(fd,bytes,count,bytes.length-count,null);if(!n)break;count+=n;}
  assert.equal(count,record.bytes);assert.equal(sha(bytes.subarray(0,count)),record.sha256);
  const after=fstatSync(fd),current=lstatSync(file);matches(after);matches(current);
  for(const key of ['dev','ino','mode','uid','gid','nlink','size','mtimeMs','ctimeMs']){assert.equal(after[key],before[key]);assert.equal(current[key],before[key]);}
 }finally{closeSync(fd);}
}
export function verifyDs4SourceBuild({document,expected,root}){
 assert(process.platform==='darwin'&&process.getuid()>0&&path.isAbsolute(document)&&/^[a-f0-9]{64}$/.test(expected));
 assert.equal(realpathSync(document),document);
 const directory=path.dirname(document),owner=lstatSync(directory),info=lstatSync(document);
 assert(directory.startsWith('/private/tmp/')&&owner.isDirectory()&&owner.uid===process.getuid()&&(owner.mode&0o077)===0);
 assert(info.isFile()&&info.nlink===1&&info.uid===process.getuid()&&info.size>0&&info.size<1<<20);
 const bytes=readFileSync(document);assert.equal(sha(bytes),expected);const receipt=JSON.parse(bytes);
 assert(receipt.version===1&&receipt.purpose==='unapproved_ds4_native_source_build'&&receipt.activation===false&&receipt.native_authority===false&&receipt.executed===false&&receipt.installed===false&&receipt.native_inference===false);
 assert.equal(receipt.revision,'9139e2ae58a41503968a500f36f75895c1ba63fc');assert.equal(receipt.sdk_version,'27.2');
 const source=path.join(directory,'source');assert.equal(realpathSync(source),source);
 const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
 const git=(...argv)=>execFileSync('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,...argv],{env,encoding:'utf8',timeout:5000,maxBuffer:8<<20});
 const files=['ds4.c','ds4.h','ds4_gpu.h','ds4_gpu_tp.h','ds4_metal.m','ds4_tp.c'];
 const patch=readFileSync(path.join(root,'platform/studio/native/ds4-9139e2a-participant-retirement.patch'),'utf8');
 assert.equal(receipt.patch_sha256,sha(patch));assert.equal(git('rev-parse','HEAD').trim(),receipt.revision);
 assert.equal(git('diff','HEAD','--name-only').trim(),files.join('\n'));assert.equal(git('diff','--no-ext-diff','HEAD','--',...files),patch);
 const declared=git('ls-files','-z').split('\0').filter(name=>name==='Makefile'||/\.(?:c|m|h|inc|metal)$/.test(name)).sort();
 assert.deepEqual(Object.keys(receipt.declared_sources).sort(),declared);
 for(const name of declared){
  assert(!path.isAbsolute(name)&&!name.split('/').includes('..'));
  verifyDs4DeclaredSource(path.join(source,name),receipt.declared_sources[name]);
 }
 assert.equal(path.dirname(receipt.artifact.file),source);assert.equal(realpathSync(receipt.artifact.file),receipt.artifact.file);
 const artifact=lstatSync(receipt.artifact.file);assert(artifact.isFile()&&artifact.nlink===1&&artifact.size===receipt.artifact.bytes&&artifact.size<64<<20);
 assert.equal(sha(readFileSync(receipt.artifact.file)),receipt.artifact.sha256);
 return {source,build_receipt_sha256:expected,patch_sha256:receipt.patch_sha256,declared_source_count:declared.length,
  scope:'selected_declared_ds4_sources_recompiled_by_native_root',native_authority:false,installed:false};
}

// Redirect only explicit DS4 include/C/ObjC paths in a disposable build graph.
// Canonical submodule and original graph stay unchanged; shaders are unchanged
// by the strictly verified patch and retain the original embed source graph.
export function bindDs4SourceBuildGraph(graph,selection){
 assert(selection?.scope==='selected_declared_ds4_sources_recompiled_by_native_root'&&selection.native_authority===false);
 let count=0;
 const output=graph.replace(/b\.path\("lib\/ds4(\/[^"\n]*)?"\)/g,(_,suffix='')=>{
  assert(!suffix.split('/').includes('..')&&/^(?:\/[a-z0-9_./]+)?$/.test(suffix));
  const target=selection.source+suffix,s=lstatSync(target);
  assert(suffix?s.isFile()&&!s.isSymbolicLink():s.isDirectory());++count;
  return '.{ .cwd_relative = '+JSON.stringify(target)+' }';
 });
 assert(count>=8&&count<=40,'Unexpected DS4 build-source graph');
 return output;
}
