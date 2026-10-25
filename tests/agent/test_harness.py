import unittest
from uuid import uuid4
from unittest.mock import patch
import httpx2
from pydantic_ai import CancellationToken
from fios_agent.harness import run_agent
from fios_agent.protocol import parse_command
from fios_agent.worker import Settings


class HarnessTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        # Unit tests may only use their explicitly supplied MockTransport.
        guard = patch('httpx2.AsyncHTTPTransport.handle_async_request', side_effect=AssertionError('Live model network is disabled in unit tests.'))
        guard.start()
        self.addCleanup(guard.stop)

    async def request(self, frames, status=200, snapshot=None):
        requests = []
        async def handler(request):
            if request.method == 'GET':
                if request.url.path == '/health': return httpx2.Response(200, json={'status':'ok'})
                model = {'id':'test/model'} if request.url.host == 'peer' else {'id':'test/model@studio-a','lan_peer':'studio-a'}
                return httpx2.Response(200, json={'data':[model]})
            requests.append(request)
            if isinstance(status, Exception):
                raise status
            return httpx2.Response(status, headers={'content-type':'text/event-stream'}, content=frames)
        events = []
        async def emit(event): events.append(event)
        command = parse_command({'v':1,'type':'run','run_id':str(uuid4()),'model':'test/model@studio-a',
                                 'context':[{'role':'user','content':'hello'}]})
        await run_agent(command, CancellationToken(), emit, Settings('http://127.0.0.1:1/v1','local',{'studio-a':'http://peer/v1'},snapshot),
                        transport=httpx2.MockTransport(handler))
        return requests, events

    async def test_exact_target_one_request_and_incremental_content(self):
        import json
        chunk = {'id':'mock','object':'chat.completion.chunk','created':1,'model':'test/model@studio-a',
                 'choices':[{'index':0,'delta':{'content':'hello'},'finish_reason':None}]}
        requests, events = await self.request(('data: '+json.dumps(chunk)+'\n\ndata: [DONE]\n\n').encode())
        self.assertEqual(len(requests), 1)
        body = json.loads(requests[0].content)
        self.assertEqual(body['model'], 'test/model@studio-a')
        self.assertEqual(body['max_tokens'], 8192)
        self.assertNotIn('tools',body)
        self.assertEqual(''.join(e.get('content','') for e in events if e['type']=='delta'),'hello')
        self.assertEqual(events[-1]['status'],'complete')

    async def test_failure_not_retried_and_provider_body_redacted(self):
        requests, events = await self.request(b'SENSITIVE_PROVIDER_BODY',503)
        self.assertEqual(len(requests),1)
        self.assertEqual(events[-1]['code'],'upstream_http')
        self.assertNotIn('SENSITIVE',str(events))

    async def test_sdk_timeout_is_not_retried(self):
        requests, events = await self.request(b'', httpx2.ReadTimeout('test timeout'))
        self.assertEqual(len(requests), 1)
        self.assertEqual(events[-1]['code'], 'upstream_timeout')

    async def test_missing_or_expired_peer_evidence_prevents_inference(self):
        import tempfile, json
        from pathlib import Path
        import hashlib
        with tempfile.TemporaryDirectory() as directory:
            file=Path(directory)/'peers.json'
            requests, events = await self.request(b'', snapshot=str(file))
            self.assertEqual(requests, [])
            self.assertEqual(events[-1]['code'], 'model_unavailable')
            file.write_text(json.dumps({'v':1,'peers':[{'name':'studio-a','endpointHash':hashlib.sha256(b'http://peer/v1').hexdigest(),
                'status':'available','reason':'ok','checkedAt':0,'models':[{'id':'test/model'}]}]}))
            requests, events = await self.request(b'', snapshot=str(file))
            self.assertEqual(requests, [])
            self.assertEqual(events[-1]['code'], 'model_unavailable')

    async def test_missing_sentinel_is_not_completion(self):
        requests, events = await self.request(b'data: {"choices":[]}\n\n')
        self.assertEqual(len(requests),1)
        self.assertEqual(events[-1]['type'],'error')
