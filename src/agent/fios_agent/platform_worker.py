"""Single-request private platform entry point. No tools, database or listener."""
import asyncio
from dataclasses import replace
import json
import hashlib
from importlib.metadata import version
import signal
import sys
import time
from urllib.parse import urlsplit

import httpx2
from pydantic_ai import CancellationToken

from .harness import run_agent, INSTRUCTIONS
from .platform_protocol import decode_platform_frame, parse_platform_command, endpoint_hash, request_correlation_id
from .platform_guard import check_native_guard, NativeGuardError
from .protocol import utf16_length
from .transport import StreamFailure
from .worker import Settings, pipe_streams


def output_chunks(text):
    start=0;units=0
    for index,char in enumerate(text):
        size=2 if ord(char)>0xffff else 1
        if units+size>8192:
            yield text[start:index]
            start=index;units=0
        units+=size
    if start<len(text):yield text[start:]


class PlatformTransport(httpx2.AsyncBaseTransport):
    def __init__(self,command,inner,emit,token,*,base_url):
        parts=urlsplit(base_url)
        self.origin=(parts.scheme,parts.hostname,parts.port or 80)
        prefix=parts.path.rstrip('/')
        root=prefix[:-3] if prefix.endswith('/v1') else prefix
        self.allowed={('GET',root+'/health'),('GET',prefix+'/models'),('POST',prefix+'/chat/completions')}
        self.command,self.inner,self.emit,self.token=command,inner,emit,token
        self.posts=0
        self.actual_posts=0

    async def handle_async_request(self,request):
        url=request.url
        # Bind GETs and redirects too, not just model POSTs. An upstream
        # redirect must never turn a private native request into an external
        # client or a different local service/admin request.
        if ((url.scheme,url.host,url.port or 80)!=self.origin or url.username or url.password
                or url.query or url.fragment or (request.method,url.path) not in self.allowed):
            raise StreamFailure('invalid_request')
        if request.method=='POST':
            if self.token.cancelled or self.posts or int(time.time()*1000)>=self.command.expires_at:
                raise StreamFailure('invalid_request')
            body=json.loads(request.content)
            if body.get('model')!=self.command.model or body.get('tools'):
                raise StreamFailure('invalid_request')
            self.posts+=1
            # A parent persists ownership BEFORE granting this command. This
            # pre-send event cannot prove dispatch if the child crashes here.
            await self.emit({'v':1,'type':'dispatched','job_id':self.command.job_id,'attempt':self.command.attempt})
            if self.token.cancelled or int(time.time()*1000)>=self.command.expires_at:
                raise StreamFailure('invalid_request')
            try:
                await check_native_guard(self.command)
            except NativeGuardError:
                raise StreamFailure('model_unavailable') from None
            # The independent read-only guard is an await boundary too. A
            # revoked/expired permission cannot dispatch after it returns.
            if self.token.cancelled or int(time.time()*1000)>=self.command.expires_at:
                raise StreamFailure('invalid_request')
            if 'x-fios-request-id' in request.headers:
                raise StreamFailure('invalid_request')
            request.headers['x-fios-request-id']=request_correlation_id(self.command)
            self.actual_posts+=1
        return await self.inner.handle_async_request(request)

    async def aclose(self):await self.inner.aclose()


async def run_platform(command,settings,emit,*,transport=None,token=None):
    token=token or CancellationToken()
    parts=urlsplit(settings.base_url)
    if (parts.scheme!='http' or parts.hostname not in ('127.0.0.1','::1') or parts.username or parts.password
            or parts.query or parts.fragment or settings.peers or endpoint_hash(settings.base_url)!=command.endpoint_hash):
        await emit({'v':1,'type':'error','job_id':command.job_id,'code':'invalid_request'})
        return
    units=0
    terminal=None
    async def convert(event):
        nonlocal units,terminal
        if event['type'] in ('done','error'):
            terminal={k:v for k,v in event.items() if k not in ('v','run_id')}
            return
        if event['type'].startswith('search_'):return
        if token.cancelled and event['type'] in ('delta','reasoning'):return
        if 'content' in event:
            next_units=units+utf16_length(event['content'])
            if next_units>64000:
                token.cancel()
                raise StreamFailure('output_limit')
            units=next_units
        converted={k:v for k,v in event.items() if k not in ('v','run_id')}
        if 'content' in converted:
            for part in output_chunks(converted['content']):
                if token.cancelled:return
                await emit({'v':1,'job_id':command.job_id,**converted,'content':part})
        else:
            await emit({'v':1,'job_id':command.job_id,**converted})
    inner=transport or httpx2.AsyncHTTPTransport(retries=0,trust_env=False)
    guarded=PlatformTransport(command,inner,emit,token,base_url=settings.base_url)
    try:
        async with asyncio.timeout(180):
            await run_agent(command.run,token,convert,replace(settings,web_search='off'),transport=guarded)
    except TimeoutError:
        token.cancel()
        terminal={'type':'error','code':'deadline'}
    finally:
        await guarded.aclose()
    await emit({'v':1,'type':'usage','job_id':command.job_id,'attempt':command.attempt,
                'posts':guarded.actual_posts,'output_units':units})
    if terminal is not None:
        await emit({'v':1,'job_id':command.job_id,**terminal})


async def main():
    reader,writer,read_transport=await pipe_streams()
    token=CancellationToken()
    loop=asyncio.get_running_loop()
    for number in (signal.SIGTERM,signal.SIGINT):loop.add_signal_handler(number,token.cancel)
    async def emit(event):
        data=json.dumps(event,separators=(',',':'),ensure_ascii=True).encode()
        if len(data)>256*1024:raise StreamFailure('output_limit')
        writer.write(len(data).to_bytes(4,'big')+data)
        async with asyncio.timeout(10):await writer.drain()
    monitor=None
    try:
        async with asyncio.timeout(10):
            size=int.from_bytes(await reader.readexactly(4),'big')
            if not 0<size<=1024*1024:raise ValueError()
            command=parse_platform_command(decode_platform_frame(await reader.readexactly(size)))
        async def cancellation():
            # One request per child. Any extra command/EOF revokes dispatch;
            # no later command can reset its permission, lease or budgets.
            await reader.read(1)
            token.cancel()
        monitor=asyncio.create_task(cancellation())
        await run_platform(command,Settings.from_environment(),emit,token=token)
    except (Exception,asyncio.CancelledError):
        token.cancel()
        try:await emit({'v':1,'type':'error','code':'invalid_request'})
        except Exception:pass
    finally:
        if monitor:
            monitor.cancel()
            await asyncio.gather(monitor,return_exceptions=True)
        read_transport.close();writer.close()


def metadata():
    # Content-free provenance only; never print the fixed policy itself.
    return {'version':1,'pipe_version':1,'package_version':version('fios-agent'),
            'python_version':'.'.join(map(str,sys.version_info[:3])),
            'policy_sha256':hashlib.sha256(INSTRUCTIONS.encode()).hexdigest(),
            'policy_input_units':utf16_length(INSTRUCTIONS)}


if __name__=='__main__':
    if sys.argv[1:]==['--metadata']:
        print(json.dumps(metadata(),sort_keys=True,separators=(',',':')))
    elif len(sys.argv)!=1:
        raise SystemExit(2)
    else:
        asyncio.run(main())
