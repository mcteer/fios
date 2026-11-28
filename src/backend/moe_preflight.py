"""Check the stage-specific resources needed by a paired model acquisition."""

from pathlib import PurePosixPath
import re

from .enrollment import Rejected, STUDIOS
from .job_ledger import integer
from .pair_trial import GIB, LARGE_FLOOR, PAIR_ONLY, digest


def estimate_single_host(pack_bytes, budgets):
    """Project an unsharded footprint with the heavier rank's overhead."""
    even_partition = (pack_bytes + 1) // 2
    overhead = max(0, max(item["peak_bytes"] for item in budgets.values()) - even_partition)
    peak = pack_bytes + overhead
    return dict(peak_bytes=peak, fits_estimate=peak + LARGE_FLOOR <= 256 * GIB, placement=PAIR_ONLY)


def check_host_budgets(budgets, observations, *, now):
    """Return the first slot-specific refusal using independently sampled hosts."""
    if not isinstance(budgets, dict) or budgets.keys() != set(STUDIOS):
        raise Rejected("invalid_budgets")
    if not isinstance(observations, dict) or observations.keys() != set(STUDIOS):
        raise Rejected("invalid_observations")

    for slot in STUDIOS:
        budget = budgets[slot]
        sample = observations[slot]
        if not isinstance(budget, dict) or budget.keys() != {"disk_bytes", "peak_bytes"}:
            raise Rejected("invalid_budgets")
        disk = integer(budget["disk_bytes"], 1, 2**60)
        peak = integer(budget["peak_bytes"], 1, 256 * GIB - LARGE_FLOOR)
        fields = {"sampled_at", "disk_free", "headroom", "pressure"}
        if not isinstance(sample, dict) or sample.keys() != fields:
            raise Rejected("invalid_observations")
        sampled = integer(sample["sampled_at"], 0, 2**63 - 1)
        disk_free = integer(sample["disk_free"], 0, 2**60)
        headroom = integer(sample["headroom"], 0, 256 * GIB)
        if not 0 <= now - sampled <= 30:
            return {"slot": slot, "reason": "stale_capacity"}
        if sample["pressure"] != "normal":
            return {"slot": slot, "reason": "memory_pressure"}
        if disk_free < disk:
            return {"slot": slot, "reason": "insufficient_disk"}
        # A large amount of memory on the peer cannot cover a heavy partition.
        if headroom < peak + LARGE_FLOOR:
            return {"slot": slot, "reason": "insufficient_headroom"}
    return None


def probe_files(value):
    """Accept only flat, digest-pinned files with an aggregate transfer ceiling."""
    if not isinstance(value, dict) or not 1 <= len(value) <= 24:
        raise Rejected("invalid_probe_files")
    total = 0
    for name, item in value.items():
        if (not isinstance(name, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,119}", name)
                or PurePosixPath(name).suffix not in (".safetensors", ".json", ".jinja", ".model", ".txt")
                or not isinstance(item, dict) or item.keys() != {"sha256", "bytes"}):
            raise Rejected("invalid_probe_files")
        digest(item["sha256"])
        total += integer(item["bytes"], 1, GIB)
    if total > GIB or not any(name.endswith(".safetensors") for name in value):
        raise Rejected("invalid_probe_files")
    return total


def verify_probe_directory(directory, files):
    """Verify a prepared probe directory before passing it to the native loader."""
    from hashlib import file_digest
    import os
    import stat

    probe_files(files)
    directory_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        if set(os.listdir(directory_fd)) != files.keys():
            raise Rejected("unexpected_probe_file")
        for name, expected in files.items():
            fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=directory_fd)
            with os.fdopen(fd, "rb") as stream:
                before = os.fstat(stream.fileno())
                if not stat.S_ISREG(before.st_mode) or before.st_size != expected["bytes"]:
                    raise Rejected("probe_file_size")
                if file_digest(stream, "sha256").hexdigest() != expected["sha256"]:
                    raise Rejected("probe_file_digest")
                after = os.fstat(stream.fileno())
                if (before.st_size, before.st_mtime_ns, before.st_ctime_ns) != (
                        after.st_size, after.st_mtime_ns, after.st_ctime_ns):
                    raise Rejected("probe_file_changed")
    finally:
        os.close(directory_fd)
