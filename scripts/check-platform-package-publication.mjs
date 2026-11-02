#!/usr/bin/env node
// Real development package build + private filesystem fault. No installation,
// controller/state/runtime/native lifecycle, model request or service action.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,writeFileSync,readFileSync,existsSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {userInfo} from 'node:os';
import {createHash,randomUUID} from 'node:crypto';
assert(process.platform==='darwin'&&process.getuid()>0&&process.argv.length===3&&process.argv[2]==='--isolated');
const root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/private/tmp/fios-package-publication-');
const parent=join(directory,'requested-parent'),sentinelParent=join(directory,'unrelated-parent'),output=join(parent,'release'),sentinel=join(sentinelParent,'release');
for(const path of [parent,sentinelParent,sentinel])mkdirSync(path,{mode:0o700});
const marker=join(sentinel,'do-not-remove'),content=randomUUID();writeFileSync(marker,content,{mode:0o600});
const digest=b=>createHash('sha256').update(b).digest('hex'),expected=digest(Buffer.from(content));
const hook=join(directory,'PublicationFault.mjs');
writeFileSync(hook,`import fs from 'node:fs';import cp from 'node:child_process';import {syncBuiltinESMExports} from 'node:module';
const output=${JSON.stringify(output)},parent=${JSON.stringify(parent)},sentinel=${JSON.stringify(sentinelParent)},directory=${JSON.stringify(directory)};
let changed=false;const copy=fs.copyFileSync,spawn=cp.spawnSync;
function race(){if(changed)return;changed=true;fs.renameSync(parent,parent+'.held');fs.symlinkSync(sentinel,parent,'dir');fs.writeFileSync(directory+'/fault-triggered','publication-parent-rebound',{mode:0o600});}
fs.copyFileSync=function(from,to,...rest){if(String(to).startsWith(output+'/')){race();throw Error('FIO_PRIVATE_ARTIFACT_COPY_REFUSAL');}return copy(from,to,...rest);};
cp.spawnSync=function(file,args,options){if(Array.isArray(args)&&args[0]==='stage-release'&&args.includes(output))race();return spawn(file,args,options);};
syncBuiltinESMExports();
`,{mode:0o600});
const env={PATH:'/usr/bin:/bin',HOME:userInfo().homedir,LANG:'C',LC_ALL:'C'};
const result=spawnSync(process.execPath,['--import',hook,join(root,'scripts/package-platform.mjs'),'--output',output],{cwd:root,env,encoding:'utf8',timeout:600000,maxBuffer:1<<20});
writeFileSync(join(directory,'stdout.log'),result.stdout??'',{mode:0o600});writeFileSync(join(directory,'stderr.log'),result.stderr??'',{mode:0o600});
writeFileSync(join(directory,'fixture-state.json'),JSON.stringify({version:1,parent,output,sentinel,expected_marker_sha256:expected,child_status:result.status,signal:result.signal,activation:false},null,2)+'\n',{mode:0o600});
console.log('Package-publication failure fixture:',directory);
assert(!result.error&&!result.signal,'Build/deadline failure is not publication evidence');assert.notEqual(result.status,0);
assert(existsSync(join(directory,'fault-triggered')),'Genuine package did not reach publication; preflight/build failure is not a behavior red');
if(!existsSync(marker)||digest(readFileSync(marker))!==expected)throw Error('FIO_PACKAGE_FAILURE_DELETED_UNRELATED_DESTINATION');
console.log(JSON.stringify({publication_refused:true,unrelated_marker_preserved:true,real_development_build:true,package_manifest_sdk:'27.0',native_inference:false,installed:false,activation:false}));
