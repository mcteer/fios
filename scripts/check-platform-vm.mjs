#!/usr/bin/env node
// Explicit disposable telemetry-source experiment, never production enrollment.
import {spawnSync} from 'node:child_process';
import {mkdtempSync,realpathSync,copyFileSync,chmodSync,rmSync} from 'node:fs';
import {homedir,tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
if(process.argv.length!==3||process.argv[2]!=='--isolated')throw Error('Usage: node scripts/check-platform-vm.mjs --isolated');
const directory=mkdtempSync(join(tmpdir(),'fios-vm-observation-')),nonce=randomUUID(),name='fios-vm-probe-'+nonce;
const socket='unix://'+join(homedir(),'.orbstack/run/docker.sock'),docker=join(directory,'docker');
const env={PATH:'/usr/bin:/bin',HOME:homedir(),LANG:'C',DOCKER_CONFIG:directory};
let id,image,createAttempted=false;
function run(program,args,timeout=5000){const result=spawnSync(program,args,{encoding:'utf8',timeout,maxBuffer:65536,env});if(result.status!==0)throw Error('Isolated VM observation failed; no telemetry accepted');return result.stdout.trim();}
const runtime=args=>run(docker,['--host',socket,...args]);
try{
  const found=spawnSync('/usr/bin/which',['docker'],{encoding:'utf8',timeout:2000});if(found.status!==0)throw Error('Existing local runtime CLI required');
  copyFileSync(realpathSync(found.stdout.trim()),docker);chmodSync(docker,0o700);
  // Unlike Docker's multicall client, this native client requires its
  // canonical application location. Do not bypass that identity/layout check.
  const orbctl=realpathSync('/usr/local/bin/orbctl');
  const envelopeStarted=performance.now(),envelopeSampledAt=Date.now();
  const capText=run(orbctl,['config','get','memory_mib']);
  if(!/^[1-9][0-9]{0,7}$/.test(capText))throw Error('Unbounded or unknown VM cap');
  const capBytes=Number(capText)*1048576;
  function configuredMachines(){const value=JSON.parse(run(orbctl,['list','--format','json']));const list=Array.isArray(value)?value:value.machines;if(!Array.isArray(list))throw Error('Unknown native topology schema');return list.length;}
  const machinesBefore=configuredMachines();
  image=runtime(['image','inspect','fios:current','--format','{{.Id}}']);if(!/^sha256:[a-f0-9]{64}$/.test(image))throw Error('Existing immutable image required; no pulls');
  const code="import json,re; s=open('/proc/meminfo').read(16384); d={k:int(v) for k,v in re.findall(r'^(MemTotal|MemFree|MemAvailable):\\s+(\\d+) kB$',s,re.M)}; m=open('/proc/self/mountinfo').read(65536).splitlines(); d['kernel_procfs_view']=any(' /proc ' in x and ' - proc ' in x for x in m) and not any(len(x.split())>4 and x.split()[4]=='/proc/meminfo' for x in m); print(json.dumps(d))";
  createAttempted=true;
  id=runtime(['create','--pull=never','--name',name,'--label','lab.fios.telemetry-fixture='+nonce,'--network=none','--read-only','--user','65532:65532','--cap-drop=ALL','--security-opt','no-new-privileges','--memory','64m','--memory-swap','64m','--oom-score-adj','1000','--cpus','1','--pids-limit','8','--entrypoint','/opt/venv/bin/python',image,'-I','-S','-B','-c',code]);
  if(!/^[a-f0-9]{64}$/.test(id))throw Error('Uncertain fixture identity');
  const sampledAt=Date.now(),monotonicStart=performance.now();
  const data=JSON.parse(runtime(['start','--attach',id]));
  if(Object.keys(data).sort().join(',')!=='MemAvailable,MemFree,MemTotal,kernel_procfs_view'||data.kernel_procfs_view!==true||!['MemTotal','MemFree','MemAvailable'].every(k=>Number.isSafeInteger(data[k])&&data[k]>=0)||data.MemFree>data.MemTotal||data.MemAvailable>data.MemTotal||data.MemTotal<=65536)throw Error('Not a coherent global-kernel memory observation');
  const machinesAfter=configuredMachines();
  const age=performance.now()-monotonicStart;
  const envelopeAge=performance.now()-envelopeStarted;
  if(age>5000||envelopeAge>5000||Date.now()<envelopeSampledAt-1000)throw Error('VM observation stale or clock regressed; no capacity accepted');
  const occupiedBytes=(data.MemTotal-data.MemFree)*1024;
  // A nonempty machine inventory needs separate shared-kernel attestation.
  // Even the empty-inventory candidate is not production enrollment.
  const candidateRemaining=machinesBefore===0&&machinesAfter===0?Math.min(data.MemFree*1024,Math.max(0,capBytes-occupiedBytes)):null;
  console.log(JSON.stringify({source:'isolated_linux_proc_meminfo',sampled_at:envelopeSampledAt,kernel_sampled_at:sampledAt,age_ms:Math.ceil(envelopeAge),kernel_age_ms:Math.ceil(age),container_limit_mib:64,vm_total_kib:data.MemTotal,vm_free_kib:data.MemFree,vm_available_kib:data.MemAvailable,configured_cap_bytes:capBytes,configured_machines_before:machinesBefore,configured_machines_after:machinesAfter,candidate_remaining_bytes:candidateRemaining,container_scoped_total:false,kernel_procfs_view:data.kernel_procfs_view,production_enrollment:false}));
  console.log('PASS: fixed read-only probe observes VM kernel memory beyond its own cgroup; all-machine coverage/cap mapping still requires validation; no inference/persistent monitor');
}finally{
  try{
    if(createAttempted){
      // Inspect the immutable ID, or reconcile the generated name after an
      // uncertain create result. Never retry create or delete by name alone.
      const identity=runtime(['inspect','--format','{{.Id}} {{.Name}} {{.Image}} {{index .Config.Labels "lab.fios.telemetry-fixture"}}',id||name]).split(' ');
      const [fullID,actualName,actualImage,owned]=identity;
      if(identity.length!==4||!/^[a-f0-9]{64}$/.test(fullID)||actualName!=='/'+name||actualImage!==image||owned!==nonce||(id&&id!==fullID))throw Error('Foreign/uncertain runtime object; cleanup refused');
      runtime(['rm','--force',fullID]);
    }
  }finally{rmSync(directory,{recursive:true,force:true});}
}
