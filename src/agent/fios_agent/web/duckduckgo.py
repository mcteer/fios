"""One fixed-provider search plus bounded public pages. Never model orchestration."""
import asyncio
from collections import deque
from datetime import timezone
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
    if u.hostname in ('duckduckgo.com','html.duckduckgo.com') and u.path.startswith('/l/'):
        args=parse_qs(u.query)
        if len(args.get('uddg',[]))!=1: raise WebFailure()
        value=args['uddg'][0]
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
            provider='https://html.duckduckgo.com/html/?'+urlencode({'q':query})
            if not await rules.allowed(provider):
                retry=rules.last_headers.get_list('retry-after') if rules.last_headers is not None else []
                limiter.block(retry[0] if len(retry)==1 else 'invalid' if retry else None)
                return result('blocked')
            status,headers,raw=await http.get(provider,seconds=5)
            if status in (202,401,403,429):
                retry=headers.get_list('retry-after')
                limiter.block(retry[0] if len(retry)==1 else 'invalid' if retry else None)
                return result('rate_limited' if status==429 else 'blocked')
            if status!=200:
                retry=headers.get_list('retry-after')
                limiter.block(retry[0] if len(retry)==1 else 'invalid' if retry else None)
                return result('unavailable')
            media,_=decode_text(headers,raw)
            if media!='text/html': return result('unavailable')
            parsed=await parse_document(raw,'provider')
            if parsed['state']=='blocked':
                limiter.block(None); return result('blocked')
            if parsed['state']=='empty': return result('empty')
            if parsed['state']!='results': return result('unavailable')
            candidates=[]; seen=set()
            for item in parsed['results']:
                try: url=target_url(item['url'],http.forbidden)
                except ValueError: continue
                if url in seen: continue
                seen.add(url)
                candidates.append((url,item))
                if len(candidates)==5: break
            if not candidates: return result('unavailable')
            await notify('fetching')
            sources=[]; skipped=False
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
    except TimeoutError: return result('timeout')
    except (ValueError,OSError,httpcore2.NetworkError,httpcore2.TimeoutException,httpcore2.ProtocolError,httpx2.HTTPError): return result('unavailable')
