#!/usr/bin/env node
// Source-only GUI coexistence component. No GUI/native service is launched.
import assert from 'node:assert/strict';
import {execFileSync,spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync,mkdtempSync,lstatSync,realpathSync,existsSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,join,dirname,isAbsolute} from 'node:path';
const root=resolve(import.meta.dirname,'..'),args=process.argv.slice(2);
assert(process.platform==='darwin'&&process.arch==='arm64'&&process.getuid()>0);
assert(args.length===3&&args[0]==='--isolated'&&args[1]==='--source');
const source=args[2];assert(isAbsolute(source)&&source.startsWith('/private/tmp/')&&realpathSync(source)===source);
const hash=data=>createHash('sha256').update(data).digest('hex');
const bytes=path=>{const st=lstatSync(path);assert(st.isFile()&&!st.isSymbolicLink()&&st.nlink===1&&st.uid===process.getuid()&&(st.mode&0o022)===0&&st.size>0&&st.size<4<<20);return readFileSync(path);};
const env={PATH:'/usr/bin:/bin:/usr/sbin:/sbin',DEVELOPER_DIR:'/Applications/Xcode.app/Contents/Developer',LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1'};
const run=(file,argv,cwd)=>execFileSync(file,argv,{cwd,env,encoding:'utf8',timeout:15000,maxBuffer:4<<20});
assert.equal(run('/usr/bin/git',['-C',source,'rev-parse','HEAD']).trim(),'3736ed55f81c6cf0966a0f0dc7265e783655d244');
const swift=run('/usr/bin/xcrun',['--find','swiftc']).trim();const sdk=run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-path']).trim();env.SDKROOT=sdk;assert.match(run(swift,['--version']),/Swift version 6\.4\.2/);
const manager='app/Sources/MLXServe/Services/ServerManager.swift',helper='app/Sources/MLXServe/Services/FiosServerLaunchPreflight.swift';
const parents={[manager]:'b7eb6a9b954361a6f7f3c691c6f66cd76176773d58d3a35fea4f94f4be3dc77b',[helper]:null};
const directory=mkdtempSync('/private/tmp/fios-009-gui-launch-check-'),review=join(directory,'projection');mkdirSync(review,{mode:0o700});
const patchPath=join(root,'platform/studio/native/mlx-serve-gui-launch-preflight.patch'),patch=bytes(patchPath);
assert.deepEqual([...patch.toString().matchAll(/^\+\+\+ b\/([^\r\n]+)$/gm)].map(x=>x[1]).sort(),Object.keys(parents).sort());
const inputs={};for(const name of Object.keys(parents)){const data=bytes(join(source,name));inputs[name]=hash(data);const target=join(review,name);mkdirSync(dirname(target),{recursive:true,mode:0o700});writeFileSync(target,data,{mode:0o600});}
const copiedPatch=join(directory,'source.patch');writeFileSync(copiedPatch,patch,{mode:0o600});run('/usr/bin/git',['apply','--reverse',copiedPatch],review);
for(const [name,digest] of Object.entries(parents)){if(digest===null)assert(!existsSync(join(review,name)));else assert.equal(hash(bytes(join(review,name))),digest);}
run('/usr/bin/git',['apply',copiedPatch],review);for(const [name,digest] of Object.entries(inputs))assert.equal(hash(bytes(join(review,name))),digest);
const fixturePath=join(root,'platform/studio/native/gui_launch_preflight_test.swift.fixture'),fixture=bytes(fixturePath),main=join(directory,'PreflightMain.swift');writeFileSync(main,fixture,{mode:0o600});
const receipt={scope:'exact_two_file_vendor_gui_overlay_actual_preflight_component_only',directory,source,parents,inputs,patch_sha256:hash(patch),fixture_sha256:hash(fixture),runner_sha256:hash(bytes(import.meta.filename)),swift,sdk,results:[],gui_launched:false,installed:false,models:0,native_authority:false,whole_native_provenance:false};
const save=()=>writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});save();
for(const [mode,flag] of [['debug','-Onone'],['optimized','-O']]){
 const binary=join(directory,'preflight-'+mode);
 for(const [phase,file,argv] of [['compile',swift,['-swift-version','6','-warnings-as-errors',flag,join(source,helper),main,'-o',binary]],['run','/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network-outbound)',binary,join(directory,mode+'-state')]]]){
  const result=spawnSync(file,argv,{env,cwd:directory,encoding:'utf8',timeout:phase==='compile'?120000:10000,maxBuffer:1<<20});
  const log=(result.stdout??'')+(result.stderr??'');writeFileSync(join(directory,mode+'-'+phase+'.log'),log,{mode:0o600});
  const item={mode,phase,status:result.status,signal:result.signal,log_sha256:hash(Buffer.from(log)),expected:!result.error&&!result.signal&&result.status===0&&(phase!=='run'||log.includes('PASS: actual GUI preflight preserves IPv4/IPv6 listeners'))};
  receipt.results.push(item);save();assert(item.expected,'GUI component check failed; preserve '+directory);
 }
}
receipt.unchanged=Object.entries(inputs).every(([n,h])=>hash(bytes(join(source,n)))===h)&&hash(bytes(patchPath))===receipt.patch_sha256&&hash(bytes(fixturePath))===receipt.fixture_sha256&&hash(bytes(import.meta.filename))===receipt.runner_sha256;save();assert(receipt.unchanged);
console.log(JSON.stringify({directory,receipt_sha256:hash(bytes(join(directory,'receipt.json'))),modes:2,models:0,gui_launched:false,native_authority:false}));
