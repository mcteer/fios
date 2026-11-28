"""Inspect immutable model metadata and stage one approved full-pack shard at a time."""

import argparse
from hashlib import file_digest, sha1, sha256
import json
import os
from pathlib import Path
import re
import socket
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.request import urlopen

from agent.native_runtime import manifest_digest
from backend.enrollment import Rejected, private_path
from backend.heartbeat import json_object
from backend.pair_trial import LARGE_FLOOR
from moe_resources import sample

PACKS = {
    "glm": ("pipenetwork/GLM-5.3-MLX-mixed-3_6bit", "4c4ce289cd0b7815dd7b30af3d0320647feb8fd9"),
    "qwen": ("mlx-community/Qwen3.5-397B-A17B-4bit", "39159bd8aa74f5c8446d2b2dc584f62bb51cb0d3"),
}
SUFFIXES = {".safetensors", ".json", ".txt", ".jinja", ".model"}
FILE_LIMIT = 32 * 1024 * 1024


def read_url(url, limit):
    with urlopen(url, timeout=30) as source:
        data = source.read(limit + 1)
    if len(data) > limit:
        raise ValueError("Metadata artifact exceeds its byte limit")
    return data


def pack_info(candidate):
    repo, revision = PACKS[candidate]
    snapshot = json_object(read_url(f"https://huggingface.co/api/models/{repo}/revision/{revision}?blobs=true",
                                    256 * 1024))
    if snapshot["sha"] != revision:
        raise ValueError("Model repository returned a different revision")
    files = {}
    for item in snapshot["siblings"]:
        name = item["rfilename"]
        if Path(name).suffix not in SUFFIXES:
            continue
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,119}", name) or name in files:
            raise ValueError("Unexpected model artifact name")
        size = item["size"]
        if type(size) is not int or size <= 0:
            raise ValueError("Invalid model artifact size")
        if "lfs" in item:
            checksum = item["lfs"]["sha256"]
        elif Path(name).suffix == ".safetensors":
            raise ValueError("Weights require a pinned SHA-256 digest")
        else:
            data = read_url(f"https://huggingface.co/{repo}/resolve/{revision}/{name}", FILE_LIMIT)
            blob = sha1(f"blob {len(data)}\0".encode() + data).hexdigest()
            if len(data) != size or blob != item["blobId"]:
                raise ValueError("Model metadata differs from the pinned revision")
            checksum = sha256(data).hexdigest()
        if not re.fullmatch(r"[0-9a-f]{64}", checksum):
            raise ValueError("Invalid model artifact digest")
        files[name] = dict(bytes=size, sha256=checksum)
    return dict(candidate=candidate, files=files, artifact=manifest_digest(
        {name: item["sha256"] for name, item in files.items()}),
        pack_bytes=sum(item["bytes"] for item in files.values()))


def copy_exact(source, destination, expected, *, clock, deadline):
    checksum = sha256()
    left = expected["bytes"]
    while left:
        if clock() >= deadline:
            raise Rejected("download_deadline", 409)
        block = source.read(min(left, 1024 * 1024))
        if not block:
            raise Rejected("artifact_size")
        left -= len(block)
        checksum.update(block)
        destination.write(block)
    if source.read(1) or checksum.hexdigest() != expected["sha256"]:
        raise Rejected("artifact_digest")


def reviewed_files(candidate, info, approval, slot, observed, *, clock):
    if candidate != "qwen":
        # Other snapshots are available for metadata review. Full staging
        # requires a native adapter that has passed the paired probe.
        raise Rejected("unreviewed_native_adapter")
    if candidate != info.get("candidate"):
        raise Rejected("unreviewed_artifact")
    files = info["files"]
    if (not isinstance(files, dict) or not 1 <= len(files) <= 256
            or any(not isinstance(item, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,119}", item)
                   or not isinstance(value, dict) or value.keys() != {"sha256", "bytes"}
                   or type(value["bytes"]) is not int or value["bytes"] <= 0
                   or not isinstance(value["sha256"], str) or not re.fullmatch("[a-f0-9]{64}", value["sha256"])
                   for item, value in files.items())):
        raise Rejected("unreviewed_artifact")
    fingerprint = manifest_digest({item: value["sha256"] for item, value in files.items()})
    total = sum(value["bytes"] for value in files.values())
    expires = approval.get("expires_at")
    if (approval.get("ok") is not True or approval.get("stage") != "full"
            or approval.get("artifact") != fingerprint or approval.get("pack_bytes") != total
            or type(expires) is not int or not 0 < expires - clock() <= 30):
        raise Rejected("stage_approval_unavailable", 409)
    budget = approval.get("budgets", {}).get(slot)
    if (not budget or observed["pressure"] != "normal"
            or budget["disk_bytes"] < total
            or observed["headroom"] < budget["peak_bytes"] + LARGE_FLOOR):
        raise Rejected("stage_resources_unavailable", 409)
    return files, budget, total


def stage_file(candidate, info, directory, approval, name, slot, observed, *, clock=time.time, peer_source=None):
    private_path(directory, directory=True)
    files, budget, _ = reviewed_files(candidate, info, approval, slot, observed, clock=clock)
    if name not in files:
        raise Rejected("unreviewed_artifact")
    target = directory / name
    expected = files[name]
    existing = 0
    for entry in directory.iterdir():
        if entry.name not in files or entry.is_symlink() or not entry.is_file():
            raise Rejected("unreviewed_artifact")
        size = entry.stat().st_size
        if size != files[entry.name]["bytes"]:
            raise Rejected("artifact_size")
        existing += size
    if target.exists():
        with target.open("rb") as stream:
            if file_digest(stream, "sha256").hexdigest() != expected["sha256"]:
                raise Rejected("artifact_digest")
        return
    if observed["disk_free"] < budget["disk_bytes"] - existing:
        raise Rejected("stage_resources_unavailable", 409)
    repo, revision = PACKS[candidate]
    with tempfile.TemporaryDirectory(prefix=".incoming-", dir=directory.parent) as temporary:
        path = Path(temporary) / name
        # Authority is verified just before starting each bounded file transfer.
        if peer_source is None:
            peer_source = lambda: urlopen(f"https://huggingface.co/{repo}/resolve/{revision}/{name}", timeout=30)
        with peer_source() as source, path.open("xb") as destination:
            copy_exact(source, destination, expected, clock=clock, deadline=clock() + 900)
        os.link(path, target)


def stage_checkpoint(candidate, info, directory, approval, cache, slot, observed, *, clock=time.time):
    private_path(directory, directory=True)
    private_path(cache, directory=True)
    if cache.parent != Path("/private/tmp") or not re.fullmatch(r"fios-moe-recovery-[0-9a-f]{16}", cache.name):
        raise Rejected("unreviewed_artifact")
    files, budget, _ = reviewed_files(candidate, info, approval, slot, observed, clock=clock)
    if observed["disk_free"] < budget["disk_bytes"]:
        raise Rejected("stage_resources_unavailable", 409)
    if any(directory.iterdir()) or set(path.name for path in cache.iterdir()) != files.keys():
        raise Rejected("unreviewed_artifact")
    linked = []
    try:
        for name, expected in files.items():
            source = cache / name
            if (source.is_symlink() or not source.is_file() or source.stat().st_size != expected["bytes"]):
                raise Rejected("artifact_size")
            if clock() >= approval["expires_at"]:
                raise Rejected("stage_approval_unavailable", 409)
            target = directory / name
            os.link(source, target, follow_symlinks=False)
            linked.append(target)
    except BaseException:
        for target in linked:
            target.unlink()
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("candidate", choices=PACKS)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--file")
    action.add_argument("--checkpoint", type=Path)
    parser.add_argument("--directory", type=Path)
    parser.add_argument("--approval", type=Path)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--peer-port", type=int)
    args = parser.parse_args()
    try:
        if args.file is None and args.checkpoint is None:
            print(json.dumps(pack_info(args.candidate), sort_keys=True))
            return
        if None in (args.directory, args.approval, args.manifest):
            raise ValueError("Supply a private staging directory, approval and reviewed manifest")
        slot, observed = sample(args.directory, hostname=socket.gethostname())
        private_path(args.approval)
        with args.approval.open("rb") as stream:
            approval = json_object(stream.read(8192))
        with args.manifest.open("rb") as stream:
            info = json_object(stream.read(64 * 1024))
        if args.checkpoint is not None:
            stage_checkpoint(args.candidate, info, args.directory, approval, args.checkpoint, slot, observed)
            print(json.dumps({"slot": slot, "linked": len(info["files"])}))
            return
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,119}", args.file):
            raise ValueError("Invalid artifact name")
        peer_source = None
        if args.peer_port is not None:
            if not 1 <= args.peer_port <= 65535:
                raise ValueError("Invalid shard source port")
            from moe_peer_transfer import receive

            credentials = args.directory.parent / "shard-transfer"
            peer_source = lambda: receive(args.peer_port, credentials / "ca.pem",
                                          credentials / "peer.pem", credentials / "peer.key")
        stage_file(args.candidate, info, args.directory, approval, args.file, slot, observed,
                   peer_source=peer_source)
        print(json.dumps({"slot": slot, "verified": args.file}))
    except HTTPError as error:
        parser.exit(75 if error.code in (408, 429, 500, 502, 503, 504) else 1, f"{error}\n")
    except (URLError, ConnectionError, TimeoutError) as error:
        parser.exit(75, f"{error}\n")
    except (OSError, ValueError) as error:
        parser.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
