import unittest
import httpx2
from fios_agent.web.http import PublicHTTP
from fios_agent.web.robots import Robots
from fios_agent.web.searxng import search, ProviderLimiter
from fios_agent.web.types import RunSearchInput


class RetrievalTests(unittest.IsolatedAsyncioTestCase):
    async def test_fixed_provider_and_page_evidence(self):
        calls=[]
        async def handler(req):
            calls.append(str(req.url))
            self.assertNotIn('authorization',req.headers)
            self.assertNotIn('cookie',req.headers)
            if req.url.path=='/robots.txt': return httpx2.Response(200,text='User-agent: *\nAllow: /',headers={'content-type':'text/plain'})
            if req.url.host=='searxng':
                return httpx2.Response(200,json={'results':[{'url':'https://www.python.org/doc/','title':'Python','content':'Release notes'}]})
            return httpx2.Response(200,text='<main>Python fixture version 3.11</main>',headers={'content-type':'text/html'})
        http=PublicHTTP(transport=httpx2.MockTransport(handler))
        try:
            result=await search('Python release',http=http,limiter=ProviderLimiter())
            self.assertEqual(result.outcome,'retrieved')
            self.assertIn('fixture version',result.sources[0].excerpt)
            self.assertEqual(sum('searxng:8080/search?' in u for u in calls),1)
        finally: await http.aclose()

    async def test_robots_denial_and_redirect_fail_closed(self):
        async def handler(req):
            return httpx2.Response(200,text='User-agent: *\nDisallow: /private\n',headers={'content-type':'text/plain'})
        http=PublicHTTP(transport=httpx2.MockTransport(handler))
        try:
            rules=Robots(http)
            self.assertFalse(await rules.allowed('https://example.com/private'))
            self.assertTrue(await rules.allowed('https://example.com/public'))
        finally: await http.aclose()

    async def test_limiter_honors_long_retry_after_and_overflow(self):
        now=[0.0]
        limiter=ProviderLimiter(clock=lambda:now[0],wall=lambda:0)
        self.assertTrue(limiter.take())
        limiter.block('3600')
        now[0]=900
        self.assertFalse(limiter.take())
        now[0]=3600
        self.assertTrue(limiter.take())
        limiter.block('not a date')
        now[0]=1e12
        self.assertFalse(limiter.take())

    async def test_body_caps_and_no_credential_forwarding(self):
        async def handler(req): return httpx2.Response(200,content=b'x'*1025)
        http=PublicHTTP(transport=httpx2.MockTransport(handler))
        try:
            with self.assertRaises(ValueError): await http.get('https://example.com/',limit=1024)
        finally: await http.aclose()
