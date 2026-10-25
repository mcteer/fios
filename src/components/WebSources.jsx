import React from 'react';
const labels={pending:'Considering web search',not_requested:'No web search used',disabled:'Web search disabled',
 privacy_skipped:'Web search skipped for privacy',retrieved:'Public page evidence retrieved',partial:'Partial web evidence',
 snippets_only:'Search snippets only — pages not read',empty:'No web results',blocked:'Search provider blocked access',
 rate_limited:'Web search rate limited',timeout:'Web search timed out',unavailable:'Web evidence unavailable',
 context_limit:'Web evidence omitted: context limit',cancelled:'Web search interrupted',error:'Web search did not complete'};
export function safeSourceURL(value){
 try{const u=new URL(value);return ['http:','https:'].includes(u.protocol)&&!u.username&&!u.password&&!u.hash&&!u.port&&!/[\x00-\x20\x7f\\]/.test(value)?u.href:null;}catch{return null;}
}
export default function WebSources({web}){
 if(!web)return null;
 const active=web.phase==='searching'||web.phase==='fetching';
 return <section className="web-sources" aria-label="Web evidence">
  <p aria-live="polite" role="status">{active?(web.phase==='searching'?'Searching DuckDuckGo…':'Reading public sources…'):labels[web.outcome]||'Web evidence unavailable'}</p>
  {!!web.sources?.length&&<details><summary>Sources ({web.sources.length}) · {web.evidence_state==='sent_to_model'?'Supplied to model':'Retrieved only — not supplied'}</summary>
   <p className="muted">Sources are untrusted evidence, not independent factual verification.</p>
   <ol>{web.sources.map(source=>{const href=safeSourceURL(source.url);return <li key={source.id}>
    {href?<a href={href} target="_blank" rel="noopener noreferrer" referrerPolicy="no-referrer">{source.id} · {source.title||new URL(href).hostname}</a>:<span>Invalid source link</span>}
    <small>{href&&new URL(href).hostname} · {source.kind==='page'?'Page':'Search snippet'} · Retrieved {new Date(source.retrieved_at).toLocaleString()}</small>
   </li>;})}</ol>
  </details>}
 </section>;
}
export function citationPlugin(web){
 return ()=>tree=>{
  if(web?.evidence_state!=='sent_to_model')return;
  const sources=new Map(web.sources.map(s=>[s.id,safeSourceURL(s.url)]));
  function walk(node){
   if(['code','inlineCode','link','html'].includes(node.type)||!node.children)return;
   node.children=node.children.flatMap(child=>{
    if(child.type!=='text'){walk(child);return [child];}
    const nodes=[];let start=0;
    for(const match of child.value.matchAll(/\[(S[1-5])\]/g)){
     const url=sources.get(match[1]);if(!url)continue;
     if(match.index>start)nodes.push({type:'text',value:child.value.slice(start,match.index)});
     nodes.push({type:'link',url,title:'Supplied source (not fact-checked)',children:[{type:'text',value:match[0]}]});
     start=match.index+match[0].length;
    }
    if(start<child.value.length)nodes.push({type:'text',value:child.value.slice(start)});
    return nodes;
   });
  }
  walk(tree);
 };
}
