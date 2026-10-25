import unittest
from fios_agent.transport import SentinelObserver, StreamFailure


class TransportTests(unittest.TestCase):
    def test_fragmented_utf8_crlf_usage_and_done(self):
        observer = SentinelObserver()
        data = 'data: {"choices":[],"usage":{}}\r\n\r\ndata: [DONE]\r\n\r\n'.encode()
        for byte in data:
            observer.feed(bytes([byte]))
        observer.finish()
        self.assertTrue(observer.done)

    def test_invalid_empty_missing_or_oversized_stream(self):
        for data in [b'', b'data: {bad}\n\n', b'data: {"choices":[]}\n\n',
                     b'data: {"error":{"message":"secret"}}\n\n']:
            with self.subTest(data=data), self.assertRaises(StreamFailure):
                obs = SentinelObserver(); obs.feed(data); obs.finish()
        with self.assertRaises(StreamFailure):
            SentinelObserver(limit=10).feed(b'x' * 11)

    def test_done_is_known_before_bytes_are_returned(self):
        obs = SentinelObserver()
        obs.feed(b'data: [DONE]\n\n')
        self.assertTrue(obs.done)
