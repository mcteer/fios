import unittest
from fios_agent.web.http import public_address, validate_url, PublicBackend, PublicTransport, PublicHTTP, WebFailure


class PublicAddressTests(unittest.TestCase):
    def test_special_use_addresses_rejected(self):
        for value in ['127.0.0.1','10.0.0.1','192.168.1.1','169.254.169.254','100.64.1.1',
                      '192.0.2.1','198.18.0.1','224.0.0.1','0.0.0.0','::1','::',
                      '::ffff:8.8.8.8','64:ff9b::808:808','2002:0808:0808::1','2001:db8::1','ff02::1']:
            with self.subTest(value=value): self.assertFalse(public_address(value))
        self.assertTrue(public_address('8.8.8.8'))
        self.assertTrue(public_address('2606:4700:4700::1111'))

    def test_transport_uses_locked_ca_bundle_with_verification_enabled(self):
        import certifi
        import ssl
        from unittest.mock import patch
        with patch('ssl.create_default_context',wraps=ssl.create_default_context) as context:
            transport=PublicTransport()
            context.assert_called_once_with(cafile=certifi.where())
        # The transport is never used; no pool connection exists to close.

    def test_url_gate(self):
        self.assertEqual(validate_url('https://www.python.org/doc/'), 'https://www.python.org/doc/')
        for url in ['http://localhost/','https://x.lab/','file:///tmp/a','https://127.0.0.1/',
                    'https://[::1]/','https://example.com/?access_token=secret','https://user:secret@example.com/','https://example.com:8443/',
                    'https://example.com\\@localhost/','https://2130706433/','https://0x7f000001/',
                    'https://example.com/#x','https://example.com/\n']:
            with self.subTest(url=url), self.assertRaises(WebFailure): validate_url(url)


class BackendTests(unittest.IsolatedAsyncioTestCase):
    async def test_socket_pinned_and_mixed_dns_closed(self):
        class Stream:
            closed=False
            def get_extra_info(self,key): return ('8.8.8.8',443) if key=='server_addr' else None
            async def aclose(self): self.closed=True
        class Delegate:
            calls=[]
            async def connect_tcp(self,host,port,**kwargs):
                self.calls.append((host,port)); return Stream()
        delegate=Delegate()
        async def resolve(host): return ['8.8.8.8']
        backend=PublicBackend(resolve=resolve,delegate=delegate)
        await backend.connect_tcp('example.com',443)
        self.assertEqual(delegate.calls,[('8.8.8.8',443)])
        async def mixed(host): return ['8.8.8.8','127.0.0.1']
        backend=PublicBackend(resolve=mixed,delegate=delegate)
        with self.assertRaises(WebFailure): await backend.connect_tcp('example.com',443)
        self.assertEqual(len(delegate.calls),1)

    async def test_original_tls_hostname_and_minimal_headers_reach_pinned_socket(self):
        import ssl
        calls=[]; writes=[]
        class Stream:
            data=b'HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\n\r\nok'
            async def read(self,max_bytes,timeout=None):
                value=self.data;self.data=b'';return value
            async def write(self,buffer,timeout=None): writes.append(buffer)
            async def aclose(self): pass
            def get_extra_info(self,key):return ('8.8.8.8',443) if key=='server_addr' else None
            async def start_tls(self,ssl_context,server_hostname=None,timeout=None):
                calls.append(('tls',server_hostname,ssl_context.check_hostname,ssl_context.verify_mode))
                return self
        class Delegate:
            async def connect_tcp(self,host,port,**kwargs):calls.append(('tcp',host,port));return Stream()
        async def resolve(host):return ['8.8.8.8']
        transport=PublicTransport(backend=PublicBackend(resolve=resolve,delegate=Delegate()))
        http=PublicHTTP(transport=transport)
        try:
            status,headers,body=await http.get('https://example.com/')
            self.assertEqual((status,body),(200,b'ok'))
            self.assertIn(('tcp','8.8.8.8',443),calls)
            self.assertIn(('tls','example.com',True,ssl.CERT_REQUIRED),calls)
            request=b''.join(writes).lower()
            self.assertIn(b'host: example.com',request)
            for forbidden in [b'authorization:',b'cookie:',b'referer:',b'x-forwarded-for:']:
                self.assertNotIn(forbidden,request)
        finally:await http.aclose()

    async def test_dns_cname_to_configured_peer_is_rejected(self):
        from unittest.mock import patch
        import dns.message,dns.rrset,dns.name
        from fios_agent.web.http import resolve_public
        class Answer:
            canonical_name=dns.name.from_text('public.example.com.')
            rrset=dns.rrset.from_text('public.example.com.',60,'IN','A','8.8.8.8')
            response=dns.message.Message()
            def __iter__(self):return iter(self.rrset)
        answer=Answer()
        answer.response.answer=[dns.rrset.from_text('example.com.',60,'IN','CNAME','gateway.internal.')]
        async def resolve(*args,**kwargs):return answer
        with patch('dns.asyncresolver.Resolver.resolve',side_effect=resolve):
            with self.assertRaises(WebFailure):await resolve_public('example.com',('gateway.internal',))

    async def test_peer_mismatch_closed(self):
        class Stream:
            closed=False
            def get_extra_info(self,key): return ('127.0.0.1',443)
            async def aclose(self): self.closed=True
        stream=Stream()
        class Delegate:
            async def connect_tcp(self,*args,**kwargs): return stream
        async def resolve(host): return ['8.8.8.8']
        with self.assertRaises(WebFailure):
            await PublicBackend(resolve=resolve,delegate=Delegate()).connect_tcp('example.com',443)
        self.assertTrue(stream.closed)
