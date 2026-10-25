import asyncio
import json
import unittest
import httpx2
from fios_agent.web.http import PublicHTTP,validate_url
from fios_agent.web.searxng import search,ProviderLimiter,ENDPOINT


class SearxNGTests(unittest.IsolatedAsyncioTestCase):
    async def run_search(self,payload,status=200):
        calls=[]
        async def handler(request):
            calls.append(request)
            if request.url.host=='searxng':
                self.assertEqual(str(request.url.copy_with(query=None)),ENDPOINT)
                self.assertEqual(dict(request.url.params),{'q':'Python release','format':'json','categories':'general','language':'en','safesearch':'1','pageno':'1'})
                self.assertNotIn('authorization',request.headers)
                self.assertNotIn('cookie',request.headers)
                return httpx2.Response(status,json=payload,headers={'retry-after':'3600'})
            if request.url.path=='/robots.txt':return httpx2.Response(200,text='User-agent: *\nAllow: /')
            return httpx2.Response(200,text='<main>Python fixture evidence</main>',headers={'content-type':'text/html'})
        http=PublicHTTP(transport=httpx2.MockTransport(handler))
        try:result=await search('Python release',http=http,limiter=ProviderLimiter())
        finally:await http.aclose()
        return result,calls

    async def test_json_results_are_real_page_evidence_and_private_results_never_connect(self):
        result,calls=await self.run_search({'results':[
            {'url':'http://127.0.0.1/private','title':'private','content':'secret'},
            {'url':'http://searxng:8080/config','title':'private','content':'secret'},
            {'url':'https://www.python.org/doc/','title':'Python','content':'Release notes'}]})
        self.assertEqual(result.outcome,'retrieved')
        self.assertEqual(len(result.sources),1)
        self.assertIn('fixture evidence',result.sources[0].excerpt)
        self.assertEqual(sum(r.url.host=='searxng' for r in calls),1)
        self.assertFalse(any(r.url.host=='127.0.0.1' for r in calls))
        with self.assertRaises(ValueError):validate_url(ENDPOINT)

    async def test_partial_upstream_failure_retains_only_real_evidence(self):
        result,calls=await self.run_search({'results':[{'url':'https://www.python.org/doc/','title':'Python','content':'Release'}],
            'unresponsive_engines':[['bing','timeout']]})
        self.assertEqual(result.outcome,'partial')
        self.assertEqual(len(result.sources),1)

    async def test_invalid_response_engine_failure_and_rate_limit_are_not_success(self):
        for payload,status,outcome in [({},200,'unavailable'),({'results':'bad'},200,'unavailable'),({'results':[{}]*101},200,'unavailable'),({'results':[]},303,'unavailable'),({'results':[],'unresponsive_engines':[['bing','timeout']]},200,'unavailable'),({'results':[]},200,'empty'),({'results':[]},429,'rate_limited'),({'results':[]},503,'unavailable')]:
            result,calls=await self.run_search(payload,status)
            self.assertEqual(result.outcome,outcome)
            self.assertEqual(len(calls),1)

    async def test_cancellation_and_attempt_cap_prevent_gateway_dispatch(self):
        calls=[]
        async def handler(request):calls.append(request);raise AssertionError()
        http=PublicHTTP(transport=httpx2.MockTransport(handler))
        http.attempts=14
        try:
            result=await search('Python release',http=http,limiter=ProviderLimiter())
            self.assertEqual(result.outcome,'unavailable');self.assertEqual(calls,[])
        finally:await http.aclose()
