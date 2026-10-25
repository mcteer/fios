import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {REASONS,initialManifest,validateManifest,validateSearchStatus,validateSearchInput,validateTransition} from '../src/agent/web-protocol.js';
const fixture=JSON.parse(readFileSync(new URL('./fixtures/web/contracts.json',import.meta.url)));
test('search metadata matches shared strict contract fixture',()=>{
 assert.deepEqual(REASONS,fixture.status_reasons);
 assert.deepEqual(initialManifest(),fixture.initial);
 validateManifest(fixture.initial);
 for(const patch of [{v:true},{reason:'raw secret'},{retrieved_at:1},{sources:null},{extra:'bad'},{tool_attempted:0}])assert.throws(()=>validateManifest({...fixture.initial,...patch}));
});
test('status mappings are exhaustive and terminal pending is rejected',()=>{
 for(const [outcome,reason]of Object.entries(REASONS)){
  const attempted=['retrieved','partial','snippets_only','empty','blocked','rate_limited','timeout','unavailable'].includes(outcome);
  validateSearchStatus({phase:outcome==='pending'?'idle':'finished',outcome,reason,tool_attempted:attempted});
  assert.throws(()=>validateSearchStatus({phase:'finished',outcome,reason:'provider response',tool_attempted:attempted}));
 }
 assert.throws(()=>validateSearchStatus({phase:'finished',outcome:'pending',reason:null,tool_attempted:false}));
});
test('manifest delivery preserves exact sources and message scope',()=>{
 const source={id:'S1',url:'https://www.python.org/',title:'Python',kind:'page',retrieved_at:1234,
  excerpt_sha256:createHash('sha256').update('test').digest('hex'),excerpt_units:4,truncated:false};
 const a={v:1,phase:'finished',outcome:'retrieved',reason:'page_evidence',tool_attempted:true,evidence_state:'retrieved_only',retrieved_at:1234,sources:[source]};
 validateManifest(a);
 const b={...a,evidence_state:'sent_to_model'};
 validateTransition(a,b);
 assert.throws(()=>validateTransition(b,a));
 assert.throws(()=>validateTransition(a,{...b,sources:[{...source,title:'changed'}]}));
 for(const patch of [{retrieved_at:null},{sources:[]},{sources:[{...source,excerpt:'private'}]}, {sources:[{...source,url:'javascript:alert(1)'}]}])assert.throws(()=>validateManifest({...a,...patch}));
});
test('plain-user provenance is typed, bounded and cannot carry browser tools',()=>{
 const a={current_text:'Python',previous_text:null,current_has_attachments:false,previous_has_attachments:false,current_elided:false,previous_elided:false};
 validateSearchInput(a);
 for(const patch of [{current_text:'x'.repeat(2001)},{current_elided:true},{current_has_attachments:0},{query:'private'},{previous_text:undefined}])assert.throws(()=>validateSearchInput({...a,...patch}));
});
