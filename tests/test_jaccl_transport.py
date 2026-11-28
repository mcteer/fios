from types import SimpleNamespace
import unittest

from agent.jaccl_transport import JacclTransport
from backend.pair_trial import paired_rdma, transport_observation


class JacclTransportTests(unittest.TestCase):
    def core(self, rank):
        group = SimpleNamespace(rank=lambda: rank, size=lambda: 2)
        output = object()
        evaluated = []

        def init(**kwargs):
            self.assertEqual(kwargs, dict(backend="jaccl", strict=True))
            return group

        def reduce(_array, **kwargs):
            self.assertIs(kwargs["group"], group)
            self.assertIs(kwargs["stream"], None)
            return output

        core = SimpleNamespace(distributed=SimpleNamespace(init=init, all_sum=reduce),
                               eval=evaluated.append)
        return core, group, evaluated, output

    def observation(self, rank, sizes):
        core, group, evaluated, output = self.core(rank)
        original = core.distributed.all_sum
        observer = JacclTransport(core, rank)
        with observer.observe_forward_passes():
            for size in sizes:
                self.assertIs(core.distributed.all_sum(SimpleNamespace(nbytes=size), group=group), output)
        self.assertEqual(evaluated, [output] * len(sizes))
        self.assertIs(core.distributed.all_sum, original)
        identity = dict(attempt="one", candidate="a" * 64, device=str(rank) * 64)
        return transport_observation(observer.evidence(**identity), **identity)

    def test_only_matching_evaluated_payloads_pass(self):
        left = self.observation(0, [0, 16, 32])
        self.assertTrue(paired_rdma(left, self.observation(1, [16, 32])))
        self.assertFalse(paired_rdma(left, self.observation(1, [32, 16])))

    def test_unapproved_group_or_failed_evaluation_produces_no_evidence(self):
        core, group, _, _ = self.core(0)
        observer = JacclTransport(core, 0)
        array = SimpleNamespace(nbytes=16)
        with observer.observe_forward_passes(), self.assertRaisesRegex(ValueError, "Unapproved"):
            core.distributed.all_sum(array, group=object())

        def fail(_result):
            raise RuntimeError("Link down")

        core.eval = fail
        with observer.observe_forward_passes(), self.assertRaisesRegex(RuntimeError, "Link down"):
            core.distributed.all_sum(array, group=group)
        self.assertEqual(observer.operations, 0)
        with self.assertRaisesRegex(ValueError, "No completed"):
            observer.evidence(attempt="one", candidate="a" * 64, device="b" * 64)
