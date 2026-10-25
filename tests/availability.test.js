import test from 'node:test';
import assert from 'node:assert/strict';
import {discover, peerConfiguration} from '../src/agent/availability.js';
import {readFileSync} from 'node:fs';

test('shared availability contract fixtures match Node observations', async () => {
  const fixtures=JSON.parse(readFileSync(new URL('./fixtures/availability.json',import.meta.url),'utf8'));
  for(const fixture of fixtures){
    const result=await discover({base:'http://gateway/v1',peers:Object.fromEntries(Object.keys(fixture.peers).map(p=>[p,`http://${p}/v1`])),fetchImpl:async url=>{
      const u=new URL(url);
      return Response.json(u.pathname==='/health'?{status:'ok'}:{data:u.hostname==='gateway'?fixture.gateway:fixture.peers[u.hostname]});
    }});
    assert.deepEqual(result.models.map(m=>[m.availability,m.reason,m.loaded]),fixture.expected,fixture.name);
  }
});

test('host readiness is independent of stale gateway listings; recovery is exact and credentials isolated', async () => {
  let mode = 'down';
  const calls = [];
  const fetchImpl = async (url, options) => {
    calls.push({url, options});
    const u = new URL(url);
    if (u.hostname === 'gateway') {
      assert.equal(options.headers.Authorization, 'Bearer PRIVATE_TEST_KEY');
      return Response.json(u.pathname === '/health' ? {status:'ok'} : {data:[
        {id:'org/local',loaded:false,capabilities:['chat']},
        {id:'org/model@studio-a',lan_peer:'studio-a',capabilities:['chat']}],
        lan_peers:[{name:'evil',url:'http://169.254.169.254'}]});
    }
    assert.equal(u.hostname, 'studio');
    assert.equal(options.headers.Authorization, undefined);
    if (mode === 'down') throw new Error('private provider body');
    if (mode === 'unauthorized') return new Response('', {status:401});
    return Response.json(u.pathname === '/health' ? {status:'ok'} : {data:mode === 'missing' ? [] : [{id:'org/model',loaded:false}]});
  };
  for (const [value, status, reason] of [['down','unavailable','host_down'],['missing','unavailable','not_advertised'],['unauthorized','unknown','unauthorized'],['up','available','ok']]) {
    mode = value;
    const result = await discover({base:'http://gateway/v1',key:'PRIVATE_TEST_KEY',peers:{'studio-a':'http://studio/v1'},fetchImpl});
    assert.equal(result.models[0].availability,'available');
    assert.equal(result.models[0].loaded,false);
    assert.equal(result.models[1].availability,status);
    assert.equal(result.models[1].reason,reason);
    assert.ok(!JSON.stringify(result).includes('PRIVATE_TEST_KEY'));
  }
  assert.equal(calls.length,16);
  assert.ok(calls.every(c=>c.options.redirect==='error'));
});

test('unknown peers, malformed/oversized catalogs, auth and probe timeouts fail closed', async () => {
  const base='http://gateway/v1';
  const goodHealth = url => url.endsWith('/health');
  let result=await discover({base,fetchImpl:async url=>Response.json(goodHealth(url)?{status:'ok'}:{data:[{id:'m@unknown',lan_peer:'unknown'}]})});
  assert.equal(result.models[0].availability,'unknown');
  for(const payload of [{data:[{id:'m',loaded:'false'}]}, {data:[{id:'m'},{id:'m'}]}, {data:'bad'}, {data:[],padding:'x'.repeat(1024*1024)}]){
    result=await discover({base,fetchImpl:async url=>Response.json(goodHealth(url)?{status:'ok'}:payload)});
    assert.equal(result.hosts[0].status,'unknown');
    assert.equal(result.models.length,0);
  }
  const start=Date.now();
  result=await discover({base,timeoutMs:30,fetchImpl:async (url,{signal})=>new Promise((resolve,reject)=>signal.addEventListener('abort',()=>reject(new Error('timeout')),{once:true}))});
  assert.equal(result.hosts[0].status,'unavailable');
  assert.ok(Date.now()-start<500);
  for(const value of ['[]','{"p":"http://user:secret@host/v1"}','{"p":"http://host/v1?x=1"}','{"gateway":"http://host/v1"}']) assert.throws(()=>peerConfiguration(value));
});
