"""Killable extraction helper within the application container, not a service."""
import asyncio
import json
import sys
from pathlib import Path

from .http import WebFailure


async def parse_document(raw,mode):
    if mode not in ('page','provider') or len(raw)>1048576: raise ValueError('parser_input')
    # Execute the installed stdlib-only helper by installed path. Importing the
    # whole package in a memory-limited child would waste its resource budget.
    path=str(Path(__file__).with_name('parser.py'))
    process=await asyncio.create_subprocess_exec(sys.executable,'-I','-B',path,mode,
        stdin=asyncio.subprocess.PIPE,stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,env={})
    try:
        async def exchange():
            async def write():
                process.stdin.write(raw)
                await process.stdin.drain()
                process.stdin.close()
            writer=asyncio.create_task(write())
            try:
                output=await process.stdout.read(65537)
                if len(output)>65536: raise WebFailure()
                await writer
                await process.wait()
                if process.returncode: raise WebFailure()
                return json.loads(output.decode('utf-8'))
            finally:
                writer.cancel()
                await asyncio.gather(writer,return_exceptions=True)
        async with asyncio.timeout(1): return await exchange()
    finally:
        if process.returncode is None:
            process.kill()
        await process.wait()


def decode_text(headers,raw):
    content_type=headers.get('content-type','').lower()
    media=content_type.split(';')[0].strip()
    if media not in ('text/html','text/plain'): raise WebFailure()
    if 'charset=' in content_type and content_type.split('charset=',1)[1].split(';')[0].strip(' \"') not in ('utf-8','utf8'):
        raise WebFailure()
    try: text=raw.decode('utf-8','strict')
    except UnicodeError: raise WebFailure() from None
    return media,text
