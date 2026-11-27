"""Run the browser and worker checks through an isolated OrbStack image."""

import os
from pathlib import Path
import signal
import socket
import subprocess
import sys
import tempfile
from urllib.request import urlopen
from uuid import uuid4


def preview():
    with urlopen("http://127.0.0.1:8741/healthz", timeout=2) as result:
        return result.read()


def main():
    if sys.platform != "darwin" or socket.gethostname().split(".")[0] != "fios-core":
        raise RuntimeError("Run the disposable OrbStack chat rehearsal on fios-core")
    if preview() != b"ok\n":
        raise RuntimeError("Existing preview failed its startup check")
    image = "fios-chat-acceptance:" + uuid4().hex[:12]
    docker = ["docker", "--context", "orbstack"]
    try:
        subprocess.run([*docker, "build", "-t", image, "."], check=True, timeout=120)
        with tempfile.TemporaryDirectory(prefix="fios-webkit-") as folder:
            browser = str(Path(folder) / "check-chat")
            build_env = {**os.environ, "CLANG_MODULE_CACHE_PATH": str(Path(folder) / "clang-cache"),
                         "SWIFT_MODULE_CACHE_PATH": str(Path(folder) / "swift-cache")}
            subprocess.run(["/usr/bin/xcrun", "swiftc", "tests/macos/check_chat_webkit.swift",
                            "-module-cache-path", str(Path(folder) / "module-cache"),
                            "-o", browser], env=build_env, check=True, timeout=90)
            subprocess.run([sys.executable, "-B", "-m", "unittest", "discover",
                            "-s", str(Path("tests").resolve()), "-p", "test_chat_web.py", "-v"],
                           env={**os.environ, "FIOS_CHAT_TEST_IMAGE": image,
                                "FIOS_CHAT_TEST_WEBKIT": browser}, check=True, timeout=90)
    finally:
        subprocess.run([*docker, "image", "rm", image], capture_output=True, timeout=20)
        if preview() != b"ok\n":
            raise RuntimeError("Existing preview is unavailable after teardown")
    mode = "Native MLX and fixture" if os.environ.get("FIOS_CHAT_NATIVE_TRIAL_CONFIG") else "Fixture"
    print(f"{mode} chat checks passed through OrbStack. Existing preview is healthy.")


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, signal.default_int_handler)
    main()
