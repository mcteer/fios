// Offline image/config/health test; no search queries or network access.
import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
const id=randomUUID().slice(0,12),image='fios-searxng-test:'+id,name='fios-searxng-test-'+id;
async function run(args){
 return new Promise((resolve,reject)=>{
  const p=spawn('docker',args,{stdio:['ignore','pipe','pipe'],shell:false});let out='';
  p.stdout.on('data',b=>{if(out.length<65536)out+=b;});p.stderr.resume();
  p.on('error',()=>reject(new Error('Offline SearXNG check failed.')));
  p.on('close',code=>code===0?resolve(out.trim()):reject(new Error('Offline SearXNG check failed.')));
 });
}
try{
 await run(['build','-f','Dockerfile.searxng','-t',image,'.']);
 await run(['run','-d','--name',name,'--network','none','--read-only','--user','977:977','--cap-drop','ALL','--security-opt','no-new-privileges','--memory','256m','--cpus','0.5','--log-driver','none','--tmpfs','/tmp:size=32m,mode=1777','--tmpfs','/etc/searxng:size=1m,uid=977,gid=977,mode=0700','--tmpfs','/var/cache/searxng:size=16m,uid=977,gid=977,mode=0700',image]);
 let healthy=false;
 for(let i=0;i<40;i++){
  try{await run(['exec',name,'/usr/local/searxng/.venv/bin/python','-c',"import urllib.request;assert urllib.request.urlopen('http://127.0.0.1:8080/healthz',timeout=2).status==200"]);healthy=true;break;}
  catch{await new Promise(r=>setTimeout(r,250));}
 }
 if(!healthy)throw new Error('SearXNG static health failed.');
 await run(['exec',name,'/usr/local/searxng/.venv/bin/python','-c',"from searx import settings;assert {e['name'] for e in settings['engines']}=={'bing','brave'};assert settings['outgoing']['retries']==0;assert settings['search']['formats']==['json'];assert settings['server']['image_proxy'] is False"]);
 console.log('Offline nonroot/read-only SearXNG image, explicit engines, JSON config and no-query health passed.');
}finally{
 await run(['rm','-f',name]).catch(()=>{});
 await run(['image','rm',image]).catch(()=>{});
}
