"""Bounded stdlib HTML parser helper. Stdin bytes only; stdout fixed JSON.

Launched by pages.py in isolated Python with an allowlisted empty environment.
"""
import ctypes
from html.parser import HTMLParser
import json
import os
import resource
import signal
import sys


class Extractor(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack=[]
        self.body=[]
        self.main=[]
        self.results=[]
        self.current=None
        self.blocked=False
        self.empty=False
        self.nodes=0

    def handle_starttag(self,tag,attrs):
        self.nodes+=1
        if self.nodes>20000 or len(self.stack)>128: raise ValueError('html_limit')
        attrs=dict(attrs)
        classes=attrs.get('class','').split()
        identifier=attrs.get('id','')
        if 'challenge' in identifier or 'anomaly' in identifier: self.blocked=True
        if 'no-results' in classes or 'no-results__message' in classes: self.empty=True
        hidden=(tag in {'script','style','form','template','nav','noscript','iframe','svg','head','footer','header'}
                or 'hidden' in attrs or attrs.get('aria-hidden')=='true'
                or any(c in {'result--ad','result--ads','ad','ads'} for c in classes)
                or any(x in attrs.get('style','').lower().replace(' ','') for x in ['display:none','visibility:hidden']))
        if tag=='a' and 'result__a' in classes and not hidden and not any(s[1] for s in self.stack) and len(self.results)<20:
            self.current={'url':attrs.get('href',''),'title':'','snippet':''}
            self.results.append(self.current)
        slot='title' if 'result__a' in classes else 'snippet' if 'result__snippet' in classes else None
        if tag not in {'area','base','br','col','embed','hr','img','input','link','meta','param','source','track','wbr'}:
            self.stack.append((tag,hidden,slot,tag in {'main','article'}))
        if tag in {'p','br','div','li','h1','h2','h3'}: self.handle_data(' ')

    def handle_startendtag(self,tag,attrs):
        before=len(self.stack)
        self.handle_starttag(tag,attrs)
        del self.stack[before:]

    def handle_endtag(self,tag):
        for i in range(len(self.stack)-1,-1,-1):
            if self.stack[i][0]==tag:
                del self.stack[i:]
                break
        self.handle_data(' ')

    def handle_data(self,data):
        if any(s[1] for s in self.stack): return
        self.body.append(data)
        if any(s[3] for s in self.stack): self.main.append(data)
        if self.current:
            slot=next((s[2] for s in reversed(self.stack) if s[2]),None)
            if slot: self.current[slot]+=data

    def result(self,mode):
        clean=lambda s:' '.join(s.split())
        if mode=='page': return {'text':clean(''.join(self.main or self.body))[:12000]}
        state='blocked' if self.blocked else 'results' if self.results else 'empty' if self.empty else 'unavailable'
        return {'state':state,'results':[{**r,'title':clean(r['title'])[:300], 'snippet':clean(r['snippet'])[:3000]} for r in self.results]}


def main():
    parent=os.getppid()
    if sys.platform=='linux':
        libc=ctypes.CDLL(None)
        if libc.prctl(1,signal.SIGKILL,0,0,0)!=0: return 1
        if os.getppid()!=parent or parent==1: return 1
    # macOS rejects RLIMIT_AS below its interpreter's existing virtual map.
    # Production and ARM64 acceptance run Linux, where this cap is mandatory.
    if sys.platform=='linux':
        resource.setrlimit(resource.RLIMIT_AS,(64*1024*1024,64*1024*1024))
    resource.setrlimit(resource.RLIMIT_CPU,(1,1))
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    mode=sys.argv[1] if len(sys.argv)==2 else ''
    if mode not in ('page','provider'): return 1
    raw=sys.stdin.buffer.read(1048577)
    if len(raw)>1048576: return 1
    parser=Extractor()
    parser.feed(raw.decode('utf-8','strict')); parser.close()
    output=json.dumps(parser.result(mode),ensure_ascii=False,separators=(',',':')).encode()
    if len(output)>65536: return 1
    sys.stdout.buffer.write(output)
    return 0


if __name__=='__main__':
    try: code=main()
    except Exception: code=1
    sys.exit(code)
