"""Read one Studio's local resources for a large-model preflight report."""

import argparse
import json
from pathlib import Path
import shutil
import socket
import sys
import time

from agent.macos_memory import headroom
from backend.enrollment import Rejected
from backend.heartbeat import json_object
from backend.host_agent import observe
from backend.moe_preflight import verify_probe_directory

STUDIO_HOSTS = {"fios-edge-a": "studio-a", "fios-edge-b": "studio-b"}


def sample(directory, *, hostname):
    slot = STUDIO_HOSTS.get(hostname.split(".")[0])
    if sys.platform != "darwin" or slot is None:
        raise ValueError("Resource sampling requires one of the two fios Studios")
    if not directory.is_absolute() or not directory.is_dir():
        raise ValueError("Supply the existing absolute staging directory")
    host = observe(slot)
    available, pressure = headroom(host["memory_bytes"])
    return slot, dict(sampled_at=host["sampled_at"], disk_free=shutil.disk_usage(directory).free,
                      headroom=available, pressure=pressure)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("staging_directory", type=Path)
    parser.add_argument("--verify-probe", type=Path, help="Check staged files against a current probe approval")
    args = parser.parse_args()
    try:
        slot, observation = sample(args.staging_directory, hostname=socket.gethostname())
        if args.verify_probe:
            with args.verify_probe.open("rb") as stream:
                approval = json_object(stream.read(8192))
            expires = approval.get("expires_at")
            if (approval.get("ok") is not True or approval.get("stage") != "probe"
                    or type(expires) is not int or not 0 < expires - time.time() <= 30):
                raise Rejected("stage_approval_unavailable", 409)
            verify_probe_directory(args.staging_directory, approval.get("files"))
    except (ValueError, OSError) as error:
        parser.exit(1, f"{error}\n")
    print(json.dumps({slot: observation}, allow_nan=False))


if __name__ == "__main__":
    main()
