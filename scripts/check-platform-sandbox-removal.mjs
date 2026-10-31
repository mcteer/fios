#!/usr/bin/env node
// Explicit one-shot owned-container check, never a service/install/admission API.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdtempSync,mkdirSync,readdirSync,realpathSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {userInfo} from 'node:os';
import {createHash} from 'node:crypto';
import {capturePlatformSources,verifyPlatformSources} from './lib/platform-source.mjs';
import {sandboxImageFile} from './lib/platform-sandbox-image.mjs';
const args=process.argv.slice(2),root=resolve(import.meta.dirname,'..');
assert(process.platform==='darwin'&&process.getuid()>0&&args.length===3&&args[0]==='--isolated'&&args[1]==='--base'&&/^sha256:[a-f0-9]{64}$/.test(args[2]));
const directory=mkdtempSync('/private/tmp/fios-sandbox-removal-'),sha=b=>createHash('sha256').update(b).digest('hex');
const developer='/Applications/Xcode.app/Contents/Developer',home=userInfo().homedir,socket=join(home,'.orbstack/run/docker.sock');
const env={PATH:'/usr/bin:/bin',HOME:home,LANG:'C',LC_ALL:'C',DEVELOPER_DIR:developer,DOCKER_CONFIG:'/var/empty',DOCKER_CLI_HINTS:'false',DOCKER_BUILDKIT:'0'};
function run(file,argv,timeout=10000){const r=spawnSync(file,argv,{env,encoding:'utf8',timeout,maxBuffer:4<<20});if(r.error||r.status!==0){if(file.endsWith('/swiftc'))writeFileSync(join(directory,'compiler-stderr.log'),r.stderr??'',{mode:0o600});throw Error('Finite sandbox-removal operation refused; retained state: '+directory);}return r.stdout;}
let possible=false,complete=false;
try {
 const status=realpathSync('/Applications/OrbStack.app/Contents/MacOS/scli.app/Contents/MacOS/scli');
 assert.equal(sha(sandboxImageFile(status,128<<20)),'b2793e99e3f452b86233d59cd5e503e069821224c022628f52521dc5b4bcab8a');
 assert.equal(run(status,['status'],2000),'Running\n');
 const cliBytes=sandboxImageFile(realpathSync('/Applications/OrbStack.app/Contents/MacOS/xbin/docker-tools'),512<<20),cliHash='927c58aed356a37f08f2586a90df4c6d8c5e890060de95ac3d11301d03959463';assert.equal(sha(cliBytes),cliHash);
 const docker=join(directory,'docker');writeFileSync(docker,cliBytes,{mode:0o700});
 const runtime=(argv,timeout)=>run(docker,['--host','unix://'+socket,...argv],timeout).trim();
 const base=JSON.parse(runtime(['image','inspect',args[2]]))[0];assert.equal(base.Id,args[2]);assert.equal(base.Os,'linux');assert.equal(base.Architecture,'arm64');assert(!base.Config?.OnBuild?.length);
 const core=join(root,'platform/studio/Sources/StudioCore'),files=readdirSync(core).filter(n=>n.endsWith('.swift')).sort().map(n=>join(core,n));
 const fixture=join(root,'platform/studio/Tests/StudioCoreTests/SandboxRemovalLive.swift.fixture');
 const inputs=[...files,fixture,join(root,'scripts/check-platform-sandbox-removal.mjs'),join(root,'scripts/lib/platform-source.mjs'),join(root,'scripts/lib/platform-sandbox-image.mjs'),...readdirSync(join(root,'platform/studio/Sources/CSQLite')).map(n=>join(root,'platform/studio/Sources/CSQLite',n))];
 const proof=capturePlatformSources(root,inputs);
 assert.equal(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-version']).trim(),'27.2');
 const sdk=realpathSync(run('/usr/bin/xcrun',['--sdk','macosx','--show-sdk-path']).trim());
 const compiler=run('/usr/bin/xcrun',['--sdk','macosx','--find','swiftc']).trim();
 assert(compiler.startsWith(developer+'/Toolchains/')&&compiler.endsWith('/usr/bin/swiftc'));
 const compilerHash=sha(sandboxImageFile(realpathSync(compiler),512<<20));
 run('/usr/bin/codesign',['--verify','--strict','--test-requirement','=anchor apple',compiler]);
 const unit=join(directory,'Live.swift'),binary=join(directory,'sandbox-removal-live');writeFileSync(unit,sandboxImageFile(fixture));
 run(compiler,['-sdk',sdk,'-target','arm64-apple-macosx14.0','-parse-as-library','-swift-version','6','-warnings-as-errors','-O','-I',join(root,'platform/studio/Sources/CSQLite'),...files,unit,'-o',binary],180000);
 const context=join(directory,'context');mkdirSync(context,{mode:0o700});
 writeFileSync(join(context,'Dockerfile'),`FROM ${args[2]}\nCOPY hold.py /hold.py\nENTRYPOINT ["/opt/venv/bin/python","-I","-B","/hold.py"]\n`,{mode:0o600});
 writeFileSync(join(context,'hold.py'),"import signal,sys,time\nsignal.signal(signal.SIGTERM,signal.SIG_IGN)\nopen('/workspace/ready','w').write('READY\\n')\ntime.sleep(0.05 if sys.argv[1:]==['fast'] else 45)\n",{mode:0o644});
 writeFileSync(join(directory,'fixture-state.json'),JSON.stringify({phase:'before-image-build',base:args[2],activation:false})+'\n',{mode:0o600});possible=true;
 const image=runtime(['build','--quiet','--pull=false','--network=none',context],120000);assert.match(image,/^sha256:[a-f0-9]{64}$/);
 writeFileSync(join(directory,'fixture-state.json'),JSON.stringify({phase:'before-owned-runtime-check',base:args[2],image,activation:false})+'\n',{mode:0o600});
 const result=spawnSync(binary,[docker,cliHash,socket,image],{env,encoding:'utf8',timeout:90000,maxBuffer:1<<20});
 writeFileSync(join(directory,'stdout.log'),result.stdout??'',{mode:0o600});writeFileSync(join(directory,'stderr.log'),result.stderr??'',{mode:0o600});assert(!result.error&&!result.signal);assert.equal(result.status,0,'Owned runtime check failed; retained: '+directory);
 const measured=JSON.parse(result.stdout.trim());assert.equal(measured.running_remove_refused,true);assert.equal(measured.daemon_plain_rm_running_refused,true);assert.equal(measured.unstarted_exit_not_certified,true);assert.equal(measured.successful_zero_exit_certified,true);assert(measured.graceful_stop_then_absence_ms>=9000&&measured.graceful_stop_then_absence_ms<60000);
 verifyPlatformSources(proof,root,inputs);assert.equal(sha(sandboxImageFile(realpathSync(compiler),512<<20)),compilerHash);
 const receipt={version:1,purpose:'isolated_owned_sandbox_removal',base_image:args[2],image,source_inputs_sha256:proof.digest,scope:'declared_swift_runtime_and_fixture_inputs_only',compiler_sha256:compilerHash,binary_sha256:sha(readFileSync(binary)),...measured,activation:false};
 const bytes=Buffer.from(JSON.stringify(receipt,null,2)+'\n');writeFileSync(join(directory,'candidate.json'),bytes,{mode:0o600});complete=true;console.log(JSON.stringify({directory,receipt_sha256:sha(bytes),...measured}));
} finally {if(!complete)console.error((possible?'RETAINED possible image/container state: ':'RETAINED preflight/build state: ')+directory);}
