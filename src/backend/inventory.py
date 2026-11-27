"""The configured topology and the v1 native observation contract."""

import json
import math
import os
from pathlib import Path
import stat

NODES = {
    "fios-core": ("Mac mini", "M4 Pro", 24, "Control plane"),
    "studio-a": ("Mac Studio", "M3 Ultra", 256, "Inference worker"),
    "studio-b": ("Mac Studio", "M3 Ultra", 256, "Inference worker"),
}
OBSERVATIONS = Path(".fios/observations")
STALE_AFTER = 30
MAX_BYTES = 4096
FIELDS = {"version", "node", "sampled_at", "memory_bytes", "logical_cpus", "load_1m"}


def valid_sample(data, node, now):
    if not isinstance(data, dict) or data.keys() != FIELDS or data["node"] != node:
        return False
    for key, lower, upper in (
        ("version", 1, 1), ("sampled_at", 1, now),
        ("memory_bytes", 1, 2**60), ("logical_cpus", 1, 65536),
    ):
        if type(data[key]) is not int or not lower <= data[key] <= upper:
            return False
    load = data["load_1m"]
    return type(load) in (int, float) and 0 <= load <= 1e9 and math.isfinite(load)


def read_node(directory, node, now):
    hardware, chip, ram, role = NODES[node]
    item = dict(id=node, hardware=hardware, chip=chip, configured_gb=ram,
                role=role, state="awaiting", observation=None)
    try:
        fd = os.open(directory / f"{node}.json", os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        return item
    except OSError:
        return dict(item, state="invalid")
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise ValueError("Expected a regular file")
        payload = os.read(fd, MAX_BYTES + 1)
        if len(payload) > MAX_BYTES:
            raise ValueError("Observation too large")
        data = json.loads(payload)
        if not valid_sample(data, node, now):
            raise ValueError("Invalid observation")
    except (OSError, ValueError, RecursionError):
        return dict(item, state="invalid")
    finally:
        os.close(fd)
    state = "stale" if now - data["sampled_at"] > STALE_AFTER else "reporting"
    return dict(item, state=state, observation=data)
