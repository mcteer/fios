"""Authorize each full-pack transfer against a cleaned hardware probe."""

import json
from pathlib import Path
import selectors
import shlex
import subprocess
import time

from backend.enrollment import STUDIOS
from backend.pair_trial import GIB
from enrollment_fixtures import Signer


def reserve(pack_bytes):
    # Each Studio holds the full pack on disk, including a scratch shard.
    # The memory budget allows about 55 GiB over the even weight partition
    # for replicated tensors, cache, and temporary load or prefill buffers.
    return {slot: dict(disk_bytes=pack_bytes + 12 * GIB, peak_bytes=160 * GIB)
            for slot in STUDIOS}


class PeerCopy:
    def __init__(self, root, run, hosts, options, remote, send, cleanup):
        self.run, self.hosts, self.options, self.remote = run, hosts, options, remote
        self.directory = run + "/shard-transfer"
        signer = Signer(root, "moe-shards")
        leaves = (signer.issue("shard-source", san="IP:192.168.0.1", server=True),
                  signer.issue("shard-destination"))
        for host, (cert, key) in zip(hosts, leaves, strict=True):
            remote(host, "mkdir", "-m", "700", self.directory)
            cleanup.callback(self.remove_credentials, host)
            for path, name in ((signer.ca, "ca.pem"), (cert, "peer.pem"), (key, "peer.key")):
                send(host, [path], self.directory + "/" + name)
            remote(host, "chmod", "600", self.directory + "/peer.key")
            send(host, [Path(__file__).with_name("moe_peer_transfer.py")], run)

    def remove_credentials(self, host):
        paths = tuple(self.directory + "/" + name for name in ("ca.pem", "peer.pem", "peer.key"))
        self.remote(host, "/bin/rm", "-f", *paths)
        self.remote(host, "/bin/rmdir", self.directory)

    def copy(self, name, command):
        leader, follower = self.hosts
        source = ("env", f"PYTHONPATH={self.run}/src", "/opt/homebrew/bin/python3", "-B",
                  self.run + "/moe_peer_transfer.py", self.run + "/model/" + name,
                  self.directory + "/ca.pem", self.directory + "/peer.pem", self.directory + "/peer.key")
        with subprocess.Popen(["ssh", *self.options, leader, shlex.join(source)],
                              stdout=subprocess.PIPE, text=True) as process:
            try:
                with selectors.DefaultSelector() as read:
                    read.register(process.stdout, selectors.EVENT_READ)
                    if not read.select(timeout=12):
                        raise TimeoutError("Shard sender did not advertise its private listener")
                    port = int(process.stdout.readline())
                if not 1 <= port <= 65535:
                    raise ValueError("Shard sender advertised an invalid listener")
                # The recipient verifies the bytes independently. If a retry
                # finds a complete local file, it can acknowledge without
                # opening the sender's socket.
                return self.remote(follower, *command, "--peer-port", str(port), limit=960)
            finally:
                if process.poll() is None:
                    process.terminate()


def acquire(catalog, jobs, profile, comparable, probe, pack, manifest, *,
            hosts, run, remote, send, observe, peer, staged=False, checkpoint=None):
    budgets = reserve(pack["pack_bytes"])

    def approval():
        decision = catalog.decide_large_stage(dict(
            candidate=profile.revision, comparable=comparable, incarnation=jobs.context(),
            budgets=budgets, observations=observe(), stage="full", probe_job=probe,
            pack_bytes=pack["pack_bytes"]))
        if decision["decision"] != "approved":
            refusal = decision["refusal"]
            raise ValueError(f"Full-pack resource refusal on {refusal['slot']}: {refusal['reason']}")
        return decision["approval"]

    approval()
    if staged:
        return budgets, approval
    for host in hosts:
        send(host, [manifest, Path(__file__).with_name("stage_moe_pack.py")], run)

    def stage_command(host):
        receipt = dict(ok=True, **catalog.large_stage_authority(profile.revision, approval(), "full"))
        remote(host, "/bin/sh", "-c", 'umask 077; cat > "$1"', "sh",
               run + "/full-approval.json", payload=json.dumps(receipt))
        return ("env", f"PYTHONPATH={run}/src", "/opt/homebrew/bin/python3", "-B",
                run + "/stage_moe_pack.py", pack["candidate"], "--directory", run + "/model",
                "--approval", run + "/full-approval.json", "--manifest", run + "/" + manifest.name)

    if checkpoint:
        for host, slot in zip(hosts, STUDIOS, strict=True):
            linked = json.loads(remote(host, *stage_command(host), "--checkpoint", checkpoint))
            if linked != {"slot": slot, "linked": len(pack["files"])}:
                raise ValueError("Studio did not confirm the complete staging checkpoint")
        print("Both Studios reopened their local full packs for digest verification.", flush=True)
        return budgets, approval

    leader, follower = hosts
    for name in sorted(pack["files"]):
        for attempt in range(3):
            try:
                source = json.loads(remote(leader, *stage_command(leader), "--file", name, limit=960))
                destination = peer.copy(name, (*stage_command(follower), "--file", name))
                verified = source, json.loads(destination)
                break
            except (TimeoutError, subprocess.TimeoutExpired, subprocess.CalledProcessError) as error:
                if attempt == 2 or (isinstance(error, subprocess.CalledProcessError)
                                    and error.returncode not in (75, 255)):
                    raise
                print(f"Retrying transient transfer failure for {name}", flush=True)
                time.sleep(2 ** (attempt + 1))
        if any(value != {"slot": slot, "verified": name}
               for slot, value in zip(STUDIOS, verified, strict=True)):
            raise ValueError("Studio did not confirm the approved shard digest")
        print(f"Verified {name} on both Studios", flush=True)
    return budgets, approval
