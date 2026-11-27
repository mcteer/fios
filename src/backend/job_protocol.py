"""Validate operator and worker messages at the native service boundary."""

from contextlib import contextmanager
import fcntl
import os
from pathlib import Path

from .enrollment import Ledger, Rejected, private_path
from .job_ledger import JobLedger, identifier, integer

WORKER_FIELDS = {
    "capacity": {"sequence", "sampled_at", "available_bytes", "resident_revision"},
    "poll": set(),
    "ready": {"job", "generation", "grant", "epoch"},
    "renew": {"job", "generation", "grant", "epoch"},
    "cleaned": {"challenge", "sequence", "disposition"},
}
WORKER_FIELDS["finish"] = WORKER_FIELDS["ready"] | {"result"}
WORKER_ROUTES = {f"/v1/jobs/{action}": action for action in WORKER_FIELDS}
OWNER = "local-operator"
OPERATOR_FIELDS = {
    "job-context": (),
    "job-submit": ("incarnation", "key", "profile", "tokens", "deadline"),
    "job-get": ("job",),
    "job-list": ("cursor",),
    "job-events": ("job", "cursor"),
    "job-cancel": ("job",),
}


@contextmanager
def service_lock(directory):
    """Serialize the live listeners and offline ledger replacement."""
    private_path(directory, directory=True)
    descriptor = os.open(directory / "service.lock",
                         os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    try:
        private_path(directory / "service.lock")
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield
    finally:
        os.close(descriptor)


def offline(args):
    directory = args.state_dir.absolute()
    # Confirm this is an existing private enrollment state directory.
    Ledger(directory)
    with service_lock(directory):
        path = directory / "jobs.sqlite"
        if args.action == "job-init":
            JobLedger.initialize(path)
        elif args.action == "job-backup":
            JobLedger(path).backup(args.target)
        else:
            JobLedger(path).restore(args.snapshot)


def cli(sub):
    for name in ("job-init", "job-backup", "job-restore"):
        parser = sub.add_parser(name)
        parser.add_argument("--state-dir", type=Path, required=True)
        if name == "job-backup":
            parser.add_argument("--target", type=Path, required=True)
        if name == "job-restore":
            parser.add_argument("--snapshot", type=Path, required=True)

    for name, fields in OPERATOR_FIELDS.items():
        parser = sub.add_parser(name)
        for field in fields:
            if field == "cursor":
                parser.add_argument("--cursor", type=int, default=0)
            elif field == "job":
                parser.add_argument("job")
            else:
                parser.add_argument(f"--{field}", required=True,
                                    type=int if field in ("tokens", "deadline") else str)


def operator(scheduler, action, data):
    if scheduler is None:
        raise Rejected("scheduling_unavailable", 503)
    fields = OPERATOR_FIELDS[action]
    required = {"action", *fields}
    if data.keys() != required and not ("cursor" in required and data.keys() == required - {"cursor"}):
        raise Rejected("invalid")
    scheduler.sweep()
    jobs = scheduler.jobs
    if action == "job-context":
        return {"incarnation": jobs.context()}
    if action == "job-submit":
        return {"job": jobs.submit(OWNER, {key: data[key] for key in fields})}
    if action == "job-list":
        # A page of full job views fits within the existing Unix response bound.
        return {"jobs": scheduler.describe(OWNER, after=integer(data.get("cursor", 0), 0, 2**63 - 1))}
    job = identifier(data["job"])
    if action == "job-get":
        return {"job": scheduler.describe(OWNER, job=job)[0]}
    if action == "job-events":
        return {"events": jobs.events(OWNER, job, integer(data.get("cursor", 0), 0, 2**63 - 1))}
    return {"job": scheduler.cancel(OWNER, job)}


def worker(scheduler, route, node, pin, data):
    operation = WORKER_ROUTES[route]
    required = WORKER_FIELDS[operation] | {"version", "node", "session"}
    fields = data.keys()
    if operation == "finish" and "usage" in fields:
        fields = fields - {"usage"}
    if fields != required or type(data["version"]) is not int or data["version"] != 1:
        raise Rejected("invalid")
    session = identifier(data["session"])
    enrollment = scheduler.enrollment
    with enrollment.lock:
        enrollment.authorize(node, pin, "scheduling")
        if session != scheduler.session(node):
            raise Rejected("session", 409)
        scheduler.sweep()
        if operation == "capacity":
            return scheduler.set_capacity(node, session, data)
        with scheduler.jobs.transaction() as db:
            if operation == "poll":
                return scheduler.poll(db, node, session)
            if operation != "cleaned":
                return scheduler.assignment(db, operation, node, session, data)
            response = scheduler.cleanup(db, node, session, data)
        # A lost response can be acknowledged again only after durable release.
        if "clean_ack" in response:
            scheduler.cleaned[node] = response["clean_ack"]
            scheduler.challenges.pop(node, None)
            scheduler.capacity[node]["idle"] = scheduler.clock()
        return {}
