#!/usr/bin/env node
// Finite artifact-only rehearsal; no controller/state/runtime/native service.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {mkdtempSync,readFileSync,writeFileSync,readdirSync,rmSync,mkdirSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {tmpdir} from 'node:os';
import {validatePlatformRelease} from './lib/platform-release.mjs';
import {capturePlatformSources,verifyPlatformSources} from './lib/platform-source.mjs';
const args=process.argv.slice(2),root=resolve(import.meta.dirname,'..');
assert(process.platform==='darwin'&&process.getuid()!==0);
assert(args.length===5&&args[0]==='--isolated'&&args[1]==='--release'&&args[3]==='--sha256');
validatePlatformRelease(args[2],args[4]);
const source=join(root,'platform/studio/Sources/StudioCore/ReleaseStaging.swift'),types=join(root,'platform/studio/Sources/StudioCore/Types.swift');
const test=join(root,'platform/studio/Tests/StudioCoreTests/ReleaseStagingTests.swift');
const core=join(root,'platform/studio/Sources/StudioCore');
const files=[...readdirSync(core).filter(n=>n.endsWith('.swift')).map(n=>join(core,n)),test,join(root,'platform/studio/Sources/StudioCLI/main.swift'),join(root,'platform/studio/Package.swift'),resolve(import.meta.filename)];
const proof=capturePlatformSources(root,files),original=readFileSync(source,'utf8'),scratch=mkdtempSync(join(tmpdir(),'fios-stage-rehearsal-'));
const profile='(version 1)(allow default)(deny network*)';
const run=(program,argv,{expected=0,timeout=120000}={})=>{
 const result=spawnSync(program,argv,{encoding:'utf8',timeout,maxBuffer:1<<20,env:{PATH:process.env.PATH,HOME:process.env.HOME,LANG:'C',LC_ALL:'C'}});
 assert.equal(result.error,undefined);assert.equal(result.status,expected,(result.stdout??'')+(result.stderr??''));return (result.stdout??'')+(result.stderr??'');
};
const guarded=(program,argv,options)=>run('/usr/bin/sandbox-exec',['-p',profile,program,...argv],options);
try {
 const main=join(scratch,'UnitMain.swift');writeFileSync(main,'import Foundation\n@main struct UnitMain {static func main()throws {try runReleaseStagingTests()}}\n');
 for(const optimize of [false,true]){
  const binary=join(scratch,optimize?'optimized':'debug');run('/usr/bin/env',['swiftc','-swift-version','6','-warnings-as-errors',...(optimize?['-O']:[]),types,source,test,main,'-o',binary]);
  console.log(guarded(binary,[]));
 }
 let witnessIndex=0;
 function witness(label,variant,expectedCase){
  const folder=join(scratch,label+"-"+(witnessIndex++));mkdirSync(folder,{mode:0o700});const swift=join(folder,'ReleaseStaging.swift'),entry=join(folder,'Main.swift'),binary=join(folder,'witness'),destination=join(folder,'destination');
  writeFileSync(swift,variant);
  writeFileSync(entry,`import Foundation\nimport Darwin\n@main struct Witness {static func main()throws {do {_=try PlatformReleaseStaging.create(source:URL(fileURLWithPath:CommandLine.arguments[1]),expectedSHA256:CommandLine.arguments[2],destination:URL(fileURLWithPath:CommandLine.arguments[3]));print("${label}_UNSAFE_SUCCESS");exit(77)}catch PlatformReleaseStagingError.${expectedCase} {print("${label}_EXPECTED_REFUSAL")}catch {print("${label}_WRONG_OUTCOME");exit(77)}}}\n`);
  run('/usr/bin/env',['swiftc','-O','-swift-version','6','-warnings-as-errors',types,swift,entry,'-o',binary]);
  return {binary,destination,label};
 }
 const execute=(witness,expected)=>guarded(witness.binary,[args[2],args[4],witness.destination],{expected});
 const copyPin='                try verify(input,before,parent:from,name:leaf)';assert.equal(original.split(copyPin).length,2);
 const corrupted=original.replace(copyPin,copyPin+'\n                var bad:UInt8=0x19;guard pwrite(output,&bad,1,0)==1 else {try fail()} // Private copied-byte corruption.');
 const hashPin='copiedHash.finalize().map({String(format:"%02x",$0)}).joined()==item.hash';assert.equal(corrupted.split(hashPin).length,2);
 console.log(execute(witness('STAGING_COPY_HASH',corrupted,'retained'),0));
 const weakHash=corrupted.replace(','+hashPin,'');assert.notEqual(weakHash,corrupted);
 assert.match(execute(witness('STAGING_COPY_HASH',weakHash,'retained'),77),/STAGING_COPY_HASH_UNSAFE_SUCCESS/);
 const racePin='            var named=stat()';assert.equal(original.split(racePin).length,2);
 const raced=original.replace(racePin,'            guard mkdirat(parentFD,name,0o700)==0 else {try fail()} // Private publication race.\n'+racePin);
 console.log(execute(witness('STAGING_NO_REPLACE',raced,'retained'),0));
 assert.match(execute(witness('STAGING_NO_REPLACE',raced.replace('UInt32(RENAME_EXCL)','0'),'retained'),77),/STAGING_NO_REPLACE_UNSAFE_SUCCESS/);
 const directoryPin='            try directory(target,privateOnly:true)';assert.equal(original.split(directoryPin).length,2);
 const substituted=original.replace(directoryPin,'            guard renameat(target,"bin",parentFD,"orphan-"+temporary)==0,mkdirat(target,"bin",0o700)==0 else {try fail()} // Private directory substitution.\n'+directoryPin);
 const bindingPin='                try childDirectory(targets[folder]!,parent:target,name:folder)';assert.equal(substituted.split(bindingPin).length,2);
 console.log(execute(witness('STAGING_DIRECTORY_BIND',substituted,'retained'),0));
 assert.match(execute(witness('STAGING_DIRECTORY_BIND',substituted.replace(bindingPin,''),'retained'),77),/STAGING_DIRECTORY_BIND_UNSAFE_SUCCESS/);
 const published=original.replace('            published=true','            published=true\n            if getpid()>0 {try fail()} // Private post-publication durability fault.');assert.notEqual(published,original);
 console.log(execute(witness('STAGING_PUBLISHED_STATE',published,'publicationUncertain'),0));
 assert.match(execute(witness('STAGING_PUBLISHED_STATE',published.replace('published=true','published=false'),'publicationUncertain'),77),/STAGING_PUBLISHED_STATE_WRONG_OUTCOME/);
 // Build the actual CLI in private scratch; parent network restriction remains
 // while SwiftPM's nested manifest sandbox is disabled. No dependency fetches.
 const product=join(scratch,'product');
 guarded('/usr/bin/env',['swift','build','--disable-sandbox','--package-path',join(root,'platform/studio'),'--scratch-path',product,'--product','studioctl'],{timeout:180000});
 const directory=guarded('/usr/bin/env',['swift','build','--disable-sandbox','--package-path',join(root,'platform/studio'),'--scratch-path',product,'--show-bin-path']).trim();
 const cli=join(directory,'studioctl'),destination=join(scratch,'actual-staged');
 const receipt=JSON.parse(guarded(cli,['stage-release','--from',args[2],'--sha256',args[4],'--to',destination]));
 assert.equal(receipt.installed,false);assert.equal(receipt.activation,false);assert.equal(receipt.artifacts,9);
 validatePlatformRelease(destination,args[4]);
 guarded(cli,['stage-release','--from',args[2],'--sha256',args[4],'--to',destination],{expected:1});
 verifyPlatformSources(proof,root,files);validatePlatformRelease(args[2],args[4]);
 console.log('PASS: Debug/optimized staging, actual CLI exact copied release, private corruption/no-replace/directory-binding/post-publication guard witnesses; no state/service/runtime/inference/installation authority');
}finally {rmSync(scratch,{recursive:true,force:true});}
