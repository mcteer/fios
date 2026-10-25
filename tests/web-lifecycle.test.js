import test from 'node:test';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {agentApp} from './agent-support.js';
test('disconnect during search closes the run without a model continuation',async()=>{
 const app=await agentApp({python:fileURLToPath(new URL('./fixtures/web-python',import.meta.url))});
 try{
  const chat=await app.chat();const response=await app.send(chat.id,'Python release web evidence slow');
  const reader=response.body.getReader();let text='';
  while(!text.includes('"phase":"searching"')){const next=await reader.read();assert.equal(next.done,false);text+=new TextDecoder().decode(next.value);}
  await reader.cancel();
  const start=Date.now();let detail;
  do{detail=await(await app.request('/api/chats/'+chat.id)).json();if(!detail.generating)break;await new Promise(r=>setTimeout(r,20));}while(Date.now()-start<2000);
  assert.equal(detail.generating,false);assert.equal(app.mock.requests.length,1);
  assert.equal(detail.messages.at(-1).status,'interrupted');
 }finally{await app.close();}
});
test('Stop during real installed Agent retrieval cancels work and forbids continuation',async()=>{
 const app=await agentApp({python:fileURLToPath(new URL('./fixtures/web-python',import.meta.url))});
 try{
  const chat=await app.chat();
  const response=await app.send(chat.id,'Python release web evidence slow');
  assert.equal(response.status,200);
  const reader=response.body.getReader();let text='';
  while(!text.includes('"phase":"searching"')){
   const next=await reader.read();assert.equal(next.done,false);text+=new TextDecoder().decode(next.value);
  }
  const start=Date.now();
  assert.equal((await app.request('/api/chats/'+chat.id+'/stop',{method:'POST'})).status,200);
  for(;;){const next=await reader.read();if(next.done)break;text+=new TextDecoder().decode(next.value);}
  assert.ok(Date.now()-start<2000,'controlled cancellation must finish within2s');
  assert.equal(app.mock.requests.length,1,'no tool-result model dispatch after Stop');
  const detail=await(await app.request('/api/chats/'+chat.id)).json();
  assert.equal(detail.messages.at(-1).status,'interrupted');
  assert.equal(detail.messages.at(-1).web.outcome,'cancelled');
  assert.equal(detail.messages.at(-1).web.evidence_state,'none');
  assert.equal(detail.generating,false);
 }finally{await app.close();}
});
