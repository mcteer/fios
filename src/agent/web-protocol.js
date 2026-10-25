// Pure validation only. No search orchestration or public-network requests.
export const REASONS = Object.freeze({pending:null,not_requested:'no_tool_call',disabled:'operator_disabled',
 privacy_skipped:'privacy_policy',retrieved:'page_evidence',partial:'partial_evidence',snippets_only:'snippet_evidence',
 empty:'no_results',blocked:'provider_blocked',rate_limited:'rate_limit',timeout:'tool_timeout',
 unavailable:'retrieval_unavailable',context_limit:'context_budget',cancelled:'run_cancelled',error:'tool_error'});
const evidence=new Set(['retrieved','partial','snippets_only']);
const fail=()=>{throw new Error('Invalid search metadata.');};
function fields(v,keys){if(!v||typeof v!=='object'||Array.isArray(v)||Object.keys(v).length!==keys.length||keys.some(k=>!Object.hasOwn(v,k)))fail();}
function text(v,max){if(typeof v!=='string'||!v.isWellFormed()||v.length>max)fail();}
function time(v){if(!Number.isSafeInteger(v)||v<0)fail();}
export function validateSearchInput(v){
 fields(v,['current_text','previous_text','current_has_attachments','previous_has_attachments','current_elided','previous_elided']);
 for(const prefix of ['current','previous']){
  if(v[prefix+'_text']!==null)text(v[prefix+'_text'],2000);
  for(const suffix of ['has_attachments','elided'])if(typeof v[prefix+'_'+suffix]!=='boolean')fail();
  if(v[prefix+'_elided']&&v[prefix+'_text']!==null)fail();
 }
 return v;
}
export function validateSearchStatus(v){
 fields(v,['phase','outcome','reason','tool_attempted']);
 if(!Object.hasOwn(REASONS,v.outcome)||v.reason!==REASONS[v.outcome]||typeof v.tool_attempted!=='boolean')fail();
 if(!['idle','searching','fetching','finished'].includes(v.phase)||(v.phase==='finished')===(v.outcome==='pending'))fail();
 if(['searching','fetching'].includes(v.phase)&&!v.tool_attempted)fail();
 if((v.phase==='idle'||['disabled','not_requested'].includes(v.outcome))&&v.tool_attempted)fail();
 if([...evidence,'empty','blocked','rate_limited','timeout','unavailable'].includes(v.outcome)&&!v.tool_attempted)fail();
 return v;
}
export function validateManifest(v){
 fields(v,['v','phase','outcome','reason','tool_attempted','evidence_state','retrieved_at','sources']);
 validateSearchStatus({phase:v.phase,outcome:v.outcome,reason:v.reason,tool_attempted:v.tool_attempted});
 if(v.v!==1||!['none','retrieved_only','sent_to_model'].includes(v.evidence_state)||!Array.isArray(v.sources)||v.sources.length>5)fail();
 if((v.evidence_state==='none')!==(v.sources.length===0)||evidence.has(v.outcome)!==(v.sources.length>0))fail();
 for(const [i,s]of v.sources.entries()){
  fields(s,['id','url','title','kind','retrieved_at','excerpt_sha256','excerpt_units','truncated']);
  if(s.id!==`S${i+1}`||!['page','snippet'].includes(s.kind))fail();
  text(s.url,2048);text(s.title,300);time(s.retrieved_at);
  const u=new URL(s.url);
  if(!['http:','https:'].includes(u.protocol)||u.username||u.password||u.hash||u.port||/[\x00-\x20\x7f\\]/.test(s.url))fail();
  if(typeof s.excerpt_sha256!=='string'||!(/^[0-9a-f]{64}$/).test(s.excerpt_sha256)||!Number.isInteger(s.excerpt_units)||s.excerpt_units<0||s.excerpt_units>3000||typeof s.truncated!=='boolean')fail();
 }
 const expected=v.sources.length?Math.max(...v.sources.map(s=>s.retrieved_at)):null;
 if(v.retrieved_at!==expected)fail();
 if(v.outcome==='retrieved'&&v.sources.some(s=>s.kind!=='page'))fail();
 if(v.outcome==='snippets_only'&&v.sources.some(s=>s.kind!=='snippet'))fail();
 if(v.outcome==='partial'&&!v.sources.some(s=>s.kind==='page'))fail();
 if(Buffer.byteLength(JSON.stringify(v))>65536)fail();
 return v;
}
export function initialManifest(){return {v:1,phase:'idle',outcome:'pending',reason:null,tool_attempted:false,evidence_state:'none',retrieved_at:null,sources:[]};}
export function validateTransition(a,b){
 validateManifest(a);validateManifest(b);
 if(JSON.stringify(a)===JSON.stringify(b)||(a.tool_attempted&&!b.tool_attempted))fail();
 if(a.phase==='finished'){
  if(a.evidence_state!=='retrieved_only'||JSON.stringify({...a,evidence_state:'sent_to_model'})!==JSON.stringify(b))fail();
 }else if(!['idle:searching','idle:finished','searching:fetching','searching:finished','fetching:finished'].includes(a.phase+':'+b.phase))fail();
 return b;
}
