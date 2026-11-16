#!/usr/bin/env node
// Development package checks only; no installation, enrollment or inference.
import assert from 'node:assert/strict';
import {spawn,spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,lstatSync,realpathSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {join} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {validatePlatformRelease} from './lib/platform-release.mjs';
import {platformConfigurationPlan,stagePlatformConfiguration,verifyPlatformConfiguration} from './lib/platform-state-plan.mjs';
import {platformPackagingInputs,capturePlatformSources,verifyPlatformSources} from './lib/platform-source.mjs';

const args=process.argv.slice(2);
assert((args.length===5||(args.length===7&&args[5]==='--source'))&&args[0]==='--isolated'&&args[1]==='--release'&&args[3]==='--sha256',
  'Use --isolated --release ABS_PRIVATE_DEVELOPMENT_RELEASE --sha256 REVIEWED_MANIFEST_SHA256 [--source ABS_CLEAN_CHECKOUT]');
assert(process.platform==='darwin'&&process.arch==='arm64'&&process.getuid()>0);
const release=args[2],digest=args[4];
assert(release.startsWith('/private/tmp/')&&realpathSync(release)===release);
const info=lstatSync(release);assert(info.isDirectory()&&info.uid===process.getuid()&&(info.mode&0o7777)===0o700);
const verified=validatePlatformRelease(release,digest);
const source=args.length===7 ? args[6]:null;
let sourceProof;
function checkSource() {
  if(source===null)return;
  assert(source.startsWith('/private/tmp/')&&realpathSync(source)===source);
  const info=lstatSync(source);assert(info.isDirectory()&&info.uid===process.getuid()&&(info.mode&0o022)===0);
  const git=argv=>{
    const result=spawnSync('/usr/bin/git',['--no-replace-objects','-c','core.fsmonitor=false','-C',source,...argv],
      {encoding:'utf8',timeout:10000,maxBuffer:1<<20,env:{PATH:'/usr/bin:/bin',HOME:source,LANG:'C',LC_ALL:'C',
        GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'}});
    assert(!result.error&&result.status===0,'Source revision/cleanliness check failed');return result.stdout;
  };
  assert.equal(git(['rev-parse','HEAD']).trim(),verified.manifest.source_revision);
  assert.equal(git(['status','--porcelain','--untracked-files=all']),'','Source checkout must be clean');
  const inputs=platformPackagingInputs(source);
  if(sourceProof)verifyPlatformSources(sourceProof,source,inputs);
  else sourceProof=capturePlatformSources(source,inputs);
  assert.equal(sourceProof.digest,verified.manifest.source_tree_sha256,'Declared source projection differs from packaged manifest');
}
checkSource(); // Refuse mismatches before executing any packaged binary.
const directory=mkdtempSync('/private/tmp/fios-009-release-check-');
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
const receipt={version:1,scope:'private_development_package_not_installed_acceptance',manifest_sha256:digest,
  source_revision:verified.manifest.source_revision,runner_sha256:hash(readFileSync(new URL(import.meta.url))),
  host_reviews:[],packaged_public_startup:false,installed:false,activation:false,native_authority:false,
  whole_repository_provenance:false,native_provenance:false,models:0,inference:false};
const save=()=>writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});
if(sourceProof)receipt.declared_source={revision:verified.manifest.source_revision,files:sourceProof.records.length,
  sha256:sourceProof.digest,clean_checkout:true,scope:'declared_inputs_not_whole_repository_or_native_provenance',rechecked:false};
save();
for(const host of verified.manifest.native_inventory.hosts){
  const state=join(directory,host+'-state'),bundle=join(directory,host+'-configuration');mkdirSync(state,{mode:0o700});
  const options={release,verified,host,state};
  const plan=platformConfigurationPlan(options);
  assert.equal(plan.activation,false);assert.deepEqual(plan.privileged_commands,[]);
  stagePlatformConfiguration({...options,destination:bundle});
  const reviewSHA256=hash(readFileSync(join(bundle,'review.json')));
  verifyPlatformConfiguration({release,verified,host,bundle,reviewSHA256});
  for(const name of ['lab.fios.studio.supervisor.plist','lab.fios.studio.session.plist']){
    const lint=spawnSync('/usr/bin/plutil',['-lint',join(bundle,name)],{encoding:'utf8',timeout:5000});
    assert.equal(lint.status,0,'Packaged plist lint failed; retain '+directory);
  }
  receipt.host_reviews.push({host,configuration_review_sha256:reviewSHA256,plists:2,privileged_commands:0});save();
}
const state=join(directory,'public-startup-state');mkdirSync(state,{mode:0o700});
const env={PATH:'/usr/bin:/bin',HOME:state,LANG:'C',LC_ALL:'C'};
const child=spawn(join(release,'bin/studio-manager'),['--state',state],{env,stdio:['ignore','ignore','pipe']});
let diagnosticBytes=0,childError;
child.on('error',error=>{childError=error;});
child.stderr.on('data',part=>{diagnosticBytes+=part.length;});
const exited=()=>child.exitCode!==null||child.signalCode!==null||childError!==undefined;
async function until(predicate,milliseconds){
  const deadline=performance.now()+milliseconds;
  while(performance.now()<deadline){if(predicate())return;await delay(25);}
  throw Error('Packaged startup deadline; retain '+directory);
}
try{
  let status;
  await until(()=>{
    assert(!exited()&&diagnosticBytes===0,'Packaged manager failed; retain '+directory);
    const result=spawnSync(join(release,'bin/studioctl'),['--state',state,'status'],{env,encoding:'utf8',timeout:3000,maxBuffer:65536});
    if(result.status!==0)return false;
    status=JSON.parse(result.stdout);return status.native_observation_source==='unconfigured';
  },15000);
  assert.equal(status.native_ingress_admissions,'unconfigured');assert.equal(status.native_admissions,'unsupported');
  assert.equal(status.native_activity,'unsupported');assert.equal(status.native_control.state,'unconfigured');
  assert.equal(status.sandbox_admission,'disabled');assert(!Object.hasOwn(status,'native_control_mode'));
  writeFileSync(join(directory,'public-startup-status.json'),JSON.stringify(status,null,2)+'\n',{mode:0o600});
  child.kill('SIGTERM');await until(exited,5000);assert.equal(child.exitCode,0);assert.equal(diagnosticBytes,0);
  receipt.packaged_public_startup=true;
  validatePlatformRelease(release,digest);receipt.release_rechecked=true;
  checkSource();if(receipt.declared_source)receipt.declared_source.rechecked=true;
  save();
}finally{
  if(!exited()){
    child.kill('SIGTERM');
    try{await until(exited,5000);}catch{child.kill('SIGKILL');await until(exited,3000);}
  }
}
console.log(JSON.stringify({directory,receipt_sha256:hash(readFileSync(join(directory,'receipt.json'))),...receipt}));
