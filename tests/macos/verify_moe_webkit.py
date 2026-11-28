"""Exercise the large-model timing harness with a disposable loopback page."""

from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory


FIXTURE = b"""<!doctype html>
<form id="composer">
<select id="alias"><option value="large-moe">Large MoE</option></select>
<textarea id="prompt"></textarea><button id="send">Send</button>
</form>
<div id="status"></div><div id="thread"></div>
<script>
document.getElementById('composer').addEventListener('submit', event => {
  event.preventDefault();
  document.getElementById('thread').innerHTML =
    '<article data-publication="approved" data-job="0123456789abcdef0123456789abcdef"><pre>Fixture answer</pre></article>';
});
</script>
"""


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(FIXTURE)))
        self.end_headers()
        self.wfile.write(FIXTURE)

    def log_message(self, *_):
        pass


def main():
    with TemporaryDirectory(prefix="fios-moe-webkit-") as folder:
        root = Path(folder)
        runner = root / "check-moe"
        subprocess.run(["xcrun", "swiftc", "tests/macos/check_moe_webkit.swift", "-module-cache-path",
                        str(root / "cache"), "-o", str(runner)], check=True, timeout=90)
        fixture = root / "request.json"
        fixture.write_text(json.dumps(dict(candidate="a" * 64, suite="b" * 64, case="cold",
                                           prompt="Synthetic fixture prompt.")))
        with HTTPServer(("127.0.0.1", 0), Handler) as server, ThreadPoolExecutor(max_workers=1) as pool:
            pool.submit(server.serve_forever, 0.1)
            try:
                trial = subprocess.run([str(runner), f"http://127.0.0.1:{server.server_port}/chat",
                                        str(fixture)], capture_output=True, text=True, timeout=25)
            finally:
                server.shutdown()
        if trial.returncode:
            raise ValueError(trial.stderr.strip())
        observed = json.loads(trial.stdout)
        expected = dict(candidate="a" * 64, suite="b" * 64, case="cold",
                        job="0123456789abcdef0123456789abcdef")
        if (set(observed) != set(expected) | {"visible_ms"}
                or {key: observed[key] for key in expected} != expected
                or type(observed["visible_ms"]) is not int or observed["visible_ms"] <= 0):
            raise ValueError("Unexpected WebKit observation")
        print("WebKit submitted the fixture and timed its rendered answer.")


if __name__ == "__main__":
    main()
