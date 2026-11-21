import json
import asyncio
import tempfile
import time
import hashlib
from pathlib import Path
import unittest
from unittest.mock import patch
import httpx2
from fios_agent.availability import discover, peer_configuration
from fios_agent.worker import Settings


class AvailabilityTests(unittest.IsolatedAsyncioTestCase):
    async def test_fresh_snapshot_requires_matching_endpoint_and_expires(self):
        with tempfile.TemporaryDirectory() as directory:
            file = Path(directory)/'peers.json'
            frame = {'v':1,'peers':[{'name':'p','endpointHash':hashlib.sha256(b'http://studio/v1').hexdigest(),
                'checkedAt':int(time.time()*1000),'status':'available','reason':'ok','models':[{'id':'m','loaded':False}]}]}
            file.write_text(json.dumps(frame))
            settings = Settings('http://gateway/v1','',{'p':'http://studio/v1'},str(file))
            async def handle(request):
                self.assertEqual(request.url.host,'gateway')
                return httpx2.Response(200,json={'status':'ok'} if request.url.path=='/health' else {'data':[{'id':'m@p','lan_peer':'p'}]})
            result = await discover(settings,transport=httpx2.MockTransport(handle))
            self.assertEqual(result['models'][0]['availability'],'available')
            for change in [{'checkedAt':0},{'checkedAt':int(time.time()*1000)+10000},{'endpointHash':'0'*64},{'status':'invented'}]:
                changed=json.loads(json.dumps(frame));changed['peers'][0].update(change);file.write_text(json.dumps(changed))
                result = await discover(settings,transport=httpx2.MockTransport(handle))
                self.assertEqual(result['models'][0]['availability'],'unknown')
            file.unlink()
            result = await discover(settings,transport=httpx2.MockTransport(handle))
            self.assertEqual(result['models'][0]['availability'],'unknown')

    async def test_shared_snapshot_rejects_every_future_millisecond_without_peer_probe(self):
        now = 1_794_700_000_000
        with tempfile.TemporaryDirectory() as directory, patch('fios_agent.availability.time.time', return_value=now/1000):
            file = Path(directory)/'peers.json'
            settings = Settings('http://gateway/v1','',{'p':'http://studio/v1'},str(file))
            calls = []
            async def handle(request):
                calls.append(request)
                self.assertEqual(request.method,'GET')
                self.assertEqual(request.url.host,'gateway')
                self.assertNotIn('authorization',request.headers)
                return httpx2.Response(200,json={'status':'ok'} if request.url.path=='/health' else {'data':[{'id':'exact/model@p','lan_peer':'p'}]})
            for offset in [0,-5000,1,500,1000,1001,-5001]:
                with self.subTest(offset=offset):
                    file.write_text(json.dumps({'v':1,'peers':[{'name':'p','endpointHash':hashlib.sha256(b'http://studio/v1').hexdigest(),
                        'checkedAt':now+offset,'status':'available','reason':'ok','models':[{'id':'exact/model','loaded':False}]}]}))
                    result = await discover(settings,transport=httpx2.MockTransport(handle))
                    self.assertEqual(result['models'][0]['id'],'exact/model@p')
                    self.assertEqual(result['models'][0]['availability'],'available' if -5000<=offset<=0 else 'unknown')
                    if offset>0:self.assertEqual(result['models'][0]['reason'],'host_unverified')
            self.assertEqual(len(calls),14)

    async def test_shared_contract_fixtures(self):
        fixtures = json.loads((Path(__file__).parents[1] / 'fixtures/availability.json').read_text())
        for fixture in fixtures:
            async def handle(request):
                if request.url.path == '/health': return httpx2.Response(200, json={'status':'ok'})
                return httpx2.Response(200, json={'data':fixture['gateway'] if request.url.host == 'gateway' else fixture['peers'][request.url.host]})
            result = await discover(Settings('http://gateway/v1', '', {p:'http://'+p+'/v1' for p in fixture['peers']}), transport=httpx2.MockTransport(handle))
            self.assertEqual([[m['availability'],m['reason'],m['loaded']] for m in result['models']], fixture['expected'], fixture['name'])

    async def test_malformed_oversized_and_slow_responses_are_bounded(self):
        for payload in [{'data':'bad'}, {'data':[{'id':'m','loaded':'false'}]}, {'data':[{'id':'m'},{'id':'m'}]}, {'data':[],'padding':'x'*(1024*1024)}]:
            async def handle(request):
                return httpx2.Response(200, json={'status':'ok'} if request.url.path == '/health' else payload)
            result = await discover(Settings('http://gateway/v1',''), transport=httpx2.MockTransport(handle))
            self.assertEqual(result['hosts'][0]['status'], 'unknown')
            self.assertEqual(result['models'], [])
        async def slow(request):
            await asyncio.sleep(10)
            return httpx2.Response(200, json={})
        start = asyncio.get_running_loop().time()
        result = await discover(Settings('http://gateway/v1',''), transport=httpx2.MockTransport(slow), timeout=.03)
        self.assertEqual(result['hosts'][0]['status'], 'unavailable')
        self.assertLess(asyncio.get_running_loop().time()-start, .5)

    async def test_stale_peer_and_recovery_never_trust_gateway_urls(self):
        mode = {'value': 'down'}
        calls = []
        async def handle(request):
            calls.append(request)
            if request.url.host == 'gateway':
                if request.url.path == '/health': return httpx2.Response(200, json={'status': 'ok'})
                return httpx2.Response(200, json={'data': [
                    {'id': 'org/local', 'loaded': False, 'capabilities': ['chat']},
                    {'id': 'org/model@studio-a', 'lan_peer': 'studio-a', 'capabilities': ['chat']}],
                    'lan_peers': [{'name': 'evil', 'url': 'http://169.254.169.254'}]})
            self.assertEqual(request.url.host, 'studio')
            self.assertNotIn('authorization', request.headers)
            if mode['value'] == 'down': raise httpx2.ConnectError('unreachable')
            if mode['value'] == 'unauthorized': return httpx2.Response(401)
            if request.url.path == '/health': return httpx2.Response(200, json={'status': 'ok'})
            return httpx2.Response(200, json={'data': [] if mode['value'] == 'missing' else [{'id': 'org/model', 'loaded': False}]})
        settings = Settings('http://gateway/v1', 'PRIVATE_TEST_KEY', {'studio-a': 'http://studio/v1'})
        for mode_value, expected, reason in [('down', 'unavailable', 'host_down'), ('missing', 'unavailable', 'not_advertised'), ('unauthorized', 'unknown', 'unauthorized'), ('up', 'available', 'ok')]:
            mode['value'] = mode_value
            result = await discover(settings, transport=httpx2.MockTransport(handle))
            self.assertEqual(result['models'][0]['availability'], 'available')
            self.assertFalse(result['models'][0]['loaded'])
            self.assertEqual(result['models'][1]['availability'], expected)
            self.assertEqual(result['models'][1]['reason'], reason)
            self.assertNotIn('PRIVATE_TEST_KEY', json.dumps(result))
        self.assertTrue(all(r.method == 'GET' for r in calls))

    async def test_exact_bonjour_peer_mapping_does_not_rename_model(self):
        route = {'id': 'org/model@Mac.home', 'lan_peer': 'Mac.home'}
        endpoint = 'http://fios-edge-b.local:11234/v1'
        async def handle(request):
            gateway = request.url.host == 'gateway'
            self.assertIn(request.url.host, ('gateway', 'fios-edge-b.local'))
            self.assertEqual(request.headers.get('authorization'), 'Bearer MOCK_GATEWAY_KEY' if gateway else None)
            return httpx2.Response(200, json={'status': 'ok'} if request.url.path == '/health' else {'data': [route if gateway else {'id': 'org/model'}]})
        for peers, reason in [({'fios-edge-b': endpoint}, 'host_unverified'), ({'Mac.home': endpoint}, 'ok')]:
            result = await discover(Settings('http://gateway/v1', 'MOCK_GATEWAY_KEY', peers), transport=httpx2.MockTransport(handle))
            self.assertEqual([(m['id'], m['reason']) for m in result['models']], [(route['id'], reason)])

    async def test_unknown_peer_and_invalid_gateway_fail_closed(self):
        async def handle(request):
            if request.url.path == '/health': return httpx2.Response(200, json={'status': 'ok'})
            return httpx2.Response(200, json={'data': [{'id': 'org/model@missing', 'lan_peer': 'missing'}]})
        result = await discover(Settings('http://gateway/v1', ''), transport=httpx2.MockTransport(handle))
        self.assertEqual(result['models'][0]['availability'], 'unknown')
        with self.assertRaises(ValueError): peer_configuration('{"p":"http://user:secret@host/v1"}')
        with self.assertRaises(ValueError): peer_configuration('{"p":"http://host/v1?x=1"}')
        with self.assertRaises(ValueError): peer_configuration('[]')
