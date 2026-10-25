// Native read-only probes, shared as bounded expiring metadata; no listener, tools or inference.
import {readFileSync,mkdirSync,writeFileSync,renameSync,chmodSync} from 'node:fs';
import {join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {parseEnv} from 'node:util';
import {setTimeout as delay} from 'node:timers/promises';
import {discover,peerConfiguration} from '../src/agent/availability.js';

export function writeSnapshot(output,frame){
  mkdirSync(output,{recursive:true,mode:0o755});
  chmodSync(output,0o755);
  let content=JSON.stringify(frame)+'\n';
  if(Buffer.byteLength(content)>1024*1024)content=JSON.stringify({v:1,peers:frame.peers.map(p=>({name:p.name,endpointHash:p.endpointHash,checkedAt:Date.now(),status:'unknown',reason:'invalid_catalog',models:[]}))})+'\n';
  const temp=join(output,'peers.json.tmp');
  writeFileSync(temp,content,{mode:0o644});
  chmodSync(temp,0o644); // No secrets in this file; container has a read-only bind of this directory only.
  renameSync(temp,join(output,'peers.json'));
}
export async function observe({repo,output}){
  try{
    const env=parseEnv(readFileSync(join(repo,'.env'),'utf8'));
    const base=new URL(env.MLX_BASE_URL||'http://127.0.0.1:11234/v1');
    if(base.hostname==='host.docker.internal')base.hostname='127.0.0.1';
    const result=await discover({base:base.href,key:env.MLX_API_KEY||'',peers:peerConfiguration(env.MLX_PEER_URLS),snapshotFile:null,includeObservations:true});
    const frame={v:1,peers:result.peerObservations};
    writeSnapshot(output,frame);
    return frame;
  }catch{
    writeSnapshot(output,{v:1,peers:[]});
    throw new Error('host_observation_failed');
  }
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)){
  const args=process.argv.slice(2);
  const option=(name,fallback)=>{const i=args.indexOf(name);return i<0?fallback:args[i+1];};
  const repo=resolve(option('--repo',fileURLToPath(new URL('../',import.meta.url))));
  const output=resolve(option('--output',join(repo,'data','readiness')));
  let stopping=false,last='';
  process.on('SIGTERM',()=>{stopping=true;});
  process.on('SIGINT',()=>{stopping=true;});
  do{
    try{
      const frame=await observe({repo,output});
      const signature=JSON.stringify(frame.peers.map(p=>[p.name,p.status,p.models.map(m=>[m.id,m.loaded])]));
      if(signature!==last){console.log(JSON.stringify({phase:'readiness_observer',status:'updated',hosts:frame.peers.length}));last=signature;}
    }catch{if(last!=='error'){console.error(JSON.stringify({phase:'readiness_observer',status:'host_observation_failed'}));last='error';}}
    if(args.includes('--once'))break;
    if(!stopping)await delay(500);
  }while(!stopping);
  if(stopping)writeSnapshot(output,{v:1,peers:[]});
}
