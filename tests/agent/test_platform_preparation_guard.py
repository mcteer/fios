import asyncio
from dataclasses import replace
import os,struct,tempfile,time,unittest,json
from unittest.mock import patch
from fios_agent.platform_guard import (GuardProfile,NativeGuardError,bound_preparation_root,
    validate_preparation_observation,query_preparation)
from fios_agent.platform_protocol import request_correlation_id
from test_platform_guard import guard_environment,guard_command

class PreparationGuardTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.command=guard_command();self.now=int(time.time()*1000)
        self.env={**guard_environment(),'FIOS_PLATFORM_NATIVE_EPOCH':'1'*32,
            'FIOS_PLATFORM_PREPARATION_ROOT':'18446744073709551615',
            'FIOS_PLATFORM_PREPARATION_CORRELATION':request_correlation_id(self.command)}
        with patch.dict(os.environ,self.env,clear=True):self.profile=GuardProfile.from_environment()
        self.root=self.env['FIOS_PLATFORM_PREPARATION_ROOT']
    def observation(self):
        return preparation_observation(self.profile,self.command,self.root,self.now)
    def test_original_scope_and_nonrenewable_lease(self):
        with patch.dict(os.environ,self.env,clear=True):
            self.assertEqual(bound_preparation_root(self.command,self.profile.native_epoch),self.root)
        value=self.observation()
        validate_preparation_observation(value,self.profile,self.command,self.root,self.now)
        for changes in ({'root_sequence':'1'},{'job_id':'00000000-0000-4000-8000-000000000003'},
            {'attempt':True},{'attempt':1},{'correlation_id':'f'*64},{'source_coverage':'unknown'},
            {'native_epoch':'2'*32},{'canonical_model':'other/model'},{'native_model':'other/model'},
            {'lineage_sequence':2},{'native_sequence':3},{'reservation_sequence':0},
            {'source_sampled_at':self.now+1},{'lease_requested_at':self.now+1},
            {'lease_expires_at':self.now},{'lease_expires_at':self.now+5000},
            {'registry_generation':True},{'registry_ready_model':''}):
            with self.subTest(changes=changes),self.assertRaises(NativeGuardError):
                validate_preparation_observation({**value,**changes},self.profile,self.command,self.root,self.now)
        with self.assertRaises(NativeGuardError):
            validate_preparation_observation(value,self.profile,self.command,self.root,value['lease_expires_at'])
    def test_root_metadata_never_downgrades_or_renews(self):
        cases=[{'FIOS_PLATFORM_PREPARATION_ROOT':v} for v in ('0','01','18446744073709551616','-1','')]
        cases += [{'FIOS_PLATFORM_PREPARATION_CORRELATION':'f'*64},
                  {'FIOS_PLATFORM_HANDOFF_ROOT':'1'},{'FIOS_PLATFORM_HANDOFF_CORRELATION':'f'*64}]
        for change in cases:
            with self.subTest(change=change),patch.dict(os.environ,{**self.env,**change},clear=True),self.assertRaises(NativeGuardError):
                bound_preparation_root(self.command,self.profile.native_epoch)
        for missing in ('FIOS_PLATFORM_PREPARATION_ROOT','FIOS_PLATFORM_PREPARATION_CORRELATION'):
            with patch.dict(os.environ,{k:v for k,v in self.env.items() if k!=missing},clear=True),self.assertRaises(NativeGuardError):
                bound_preparation_root(self.command,self.profile.native_epoch)
    async def test_private_original_scope_query_without_activity_fallback(self):
        with tempfile.TemporaryDirectory(prefix='fg-') as directory:
            path=directory+'/observe.sock';seen=[];mode=['healthy']
            async def respond(reader,writer):
                n=struct.unpack('!I',await reader.readexactly(4))[0];request=json.loads(await reader.readexactly(n));seen.append(request)
                result={'version':1,'id':request['id'],'ok':True,'epoch':self.command.epoch,'preparation':self.observation()}
                if mode[0]=='unknown':result['preparation']=None
                if mode[0]=='root':result['preparation']['root_sequence']='1'
                body=json.dumps(result).encode();writer.write(struct.pack('!I',len(body))+body)
                await writer.drain();writer.close();await writer.wait_closed()
            server=await asyncio.start_unix_server(respond,path);os.chmod(path,0o600)
            try:
                profile=replace(self.profile,path=path)
                result=await query_preparation(profile,self.command,self.root)
                self.assertEqual(result['root_sequence'],self.root)
                for refusal in ('unknown','root'):
                    mode[0]=refusal
                    with self.assertRaises(NativeGuardError):await query_preparation(profile,self.command,self.root)
                self.assertEqual(len(seen),3)
                for request in seen:
                    self.assertEqual(request['operation'],'preparation')
                    self.assertEqual(request['payload'],{'job_id':self.command.job_id,'attempt':self.command.attempt,
                        'root_sequence':self.root,'correlation_id':request_correlation_id(self.command)})
            finally:server.close();await server.wait_closed()


def preparation_observation(profile,command,root,now):
    return {'version':1,'host':profile.host,'endpoint_hash':command.endpoint_hash,'profile_hash':profile.profile_hash,
        'manager_epoch':command.epoch,'native_epoch':profile.native_epoch,'job_id':command.job_id,'attempt':command.attempt,
        'canonical_model':profile.canonical_model,'native_model':profile.native_model,'root_sequence':root,
        'correlation_id':request_correlation_id(command),'source_coverage':'all_clients',
        'reservation_sequence':2,'lineage_sequence':3,'native_sequence':4,'source_sampled_at':now,
        'lease_requested_at':now-1,'lease_expires_at':now+4999,'registry_generation':0,'registry_ready_model':'other/idle-model'}
