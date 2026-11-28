"""Install an approved reduced probe into a run-owned Studio directory."""

import argparse
from hashlib import sha256
import json
import os
from pathlib import Path
import secrets
import socket
import stat
import tempfile
import time

from backend.enrollment import Rejected, private_path
from backend.heartbeat import json_object
from backend.job_ledger import integer
from backend.moe_preflight import probe_files
from backend.pair_trial import GIB, LARGE_FLOOR

from moe_resources import sample

CHUNK = 1024 * 1024


def copy_reviewed(source, destination, expected, *, expiry, clock):
    # A file can be replaced between metadata review and staging. Read one
    # descriptor and check the exact byte count and digest of what is copied.
    fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as incoming, destination.open("xb") as outgoing:
        info = os.fstat(incoming.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size != expected["bytes"]:
            raise Rejected("probe_file_size")
        digest = sha256()
        left = expected["bytes"]
        while left:
            if clock() >= expiry:
                raise Rejected("stage_approval_unavailable", 409)
            data = incoming.read(min(left, CHUNK))
            if not data:
                raise Rejected("probe_file_size")
            digest.update(data)
            outgoing.write(data)
            left -= len(data)
        if incoming.read(1) or digest.hexdigest() != expected["sha256"]:
            raise Rejected("probe_file_digest")


def stage(source, staging_parent, approval, *, clock=time.time):
    private_path(staging_parent, directory=True)
    expires = approval.get("expires_at")
    if (approval.get("ok") is not True or approval.get("stage") != "probe"
            or type(expires) is not int or not 0 < expires - clock() <= 30):
        raise Rejected("stage_approval_unavailable", 409)
    files = approval.get("files")
    probe_files(files)
    with tempfile.TemporaryDirectory(prefix=".probe-", dir=staging_parent) as work:
        staged = Path(work) / "model"
        staged.mkdir(mode=0o700)
        for name, expected in files.items():
            copy_reviewed(source / name, staged / name, expected, expiry=expires, clock=clock)
        if clock() >= expires:
            raise Rejected("stage_approval_unavailable", 409)
        final = staging_parent / ("probe-" + secrets.token_hex(16))
        staged.rename(final)
    return final


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("staging_parent", type=Path)
    parser.add_argument("approval", type=Path)
    args = parser.parse_args()
    try:
        slot, observed = sample(args.staging_parent, hostname=socket.gethostname())
        private_path(args.approval)
        with args.approval.open("rb") as stream:
            approval = json_object(stream.read(8192))
        budgets = approval.get("budgets")
        budget = budgets.get(slot) if isinstance(budgets, dict) else None
        if not isinstance(budget, dict) or budget.keys() != {"disk_bytes", "peak_bytes"}:
            raise Rejected("invalid_budgets")
        disk = integer(budget["disk_bytes"], probe_files(approval.get("files")), 2**60)
        peak = integer(budget["peak_bytes"], 1, 256 * GIB - LARGE_FLOOR)
        if (observed["disk_free"] < disk or observed["pressure"] != "normal"
                or observed["headroom"] < peak + LARGE_FLOOR):
            raise Rejected("stage_resources_unavailable", 409)
        path = stage(args.source, args.staging_parent, approval)
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")
    print(json.dumps({"slot": slot, "staged": str(path)}, allow_nan=False))


if __name__ == "__main__":
    main()
