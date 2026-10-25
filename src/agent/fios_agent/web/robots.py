"""Bounded per-run origin rules. No result/query cache or redirect following."""
import time
import math
import httpcore2
import httpx2
from urllib.parse import urlsplit, urlunsplit
from protego import Protego
from email.utils import parsedate_to_datetime
from .http import WebFailure, validate_url


# Rule bodies remain per-run to avoid a mock fixture poisoning another run.
# Access times are worker-wide so user turns cannot reset site crawl delays.
ACCESS={}

class Robots:
    def __init__(self,http):
        self.http=http
        self.cache={}
        self.access=ACCESS
        self.last_headers=None

    def defer(self,url,headers):
        u=urlsplit(url)
        origin=urlunsplit((u.scheme,u.netloc,'','',''))
        values=headers.get_list('retry-after')
        delay=60
        if values:
            try:
                if len(values)!=1: raise ValueError()
                value=values[0]
                delay=max(60,int(value) if value.isascii() and value.isdigit() else parsedate_to_datetime(value).timestamp()-time.time())
                if not math.isfinite(delay): raise ValueError()
            except (ValueError,TypeError,OverflowError):delay=float('inf')
        now=time.monotonic()
        old=self.access.get(origin)
        if old:delay=max(delay,old[0]+old[1]-now)
        if origin in self.access or len(self.access)<128:self.access[origin]=(now,delay)

    async def allowed(self,url):
        validate_url(url,self.http.forbidden)
        u=urlsplit(url)
        origin=urlunsplit((u.scheme,u.netloc,'','',''))
        now=time.monotonic()
        for key,(last,required_delay) in list(self.access.items()):
            if now-last>=max(3600,required_delay):self.access.pop(key,None)
        previous=self.access.get(origin)
        if previous is not None and now-previous[0]<previous[1]:return False
        if previous is None and len(self.access)>=128:return False
        entry=self.cache.get(origin)
        if not entry or entry[0]<=now:
            try:
                status,headers,body=await self.http.get(origin+'/robots.txt',limit=65536)
                self.last_headers=headers
                if status==404: rules=Protego.parse('User-agent: *\nAllow: /')
                elif status==200: rules=Protego.parse(body.decode('utf-8','strict'))
                else:
                    self.defer(url,headers)
                    return False
                text=body.decode('utf-8','strict')
                import re
                if status==200:
                    lines=[line.split('#',1)[0].strip() for line in text.splitlines()]
                    if (not any(re.fullmatch(r'(?i)user-agent:\s*\S.*',line) for line in lines)
                        or any(line and re.fullmatch(r'[A-Za-z-]+:\s*.*',line) is None for line in lines)
                        or any(ord(c)<32 and c not in '\r\n\t' for c in text)):
                        return False
                    for line in lines:
                        if line.lower().startswith('crawl-delay:'):
                            try:
                                value=float(line.split(':',1)[1].strip())
                                if value<0 or not math.isfinite(value):return False
                            except ValueError:return False
                directives=headers.get('cache-control','').lower()
                ttl=3600
                match=re.search(r'max-age=(\d+)',directives)
                if match: ttl=min(ttl,int(match[1]))
                if headers.get('expires'):
                    try: ttl=min(ttl,max(0,parsedate_to_datetime(headers['expires']).timestamp()-time.time()))
                    except (ValueError,TypeError,OverflowError): ttl=0
                if 'no-store' in directives or 'no-cache' in directives: ttl=0
                if len(self.cache)>=128: self.cache.pop(next(iter(self.cache)))
                if ttl: self.cache[origin]=(now+ttl,rules)
            except (ValueError,TimeoutError,OSError,httpcore2.NetworkError,httpcore2.TimeoutException,httpcore2.ProtocolError,httpx2.HTTPError): return False
        else: rules=entry[1]
        if not rules.can_fetch(url,'Fios'): return False
        delay=rules.crawl_delay('Fios') or 0
        rate=rules.request_rate('Fios')
        # Optional time-window directives need not be implemented to be safe:
        # decline this page rather than guessing a timezone/window.
        if rules.visit_time('Fios') is not None or (rate and (rate.start_time is not None or rate.end_time is not None)):
            return False
        if rate:
            delay=max(delay,rate.seconds/rate.requests)
        previous=self.access.get(origin)
        if previous is not None and now-previous[0]<max(delay,previous[1]): return False
        # Mark even a failed page attempt; no same-origin retry to evade delays.
        if origin not in self.access and len(self.access)>=128:
            # Never evict a live delay merely to admit a new destination.
            for key,(last,required_delay) in list(self.access.items()):
                if now-last>=max(3600,required_delay):self.access.pop(key,None)
            if len(self.access)>=128:return False
        self.access[origin]=(now,delay)
        return True
