"""Immutable image entry point. Execute ONLY inside the approved hardened sandbox.

No listener/network client, host paths, credentials, runtime access or tools.
All frames are untrusted job-scoped data, never management authorization.
"""
import base64
import ctypes
import hashlib
import json
import os
import selectors
import signal
import socket
import struct
import subprocess
import sys
import time
import uuid

MAX_FRAME = 65536


def pairs(items):
    result = {}
    for key, value in items:
        if key in result:
            raise ValueError('invalid_frame')
        result[key] = value
    return result


def decode(data):
    if not 0 < len(data) <= MAX_FRAME:
        raise ValueError('invalid_frame')
    value = json.loads(data, object_pairs_hook=pairs,
                       parse_constant=lambda _: (_ for _ in ()).throw(ValueError('invalid_frame')))
    if not isinstance(value, dict) or type(value.get('version')) is not int or value['version'] != 1:
        raise ValueError('invalid_frame')
    return value


def exact(value, fields):
    if set(value) != {'version', 'type', *fields}:
        raise ValueError('invalid_frame')


def encode(value):
    body = json.dumps({'version': 1, **value}, separators=(',', ':'), ensure_ascii=True).encode()
    if not 0 < len(body) <= MAX_FRAME:
        raise ValueError('output_limit')
    return struct.pack('!I', len(body)) + body


def emit(value):
    data = encode(value)
    offset = 0
    end = time.monotonic() + 2
    selector = selectors.DefaultSelector()
    try:
        selector.register(1, selectors.EVENT_WRITE)
        while offset < len(data):
            if time.monotonic() >= end or not selector.select(max(0, end - time.monotonic())):
                raise ValueError('backpressure')
            try:
                offset += os.write(1, data[offset:])
            except BlockingIOError:
                continue
    finally:
        selector.close()


def input_frame(end):
    data = bytearray()
    size = 4
    selector = selectors.DefaultSelector()
    try:
        selector.register(0, selectors.EVENT_READ)
        while len(data) < size:
            if time.monotonic() >= end or not selector.select(max(0, end - time.monotonic())):
                raise ValueError('input_deadline')
            block = os.read(0, size - len(data))
            if not block:
                raise ValueError('owner_gone')
            data.extend(block)
            if size == 4 and len(data) == 4:
                length = struct.unpack('!I', data)[0]
                if not 0 < length <= MAX_FRAME:
                    raise ValueError('invalid_frame')
                size += length
        return decode(data[4:])
    finally:
        selector.close()


def utf16(text):
    return len(text.encode('utf-16-le')) // 2


def hardened_runtime():
    status = {}
    with open('/proc/self/status', encoding='ascii') as source:
        for line in source:
            if ':' in line:
                key, value = line.split(':', 1)
                status[key] = value.strip()
    if (int(status.get('CapEff', '1'), 16) != 0 or int(status.get('CapBnd', '1'), 16) != 0
            or status.get('NoNewPrivs') != '1' or set(os.listdir('/sys/class/net')) != {'lo'}
            or not os.statvfs('/').f_flag & os.ST_RDONLY):
        return False
    def value(name):
        with open('/sys/fs/cgroup/' + name, encoding='ascii') as source:
            return source.read().strip()
    quota, period = value('cpu.max').split()
    if (not (512 << 20) <= int(value('memory.max')) <= (2 << 30)
            or int(value('memory.swap.max')) != 0 or not 1 <= int(value('pids.max')) <= 64
            or not 0 < int(quota) <= 2 * int(period)):
        return False
    mounts = {}
    with open('/proc/self/mountinfo', encoding='utf-8') as source:
        for line in source:
            left, right = line.split(' - ', 1)
            mounts[left.split()[4]] = right.split()[0]
    return (mounts.get('/workspace') == 'tmpfs' and mounts.get('/tmp') == 'tmpfs'
            and not os.path.exists('/var/run/docker.sock') and not os.path.exists('/run/docker.sock'))


def seal_control_descriptors():
    # Task and runner share a nonroot UID. Without dumpability protection,
    # task code can reopen /proc/1/fd/0 or1 and forge the host-facing channel.
    # The manager still treats ALL container output as untrusted scoped data.
    library = ctypes.CDLL(None, use_errno=True)
    function = library.prctl
    function.argtypes = [ctypes.c_int, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong]
    function.restype = ctypes.c_int
    return function(4, 0, 0, 0, 0) == 0 and function(3, 0, 0, 0, 0) == 0


def main():
    # Guard against an accidental developer invocation outside a container.
    if not os.path.exists('/.dockerenv') or os.getuid() != 65532:
        return 2
    os.set_blocking(1, False)
    process = None
    rpc = None
    try:
        if not hardened_runtime() or not seal_control_descriptors():
            raise ValueError('unsafe_runtime')
        began = time.monotonic()
        begin = input_frame(began + 10)
        exact(begin, {'length', 'sha256', 'deadline'})
        size, digest, deadline = begin['length'], begin['sha256'], begin['deadline']
        wall = int(time.time() * 1000)
        if (begin['type'] != 'input.begin' or type(size) is not int or not 0 <= size <= 4 << 20
                or not isinstance(digest, str) or len(digest) != 64 or any(c not in '0123456789abcdef' for c in digest)
                or type(deadline) is not int or not wall < deadline <= wall + 1800000):
            raise ValueError('invalid_frame')
        source = bytearray()
        index = 0
        while True:
            value = input_frame(began + 10)
            if value['type'] == 'input.end':
                exact(value, set())
                break
            exact(value, {'index', 'data'})
            if value['type'] != 'input.chunk' or type(value['index']) is not int or value['index'] != index:
                raise ValueError('invalid_frame')
            encoded = value['data']
            if not isinstance(encoded, str) or len(encoded) > 43692:
                raise ValueError('invalid_frame')
            block = base64.b64decode(encoded, validate=True)
            if not block or len(block) > 32768 or base64.b64encode(block).decode() != encoded or len(source) + len(block) > size:
                raise ValueError('invalid_frame')
            source.extend(block)
            index += 1
        if len(source) != size or hashlib.sha256(source).hexdigest() != digest:
            raise ValueError('input_hash')
        source.decode('utf-8')
        path = '/workspace/task-' + str(uuid.uuid4()) + '.py'
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        with os.fdopen(fd, 'wb') as output:
            output.write(source)
        source.clear()
        rpc, child_rpc = socket.socketpair()
        process = subprocess.Popen([sys.executable, '-I', '-B', path], stdin=subprocess.DEVNULL,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, close_fds=True,
                                   pass_fds=(child_rpc.fileno(),), start_new_session=True,
                                   env={'PATH': '/opt/venv/bin:/usr/bin:/bin', 'LANG': 'C',
                                        'FIOS_MODEL_FD': str(child_rpc.fileno())})
        child_rpc.close()
        rpc.setblocking(False)
        selector = selectors.DefaultSelector()
        for fd, name in ((0, 'host'), (process.stdout.fileno(), 'stdout'),
                         (process.stderr.fileno(), 'stderr'), (rpc.fileno(), 'rpc')):
            os.set_blocking(fd, False)
            selector.register(fd, selectors.EVENT_READ, name)
        buffers = {'host': bytearray(), 'rpc': bytearray()}
        open_outputs = {'stdout', 'stderr'}
        pending = None
        rpc_open = True
        used_ids = set()
        export_ids, acknowledged = set(), set()
        artifact = None
        model_units = request_units = output_bytes = output_index = 0
        lease = time.monotonic() + 30
        while True:
            now, current_wall = time.monotonic(), int(time.time() * 1000)
            if now >= lease or now >= began + 1800 or current_wall >= deadline or current_wall < wall:
                raise ValueError('lease_expired')
            wall = current_wall
            if artifact is not None and now >= artifact['deadline']:
                raise ValueError('artifact_deadline')
            if process.poll() is not None and not open_outputs and not rpc_open:
                if artifact is not None:
                    raise ValueError('invalid_frame')
                emit({'type': 'done', 'status': 'complete' if process.returncode == 0 else 'failed',
                      'exit_code': process.returncode, 'output_bytes': output_bytes})
                return 0
            for key, _ in selector.select(0.1):
                name = key.data
                try:
                    block = os.read(key.fd, 32768)
                except ConnectionResetError:
                    if name != 'rpc':
                        raise
                    block = b''
                if not block:
                    selector.unregister(key.fd)
                    if name == 'rpc':
                        rpc_open = False
                        if buffers['rpc']:
                            raise ValueError('invalid_frame')
                        if pending is not None:
                            emit({'type': 'model.cancel', 'id': pending})
                    if name == 'host':
                        raise ValueError('owner_gone')
                    open_outputs.discard(name)
                    continue
                if name in ('stdout', 'stderr'):
                    output_bytes += len(block)
                    if output_bytes > 16 << 20:
                        raise ValueError('output_limit')
                    emit({'type': 'output', 'stream': name, 'index': output_index,
                          'data': base64.b64encode(block).decode()})
                    output_index += 1
                    continue
                buffer = buffers[name]
                buffer.extend(block)
                if len(buffer) > 131072:
                    raise ValueError('invalid_frame')
                while len(buffer) >= 4:
                    length = struct.unpack('!I', buffer[:4])[0]
                    if not 0 < length <= MAX_FRAME:
                        raise ValueError('invalid_frame')
                    if len(buffer) < length + 4:
                        break
                    value = decode(buffer[4:4 + length])
                    del buffer[:4 + length]
                    kind = value['type']
                    if name == 'rpc' and kind.startswith('artifact.'):
                        ident = value.get('id')
                        if not isinstance(ident, str) or str(uuid.UUID(ident)) != ident or pending is not None:
                            raise ValueError('invalid_frame')
                        if kind == 'artifact.begin':
                            exact(value, {'id', 'length', 'sha256'})
                            length, digest = value['length'], value['sha256']
                            if (artifact is not None or ident in export_ids or len(export_ids) >= 256
                                    or type(length) is not int or not 0 <= length <= (16 << 20) - output_bytes
                                    or not isinstance(digest, str) or len(digest) != 64
                                    or any(c not in '0123456789abcdef' for c in digest)):
                                raise ValueError('invalid_frame')
                            export_ids.add(ident)
                            output_bytes += length
                            artifact = {'id': ident, 'length': length, 'sha256': digest, 'seen': 0,
                                        'index': 0, 'hash': hashlib.sha256(), 'deadline': time.monotonic() + 30}
                        elif kind == 'artifact.chunk':
                            exact(value, {'id', 'index', 'data'})
                            if artifact is None or artifact['id'] != ident or type(value['index']) is not int or value['index'] != artifact['index']:
                                raise ValueError('invalid_frame')
                            encoded = value['data']
                            if not isinstance(encoded, str) or len(encoded) > 43692:
                                raise ValueError('invalid_frame')
                            chunk = base64.b64decode(encoded, validate=True)
                            if (not chunk or len(chunk) > 32768 or base64.b64encode(chunk).decode() != encoded
                                    or artifact['seen'] + len(chunk) > artifact['length']):
                                raise ValueError('invalid_frame')
                            artifact['seen'] += len(chunk)
                            artifact['index'] += 1
                            artifact['hash'].update(chunk)
                        elif kind == 'artifact.end':
                            exact(value, {'id'})
                            if (artifact is None or artifact['id'] != ident or artifact['seen'] != artifact['length']
                                    or artifact['hash'].hexdigest() != artifact['sha256']):
                                raise ValueError('input_hash')
                            artifact = None
                        else:
                            raise ValueError('invalid_frame')
                        emit({k: v for k, v in value.items() if k != 'version'})
                    elif name == 'rpc':
                        exact(value, {'id', 'prompt'})
                        ident, prompt = value['id'], value['prompt']
                        if (kind != 'model.request' or pending is not None or artifact is not None or len(used_ids) >= 4
                                or not isinstance(ident, str) or str(uuid.UUID(ident)) != ident or ident in used_ids
                                or not isinstance(prompt, str) or utf16(prompt) > 128000):
                            raise ValueError('invalid_frame')
                        used_ids.add(ident)
                        pending = ident
                        request_units = 0
                        emit({'type': 'model.request', 'id': ident, 'prompt': prompt})
                    elif kind == 'lease.renew':
                        exact(value, set())
                        if time.monotonic() >= lease:
                            raise ValueError('lease_expired')
                        lease = time.monotonic() + 30
                    elif kind == 'artifact.saved':
                        exact(value, {'id', 'artifact_id'})
                        ident, saved = value['id'], value['artifact_id']
                        if (ident not in export_ids or ident in acknowledged or not isinstance(saved, str)
                                or str(uuid.UUID(saved)) != saved or (artifact is not None and artifact['id'] == ident)):
                            raise ValueError('invalid_frame')
                        acknowledged.add(ident)
                        try:
                            rpc.sendall(encode(value))
                        except (BrokenPipeError, ConnectionResetError):
                            pass
                    else:
                        if value.get('id') != pending or pending is None:
                            raise ValueError('invalid_frame')
                        if kind == 'model.delta':
                            exact(value, {'id', 'content'})
                            if not isinstance(value['content'], str) or utf16(value['content']) > 8192:
                                raise ValueError('invalid_frame')
                            request_units += utf16(value['content'])
                            model_units += utf16(value['content'])
                            if request_units > 64000 or model_units > 256000:
                                raise ValueError('output_limit')
                        elif kind == 'model.done':
                            exact(value, {'id', 'status'})
                            if value['status'] not in ('complete', 'interrupted', 'failed'):
                                raise ValueError('invalid_frame')
                            pending = None
                        else:
                            raise ValueError('invalid_frame')
                        try:
                            rpc.sendall(encode(value))
                        except (BrokenPipeError, ConnectionResetError):
                            pass  # Child abandoned data; never release native ownership here.
    except Exception as error:
        codes = {'invalid_frame', 'input_deadline', 'input_hash', 'owner_gone',
                 'output_limit', 'backpressure', 'lease_expired', 'unsafe_runtime', 'artifact_deadline'}
        code = str(error) if type(error) is ValueError and str(error) in codes else 'task_revoked'
        try:
            emit({'type': 'error', 'code': code})
        except Exception:
            pass
        return 1
    finally:
        if process is not None and process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=1)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=1)
                except (ProcessLookupError, subprocess.TimeoutExpired):
                    pass
        if rpc is not None:
            rpc.close()


if __name__ == '__main__':
    raise SystemExit(main())
