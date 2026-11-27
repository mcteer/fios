"""Container-side client for the native loopback chat service."""

from http.client import HTTPConnection, HTTPException
import json
from pathlib import Path

REQUEST_LIMIT = 112 * 1024
RESPONSE_LIMIT = 5 * 1024 * 1024


class BridgeError(ValueError):
    def __init__(self, reason, status):
        super().__init__(reason)
        self.status = status


class ChatBridge:
    def __init__(self, port, secret_file):
        if type(port) is not int or not 1 <= port <= 65535:
            raise ValueError("Invalid chat bridge port")
        self.port = port
        with Path(secret_file).open("rb") as stream:
            self.token = stream.read(33).hex()
        if len(self.token) != 64:
            raise ValueError("Chat bridge key requires 32 bytes")

    def call(self, action, data):
        body = json.dumps({"action": action, "data": data}, ensure_ascii=True).encode("ascii")
        if len(body) > REQUEST_LIMIT:
            raise BridgeError("too_large", 413)
        client = HTTPConnection("127.0.0.1", self.port, timeout=2)
        try:
            client.request("POST", "/v1/chat", body, {
                "Content-Type": "application/json", "Authorization": "Bearer " + self.token,
            })
            with client.getresponse() as response:
                wire = response.read(RESPONSE_LIMIT + 1)
                if len(wire) > RESPONSE_LIMIT:
                    raise BridgeError("unavailable", 503)
                reply = json.loads(wire)
                if response.status != 200:
                    raise BridgeError(reply.get("reason", "unavailable"), response.status)
                return reply
        except BridgeError:
            raise
        except (OSError, HTTPException, UnicodeError, ValueError):
            raise BridgeError("unavailable", 503) from None
        finally:
            client.close()
