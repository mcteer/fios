// Local, outbound-only delivery agent. Never executes PR code or opens a listener.
import {spawn} from 'node:child_process';
import {mkdirSync,readFileSync,writeFileSync,renameSync,rmSync,existsSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {homedir} from 'node:os';
import {fileURLToPath} from 'node:url';

export const REQUIRED_CHECKS = ['Tests (Node 22.23.4)','Tests (Node 24.15.0)','Browser regressions','Dependency audits','ARM64 container and rollback','CI gate'];
export function greenChecks(checks) {
  return REQUIRED_CHECKS.every(name => checks.some(c => c.name === name && c.status === 'completed' && c.conclusion === 'success')) &&
    checks.every(c => c.status === 'completed' && c.conclusion === 'success');
}
export async function execute(program,args,{cwd,env=process.env,timeout=20*60*1000}={}) {
  return new Promise((resolveResult,reject)=>{
    const child=spawn(program,args,{cwd,env,stdio:['ignore','pipe','pipe'],shell:false});
    let output='',size=0;
    const timer=setTimeout(()=>{child.kill('SIGKILL');reject(new Error('command_timeout'));},timeout);
    child.stdout.on('data',chunk=>{size+=chunk.length;if(size<=1024*1024)output+=chunk;});
    // Raw command failures may contain sensitive deployment settings. Never forward them.
    child.stderr.resume();
    child.on('error',()=>{clearTimeout(timer);reject(new Error('command_failed'));});
    child.on('close',code=>{clearTimeout(timer);code===0?resolveResult(output.trim()):reject(new Error('command_failed'));});
  });
}
const backupCode = `const fs=require('node:fs');const path=require('node:path');const root='/app/data';const name=process.argv[1];if(!/^before-[a-f0-9-]+$/.test(name))throw new Error('invalid_backup');const dest=path.join(root,'backups',name);fs.mkdirSync(dest,{recursive:true,mode:0o700});for(const f of fs.readdirSync(root)){if(f!=='backups')fs.cpSync(path.join(root,f),path.join(dest,f),{recursive:true,errorOnExist:true,force:false});}fs.writeFileSync(path.join(dest,'complete'),'stopped-volume snapshot\\n',{mode:0o600});`;
const verifyCode = `const origin='http://127.0.0.1:3000';const health=await fetch(origin+'/health');if(!health.ok)throw new Error('health_failed');const login=await fetch(origin+'/api/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password:process.env.FIOS_PASSWORD})});if(!login.ok)throw new Error('login_failed');const cookie=login.headers.get('set-cookie')?.split(';')[0];if(!cookie)throw new Error('session_failed');const response=await fetch(origin+'/api/models',{headers:{Cookie:cookie}});if(!response.ok)throw new Error('discovery_failed');const data=await response.json();if(!Array.isArray(data.models)||!data.models.length)throw new Error('empty_catalog');if(data.hosts&&(!data.hosts.some(h=>h.name==='gateway'&&h.status==='available')||!data.models.some(m=>m.availability==='available')))throw new Error('gateway_unavailable');console.log('Authenticated non-inference discovery verified: '+data.models.length+' models');`;

// Injectable command boundaries allow an actual isolated Compose rehearsal and failure-path tests.
export async function deployRelease({image,service='fios',run,compose,stamp=Date.now().toString(16),beforeStop=async()=>{},publish=async()=>{}}) {
  const container=await compose(image,['ps','-q',service]);
  if(!/^[a-f0-9]{12,64}$/.test(container))throw new Error('existing_application_required');
  const previous=await run(['inspect','--format','{{.Image}}',container]);
  if(!/^sha256:[a-f0-9]{64}$/.test(previous))throw new Error('invalid_previous_image');
  const volume=await run(['inspect','--format','{{range .Mounts}}{{if eq .Destination "/app/data"}}{{.Name}}{{end}}{{end}}',container]);
  if(!/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(volume))throw new Error('named_data_volume_required');
  const rollback='fios:rollback-'+stamp;
  const backup='before-'+stamp;
  await run(['tag',previous,rollback]);
  await beforeStop();
  let stopped=false;
  try {
    stopped=true;
    await compose(image,['stop','-t','12',service]);
    const backupContainer='fios-backup-'+stamp;
    try {
      await run(['run','--rm','--name',backupContainer,'--network','none','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges','--user','1000:1000',
        '--mount',`type=volume,source=${volume},target=/app/data`,'--entrypoint','node',rollback,'-e',backupCode,backup]);
    } finally { await run(['rm','--force',backupContainer]).catch(()=>{}); }
    await compose(image,['up','-d','--no-build','--pull','never','--wait','--wait-timeout','120',service]);
    const verification=await compose(image,['exec','-T',service,'node','--input-type=module','-e',verifyCode]);
    await compose(image,['exec','-T',service,'/opt/venv/bin/python','-I','-B','-c',
      "import asyncio;from fios_agent.worker import Settings;from fios_agent.availability import discover;r=asyncio.run(discover(Settings.from_environment()));assert any(m['availability']=='available' for m in r['models']);print('Python harness non-inference discovery verified')"]);
    await publish();
    return {image,previousImage:rollback,backup:`${volume}/backups/${backup}`,verification};
  } catch {
    if(stopped){
      try {
        await compose(rollback,['stop','-t','12',service]);
        await compose(rollback,['up','-d','--no-build','--pull','never','--wait','--wait-timeout','120',service]);
        await compose(rollback,['exec','-T',service,'node','--input-type=module','-e',verifyCode]);
      } catch {throw new Error('deployment_and_rollback_failed');}
    }
    // No schema migration: roll the image back on the same data. Never discard new records automatically.
    throw new Error('deployment_failed_previous_image_restored');
  }
}

function atomicJson(path,value){const temp=path+'.tmp';writeFileSync(temp,JSON.stringify(value)+'\n',{mode:0o600});renameSync(temp,path);}
function record(value){console.log(JSON.stringify({phase:'deploy',time:new Date().toISOString(),...value}));}
export async function poll({repo,state,repository='mcteer/fios'}) {
  if(process.platform!=='darwin')throw new Error('macos_application_host_required');
  mkdirSync(state,{recursive:true,mode:0o700});
  const lock=join(state,'deploy.pid');
  // macOS shlock atomically serializes runs and reclaims locks whose owner has exited.
  try{await execute('/usr/bin/shlock',['-p',String(process.pid),'-f',lock]);}catch{return {status:'busy'};}
  const stateFile=join(state,'state.json');
  let stored={};
  let sha;
  try {
    stored=existsSync(stateFile)?JSON.parse(readFileSync(stateFile,'utf8')):{};
    const gh=async args=>execute('gh',args,{cwd:repo,timeout:30000});
    sha=await gh(['api',`repos/${repository}/commits/main`,'--jq','.sha']);
    if(!/^[a-f0-9]{40}$/.test(sha))throw new Error('invalid_revision');
    if(stored.deployedSha===sha || stored.failedSha===sha)return {status:'unchanged',sha};
    const runs=JSON.parse(await gh(['run','list','--repo',repository,'--branch','main','--event','push','--workflow','ci.yml','--commit',sha,'--json','headSha,status,conclusion']));
    const checks=JSON.parse(await gh(['api',`repos/${repository}/commits/${sha}/check-runs?filter=latest&per_page=100`])).check_runs;
    if(!runs.some(r=>r.headSha===sha&&r.status==='completed'&&r.conclusion==='success')||!greenChecks(checks))return {status:'waiting_for_ci',sha};
    await execute('git',['fetch','--no-tags','origin','main'],{cwd:repo,timeout:60000});
    const remote=await execute('git',['rev-parse','refs/remotes/origin/main'],{cwd:repo});
    if(remote!==sha)return {status:'superseded',sha};
    const release=join(state,'releases',sha);
    if(!existsSync(join(release,'.snapshot-complete'))){
      rmSync(release,{recursive:true,force:true});
      mkdirSync(release,{recursive:true,mode:0o700});
      const archive=join(state,sha+'.tar');
      await execute('git',['archive','--format=tar','--output',archive,sha],{cwd:repo});
      await execute('tar',['-xf',archive,'-C',release]);
      rmSync(archive);
      writeFileSync(join(release,'.snapshot-complete'),'ok\n',{mode:0o600});
    }
    const envFile=join(repo,'.env');
    if(!existsSync(envFile))throw new Error('private_environment_missing');
    const run=args=>execute('docker',args,{cwd:release});
    const image='fios:'+sha;
    const compose=(selected,args)=>execute('docker',['compose','--env-file',envFile,'--project-name','fios','--file',join(release,'compose.yaml'),...args],
      {cwd:release,env:{...process.env,FIOS_IMAGE:selected}});
    await compose(image,['config','--quiet']);
    await run(['build','--label','org.opencontainers.image.revision='+sha,'--tag',image,release]);
    const result=await deployRelease({image,run,compose,beforeStop:async()=>{
      if(await gh(['api',`repos/${repository}/commits/main`,'--jq','.sha'])!==sha)throw new Error('superseded');
      const currentChecks=JSON.parse(await gh(['api',`repos/${repository}/commits/${sha}/check-runs?filter=latest&per_page=100`])).check_runs;
      if(!greenChecks(currentChecks))throw new Error('ci_not_green');
    },publish:async()=>{
      const deployed=await compose(image,['ps','-q','fios']);
      const revision=await run(['inspect','--format','{{index .Config.Labels "org.opencontainers.image.revision"}}',deployed]);
      if(revision!==sha)throw new Error('deployed_revision_mismatch');
      const original=readFileSync(envFile,'utf8');
      const line='FIOS_IMAGE='+image;
      const updated=/^FIOS_IMAGE=.*$/m.test(original)?original.replace(/^FIOS_IMAGE=.*$/m,line):original+(original.endsWith('\n')?'':'\n')+line+'\n';
      writeFileSync(envFile+'.deploy-tmp',updated,{mode:0o600});
      renameSync(envFile+'.deploy-tmp',envFile);
    }});
    stored={...stored,deployedSha:sha,failedSha:null,deployedAt:new Date().toISOString(),...result};
    atomicJson(stateFile,stored);
    record({status:'deployed',sha,backup:result.backup});
    return {status:'deployed',sha};
  } catch(error){
    const code=['deployment_failed_previous_image_restored','deployment_and_rollback_failed'].includes(error.message)?error.message:'deployment_blocked';
    if(sha)atomicJson(stateFile,{...stored,...(code!=='deployment_blocked'?{failedSha:sha}:{}),lastError:code,failedAt:new Date().toISOString()});
    record({status:code,sha});
    throw new Error(code);
  } finally {rmSync(lock,{force:true});}
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const args=process.argv.slice(2);
  const option=(key,fallback)=>{const i=args.indexOf(key);return i<0?fallback:args[i+1];};
  const repo=resolve(option('--repo',fileURLToPath(new URL('../',import.meta.url))));
  const state=resolve(option('--state',join(homedir(),'Library','Application Support','Fios','deploy')));
  try {const result=await poll({repo,state});if(result.status!=='deployed')record(result);}
  catch {process.exitCode=1;}
}
