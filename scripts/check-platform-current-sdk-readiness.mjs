#!/usr/bin/env node
// Exact-parent source projection only. No native service, SDK library or model.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {lstatSync,mkdirSync,mkdtempSync,readFileSync,realpathSync,writeFileSync} from 'node:fs';
import {dirname,isAbsolute,join,relative,resolve} from 'node:path';

const args=process.argv.slice(2);
assert(args.length===5&&args[0]==='--isolated'&&args[1]==='--source'&&args[3]==='--zig');
assert(process.platform==='darwin'&&process.arch==='arm64'&&process.getuid()>0);
const [source,zig]=[args[2],args[4]];
for(const p of [source,zig])assert(p.startsWith('/private/tmp/')&&realpathSync(p)===p);
const hash=b=>createHash('sha256').update(b).digest('hex');
function bytes(p,limit=8<<20){
  const s=lstatSync(p);
  assert(s.isFile()&&s.nlink===1&&s.uid===process.getuid()&&(s.mode&0o022)===0&&s.size>0&&s.size<=limit&&realpathSync(p)===p);
  return readFileSync(p);
}
const compiler=hash(bytes(zig,512<<20));
assert.equal(compiler,'1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523');
const runner=hash(bytes(import.meta.filename));
const repository=resolve(import.meta.dirname,'..'),native=join(repository,'platform/studio/native');
const directory=mkdtempSync('/private/tmp/fios-009-current-sdk-readiness-'),projection=join(directory,'src');
const primary='fios/sdk_request_ownership.zig',tracker='fios/request_ownership.zig';
const pins={
  [primary]:'fa2260c4b6fb8a01a7de74d74737fb844038f84ea841cad50a9aa2ed0e60111b',
  [tracker]:'81e4ce4f19493867d23b88a2114f59f0204815b78aa6ef8d2b607c5bff524562',
};
const inputs={},pending=[primary,tracker],root=join(source,'src');
while(pending.length){
  const name=pending.pop();if(Object.hasOwn(inputs,name))continue;
  assert(Object.keys(inputs).length<512);
  const data=bytes(join(root,name));inputs[name]=hash(data);
  if(Object.hasOwn(pins,name))assert.equal(inputs[name],pins[name],`Unexpected readiness parent: ${name}`);
  const target=join(projection,name);mkdirSync(dirname(target),{mode:0o700,recursive:true});writeFileSync(target,data,{mode:0o600});
  for(const match of String(data).matchAll(/@import\("([^"\n]+\.zig)"\)/g)){
    const dependency=relative(root,resolve(dirname(join(root,name)),match[1]));
    assert(!dependency.startsWith('..')&&!isAbsolute(dependency));pending.push(dependency);
  }
}
const patch=bytes(join(native,'mlx-serve-current-sdk-readiness-latch.patch'));
assert.deepEqual([...String(patch).matchAll(/^\+\+\+ b\/(\S+)$/gm)].map(m=>m[1]),['src/'+primary]);
const patchPath=join(directory,'projection.patch');writeFileSync(patchPath,patch,{mode:0o600});
const env={PATH:'/usr/bin:/bin',HOME:directory,LANG:'C',LC_ALL:'C',GIT_CONFIG_GLOBAL:'/dev/null',GIT_CONFIG_NOSYSTEM:'1',GIT_NO_REPLACE_OBJECTS:'1'};
const run=(file,argv)=>execFileSync(file,argv,{cwd:directory,env,encoding:'utf8',timeout:90000,stdio:['ignore','pipe','pipe']});
run('/usr/bin/git',['apply','--check',patchPath]);run('/usr/bin/git',['apply',patchPath]);
const candidate=hash(bytes(join(projection,primary)));
assert.equal(candidate,'9c31abd758777a619ad974fa605fcc581f907f7ad826029286a9bb59d2fd7cfe');
const fixture=bytes(join(native,'current_sdk_readiness_test.zig.fixture'));
const main=join(projection,'readiness.zig'),options=join(directory,'options.zig');
const buildOptions='pub const fios_source_ane = false;\n';
writeFileSync(main,fixture,{mode:0o600});writeFileSync(options,buildOptions,{mode:0o600});
const modes=['Debug','ReleaseSafe'],filters=['projected current bridge','projected ready bridge','readiness does not overwrite'];
for(const mode of modes){
  try{
    // Imported upstream tests independently initialize process-lifetime state.
    // Keep this focused scenario and the atomic ordering unit in separate runs.
    for(const filter of filters){
      run('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',zig,'test','--test-filter',filter,'-O',mode,'-lc','--dep','build_options','-Mroot='+main,'-Mbuild_options='+options]);
    }
  }catch(error){console.error(`Retained failed ${mode} source projection: ${directory}`);throw error;}
}
for(const [name,digest] of Object.entries(inputs)){
  assert.equal(hash(bytes(join(root,name))),digest);
  if(name!==primary)assert.equal(hash(bytes(join(projection,name))),digest);
}
assert.equal(hash(bytes(join(native,'mlx-serve-current-sdk-readiness-latch.patch'))),hash(patch));
assert.equal(hash(bytes(join(native,'current_sdk_readiness_test.zig.fixture'))),hash(fixture));
assert.equal(hash(bytes(zig,512<<20)),compiler);
assert.equal(hash(bytes(import.meta.filename)),runner);
assert.equal(hash(bytes(join(projection,primary))),candidate);
assert.equal(hash(bytes(main)),hash(fixture));
assert.equal(hash(bytes(options)),hash(buildOptions));
const receipt={scope:'declared_cpu_readiness_projection_only',directory,inputs,compiler_sha256:compiler,runner_sha256:runner,options_sha256:hash(buildOptions),patch_sha256:hash(patch),fixture_sha256:hash(fixture),candidate,modes,filters,activation:false,native_authority:false};
writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});
console.log(JSON.stringify({ok:true,directory,candidate,declared_inputs:Object.keys(inputs).length,activation:false,native_authority:false}));
