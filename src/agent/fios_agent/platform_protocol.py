"""Strict single-use, text-only platform pipe commands; independent of UI IPC."""
from dataclasses import dataclass
import hashlib
import json
import time
from uuid import UUID

from .protocol import parse_command, utf16_length
from .harness import INSTRUCTIONS


class PlatformProtocolError(ValueError):
    pass


def _uuid(value):
    return isinstance(value,str) and str(UUID(value)) == value


def _pairs(pairs):
    result={}
    for key,value in pairs:
        if key in result:raise PlatformProtocolError('invalid_request')
        result[key]=value
    return result


def decode_platform_frame(data):
    if not isinstance(data,bytes) or not 0<len(data)<=1024*1024:raise PlatformProtocolError('invalid_request')
    try:
        return json.loads(data.decode('utf-8'),object_pairs_hook=_pairs,
                          parse_constant=lambda _: (_ for _ in ()).throw(PlatformProtocolError('invalid_request')))
    except (ValueError,UnicodeError,RecursionError):raise PlatformProtocolError('invalid_request') from None


@dataclass(frozen=True)
class PlatformCommand:
    job_id:str
    attempt:int
    epoch:str
    model:str
    endpoint_hash:str
    expires_at:int
    run:object


def parse_platform_command(data):
    expected={'v','type','job_id','attempt','epoch','model','endpoint_hash','expires_at','context'}
    try:
        if not isinstance(data,dict) or set(data)!=expected:raise ValueError()
        if type(data['v']) is not int or data['v']!=1 or data['type']!='run':raise ValueError()
        if not _uuid(data['job_id']) or not _uuid(data['epoch']):raise ValueError()
        if type(data['attempt']) is not int or not 0<=data['attempt']<=3:raise ValueError()
        if not isinstance(data['model'],str) or not 0<len(data['model'].encode())<=1024:raise ValueError()
        digest=data['endpoint_hash']
        if not isinstance(digest,str) or len(digest)!=64 or any(c not in '0123456789abcdef' for c in digest):raise ValueError()
        now=int(time.time()*1000);expiry=data['expires_at']
        if type(expiry) is not int or not now<expiry<=now+5000:raise ValueError()
        context=data['context']
        if not isinstance(context,list) or not context:raise ValueError()
        total=utf16_length(INSTRUCTIONS)
        for item in context:
            if not isinstance(item,dict) or set(item)!={'role','content'} or not isinstance(item['content'],str):raise ValueError()
            total+=utf16_length(item['content'])
        if total>128000:raise ValueError()
        run=parse_command({'v':2,'type':'run','run_id':data['job_id'],'model':data['model'],'context':context})
        return PlatformCommand(data['job_id'],data['attempt'],data['epoch'],data['model'],digest,expiry,run)
    except (ValueError,TypeError,KeyError,AttributeError,UnicodeError):
        raise PlatformProtocolError('invalid_request') from None


def endpoint_hash(base_url):
    return hashlib.sha256(base_url.encode()).hexdigest()


def request_correlation_id(command):
    """Opaque identity for one parsed permission; never terminal authority."""
    parts=(command.job_id,str(command.attempt),command.epoch,command.model,command.endpoint_hash)
    payload=b'fios-native-request-v1\0'
    for field in parts:
        encoded=field.encode('utf-8')
        payload+=len(encoded).to_bytes(4,'big')+encoded
    return hashlib.sha256(payload).hexdigest()
