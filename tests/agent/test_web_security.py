import asyncio
from pathlib import Path
import unittest
from fios_agent.web.pages import parse_document
from fios_agent.web.http import PublicBackend,WebFailure
from fios_agent.web.query import validate_query
from fios_agent.web.types import RunSearchInput


class SearchSecurityTests(unittest.IsolatedAsyncioTestCase):
    async def test_fixture_ads_and_active_content_never_become_evidence(self):
        root=Path(__file__).resolve().parents[1]/'fixtures/web'
        provider=await parse_document((root/'provider.html').read_bytes(),'provider')
        self.assertEqual(len(provider['results']),1)
        page=await parse_document((root/'page.html').read_bytes(),'page')
        self.assertNotIn('send_private_context',page['text'])
        self.assertNotIn('Hidden data',page['text'])
        self.assertNotIn('Navigation not evidence',page['text'])
        self.assertIn('run_shell',page['text']) # Visible hostile prose stays untrusted data, not executable.

    async def test_cancellation_after_resolution_never_connects(self):
        cancelled=[False]; connections=[]
        def check():
            if cancelled[0]:raise WebFailure()
        async def resolve(host):
            cancelled[0]=True
            return ['8.8.8.8']
        class Delegate:
            async def connect_tcp(self,*args,**kwargs):connections.append(args);raise AssertionError('forbidden connection')
        backend=PublicBackend(resolve=resolve,delegate=Delegate(),check=check)
        with self.assertRaises(WebFailure):await backend.connect_tcp('example.com',443)
        self.assertEqual(connections,[])

    async def test_private_context_and_attachment_only_terms_not_eligible(self):
        p=RunSearchInput(current_text='Python release',previous_text=None,current_has_attachments=False,
                        previous_has_attachments=False,current_elided=False,previous_elided=False)
        for query in ['attachmentcanary2026 release','Python bearer SECRET','Python site:internal.lab','Python ../credentials']:
            with self.assertRaises(ValueError):validate_query(query,p)
