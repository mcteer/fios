"""Exercise native process fencing using a disposable, harmless child."""

from hashlib import file_digest
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from agent.native_runtime import NativeRuntime
from backend.enrollment import Rejected


class NativeRuntimeTests(unittest.TestCase):
    def test_only_child_owner_can_certify_runtime_cleanup(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            path = directory / "runtime.json"
            with Path(sys.executable).open("rb") as stream:
                fingerprint = file_digest(stream, "sha256").hexdigest()
            path.touch(mode=0o600)
            path.write_text(json.dumps({
                "revision": "a"*64, "model": str(directory), "engine": sys.executable,
                "executable_sha256": fingerprint, "entry": "mlx_lm.server", "port": 8765,
            }))
            first = NativeRuntime(path, directory)
            replacement = NativeRuntime(path, directory)
            first.descriptor = first.acquire_executor()
            try:
                first.process = subprocess.Popen(
                    [sys.executable, "-B", "-c", "import time; time.sleep(30)"],
                    pass_fds=(first.descriptor,), start_new_session=True)
            except BaseException:
                import os
                os.close(first.descriptor)
                raise
            try:
                self.assertFalse(replacement.quiescent())
                with self.assertRaisesRegex(Rejected, "profile_changed"):
                    first.generate("b"*64, [], 128, 32, 1)
            finally:
                first.stop()
            self.assertTrue(first.quiescent())
            self.assertTrue(replacement.quiescent())

    def test_pinned_model_checks_full_file_set_and_digest(self):
        from hashlib import sha256
        from agent.native_runtime import verify_model_manifest

        with tempfile.TemporaryDirectory() as tmp:
            model = Path(tmp)
            files = {"config.json": b"{}", "model.safetensors": b"fixture weights"}
            for name, content in files.items():
                (model / name).write_bytes(content)
            manifest = {name: sha256(content).hexdigest() for name, content in files.items()}
            verify_model_manifest(model, manifest)
            (model / "model.safetensors").write_bytes(b"corrupted weights")
            with self.assertRaisesRegex(ValueError, "digest changed"):
                verify_model_manifest(model, manifest)
            (model / "extra.safetensors").write_bytes(b"unreviewed extra shard")
            with self.assertRaisesRegex(ValueError, "does not match"):
                verify_model_manifest(model, manifest)

    def test_stop_before_model_entry_cannot_be_cleared_by_generate(self):
        from threading import Event

        runtime = NativeRuntime.__new__(NativeRuntime)
        runtime.revision = "a"*64
        runtime.limits = (128, 32)
        runtime.interrupted = Event()
        runtime.interrupted.set()
        with self.assertRaisesRegex(Rejected, "profile_changed"):
            runtime.generate(runtime.revision, [], 128, 64, 1)
        with self.assertRaisesRegex(Rejected, "fenced"):
            runtime.generate(runtime.revision, [], 128, 32, 1)

    def test_hard_parent_loss_releases_executor_lock(self):
        import fcntl
        import os
        import signal
        import time

        with tempfile.TemporaryDirectory() as tmp:
            lock = Path(tmp) / "runtime.lock"
            lock.touch(mode=0o600)
            owner_code = """
import fcntl, os, subprocess, sys, time
fd=os.open(sys.argv[1],os.O_RDWR)
fcntl.flock(fd,fcntl.LOCK_EX)
child_code=('import os,sys,time; from agent.native_executor import watch_parent; '
            'watch_parent(int(sys.argv[1])); print("ready",flush=True); time.sleep(30)')
child=subprocess.Popen([sys.executable,'-B','-c',child_code,str(os.getpid())],
                       stdout=subprocess.PIPE, pass_fds=(fd,), start_new_session=True)
assert child.stdout.readline() == b"ready\\n"
print(child.pid,flush=True)
time.sleep(30)
"""
            owner = subprocess.Popen([sys.executable, "-B", "-c", owner_code, str(lock)],
                                     stdout=subprocess.PIPE, text=True)
            child_pid = None
            try:
                child_pid = int(owner.stdout.readline())
                owner.kill()
                owner.wait(timeout=3)
                deadline = time.monotonic() + 4
                while time.monotonic() < deadline:
                    with lock.open("r+") as stream:
                        try:
                            fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                        except BlockingIOError:
                            pass
                        else:
                            child_pid = None
                            return
                    time.sleep(0.05)
                self.fail("Orphaned native process retained the executor lock")
            finally:
                owner.stdout.close()
                if owner.poll() is None:
                    owner.kill()
                    owner.wait(timeout=3)
                if child_pid is not None:
                    try:
                        os.killpg(child_pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_package_drift_invalidates_environment_with_same_interpreter(self):
        from agent.native_runtime import digest_file, verify_environment

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            packages = root / "lib/python3.15/site-packages"
            packages.mkdir(parents=True)
            package = packages / "mlx_example.py"
            package.write_text("VERSION = 1\n")
            manifest = root / "lock.json"
            manifest.touch(mode=0o600)
            manifest.write_text(json.dumps({package.name: digest_file(package)}))
            engine = root / "bin/python"
            self.assertEqual(len(verify_environment(engine, manifest, "mlx_lm.server", "a"*64)), 64)
            package.write_text("VERSION = 2\n")
            with self.assertRaisesRegex(ValueError, "environment digest changed"):
                verify_environment(engine, manifest, "mlx_lm.server", "a"*64)

    def test_running_owner_rejects_changes_to_a_previously_verified_deployment(self):
        from agent.native_runtime import deployment_stamp

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            root.joinpath("lib/python3.15/site-packages").mkdir(parents=True)
            engine = root / "python"
            engine.write_bytes(b"native executable")
            # The stamped interpreter path has the same layout as a venv.
            engine.parent.joinpath("bin").mkdir()
            engine = engine.rename(root / "bin/python")
            model = root / "model"
            model.mkdir()
            config = model / "config.json"
            config.write_text("{}")
            runtime = NativeRuntime.__new__(NativeRuntime)
            runtime.engine, runtime.model = engine, model
            runtime.verified_deployment = deployment_stamp(engine, model)
            config.write_text('{"changed":true}')
            with self.assertRaisesRegex(Rejected, "profile_changed"):
                runtime.launch()


class PairedWorkerBarrierTests(unittest.TestCase):
    def test_prepared_rank_starts_when_peer_arrives_on_later_poll(self):
        from agent.inference_worker import InferenceWorker

        fields = dict(job="job", generation=1, epoch="epoch", grant="grant", remaining=15)
        prepare = dict(action="prepare", **fields)
        start = dict(action="start", **fields)
        offers = iter((prepare, prepare, start, start))
        runs = []

        class Worker(InferenceWorker):
            def execute(self, offer, grant):
                runs.append((offer["job"], grant["generation"]))

        def control(operation, _data):
            if operation == "poll":
                return next(offers)

        worker = Worker(control, None, lambda _: {}, object())
        worker.step()
        self.assertEqual(runs, [])
        worker.step()
        worker.step()
        self.assertEqual(runs, [("job", 1)])

    def test_worker_does_not_start_an_assignment_prepared_by_prior_process(self):
        from agent.inference_worker import InferenceWorker

        start = dict(action="start", job="job", generation=1, epoch="epoch",
                     grant="grant", remaining=15)

        class Worker(InferenceWorker):
            def execute(self, _offer, _grant):
                self.fail_start()

        worker = Worker(lambda action, _: start if action == "poll" else {}, None, lambda _: {}, None)
        worker.fail_start = lambda: self.fail("unprepared grant started")
        worker.step()

    def test_running_trial_stops_its_child_when_link_monitor_reports_down(self):
        from threading import Event
        from agent.inference_worker import InferenceWorker

        fields = dict(job="job", generation=1, epoch="epoch", grant="grant", remaining=15)
        offers = iter((dict(action="prepare", trial={}, **fields),
                       dict(action="start", trial={}, **fields)))
        stopped = Event()
        receipts = []

        class Runtime:
            def check_budget(self):
                pass

            def prepare(self, _offer):
                pass

            def run_trial(self, _offer, _deadline):
                if not stopped.wait(timeout=5):
                    raise AssertionError("Native process was left running")
                return {}

            def check_link(self):
                raise Rejected("transport_unavailable", 409)

            def stop(self):
                stopped.set()

        def control(operation, data):
            if operation == "poll":
                return next(offers)
            if operation == "finish":
                receipts.append(data)

        worker = InferenceWorker(control, None, lambda _: {}, None, paired_runtime=Runtime())
        worker.step()
        self.assertTrue(stopped.is_set())
        self.assertEqual(receipts, [dict(job="job", generation=1, epoch="epoch", grant="grant",
                                         result="failed", failure="transport_unavailable")])
