#!/usr/bin/env node
// Actual registry claimability frames decoded by current Core; no native authority.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,readdirSync,mkdtempSync,lstatSync,realpathSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,join,dirname,isAbsolute} from 'node:path';
import {spawnSync} from 'node:child_process';
const root=resolve(import.meta.dirname,'..'),args=process.argv.slice(2);
assert(args.length===5&&args[0]==='--isolated'&&args[1]==='--receipt'&&args[3]==='--sha256');
assert(process.platform==='darwin'&&process.arch==='arm64'&&process.getuid()>0);
const sha=data=>createHash('sha256').update(data).digest('hex');
const read=(path,size=256<<10)=>{
  const info=lstatSync(path);assert(info.isFile()&&!info.isSymbolicLink()&&info.nlink===1&&info.uid===process.getuid()&&info.size>0&&info.size<=size);
  return readFileSync(path);
};
const input=resolve(args[2]);assert(isAbsolute(args[2])&&input.startsWith('/private/tmp/fios-009-claimability-')&&realpathSync(input)===input);
const bytes=read(input);assert.equal(sha(bytes),args[4]);const native=JSON.parse(bytes);
assert.equal(native.scope,'exact_registry_claimability_overlay_actual_tracker_registry_shaped_metadata_no_native_authority');
assert.equal(native.results.length,6);assert(native.results.every(value=>value.expected&&value.status===0));
const frames=[];
for(const result of native.results){
  for(const [name,digest]of Object.entries(result.native_frames)){
    assert(/^(Debug|ReleaseSafe)-0-claimability-native-frame\.bin$/.test(name));
    const path=join(dirname(input),name),data=read(path,67168);assert.equal(data.length,67168);assert.equal(sha(data),digest);frames.push(path);
  }
}
assert.equal(frames.length,2);
const work=mkdtempSync('/private/tmp/fios-009-claimability-cross-');
const sourceDirectory=join(root,'platform/studio/Sources/StudioCore');
const sources=readdirSync(sourceDirectory).filter(name=>name.endsWith('.swift')).sort().map(name=>join(sourceDirectory,name));
const fixture=join(root,'platform/studio/Tests/StudioCoreTests/RegistryClaimabilityFrame.swift.fixture');
const fixtureCopy=join(work,'RegistryClaimabilityFrame.swift');writeFileSync(fixtureCopy,read(fixture),{mode:0o600});
const inputs=Object.fromEntries([...sources,fixture].map(path=>[path,sha(read(path))]));
const receipt={scope:'actual_registry_claimability_frames_current_core_decode_no_native_authority',native_receipt_sha256:args[4],inputs,models:0,installed:false,activation:false,results:[]};
const save=()=>writeFileSync(join(work,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});save();
for(const mode of ['Debug','Optimized']){
  const binary=join(work,mode),argv=['-parse-as-library','-swift-version','6','-warnings-as-errors',...(mode==='Optimized'?['-O']:[]),'-I',join(root,'platform/studio/Sources/CSQLite'),...sources,fixtureCopy,'-o',binary];
  const built=spawnSync('swiftc',argv,{cwd:root,encoding:'utf8',timeout:300000});
  writeFileSync(join(work,mode+'-compile.log'),(built.stdout??'')+(built.stderr??''),{mode:0o600});
  assert(!built.error&&!built.signal&&built.status===0,'Core frame decoder compile failed: '+work);
  const binarySHA=sha(read(binary,128<<20));
  for(const [index,frame]of frames.entries()){
    const result=spawnSync('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',binary,frame],{cwd:work,encoding:'utf8',timeout:10000});
    const output=(result.stdout??'')+(result.stderr??'');writeFileSync(join(work,mode+'-'+index+'.log'),output,{mode:0o600});
    const expected=!result.error&&!result.signal&&result.status===0&&output.includes('PASS actual native claimability frame');
    receipt.results.push({mode,index,status:result.status,expected,binary_sha256:binarySHA,log_sha256:sha(Buffer.from(output))});save();assert(expected,'Native frame decode failed: '+work);
    assert.equal(sha(read(binary,128<<20)),binarySHA);
  }
}
for(const [path,digest]of Object.entries(inputs))assert.equal(sha(read(path)),digest);
assert.equal(sha(read(input)),args[4]);for(const result of native.results)for(const [name,digest]of Object.entries(result.native_frames))assert.equal(sha(read(join(dirname(input),name),67168)),digest);
save();console.log(work);console.log('PASS current Core Debug/optimized with native Debug/ReleaseSafe claimability frames; no native authority');
