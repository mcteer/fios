"""Fixed internal SearXNG JSON gateway plus independently guarded public pages.

The gateway is an explicit private-service exception, never a general URL fetch.
No model/client argument can change its host, port, path, engines or pagination.
"""
import asyncio
from collections import deque
import json
from email.utils import parsedate_to_datetime
import hashlib
import math
import time
import httpcore2
import httpx2
from urllib.parse import urlencode, urlsplit, urljoin, parse_qs, urlunsplit

from .http import WebFailure,validate_url
from .pages import parse_document,decode_text
from .robots import Robots
from .types import REASONS,Source,ToolResult
from ..protocol import utf16_length


class ProviderLimiter:
    def __init__(self,*,clock=time.monotonic,wall=time.time):
        self.clock,self.wall=clock,wall
        self.calls=deque()
        self.until=0
        self.suppressed=False

    def take(self):
        now=self.clock()
        while self.calls and self.calls[0]<=now-60: self.calls.popleft()
        if self.suppressed or now<self.until or len(self.calls)>=12 or (self.calls and now-self.calls[-1]<5): return False
        self.calls.append(now)
        return True

    def block(self,value):
        delay=60
        if value is not None:
            try:
                if value.isascii() and value.isdigit(): delay=max(60,int(value))
                else:
                    date=parsedate_to_datetime(value)
                    if date.tzinfo is None: raise ValueError()
                    delay=max(60,date.timestamp()-self.wall())
                deadline=self.clock()+delay
                if not math.isfinite(deadline): raise ValueError()
            except (ValueError,TypeError,OverflowError):
                self.suppressed=True
                return
        self.until=max(self.until,self.clock()+delay)


LIMITER=ProviderLimiter()
ENDPOINT='http://searxng:8080/search'


async def gateway(query,http):
    http.check()
    if http.attempts>=14: raise WebFailure()
    http.attempts+=1
    remaining=http.deadline-time.monotonic()
    if remaining<=0:raise TimeoutError()
    # Separate unauthenticated client. PublicHTTP's private-address ban stays
    # intact; only this exact internal API can be contacted here.
    transport=http.test_transport or httpx2.AsyncHTTPTransport(retries=0)
    async with asyncio.timeout(min(6,remaining)),httpx2.AsyncClient(
        transport=transport,trust_env=False,follow_redirects=False,timeout=5,
        headers={'User-Agent':'Fios/0.1','Accept':'application/json','Accept-Encoding':'identity'}) as client:
        async with client.stream('GET',ENDPOINT,params={'q':query,'format':'json',
            'categories':'general','language':'en','safesearch':'1','pageno':'1'}) as response:
            if (sum(len(k)+len(v)+4 for k,v in response.headers.raw)>32768
                or response.headers.get('content-encoding','identity').lower()!='identity'):
                raise WebFailure()
            body=bytearray()
            async for chunk in response.aiter_bytes():
                http.check()
                http.total+=len(chunk)
                if len(body)+len(chunk)>1048576 or http.total>5*1048576:raise WebFailure()
                body.extend(chunk)
            http.check()
            http.gateway_status=response.status_code
            return response.status_code,response.headers,bytes(body)


def clipped(text,limit):
    result=[]; units=0
    for c in text:
        units+=2 if ord(c)>65535 else 1
        if units>limit: break
        result.append(c)
    return ''.join(result)


def result(outcome,sources=()):
    return ToolResult(v=1,outcome=outcome,reason=REASONS[outcome],
        retrieved_at=max((s.retrieved_at for s in sources),default=None),sources=list(sources))


def target_url(value,forbidden):
    if value.startswith('//'): value='https:'+value
    u=urlsplit(value)
    query=urlencode([(k,v) for k,values in parse_qs(u.query,keep_blank_values=True).items()
                     if not k.lower().startswith('utm_') and k.lower() not in ('fbclid','gclid') for v in values])
    return validate_url(urlunsplit((u.scheme,u.netloc,u.path,query,'')),forbidden)


async def search(query,*,http,limiter=LIMITER,progress=None):
    async def notify(phase):
        if progress: await progress(phase)
    if not limiter.take(): return result('rate_limited')
    try:
        async with asyncio.timeout(max(0,http.deadline-time.monotonic())):
            rules=Robots(http)
            status,headers,raw=await gateway(query,http)
            if status in (202,401,403,429):
                retry=headers.get_list('retry-after')
                limiter.block(retry[0] if len(retry)==1 else 'invalid' if retry else None)
                return result('rate_limited' if status==429 else 'blocked')
            if status!=200:
                retry=headers.get_list('retry-after')
                limiter.block(retry[0] if len(retry)==1 else 'invalid' if retry else None)
                return result('unavailable')
            if headers.get('content-type','').split(';')[0].strip().lower()!='application/json':return result('unavailable')
            parsed=json.loads(raw)
            if (type(parsed) is not dict or type(parsed.get('results')) is not list
                or len(parsed['results'])>100):return result('unavailable')
            http.gateway_results=len(parsed['results'])
            errors=parsed.get('unresponsive_engines',[])
            http.gateway_failed_engines=len(errors) if type(errors) is list else None
            if not parsed['results']:
                return result('unavailable' if parsed.get('unresponsive_engines') else 'empty')
            http.gateway_valid_rows=0
            http.gateway_valid_urls=0
            candidates=[]; seen=set()
            for item in parsed['results']:
                if type(item) is not dict or any(type(item.get(k)) is not str for k in ('url','title','content')):continue
                if any(len(item[k].encode('utf-8'))>65536 for k in ('title','content')):continue
                http.gateway_valid_rows+=1
                try: url=target_url(item['url'],http.forbidden)
                except ValueError: continue
                http.gateway_valid_urls+=1
                if url in seen: continue
                seen.add(url)
                snippet=(await parse_document(item['content'].encode('utf-8'),'page'))['text']
                candidates.append((url,{'title':item['title'],'snippet':snippet}))
                if len(candidates)==5: break
            if not candidates: return result('unavailable')
            await notify('fetching')
            sources=[]; skipped=bool(errors)
            for index,(url,item) in enumerate(candidates):
                excerpt=item['snippet']; kind='snippet'; truncated=False
                if index<3:
                    try:
                        current=url
                        for hop in range(3):
                            if not await rules.allowed(current): raise WebFailure()
                            status,headers,body=await http.get(current)
                            if status in (301,302,303,307,308):
                                target=validate_url(urljoin(current,headers.get('location','')),http.forbidden)
                                if hop==2 or (current.startswith('https:') and not target.startswith('https:')): raise WebFailure()
                                current=target; continue
                            if status!=200:
                                if status>=400:rules.defer(current,headers)
                                raise WebFailure()
                            media,text=decode_text(headers,body)
                            text=(await parse_document(body,'page'))['text'] if media=='text/html' else text
                            if not text.strip(): raise WebFailure()
                            excerpt=text; kind='page'; url=current
                            break
                    except (ValueError,TimeoutError,OSError,httpcore2.NetworkError,httpcore2.TimeoutException,httpcore2.ProtocolError,httpx2.HTTPError): skipped=True
                else: skipped=True
                if not excerpt.strip(): continue
                limited=clipped(excerpt,3000)
                truncated=limited!=excerpt
                sources.append(Source(id=f'S{len(sources)+1}',url=url,title=clipped(item['title'],300),
                    kind=kind,retrieved_at=int(time.time()*1000),excerpt=limited,
                    excerpt_sha256=hashlib.sha256(limited.encode()).hexdigest(),
                    excerpt_units=utf16_length(limited),truncated=truncated))
            if not sources: return result('unavailable')
            pages=sum(s.kind=='page' for s in sources)
            return result('snippets_only' if not pages else 'partial' if skipped or pages<len(sources) else 'retrieved',sources)
    except (TimeoutError,httpcore2.TimeoutException,httpx2.TimeoutException): return result('timeout')
    except (ValueError,RecursionError,OSError,httpcore2.NetworkError,httpcore2.TimeoutException,httpcore2.ProtocolError,httpx2.HTTPError): return result('unavailable')
