import { readFileSync } from 'node:fs';
import { sseEvents } from '../src/stream.js';
const env = Object.fromEntries(readFileSync(new URL('../.env',import.meta.url),'utf8').split('\n').filter(l=>l&&!l.startsWith('#')).map(l=>{const i=l.indexOf('=');return [l.slice(0,i),l.slice(i+1)];}));
const origin = process.env.FIOS_URL || 'http://127.0.0.1:3000';
const login=await fetch(origin+'/api/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password:env.FIOS_PASSWORD})});
if(!login.ok)throw new Error('Authentication failed');
const cookie=login.headers.get('set-cookie').split(';')[0];
const request=(path,options={})=>fetch(origin+'/api'+path,{...options,headers:{Cookie:cookie,...options.headers}});
const catalog=await request('/models');
if(!catalog.ok)throw new Error(await catalog.text());
const {models}=await catalog.json();console.log('Authenticated gateway discovery passed: '+models.length+' chat models');
for(const m of models)console.log((m.loaded?'[loaded] ':'[on demand] ')+m.id);
const model=process.argv[2];
if(model){
  if(!models.some(m=>m.id===model))throw new Error('Model not in catalog');
  const chat=await(await request('/chats',{method:'POST'})).json();
  try{
    const form=new FormData();form.set('model',model);form.set('content','Read the attached file. Reply with only the value of workspace_name, no explanation.');
    form.append('files',new Blob(['workspace_name = "Fios connected"'],{type:'text/plain'}),'context.txt');
    const response=await request(`/chats/${chat.id}/messages`,{method:'POST',body:form});
    if(!response.ok)throw new Error(await response.text());
    let content='',done=false;
    for await(const {event,data} of sseEvents(response.body)){
      if(event==='delta')content+=data.content;
      if(event==='error')throw new Error(data.error);
      if(event==='done')done=data.status==='complete';
    }
    if(!done||!content.trim())throw new Error('Incomplete response');
    console.log('Streamed answer:',content.trim());
    if(!content.includes('Fios connected'))throw new Error('Attachment context was not reflected in answer');
    console.log('Authenticated attachment + streaming inference passed');
  }finally{
    const removal=await request('/chats/'+chat.id,{method:'DELETE'});
    if(!removal.ok)console.warn('Smoke chat cleanup failed; remove it in the UI.');
  }
}
