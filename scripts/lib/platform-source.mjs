// Development packaging provenance, not runtime/model authority. Source edits
// during compilation must not produce a manifest claiming a different input.
import {openSync,closeSync,readSync,lstatSync,fstatSync,constants} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,relative,isAbsolute,dirname} from 'node:path';
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
