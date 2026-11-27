"""Run scoped launchd jobs in the current macOS login session."""

from contextlib import contextmanager
import os
import plistlib
import re
import subprocess
import time


class Jobs:
    def __init__(self, root, prefix, source):
        self.root = root
        self.prefix = prefix
        self.source = source
        self.domain = f"gui/{os.getuid()}"

    def target(self, name):
        return f"{self.domain}/{self.prefix}.{name}"

    def inspect(self, name):
        return subprocess.run(["launchctl", "print", self.target(name)],
                              capture_output=True, text=True, timeout=5)

    def pid(self, name):
        match = re.search(r"^\s*pid = (\d+)$", self.inspect(name).stdout, re.M)
        return int(match[1]) if match else None

    @contextmanager
    def job(self, name, arguments):
        label = f"{self.prefix}.{name}"
        path = self.root / f"{label}.plist"
        data = dict(Label=label, ProgramArguments=list(map(str, arguments)),
                    KeepAlive=True, ThrottleInterval=2,
                    EnvironmentVariables={"PYTHONPATH": str(self.source)},
                    StandardErrorPath=str(self.root / f"{label}.stderr"),
                    StandardOutPath=str(self.root / f"{label}.stdout"))
        path.write_bytes(plistlib.dumps(data))
        subprocess.run(["plutil", "-lint", path], check=True, capture_output=True, timeout=5)
        try:
            subprocess.run(["launchctl", "bootstrap", self.domain, path], check=True, timeout=10)
            yield
        finally:
            if self.inspect(name).returncode == 0:
                subprocess.run(["launchctl", "bootout", self.target(name)], check=True, timeout=10)
            deadline = time.monotonic() + 5
            while self.inspect(name).returncode == 0:
                if time.monotonic() >= deadline:
                    raise RuntimeError(f"Test job still present: {label}")
                time.sleep(0.1)
