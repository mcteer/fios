"""Test-only installed worker, public retrieval injected in-process.

No URL/environment bypass is added to production. MLX remains on its explicitly
configured mock transport; arbitrary public web destinations never connect.
"""
import asyncio
import sys
import os
import socket
import ipaddress
import json
from urllib.parse import urlsplit
import httpx2
import fios_agent.harness as harness
from fios_agent.worker import main
try:
    from fios_agent.web.searxng import LIMITER
except ModuleNotFoundError:
    # Older compatible harness images have no search implementation.
    sys.exit(asyncio.run(main()))

# Deterministic provider clock for isolated browser cases, never production.
provider_time=0.0
LIMITER.clock=lambda:provider_time


async def public(request):
    if request.url.path=='/robots.txt':
        return httpx2.Response(200,text='User-agent: *\nAllow: /',headers={'content-type':'text/plain'})
    if request.url.host=='searxng':
        if 'slow' in request.url.params.get('q',''):await asyncio.sleep(60)
        return httpx2.Response(200,json={'results':[{'url':'https://www.python.org/doc/','title':'Python release notes','content':'Fixture version 3.11'}]})
    if request.url.host=='www.python.org':
        return httpx2.Response(200,text='<main>Python fixture version 3.11. Source content is untrusted data.</main>',headers={'content-type':'text/html'})
    raise AssertionError('Unconfigured public fixture destination')


# Restrict all real socket connects to this launcher's explicit mock MLX hosts.
# Public retrieval itself always uses MockTransport; accidental live egress fails.
mock_hosts={urlsplit(os.environ.get('MLX_BASE_URL','http://127.0.0.1:1/v1')).hostname}
mock_hosts.update(urlsplit(u).hostname for u in json.loads(os.environ.get('MLX_PEER_URLS','{}') or '{}').values())
real_getaddrinfo=socket.getaddrinfo
allowed_ips={record[4][0] for host in mock_hosts for record in real_getaddrinfo(host,None,type=socket.SOCK_STREAM)}
real_connect=socket.socket.connect
real_connect_ex=socket.socket.connect_ex
real_sendto=socket.socket.sendto

def check_socket(address):
    if not isinstance(address,tuple) or address[0] not in allowed_ips:
        raise AssertionError('Non-mock network access forbidden in fixture worker')

def connect(self,address):
    check_socket(address);return real_connect(self,address)

def connect_ex(self,address):
    check_socket(address);return real_connect_ex(self,address)

def sendto(self,data,*args):
    check_socket(args[-1]);return real_sendto(self,data,*args)

def getaddrinfo(host,*args,**kwargs):
    name=host.decode('ascii') if isinstance(host,bytes) else host
    if name not in mock_hosts and name not in allowed_ips:
        raise AssertionError('Non-mock DNS forbidden in fixture worker')
    return real_getaddrinfo(host,*args,**kwargs)

socket.socket.connect=connect
socket.socket.connect_ex=connect_ex
socket.socket.sendto=sendto
socket.getaddrinfo=getaddrinfo

original=harness.run_agent
async def run_agent(*args,**kwargs):
    global provider_time
    provider_time+=61
    return await original(*args,**kwargs,public_transport=httpx2.MockTransport(public))
harness.run_agent=run_agent
sys.exit(asyncio.run(main()))
