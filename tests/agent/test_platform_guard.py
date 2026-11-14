import asyncio
from dataclasses import replace
import hashlib
import json
import os
import struct
import tempfile
import time
import unittest
from unittest.mock import patch
from uuid import uuid4

from fios_agent.platform_protocol import parse_platform_command
from fios_agent.platform_guard import GuardProfile, NativeGuardError, validate_observation, query_observation


def guard_environment(model='test/model'):
    return {'FIOS_PLATFORM_GUARD_PATH': '/fixture/observe.sock', 'FIOS_PLATFORM_HOST_ID': 'fixture-host',
            'FIOS_PLATFORM_PROFILE_HASH': 'f' * 64, 'FIOS_PLATFORM_NATIVE_EPOCH': 'native-fixture-one',
            'FIOS_PLATFORM_NATIVE_SEQUENCE': '1', 'FIOS_PLATFORM_CANONICAL_MODEL': model,
            'FIOS_PLATFORM_NATIVE_MODEL': model}


def guard_command():
    return parse_platform_command({'v': 1, 'type': 'run', 'job_id': str(uuid4()), 'attempt': 0, 'epoch': str(uuid4()),
        'model': 'test/model', 'endpoint_hash': hashlib.sha256(b'http://127.0.0.1:1/v1').hexdigest(),
        'expires_at': int(time.time() * 1000) + 5000, 'context': [{'role': 'user', 'content': 'fixture only'}]})


def observation(profile, command, now):
    return {'version': 1, 'host': profile.host, 'profile_hash': profile.profile_hash,
            'endpoint_hash': command.endpoint_hash, 'manager_epoch': command.epoch, 'native_epoch': profile.native_epoch,
            'sequence': profile.minimum_sequence, 'sampled_at': now, 'coverage': 'supported',
            'resident_model': 'idle-other/model', 'outstanding_owners': 0, 'loading': False}


class PlatformGuardTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        with patch.dict(os.environ, guard_environment()):
            self.profile = GuardProfile.from_environment()
        self.command = guard_command()
        self.now = int(time.time() * 1000)

    def test_idle_replacement_and_same_model_overlap(self):
        value = observation(self.profile, self.command, self.now)
        validate_observation(value, self.profile, self.command, self.now)
        value.update(resident_model='test/model', outstanding_owners=2)
        validate_observation(value, self.profile, self.command, self.now)

    def test_unknown_busy_loading_and_malformed_reject(self):
        for changes in ({'coverage': 'unsupported'}, {'coverage': 'unknown'}, {'outstanding_owners': True},
                        {'outstanding_owners': -1}, {'outstanding_owners': 2147483648}, {'loading': True},
                        {'resident_model': None, 'outstanding_owners': 1}, {'outstanding_owners': 1},
                        {'version': True}, {'sequence': 0}, {'sampled_at': self.now - 5001},
                        {'sampled_at': self.now + 1001}, {'host': 'other'}, {'profile_hash': '0' * 64},
                        {'native_epoch': 'other'}, {'manager_epoch': str(uuid4())}, {'endpoint_hash': '0' * 64}):
            with self.assertRaises(NativeGuardError):
                validate_observation({**observation(self.profile, self.command, self.now), **changes}, self.profile, self.command, self.now)

    def test_exact_peer_mapping_no_suffix_stripping(self):
        profile = replace(self.profile, canonical_model='test/model@studio-a')
        value = observation(profile, self.command, self.now)
        value.update(resident_model='test/model@studio-a', outstanding_owners=1)
        validate_observation(value, profile, self.command, self.now)
        value['resident_model'] = 'test/model'
        with self.assertRaises(NativeGuardError):
            validate_observation(value, profile, self.command, self.now)

    def test_regressing_sequence_rejects(self):
        value = observation(self.profile, self.command, self.now)
        with self.assertRaises(NativeGuardError):
            validate_observation(value, replace(self.profile, minimum_sequence=2), self.command, self.now)

    def test_missing_or_invalid_enrollment_rejects(self):
        for env in ({}, {**guard_environment(), 'FIOS_PLATFORM_GUARD_PATH': '/fixture/control.sock'},
                    {**guard_environment(), 'FIOS_PLATFORM_PROFILE_HASH': 'unknown'},
                    {**guard_environment(), 'FIOS_PLATFORM_NATIVE_SEQUENCE': '-1'}):
            with patch.dict(os.environ, env, clear=True), self.assertRaises(NativeGuardError):
                GuardProfile.from_environment()

    async def test_real_private_unix_peer_and_correlated_observation(self):
        with tempfile.TemporaryDirectory(prefix='fg-') as directory:
            path = directory + '/observe.sock'
            async def respond(reader, writer):
                size = struct.unpack('!I', await reader.readexactly(4))[0]
                request = json.loads(await reader.readexactly(size))
                self.assertEqual(request['operation'], 'activity')
                self.assertEqual(request['payload'], {})
                profile = replace(self.profile, path=path)
                result = {'version': 1, 'id': request['id'], 'ok': True, 'epoch': self.command.epoch,
                          'coverage': 'supported', 'activity': 'idle', 'observation': observation(profile, self.command, self.now)}
                body = json.dumps(result).encode()
                writer.write(struct.pack('!I', len(body)) + body)
                await writer.drain()
                writer.close()
                await writer.wait_closed()
            server = await asyncio.start_unix_server(respond, path)
            os.chmod(path, 0o600)
            try:
                profile = replace(self.profile, path=path)
                result = await query_observation(profile, self.command)
                validate_observation(result, profile, self.command, self.now)
            finally:
                server.close()
                await server.wait_closed()

    async def test_socket_symlink_refused(self):
        with tempfile.TemporaryDirectory(prefix='fg-') as directory:
            path = directory + '/observe.sock'
            os.symlink('/dev/null', path)
            with self.assertRaises(NativeGuardError):
                await query_observation(replace(self.profile, path=path), self.command)
