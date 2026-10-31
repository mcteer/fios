// Ordinary actual Swift factory → copied Python runtime metadata integration.
// No dispatch binding, model call, installed service or enrollment is created.
import assert from 'node:assert/strict';
import {mkdtempSync,readdirSync,readFileSync,writeFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
const args=process.argv.slice(2);
assert.equal(args.length,5,'Use --isolated --candidate ABS_RUNTIME --sha256 RECEIPT_SHA256');
assert.equal(args[0],'--isolated');assert.equal(args[1],'--candidate');assert.equal(args[3],'--sha256');assert.ok(args[2].startsWith('/'));assert.match(args[4],/^[a-f0-9]{64}$/);
const root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/private/tmp/fios-009-worker-runtime-');
function run(command,args,timeout){const result=spawnSync(command,args,{encoding:'utf8',timeout,maxBuffer:1<<20});assert.equal(result.status,0,result.stderr||result.error?.message);return result.stdout.trim()}
const review=()=>run(join(root,'.venv/bin/python'),['-I','-B',join(root,'scripts/check-platform-python-candidate.py'),'--candidate',args[2],'--sha256',args[4]],130000);
review();
const bytes=readFileSync(join(args[2],'candidate.json'));
assert.equal(createHash('sha256').update(bytes).digest('hex'),args[4]);
const candidate=JSON.parse(bytes),release=JSON.parse(readFileSync(join(root,'platform/studio/deployment/release.json')));
const executable=join(args[2],'bin/python'),executableSHA=candidate.files['bin/python'].sha256;
const core=join(root,'platform/studio/Sources/StudioCore'),entry=join(directory,'RuntimeMetadata.swift'),binary=join(directory,'worker-runtime');
const sources=readdirSync(core).filter(name=>name.endsWith('.swift')).sort().map(name=>join(core,name));
const digest=()=>{const hash=createHash('sha256');for(const path of sources)hash.update(path.slice(root.length)).update('\0').update(readFileSync(path));return hash.digest('hex')};
const sourceSHA=digest();
writeFileSync(entry,`import Foundation
@main struct RuntimeMetadata {
 static func main() throws {
  let a=CommandLine.arguments
  let factory=try PythonWorkerFactory(invocation:a[1],executableSHA256:a[2],policySHA256:a[3],packageVersion:a[4])
  guard factory.metadata.python_version=="3.11.17",factory.metadata.policy_input_units==Int(a[5]) else {throw RuntimeError.identity}
  print("PASS: actual Swift worker factory accepts copied runtime metadata without model dispatch")
 }
}
`,{mode:0o600});
run('swiftc',['-swift-version','6','-warnings-as-errors','-I',join(root,'platform/studio/Sources/CSQLite'),...sources,entry,'-o',binary],180000);
assert.equal(digest(),sourceSHA);
const output=run('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',binary,executable,executableSHA,release.python.policy_sha256,release.python.package_version,String(release.python.policy_input_utf16)],20000);
review();
const receipt={ok:true,candidate_sha256:args[4],core_source_sha256:sourceSHA,actual_factory:true,copied_runtime:true,model_posts:0,immutable_tree_enrolled:false,activation:false,review_directory:directory};
writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});
console.log(output);console.log(JSON.stringify(receipt));
