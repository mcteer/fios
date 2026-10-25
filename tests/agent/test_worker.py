import asyncio
import unittest
from pydantic_ai import CancellationToken
from fios_agent.worker import Worker, Settings
from fios_agent.protocol import parse_command
from uuid import uuid4


class WorkerTests(unittest.IsolatedAsyncioTestCase):
    async def test_control_token_cancellation_and_cleanup(self):
        worker = Worker(Settings('http://127.0.0.1:1/v1','local'),None,None)
        token=CancellationToken()
        started=asyncio.Event()
        cleaned=asyncio.Event()
        async def execute(command, current):
            started.set()
            try:
                while not current.cancelled:
                    await asyncio.sleep(.001)
            finally:
                cleaned.set()
        worker.execute=execute
        command=parse_command({'v':2,'type':'run','run_id':str(uuid4()),'model':'test/model',
                               'context':[{'role':'user','content':'hello'}]})
        task=asyncio.create_task(worker.run_task(command,token))
        worker.active=(command,token,task)
        await started.wait()
        await worker.stop()
        self.assertTrue(cleaned.is_set())
        self.assertIsNone(worker.active)
