"""Public-only read transport. Independent of authenticated MLX clients.

The resolver and delegate arguments are Python test seams, never environment flags.
"""
import asyncio
import ipaddress
import re
import ssl
import time
from urllib.parse import urlsplit,parse_qsl

import certifi
import dns.asyncresolver
import dns.exception
import dns.resolver
import httpcore2
import httpx2

from .types import bounded


class WebFailure(ValueError):
    def __init__(self, code='unavailable'):
        self.code=code
        super().__init__('Public retrieval unavailable.')


# Explicit conservative additions: CPython 3.11 is_global predates IANA updates.
DENY = tuple(ipaddress.ip_network(n) for n in (
    '0.0.0.0/8','10.0.0.0/8','100.64.0.0/10','127.0.0.0/8','169.254.0.0/16',
    '172.16.0.0/12','192.0.0.0/24','192.0.2.0/24','192.88.99.0/24','192.168.0.0/16',
    '198.18.0.0/15','198.51.100.0/24','203.0.113.0/24','224.0.0.0/4','240.0.0.0/4',
    '::/96','::ffff:0:0/96','64:ff9b::/96','64:ff9b:1::/48','100::/64',
    '2001::/23','2001:db8::/32','2002::/16','3fff::/20','5f00::/16','fc00::/7','fe80::/10','ff00::/8',
))


def public_address(value):
    try:
        ip=ipaddress.ip_address(value)
        return ip.is_global and not ip.is_multicast and not any(ip.version==n.version and ip in n for n in DENY)
    except ValueError:
        return False


def public_hostname(host, forbidden=()):
    host=host.lower().rstrip('.')
    try:
        ipaddress.ip_address(host)
    except ValueError:
        pass
    else:
        raise WebFailure()
    if (not host.isascii() or len(host)>253 or '.' not in host
        or host.endswith(('.localhost','.local','.lab','.internal','.home','.test','.invalid','.onion'))
        or host in {'localhost',*(x.lower().rstrip('.') for x in forbidden)}
        or any(re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?',p) is None for p in host.split('.'))
        or not re.search(r'[a-z]',host.split('.')[-1])):
        raise WebFailure()
    return host


def validate_url(value, forbidden=()):
    try:
        bounded(value,2048)
        if not value.isascii() or any(ord(c)<33 or ord(c)==127 for c in value) or '\\' in value:
            raise WebFailure()
        u=urlsplit(value)
        if (u.scheme not in ('http','https') or not u.hostname or u.username is not None
            or u.password is not None or u.fragment or '%' in u.netloc
            or u.port not in (None,443 if u.scheme=='https' else 80)):
            raise WebFailure()
        if any(k.casefold() in {'access_token','api_key','apikey','password','passwd','authorization','auth','token','secret','session','sessionid','signature','credential','key'} for k,_ in parse_qsl(u.query,keep_blank_values=True)):
            raise WebFailure()
        public_hostname(u.hostname,forbidden)
        return value
    except (ValueError,UnicodeError):
        raise WebFailure() from None


async def resolve_public(host,forbidden=()):
    resolver=dns.asyncresolver.Resolver()
    async def query(kind):
        try:
            answer=await resolver.resolve(host+'.',kind,lifetime=2,search=False,raise_on_no_answer=False)
            public_hostname(str(answer.canonical_name).rstrip('.'),forbidden)
            for rrset in answer.response.answer:
                if rrset.rdtype==5:  # Validate every CNAME edge, not just terminal.
                    public_hostname(str(rrset.name).rstrip('.'),forbidden)
                    for record in rrset: public_hostname(str(record.target).rstrip('.'),forbidden)
            return [str(r) for r in answer] if answer.rrset is not None else []
        except dns.resolver.NoAnswer:
            return []
        except (dns.exception.DNSException,ValueError):
            raise WebFailure() from None
    async with asyncio.timeout(2):
        a,b=await asyncio.gather(query('A'),query('AAAA'))
    return a+b


class PublicBackend(httpcore2.AsyncNetworkBackend):
    def __init__(self, *, resolve=resolve_public, delegate=None, forbidden=(), check=lambda:None):
        self.check=check
        self.resolve=(lambda host:resolve_public(host,forbidden)) if resolve is resolve_public else resolve
        self.delegate=delegate or httpcore2.AnyIOBackend()
        self.forbidden=forbidden

    async def connect_tcp(self,host,port,timeout=None,local_address=None,socket_options=None):
        self.check()
        public_hostname(host,self.forbidden)
        if port not in (80,443) or local_address is not None:
            raise WebFailure()
        async with asyncio.timeout(min(timeout or 2,2)):
            addresses=await self.resolve(host)
        self.check()
        if not addresses or any(not public_address(a) for a in addresses):
            raise WebFailure()
        selected=str(ipaddress.ip_address(addresses[0]))
        stream=await self.delegate.connect_tcp(selected,port,timeout=timeout,
                                               local_address=None,socket_options=socket_options)
        try:
            self.check()
            peer=stream.get_extra_info('server_addr')
            if not peer or ipaddress.ip_address(peer[0])!=ipaddress.ip_address(selected):
                raise WebFailure()
        except BaseException:
            await stream.aclose()
            raise
        # The pool retains its original URL hostname for Host and start_tls SNI.
        return stream

    async def connect_unix_socket(self,*args,**kwargs):
        raise WebFailure()

    async def sleep(self,seconds):
        await asyncio.sleep(seconds)


class CoreStream(httpx2.AsyncByteStream):
    def __init__(self,stream): self.stream=stream
    async def __aiter__(self):
        async for chunk in self.stream: yield chunk
    async def aclose(self): await self.stream.aclose()


class PublicTransport(httpx2.AsyncBaseTransport):
    def __init__(self, *, backend=None, forbidden=(), check=lambda:None):
        self.forbidden=forbidden
        self.pool=httpcore2.AsyncConnectionPool(ssl_context=ssl.create_default_context(cafile=certifi.where()),
            max_connections=2,max_keepalive_connections=0,http1=True,http2=False,retries=0,
            network_backend=backend or PublicBackend(forbidden=forbidden,check=check))

    async def handle_async_request(self,request):
        validate_url(str(request.url),self.forbidden)
        if request.method!='GET': raise WebFailure()
        allowed={'host','user-agent','accept','accept-encoding','connection'}
        if any(k.lower() not in allowed for k in request.headers.keys()): raise WebFailure()
        req=httpcore2.Request(method=b'GET',url=httpcore2.URL(scheme=request.url.raw_scheme,
            host=request.url.raw_host,port=request.url.port,target=request.url.raw_path),
            headers=request.headers.raw,content=request.stream,extensions=request.extensions)
        try:
            response=await self.pool.handle_async_request(req)
        except (httpcore2.NetworkError,httpcore2.TimeoutException,httpcore2.ProtocolError):
            raise WebFailure() from None
        return httpx2.Response(response.status,headers=response.headers,stream=CoreStream(response.stream),extensions=response.extensions)

    async def aclose(self): await self.pool.aclose()


class PublicHTTP:
    def __init__(self, *, forbidden=(), transport=None, check=lambda:None):
        self.check=check
        self.forbidden=forbidden
        self.attempts=0
        self.total=0
        self.deadline=time.monotonic()+15
        self.client=httpx2.AsyncClient(transport=transport or PublicTransport(forbidden=forbidden,check=check),
            trust_env=False,follow_redirects=False,headers={'User-Agent':'Fios/0.1',
            'Accept':'text/html, text/plain','Accept-Encoding':'identity'},timeout=4)
        self.slots=asyncio.Semaphore(2)

    async def get(self,url,*,limit=1048576,seconds=4):
        self.check()
        validate_url(url,self.forbidden)
        if self.attempts>=14: raise WebFailure()
        remaining=self.deadline-time.monotonic()
        if remaining<=0: raise WebFailure('timeout')
        self.attempts+=1
        async with asyncio.timeout(min(remaining,seconds)),self.slots:
            self.client.cookies.clear()  # Do not replay provider/site Set-Cookie.
            async with self.client.stream('GET',url) as response:
                self.check()
                if sum(len(k)+len(v)+4 for k,v in response.headers.raw)>32768: raise WebFailure()
                if response.headers.get('content-encoding','identity').lower()!='identity': raise WebFailure()
                body=bytearray()
                # Identity encoding was enforced above. aiter_bytes also
                # supports prebuffered MockTransport responses without a
                # production-only test branch or double-reading the stream.
                async for chunk in response.aiter_bytes():
                    self.check()
                    self.total+=len(chunk)
                    if len(body)+len(chunk)>limit or self.total>5*1048576: raise WebFailure()
                    body.extend(chunk)
                return response.status_code,response.headers,bytes(body)

    async def aclose(self): await self.client.aclose()
