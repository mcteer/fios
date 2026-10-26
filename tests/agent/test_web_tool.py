"""Actual installed Pydantic Agent with mock model/provider, not a tool stub."""
import json
import unittest
from uuid import uuid4
from unittest.mock import patch
import httpx2
from pydantic_ai import CancellationToken
from fios_agent.harness import run_agent
from fios_agent.protocol import parse_command,parse_event
from fios_agent.worker import Settings
from fios_agent.web.searxng import LIMITER


def frame(delta,finish=None):
    payload={'id':'mock','object':'chat.completion.chunk','created':1,'model':'test/model',
        'choices':[{'index':0,'delta':delta,'finish_reason':finish}]}
    return ('data: '+json.dumps(payload)+'\n\ndata: [DONE]\n\n').encode()


class ToolIntegrationTests(unittest.IsolatedAsyncioTestCase):
    async def exercise(self,*,no_tool=False,incomplete=False,query='Python release',second_incomplete=False,repeat=False,parallel=False,unknown=False,cancel_public=False,fragmented=False,off=False):
        posts=[]; web=[]; events=[]
        token=CancellationToken()
        LIMITER.calls.clear(); LIMITER.until=0; LIMITER.suppressed=False
        async def model(req):
            if req.method=='GET':
                return httpx2.Response(200,json={'status':'ok'} if req.url.path=='/health' else {'data':[{'id':'test/model'}]})
            posts.append(json.loads(req.content))
            if len(posts)==1:
                raw=frame({'content':'ordinary answer'},'stop') if no_tool else frame({'tool_calls':[{'index':0,'id':'call_1','type':'function','function':{'name':'web_search','arguments':json.dumps({'query':query})}}]},'tool_calls')
                if fragmented:
                    marker=b'data: [DONE]\n\n'
                    raw=(frame({'content':'Preliminary text'})[:-len(marker)]+
                         frame({'tool_calls':[{'index':0,'id':'call_1','type':'function','function':{'name':'web_','arguments':'{"query":'}}]})[:-len(marker)]+
                         frame({'tool_calls':[{'index':0,'function':{'name':'search','arguments':'"Python release"}'}}]},'tool_calls'))
                if incomplete: raw=raw.replace(b'data: [DONE]\n\n',b'')
            else:
                raw=frame({'tool_calls':[{'index':0,'id':'call_2','type':'function','function':{'name':'web_search','arguments':json.dumps({'query':query})}}]},'tool_calls') if repeat else frame({'content':'Python fixture version 3.11 [S1]'},'stop')
                if second_incomplete: raw=raw.replace(b'data: [DONE]\n\n',b'')
            if len(posts)==1 and unknown: raw=raw.replace(b'web_search',b'run_shell')
            if len(posts)==1 and parallel: raw=raw.replace(b'"index": 0, "id": "call_1"',b'"index": 1, "id": "call_1"')
            return httpx2.Response(200,headers={'content-type':'text/event-stream'},content=raw)
        async def public(req):
            web.append(str(req.url))
            if cancel_public: token.cancel()
            if req.url.path=='/robots.txt': return httpx2.Response(200,text='User-agent: *\nAllow: /',headers={'content-type':'text/plain'})
            if req.url.host=='searxng':
                return httpx2.Response(200,json={'results':[{'url':'https://www.python.org/doc/','title':'Python','content':'Release notes'}]})
            return httpx2.Response(200,text='<main>Python fixture version 3.11</main>',headers={'content-type':'text/html'})
        async def emit(value): parse_event(value); events.append(value)
        command=parse_command({'v':2,'type':'run','run_id':str(uuid4()),'model':'test/model',
            'context':[{'role':'user','content':'Python release'}],
            'search_input':{'current_text':'Python release','previous_text':None,'current_has_attachments':False,
                'previous_has_attachments':False,'current_elided':False,'previous_elided':False}})
        with patch('httpx2.AsyncHTTPTransport.handle_async_request',side_effect=AssertionError('live network forbidden')):
            await run_agent(command,token,emit,Settings('http://mock/v1','local',web_search='off' if off else 'auto'),
                transport=httpx2.MockTransport(model),public_transport=httpx2.MockTransport(public))
        return posts,web,events

    async def test_actual_tool_return_and_same_model_continuation(self):
        posts,web,events=await self.exercise()
        self.assertEqual(events[-1].get('status'),'complete',events)
        self.assertEqual(len(posts),2)
        self.assertTrue(web)
        self.assertEqual([p['model'] for p in posts],['test/model']*2)
        self.assertEqual(posts[0]['tools'][0]['function']['name'],'web_search')
        self.assertFalse(posts[1].get('tools'))
        tool_parts=[m for m in posts[1]['messages'] if m['role']=='tool']
        self.assertEqual(len(tool_parts),1)
        self.assertIn('fixture version',tool_parts[0]['content'])
        self.assertEqual([e['manifest']['evidence_state'] for e in events if e['type']=='search_sources'],['retrieved_only','sent_to_model'])
        self.assertEqual(sum(e['type']=='answer_reset' for e in events),1)
        self.assertIn('fixture version 3.11',''.join(e.get('content','') for e in events))
        self.assertNotIn('query',str([e for e in events if e['type'].startswith('search_')]))

    async def test_operator_off_does_not_declare_tools_or_retrieve(self):
        posts,web,events=await self.exercise(off=True,no_tool=True)
        self.assertEqual(len(posts),1)
        self.assertFalse(posts[0].get('tools'))
        self.assertEqual(web,[])
        self.assertEqual(events[-2]['status']['outcome'],'disabled')

    async def test_no_tool_turn_is_one_request_and_zero_search(self):
        posts,web,events=await self.exercise(no_tool=True)
        self.assertEqual(len(posts),1)
        self.assertEqual(web,[])
        self.assertEqual(events[-2]['status']['outcome'],'not_requested')

    async def test_missing_first_done_never_searches(self):
        posts,web,events=await self.exercise(incomplete=True)
        self.assertEqual(len(posts),1)
        self.assertEqual(web,[])
        self.assertEqual(events[-1]['code'],'incomplete_stream')

    async def test_fragmented_arguments_and_preliminary_text_reset(self):
        posts,web,events=await self.exercise(fragmented=True)
        self.assertEqual(events[-1].get('status'),'complete',events)
        self.assertEqual(len(posts),2)
        reset=next(i for i,e in enumerate(events) if e['type']=='answer_reset')
        self.assertTrue(any(e.get('content')=='Preliminary text' for e in events[:reset]))
        self.assertFalse(any('query' in e.get('content','') for e in events))

    async def test_cancellation_during_public_work_never_continues_model(self):
        posts,web,events=await self.exercise(cancel_public=True)
        self.assertEqual(len(posts),1)
        self.assertEqual(events[-1]['type'],'done')
        self.assertEqual(events[-1]['status'],'interrupted')
        self.assertFalse(any(e.get('manifest',{}).get('evidence_state')=='sent_to_model' for e in events))

    async def test_each_response_requires_independent_done(self):
        posts,web,events=await self.exercise(second_incomplete=True)
        self.assertEqual(len(posts),2)
        self.assertTrue(web)
        self.assertEqual(events[-1]['code'],'incomplete_stream')
        self.assertFalse(any(e.get('status')=='complete' for e in events))

    async def test_repeat_unknown_parallel_fail_closed(self):
        for mode in ['repeat','unknown','parallel']:
            posts,web,events=await self.exercise(**{mode:True})
            self.assertEqual(events[-1]['type'],'error',mode)
            self.assertLessEqual(len(posts),2)
            if mode!='repeat': self.assertEqual(web,[])

    async def test_private_query_fails_before_network_but_can_explain_once(self):
        posts,web,events=await self.exercise(query='attachmentcanary2026 release')
        self.assertEqual(web,[])
        self.assertEqual(len(posts),2)
        self.assertTrue(any(e.get('status',{}).get('outcome')=='privacy_skipped' for e in events if isinstance(e.get('status'),dict)))
