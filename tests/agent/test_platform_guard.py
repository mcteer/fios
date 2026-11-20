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


def observation_v2(profile, command, now, phase=None, model=None):
    value=observation(profile,command,now)
    counts={name:0 for name in ('ingress','preparing','queued','active','responding')}
    if phase:counts[phase]=1
    model=model or ('test/model' if phase else 'idle-other/model')
    value.update(version=2,coverage='all_clients',native_sequence=profile.minimum_sequence,
                 native_sampled_at=now,source_age_ms=0,activity=('active' if phase in ('active','responding') else phase or 'idle'),
                 resident_model=model,outstanding_owners=int(phase is not None),loading=False,transitioning=False,
                 counts=counts,unattributed_counts={name:0 for name in counts},
                 models=[{'model':model,'resident':True,'counts':dict(counts)}],reason='none',
                 resources={'sampled_at':now,'pressure':'normal','thermal':'nominal'},
                 services={'mlx':'ready','orbstack':'ready'},
                 local_ownership={'unresolved_count':int(phase is not None),'uncertain':False,'blocked':False})
    return value


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

    def test_current_v2_manager_activity_and_source_sequence(self):
        for phase in (None,'queued','active','responding'):
            with self.subTest(phase=phase):
                value=observation_v2(self.profile,self.command,self.now,phase)
                value['sequence']=1
                value['native_sequence']=7
                validate_observation(value,replace(self.profile,minimum_sequence=7),self.command,self.now)
        busy=observation_v2(self.profile,self.command,self.now,'active','other/model')
        with self.assertRaises(NativeGuardError):validate_observation(busy,self.profile,self.command,self.now)

    def test_v2_busy_does_not_refresh_independent_resource_time(self):
        busy = observation_v2(self.profile, self.command, self.now, 'responding')
        for offset, accepted in [(-5000, True), (-5001, False), (1000, True), (1001, False)]:
            with self.subTest(offset=offset):
                value = {**busy, 'resources': {**busy['resources'], 'sampled_at': self.now + offset}}
                if accepted:
                    validate_observation(value, self.profile, self.command, self.now)
                else:
                    with self.assertRaises(NativeGuardError):
                        validate_observation(value, self.profile, self.command, self.now)

    def test_v2_busy_allows_explicit_unknown_resource_context(self):
        busy = observation_v2(self.profile, self.command, self.now, 'responding')
        busy['resources'] = {'sampled_at': None, 'pressure': 'unknown', 'thermal': 'unknown'}
        validate_observation(busy, self.profile, self.command, self.now)
        busy['resources']['sampled_at'] = self.now - 5001
        with self.assertRaises(NativeGuardError):
            validate_observation(busy, self.profile, self.command, self.now)

    def test_v2_unknown_conflicts_and_malformed_refuse(self):
        import copy
        original=observation_v2(self.profile,self.command,self.now)
        mutations=[{'coverage':'unknown'},{'activity':'unknown'},{'version':True},{'native_sequence':None},
                   {'native_sequence':0},{'native_sampled_at':self.now-5001},{'source_age_ms':True},
                   {'source_age_ms':1},{'native_sampled_at':self.now+1001},{'transitioning':True},
                   {'loading':True},{'reason':'source_unknown'},{'outstanding_owners':1},
                   {'counts':{**original['counts'],'active':1}},
                   {'unattributed_counts':{**original['counts'],'ingress':1}},
                   {'models':original['models']*2},
                   {'local_ownership':{'unresolved_count':1,'uncertain':True,'blocked':False}},
                   {'local_ownership':{'unresolved_count':1,'uncertain':False,'blocked':True}},
                   {'resources':{'sampled_at':None,'pressure':'normal','thermal':'nominal'}}]
        for changes in mutations:
            with self.subTest(changes=changes),self.assertRaises(NativeGuardError):
                validate_observation({**copy.deepcopy(original),**changes},self.profile,self.command,self.now)

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

    async def test_real_v2_unix_envelope_matches_current_frame(self):
        with tempfile.TemporaryDirectory(prefix='fg-') as directory:
            path=directory+'/observe.sock';mode=['healthy']
            async def respond(reader,writer):
                size=struct.unpack('!I',await reader.readexactly(4))[0]
                request=json.loads(await reader.readexactly(size))
                inner=observation_v2(self.profile,self.command,int(time.time()*1000),'queued')
                outer={'version':1,'id':request['id'],'ok':True,'epoch':self.command.epoch,
                       'coverage':'all_clients','activity':'queued','observation':inner}
                if mode[0]=='state':outer['activity']='idle'
                if mode[0]=='coverage':outer['coverage']='supported'
                if mode[0]=='unknown':inner['activity']='unknown';outer['activity']='unknown'
                if mode[0]=='native_sequence':inner['native_sequence']=0
                body=json.dumps(outer).encode();writer.write(struct.pack('!I',len(body))+body)
                await writer.drain();writer.close();await writer.wait_closed()
            server=await asyncio.start_unix_server(respond,path);os.chmod(path,0o600)
            try:
                profile=replace(self.profile,path=path)
                result=await query_observation(profile,self.command)
                validate_observation(result,profile,self.command,int(time.time()*1000))
                for refusal in ('state','coverage','unknown','native_sequence'):
                    mode[0]=refusal
                    with self.subTest(mode=refusal),self.assertRaises(NativeGuardError):
                        await query_observation(profile,self.command)
            finally:
                server.close();await server.wait_closed()

    async def test_socket_symlink_refused(self):
        with tempfile.TemporaryDirectory(prefix='fg-') as directory:
            path = directory + '/observe.sock'
            os.symlink('/dev/null', path)
            with self.assertRaises(NativeGuardError):
                await query_observation(replace(self.profile, path=path), self.command)
