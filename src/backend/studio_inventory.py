"""Read a live, sanitized Studio snapshot from the native service."""

import http.client
import json
import time

from .inventory import NODES, valid_sample
from .wire import read_reply

STUDIOS = tuple(node for node in NODES if node != "fios-core")


def studio_nodes(port):
    connection = http.client.HTTPConnection("127.0.0.1", port, timeout=1)
    try:
        deadline = time.monotonic() + 1
        connection.request("GET", "/v1/studios")
        status, payload = read_reply(connection.sock, deadline, 8192)
        if status != 200:
            raise ValueError
        snapshot = json.loads(payload)
        if not isinstance(snapshot, dict) or set(snapshot) != set(STUDIOS):
            raise ValueError
        for node in STUDIOS:
            if not valid_record(snapshot[node], node):
                raise ValueError
    except (OSError, ValueError, http.client.HTTPException, RecursionError):
        snapshot = dict.fromkeys(STUDIOS, {"enrollment": "unknown", "state": "invalid",
                                          "observation": None})
    finally:
        connection.close()
    result = []
    for node in STUDIOS:
        hardware, chip, ram, role = NODES[node]
        result.append(dict(id=node, hardware=hardware, chip=chip, configured_gb=ram,
                           role=role, **snapshot[node]))
    return result


def valid_record(record, node):
    if not isinstance(record, dict) or record.keys() != {"enrollment", "state", "observation"}:
        return False
    enrollment, state, sample = record["enrollment"], record["state"], record["observation"]
    if state == "awaiting":
        return enrollment in ("not_enrolled", "active", "revoked") and sample is None
    # The native service is authoritative for freshness. Preserve stale observations
    # even if the wall clock has since been adjusted.
    return (enrollment == "active" and state in ("reporting", "stale")
            and valid_sample(sample, node, 253402300799))
