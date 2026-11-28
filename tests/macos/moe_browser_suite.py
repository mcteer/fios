"""Observe the frozen large-model browser cases through the real private UI."""

from contextlib import ExitStack
import json
import os
from pathlib import Path
import re
import selectors
import subprocess
import sys

from agent.text_policy import LoopbackPolicy
from backend.chat_dispatch import Dispatch
from backend.conversations import ConversationStore
from backend.enroll import command
from backend.enrollment import private_path
from backend.heartbeat import Listener
from backend.job_ledger import JobLedger
from backend.model_catalog import Catalog
from backend.moe_suite import POLICY_CASES, TIMED
from backend.native_chat import browser_handler
from jaccl_lease_trial import wait_for


def request(admin, action, **data):
    result = command(admin, dict(action=action, **data))
    if result.get("ok") is not True:
        raise ValueError(f"{action}: {result.get('reason', 'missing acknowledgement')}")
    return result


def stop_web(process):
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
    process.stdout.close()


def start_web(resources, root, port, key_path):
    process = subprocess.Popen([
        sys.executable, "-B", "-m", "backend.core", "--directory", root, "--port", "0",
        "--chat-port", str(port), "--chat-key", key_path,
    ], stdout=subprocess.PIPE, text=True)
    resources.callback(stop_web, process)
    with selectors.DefaultSelector() as read:
        read.register(process.stdout, selectors.EVENT_READ)
        if not read.select(timeout=10):
            raise TimeoutError("Private browser service did not start")
        announcement = process.stdout.readline()
    address = re.fullmatch(r"fios listening on (http://127\.0\.0\.1:[0-9]+)\n", announcement)
    if not address:
        raise ValueError("Private browser service did not advertise its loopback address")
    return address[1]


def rehearse_release(root, scheduler, admin, profile, store, suite):
    alias = profile.document()["alias"]
    revision = profile.revision
    owner = "local-moe-rehearsal"
    policy = profile.document()["policy"]
    before = store.history(owner, policy)
    if not before["conversations"]:
        raise ValueError("Fixture browser history could not be reopened")
    request(admin, "large-rehearsal-close")
    request(admin, "model-promote", alias=alias, expected=None, revision=revision)
    stale = command(admin, dict(action="model-withdraw", alias=alias, expected="0" * 64))
    if stale.get("reason") != "conflict":
        raise ValueError("A stale revision could withdraw the model")
    request(admin, "model-withdraw", alias=alias, expected=revision)
    request(admin, "model-promote", alias=alias, expected=None, revision=revision)
    snapshot = root / "release-source.sqlite"
    scheduler.jobs.backup(snapshot)
    request(admin, "model-withdraw", alias=alias, expected=revision)
    scratch = root / "restored"
    scratch.mkdir(mode=0o700)
    restored_path = scratch / "jobs.sqlite"
    JobLedger.initialize(restored_path)
    restored = JobLedger(restored_path)
    restored.restore(snapshot)
    catalog = Catalog(restored)
    with restored.transaction(write=False) as db:
        if (restored.incarnation(db) == scheduler.jobs.context()
                or catalog.active(db, alias) is not None or catalog.qualified(db, revision, False)):
            raise ValueError("Restored state kept a stale large-model release")
    if store.history(owner, policy) != before:
        raise ValueError("Withdrawing the fixture alias disturbed its history")
    canaries = ((suite / "cold.txt").read_bytes(), (suite / "full-budget.txt").read_bytes())
    telemetry = snapshot.read_bytes()
    if any(canary in telemetry for canary in canaries):
        raise ValueError("The execution ledger contained a private fixture prompt")


def run_browser(root, scheduler, admin, profile, comparable, approval, native, suite, serving):
    private_path(serving)
    checker = json.loads(serving.read_text())
    document = profile.document()
    if checker["revision"] != document["policy"]:
        raise ValueError("Running checker differs from the reviewed policy revision")
    store = ConversationStore(scheduler.jobs, os.urandom(32), catalog=scheduler.catalog, directory=root)
    scheduler.dispatch = Dispatch(scheduler, store, LoopbackPolicy(checker["port"], long_context=True),
                                  policy_revision=checker["revision"], long_context=True)
    for case in POLICY_CASES:
        fixture = json.loads((suite / (case + ".json")).read_text())
        checked = request(admin, "large-policy-check", report=dict(
            candidate=profile.revision, comparable=comparable, case=case, **fixture))
        if checked.get("passed") is not True:
            raise ValueError(f"Real checker failed {case}")
    runner = root / "moe-webkit"
    subprocess.run(["xcrun", "swiftc", Path(__file__).with_name("check_moe_webkit.swift"),
                    "-module-cache-path", root / "swift-cache", "-o", runner], check=True, timeout=90)
    key_path = root / "rehearsal-bridge.key"
    key = os.urandom(32)
    with os.fdopen(os.open(key_path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600), "wb") as output:
        output.write(key)
    with ExitStack() as resources:
        service = Listener(("127.0.0.1", 0), browser_handler(scheduler, key, rehearsal=True)).start()
        resources.callback(service.close)
        web = start_web(resources, root, service.address[1], key_path)
        request(admin, "large-rehearsal-open", report=dict(
            candidate=profile.revision, comparable=comparable, approval=approval(), native=native))
        resources.callback(request, admin, "large-rehearsal-close")
        observed = {}
        for case in TIMED:
            fixture = root / "webkit-fixture.json"
            fixture.write_text(json.dumps(dict(candidate=profile.revision, suite=document["evaluation"],
                                               case=case, prompt=(suite / (case + ".txt")).read_text())))
            limit = 915 if case == "full-budget" else 255
            try:
                evidence = json.loads(subprocess.check_output(
                    [runner, web + "/chat", fixture], timeout=limit))
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
                with scheduler.jobs.transaction(write=False) as db:
                    recent = db.execute("SELECT state,reason FROM jobs WHERE owner='local-moe-rehearsal' "
                                        "AND json_extract(intent,'$.case')=? ORDER BY position DESC LIMIT 1",
                                        (case,)).fetchone()
                detail = f"{recent['state']} ({recent['reason']})" if recent else "no job submitted"
                raise ValueError(f"{case} browser turn failed with {detail}") from error
            job = evidence["job"]
            def released():
                scheduler.sweep()
                return not scheduler.jobs.get("local-moe-rehearsal", job)["slots"]
            wait_for(released, "Published turn retained a native hold", 17)
            request(admin, "large-rehearsal-observe", report=evidence)
            observed[case] = job
            print(json.dumps(evidence), flush=True)
        result = request(admin, "large-rehearsal-record", report=observed)
        rehearse_release(root, scheduler, admin, profile, store, suite)
        return result["revision"]
