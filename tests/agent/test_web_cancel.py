import asyncio
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import fios_agent.web.pages as pages


class ParserCancellationTests(unittest.IsolatedAsyncioTestCase):
    async def test_unresponsive_parser_is_killed_and_reaped_on_cancel(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)
            (path/'parser.py').write_text('import time\ntime.sleep(60)\n')
            real=asyncio.create_subprocess_exec
            children=[]
            async def capture(*args,**kwargs):
                child=await real(*args,**kwargs)
                children.append(child)
                return child
            with patch.object(pages,'__file__',str(path/'pages.py')),patch.object(pages.asyncio,'create_subprocess_exec',side_effect=capture):
                task=asyncio.create_task(pages.parse_document(b'<p>fixture</p>','page'))
                for _ in range(100):
                    if children:break
                    await asyncio.sleep(.005)
                self.assertTrue(children)
                task.cancel()
                with self.assertRaises(asyncio.CancelledError):await task
                self.assertIsNotNone(children[0].returncode)

    async def test_parser_wall_timeout_does_not_leave_a_background_child(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)
            (path/'parser.py').write_text('import time\ntime.sleep(60)\n')
            with patch.object(pages,'__file__',str(path/'pages.py')):
                start=asyncio.get_running_loop().time()
                with self.assertRaises(TimeoutError):await pages.parse_document(b'x','page')
                self.assertLess(asyncio.get_running_loop().time()-start,2)
