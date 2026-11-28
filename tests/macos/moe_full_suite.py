"""Exercise frozen full-pack fixtures and native fault recovery on the Studios."""

import json
import shlex
import subprocess
import time

from backend.enroll import command
from backend.enrollment import Rejected
from backend.job_protocol import TRIAL_OWNER, operator
from backend.moe_suite import CAMPAIGNS, CODING, CONTROLS, FAULTS, verify_native_case
from grade_moe_sql import grade
from jaccl_lease_trial import wait_for


def run_native(scheduler, hosts, call, remote, run, admin, submit, settle, profile):
    completed = {}
    failures = {}
    campaign_reviews = {}

    def attempts(db, case):
        base = "suite-" + case
        return db.execute("SELECT id FROM jobs WHERE owner=? AND (request_key=? OR request_key LIKE ?) "
                          "ORDER BY position", (TRIAL_OWNER, base, base + "-attempt-%")).fetchall()

    def use_prior(case):
        with scheduler.jobs.transaction(write=False) as db:
            for row in reversed(attempts(db, case)):
                try:
                    verify_native_case(db, profile, case, row["id"], scheduler.catalog.joint_trial)
                except Rejected:
                    continue
                completed[case] = row["id"]
                print(json.dumps(dict(case=case, job=row["id"], state="reused_verified_attempt")), flush=True)
                return True
        return False

    def start(case):
        with scheduler.jobs.transaction(write=False) as db:
            count = len(attempts(db, case))
        key = "suite-" + case
        return submit(case, key if count == 0 else f"{key}-attempt-{count + 1}")

    def verify_case(case):
        if use_prior(case):
            return
        for attempt in range(2):
            job = start(case)
            view = settle(job, 720)
            if attempt == 1 or view["reason"] != "worker_failed":
                break
            print(json.dumps(dict(case=case, job=job, state=view["state"], reason=view["reason"],
                                  retry="separate_attempt")), flush=True)
        outcome = view["state"]
        expected = "failed" if case == "over-limit" else "succeeded"
        ranks = {}
        for slot, receipt in view["ranks"].items():
            phases = receipt.get("phase_observation", {}).get("phases", [])
            if phases:
                ranks[slot] = dict(peak_bytes=max(phase["peak_footprint_bytes"] for phase in phases),
                                   headroom_bytes=min(phase["min_headroom_bytes"] for phase in phases),
                                   swap_growth=max(phase["max_swap_growth_bytes"] for phase in phases),
                                   timing=receipt["trial_measurement"])
        print(json.dumps(dict(case=case, job=job, state=outcome, reason=view["reason"], ranks=ranks)), flush=True)
        if outcome != expected or (case == "over-limit" and view["reason"] != "context_limit"):
            failures[case] = view["reason"]
            # A capacity or runtime failure on the first control means the
            # remaining cases cannot provide independent model observations.
            if case == CONTROLS[0]:
                raise ValueError(f"First full-pack control failed: {view['reason']}")
            return
        if case in (*CODING, *CAMPAIGNS):
            proofs = [data["review_output"] for data in view["ranks"].values() if "review_output" in data]
            if len(proofs) != 1:
                failures[case] = "review_output_unavailable"
                return
            blind = proofs[0]["blind"]
            if case in CODING:
                verdict = grade(admin, blind, case)
                result = command(admin, dict(action="large-review-verdict", **verdict))
                if result.get("ok") is not True or verdict["verdict"] is not True:
                    failures[case] = "coding_review_failed"
            else:
                campaign_reviews[case] = blind
                print(json.dumps(dict(case=case, blind=blind, review_socket=str(admin))), flush=True)
        completed[case] = job

    verify_case(CONTROLS[0])

    def active():
        return [json.loads(call(host, "rank-active")) for host in hosts]

    def link_restored():
        if not json.loads(call(hosts[1], "link-up")):
            return False
        try:
            remote(hosts[1], "/sbin/ping", "-c", "1", "-W", "1000", "192.168.0.1", limit=4)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            return False
        return True

    # The operator can finish the physical-link step while the remaining
    # fixtures are still ahead. A successful control first proves model fit.
    for case in ("link", "cancel", "rank-0", "rank-1"):
        if use_prior(case):
            continue
        if case == "link":
            print(f"LINK TEST WAITING TO ARM: {run}", flush=True)
            print(f"Run on edge-b: /bin/sh {run}/arm_jaccl_link.sh", flush=True)
            try:
                wait_for(lambda: json.loads(call(hosts[1], "link-armed")),
                         "The operator did not arm the physical link test", 180)
            except TimeoutError:
                failures[case] = "operator_link_not_armed"
                continue
        job = start(case)
        wait_for(lambda: all(active()), "Both native ranks did not start", 40)
        if case == "cancel":
            action = "pair-trial-cancel"
            operator(scheduler, action, dict(action=action, job=job))
        elif case == "link":
            remote(hosts[1], "/usr/bin/touch", run + "/link-ready")
            wait_for(lambda: not json.loads(call(hosts[1], "link-up")),
                     "The Thunderbolt interruption was not observed", 15)
        else:
            call(hosts[int(case[-1])], "kill-rank")
        started = time.monotonic()
        view = settle(job, 17)
        if (view["state"] != FAULTS[case] or any(active())
                or (case == "link" and view["reason"] != "transport_unavailable")):
            failures[case] = view["reason"]
        else:
            completed[case] = job
        print(json.dumps(dict(case=case, job=job, reason=view["reason"],
                              cleanup_ms=round((time.monotonic() - started) * 1000))), flush=True)
        if case == "link":
            wait_for(link_restored, "Thunderbolt did not recover", 20)

    verify_case("post-fault")
    for case in (*CONTROLS[1:], *CODING, *CAMPAIGNS, "over-limit"):
        verify_case(case)
    if not failures:
        def graded():
            with scheduler.jobs.transaction(write=False) as db:
                return all(db.execute("SELECT 1 FROM large_review_verdicts WHERE job=?",
                                      (completed[case],)).fetchone() for case in CAMPAIGNS)

        if not graded():
            arguments = [f"{case}={blind}" for case, blind in campaign_reviews.items()]
            command_line = shlex.join(("python3", "-B", "tests/macos/review_moe_campaign.py",
                                       "--socket", str(admin), *arguments))
            print("CAMPAIGN REVIEW WAITING FOR SCORES. Run on the Mini from the repository:", flush=True)
            print(f"PYTHONPATH=src:tests {command_line}", flush=True)
            wait_for(graded, "Campaign verdicts still require a local reviewer", 900)
    return completed, failures
