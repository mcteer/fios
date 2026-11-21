// Ordinary actual Swift factory → copied Python runtime metadata integration.
// No dispatch binding, model call, installed service or enrollment is created.
import assert from 'node:assert/strict';
import {mkdtempSync,readdirSync,readFileSync,writeFileSync,lstatSync,realpathSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {validatePlatformRelease} from './lib/platform-release.mjs';
const args=process.argv.slice(2);
const withEnrollment=args.length===9&&args[5]==='--enrollment-proposal'&&args[7]==='--proposal-sha256';
assert(args.length===5||withEnrollment,'Use --isolated --candidate ABS_RUNTIME --sha256 RECEIPT_SHA256 [--enrollment-proposal ABS_FILE --proposal-sha256 SHA256]');
assert.equal(args[0],'--isolated');assert.equal(args[1],'--candidate');assert.equal(args[3],'--sha256');assert.ok(args[2].startsWith('/'));assert.match(args[4],/^[a-f0-9]{64}$/);
const root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/private/tmp/fios-009-worker-runtime-');
function run(command,args,timeout){const result=spawnSync(command,args,{encoding:'utf8',timeout,maxBuffer:1<<20});assert.equal(result.status,0,result.stderr||result.error?.message);return result.stdout.trim()}
const review=()=>run(join(root,'.venv/bin/python'),['-I','-B',join(root,'scripts/check-platform-python-candidate.py'),'--candidate',args[2],'--sha256',args[4]],130000);
review();
const bytes=readFileSync(join(args[2],'candidate.json'));
assert.equal(createHash('sha256').update(bytes).digest('hex'),args[4]);
const candidate=JSON.parse(bytes),release=JSON.parse(readFileSync(join(root,'platform/studio/deployment/release.json')));
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const runnerSHA=sha(readFileSync(new URL(import.meta.url)));
let proposalBytes,managerSHA;
if(withEnrollment){
 assert.match(args[8],/^[a-f0-9]{64}$/);assert(args[6].startsWith('/private/tmp/')&&realpathSync(args[6])===args[6]);
 const info=lstatSync(args[6]),parent=lstatSync(resolve(args[6],'..'));
 assert(info.isFile()&&info.nlink===1&&info.uid===process.getuid()&&info.size>0&&info.size<=65536);
 assert(parent.isDirectory()&&parent.uid===process.getuid()&&(parent.mode&0o7777)===0o700);
 proposalBytes=readFileSync(args[6]);assert.equal(sha(proposalBytes),args[8]);
 const proposal=JSON.parse(proposalBytes),compositionRoot=resolve(args[2],'..');
 assert.equal(resolve(args[2]),join(compositionRoot,'python-runtime'));
 const compositionBytes=readFileSync(join(compositionRoot,'composition.json'));
 assert.equal(sha(compositionBytes),proposal.composition_sha256);
 const composition=JSON.parse(compositionBytes);assert.equal(composition.python_candidate_sha256,args[4]);
 const platform=validatePlatformRelease(join(compositionRoot,'platform'),composition.platform_manifest_sha256);
 managerSHA=platform.manifest.artifacts.find(item=>item.path==='bin/studio-manager').sha256;
 assert.equal(proposal.operation,'python_enrollment_configuration_proposal');assert.equal(proposal.state,'blocked');
 assert.deepEqual(JSON.parse(proposal.policy_candidate_json),proposal.policy_candidate);
 assert.equal(sha(Buffer.from(proposal.policy_candidate_json)),proposal.policy_candidate_sha256);
 assert.equal(proposal.policy_candidate.manager_sha256,managerSHA);
}
const executable=join(args[2],'bin/python'),executableSHA=candidate.files['bin/python'].sha256;
const core=join(root,'platform/studio/Sources/StudioCore'),entry=join(directory,'RuntimeMetadata.swift'),binary=join(directory,'worker-runtime');
const sources=readdirSync(core).filter(name=>name.endsWith('.swift')).sort().map(name=>join(core,name));
const digest=()=>{const hash=createHash('sha256');for(const path of sources)hash.update(path.slice(root.length)).update('\0').update(readFileSync(path));return hash.digest('hex')};
const sourceSHA=digest();
writeFileSync(entry,`import Foundation
import CryptoKit
import CoreFoundation
@main struct RuntimeMetadata {
 static func main() throws {
  let a=CommandLine.arguments
  let tree=try PythonRuntimeTreeReview.privateCandidate(directory:URL(fileURLWithPath:a[6]),manifestSHA256:a[7])
  guard !tree.rootProtected,tree.files==Int(a[8]),tree.bytes==Int64(a[9]) else {throw RuntimeError.identity}
  guard tree.interpreterSHA256==a[2],tree.lockSHA256==a[10],tree.producerSHA256==a[11],tree.templateSHA256==a[12] else {throw RuntimeError.identity}
  if a.count==16 {
   let bytes=try Data(contentsOf:URL(fileURLWithPath:a[13]))
   guard SHA256.hash(data:bytes).map({String(format:"%02x",$0)}).joined()==a[14] else {throw RuntimeError.identity}
   try StrictJSON.validate(bytes,maximum:65536)
   guard let envelope=try JSONSerialization.jsonObject(with:bytes) as? [String:Any],
         envelope["operation"] as? String=="python_enrollment_configuration_proposal",
         envelope["state"] as? String=="blocked",let encoded=envelope["policy_candidate_json"] as? String,
         let payload=encoded.data(using:.utf8),payload.count<=4096,
         SHA256.hash(data:payload).map({String(format:"%02x",$0)}).joined()==envelope["policy_candidate_sha256"] as? String else {throw RuntimeError.identity}
   for name in ["commands_authorized","approved","policy_written","credentials_written","state_opened","installed","activation","native_authority"] {
    guard let flag=envelope[name] as? NSNumber,CFGetTypeID(flag)==CFBooleanGetTypeID(),!flag.boolValue else {throw RuntimeError.identity}
   }
   let document=try PythonRuntimeEnrollmentDocument(payload)
   guard document.managerSHA256==a[15],document.manifestSHA256==a[7],document.pythonSHA256==a[2],
         document.lockSHA256==a[10],document.producerSHA256==a[11],document.templateSHA256==a[12],
         document.policySHA256==a[3],!document.matches(tree) else {throw RuntimeError.identity}
   if let _=try PythonRuntimeEnrolledPolicy.load(directory:URL(fileURLWithPath:document.statePath)) {throw RuntimeError.identity}
   guard let policy=try JSONSerialization.jsonObject(with:payload) as? [String:Any] else {throw RuntimeError.identity}
   let invalidFields:[(String,Any)]=[("uid",0),("uid",true),("host","fios-core"),("approved",true)]
   for (name,value) in invalidFields {
    var invalid=policy;invalid[name]=value
    var accepted=false
    do {_=try PythonRuntimeEnrollmentDocument(JSONSerialization.data(withJSONObject:invalid,options:[.sortedKeys]));accepted=true} catch {}
    guard !accepted else {throw RuntimeError.identity}
   }
   print("PASS: proposed enrollment decodes and binds genuine components without root protection or policy issuance")
   print("PASS: four malformed/authority-field policies and the actual private image cannot issue enrollment")
  }
  let factory=try PythonWorkerFactory(invocation:a[1],executableSHA256:a[2],policySHA256:a[3],packageVersion:a[4])
  guard factory.metadata.python_version=="3.11.17",factory.metadata.policy_input_units==Int(a[5]) else {throw RuntimeError.identity}
  print("PASS: actual Swift worker factory accepts copied runtime metadata without model dispatch")
 }
}
`,{mode:0o600});
const entrySHA=sha(readFileSync(entry));
run('swiftc',['-swift-version','6','-warnings-as-errors','-j2','-I',join(root,'platform/studio/Sources/CSQLite'),...sources,entry,'-o',binary],180000);
assert.equal(digest(),sourceSHA);
const binarySHA=sha(readFileSync(binary));
const invocation=[binary,executable,executableSHA,release.python.policy_sha256,release.python.package_version,String(release.python.policy_input_utf16),args[2],args[4],String(Object.keys(candidate.files).length),String(candidate.bytes),candidate.uv_lock_sha256,candidate.producer_sha256,candidate.release_template_sha256];
let output=run('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',...invocation],145000);
if(withEnrollment)output+='\n'+run('/usr/bin/sandbox-exec',['-p','(version 1)(allow default)(deny network*)',...invocation,args[6],args[8],managerSHA],145000);
review();
assert.equal(digest(),sourceSHA);assert.equal(sha(readFileSync(entry)),entrySHA);assert.equal(sha(readFileSync(binary)),binarySHA);assert.equal(sha(readFileSync(new URL(import.meta.url))),runnerSHA);
if(withEnrollment)assert(readFileSync(args[6]).equals(proposalBytes));
const receipt={ok:true,candidate_sha256:args[4],core_source_sha256:sourceSHA,runner_sha256:runnerSHA,entry_sha256:entrySHA,binary_sha256:binarySHA,actual_factory:true,copied_runtime:true,native_byte_tree_review:true,enrollment_proposal_decoded:withEnrollment,enrollment_refusal_cases:withEnrollment?4:0,private_image_policy_refused:withEnrollment,policy_issued:false,root_protection_proven:false,model_posts:0,immutable_tree_enrolled:false,activation:false,review_directory:directory};
if(withEnrollment)receipt.proposal_sha256=args[8];
writeFileSync(join(directory,'receipt.json'),JSON.stringify(receipt,null,2)+'\n',{mode:0o600});
console.log(output);console.log(JSON.stringify(receipt));
