"""Short-lived, grant-bound synthetic fixture output for blind review."""

import base64
import binascii
from dataclasses import dataclass, field
from hashlib import sha256
import json
import secrets

from .enrollment import Rejected
from .job_ledger import encoded, identifier, integer
from .pair_trial import digest

PAGE_BYTES = 2048
MAX_FRAMES = 32
MAX_PENDING = 32
RETENTION = 24 * 60 * 60
DIMENSIONS = {"canon_fidelity", "narrative_clarity", "session_usability"}


@dataclass
class Sample:
    blind: str
    kind: str
    expires: float
    generation: int
    case: str | None
    frames: list[bytes] = field(default_factory=list)

    def payload(self):
        return b"".join(self.frames)


class TrialReview:
    """The scheduler lock serializes access. Raw output lives only in memory."""

    def __init__(self, clock):
        self.clock = clock
        self.samples = {}

    def purge(self, db):
        for job, sample in list(self.samples.items()):
            row = db.execute("SELECT state,outcome,generation FROM jobs WHERE id=?", (job,)).fetchone()
            if (self.clock() >= sample.expires or row is None
                    or row["generation"] != sample.generation
                    or row["state"] not in ("running", "stopping", "succeeded")
                    or (row["state"] == "stopping" and row["outcome"] != "succeeded")):
                del self.samples[job]

    def append(self, row, kind, sequence, data, *, case=None):
        sequence = integer(sequence, 0, MAX_FRAMES - 1)
        if not isinstance(data, str) or len(data) > 4 * ((PAGE_BYTES + 2) // 3):
            raise Rejected("invalid_review_frame")
        try:
            raw = base64.b64decode(data, validate=True)
        except (ValueError, binascii.Error):
            raise Rejected("invalid_review_frame") from None
        if not 1 <= len(raw) <= PAGE_BYTES:
            raise Rejected("invalid_review_frame")
        job = row["id"]
        sample = self.samples.get(job)
        if sample is None:
            if sequence != 0:
                raise Rejected("frame_gap", 409)
            if len(self.samples) >= MAX_PENDING:
                raise Rejected("review_queue_full", 429)
            sample = Sample(secrets.token_hex(16), kind, self.clock() + RETENTION, row["generation"], case)
            self.samples[job] = sample
        frames = sample.frames
        if sequence < len(frames):
            if frames[sequence] != raw:
                raise Rejected("conflict", 409)
        elif sequence != len(frames) or (frames and len(frames[-1]) != PAGE_BYTES):
            raise Rejected("frame_gap", 409)
        else:
            frames.append(raw)
        return {"accepted": True}

    def complete(self, job, proof, prior=None):
        sample = self.samples.get(job)
        if not isinstance(proof, dict) or proof.keys() != {"frames", "digest"}:
            raise Rejected("review_output_unavailable", 409)
        count = integer(proof["frames"], 1, MAX_FRAMES)
        checksum = digest(proof["digest"])
        if prior:
            if (count, checksum) != (prior["frames"], prior["digest"]):
                raise Rejected("conflict", 409)
            return prior
        if sample is None:
            raise Rejected("review_output_unavailable", 409)
        payload = sample.payload()
        if count != len(sample.frames) or checksum != sha256(payload).hexdigest():
            raise Rejected("review_output_mismatch", 409)
        try:
            if not payload.decode().strip():
                raise ValueError()
        except ValueError:
            raise Rejected("invalid_review_output") from None
        return {"blind": sample.blind, "digest": proof["digest"], "kind": sample.kind, "frames": count}

    def find(self, db, blind):
        identifier(blind)
        self.purge(db)
        for job, sample in self.samples.items():
            if sample.blind == blind:
                row = db.execute("SELECT state,reporter,receipts FROM jobs WHERE id=?", (job,)).fetchone()
                proof = json.loads(row["receipts"]).get(row["reporter"], {}).get("review_output")
                if row["state"] == "succeeded" and proof and proof["blind"] == blind:
                    return job, sample, proof
        raise Rejected("review_output_unavailable", 409)

    def page(self, db, blind, cursor):
        _, sample, proof = self.find(db, blind)
        data = sample.payload()
        offset = integer(cursor, 0, len(data) - 1)
        end = min(offset + PAGE_BYTES, len(data))
        return dict(blind=blind, kind=sample.kind, case=sample.case, digest=proof["digest"],
                    data=base64.b64encode(data[offset:end]).decode(),
                    cursor=end if end < len(data) else None)

    def grade(self, db, blind, expected, verdict):
        identifier(blind)
        checksum = digest(expected)
        prior = db.execute("SELECT job,digest,verdict FROM large_review_verdicts WHERE blind=?",
                           (blind,)).fetchone()
        if prior:
            if checksum != prior["digest"] or encoded(verdict) != prior["verdict"]:
                raise Rejected("conflict", 409)
            return prior["job"]
        job, sample, proof = self.find(db, blind)
        if checksum != proof["digest"]:
            raise Rejected("review_output_mismatch", 409)
        if sample.kind == "campaign":
            if not isinstance(verdict, dict) or verdict.keys() != DIMENSIONS:
                raise Rejected("invalid_review_verdict")
            for score in verdict.values():
                integer(score, 1, 5)
        elif type(verdict) is not bool:
            raise Rejected("invalid_review_verdict")
        db.execute("INSERT INTO large_review_verdicts VALUES (?,?,?,?,?)",
                   (job, blind, proof["digest"], sample.kind, encoded(verdict)))
        return job
