// Development packaging provenance, not runtime/model authority. Source edits
// during compilation must not produce a manifest claiming a different input.
import {openSync,closeSync,readSync,lstatSync,fstatSync,readdirSync,constants} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,relative,isAbsolute,dirname,join} from 'node:path';
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const fail=()=>{throw Error('Platform build sources changed or are not regular bounded inputs');};
const identity=s=>[s.dev,s.ino,s.mode,s.size,s.mtimeNs,s.ctimeNs].join(':');
function readStable(file){
 const before=lstatSync(file,{bigint:true});
 if(!before.isFile()||before.isSymbolicLink()||before.size>16n*1024n*1024n)fail();
 const fd=openSync(file,constants.O_RDONLY|constants.O_NOFOLLOW);
 try{
  if(identity(before)!==identity(fstatSync(fd,{bigint:true})))fail();
  const bytes=Buffer.alloc(Number(before.size)+1);let count=0;
  while(count<bytes.length){const n=readSync(fd,bytes,count,bytes.length-count,count);if(!n)break;count+=n;}
  if(count!==Number(before.size)||identity(before)!==identity(fstatSync(fd,{bigint:true}))||identity(before)!==identity(lstatSync(file,{bigint:true})))fail();
  return {digest:sha(bytes.subarray(0,count)),identity:identity(before)};
 }finally{closeSync(fd);}
}
// One explicit source closure shared by the packer and qualification. The
// installer also consumes these Python reviewers; omitting them would let a
// changed review implementation retain an unchanged packaging source digest.
export function platformPackagingInputs(root){
 root=resolve(root);
 function files(directory){
  return readdirSync(directory).sort().flatMap(name=>{
   const file=join(directory,name),info=lstatSync(file);
   if(info.isSymbolicLink()||(!info.isFile()&&!info.isDirectory()))fail();
   return info.isDirectory()?files(file):[file];
  });
 }
 const fixed=['platform/studio/Package.swift','platform/studio/Package.resolved',
  'platform/studio/sandbox/runner.py','platform/studio/sandbox/Dockerfile','platform/studio/deployment/release.json',
  'uv.lock','scripts/package-platform.mjs','scripts/install-platform.mjs','scripts/lib/platform-state-plan.mjs',
  'scripts/lib/platform-release.mjs','scripts/lib/platform-source.mjs','scripts/check-platform-composition.py',
  'scripts/compose-platform-candidate.py','scripts/check-platform-python-candidate.py','scripts/package-platform-python.py'];
 return [...files(join(root,'platform/studio/Sources')),...fixed.map(name=>join(root,name)),
  ...files(join(root,'platform/studio/deployment')).filter(file=>file.endsWith('.plist'))].sort();
}
export function capturePlatformSources(root,paths){
 root=resolve(root);
 if(!Array.isArray(paths)||!paths.length||paths.length>4096)fail();
 const names=paths.map(file=>resolve(file)).sort();
 if(new Set(names).size!==names.length)fail();
 const records=names.map(file=>{
  const name=relative(root,file);
  if(!name||name==='..'||name.startsWith('../')||isAbsolute(name))fail();
  return Object.freeze({name,...readStable(file)});
 });
 const parents=new Set();
 for(const file of names){let parent=dirname(file);while(true){parents.add(parent);if(parent===root)break;parent=dirname(parent);}}
 const directories=[...parents].sort().map(parent=>{
  const stat=lstatSync(parent,{bigint:true});if(!stat.isDirectory()||stat.isSymbolicLink())fail();
  return Object.freeze({name:relative(root,parent)||'.',identity:identity(stat)});
 });
 return Object.freeze({root,records:Object.freeze(records),directories:Object.freeze(directories),digest:sha(Buffer.from(records.map(v=>v.name+'\0'+v.digest).join('\n')))});
}
export function verifyPlatformSources(proof,root,paths){
 const after=capturePlatformSources(root,paths);
 if(proof.root!==after.root||proof.digest!==after.digest||proof.records.length!==after.records.length||
    proof.records.some((v,i)=>v.name!==after.records[i].name||v.identity!==after.records[i].identity)||
    proof.directories.length!==after.directories.length||proof.directories.some((v,i)=>v.name!==after.directories[i].name||v.identity!==after.directories[i].identity))fail();
}
