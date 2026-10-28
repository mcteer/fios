"""Private installed Pydantic worker fixture: all model/health IO is mocked."""
import asyncio
import json
import os
import socket
import sys
import time

import httpx2
from fios_agent.platform_worker import main
from fios_agent import platform_guard

posts = 0
# This trusted fixture mocks only the read-only observation transport. The
# installed child's actual guard/mapping/freshness validation still runs.
os.environ.update({'FIOS_PLATFORM_GUARD_PATH':'/fixture/observe.sock','FIOS_PLATFORM_HOST_ID':'fixture-host',
                   'FIOS_PLATFORM_PROFILE_HASH':'f'*64,'FIOS_PLATFORM_NATIVE_EPOCH':'native-fixture-one',
                   'FIOS_PLATFORM_NATIVE_SEQUENCE':'1','FIOS_PLATFORM_CANONICAL_MODEL':'fixture/model',
                   'FIOS_PLATFORM_NATIVE_MODEL':'fixture/model'})


async def guard_query(profile, command):
    return {'version':1,'host':profile.host,'endpoint_hash':command.endpoint_hash,'profile_hash':profile.profile_hash,
            'manager_epoch':command.epoch,'native_epoch':profile.native_epoch,'sequence':profile.minimum_sequence,
            'sampled_at':int(time.time()*1000),'coverage':'supported','resident_model':'fixture/idle-other-model',
            'outstanding_owners':0,'loading':False}


platform_guard.query_observation = guard_query


def denied(*_args, **_kwargs):
    raise RuntimeError('live_transport_forbidden')


async def handler(request):
    global posts
    if request.method == 'GET' and request.url.path == '/health':
        if os.environ.get('FIOS_PLATFORM_FIXTURE_DELAY') == '1.25':
            await asyncio.sleep(1.25)
        return httpx2.Response(200, json={'status': 'ok'})
    if request.method == 'GET' and request.url.path == '/v1/models':
        return httpx2.Response(200, json={'data': [{'id': 'fixture/not-allowed' if os.environ.get('FIOS_PLATFORM_FIXTURE_MODE') == 'missing-model' else 'fixture/model'}]})
    if request.method != 'POST' or request.url.path != '/v1/chat/completions':
        raise RuntimeError('unexpected_mock_request')
    body = json.loads(request.content)
    if body.get('model') != 'fixture/model' or body.get('tools') or posts:
        raise RuntimeError('invalid_mock_dispatch')
    posts += 1
    chunk = {'id': 'fixture', 'object': 'chat.completion.chunk', 'created': 1, 'model': 'fixture/model',
             'choices': [{'index': 0, 'delta': {'content': 'MOCK_ONLY'}, 'finish_reason': None}]}
    return httpx2.Response(200, headers={'content-type': 'text/event-stream'},
                          content=('data: ' + json.dumps(chunk) + '\n\ndata: [DONE]\n\n').encode())


# Block any accidentally retained real transport in addition to injecting the
# explicit mock. No inference server/listener or live discovery is started.
httpx2.AsyncHTTPTransport.handle_async_request = denied
httpx2.HTTPTransport.handle_request = denied
httpx2.AsyncHTTPTransport = lambda **_kwargs: httpx2.MockTransport(handler)
socket.socket.connect = denied
socket.socket.connect_ex = denied
socket.create_connection = denied
try:
    asyncio.run(main())
except Exception:
    sys.stderr.write('private worker fixture failed\n')
    raise SystemExit(1) from None
