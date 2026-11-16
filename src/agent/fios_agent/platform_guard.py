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

from .platform_protocol import decode_platform_frame, request_correlation_id


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


def _model(value):
    try:
        return isinstance(value,str) and 0<len(value.encode('utf-8'))<=1024 and '\0' not in value
    except UnicodeError:
        return False


def _current_observation(value,now):
    # Exact current manager frame. These checks preserve its independent
    # all-client ceiling; they cannot raise an unknown export into eligibility.
    legacy={'version','host','endpoint_hash','profile_hash','manager_epoch','native_epoch',
            'sequence','sampled_at','coverage','resident_model','outstanding_owners','loading'}
    fields=legacy|{'native_sequence','native_sampled_at','source_age_ms','activity','counts','unattributed_counts',
                   'models','transitioning','reason','resources','services','local_ownership'}
    if (set(value)!=fields or type(value['version']) is not int or value['version']!=2
            or value['coverage']!='all_clients' or value['activity'] not in ('idle','queued','active')
            or value['reason']!='none' or value['loading'] is not False or value['transitioning'] is not False
            or not _integer(now) or not _integer(value['sequence']) or value['sequence']==0
            or not _integer(value['native_sequence']) or value['native_sequence']==0
            or not _integer(value['sampled_at']) or not _integer(value['native_sampled_at'])
            or not -1000<=now-value['native_sampled_at']<=5000
            or type(value['source_age_ms']) is not int
            or value['source_age_ms']!=value['sampled_at']-value['native_sampled_at']
            or value['source_age_ms']< -1000):
        raise NativeGuardError()
    names={'ingress','preparing','queued','active','responding'}
    def counts(v):
        if not isinstance(v,dict) or set(v)!=names or any(not _integer(n,2147483647) for n in v.values()):
            raise NativeGuardError()
        return v
    total=counts(value['counts']);unattributed=counts(value['unattributed_counts'])
    rows=value['models']
    if (not isinstance(rows,list) or len(rows)>64 or any(unattributed.values())
            or total['ingress'] or total['preparing']):raise NativeGuardError()
    identities=set();combined={name:0 for name in names};residents=[];busy=[]
    for row in rows:
        if (not isinstance(row,dict) or set(row)!={'model','resident','counts'} or not _model(row['model'])
                or row['model'] in identities or type(row['resident']) is not bool):raise NativeGuardError()
        identities.add(row['model']);phase=counts(row['counts'])
        for name in names:combined[name]+=phase[name]
        if row['resident']:residents.append(row['model'])
        if any(phase.values()):busy.append(row['model'])
    owners=sum(total.values());resident=residents[0] if residents else None
    expected='active' if total['active'] or total['responding'] else 'queued' if total['queued'] else 'idle'
    if (combined!=total or owners>2147483647 or len(residents)>1 or len(busy)>1
            or (busy and residents and busy[0]!=resident) or value['resident_model']!=resident
            or not _integer(value['outstanding_owners'],2147483647) or value['outstanding_owners']!=owners
            or value['activity']!=expected):raise NativeGuardError()
    local=value['local_ownership'];resources=value['resources'];services=value['services']
    if (not isinstance(local,dict) or set(local)!={'unresolved_count','uncertain','blocked'}
            or not _integer(local['unresolved_count'],32) or local['uncertain'] is not False or local['blocked'] is not False
            or (local['unresolved_count']>0 and expected=='idle')
            or not isinstance(resources,dict) or set(resources)!={'sampled_at','pressure','thermal'}
            or resources['pressure'] not in ('normal','warning','critical','unknown')
            or resources['thermal'] not in ('nominal','fair','serious','critical','unknown')
            or (resources['sampled_at'] is not None and not _integer(resources['sampled_at']))
            or (resources['sampled_at'] is None and (resources['pressure']!='unknown' or resources['thermal']!='unknown'))
            or not isinstance(services,dict) or set(services)!={'mlx','orbstack'}
            or any(v not in ('starting','ready','waiting_session','waiting_credentials','stopped','degraded','unknown') for v in services.values())):
        raise NativeGuardError()
    # The trusted parent's minimum is a native-source sequence, not the
    # independent manager/control export sequence. Keep the two clocks distinct.
    result={key:value[key] for key in legacy}
    result.update(version=1,coverage='supported',sequence=value['native_sequence'],
                  resident_model=busy[0] if busy else resident)
    return result


def validate_observation(value, profile, command, now):
    profile.validate()
    if isinstance(value,dict) and type(value.get('version')) is int and value['version']==2:
        value=_current_observation(value,now)
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


async def _query_guard(profile, command, operation, payload):
    writer = None
    try:
        profile.validate()
        if operation not in ('activity','preparation') or not isinstance(payload,dict):raise NativeGuardError()
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
            request = json_bytes({'version': 1, 'id': identifier, 'operation': operation, 'payload': payload})
            if len(request)>1024:raise NativeGuardError()
            writer.write(struct.pack('!I', len(request)) + request)
            await writer.drain()
            size = struct.unpack('!I', await reader.readexactly(4))[0]
            if not 0 < size <= 65536:
                raise NativeGuardError()
            response = decode_platform_frame(await reader.readexactly(size))
            if (not isinstance(response,dict) or not {'version','id','ok','epoch'}.issubset(response)
                    or type(response['version']) is not int or response['version']!=1
                    or response['id']!=identifier or response['ok'] is not True or response['epoch']!=command.epoch):
                raise NativeGuardError()
            return response
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


async def query_observation(profile, command):
    response=await _query_guard(profile,command,'activity',{})
    if (set(response)!={'version','id','ok','epoch','coverage','activity','observation'}
            or not isinstance(response['observation'],dict)):raise NativeGuardError()
    current=response['observation'].get('version')==2
    if current:
        if (response['coverage']!='all_clients' or response['activity']!=response['observation'].get('activity')
                or response['activity'] not in ('idle','queued','active')):raise NativeGuardError()
    elif response['coverage']!='supported' or response['activity'] not in ('idle','busy'):
        raise NativeGuardError()
    validate_observation(response['observation'],profile,command,int(time.time()*1000))
    return response['observation']


def json_bytes(value):
    import json
    return json.dumps(value, separators=(',', ':')).encode()


async def check_native_guard(command):
    try:
        profile = GuardProfile.from_environment()
        value = await query_observation(profile, command)
        validate_observation(value, profile, command, int(time.time() * 1000))
        return profile.native_epoch
    except (ValueError, TypeError, KeyError, UnicodeError):
        raise NativeGuardError() from None


def _root(value):
    return (isinstance(value,str) and 1<=len(value)<=20 and value[0]!='0'
            and value.isascii() and value.isdecimal() and int(value)<=18446744073709551615)


def _instance(value):
    return (isinstance(value,str) and len(value)==32 and all(c in '0123456789abcdef' for c in value)
            and int(value,16)!=0)


def _bound_root(command,native_epoch,kind):
    root=os.environ.get('FIOS_PLATFORM_'+kind+'_ROOT')
    correlation=os.environ.get('FIOS_PLATFORM_'+kind+'_CORRELATION')
    other='PREPARATION' if kind=='HANDOFF' else 'HANDOFF'
    competing=any(os.environ.get('FIOS_PLATFORM_'+other+'_'+name) is not None for name in ('ROOT','CORRELATION'))
    if kind=='HANDOFF' and competing:raise NativeGuardError()
    if root is None and correlation is None:return None
    try:
        profile=GuardProfile.from_environment()
        if (competing or not _root(root) or not _digest(correlation) or correlation!=request_correlation_id(command)
                or profile.native_epoch!=native_epoch or not _instance(native_epoch)
                or profile.native_model!=command.model):raise NativeGuardError()
        return root
    except (ValueError,TypeError,KeyError,UnicodeError):raise NativeGuardError() from None


def bound_handoff_root(command,native_epoch):
    return _bound_root(command,native_epoch,'HANDOFF')


def bound_preparation_root(command,native_epoch):
    return _bound_root(command,native_epoch,'PREPARATION')


def validate_preparation_observation(value,profile,command,root,now):
    # Original-scope advisory evidence only. Native atomic consumption remains
    # mandatory. A global unknown/preparing activity frame cannot stand in for it.
    profile.validate()
    fields={'version','host','endpoint_hash','profile_hash','manager_epoch','native_epoch','job_id','attempt',
            'canonical_model','native_model','root_sequence','correlation_id','source_coverage',
            'reservation_sequence','lineage_sequence','native_sequence','source_sampled_at',
            'lease_requested_at','lease_expires_at','registry_generation','registry_ready_model'}
    if (not isinstance(value,dict) or set(value)!=fields or type(value['version']) is not int or value['version']!=1
            or not _instance(profile.native_epoch) or not _root(root) or value['root_sequence']!=root or value['correlation_id']!=request_correlation_id(command)
            or value['host']!=profile.host or value['endpoint_hash']!=command.endpoint_hash
            or value['profile_hash']!=profile.profile_hash or value['manager_epoch']!=command.epoch
            or value['native_epoch']!=profile.native_epoch or value['job_id']!=command.job_id
            or not _integer(value['attempt'],3) or value['attempt']!=command.attempt
            or value['canonical_model']!=profile.canonical_model or value['native_model']!=profile.native_model
            or command.model!=profile.native_model or value['source_coverage']!='all_clients'
            or not _integer(now) or any(not _integer(value[name]) for name in
                ('reservation_sequence','lineage_sequence','native_sequence','source_sampled_at',
                 'lease_requested_at','lease_expires_at','registry_generation'))):raise NativeGuardError()
    start=value['lease_requested_at'];end=value['lease_expires_at'];stamp=value['source_sampled_at']
    if (not 0<value['reservation_sequence']<value['lineage_sequence']<value['native_sequence']
            or value['native_sequence']<profile.minimum_sequence or not 1<=end-start<=5000
            or not start<=stamp<=now<end or now-stamp>5000 or now>=command.expires_at
            or (value['registry_ready_model'] is not None and not _model(value['registry_ready_model']))):
        raise NativeGuardError()


async def query_preparation(profile,command,root):
    if not _root(root):raise NativeGuardError()
    response=await _query_guard(profile,command,'preparation',{'job_id':command.job_id,'attempt':command.attempt,
        'root_sequence':root,'correlation_id':request_correlation_id(command)})
    if set(response)!={'version','id','ok','epoch','preparation'}:raise NativeGuardError()
    value=response['preparation']
    validate_preparation_observation(value,profile,command,root,int(time.time()*1000))
    return value


async def check_preparation_guard(command):
    try:
        profile=GuardProfile.from_environment()
        root=bound_preparation_root(command,profile.native_epoch)
        if root is None:raise NativeGuardError()
        value=await query_preparation(profile,command,root)
        validate_preparation_observation(value,profile,command,root,int(time.time()*1000))
        return profile.native_epoch,root
    except (ValueError,TypeError,KeyError,UnicodeError):raise NativeGuardError() from None
