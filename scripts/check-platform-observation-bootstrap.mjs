#!/usr/bin/env node
// Exact overlay/module metadata only; no installed-root or native authority.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,mkdtempSync,mkdirSync,lstatSync,realpathSync,existsSync} from 'node:fs';
import {execFileSync,spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {join,dirname,isAbsolute,resolve} from 'node:path';
const args=process.argv.slice(2),root=resolve(import.meta.dirname,'..');
assert.equal(process.platform,'darwin');assert.equal(process.arch,'arm64');assert(process.getuid()>0);
assert(args.length===5&&args[0]==='--isolated'&&args[1]==='--source'&&args[3]==='--zig');
const [source,zig]=[args[2],args[4]].map(path=>{assert(isAbsolute(path)&&path.startsWith('/private/tmp/')&&realpathSync.native(path)===path);return path;});
const hash=bytes=>createHash('sha256').update(bytes).digest('hex');
function bytes(path,maximum=1<<20){const s=lstatSync(path);assert(s.isFile()&&!s.isSymbolicLink()&&s.uid===process.getuid()&&s.nlink===1&&(s.mode&0o022)===0&&s.size>0&&s.size<maximum);return readFileSync(path);}
assert.equal(hash(bytes(zig,512<<20)),'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
const parents={
 'src/fios/control_transport.zig':'d3d9312a1bfda82c845776a9207d6dfb4bcd44676f76aa46d4e60c62248dca2a',
 'src/fios/startup_guard.zig':'4e21a99052a22534e991b7b50fb47765f06182a7cab4dcbf622c898a53e2e0ce',
 'src/fios/observation_access.zig':null,'src/fios/observation_policy.zig':null};
const directory=mkdtempSync('/private/tmp/fios-009-observation-bootstrap-check-'),review=join(directory,'projection');mkdirSync(review,{mode:0o700});
const patchPath=join(root,'platform/studio/native/mlx-serve-reviewed-observation-bootstrap.patch'),patch=bytes(patchPath);
assert.deepEqual([...patch.toString().matchAll(/^\+\+\+ b\/([^\n]+)$/gm)].map(m=>m[1]).sort(),Object.keys(parents).sort());
const inputs={};for(const name of Object.keys(parents)){const data=bytes(join(source,name));inputs[name]=hash(data);mkdirSync(dirname(join(review,name)),{recursive:true,mode:0o700});writeFileSync(join(review,name),data,{mode:0o600});}
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_SYSTEM:'/dev/null',GIT_CONFIG_NOSYSTEM:'1'};
const copy=join(directory,'source.patch');writeFileSync(copy,patch,{mode:0o600});
for(const reverse of [true,false]){
 execFileSync('/usr/bin/git',['apply',...(reverse?['--reverse']:[]),copy],{cwd:review,env,timeout:15000});
 for(const [name,digest] of Object.entries(reverse?parents:inputs))if(digest===null)assert(!existsSync(join(review,name)));else assert.equal(hash(bytes(join(review,name))),digest);
}
const receipt={version:1,scope:'selected_four_path_overlay_and_metadata_modules_not_installed_acceptance',source,parent_projection:parents,inputs,patch_sha256:hash(patch),runner_sha256:hash(bytes(import.meta.filename)),models:0,installed:false,activation:false,native_authority:false,whole_native_provenance:false,results:[]};
function save(){writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});}save();
for(const mode of ['Debug','ReleaseSafe'])for(const [name,count] of [['observation_access.zig',1],['observation_policy.zig',2]]){
 const result=spawnSync('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',zig,'test','-lc','-O'+mode,join(source,'src/fios',name)],{cwd:directory,env,encoding:'utf8',timeout:120000,maxBuffer:1<<20});
 const log=(result.stdout??'')+(result.stderr??'');writeFileSync(join(directory,name+'-'+mode+'.log'),log,{mode:0o600});
 const item={name,mode,status:result.status,signal:result.signal,log_sha256:hash(Buffer.from(log)),expected:!result.error&&!result.signal&&result.status===0&&log.includes(`All ${count} tests passed.`)};
 receipt.results.push(item);save();assert(item.expected,'Metadata module failed; retain '+directory);
}
receipt.unchanged=Object.entries(inputs).every(([name,digest])=>hash(bytes(join(source,name)))===digest)&&hash(bytes(patchPath))===receipt.patch_sha256&&hash(bytes(import.meta.filename))===receipt.runner_sha256;save();assert(receipt.unchanged);
console.log(JSON.stringify({directory,receipt_sha256:hash(bytes(join(directory,'receipt.json'))),named_cases_per_mode:3,models:0,native_authority:false}));
