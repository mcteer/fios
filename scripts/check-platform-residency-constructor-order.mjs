#!/usr/bin/env node
// Fixed source control-flow check; all Metal/configuration ports are synthetic.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync,mkdirSync,lstatSync,realpathSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const args=process.argv.slice(2),root=resolve(import.meta.dirname,'..');
assert(args.length===2&&args[0]==='--isolated');
assert(process.platform==='darwin'&&process.arch==='arm64'&&process.getuid()>0);
const source=args[1];assert(source.startsWith('/private/tmp/')&&realpathSync(source)===source);
const patch=join(root,'platform/studio/native/mlx-residency-constructor-refusal-order.patch');
const parent=join(root,'platform/studio/native/residency_constructor_order_parents.json');
const fixture=join(root,'platform/studio/native/mlx_residency_constructor_order.cpp.fixture');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const files=[source,patch,parent,fixture,import.meta.filename];
const capture=()=>Object.fromEntries(files.map(file=>{
 const info=lstatSync(file);assert(info.isFile()&&!info.isSymbolicLink()&&info.nlink===1&&info.size>0&&info.size<=65536);
 return [file,sha(readFileSync(file))];
}));
const before=capture(),parents=JSON.parse(readFileSync(parent));
assert.deepEqual(Object.keys(parents),['mlx/backend/metal/resident.cpp']);
assert.equal(before[source],parents['mlx/backend/metal/resident.cpp']);
const directory=mkdtempSync('/private/tmp/fios-009-residency-order-');
const target=join(directory,'mlx/backend/metal/resident.cpp');mkdirSync(resolve(target,'..'),{recursive:true,mode:0o700});
writeFileSync(target,readFileSync(source),{mode:0o600});
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1'};
function run(name,program,argv,timeout=15000){
 const result=spawnSync(program,argv,{cwd:directory,env,encoding:'utf8',timeout,maxBuffer:65536});
 writeFileSync(join(directory,name+'.log'),(result.stdout??'')+(result.stderr??''),{mode:0o600});return result;
}
const applied=run('apply','/usr/bin/git',['apply',patch]);assert(!applied.error&&applied.status===0);
function constructor(text){
 const start=text.indexOf('ResidencySets::ResidencySets(MTL::Device* d) {');assert(start>=0);
 const end=text.indexOf('\nResidencySets::~ResidencySets()',start);assert(end>start);
 const body=text.slice(start,end).trim();assert(body.endsWith('}'));return body;
}
const template=readFileSync(fixture,'utf8');assert.equal(template.split('// FIOS_ACTUAL_CONSTRUCTOR').length,2);
const records=[];
for(const [name,text]of [['parent',readFileSync(source,'utf8')],['candidate',readFileSync(target,'utf8')]]){
 const cpp=join(directory,name+'.cpp');writeFileSync(cpp,template.replace('// FIOS_ACTUAL_CONSTRUCTOR',constructor(text)),{mode:0o600});
 for(const [mode,flags]of [['debug',['-O0']],['optimized',['-O2']]]){
  const binary=join(directory,name+'-'+mode);
  const built=run(name+'-'+mode+'-compile','/usr/bin/clang++',['-std=c++20','-Wall','-Wextra','-Werror',...flags,cpp,'-o',binary]);
  assert(!built.error&&built.status===0,'Compile failed; retain '+directory);
  for(const scenario of ['sealed','ordinary','disabled']){
   const result=run(name+'-'+mode+'-'+scenario,binary,[scenario],5000);
   const expected=name==='parent'&&scenario==='sealed'?3:0;
   assert(!result.error&&result.status===expected,'Unexpected constructor result; retain '+directory);
   records.push({name,mode,scenario,status:result.status,expected});
  }
 }
}
assert.deepEqual(capture(),before);
const receipt={scope:'actual_constructor_control_flow_synthetic_ports_only',inputs:before,candidate_source_sha256:sha(readFileSync(target)),records,inputs_unchanged:true,models:0,model_requests:0,native_authority:false,installed:false};
const bytes=Buffer.from(JSON.stringify(receipt,null,2)+'\n');writeFileSync(join(directory,'receipt.json'),bytes,{mode:0o600});
console.log(JSON.stringify({directory,receipt_sha256:sha(bytes),checks:records.length,models:0,native_authority:false}));
