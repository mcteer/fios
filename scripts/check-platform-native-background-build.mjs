#!/usr/bin/env node
// Explicit private Core-only startup exclusion check. No model or installation.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdtempSync,mkdirSync,realpathSync,lstatSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {createHash} from 'node:crypto';
import {verifyNativeReview} from './lib/platform-native-review.mjs';
const args=process.argv.slice(2),root=resolve(import.meta.dirname,'..');
assert(args.length===7&&args[0]==='--isolated'&&args[1]==='--source'&&args[3]==='--capsule'&&args[5]==='--sha256');
assert(process.platform==='darwin'&&process.arch==='arm64'&&process.getuid()>0);
const source=args[2];assert(source.startsWith('/private/tmp/')&&realpathSync(source)===source);
const capsule=verifyNativeReview(args[4],args[6]),declared=capsule.receipt.declared_inputs;
assert.equal(declared.model_effects,'forbidden');assert.equal(declared.serving_primary_guard,false);
assert.equal(declared.native_sdk_background_seal_build_version,1);
const directory=mkdtempSync('/private/tmp/fios-009-background-build-check-');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const files=[import.meta.filename,join(root,'tests/fixtures/platform/current-native-ingress.py')];
for(const [name,field]of [['semantic','native_semantic_receipt_sha256'],['link','native_link_receipt_sha256'],['units-check','native_units_receipt_sha256']]){
 const file=join(source,'..',name+'-receipt.json'),info=lstatSync(file);
 assert(info.isFile()&&!info.isSymbolicLink()&&info.nlink===1&&info.size>0&&info.size<=65536);
 const bytes=readFileSync(file);assert.equal(sha(bytes),declared[field]);const build=JSON.parse(bytes);
 assert.equal(build.status,0);assert.equal(build.model_requests,0);assert.equal(build.native_authority,false);
 assert(build.arguments.includes('-Dfios-source-background-seal=true'));
 assert(build.arguments.includes('-Dfios-source-sdk=true'));
 assert(build.arguments.includes('-j2'));files.push(file);
}

const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1'};
for(const [patchName,parentName,key]of [
 ['mlx-serve-sdk-background-seal.patch','sdk_background_seal_parents.json','native_source'],
 ['mlx-serve-sdk-background-seal-build.patch','sdk_background_seal_build_parents.json',null]]){
 const patch=join(root,'platform/studio/native',patchName),parent=join(root,'platform/studio/native',parentName);
 files.push(patch,parent);const document=JSON.parse(readFileSync(parent)),parents=key?document[key]:document;
 const expected=key?['src/fios/current_sdk_owners.cpp']:['build/macos.zig'];assert.deepEqual(Object.keys(parents),expected);
 const review=join(directory,key?'constructor':'build');mkdirSync(review,{mode:0o700});
 for(const name of expected){
  const original=join(source,name),info=lstatSync(original);assert(info.isFile()&&!info.isSymbolicLink()&&info.nlink===1&&info.size>0&&info.size<=65536);
  files.push(original);const target=join(review,name);mkdirSync(resolve(target,'..'),{recursive:true,mode:0o700});writeFileSync(target,readFileSync(original));
 }
 for(const reverse of [true,false]){
  const result=spawnSync('/usr/bin/git',['apply',...(reverse?['--reverse']:[]),patch],{cwd:review,env,encoding:'utf8',timeout:5000,maxBuffer:65536});
  assert(!result.error&&result.status===0);
  for(const name of expected)assert.equal(sha(readFileSync(join(review,name))),reverse?parents[name]:sha(readFileSync(join(source,name))));
 }
 const field=key?'native_bridge_patch_sha256':'native_background_build_patch_sha256';assert.equal(declared[field],sha(readFileSync(patch)));
}
const capture=()=>Object.fromEntries(files.map(file=>[file,sha(readFileSync(file))]));
const inputs=capture(),python=join(root,'.venv/bin/python');
const result=spawnSync(python,['-I','-B',join(root,'tests/fixtures/platform/current-native-ingress.py'),'--isolated',capsule.binary,capsule.receipt.files['bin/mlx-serve'].sha256,'--background-sealed'],{env,encoding:'utf8',timeout:90000,maxBuffer:1<<20});
writeFileSync(join(directory,'fixture.log'),(result.stdout??'')+(result.stderr??''),{mode:0o600});
assert(!result.error&&result.status===0,'Private background startup fixture failed; retain '+directory);
const receipt=JSON.parse(result.stdout.trim());assert.equal(receipt.models,0);assert.equal(receipt.model_requests,0);assert.equal(receipt.inference_started,false);
assert.equal(receipt.explicit_private_background_exclusion,true);assert.equal(receipt.source_background_untracked,false);
assert.equal(receipt.coverage,'unknown');assert.equal(receipt.all_client_coverage,false);assert.equal(receipt.native_admission_authority,false);
assert.deepEqual(capture(),inputs);verifyNativeReview(args[4],args[6]);
const review={scope:'actual_private_strict_source_startup_exclusion_not_all_client_or_model_acceptance',capsule_sha256:args[6],inputs,fixture:receipt,inputs_unchanged:true,models:0,installed:false,activation:false,native_authority:false};
const bytes=Buffer.from(JSON.stringify(review,null,2)+'\n');writeFileSync(join(directory,'receipt.json'),bytes,{mode:0o600});
console.log(JSON.stringify({directory,receipt_sha256:sha(bytes),models:0,native_authority:false}));
