#!/usr/bin/env node
import {spawnSync} from 'node:child_process';
import {mkdtempSync,readFileSync,writeFileSync,rmSync} from 'node:fs';
import {join,resolve} from 'node:path';
const args=process.argv.slice(2);
if(args.length!==2||args[0]!=='--isolated'||!/^\d+$/.test(args[1])||Number(args[1])<5||Number(args[1])>300)throw Error('Usage: node scripts/check-platform-idle.mjs --isolated SECONDS_5_TO_300');
const root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/tmp/fios-idle-build-');
function run(command,args,timeout=120000){
  const result=spawnSync(command,args,{cwd:root,encoding:'utf8',timeout,maxBuffer:1<<20});
  if(result.status!==0)throw Error(`Idle fixture failed (${result.status??result.signal}): ${result.stderr??''}\n${result.stdout??''}`);
  return result.stdout.trim();
}
try{
  run('swift',['build','--package-path','platform/studio','-c','release']);
  const bin=run('swift',['build','--package-path','platform/studio','-c','release','--show-bin-path']);
  const source=join(directory,'IdleLive.swift'),binary=join(directory,'idle-live');
  writeFileSync(source,readFileSync(join(root,'platform/studio/Tests/StudioCoreTests/IdleLive.swift.fixture')));
  run('/usr/bin/env',['swiftc','-swift-version','6','-O','-warnings-as-errors','-I',join(root,'platform/studio/Sources/CSQLite'),...run('/usr/bin/find',[join(root,'platform/studio/Sources/StudioCore'),'-name','*.swift']).split('\n').sort(),source,'-o',binary]);
  console.log(run(binary,[join(bin,'studio-supervisor'),args[1]],(Number(args[1])+30)*1000));
}finally{rmSync(directory,{recursive:true,force:true});}
