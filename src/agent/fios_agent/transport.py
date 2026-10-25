"""Observe upstream framing; the Pydantic provider alone performs inference."""
import json
import time
import httpx2


class StreamFailure(ValueError):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


class SentinelObserver:
    def __init__(self, limit=4 * 1024 * 1024):
        self.limit = limit
        self.line = bytearray()
        self.data = []
        self.frame_size = 0
        self.done = False

    def feed(self, chunk):
        offset = 0
        while offset < len(chunk):
            end = chunk.find(b'\n', offset)
            boundary = len(chunk) if end < 0 else end
            segment = chunk[offset:boundary]
            self.frame_size += len(segment) + (end >= 0)
            if self.frame_size > self.limit:
                raise StreamFailure('invalid_stream')
            self.line.extend(segment)
            if end < 0:
                return
            line = bytes(self.line).removesuffix(b'\r')
            self.line.clear()
            if not line:
                if self.data:
                    payload = b'\n'.join(self.data)
                    if payload == b'[DONE]':
                        self.done = True
                    else:
                        try:
                            obj = json.loads(payload.decode('utf-8'))
                            if not isinstance(obj, dict) or 'error' in obj or not isinstance(obj.get('choices'), list):
                                raise ValueError()
                        except (ValueError, UnicodeError, RecursionError):
                            raise StreamFailure('invalid_stream') from None
                    self.data.clear()
                self.frame_size = 0
            elif line.startswith(b'data:'):
                self.data.append(line[5:].removeprefix(b' '))
            elif not line.startswith((b':', b'event:', b'id:', b'retry:')):
                raise StreamFailure('invalid_stream')
            offset = end + 1

    def finish(self):
        if not self.done:
            raise StreamFailure('incomplete_stream')


class ObservedStream(httpx2.AsyncByteStream):
    def __init__(self, stream, observer, activity):
        self.stream, self.observer, self.activity = stream, observer, activity
        self.last_activity = 0.0

    async def __aiter__(self):
        async for chunk in self.stream:
            if chunk:
                self.observer.feed(chunk)
                now = time.monotonic()
                if now - self.last_activity >= 1:
                    self.last_activity = now
                    await self.activity()
            yield chunk
        self.observer.finish()

    async def aclose(self):
        await self.stream.aclose()


class ObservingTransport(httpx2.AsyncBaseTransport):
    def __init__(self, observer, activity, inner=None):
        self.inner = inner or httpx2.AsyncHTTPTransport(retries=0, trust_env=False)
        self.observer, self.activity = observer, activity

    async def handle_async_request(self, request):
        response = await self.inner.handle_async_request(request)
        if response.status_code == 200:
            if response.is_stream_consumed:
                # MockTransport may return a pre-buffered response; production
                # transport remains streaming and never buffers the full body.
                self.observer.feed(response.content)
                await self.activity()
            else:
                response.stream = ObservedStream(response.stream, self.observer, self.activity)
        return response

    async def aclose(self):
        await self.inner.aclose()
