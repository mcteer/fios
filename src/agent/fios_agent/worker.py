"""Private pipe worker lifecycle; no network listener or database access."""
from __future__ import annotations

import asyncio
import json
import os
import sys
from dataclasses import dataclass, field
from urllib.parse import urlsplit

from pydantic_ai import CancellationToken

from .protocol import (
    REQUEST_LIMIT, Cancel, FrameDecoder, ProtocolError, Run, Shutdown,
    encode_frame, parse_command, parse_event,
)


def diagnostic(code: str, *, run_id: str | None = None):
    record = {"phase": "worker", "code": code}
    if run_id:
        record["run_id"] = run_id
    sys.stderr.write(json.dumps(record, separators=(",", ":")) + "\n")
    sys.stderr.flush()


@dataclass(frozen=True)
class Settings:
    base_url: str
    api_key: str
    peers: dict[str, str] = field(default_factory=dict)
    readiness_file: str | None = None

    @classmethod
    def from_environment(cls):
        base = os.environ.get("MLX_BASE_URL", "http://host.docker.internal:11234/v1")
        parsed = urlsplit(base)
        if (parsed.scheme not in ("http", "https") or not parsed.hostname
                or parsed.username is not None or parsed.password is not None
                or parsed.query or parsed.fragment or "?" in base or "#" in base
                or any(c.isspace() or ord(c) < 32 for c in base)):
            raise ValueError("Invalid configuration.")
        # Force port validation without leaking its value on failure.
        parsed.port
        from .availability import peer_configuration
        return cls(base.rstrip("/"), os.environ.get("MLX_API_KEY") or "fios-local-no-key",
                   peer_configuration(os.environ.get("MLX_PEER_URLS", "{}")),
                   os.environ.get("MLX_READINESS_FILE") or None)


class OutputProtocol(asyncio.streams.FlowControlMixin):
    def __init__(self):
        super().__init__()
        self.closed = asyncio.get_running_loop().create_future()

    def connection_lost(self, exc):
        super().connection_lost(exc)
        if not self.closed.done():
            self.closed.set_result(None)

    def _get_close_waiter(self, stream):
        return self.closed


async def pipe_streams():
    loop = asyncio.get_running_loop()
    reader = asyncio.StreamReader(limit=65536)
    read_protocol = asyncio.StreamReaderProtocol(reader)
    read_transport, _ = await loop.connect_read_pipe(lambda: read_protocol, sys.stdin.buffer)
    write_protocol = OutputProtocol()
    write_transport, _ = await loop.connect_write_pipe(lambda: write_protocol, sys.stdout.buffer)
    writer = asyncio.StreamWriter(write_transport, write_protocol, None, loop)
    return reader, writer, read_transport


class Worker:
    def __init__(self, settings: Settings, reader, writer):
        self.settings = settings
        self.reader, self.writer = reader, writer
        self.write_lock = asyncio.Lock()
        self.active: tuple[Run, CancellationToken, asyncio.Task] | None = None

    async def emit(self, frame):
        parse_event(frame)
        encoded = encode_frame(frame)
        async with self.write_lock:
            self.writer.write(encoded)
            await self.writer.drain()

    async def execute(self, command: Run, token: CancellationToken):
        from .harness import run_agent
        await self.emit({"v": 1, "type": "started", "run_id": command.run_id})
        await run_agent(command, token, self.emit, self.settings)

    async def run_task(self, command, token):
        try:
            await self.execute(command, token)
        except asyncio.CancelledError:
            raise
        except (BrokenPipeError, ConnectionError):
            raise
        except Exception:
            diagnostic("internal_error", run_id=command.run_id)
            await self.emit({"v": 1, "type": "error", "run_id": command.run_id, "code": "internal_error"})
        finally:
            self.active = None

    async def stop(self):
        if self.active:
            _, token, task = self.active
            token.cancel()
            # EOF/shutdown may mean no stdout reader; do not wait forever for drain.
            try:
                await asyncio.wait_for(task, 0.75)
            except (asyncio.TimeoutError, BrokenPipeError, ConnectionError):
                task.cancel()
                await asyncio.gather(task, return_exceptions=True)

    async def serve(self):
        decoder = FrameDecoder(REQUEST_LIMIT)
        await self.emit({"v": 1, "type": "ready"})
        try:
            while chunk := await self.reader.read(65536):
                for raw in decoder.feed(chunk):
                    command = parse_command(raw)
                    if isinstance(command, Shutdown):
                        return
                    if isinstance(command, Cancel):
                        if self.active and command.run_id == self.active[0].run_id:
                            self.active[1].cancel()
                    elif isinstance(command, Run):
                        if self.active:
                            await self.emit({"v": 1, "type": "error", "run_id": command.run_id, "code": "busy"})
                        else:
                            # Allocate before another frame can deliver immediate cancellation.
                            token = CancellationToken()
                            task = asyncio.create_task(self.run_task(command, token))
                            self.active = command, token, task
            decoder.finish()
        finally:
            await self.stop()


async def main():
    try:
        settings = Settings.from_environment()
        # Validate all inference imports before readiness, without invoking a model.
        from .harness import run_agent
    except (ValueError, UnicodeError):
        diagnostic("configuration_error")
        return 1
    reader, writer, read_transport = await pipe_streams()
    try:
        await Worker(settings, reader, writer).serve()
        return 0
    except ProtocolError:
        diagnostic("protocol_error")
        return 1
    except (BrokenPipeError, ConnectionError):
        return 1
    except Exception:
        diagnostic("internal_error")
        return 1
    finally:
        read_transport.close()
        writer.close()
