import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,writeFileSync,readFileSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {observe} from '../scripts/observe-hosts.mjs';
import {discover} from '../src/agent/availability.js';
import {mockMlx} from './mock-mlx.js';

test('container observer shares fresh endpoint-bound metadata; offline, expired, tampered and missing observations fail closed',async()=>{
  const gateway=await mockMlx(),peer=await mockMlx();
  gateway.addPeer();
  const root=mkdtempSync(join(tmpdir(),'fios-observer-'));
  const output=join(root,'metadata'),file=join(output,'peers.json');
  writeFileSync(join(root,'.env'),`MLX_BASE_URL=${gateway.url}\nMLX_PEER_URLS=${JSON.stringify({'studio-a':peer.url})}\n`,{mode:0o600});
  const options={base:gateway.url,peers:{'studio-a':peer.url},snapshotFile:file,fetchImpl:async(url,opts)=>{
    assert.ok(!url.startsWith(peer.url),'container must not need direct access to Studio addresses');
    return fetch(url,opts);
  }};
  try{
    await observe({output,env:{MLX_BASE_URL:gateway.url,MLX_PEER_URLS:JSON.stringify({'studio-a':peer.url})}});
    let result=await discover(options);
    assert.equal(result.models.find(m=>m.peer).availability,'available');
    assert.equal(gateway.requests.length+peer.requests.length,0);
    const fresh=JSON.parse(readFileSync(file,'utf8'));
    assert.ok(!JSON.stringify(fresh).includes(peer.url));
    for(const mutate of [v=>{v.peers[0].checkedAt=Date.now()-5001;},v=>{v.peers[0].checkedAt=Date.now()+10000;},v=>{v.peers[0].endpointHash='0'.repeat(64);},v=>{v.peers[0].status='invented';}]){
      const changed=structuredClone(fresh);mutate(changed);writeFileSync(file,JSON.stringify(changed));
      result=await discover(options);assert.equal(result.models.find(m=>m.peer).availability,'unknown');
    }
    peer.health.status=503;
    await observe({repo:root,output});
    result=await discover(options);assert.equal(result.models.find(m=>m.peer).availability,'unavailable');
    peer.health.status=200;
    await observe({repo:root,output});
    result=await discover(options);assert.equal(result.models.find(m=>m.peer).availability,'available');
    rmSync(file);
    result=await discover(options);assert.equal(result.models.find(m=>m.peer).availability,'unknown');
  }finally{
    for(const mock of [gateway,peer]){mock.server.closeAllConnections();await new Promise(r=>mock.server.close(r));}
    rmSync(root,{recursive:true,force:true});
  }
});

test('shared observer timestamps reject any future millisecond without probing peers',async t=>{
  const now=1_794_700_000_000;
  t.mock.method(Date,'now',()=>now);
  const root=mkdtempSync(join(tmpdir(),'fios-observer-clock-'));
  t.after(()=>rmSync(root,{recursive:true,force:true}));
  const file=join(root,'peers.json');
  const {endpointHash}=await import('../src/agent/availability.js');
  const calls=[];
  for(const offset of [0,-5000,1,500,1000,1001,-5001]){
    writeFileSync(file,JSON.stringify({v:1,peers:[{name:'p',endpointHash:endpointHash('http://studio/v1'),
      checkedAt:now+offset,status:'available',reason:'ok',models:[{id:'exact/model',loaded:false}]}]}));
    const result=await discover({base:'http://gateway/v1',peers:{p:'http://studio/v1'},snapshotFile:file,
      fetchImpl:async(url,options)=>{
        const target=new URL(url);calls.push(target.href);
        assert.equal(target.hostname,'gateway');
        assert.equal(options.headers.Authorization,undefined);
        return Response.json(target.pathname==='/health'?{status:'ok'}:{data:[{id:'exact/model@p',lan_peer:'p'}]});
      }});
    assert.equal(result.models[0].id,'exact/model@p');
    assert.equal(result.models[0].availability,offset<=0&&offset>=-5000?'available':'unknown',`offset ${offset}`);
    if(offset>0)assert.equal(result.models[0].reason,'host_unverified');
  }
  assert.equal(calls.length,14);
});
