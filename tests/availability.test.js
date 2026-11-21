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

test('an advertised Bonjour alias uses only its exact configured Studio endpoint', async () => {
  const base='http://gateway/v1',studio='http://fios-edge-b.local:11234/v1';
  const advertised={id:'org/model@Mac.home',lan_peer:'Mac.home',capabilities:['chat']};
  const legacy={id:'org/model@fios-edge-b.lab',lan_peer:'fios-edge-b.lab',capabilities:['chat']};
  let up=true;
  const fetchImpl=async (url,{headers})=>{
    const target=new URL(url),isGateway=target.hostname==='gateway';
    assert.equal(target.hostname,isGateway?'gateway':'fios-edge-b.local');
    assert.equal(headers.Authorization,isGateway?'Bearer MOCK_GATEWAY_KEY':undefined);
    if(!isGateway&&!up) throw new Error('offline');
    return Response.json(target.pathname==='/health'?{status:'ok'}:{data:isGateway?[advertised,legacy]:[{id:'org/model',capabilities:['chat']}]});
  };
  const peers={'fios-edge-b':studio};
  const options={base,key:'MOCK_GATEWAY_KEY',fetchImpl};
  const unmapped=await discover({...options,peers});
  assert.deepEqual(unmapped.models.map(m=>[m.id,m.reason]),[[advertised.id,'host_unverified'],[legacy.id,'host_unverified']]);
  const mapped={...peers,'Mac.home':studio};
  const recovered=await discover({...options,peers:mapped});
  assert.deepEqual(recovered.models.map(m=>[m.id,m.availability]),[[advertised.id,'available'],[legacy.id,'unknown']]);
  up=false;
  const unavailable=await discover({...options,peers:mapped});
  assert.deepEqual(unavailable.models.map(m=>[m.id,m.reason]),[[advertised.id,'host_down'],[legacy.id,'host_unverified']]);
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
