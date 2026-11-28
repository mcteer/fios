"""Collect completed two-rank JACCL operations during a model forward pass."""

from contextlib import contextmanager
from hashlib import sha256


class JacclTransport:
    def __init__(self, core, rank):
        self.core = core
        self.group = core.distributed.init(backend="jaccl", strict=True)
        if self.group.size() != 2 or self.group.rank() != rank:
            raise ValueError("JACCL group does not match the assigned rank")
        self.operations = 0
        self.input_bytes = 0
        self.sequence = sha256()

    @contextmanager
    def observe_forward_passes(self):
        """Observe this process's tensor-parallel all-reduces, excluding initialization."""
        core = self.core
        original = core.distributed.all_sum

        def observed(array, *, group=None, stream=None):
            if group is not self.group:
                raise ValueError("Unapproved collective group during inference")
            result = original(array, group=group, stream=stream)
            # MLX is lazy. Returning an unevaluated result would count a call
            # whose payload might never reach the peer or might fail later.
            core.eval(result)
            if array.nbytes:
                self.sequence.update(array.nbytes.to_bytes(8, "big"))
                self.operations += 1
                self.input_bytes += array.nbytes
            return result

        core.distributed.all_sum = observed
        try:
            yield
        finally:
            core.distributed.all_sum = original

    def evidence(self, *, attempt, candidate, device):
        if not self.operations:
            raise ValueError("No completed JACCL model traffic")
        # A two-member all-reduce exchanges payload in both directions.
        # The ordered sizes match across ranks without exposing model data.
        transfer_id = self.sequence.hexdigest()[:40]
        return dict(attempt=attempt, candidate=candidate, device=device, transfers=[
            dict(id=transfer_id, direction=direction, transport="rdma", count=self.operations)
            for direction in ("send", "receive")
        ])
