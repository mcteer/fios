# Ordinary model-pipe/artifact task inside a disposable test container.
import base64
import hashlib
import json
import os
import struct
import uuid

fd = int(os.environ['FIOS_MODEL_FD'])


def send(value):
    body = json.dumps({'version': 1, **value}).encode()
    os.write(fd, struct.pack('!I', len(body)) + body)


def read_exact(length):
    result = bytearray()
    while len(result) < length:
        block = os.read(fd, length - len(result))
        assert block
        result.extend(block)
    return result


def receive():
    length = struct.unpack('!I', read_exact(4))[0]
    return json.loads(read_exact(length))


request = str(uuid.uuid4())
send({'type': 'model.request', 'id': request, 'prompt': 'fixture only'})
response = receive()
assert response['type'] == 'model.delta' and response['content'] == 'MOCK_ONLY'
assert receive()['type'] == 'model.done'
artifact = str(uuid.uuid4())
data = b'EXPLICIT_ARTIFACT_ONLY'
send({'type': 'artifact.begin', 'id': artifact, 'length': len(data), 'sha256': hashlib.sha256(data).hexdigest()})
send({'type': 'artifact.chunk', 'id': artifact, 'index': 0, 'data': base64.b64encode(data).decode()})
send({'type': 'artifact.end', 'id': artifact})
saved = receive()
assert saved['type'] == 'artifact.saved' and saved['id'] == artifact
assert str(uuid.UUID(saved['artifact_id'])) == saved['artifact_id']
print('SANDBOX_TASK_PASS')
