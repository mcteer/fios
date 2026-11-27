"""Drive a fake executor over real TLS with deterministic pause points."""

import argparse
import json
from pathlib import Path
import select
import sys
import time

from backend.enrollment import elapsed
from backend.host_agent import observe
from backend.job_ledger import RESIDENT
from backend.machine_tls import context
from backend.worker import Reporter

FIELDS = ("job", "generation", "grant", "epoch")


class FakeWorker:
    def __init__(self, reporter):
        self.reporter = reporter
        self.capacity_sequence = 0
        self.resident = None
        self.ticket = None
        self.running = False
        self.deadline = 0

    def guard(self):
        if self.ticket and elapsed() >= self.deadline:
            self.running = False
            self.ticket = None

    def call(self, op, **data):
        status, response = self.reporter.request(
            f"/v1/jobs/{op}", dict(version=1, node=self.reporter.node,
                                 session=self.reporter.session, **data))
        return {"status": status, **json.loads(response)}

    def sample(self, available=2**30):
        previous = self.reporter.session
        if not self.reporter.report(observe):
            raise ValueError("Native heartbeat rejected")
        if previous != self.reporter.session:
            self.capacity_sequence = 0
            self.running, self.ticket = False, None
        self.capacity_sequence += 1
        return self.call("capacity", sequence=self.capacity_sequence, sampled_at=int(time.time()),
                         available_bytes=available, resident_revision=self.resident)

    def poll(self):
        # Subtract transit by starting the countdown before sending the poll.
        before = elapsed()
        response = self.call("poll")
        if response.get("action") in ("prepare", "start"):
            ticket = {key: response[key] for key in FIELDS}
            candidate = before + response["remaining"]
            if self.ticket == ticket:
                self.deadline = min(self.deadline, candidate)
            else:
                self.ticket, self.deadline = ticket, candidate
            self.guard()
            if response["action"] == "start" and self.ticket == ticket:
                self.resident = RESIDENT
                self.running = True
        return response

    def assigned(self, op, **data):
        self.guard()
        if not self.ticket:
            return {"status": 409, "reason": "local_lease_lost"}
        before = elapsed()
        response = self.call(op, **self.ticket, **data)
        self.guard()
        if response["status"] == 200:
            if op == "renew" and self.ticket:
                self.deadline = before + response["remaining"]
            elif op == "finish":
                self.running = False
        return response

    def cleanup(self):
        before = elapsed()
        instruction = self.call("poll")
        self.guard()
        if instruction.get("action") not in ("stop", "unload"):
            return instruction
        if instruction["action"] == "unload" and (
                self.running or self.ticket or self.resident != instruction["revision"]
                or elapsed() >= before + instruction["remaining"]):
            return {"status": 409, "reason": "unload_refused"}
        self.running, self.ticket = False, None
        if instruction["action"] == "unload":
            self.resident = None
        response = self.sample()
        if response["status"] != 200:
            return response
        return self.call("cleaned", challenge=instruction["challenge"],
                         sequence=self.capacity_sequence, disposition="quiescent")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("slot")
    parser.add_argument("port", type=int)
    for name in ("ca", "cert", "key"):
        parser.add_argument(name, type=Path)
    args = parser.parse_args()
    worker = FakeWorker(Reporter(args.slot, "127.0.0.1", args.port, "fios-core",
                                 context(args.ca, args.cert, args.key)))
    while True:
        worker.guard()
        if not select.select([sys.stdin], [], [], 0.05)[0]:
            continue
        line = sys.stdin.readline()
        if not line:
            return
        operation, fields = json.loads(line)
        if operation in ("sample", "poll", "cleanup"):
            result = getattr(worker, operation)(**fields)
        elif operation == "call":
            result = worker.call(**fields)
        elif operation == "state":
            result = {"running": worker.running}
        else:
            result = worker.assigned(operation, **fields)
        print(json.dumps(result), flush=True)


if __name__ == "__main__":
    main()
