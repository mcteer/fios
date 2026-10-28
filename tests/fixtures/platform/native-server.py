"""Disposable loopback/Unix model+observation MOCK; never runs real inference."""
import asyncio
import hashlib
import json
import os
import struct
import sys
import time
from uuid import UUID


def body(value):
    return json.dumps(value, separators=(',', ':')).encode()


async def main():
    directory, epoch = sys.argv[1:]
    assert str(UUID(epoch)) == epoch
    path = directory + '/observe.sock'
    assert not os.path.lexists(path)
    profile_hash = 'f' * 64
    endpoint_hash = None
    sequence = 1
    posts = 0

    async def observe(reader, writer):
        nonlocal sequence
        try:
            async with asyncio.timeout(2):
                size = struct.unpack('!I', await reader.readexactly(4))[0]
                assert 0 < size <= 65536
                request = json.loads(await reader.readexactly(size))
                assert request['operation'] == 'activity' and request['payload'] == {}
                sequence += 1
                snapshot = {'version': 1, 'host': 'fixture-host', 'endpoint_hash': endpoint_hash,
                            'profile_hash': profile_hash, 'manager_epoch': epoch, 'native_epoch': 'native-fixture-one',
                            'sequence': sequence, 'sampled_at': int(time.time() * 1000), 'coverage': 'supported',
                            'resident_model': 'fixture/idle-other', 'outstanding_owners': 0, 'loading': False}
                response = body({'version': 1, 'id': request['id'], 'ok': True, 'epoch': epoch,
                                 'coverage': 'supported', 'activity': 'idle', 'observation': snapshot})
                writer.write(struct.pack('!I', len(response)) + response)
                await writer.drain()
        except Exception:
            pass
        finally:
            writer.close()

    async def http(reader, writer):
        nonlocal posts
        try:
            async with asyncio.timeout(3):
                headers = await reader.readuntil(b'\r\n\r\n')
                assert len(headers) <= 16384
                lines = headers.decode('ascii').split('\r\n')
                method, route, _ = lines[0].split(' ')
                fields = dict(line.split(':', 1) for line in lines[1:] if ':' in line)
                fields = {key.lower(): value.strip() for key, value in fields.items()}
                length = int(fields.get('content-length', '0'))
                assert 0 <= length <= 1048576
                data = await reader.readexactly(length)
                content_type = 'application/json'
                if method == 'GET' and route == '/health':
                    result = body({'status': 'ok'})
                elif method == 'GET' and route == '/v1/models':
                    result = body({'data': [{'id': 'fixture/model'}]})
                elif method == 'POST' and route == '/v1/chat/completions':
                    posts += 1
                    print(json.dumps({'posts': posts}), flush=True)
                    value = json.loads(data)
                    assert value['model'] == 'fixture/model' and not value.get('tools')
                    assert value['stream'] is True and value['max_tokens'] <= 8192
                    chunk = {'id': 'mock-fixture', 'object': 'chat.completion.chunk', 'created': 1, 'model': 'fixture/model',
                             'choices': [{'index': 0, 'delta': {'content': 'MOCK_ONLY'}, 'finish_reason': None}]}
                    result = b'data: ' + body(chunk) + b'\n\ndata: [DONE]\n\n'
                    content_type = 'text/event-stream'
                else:
                    raise ValueError()
                writer.write(('HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Type: ' + content_type +
                              '\r\nContent-Length: ' + str(len(result)) + '\r\n\r\n').encode() + result)
                await writer.drain()
        except Exception:
            pass
        finally:
            writer.close()

    fixed_port = os.environ.get('FIOS_PLATFORM_MOCK_PORT')
    if fixed_port is not None:
        assert fixed_port.isascii() and fixed_port.isdecimal() and 49152 <= int(fixed_port) <= 65535
    api = await asyncio.start_server(http, '127.0.0.1', int(fixed_port) if fixed_port is not None else 0, limit=16385)
    port = api.sockets[0].getsockname()[1]
    endpoint_hash = hashlib.sha256(('http://127.0.0.1:' + str(port) + '/v1').encode()).hexdigest()
    control = await asyncio.start_unix_server(observe, path, limit=65540)
    os.chmod(path, 0o600)
    print(json.dumps({'port': port}), flush=True)
    reader = asyncio.StreamReader()
    transport, _ = await asyncio.get_running_loop().connect_read_pipe(lambda: asyncio.StreamReaderProtocol(reader), sys.stdin.buffer)
    try:
        await reader.read(1)
    finally:
        transport.close()
        api.close()
        control.close()
        await api.wait_closed()
        await control.wait_closed()
        os.unlink(path)


try:
    asyncio.run(main())
except Exception:
    sys.stderr.write('mock native fixture failed\n')
    raise SystemExit(1) from None
