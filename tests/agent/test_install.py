"""Packaging checks run without network access or model initialization."""
import unittest
from importlib.metadata import version


class InstallationTests(unittest.TestCase):
    def test_platform_entry_is_installed_not_checkout(self):
        from pathlib import Path
        import sysconfig
        from fios_agent import platform_guard, platform_protocol, platform_worker
        site=Path(sysconfig.get_path('purelib')).resolve()
        for module in (platform_guard,platform_protocol,platform_worker):
            self.assertTrue(Path(module.__file__).resolve().is_relative_to(site),'Private platform entry must use the installed distribution')

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
