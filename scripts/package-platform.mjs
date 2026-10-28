#!/usr/bin/env node
// Build/package only. No native apps, runtime, SSH, launchd or installation.
import {spawnSync} from 'node:child_process';
import {mkdtempSync,mkdirSync,readFileSync,writeFileSync,readdirSync,lstatSync,copyFileSync,chmodSync,rmSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {homedir} from 'node:os';
import {createHash} from 'node:crypto';
import {validatePlatformRelease} from './lib/platform-release.mjs';
import {capturePlatformSources,verifyPlatformSources} from './lib/platform-source.mjs';
const root=resolve(import.meta.dirname,'..'),args=process.argv.slice(2);
if(args.length!==2||args[0]!=='--output'||!args[1].startsWith('/'))throw Error('Usage: node scripts/package-platform.mjs --output NEW_ABSOLUTE_DIRECTORY');
const output=resolve(args[1]),scratch=mkdtempSync('/tmp/fios-package-');
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const template=JSON.parse(readFileSync(join(root,'platform/studio/deployment/release.json')));
function run(command,args,timeout=180000){
  const result=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout,maxBuffer:1<<20,env:{PATH:'/usr/bin:/bin',HOME:homedir(),LANG:'C',LC_ALL:'C'}});
  if(result.status!==0)throw Error('Release build/identity check failed');
  return result.stdout.trim();
}
function files(directory){
  return readdirSync(directory).sort().flatMap(name=>{
    const path=join(directory,name),stat=lstatSync(path);
    if(stat.isSymbolicLink()||(!stat.isFile()&&!stat.isDirectory()))throw Error('Nonregular release source');
    return stat.isDirectory()?files(path):[path];
  });
}
let created=false;
try{
  if(run('/usr/bin/uname',['-m'])!==template.architecture||!run('/usr/bin/swift',['--version']).includes(`Apple Swift version ${template.toolchain.swift} `)||run('/usr/bin/xcrun',['--show-sdk-version'])!==template.toolchain.sdk)throw Error('Pinned arm64/Swift/SDK toolchain required');
  if(!run('/usr/bin/swift',['--version']).includes(template.toolchain.swift_build)||run('/usr/bin/swift',['-I','platform/studio/Sources/CSQLite','-e','import CSQLite; print(String(cString: sqlite3_libversion()))'])!==template.sqlite.version)throw Error('Pinned Swift build/SQLite runtime required');
  if(sha(readFileSync(join(root,'uv.lock')))!==template.python.uv_lock_sha256)throw Error('Python lock identity changed');
  const collectSources=()=>[...files(join(root,'platform/studio/Sources')),join(root,'platform/studio/Package.swift'),join(root,'platform/studio/sandbox/runner.py'),join(root,'platform/studio/sandbox/Dockerfile'),join(root,'platform/studio/deployment/release.json'),join(root,'uv.lock'),join(root,'scripts/package-platform.mjs'),join(root,'scripts/install-platform.mjs'),join(root,'scripts/lib/platform-state-plan.mjs'),join(root,'scripts/lib/platform-release.mjs'),join(root,'scripts/lib/platform-source.mjs'),...files(join(root,'platform/studio/deployment')).filter(path=>path.endsWith('.plist'))].sort();
  const sourceProof=capturePlatformSources(root,collectSources()),sourceHash=sourceProof.digest;
  const build=['build','--package-path','platform/studio','-c','release','--arch','arm64','--scratch-path',scratch,
    '-Xswiftc','-gnone','-Xswiftc','-file-prefix-map','-Xswiftc',`${root}=/fios/source`,
    '-Xswiftc','-debug-prefix-map','-Xswiftc',`${scratch}=/fios/build`,
    '-Xcc',`-fdebug-prefix-map=${root}=/fios/source`,'-Xlinker','-no_uuid'];
  run('/usr/bin/swift',build);
  const bin=run('/usr/bin/swift',[...build,'--show-bin-path']);
  verifyPlatformSources(sourceProof,root,collectSources());
  mkdirSync(output,{mode:0o700});created=true;
  const artifacts=[];
  function add(source,path,mode){
    const bytes=readFileSync(source);
    mkdirSync(resolve(output,path,'..'),{recursive:true,mode:0o700});
    copyFileSync(source,join(output,path));chmodSync(join(output,path),mode);
    artifacts.push({path,sha256:sha(bytes),bytes:bytes.length,mode});
  }
  for(const name of ['studio-manager','studio-supervisor','studio-session','studioctl']){
    const path=join(bin,name);
    run('/usr/bin/strip',['-S',path]);
    run('/usr/bin/codesign',['--force','--sign','-','--timestamp=none','--identifier','lab.fios.'+name+'.development',path]);
    const bytes=readFileSync(path);
    if(bytes.readUInt32LE(0)!==0xfeedfacf||bytes.readUInt32LE(4)!==0x0100000c)throw Error('Non-arm64 native artifact');
    add(path,'bin/'+name,0o755);
  }
  add(join(root,'platform/studio/sandbox/runner.py'),'sandbox/runner.py',0o644);
  add(join(root,'platform/studio/sandbox/Dockerfile'),'sandbox/Dockerfile',0o644);
  add(join(root,'uv.lock'),'python/uv.lock',0o644);
  for(const name of ['lab.fios.studio.supervisor.plist','lab.fios.studio.session.plist'])add(join(root,'platform/studio/deployment',name),'launchd/'+name,0o644);
  verifyPlatformSources(sourceProof,root,collectSources());
  const manifest={...template,source_revision:run('/usr/bin/git',['rev-parse','HEAD']),source_tree_sha256:sourceHash,artifacts:artifacts.sort((a,b)=>a.path.localeCompare(b.path)),package_complete:false};
  writeFileSync(join(output,'release.json'),JSON.stringify(manifest,null,2)+'\n',{mode:0o600});
  const manifestSHA=sha(readFileSync(join(output,'release.json')));
  validatePlatformRelease(output,manifestSHA);
  console.log(JSON.stringify({state:'development_observation_only',manifest_sha256:manifestSHA,artifacts:artifacts.length,source_tree_sha256:sourceHash,activation:false}));
}catch(error){
  if(created)rmSync(output,{recursive:true,force:true});
  throw error;
}finally{rmSync(scratch,{recursive:true,force:true});}
