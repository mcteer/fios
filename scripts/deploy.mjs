// Container-only outbound delivery controller. No listener, native service or PR execution.
import {spawn} from 'node:child_process';
import {mkdirSync,readFileSync,writeFileSync,renameSync,rmSync,existsSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {setTimeout as delay} from 'node:timers/promises';

export const REQUIRED_CHECKS=['Tests (Node 22.23.4)','Tests (Node 24.15.0)','Browser regressions','Dependency audits','ARM64 container and rollback','CI gate'];
export function greenChecks(checks){
  return Array.isArray(checks)&&REQUIRED_CHECKS.every(name=>checks.some(c=>c.name===name&&c.status==='completed'&&c.conclusion==='success'))&&checks.every(c=>c.status==='completed'&&c.conclusion==='success');
}
export function successfulMainRun(runs,sha){
  if(!Array.isArray(runs))return false;
  const latest=runs.find(r=>r.head_sha===sha&&r.event==='push'&&r.head_branch==='main');
  return latest?.status==='completed'&&latest?.conclusion==='success';
}
const publicRequests=[];let publicPauseUntil=0;
export async function github(path,fetchImpl=fetch){
  if(fetchImpl===fetch){
    const now=Date.now();while(publicRequests.length&&publicRequests[0]<now-3600000)publicRequests.shift();
    if(now<publicPauseUntil||publicRequests.length>=50)throw new Error('github_rate_limited');
    publicRequests.push(now);
  }
  const r=await fetchImpl('https://api.github.com/'+path,{redirect:'error',headers:{Accept:'application/vnd.github+json','User-Agent':'fios-delivery','X-GitHub-Api-Version':'2022-11-28'},signal:AbortSignal.timeout(30000)});
  if(!r.ok){
    if(fetchImpl===fetch&&(r.status===403||r.status===429))publicPauseUntil=Math.max(Date.now()+360000,Number(r.headers.get('x-ratelimit-reset')||0)*1000);
    await r.body?.cancel().catch(()=>{});throw new Error('github_unavailable');
  }
  const reader=r.body.getReader();const chunks=[];let size=0;
  try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>3*1024*1024)throw new Error('github_response_limit');chunks.push(value);}}finally{await reader.cancel().catch(()=>{});}
  try{return JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{throw new Error('github_invalid_response');}
}
export async function execute(program,args,{cwd,env=process.env,timeout=20*60*1000}={}){
  return new Promise((resolveResult,reject)=>{
    const child=spawn(program,args,{cwd,env,stdio:['ignore','pipe','pipe'],shell:false});let output='',size=0;
    const timer=setTimeout(()=>{child.kill('SIGKILL');reject(new Error('command_timeout'));},timeout);
    child.stdout.on('data',chunk=>{size+=chunk.length;if(size<=1024*1024)output+=chunk;});
    child.stderr.resume(); // Never forward commands' raw errors/configuration/credentials.
    child.on('error',()=>{clearTimeout(timer);reject(new Error('command_failed'));});
    child.on('close',code=>{clearTimeout(timer);code===0?resolveResult(output.trim()):reject(new Error('command_failed'));});
  });
}
export async function runLocked(script,args,state){
  mkdirSync(state,{recursive:true,mode:0o700});
  return new Promise(resolveResult=>{
    const child=spawn('flock',['--no-fork','--nonblock','--conflict-exit-code','75',join(state,'deploy.lock'),process.execPath,script,...args,'--lock-held'],{stdio:['ignore','inherit','inherit'],shell:false});
    const term=()=>child.kill('SIGTERM'),interrupt=()=>child.kill('SIGINT');
    process.on('SIGTERM',term);process.on('SIGINT',interrupt);
    const cleanup=()=>{process.off('SIGTERM',term);process.off('SIGINT',interrupt);};
    child.on('error',()=>{cleanup();resolveResult(1);});child.on('close',code=>{cleanup();resolveResult(code??1);});
  });
}
const backupCode=`const fs=require('node:fs');const path=require('node:path');const root='/app/data';const name=process.argv[1];if(!/^before-[a-f0-9-]+$/.test(name))throw new Error('invalid_backup');const dest=path.join(root,'backups',name);fs.mkdirSync(dest,{recursive:true,mode:0o700});for(const f of fs.readdirSync(root)){if(f!=='backups')fs.cpSync(path.join(root,f),path.join(dest,f),{recursive:true,errorOnExist:true,force:false});}fs.writeFileSync(path.join(dest,'complete'),'stopped-volume snapshot\\n',{mode:0o600});`;
const verifyCode=`const origin='http://127.0.0.1:3000';const health=await fetch(origin+'/health');if(!health.ok)throw new Error('health_failed');const login=await fetch(origin+'/api/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password:process.env.FIOS_PASSWORD})});if(!login.ok)throw new Error('login_failed');const cookie=login.headers.get('set-cookie')?.split(';')[0];if(!cookie)throw new Error('session_failed');const response=await fetch(origin+'/api/models',{headers:{Cookie:cookie}});if(!response.ok)throw new Error('discovery_failed');const data=await response.json();if(!Array.isArray(data.models)||!data.models.length)throw new Error('empty_catalog');if(data.hosts&&(!data.hosts.some(h=>h.name==='gateway'&&h.status==='available')||!data.models.some(m=>m.availability==='available')))throw new Error('gateway_unavailable');console.log('Authenticated non-inference discovery verified: '+data.models.length+' models');`;

// Pure transaction boundary retained for unit tests and actual isolated Docker rehearsals.
export async function deployRelease({image,service='fios',run,compose,stamp=Date.now().toString(16),beforeStop=async()=>{},publish=async()=>{}}){
  const container=await compose(image,['ps','-q',service]);
  if(!/^[a-f0-9]{12,64}$/.test(container))throw new Error('existing_application_required');
  const previous=await run(['inspect','--format','{{.Image}}',container]);
  if(!/^sha256:[a-f0-9]{64}$/.test(previous))throw new Error('invalid_previous_image');
  const volume=await run(['inspect','--format','{{range .Mounts}}{{if eq .Destination "/app/data"}}{{.Name}}{{end}}{{end}}',container]);
  if(!/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(volume))throw new Error('named_data_volume_required');
  const rollback='fios:rollback-'+stamp,backup='before-'+stamp;
  await run(['tag',previous,rollback]);await beforeStop();let stopped=false;
  try{
    stopped=true;await compose(image,['stop','-t','12',service]);
    const backupContainer='fios-backup-'+stamp;
    try{await run(['run','--rm','--name',backupContainer,'--network','none','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges','--user','1000:1000','--mount',`type=volume,source=${volume},target=/app/data`,'--entrypoint','node',rollback,'-e',backupCode,backup]);}
    finally{await run(['rm','--force',backupContainer]).catch(()=>{});}
    // Supporting services are intentionally stable during the SQLite-critical app transaction.
    await compose(image,['up','-d','--no-deps','--no-build','--pull','never','--wait','--wait-timeout','120',service]);
    const verification=await compose(image,['exec','-T',service,'node','--input-type=module','-e',verifyCode]);
    await compose(image,['exec','-T',service,'/opt/venv/bin/python','-I','-B','-c',"import asyncio;from fios_agent.worker import Settings;from fios_agent.availability import discover;r=asyncio.run(discover(Settings.from_environment()));assert any(m['availability']=='available' for m in r['models']);print('Python harness non-inference discovery verified')"]);
    await publish();return {image,previousImage:rollback,backup:`${volume}/backups/${backup}`,verification};
  }catch{
    if(stopped){try{
      await compose(rollback,['stop','-t','12',service]);
      await compose(rollback,['up','-d','--no-deps','--no-build','--pull','never','--wait','--wait-timeout','120',service]);
      await compose(rollback,['exec','-T',service,'node','--input-type=module','-e',verifyCode]);
    }catch{throw new Error('deployment_and_rollback_failed');}}
    throw new Error('deployment_failed_previous_image_restored');
  }
}
function atomicJson(path,value){writeFileSync(path+'.tmp',JSON.stringify(value)+'\n',{mode:0o600});renameSync(path+'.tmp',path);}
function record(value){console.log(JSON.stringify({phase:'deploy',time:new Date().toISOString(),...value}));}
export async function poll({repo,state,repository='mcteer/fios',api=github}){
  if(process.platform!=='linux')throw new Error('container_required');
  mkdirSync(state,{recursive:true,mode:0o700});const stateFile=join(state,'state.json');let stored={},sha;
  try{
    stored=existsSync(stateFile)?JSON.parse(readFileSync(stateFile,'utf8')):{};
    const main=async()=>(await api(`repos/${repository}/commits/main`)).sha;
    const checksFor=async revision=>(await api(`repos/${repository}/commits/${revision}/check-runs?filter=latest&per_page=100`)).check_runs;
    sha=await main();if(!/^[a-f0-9]{40}$/.test(sha))throw new Error('invalid_revision');
    if(stored.deployedSha===sha||stored.failedSha===sha)return {status:'unchanged',sha};
    const {workflow_runs:runs}=await api(`repos/${repository}/actions/workflows/ci.yml/runs?branch=main&event=push&head_sha=${sha}&per_page=10`);
    if(!successfulMainRun(runs,sha)||!greenChecks(await checksFor(sha)))return {status:'waiting_for_ci',sha};
    await execute('git',['fetch','--no-tags','origin','main'],{cwd:repo,timeout:60000});
    if(await execute('git',['rev-parse','refs/remotes/origin/main'],{cwd:repo})!==sha)return {status:'superseded',sha};
    const release=join(state,'releases',sha);
    if(!existsSync(join(release,'.snapshot-complete'))){
      rmSync(release,{recursive:true,force:true});mkdirSync(release,{recursive:true,mode:0o700});const archive=join(state,sha+'.tar');
      await execute('git',['archive','--format=tar','--output',archive,sha],{cwd:repo});await execute('tar',['-xf',archive,'-C',release]);rmSync(archive);writeFileSync(join(release,'.snapshot-complete'),'ok\n',{mode:0o600});
    }
    const envFile=join(state,'empty.env');writeFileSync(envFile,'',{mode:0o600});
    const run=args=>execute('docker',args,{cwd:release});const image='fios:'+sha;
    const compose=(selected,args)=>execute('docker',['compose','--env-file',envFile,'--project-name','fios','--file',join(release,'compose.yaml'),...args],{cwd:release,env:{...process.env,FIOS_IMAGE:selected}});
    await compose(image,['config','--quiet']);await run(['build','--label','org.opencontainers.image.revision='+sha,'--tag',image,release]);
    const result=await deployRelease({image,run,compose,beforeStop:async()=>{
      if(await main()!==sha)throw new Error('superseded');
      const latest=await api(`repos/${repository}/actions/workflows/ci.yml/runs?branch=main&event=push&head_sha=${sha}&per_page=10`);
      if(!successfulMainRun(latest.workflow_runs,sha)||!greenChecks(await checksFor(sha)))throw new Error('ci_not_green');
    },publish:async()=>{
      const deployed=await compose(image,['ps','-q','fios']);const revision=await run(['inspect','--format','{{index .Config.Labels "org.opencontainers.image.revision"}}',deployed]);
      if(revision!==sha)throw new Error('deployed_revision_mismatch');await run(['tag',image,'fios:current']);
    }});
    atomicJson(stateFile,{...stored,deployedSha:sha,failedSha:null,lastError:null,deployedAt:new Date().toISOString(),...result});record({status:'deployed',sha,backup:result.backup});return {status:'deployed',sha};
  }catch(error){
    const code=['deployment_failed_previous_image_restored','deployment_and_rollback_failed'].includes(error.message)?error.message:'deployment_blocked';
    if(sha)atomicJson(stateFile,{...stored,...(code!=='deployment_blocked'?{failedSha:sha}:{}),lastError:code,failedAt:new Date().toISOString()});record({status:code,sha});throw new Error(code);
  }
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  const args=process.argv.slice(2),state='/state',repo=join(state,'repo');
  if(process.platform!=='linux'||!existsSync('/.dockerenv')||!existsSync('/var/run/docker.sock')){console.error('Delivery must run in its dedicated Fios Compose management container.');process.exitCode=1;}
  else if(!args.includes('--lock-held')){const code=await runLocked(fileURLToPath(import.meta.url),args,state);if(code===75)record({status:'busy'});else process.exitCode=code;}
  else{
    let stopping=false;const sleeper=new AbortController();const stop=()=>{stopping=true;sleeper.abort();};process.on('SIGTERM',stop);process.on('SIGINT',stop);
    try{
      mkdirSync(repo,{recursive:true,mode:0o700});
      if(!existsSync(join(repo,'.git'))){await execute('git',['init',repo]);await execute('git',['-C',repo,'remote','add','origin','https://github.com/mcteer/fios.git']);}
      do{
        try{record(await poll({repo,state}));}catch{ /* poll records a fixed safe code; retry only on the next scheduled cycle. */ }
        writeFileSync(join(state,'heartbeat'),String(Date.now()),{mode:0o600});
        if(args.includes('--once')||stopping)break;
        // 20 idle requests/hour; github() caps active traffic at 50/hour and honors server rate-limit resets.
        await delay(180000,undefined,{signal:sleeper.signal}).catch(()=>{});
      }while(!stopping);
    }catch{record({status:'controller_startup_failed'});process.exitCode=1;}
  }
}
