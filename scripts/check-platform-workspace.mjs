// Ordinary request/configuration/journal flow, without a runtime or model.
import assert from 'node:assert/strict';
import {mkdtempSync,readdirSync,writeFileSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
assert.deepEqual(process.argv.slice(2),['--isolated']);
const root=resolve(import.meta.dirname,'..'),directory=mkdtempSync('/private/tmp/fios-009-workspace-');
const core=join(root,'platform/studio/Sources/StudioCore'),entry=join(directory,'WorkspaceMain.swift');
writeFileSync(entry,'@main struct WorkspaceMain { static func main() throws { try runWorkspaceConfigurationTests() } }\n');
const sources=readdirSync(core).filter(name=>name.endsWith('.swift')).sort().map(name=>join(core,name));
for(const optimized of [false,true]){
 const binary=join(directory,optimized?'workspace-release':'workspace-debug');
 const build=spawnSync('swiftc',['-swift-version','6','-warnings-as-errors',...(optimized?['-O']:[]),'-I',join(root,'platform/studio/Sources/CSQLite'),...sources,join(root,'platform/studio/Tests/StudioCoreTests/WorkspaceConfigurationTests.swift'),entry,'-o',binary],{encoding:'utf8',timeout:180000,maxBuffer:2<<20});
 assert.equal(build.status,0,build.stderr);
 const result=spawnSync(binary,[],{encoding:'utf8',timeout:15000,maxBuffer:65536});
 assert.equal(result.status,0,result.stderr);process.stdout.write(result.stdout);
}
console.log(JSON.stringify({ok:true,configurations:2,runtime_commands:0,model_requests:0,review_directory:directory}));
