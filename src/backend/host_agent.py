"""Sample native macOS telemetry into a local directory."""

import argparse
import json
import os
from pathlib import Path
import platform
import subprocess
import tempfile
import time

from .inventory import NODES, OBSERVATIONS, valid_sample


def observe(node):
    if platform.system() != "Darwin":
        raise ValueError("Run the host agent natively on macOS.")
    memory = subprocess.check_output(
        ["/usr/sbin/sysctl", "-n", "hw.memsize"], timeout=3, text=True,
    )
    return dict(version=1, node=node, sampled_at=int(time.time()),
                memory_bytes=int(memory), logical_cpus=os.cpu_count(),
                load_1m=round(os.getloadavg()[0], 2))


def publish(directory, sample):
    node = sample["node"]
    if node not in NODES or not valid_sample(sample, node, int(time.time())):
        raise ValueError("Cannot publish invalid host observation")
    directory.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        directory.mkdir(mode=0o711)
    except FileExistsError:
        if not directory.is_dir():
            raise
    else:
        # A restrictive umask still permits the container to open known files.
        directory.chmod(0o711)
    with tempfile.NamedTemporaryFile(dir=directory, mode="w", delete=False) as tmp:
        path = Path(tmp.name)
        try:
            json.dump(sample, tmp, allow_nan=False)
            tmp.write("\n")
            tmp.flush()
            # The container's unprivileged UID shares only this directory.
            os.fchmod(tmp.fileno(), 0o644)
            os.replace(path, directory / f"{node}.json")
        finally:
            path.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--node", required=True, choices=NODES)
    parser.add_argument("--directory", type=Path, default=OBSERVATIONS)
    parser.add_argument("--watch", action="store_true", help="Repeat every five seconds")
    args = parser.parse_args()
    try:
        while True:
            publish(args.directory, observe(args.node))
            if not args.watch:
                break
            time.sleep(5)
    except KeyboardInterrupt:
        pass
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Observation failed: {error}\n")


if __name__ == "__main__":
    main()
