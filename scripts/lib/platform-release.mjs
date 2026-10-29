import {readSync,lstatSync,opendirSync,openSync,closeSync,fstatSync,constants} from 'node:fs';
import {join,resolve} from 'node:path';
import {createHash} from 'node:crypto';
export const platformArtifactModes=Object.freeze({
  'bin/studio-manager':0o755,'bin/studio-supervisor':0o755,'bin/studio-session':0o755,'bin/studioctl':0o755,
  'sandbox/runner.py':0o644,'sandbox/Dockerfile':0o644,'python/uv.lock':0o644,
  'launchd/lab.fios.studio.supervisor.plist':0o644,'launchd/lab.fios.studio.session.plist':0o644,
});
const digest=value=>typeof value==='string'&&/^[a-f0-9]{64}$/.test(value);
const fail=()=>{throw Error('Invalid or unsupported platform release');};
function exact(value,keys){
  if(!value||typeof value!=='object'||Array.isArray(value)||Object.keys(value).sort().join('\0')!==[...keys].sort().join('\0'))fail();
}
export function validatePlatformManifest(value,{template=false}={}){
  exact(value,['schema','approval','architecture','toolchain','sqlite','journal_schema','journal_application_id','python','native_inventory','approved_sandbox_images','activation',...(template?[]:['source_revision','source_tree_sha256','artifacts','package_complete'])]);
  if(value.schema!==1||value.approval!=='development_observation_only'||value.architecture!=='arm64'||value.journal_schema!==8||value.journal_application_id!=='FIS9')fail();
  exact(value.toolchain,['swift','swift_build','sdk','minimum_macos']);
  exact(value.sqlite,['provider','version']);
  if(value.sqlite.provider!=='macos_system'||value.sqlite.version!=='3.54.0')fail();
  if(value.toolchain.swift!=='6.4'||value.toolchain.swift_build!=='swiftlang-6.4.0.34.1'||value.toolchain.sdk!=='27.0'||value.toolchain.minimum_macos!=='14.0')fail();
  exact(value.python,['version','package','package_version','uv_lock_sha256','policy_sha256','policy_input_utf16','immutable_tree_enrolled']);
  if(value.python.version!=='3.11.17'||value.python.package!=='fios-agent'||value.python.package_version!=='0.1.0'||!digest(value.python.uv_lock_sha256)||!digest(value.python.policy_sha256)||value.python.policy_input_utf16!==504||value.python.immutable_tree_enrolled!==false)fail();
  exact(value.native_inventory,['hosts','mlx_version','mlx_server_sha256','mlx_application_sha256','mlx_application_identifier','mlx_team_identifier','orbstack_version','orbstack_application_sha256','docker_cli_sha256','orbctl_cli_sha256','all_client_coverage','enrolled']);
  const native=value.native_inventory;
  if(JSON.stringify(native.hosts)!==JSON.stringify(['fios-edge-a.lab','fios-edge-b.lab'])||native.mlx_version!=='26.10.3'||native.mlx_application_identifier!=='com.dalcu.mlx-core'||native.mlx_team_identifier!=='S77TW432YG'||native.orbstack_version!=='2.2.5'||native.all_client_coverage!=='unsupported'||native.enrolled!==false||![native.mlx_server_sha256,native.mlx_application_sha256,native.orbstack_application_sha256,native.docker_cli_sha256,native.orbctl_cli_sha256].every(digest))fail();
  if(!Array.isArray(value.approved_sandbox_images)||value.approved_sandbox_images.length!==0)fail();
  exact(value.activation,['managed_inference','sandbox_tasks','native_lifecycle','launchd_installation']);
  if(Object.values(value.activation).some(flag=>flag!==false))fail();
  if(!template){
    if(!/^[a-f0-9]{40}$/.test(value.source_revision)||!digest(value.source_tree_sha256)||value.package_complete!==false||!Array.isArray(value.artifacts)||value.artifacts.length!==Object.keys(platformArtifactModes).length)fail();
    const seen=new Set();
    for(const artifact of value.artifacts){
      exact(artifact,['path','sha256','bytes','mode']);
      if(!Object.hasOwn(platformArtifactModes,artifact.path)||seen.has(artifact.path)||artifact.mode!==platformArtifactModes[artifact.path]||!digest(artifact.sha256)||!Number.isSafeInteger(artifact.bytes)||artifact.bytes<1||artifact.bytes>64*1024*1024)fail();
      seen.add(artifact.path);
    }
  }
  return value;
}
export function decodePlatformManifest(bytes,options){
  if(!Buffer.isBuffer(bytes)||bytes.length<1||bytes.length>65536)fail();
  const value=JSON.parse(bytes.toString('utf8'));
  // The producer's canonical pretty encoding eliminates duplicate keys,
  // alternate escaping/number spellings and cross-parser ambiguities.
  if(!bytes.equals(Buffer.from(JSON.stringify(value,null,2)+'\n')))fail();
  return validatePlatformManifest(value,options);
}
export function validatePlatformRelease(directory,expectedManifestSHA256){
  if(!digest(expectedManifestSHA256)||!directory.startsWith('/'))fail();
  const root=resolve(directory),uid=process.getuid();
  function regular(path,maximum){
    const fd=openSync(path,constants.O_RDONLY|constants.O_NOFOLLOW);
    try{
      const info=fstatSync(fd);
      if(!info.isFile()||info.nlink!==1||![0,uid].includes(info.uid)||(info.mode&0o022)!==0||info.size>maximum)fail();
      const chunks=[],buffer=Buffer.alloc(32768);let total=0;
      while(true){
        const count=readSync(fd,buffer,0,Math.min(buffer.length,maximum-total+1),null);
        if(count===0)break;
        if(total+count>maximum)fail();
        chunks.push(Buffer.from(buffer.subarray(0,count)));total+=count;
      }
      return {bytes:Buffer.concat(chunks,total),mode:info.mode&0o777};
    }finally{closeSync(fd);}
  }
  const info=lstatSync(root);
  if(!info.isDirectory()||![0,uid].includes(info.uid)||(info.mode&0o022)!==0)fail();
  const receipt=regular(join(root,'release.json'),65536);
  if(createHash('sha256').update(receipt.bytes).digest('hex')!==expectedManifestSHA256)fail();
  const manifest=decodePlatformManifest(receipt.bytes),expected=new Set(['release.json',...Object.keys(platformArtifactModes)]);
  function walk(path,prefix=''){
    const handle=opendirSync(path);let count=0;
    try{
      while(true){
        const item=handle.readSync();if(!item)break;
        if(++count>16)fail();
        const name=item.name,relative=prefix+name,full=join(path,name),info=lstatSync(full);
        if(info.isDirectory()){
          if(![0,uid].includes(info.uid)||(info.mode&0o022)!==0||!['bin','sandbox','python','launchd'].includes(relative))fail();
          walk(full,relative+'/');
        }else if(!info.isFile()||!expected.has(relative))fail();
      }
    }finally{handle.closeSync();}
  }
  walk(root);
  for(const artifact of manifest.artifacts){
    const file=regular(join(root,artifact.path),64*1024*1024);
    if(file.mode!==artifact.mode||file.bytes.length!==artifact.bytes||createHash('sha256').update(file.bytes).digest('hex')!==artifact.sha256)fail();
    if(artifact.path.startsWith('bin/')&&(file.bytes.length<32||file.bytes.readUInt32LE(0)!==0xfeedfacf||file.bytes.readUInt32LE(4)!==0x0100000c))fail();
  }
  return {manifest,manifestSHA256:expectedManifestSHA256,activation:false};
}
