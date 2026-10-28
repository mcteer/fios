import hashlib
import json
import time
import os
import subprocess
import sys
import unittest
from pathlib import Path
from uuid import uuid4
from unittest.mock import patch

import httpx2
from fios_agent.platform_protocol import parse_platform_command, decode_platform_frame, PlatformProtocolError
from fios_agent.platform_worker import run_platform, output_chunks, PlatformTransport
from fios_agent.worker import Settings
from test_platform_guard import guard_environment, observation


def command():
    return {'v':1,'type':'run','job_id':str(uuid4()),'attempt':0,'epoch':str(uuid4()),
            'model':'test/model','endpoint_hash':hashlib.sha256(b'http://127.0.0.1:1/v1').hexdigest(),
            'expires_at':int(time.time()*1000)+5000,'context':[{'role':'user','content':'hello'}]}


class PlatformWorkerTests(unittest.IsolatedAsyncioTestCase):
    async def test_exact_local_target_single_post_and_no_tools(self):
        sent=[]; events=[]
        async def handler(request):
            if request.method=='GET':
                return httpx2.Response(200,json={'status':'ok'} if request.url.path=='/health' else {'data':[{'id':'test/model'}]})
            sent.append(json.loads(request.content))
            chunk={'id':'x','object':'chat.completion.chunk','created':1,'model':'test/model',
                   'choices':[{'index':0,'delta':{'content':'answer'},'finish_reason':None}]}
            return httpx2.Response(200,headers={'content-type':'text/event-stream'},content=('data: '+json.dumps(chunk)+'\n\ndata: [DONE]\n\n').encode())
        async def emit(event):events.append(event)
        async def guard_query(profile, permitted):return observation(profile, permitted, int(time.time()*1000))
        with patch('httpx2.AsyncHTTPTransport.handle_async_request',side_effect=AssertionError('Live inference forbidden')), \
             patch.dict(os.environ,guard_environment()), \
             patch('fios_agent.platform_guard.query_observation',new=guard_query):
            await run_platform(parse_platform_command(command()),Settings('http://127.0.0.1:1/v1','test'),emit,transport=httpx2.MockTransport(handler))
        self.assertEqual(len(sent),1)
        self.assertEqual(sent[0]['model'],'test/model')
        self.assertNotIn('tools',sent[0])
        self.assertEqual(events[-1]['status'],'complete')
        self.assertEqual(sum(e['type']=='dispatched' for e in events),1)
        self.assertTrue(all(e['v']==1 for e in events))
        self.assertEqual(events[-2]['type'],'usage')
        self.assertEqual(events[-2]['posts'],1)
        self.assertEqual(events[-2]['output_units'],6)

    async def test_endpoint_mismatch_rejects_before_network(self):
        data=command();data['endpoint_hash']='0'*64;events=[]
        async def emit(event):events.append(event)
        await run_platform(parse_platform_command(data),Settings('http://127.0.0.1:1/v1','test'),emit)
        self.assertEqual(events[-1]['code'],'invalid_request')

    def test_bounded_strict_command(self):
        for change in ({'attempt':True},{'attempt':4},{'v':2},{'role':'operator'},
                       {'context':[{'role':'user','content':[{'type':'image','data':'x'}]}]},
                       {'context':[{'role':'user','content':'x'*128001}]}):
            data={**command(),**change}
            with self.assertRaises(PlatformProtocolError):parse_platform_command(data)

    async def test_revocation_during_dispatch_event_cannot_send_post(self):
        from pydantic_ai import CancellationToken
        token=CancellationToken();posts=[];events=[]
        async def handler(request):
            if request.method=='POST':
                posts.append(request)
                raise AssertionError('Revoked POST reached transport')
            return httpx2.Response(200,json={'status':'ok'} if request.url.path=='/health' else {'data':[{'id':'test/model'}]})
        async def emit(event):
            events.append(event)
            if event['type']=='dispatched':token.cancel()
        await run_platform(parse_platform_command(command()),Settings('http://127.0.0.1:1/v1','test'),emit,
                           transport=httpx2.MockTransport(handler),token=token)
        self.assertEqual(posts,[])
        self.assertEqual(next(e for e in events if e['type']=='usage')['posts'],0)
        self.assertFalse(any(e.get('status')=='complete' for e in events))

    def test_duplicate_and_nonfinite_pipe_json_rejects(self):
        for payload in (b'{"v":1,"\\u0076":1}',b'{"value":NaN}',b'['*10000,b'\xff',b'x'*1048577):
            with self.assertRaises(PlatformProtocolError):decode_platform_frame(payload)

    def test_utf16_output_frames_preserve_unicode_and_bound_each_chunk(self):
        original='🌊'*12000+'x'*12000
        chunks=list(output_chunks(original))
        self.assertEqual(''.join(chunks),original)
        self.assertTrue(all(len(part.encode('utf-16-le'))//2<=8192 for part in chunks))

    def test_fixed_policy_counts_toward_input(self):
        data=command();data['context']=[{'role':'user','content':'x'*128000}]
        with self.assertRaises(PlatformProtocolError):parse_platform_command(data)

    def test_installed_metadata_is_content_free_and_exact(self):
        from fios_agent.harness import INSTRUCTIONS
        result=subprocess.run([sys.executable,'-I','-B','-m','fios_agent.platform_worker','--metadata'],capture_output=True,timeout=10,
                              env={'PATH':os.environ.get('PATH','/usr/bin:/bin'),'LANG':'C'})
        self.assertEqual(result.returncode,0)
        self.assertEqual(result.stderr,b'')
        self.assertFalse(INSTRUCTIONS.encode() in result.stdout,'Fixed policy leaked')
        value=json.loads(result.stdout)
        self.assertEqual(set(value),{'version','pipe_version','package_version','python_version','policy_sha256','policy_input_units'})
        self.assertEqual(value['version'],1)
        self.assertEqual(value['pipe_version'],1)
        self.assertEqual(value['policy_sha256'],hashlib.sha256(INSTRUCTIONS.encode()).hexdigest())
        self.assertEqual(value['policy_input_units'],len(INSTRUCTIONS.encode('utf-16-le'))//2)
        fixture=json.loads((Path(__file__).parents[1]/'fixtures/platform/model.json').read_text())
        self.assertEqual(value['policy_sha256'],fixture['policy_sha256'])
        self.assertEqual(value['policy_input_units'],fixture['policy_input_units'])

    def test_installed_private_pipe_rejects_without_secret_echo(self):
        marker='SECRET_PAYLOAD_NOT_FOR_LOGS'
        payload=json.dumps({'secret':marker}).encode()
        for framed in (len(payload).to_bytes(4,'big')+payload,(1048577).to_bytes(4,'big')):
            result=subprocess.run([sys.executable,'-I','-B','-m','fios_agent.platform_worker'],input=framed,
                                  capture_output=True,timeout=10,env={'PATH':os.environ.get('PATH','/usr/bin:/bin'),'LANG':'C'})
            self.assertEqual(result.returncode,0)
            self.assertEqual(result.stderr,b'')
            self.assertNotIn(marker.encode(),result.stdout)
            size=int.from_bytes(result.stdout[:4],'big')
            self.assertEqual(len(result.stdout)-4,size)
            event=json.loads(result.stdout[4:])
            self.assertEqual(event,{'v':1,'type':'error','code':'invalid_request'})

    async def test_incomplete_malformed_http_and_tool_outputs_never_complete_or_retry(self):
        marker='PRIVATE_UPSTREAM_BODY_NOT_FOR_EVENTS'
        for mode in ('missing_done','malformed','http_error','unrequested_tool'):
            posts=[];events=[]
            async def handler(request):
                if request.method=='GET':
                    return httpx2.Response(200,json={'status':'ok'} if request.url.path=='/health' else {'data':[{'id':'test/model'}]})
                posts.append(request)
                if mode=='http_error':return httpx2.Response(503,json={'error':{'message':marker}})
                delta={'content':'answer'} if mode!='unrequested_tool' else {'tool_calls':[{'index':0,'id':'fixture-call','type':'function','function':{'name':'service.force','arguments':'{}'}}]}
                chunk={'id':'x','object':'chat.completion.chunk','created':1,'model':'test/model','choices':[{'index':0,'delta':delta,'finish_reason':None}]}
                data=('data: '+json.dumps(chunk)+'\n\n').encode() if mode!='malformed' else b'data: {invalid}\n\n'
                if mode!='missing_done':data+=b'data: [DONE]\n\n'
                return httpx2.Response(200,headers={'content-type':'text/event-stream'},content=data)
            async def emit(event):events.append(event)
            async def guard_query(profile,permitted):return observation(profile,permitted,int(time.time()*1000))
            with patch.dict(os.environ,guard_environment()),patch('fios_agent.platform_guard.query_observation',new=guard_query):
                await run_platform(parse_platform_command(command()),Settings('http://127.0.0.1:1/v1','test'),emit,transport=httpx2.MockTransport(handler))
            self.assertEqual(len(posts),1)
            self.assertFalse(any(e.get('status')=='complete' for e in events))
            self.assertEqual(next(e for e in events if e['type']=='usage')['posts'],1)
            self.assertEqual(sum(e['type']=='dispatched' for e in events),1)
            self.assertFalse(marker in json.dumps(events),'Raw upstream body leaked')

    async def test_every_transport_request_is_bound_to_native_origin_and_path(self):
        from pydantic_ai import CancellationToken
        from fios_agent.transport import StreamFailure
        reached=[]
        async def handler(request):reached.append(request);return httpx2.Response(200,json={})
        async def emit(_event):pass
        transport=PlatformTransport(parse_platform_command(command()),httpx2.MockTransport(handler),emit,CancellationToken(),base_url='http://127.0.0.1:1/v1')
        try:
            for method,url in [('GET','https://public.invalid/v1/models'),('GET','http://127.0.0.1:2/v1/models'),
                               ('GET','http://127.0.0.1:1/admin'),('DELETE','http://127.0.0.1:1/v1/models'),
                               ('GET','http://127.0.0.1:1/v1/models?redirect=outside')]:
                with self.assertRaises(StreamFailure):await transport.handle_async_request(httpx2.Request(method,url))
        finally:await transport.aclose()
        self.assertEqual(reached,[])

    async def test_unknown_model_rejected_before_dispatch(self):
        posts=[];events=[]
        async def handler(request):
            if request.method=='POST':posts.append(request)
            return httpx2.Response(200,json={'status':'ok'} if request.url.path=='/health' else {'data':[{'id':'other/model'}]})
        async def emit(event):events.append(event)
        await run_platform(parse_platform_command(command()),Settings('http://127.0.0.1:1/v1','test'),emit,transport=httpx2.MockTransport(handler))
        self.assertEqual(posts,[])
        self.assertFalse(any(e['type']=='dispatched' for e in events))
        self.assertEqual(events[-1]['code'],'model_unavailable')

    async def test_missing_native_guard_cannot_dispatch(self):
        posts=[];events=[]
        async def handler(request):
            if request.method=='POST':posts.append(request)
            return httpx2.Response(200,json={'status':'ok'} if request.url.path=='/health' else {'data':[{'id':'test/model'}]})
        async def emit(event):events.append(event)
        with patch.dict(os.environ,{'FIOS_PLATFORM_GUARD_PATH':''}):
            await run_platform(parse_platform_command(command()),Settings('http://127.0.0.1:1/v1','test'),emit,transport=httpx2.MockTransport(handler))
        self.assertEqual(posts,[])
        self.assertEqual(next(e for e in events if e['type']=='usage')['posts'],0)
        self.assertFalse(any(e.get('status')=='complete' for e in events))

    async def test_revocation_during_guard_await_cannot_dispatch(self):
        from pydantic_ai import CancellationToken
        token=CancellationToken();posts=[];events=[]
        async def handler(request):
            if request.method=='POST':posts.append(request)
            return httpx2.Response(200,json={'status':'ok'} if request.url.path=='/health' else {'data':[{'id':'test/model'}]})
        async def guard(_command):token.cancel()
        async def emit(event):events.append(event)
        with patch('fios_agent.platform_worker.check_native_guard',new=guard):
            await run_platform(parse_platform_command(command()),Settings('http://127.0.0.1:1/v1','test'),emit,transport=httpx2.MockTransport(handler),token=token)
        self.assertEqual(posts,[])
        self.assertEqual(next(e for e in events if e['type']=='usage')['posts'],0)
        self.assertFalse(any(e.get('status')=='complete' for e in events))

    def test_expired_permission_rejects(self):
        data=command();data['expires_at']=int(time.time()*1000)-1
        with self.assertRaises(PlatformProtocolError):parse_platform_command(data)
