"""Fail closed at the boundary to a configured local text-policy checker."""

from http.client import HTTPConnection
import json
import re

from backend.enrollment import Rejected


def require_approved(check, purpose, text):
    try:
        approved = check(purpose, text)
    except Exception:
        # Checker diagnostics can contain the private text passed to it.
        raise Rejected("publication_unavailable", 503) from None
    if approved is not True:
        raise Rejected("publication_withheld", 403)


class LoopbackPolicy:
    """Call a separately qualified local policy service using a fixed contract."""

    def __init__(self, port, *, long_context=False):
        if type(port) is not int or not 1 <= port <= 65535:
            raise ValueError("Invalid policy port")
        self.port = port
        self.timeout = 30.25 if long_context else 5.25

    def __call__(self, purpose, text, revision):
        if not isinstance(revision, str) or not re.fullmatch(r"[a-f0-9]{64}", revision):
            raise ValueError("Invalid policy revision")
        body = json.dumps({"purpose": purpose, "text": text, "revision": revision},
                          ensure_ascii=True).encode("ascii")
        if len(body) > 1024 * 1024:
            return False
        client = HTTPConnection("127.0.0.1", self.port, timeout=self.timeout)
        try:
            client.request("POST", "/v1/classify", body, {"Content-Type": "application/json"})
            with client.getresponse() as response:
                if (response.status != 200
                        or response.headers.get_all("X-Fios-Policy-Revision") != [revision]
                        or response.headers.get_all("Content-Length") not in (["15"], ["16"])
                        or response.headers.get_all("Transfer-Encoding")):
                    raise ValueError("Unverified policy response")
                result = response.read(16)
                if result == b'{"allow":true}\n':
                    return True
                if result == b'{"allow":false}\n':
                    return False
                raise ValueError("Invalid policy decision")
        finally:
            client.close()
