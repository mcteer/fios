// Explicit acceptance driver only; all retrieval remains in installed Python.
import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {sseEvents} from '../src/stream.js';
const root=fileURLToPath(new URL('../',import.meta.url));
const args=process.argv.slice(2);
const query='Python 3.11 release notes';
async function command(program,argv,{capture=false,env=process.env}={}){
 return new Promise((resolve,reject)=>{
  const p=spawn(program,argv,{cwd:root,env,stdio:['ignore','pipe','pipe'],shell:false});
  let output='',bytes=0;
  const timer=setTimeout(()=>{p.kill('SIGKILL');reject(new Error('Acceptance command timed out.'));},180000);
  p.stdout.on('data',b=>{bytes+=b.length;if(capture&&bytes<=65536)output+=b;});
  p.stderr.resume();
  p.on('error',()=>{clearTimeout(timer);reject(new Error('Acceptance command failed.'));});
  p.on('close',code=>{clearTimeout(timer);code===0?resolve(output):reject(new Error('Acceptance command failed; no raw provider output logged.'));});
 });
}
async function provider(){
 const requested=args.indexOf('--query');
 if(requested>=0&&args[requested+1]!==query)throw new Error('Provider acceptance permits only the fixed nonsensitive query.');
 if(args.some((a,i)=>!['--provider-only','--query',query].includes(a)))throw new Error('Unknown acceptance argument.');
 const id=randomUUID().slice(0,12),image='fios-web-accept:'+id,project='fios-search-accept-'+id;
 const env={...process.env,FIOS_PASSWORD:'isolated-acceptance-only',SESSION_SECRET:'isolated-acceptance-only',FIOS_SEARXNG_IMAGE:'fios-searxng-accept:'+id};
 const compose=(...a)=>command('docker',['compose','--env-file','/dev/null','-p',project,'-f','compose.yaml',...a],{env});
 try{
  await command('docker',['build','-t',image,'.']);
  await compose('build','searxng');
  await compose('up','-d','--no-deps','--no-build','--wait','--wait-timeout','60','searxng');
  const code=`import asyncio,json\nfrom fios_agent.web.http import PublicHTTP\nfrom fios_agent.web.searxng import search\nasync def main():\n h=PublicHTTP()\n try:\n  r=await search(${JSON.stringify(query)},http=h)\n  print(json.dumps({'outcome':r.outcome,'sources':len(r.sources),'pages':sum(s.kind=='page' for s in r.sources),'http_attempts':h.attempts,'gateway_status':getattr(h,'gateway_status',None),'gateway_results':getattr(h,'gateway_results',None),'gateway_failed_engines':getattr(h,'gateway_failed_engines',None),'valid_rows':getattr(h,'gateway_valid_rows',None),'valid_urls':getattr(h,'gateway_valid_urls',None)}))\n finally: await h.aclose()\nasyncio.run(main())`;
  const raw=await command('docker',['run','--rm','--init','--network',project+'_search-egress','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges',
   '--user','1000:1000','--memory','1g','--cpus','2','--tmpfs','/tmp:size=64m,mode=1777',
   '--entrypoint','/opt/venv/bin/python',image,'-I','-B','-c',code],{capture:true});
  const data=JSON.parse(raw);
  if(!['retrieved','partial','snippets_only','empty','blocked','rate_limited','timeout','unavailable'].includes(data.outcome)||!Number.isInteger(data.sources)||!Number.isInteger(data.pages)||!Number.isInteger(data.http_attempts))throw new Error('Invalid acceptance result.');
  console.log(JSON.stringify({mode:'provider-only',...data}));
  if(!['retrieved','partial','snippets_only'].includes(data.outcome))process.exitCode=1;
 }finally{
  await compose('down','--remove-orphans').catch(()=>{});
  await command('docker',['image','rm',image,env.FIOS_SEARXNG_IMAGE]).catch(()=>{});
 }
}
async function model(){
 if(args.length!==2||args[0]!=='--model'||!args[1])throw new Error('Use --model EXACT_ADVERTISED_MODEL_ID only after explicit inference authorization.');
 // This path is intentionally opt-in and never called by CI/health checks.
 process.loadEnvFile?.(fileURLToPath(new URL('../.env',import.meta.url)));
 const origin='http://127.0.0.1:3000';let cookie='',chat;
 async function request(path,options={}){
  const r=await fetch(origin+path,{...options,redirect:'error',signal:AbortSignal.timeout(200000),headers:{Cookie:cookie,Origin:origin,...options.headers}});
  if(!r.ok)throw new Error('Authenticated acceptance request failed.');
  return r;
 }
 try{
  const login=await request('/api/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password:process.env.FIOS_PASSWORD})});
  cookie=login.headers.get('set-cookie')?.split(';')[0]||'';
  const catalog=await(await request('/api/models')).json();
  if(!catalog.models.some(m=>m.id===args[1]&&m.availability==='available'))throw new Error('Exact authorized model unavailable.');
  chat=await(await request('/api/chats',{method:'POST'})).json();
  const body=new FormData();body.set('model',args[1]);body.set('content','Find the official Python 3.11 release notes on the web and summarize one change with a source.');
  const stream=await request('/api/chats/'+chat.id+'/messages',{method:'POST',body});
  let complete=false;
  for await(const {event,data}of sseEvents(stream.body))if(event==='done')complete=data.status==='complete';
  const detail=await(await request('/api/chats/'+chat.id)).json();
  const answer=detail.messages.at(-1);
  const verified=complete&&answer?.web?.evidence_state==='sent_to_model'&&answer.web.sources.length>0;
  console.log(JSON.stringify({mode:'authorized-model',model:args[1],complete,
   outcome:answer?.web?.outcome??'unverified',sources:answer?.web?.sources?.length??0,tool_cycle_observed:verified,
   semantic_grounding:'requires source/answer review; tool delivery alone is not semantic verification'}));
  if(!verified)process.exitCode=1;
 }finally{if(chat)await request('/api/chats/'+chat.id,{method:'DELETE'});}
}
try{if(args[0]==='--provider-only')await provider();else if(args[0]==='--model')await model();else throw new Error('Choose --provider-only or explicitly authorized --model EXACT_ID.');}
catch{console.error('Web-search acceptance did not pass. No retry, alternate provider or model substitution performed.');process.exitCode=1;}
