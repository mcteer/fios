"""Validate attempt-bound resource summaries from large-model ranks."""

from .enrollment import Rejected
from .job_ledger import identifier, integer
from .pair_trial import GIB, LARGE_FLOOR

PHASES = ("load", "prefill", "decode")
MAX_SAMPLE_GAP_MS = 2000


def rank_phases(document, *, attempt, ceiling, deadline_ms):
    """Validate reports without combining the two hosts' resource budgets."""
    if (not isinstance(document, dict) or document.keys() != {"attempt", "phases"}
            or identifier(document["attempt"]) != attempt
            or not isinstance(document["phases"], list) or len(document["phases"]) != len(PHASES)):
        raise Rejected("invalid_phase_evidence")
    prior = 0
    for phase, summary in zip(PHASES, document["phases"], strict=True):
        fields = {"phase", "first_ms", "last_ms", "max_gap_ms", "min_headroom_bytes",
                  "peak_footprint_bytes", "max_swap_growth_bytes", "worst_pressure"}
        if not isinstance(summary, dict) or summary.keys() != fields or summary["phase"] != phase:
            raise Rejected("invalid_phase_evidence")
        # Measure elapsed time from the pre-load sample on this Studio.
        first = integer(summary["first_ms"], prior, min(prior + MAX_SAMPLE_GAP_MS, deadline_ms))
        last = integer(summary["last_ms"], first, deadline_ms)
        integer(summary["max_gap_ms"], int(last > first), min(MAX_SAMPLE_GAP_MS, last - first))
        integer(summary["min_headroom_bytes"], LARGE_FLOOR, 256 * GIB)
        integer(summary["peak_footprint_bytes"], 1, ceiling - 1)
        integer(summary["max_swap_growth_bytes"], 0, 0)
        if summary["worst_pressure"] != "normal":
            raise Rejected("memory_pressure")
        prior = last
    return document
