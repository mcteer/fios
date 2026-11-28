"""Frozen cases and numeric acceptance limits for a large-model qualification."""

from hashlib import sha256

from .enrollment import Rejected
from .job_ledger import encoded
from .pair_trial import digest

CAMPAIGNS = tuple(f"campaign-{index}" for index in range(1, 5))
CODING = tuple(f"coding-{index}" for index in range(1, 5))
CONTROLS = tuple(f"control-{index}" for index in range(1, 7))
TIMED = ("cold", *(f"warm-{index}" for index in range(1, 6)), "full-budget")
POLICY_CASES = {"policy-allow": True, "policy-deny": False}
FAULTS = {"cancel": "cancelled", "rank-0": "failed", "rank-1": "failed", "link": "failed"}
CASES = frozenset((*CAMPAIGNS, *CODING, *CONTROLS, *TIMED, *FAULTS, *POLICY_CASES,
                   "over-limit", "tcp-control", "post-fault"))
REFERENCE_CASES = frozenset({"tcp-control"})
NATIVE_CASES = CASES.difference(TIMED, POLICY_CASES, REFERENCE_CASES)
LIMITS = dict(short_input=256, short_output=32, short_native_ms=180_000, short_visible_ms=240_000,
              full_input=7168, full_output=1024, full_visible_ms=900_000, full_min_decode_tps=2)


def freeze_suite(document):
    if (not isinstance(document, dict) or document.keys() != {"fixtures", "rubric", "policy"}
            or not isinstance(document["fixtures"], dict) or document["fixtures"].keys() != CASES):
        raise Rejected("invalid_moe_suite")
    fixtures = {key: digest(value) for key, value in document["fixtures"].items()}
    suite = dict(fixtures=fixtures, rubric=digest(document["rubric"]),
                 policy=digest(document["policy"]), limits=LIMITS)
    return sha256(encoded(suite).encode("ascii")).hexdigest(), suite


def verify_recipe_case(document, recipe):
    case = recipe.get("case")
    if not isinstance(case, str) or case not in CASES or recipe["fixture"] != document["fixtures"][case]:
        raise Rejected("unregistered_trial_case", 409)
    if case in POLICY_CASES:
        raise Rejected("requires_native_policy_check", 409)
    if case in TIMED:
        raise Rejected("requires_browser_rehearsal", 409)
    review = ("campaign" if case in CAMPAIGNS else "coding" if case in CODING else None)
    if recipe.get("review") != review:
        raise Rejected("trial_review_mismatch", 409)


def timed_limits(case, measurement, visible):
    from .job_ledger import integer

    if case not in TIMED:
        raise Rejected("invalid_timed_case")
    integer(visible, 1, LIMITS["full_visible_ms" if case == "full-budget" else "short_visible_ms"])
    timing = measurement["timing"]
    if case == "full-budget":
        if (timing["input_tokens"] != LIMITS["full_input"]
                or measurement["completed_tokens"] != LIMITS["full_output"]
                or LIMITS["full_min_decode_tps"] * timing["decode_ms"] > (LIMITS["full_output"] - 1) * 1000):
            raise Rejected("full_budget_timing", 409)
    elif (timing["input_tokens"] > LIMITS["short_input"]
          or measurement["completed_tokens"] > LIMITS["short_output"]
          or measurement["first_text_ms"] > LIMITS["short_native_ms"]):
        raise Rejected("short_case_timing", 409)


NEGATIVE_CASES = dict(FAULTS, **{"over-limit": "failed", "policy-deny": "denied", "tcp-control": "failed"})


def verify_native_case(db, profile, case, job, joint_trial):
    import json

    from .job_ledger import identifier

    row = db.execute("SELECT * FROM jobs WHERE id=?", (identifier(job),)).fetchone()
    if not row:
        raise Rejected("unknown_trial", 409)
    intent = json.loads(row["intent"])
    if (intent.get("hardware") is not True or intent.get("profile") != profile.revision
            or intent.get("review", {}).get("case") != case or "stage_approval" not in intent
            or db.execute("SELECT 1 FROM holds WHERE job=?", (job,)).fetchone()):
        raise Rejected("invalid_case_evidence", 409)
    if case in NEGATIVE_CASES:
        if row["state"] != NEGATIVE_CASES[case]:
            raise Rejected("negative_case_failed", 409)
        expected = {"cancel": "operator_cancelled", "tcp-control": "transport_mismatch",
                    "link": "transport_unavailable", "policy-deny": "publication_withheld",
                    "over-limit": "context_limit"}
        if case in expected and row["reason"] != expected[case]:
            raise Rejected("negative_case_reason", 409)
        if case in FAULTS:
            events = {event["state"]: event["at"] for event in db.execute(
                "SELECT state,at FROM events WHERE job=? ORDER BY position", (job,))}
            if (not {"running", "stopping", row["state"]} <= events.keys()
                    or not 0 <= events[row["state"]] - events["stopping"] <= 17):
                raise Rejected("fault_cleanup_unverified", 409)
        if case == "tcp-control":
            receipts = json.loads(row["receipts"])
            if (len(receipts) != 2 or not all(any(transfer["transport"] == "tcp"
                                                 for transfer in value["transport_evidence"]["transfers"])
                                             for value in receipts.values())):
                raise Rejected("tcp_control_unverified", 409)
        return {}
    review, ranks = joint_trial(db, job, profile, paired=True)
    if case in CODING or case in CAMPAIGNS:
        verdict = db.execute("SELECT digest,kind,verdict FROM large_review_verdicts WHERE job=?",
                             (job,)).fetchone()
        proof = ranks[row["reporter"]].get("review_output")
        if not verdict or not proof or verdict["digest"] != proof["digest"]:
            raise Rejected("missing_review_verdict", 409)
        decision = json.loads(verdict["verdict"])
        if ((case in CODING and (verdict["kind"] != "coding" or decision is not True))
                or (case in CAMPAIGNS and (verdict["kind"] != "campaign"
                                          or min(decision.values()) < 4))):
            raise Rejected("case_quality_failed", 409)
    return {slot: receipt["trial_measurement"]["peak_bytes"] + review["budgets"][slot]["floor"]
            for slot, receipt in ranks.items()}
