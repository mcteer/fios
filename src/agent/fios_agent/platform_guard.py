"""Read-only, independently validated native activity guard for private workers.

No inference or management operation is issued by this module. The socket and
mapping come only from the enrolled parent environment, never task/model data.
"""
import asyncio
import ctypes
from dataclasses import dataclass
import os
import socket
import stat
import struct
import sys
import time
from uuid import UUID, uuid4

from .platform_protocol import decode_platform_frame


class NativeGuardError(ValueError):
    def __init__(self):
        super().__init__('native_guard_unavailable')


def _integer(value, maximum=9007199254740991):
    return type(value) is int and 0 <= value <= maximum


def _digest(value):
    return isinstance(value, str) and len(value) == 64 and all(c in '0123456789abcdef' for c in value)


@dataclass(frozen=True)
class GuardProfile:
    path: str
    host: str
    profile_hash: str
    native_epoch: str
    minimum_sequence: int
    canonical_model: str
    native_model: str

    @classmethod
    def from_environment(cls):
        try:
            sequence = os.environ['FIOS_PLATFORM_NATIVE_SEQUENCE']
            if not sequence.isascii() or not sequence.isdecimal():
                raise NativeGuardError()
            result = cls(os.environ['FIOS_PLATFORM_GUARD_PATH'], os.environ['FIOS_PLATFORM_HOST_ID'],
                         os.environ['FIOS_PLATFORM_PROFILE_HASH'], os.environ['FIOS_PLATFORM_NATIVE_EPOCH'],
                         int(sequence), os.environ['FIOS_PLATFORM_CANONICAL_MODEL'], os.environ['FIOS_PLATFORM_NATIVE_MODEL'])
            result.validate()
            return result
        except (ValueError, KeyError, UnicodeError):
            raise NativeGuardError() from None

    def validate(self):
        if (not self.path.startswith('/') or not self.path.endswith('/observe.sock')
                or '\0' in self.path or len(self.path.encode()) > 103
                or not 0 < len(self.host) <= 128 or not all(32 < ord(c) < 127 for c in self.host)
                or not _digest(self.profile_hash) or not 0 < len(self.native_epoch.encode()) <= 128
                or not _integer(self.minimum_sequence) or self.minimum_sequence == 0
                or any(not isinstance(model, str) or not 0 < len(model.encode()) <= 1024
                       for model in (self.canonical_model, self.native_model))):
            raise NativeGuardError()


def validate_observation(value, profile, command, now):
    profile.validate()
    fields = {'version', 'host', 'endpoint_hash', 'profile_hash', 'manager_epoch', 'native_epoch',
              'sequence', 'sampled_at', 'coverage', 'resident_model', 'outstanding_owners', 'loading'}
    if not isinstance(value, dict) or set(value) != fields:
        raise NativeGuardError()
    if (not _integer(value['version']) or value['version'] != 1
            or value['host'] != profile.host or value['endpoint_hash'] != command.endpoint_hash
            or value['profile_hash'] != profile.profile_hash or value['manager_epoch'] != command.epoch
            or value['native_epoch'] != profile.native_epoch or command.model != profile.native_model
            or not _integer(value['sequence']) or value['sequence'] < profile.minimum_sequence
            or not _integer(now) or not _integer(value['sampled_at'])
            or not -1000 <= now - value['sampled_at'] <= 5000
            or value['coverage'] != 'supported' or not _integer(value['outstanding_owners'], 2147483647)
            or type(value['loading']) is not bool or value['loading']):
        raise NativeGuardError()
    resident = value['resident_model']
    if resident is not None and (not isinstance(resident, str) or not 0 < len(resident.encode()) <= 1024):
        raise NativeGuardError()
    if value['outstanding_owners'] and resident != profile.canonical_model:
        raise NativeGuardError()
    # Idle resident replacement is allowed. Native in-use protection must
    # independently close the race after this advisory observation.


def _peer_uid(stream):
    if sys.platform == 'darwin':
        library = ctypes.CDLL(None, use_errno=True)
        uid, gid = ctypes.c_uint(), ctypes.c_uint()
        function = library.getpeereid
        function.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_uint), ctypes.POINTER(ctypes.c_uint)]
        function.restype = ctypes.c_int
        if function(stream.fileno(), ctypes.byref(uid), ctypes.byref(gid)) != 0:
            raise NativeGuardError()
        return uid.value
    if sys.platform == 'linux':
        return struct.unpack('3i', stream.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))[1]
    raise NativeGuardError()


async def query_observation(profile, command):
    writer = None
    try:
        info = os.lstat(profile.path)
        parent = os.lstat(os.path.dirname(profile.path))
        if (not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.geteuid() or info.st_mode & 0o077
                or not stat.S_ISDIR(parent.st_mode) or parent.st_uid != os.geteuid() or parent.st_mode & 0o077):
            raise NativeGuardError()
        async with asyncio.timeout(2):
            reader, writer = await asyncio.open_unix_connection(profile.path, limit=65540)
            if _peer_uid(writer.get_extra_info('socket')) != os.geteuid():
                raise NativeGuardError()
            identifier = str(uuid4())
            request = json_bytes({'version': 1, 'id': identifier, 'operation': 'activity', 'payload': {}})
            writer.write(struct.pack('!I', len(request)) + request)
            await writer.drain()
            size = struct.unpack('!I', await reader.readexactly(4))[0]
            if not 0 < size <= 65536:
                raise NativeGuardError()
            response = decode_platform_frame(await reader.readexactly(size))
            if (not isinstance(response, dict) or set(response) != {'version', 'id', 'ok', 'epoch', 'coverage', 'activity', 'observation'}
                    or type(response['version']) is not int or response['version'] != 1
                    or response['id'] != identifier or response['ok'] is not True or response['epoch'] != command.epoch
                    or response['coverage'] != 'supported' or response['activity'] not in ('idle', 'busy')):
                raise NativeGuardError()
            return response['observation']
    except (OSError, ValueError, TimeoutError, asyncio.IncompleteReadError, UnicodeError):
        raise NativeGuardError() from None
    finally:
        if writer:
            writer.close()
            try:
                async with asyncio.timeout(0.1):
                    await writer.wait_closed()
            except (OSError, TimeoutError):
                pass


def json_bytes(value):
    import json
    return json.dumps(value, separators=(',', ':')).encode()


async def check_native_guard(command):
    try:
        profile = GuardProfile.from_environment()
        value = await query_observation(profile, command)
        validate_observation(value, profile, command, int(time.time() * 1000))
    except (ValueError, TypeError, KeyError, UnicodeError):
        raise NativeGuardError() from None
