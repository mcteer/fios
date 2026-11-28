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
TRIAL_OWNER = "local-pair-trial"
OPERATOR_FIELDS = {
    "job-context": (),
    "job-submit": ("incarnation", "key", "profile", "tokens", "deadline"),
    "job-get": ("job",),
    "job-list": ("cursor",),
    "job-events": ("job", "cursor"),
    "job-cancel": ("job",),
    "pair-trial-submit": ("incarnation", "key", "candidate", "recipe"),
    "pair-trial-inspect": ("job",),
    "pair-trial-cancel": ("job",),
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
        elif args.action == "job-migrate":
            JobLedger(path).migrate()
        elif args.action == "job-backup":
            JobLedger(path).backup(args.target)
        else:
            JobLedger(path).restore(args.snapshot)


def cli(sub):
    for name in ("job-init", "job-migrate", "job-backup", "job-restore"):
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
    if action == "pair-trial-submit":
        return {"job": scheduler.submit_trial(TRIAL_OWNER, data)}
    if action == "job-submit":
        return {"job": jobs.submit(OWNER, {key: data[key] for key in fields})}
    if action == "job-list":
        # A page of full job views fits within the existing Unix response bound.
        return {"jobs": scheduler.describe(OWNER, after=integer(data.get("cursor", 0), 0, 2**63 - 1))}
    job = identifier(data["job"])
    if action == "pair-trial-inspect":
        return {"job": scheduler.describe(TRIAL_OWNER, job=job, diagnostics=True)[0]}
    if action == "pair-trial-cancel":
        return {"job": scheduler.cancel(TRIAL_OWNER, job)}
    if action == "job-get":
        return {"job": scheduler.describe(OWNER, job=job)[0]}
    if action == "job-events":
        return {"events": jobs.events(OWNER, job, integer(data.get("cursor", 0), 0, 2**63 - 1))}
    return {"job": scheduler.cancel(OWNER, job)}


def local(scheduler, operation, data):
    if operation == "session" and not data:
        return {"session": scheduler.open_local_session()}
    return worker_operation(scheduler, operation, "fios-core", data, local_peer=True)


def worker(scheduler, route, node, pin, data):
    operation = WORKER_ROUTES[route]
    with scheduler.enrollment.lock:
        scheduler.enrollment.authorize(node, pin, "scheduling")
        return worker_operation(scheduler, operation, node, data)


def worker_operation(scheduler, operation, node, data, *, local_peer=False):
    if operation not in WORKER_FIELDS:
        raise Rejected("invalid")
    required = WORKER_FIELDS[operation] | {"version", "node", "session"}
    if operation == "capacity" and scheduler.catalog is not None:
        required |= {"pressure"}
        if local_peer:
            required |= {"memory_bytes"}
    version = data.get("version")
    pair_capable = type(version) is int and version == 2 and not local_peer and scheduler.catalog is not None
    fields = data.keys()
    if operation == "finish":
        fields = fields - ({"usage", "transport_evidence", "trial_measurement", "failure"} if pair_capable else {"usage"})
    if (fields != required or (not pair_capable and (type(version) is not int or version != 1))
            or data["node"] != node):
        raise Rejected("invalid")
    session = identifier(data["session"])
    with scheduler.enrollment.lock:
        if session != scheduler.session(node):
            raise Rejected("session", 409)
        scheduler.sweep()
        if operation == "capacity":
            if local_peer:
                return scheduler.local_capacity(session, {key: data[key] for key in
                                                required - {"version", "node", "session"}})
            return scheduler.set_capacity(node, session, data)
        dispatch = getattr(scheduler, "dispatch", None)
        transaction = (dispatch.conversations.transaction if dispatch is not None
                       and operation == "finish" else scheduler.jobs.transaction)
        with transaction() as db:
            if operation == "poll":
                return scheduler.poll(db, node, session, pair_capable=pair_capable)
            if operation != "cleaned":
                return scheduler.assignment(db, operation, node, session, data, pair_capable=pair_capable)
            response = scheduler.cleanup(db, node, session, data)
        # A lost response can be acknowledged again only after durable release.
        if "clean_ack" in response:
            scheduler.cleaned[node] = response["clean_ack"]
            scheduler.challenges.pop(node, None)
            scheduler.capacity[node]["idle"] = scheduler.clock()
        return {}
