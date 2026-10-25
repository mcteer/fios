"""Packaging checks run without network access or model initialization."""
import unittest
from importlib.metadata import version


class InstallationTests(unittest.TestCase):
    def test_pinned_runtime_imports(self):
        import fios_agent
        import pydantic_ai
        import openai
        import httpx2

        self.assertTrue(fios_agent.__file__)
        self.assertEqual(version("pydantic-ai-slim"), "2.61.0")
        self.assertEqual(version("openai"), "3.37.0")
        self.assertEqual(version("httpx2"), "2.16.0")
        with self.assertRaises(ModuleNotFoundError):
            version("pydantic-ai")
