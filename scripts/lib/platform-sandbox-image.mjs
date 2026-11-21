import {openSync,readSync,closeSync,lstatSync,fstatSync,constants} from 'node:fs';
import {createHash} from 'node:crypto';
export const sandboxImageEnvironment=Object.freeze(['PATH=/opt/venv/bin:/usr/bin:/bin','LANG=C','LC_ALL=C','PYTHONDONTWRITEBYTECODE=1']);
const digest=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
const immutable=value=>typeof value==='string'&&/^sha256:[a-f0-9]{64}$/.test(value);
const fail=()=>{throw Error('Sandbox image review refused');};
export function sandboxImageFile(path,maximum=65536){
 const named=lstatSync(path,{bigint:true});
 const safe=s=>s.isFile()&&s.nlink===1n&&[0n,BigInt(process.getuid())].includes(s.uid)&&(s.mode&0o6022n)===0n&&s.size>0n&&s.size<=BigInt(maximum);
 const same=(a,b)=>['dev','ino','mode','uid','gid','nlink','size','mtimeNs','ctimeNs'].every(k=>a[k]===b[k]);
 if(!safe(named))fail();const fd=openSync(path,constants.O_RDONLY|constants.O_NONBLOCK|constants.O_NOFOLLOW);
 try{
  const initial=fstatSync(fd,{bigint:true});if(!safe(initial)||!same(named,initial))fail();
  const data=Buffer.alloc(Number(initial.size)+1);let count=0;
  while(count<data.length){const n=readSync(fd,data,count,data.length-count,null);if(!n)break;count+=n;}
  if(BigInt(count)!==initial.size||!same(initial,fstatSync(fd,{bigint:true}))||!same(initial,lstatSync(path,{bigint:true})))fail();
  return data.subarray(0,count);
 }finally{closeSync(fd);}
}
export function readSandboxBaseReview(path,expected){
 if(!digest(expected))fail();const bytes=sandboxImageFile(path,4096);
 if(createHash('sha256').update(bytes).digest('hex')!==expected)fail();
 const value=JSON.parse(bytes.toString('utf8'));
 if(!bytes.equals(Buffer.from(JSON.stringify(value,null,2)+'\n'))||Object.keys(value).sort().join(',')!==['version','purpose','base_image','docker_cli_sha256','python_version','platform','provenance_sha256','dockerfile_sha256','runner_sha256'].sort().join(',')||
    value.version!==1||value.purpose!=='sandbox_base_build_review'||!immutable(value.base_image)||!digest(value.docker_cli_sha256)||value.python_version!=='3.11.17'||value.platform!=='linux/arm64'||!digest(value.provenance_sha256)||!digest(value.dockerfile_sha256)||!digest(value.runner_sha256))fail();
 return Object.freeze(value); // Metadata only; no enrollment/admission authority.
}
export function validateSandboxBase(value,expected){
 if(!immutable(expected)||value?.Id!==expected||value.Os!=='linux'||value.Architecture!=='arm64'||
    (value.Config?.OnBuild!=null&&(!Array.isArray(value.Config.OnBuild)||value.Config.OnBuild.length)))fail();
 return expected;
}
export function validateSandboxImage(value,expected){
 if(!immutable(expected)||value?.Id!==expected||value.Os!=='linux'||value.Architecture!=='arm64')fail();
 const c=value.Config;
 if(!c||c.User!=='65532:65532'||c.WorkingDir!=='/workspace'||JSON.stringify(c.Entrypoint)!==JSON.stringify(['/opt/venv/bin/python','-I','-B','/runner.py'])||
    (c.Cmd!=null&&(!Array.isArray(c.Cmd)||c.Cmd.length))||JSON.stringify(c.Env)!==JSON.stringify(sandboxImageEnvironment)||
    (c.ExposedPorts&&Object.keys(c.ExposedPorts).length)||(c.Volumes&&Object.keys(c.Volumes).length)||c.Healthcheck||(c.OnBuild!=null&&(!Array.isArray(c.OnBuild)||c.OnBuild.length)))fail();
 return expected;
}
