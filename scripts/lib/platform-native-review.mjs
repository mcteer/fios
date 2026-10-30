// Private source-review data, never installation, native admission or an inference grant.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {mkdirSync,lstatSync,realpathSync,openSync,closeSync,readSync,writeSync,fstatSync,fsyncSync,chmodSync,readFileSync,writeFileSync,readdirSync,constants} from 'node:fs';
import path from 'node:path';
const names=['libmlx.dylib','libmlxc.dylib','libjaccl.dylib','mlx.metallib','libwebp.dylib','libsharpyuv.dylib','libllama.dylib'];
const sha=b=>createHash('sha256').update(b).digest('hex');
const run=(program,args)=>execFileSync(program,args,{encoding:'utf8',timeout:15000,maxBuffer:1<<20,env:{PATH:'/usr/bin:/bin',LANG:'C',LC_ALL:'C'}});
function privateDirectory(directory) {
 const s=lstatSync(directory);assert(s.isDirectory()&&!s.isSymbolicLink()&&s.uid===process.getuid()&&(s.mode&0o077)===0);
 assert(!run('/bin/ls',['-lde',directory]).split(/\s/)[0].includes('+'),'ACL-bearing review directory refused');
}
function copy(from,to,mode) {
 const input=openSync(from,constants.O_RDONLY|constants.O_NOFOLLOW|constants.O_NONBLOCK);
 let output;
 try {
  const before=fstatSync(input);assert(before.isFile()&&before.nlink===1&&(before.mode&0o6022)===0&&before.size>0&&before.size<=256<<20);
  output=openSync(to,constants.O_WRONLY|constants.O_CREAT|constants.O_EXCL|constants.O_NOFOLLOW,0o600);
  let total=0;const hash=createHash('sha256'),buffer=Buffer.alloc(65536);
  for(;;){const n=readSync(input,buffer,0,buffer.length,null);if(!n)break;total+=n;assert(total<=before.size);hash.update(buffer.subarray(0,n));let at=0;while(at<n)at+=writeSync(output,buffer,at,n-at);}
  const after=fstatSync(input),named=lstatSync(from);assert.equal(total,before.size);
  for(const key of ['dev','ino','uid','mode','nlink','size','mtimeMs','ctimeMs'])assert.equal(after[key],before[key]);
  assert.equal(named.ino,before.ino);assert.equal(named.dev,before.dev);assert(!named.isSymbolicLink());
  fsyncSync(output);chmodSync(to,mode);const digest=hash.digest('hex');assert.equal(sha(readFileSync(to)),digest);return digest;
 }finally{if(output!==undefined)closeSync(output);closeSync(input);}
}
function rpaths(file){return [...run('/usr/bin/otool',['-l',file]).matchAll(/cmd LC_RPATH\s+cmdsize \d+\s+path (.+?) \(offset \d+\)/g)].map(m=>m[1]);}
function sectionDigest(file) {
 const b=readFileSync(file);assert(b.readUInt32LE(0)===0xfeedfacf,'Only reviewed thin arm64 Mach-O artifacts are accepted');
 const h=createHash('sha256');let at=32;
 for(let i=0;i<b.readUInt32LE(16);i++){const command=b.readUInt32LE(at),size=b.readUInt32LE(at+4);assert(size>=8&&at+size<=b.length);
  if(command===0x19){const count=b.readUInt32LE(at+64);assert(72+count*80<=size);for(let n=0;n<count;n++){const section=at+72+n*80,type=b.readUInt32LE(section+64)&255;if([1,12,18].includes(type))continue;const bytes=Number(b.readBigUInt64LE(section+40)),offset=b.readUInt32LE(section+48);assert(Number.isSafeInteger(bytes)&&offset+bytes<=b.length);h.update(b.subarray(section,section+32));h.update(b.subarray(offset,offset+bytes));}}
  at+=size;
 }return h.digest('hex');
}
function normalizePaths(file,wanted,mode,installID) {
 const code=sectionDigest(file);chmodSync(file,0o755);
 if(installID)run('/usr/bin/install_name_tool',['-id',installID,file]);
 for(const value of rpaths(file))run('/usr/bin/install_name_tool',['-delete_rpath',value,file]);
 run('/usr/bin/install_name_tool',['-add_rpath',wanted,file]);run('/usr/bin/codesign',['--force','--sign','-',file]);chmodSync(file,mode);
 assert.deepEqual(rpaths(file),[wanted]);assert.equal(sectionDigest(file),code,'Native code/data section bytes changed');return code;
}
function boundedRead(file,maximum) {
 const fd=openSync(file,constants.O_RDONLY|constants.O_NOFOLLOW|constants.O_NONBLOCK);
 try{const a=fstatSync(fd);assert(a.isFile()&&a.nlink===1&&a.size>0&&a.size<=maximum);const b=Buffer.alloc(a.size);let at=0;while(at<b.length){const n=readSync(fd,b,at,b.length-at,null);assert(n>0);at+=n;}const z=fstatSync(fd),named=lstatSync(file);for(const k of ['dev','ino','uid','mode','size','mtimeMs','ctimeMs'])assert.equal(a[k],z[k]);assert.equal(named.ino,a.ino);assert.equal(named.dev,a.dev);assert(!named.isSymbolicLink());return b;}finally{closeSync(fd);}
}
function dependencies(file) {
 for(const line of run('/usr/bin/otool',['-L',file]).split('\n').slice(1).filter(s=>s.trim())) {
  const dependency=line.trim().split(' (')[0];
  assert(dependency.startsWith('/usr/lib/')||dependency.startsWith('/System/Library/')||names.some(n=>dependency==='@rpath/'+n||dependency==='@loader_path/'+n),'Unreviewed native dependency');
 }
}
export function stageNativeReview({directory,binary,libraries,inputs}) {
 assert(process.platform==='darwin'&&process.getuid()>0&&path.isAbsolute(directory));
 const parent=realpathSync(path.dirname(directory));privateDirectory(parent);assert.equal(path.dirname(directory),parent);
 mkdirSync(directory,{mode:0o700});privateDirectory(directory);
 mkdirSync(path.join(directory,'bin'),{mode:0o700});mkdirSync(path.join(directory,'Frameworks'),{mode:0o700});
 assert.deepEqual(Object.keys(libraries).sort(),[...names].sort());
 const target=path.join(directory,'bin/mlx-serve'),originalBinarySHA256=copy(binary,target,0o555);
 const libraryPayloads={};
 for(const name of names){const file=path.join(directory,'Frameworks',name);copy(libraries[name],file,0o444);if(name.endsWith('.dylib')){const installID=run('/usr/bin/otool',['-D',file]).split('\n')[1]?.trim();if(installID!=='@rpath/'+name||!rpaths(file).every(p=>p==='@loader_path'))libraryPayloads[name]=normalizePaths(file,'@loader_path',0o444,'@rpath/'+name);dependencies(file);}}
 // Only this new private copy changes. Remove build-tree lookup paths so it
 // cannot silently borrow a library from outside its reviewed Frameworks.
 const binaryPayload=normalizePaths(target,'@executable_path/../Frameworks',0o555);
 assert.deepEqual(rpaths(target),['@executable_path/../Frameworks']);dependencies(target);
 const files=Object.fromEntries(['bin/mlx-serve',...names.map(n=>'Frameworks/'+n)].map(name=>[name,{sha256:sha(readFileSync(path.join(directory,name))),bytes:lstatSync(path.join(directory,name)).size}]));
 assert(Object.values(files).reduce((n,f)=>n+f.bytes,0)<=256<<20);
 return {directory,binary:target,sha256:files['bin/mlx-serve'].sha256,receipt:{version:1,purpose:'private_native_source_review',source_fixture_only:true,activation:false,native_inference:false,native_admission_authority:false,coverage:'unknown',original_binary_sha256:originalBinarySHA256,binary_change:'private_rpath_and_adhoc_signature_only',unchanged_section_payloads:{binary:binaryPayload,libraries:libraryPayloads},files,declared_inputs:inputs}};
}
export function finishNativeReview(review) {
 const receipt={...review.receipt,empty_model_validation:'passed'};
 const bytes=Buffer.from(JSON.stringify(receipt)+'\n'),file=path.join(review.directory,'review.json');
 writeFileSync(file,bytes,{flag:'wx',mode:0o400});const fd=openSync(file,constants.O_RDONLY|constants.O_NOFOLLOW);try{fsyncSync(fd);}finally{closeSync(fd);}
 return {directory:review.directory,receipt_sha256:sha(bytes),binary_sha256:review.sha256,native_inference:false,activation:false};
}
export function verifyNativeReview(directory,expected) {
 assert(/^[a-f0-9]{64}$/.test(expected));directory=realpathSync(directory);privateDirectory(directory);
 for(const child of ['bin','Frameworks'])privateDirectory(path.join(directory,child));
 const bytes=boundedRead(path.join(directory,'review.json'),65536);assert(bytes.length<=65536&&sha(bytes)===expected);
 const receipt=JSON.parse(bytes);assert(receipt.version===1&&receipt.purpose==='private_native_source_review'&&receipt.source_fixture_only===true&&receipt.activation===false&&receipt.native_inference===false&&receipt.native_admission_authority===false&&receipt.coverage==='unknown'&&receipt.empty_model_validation==='passed');
 const wanted=['bin/mlx-serve',...names.map(n=>'Frameworks/'+n)];assert.deepEqual(Object.keys(receipt.files).sort(),wanted.sort());
 assert.deepEqual(readdirSync(directory).sort(),['Frameworks','bin','review.json']);assert.deepEqual(readdirSync(path.join(directory,'bin')),['mlx-serve']);assert.deepEqual(readdirSync(path.join(directory,'Frameworks')).sort(),[...names].sort());
 for(const name of wanted){const file=path.join(directory,name),s=lstatSync(file);assert(s.isFile()&&!s.isSymbolicLink()&&s.nlink===1&&s.uid===process.getuid()&&(s.mode&0o222)===0&&s.size===receipt.files[name].bytes&&s.size>0&&s.size<=256<<20);assert.equal(sha(boundedRead(file,256<<20)),receipt.files[name].sha256);}
 return {directory,binary:path.join(directory,'bin/mlx-serve'),receipt};
}
