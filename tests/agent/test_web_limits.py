import asyncio
import unittest
import httpx2
from fios_agent.web.http import PublicBackend,PublicHTTP,WebFailure
from fios_agent.web.pages import parse_document,decode_text


class WebLimitsTests(unittest.IsolatedAsyncioTestCase):
    async def test_body_header_encoding_and_attempt_caps(self):
        cases=[({'content-encoding':'gzip'},b'compressed'),({'x-large':'x'*33000},b'x'),({},b'x'*1025)]
        for headers,body in cases:
            class Stream(httpx2.AsyncByteStream):
                async def __aiter__(self):yield body
            async def handle(request):return httpx2.Response(200,headers=headers,stream=Stream())
            http=PublicHTTP(transport=httpx2.MockTransport(handle))
            try:
                with self.assertRaises(WebFailure):await http.get('https://example.com/',limit=1024)
            finally:await http.aclose()
        count=[]
        async def handle(request):count.append(1);return httpx2.Response(200,content=b'x')
        http=PublicHTTP(transport=httpx2.MockTransport(handle))
        http.attempts=14
        try:
            with self.assertRaises(WebFailure):await http.get('https://example.com/')
            self.assertEqual(count,[])
        finally:await http.aclose()

    async def test_malformed_and_unsupported_robot_restrictions_fail_closed(self):
        from unittest.mock import patch
        from fios_agent.web.robots import Robots,ACCESS
        cases=['<html>User-agent: * Allow: /</html>','User-agent: *\nCrawl-delay: malformed',
               'User-agent: *\nAllow: /\nVisit-time: 0800-2000']
        for text in cases:
            async def handle(request):return httpx2.Response(200,text=text)
            http=PublicHTTP(transport=httpx2.MockTransport(handle))
            try:
                with patch.dict(ACCESS,clear=True):self.assertFalse(await Robots(http).allowed('https://example.com/page'))
            finally:await http.aclose()

    async def test_expired_rules_refetch_and_site_retry_after_is_not_clamped(self):
        from unittest.mock import patch
        from fios_agent.web.robots import Robots,ACCESS
        count=[]
        async def handle(request):
            count.append(1)
            return httpx2.Response(200,text='User-agent: *\nAllow: /',headers={'cache-control':'max-age=0'})
        http=PublicHTTP(transport=httpx2.MockTransport(handle))
        try:
            with patch.dict(ACCESS,clear=True):
                rules=Robots(http)
                self.assertTrue(await rules.allowed('https://example.com/page'))
                self.assertTrue(await rules.allowed('https://example.com/other'))
                self.assertEqual(len(count),2)
                rules.defer('https://example.com/page',httpx2.Headers({'Retry-After':'7200'}))
                self.assertFalse(await rules.allowed('https://example.com/page'))
                self.assertGreater(ACCESS['https://example.com'][1],7000)
                rules.defer('https://example.com/page',httpx2.Headers({'Retry-After':'invalid'}))
                self.assertEqual(ACCESS['https://example.com'][1],float('inf'))
        finally:await http.aclose()

    async def test_dns_timeout_is_bounded_and_does_not_connect(self):
        calls=[]
        async def resolve(host):await asyncio.sleep(60)
        class Delegate:
            async def connect_tcp(self,*args,**kwargs):calls.append(1)
        backend=PublicBackend(resolve=resolve,delegate=Delegate())
        with self.assertRaises(TimeoutError):await backend.connect_tcp('example.com',443,timeout=.02)
        self.assertEqual(calls,[])

    async def test_parser_input_depth_and_charset_caps(self):
        with self.assertRaises(ValueError):await parse_document(b'x'*(1024*1024+1),'page')
        with self.assertRaises(ValueError):await parse_document(b'<div>'*130+b'content'+b'</div>'*130,'page')
        with self.assertRaises(ValueError):decode_text({'content-type':'text/html; charset=unsupported-charset'},b'x')
